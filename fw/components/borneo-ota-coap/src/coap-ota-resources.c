#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <memory.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_mac.h>
#include <nvs_flash.h>
#include <esp_ota_ops.h>
#include <esp_flash_partitions.h>
#include <esp_partition.h>

#include <sys/socket.h>

#include <freertos/FreeRTOS.h>
#include <freertos/portmacro.h>

#include <coap3/coap.h>
#include <cbor.h>

#include <borneo/rtc.h>
#include <borneo/common.h>
#include <borneo/coap.h>
#include <borneo/wifi.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>

#if CONFIG_BORNEO_EDITION_CE

#define TAG "ota.coap"

#define OTA_COAP_UPDATE_TIMEOUT 5000
#define COAP_MAX_BLOCK_SIZE 512

struct ota_state {
    portMUX_TYPE lock;
    esp_ota_handle_t update_handle;
    bool update_in_progress;
    size_t total_bytes_received;
    TickType_t last_block_time;
    size_t last_block_num;
    uint32_t last_processed_block_num;
};

static struct ota_state s_ota_state = {
    .lock = portMUX_INITIALIZER_UNLOCKED,
    .update_handle = 0,
    .update_in_progress = false,
    .total_bytes_received = 0,
    .last_block_time = 0,
    .last_block_num = 0,
    .last_processed_block_num = UINT32_MAX,
};

static void ota_reset_state(bool abort_update)
{
    esp_ota_handle_t update_handle = 0;

    portENTER_CRITICAL(&s_ota_state.lock);
    update_handle = s_ota_state.update_handle;
    s_ota_state.update_handle = 0;
    s_ota_state.update_in_progress = false;
    s_ota_state.total_bytes_received = 0;
    s_ota_state.last_block_time = 0;
    s_ota_state.last_block_num = 0;
    s_ota_state.last_processed_block_num = UINT32_MAX;
    portEXIT_CRITICAL(&s_ota_state.lock);

    if (abort_update && update_handle != 0) {
        esp_ota_abort(update_handle);
    }
}

/**
 * @brief Build status response in CBOR format
 * @param buffer Output buffer for CBOR data
 * @param buffer_size Size of output buffer
 * @return Length of generated CBOR data
 */
static size_t build_status_response(uint8_t* buffer, size_t buffer_size)
{
    portENTER_CRITICAL(&s_ota_state.lock);
    bool update_in_progress = s_ota_state.update_in_progress;
    size_t total_bytes_received = s_ota_state.total_bytes_received;
    portEXIT_CRITICAL(&s_ota_state.lock);

    CborEncoder encoder, map_encoder;
    cbor_encoder_init(&encoder, buffer, buffer_size, 0);

    cbor_encoder_create_map(&encoder, &map_encoder, CborIndefiniteLength);

    // Current running partition info
    const esp_partition_t* running = esp_ota_get_running_partition();
    cbor_encode_text_stringz(&map_encoder, "running_partition");
    cbor_encode_text_stringz(&map_encoder, running->label);

    // Update status
    cbor_encode_text_stringz(&map_encoder, "update_status");
    cbor_encode_text_stringz(&map_encoder, update_in_progress ? "in_progress" : "idle");

    // Bytes received
    cbor_encode_text_stringz(&map_encoder, "bytes_received");
    cbor_encode_uint(&map_encoder, total_bytes_received);

    // OTA partition info
    cbor_encode_text_stringz(&map_encoder, "ota_partitions");
    CborEncoder array_encoder;
    cbor_encoder_create_array(&map_encoder, &array_encoder, 2);

    const esp_partition_t* part = esp_ota_get_running_partition();
    cbor_encode_text_stringz(&array_encoder, part->label);

    part = esp_ota_get_next_update_partition(NULL);
    cbor_encode_text_stringz(&array_encoder, part ? part->label : "none");

    cbor_encoder_close_container(&map_encoder, &array_encoder);
    cbor_encoder_close_container(&encoder, &map_encoder);

    return cbor_encoder_get_buffer_size(&encoder, buffer);
}

/**
 * @brief Handler for firmware status query
 * @param resource CoAP resource
 * @param session CoAP session
 * @param request CoAP request PDU
 * @param query Query string
 * @param response CoAP response PDU
 */
static void coap_hnd_status_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                const coap_string_t* query, coap_pdu_t* response)
{
    uint8_t cbor_buffer[256];
    size_t cbor_len = build_status_response(cbor_buffer, sizeof(cbor_buffer));

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, cbor_len, cbor_buffer);
}

/**
 * @brief Handler for firmware update
 * @param resource CoAP resource
 * @param session CoAP session
 * @param request CoAP request PDU
 * @param query Query string
 * @param response CoAP response PDU
 */
static void coap_hnd_download(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                              const coap_string_t* query, coap_pdu_t* response)
{
    const uint8_t* data = NULL;
    size_t data_len = 0;
    coap_opt_iterator_t opt_iter;
    coap_opt_t* block_opt;
    uint32_t block_val = 0;
    uint32_t block_num = 0;
    int block_m = 0;
    size_t block_size = 0;
    coap_pdu_code_t err_code = COAP_RESPONSE_CODE_INTERNAL_ERROR;

    // Get block transfer option
    block_opt = coap_check_option(request, COAP_OPTION_BLOCK1, &opt_iter);
    if (block_opt) {
        const uint8_t* opt_data = coap_opt_value(block_opt);
        size_t opt_len = coap_opt_length(block_opt);
        block_val = coap_decode_var_bytes(opt_data, opt_len);
        block_num = (block_val >> 4);
        block_m = (block_val >> 3) & 0x1;
        block_size = 1 << ((block_val & 0x7) + 4);
        if (block_size > COAP_MAX_BLOCK_SIZE) {
            ESP_LOGE(TAG, "Block size too large, maximum supported is %d bytes", COAP_MAX_BLOCK_SIZE);
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_REQUEST_TOO_LARGE);
            return;
        }
    }

    if (block_num % 64 == 0) {
        ESP_LOGI(TAG, "Received block %lu", block_num);
    }

    // Get request data
    bool has_data = coap_get_data(request, &data_len, &data);

    // Handle PUT request (firmware upload)
    coap_pdu_code_t method = coap_pdu_get_code(request);
    if (method == COAP_REQUEST_CODE_PUT) {
        // If first block, initialize OTA
        portENTER_CRITICAL(&s_ota_state.lock);
        bool update_in_progress = s_ota_state.update_in_progress;
        uint32_t last_processed_block_num = s_ota_state.last_processed_block_num;
        size_t last_block_num = s_ota_state.last_block_num;
        TickType_t last_block_time = s_ota_state.last_block_time;
        esp_ota_handle_t update_handle = s_ota_state.update_handle;
        portEXIT_CRITICAL(&s_ota_state.lock);

        // Check for duplicate block before any session restart logic.
        if (block_num == last_processed_block_num) {
            ESP_LOGW(TAG, "Received duplicate block number %lu, ignoring", block_num);
            if (block_opt) {
                uint8_t buf[4];
                size_t len = coap_encode_var_safe(buf, sizeof(buf), block_val);
                coap_add_option(response, COAP_OPTION_BLOCK1, len, buf);
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTINUE);
            }
            else {
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_CREATED);
            }
            return;
        }

        if (block_num == 0) {
            if (update_in_progress) {
                ESP_LOGW(TAG, "Received block 0 during OTA, restarting session");
                ota_reset_state(true);
                update_in_progress = false;
                update_handle = 0;
            }

            if (!update_in_progress) {
                ESP_LOGI(TAG, "Starting new OTA download...");

                const esp_partition_t* update_partition = esp_ota_get_next_update_partition(NULL);
                if (update_partition == NULL) {
                    ESP_LOGE(TAG, "No OTA update partition found");
                    coap_pdu_set_code(response, COAP_RESPONSE_CODE_INTERNAL_ERROR);
                    return;
                }

                update_handle = 0;
                esp_err_t err = esp_ota_begin(update_partition, OTA_SIZE_UNKNOWN, &update_handle);
                if (err != ESP_OK) {
                    ESP_LOGE(TAG, "OTA begin failed: %s", esp_err_to_name(err));
                    coap_pdu_set_code(response, COAP_RESPONSE_CODE_INTERNAL_ERROR);
                    return;
                }

                portENTER_CRITICAL(&s_ota_state.lock);
                s_ota_state.update_handle = update_handle;
                s_ota_state.update_in_progress = true;
                s_ota_state.total_bytes_received = 0;
                s_ota_state.last_block_time = xTaskGetTickCount();
                s_ota_state.last_block_num = 0;
                s_ota_state.last_processed_block_num = UINT32_MAX;
                portEXIT_CRITICAL(&s_ota_state.lock);
            }
        }

        // Check block number continuity
        if (block_num > 0 && block_num != last_block_num + 1) {
            ESP_LOGE(TAG, "Non-sequential block number: expected=%zu, received=%lu", last_block_num + 1, block_num);
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_BAD_REQUEST);
            return;
        }

        // Check timeout
        if (block_num > 0 && (xTaskGetTickCount() - last_block_time) > pdMS_TO_TICKS(OTA_COAP_UPDATE_TIMEOUT)) {
            ESP_LOGE(TAG, "Block transfer timeout, aborting OTA");
            err_code = COAP_RESPONSE_CODE_GATEWAY_TIMEOUT;
            goto put_abort_err;
        }

        // Write OTA data
        if (has_data && data_len > 0) {
            // Validate block size
            if (block_opt && data_len != block_size && block_m) {
                ESP_LOGE(TAG, "Block data length %zu doesn't match Block1 option size %zu", data_len, block_size);
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_BAD_REQUEST);
                return;
            }

            if (data_len > COAP_MAX_BLOCK_SIZE) {
                ESP_LOGE(TAG, "Data length exceeds buffer limit");
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_REQUEST_TOO_LARGE);
                return;
            }

            esp_err_t err = esp_ota_write(update_handle, data, data_len);
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "OTA write failed: %s (write_len=%zu, total_received=%zu, block=%lu)",
                         esp_err_to_name(err), data_len, s_ota_state.total_bytes_received, block_num);
                err_code = COAP_RESPONSE_CODE_INTERNAL_ERROR;
                goto put_abort_err;
            }

            portENTER_CRITICAL(&s_ota_state.lock);
            s_ota_state.total_bytes_received += data_len;
            s_ota_state.last_block_time = xTaskGetTickCount();
            s_ota_state.last_block_num = block_num;
            s_ota_state.last_processed_block_num = block_num;
            portEXIT_CRITICAL(&s_ota_state.lock);
        }

        // Set block transfer response
        if (block_opt) {
            uint8_t buf[4];
            size_t len = coap_encode_var_safe(buf, sizeof(buf), block_val);
            coap_add_option(response, COAP_OPTION_BLOCK1, len, buf);

            if (block_m) {
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTINUE);
            }
            else {
                ESP_LOGI(TAG, "All firmware blocks received, total size %zu bytes", s_ota_state.total_bytes_received);
                coap_pdu_set_code(response, COAP_RESPONSE_CODE_CREATED);
            }
        }
        else {
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_CREATED);
        }
        return;

    put_abort_err:
        ota_reset_state(true);
        coap_pdu_set_code(response, err_code);
        return;
    }
    // Handle POST request (complete update)
    else if (method == COAP_REQUEST_CODE_POST) {
        portENTER_CRITICAL(&s_ota_state.lock);
        bool update_in_progress = s_ota_state.update_in_progress;
        portEXIT_CRITICAL(&s_ota_state.lock);

        if (!update_in_progress) {
            ESP_LOGE(TAG, "No OTA update in progress");
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_BAD_REQUEST);
            return;
        }

        ESP_LOGI(TAG, "Completing OTA update...");

        // Finalize OTA update
        esp_err_t err = esp_ota_end(s_ota_state.update_handle);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "OTA end failed: %s", esp_err_to_name(err));
            err_code = COAP_RESPONSE_CODE_INTERNAL_ERROR;
            goto post_err;
        }

        const esp_partition_t* update_partition = esp_ota_get_next_update_partition(NULL);

        uint8_t sha_256[32] = { 0 };
        esp_err_t ret = esp_partition_get_sha256(update_partition, sha_256);
        if (ret) {
            ESP_LOGE(TAG, "OTA get partition SHA256 failed: %s", esp_err_to_name(ret));
            err_code = COAP_RESPONSE_CODE_INTERNAL_ERROR;
            goto post_err;
        }

        // Verify signature (only for first block)
        /*
        if (block_num == 0 && has_data && !verify_firmware_signature(data, data_len)) {
            ESP_LOGE(TAG, "Firmware signature verification failed");
            esp_ota_abort(update_handle);
            update_in_progress = false;
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_UNAUTHORIZED);
            return;
        }
        */

        err = esp_ota_set_boot_partition(update_partition);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Set boot partition failed: %s", esp_err_to_name(err));
            err_code = COAP_RESPONSE_CODE_INTERNAL_ERROR;
            goto post_err;
        }

        ota_reset_state(false);

        // Prepare response
        uint8_t cbor_buffer[128];
        CborEncoder encoder, map_encoder;
        cbor_encoder_init(&encoder, cbor_buffer, sizeof(cbor_buffer), 0);
        cbor_encoder_create_map(&encoder, &map_encoder, 2);

        cbor_encode_text_stringz(&map_encoder, "status");
        cbor_encode_text_stringz(&map_encoder, "success");

        cbor_encode_text_stringz(&map_encoder, "next_boot");
        cbor_encode_text_stringz(&map_encoder, update_partition->label);

        cbor_encoder_close_container(&encoder, &map_encoder);

        size_t cbor_len = cbor_encoder_get_buffer_size(&encoder, cbor_buffer);
        if (cbor_len == 0 || cbor_len >= sizeof(cbor_buffer)) {
            ESP_LOGE(TAG, "CBOR encoding failed or buffer overflow");
            coap_pdu_set_code(response, COAP_RESPONSE_CODE_INTERNAL_ERROR);
            return;
        }

        coap_add_data(response, cbor_len, cbor_buffer);
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_CHANGED);

        ESP_LOGI(TAG, "OTA update successful, preparing to reboot...");

        // Delay reboot to allow response to be sent
        bo_system_reboot_later(5000);

        coap_pdu_set_code(response, COAP_RESPONSE_CODE_CREATED);
        return;

    post_err:
        ota_reset_state(false);
        coap_pdu_set_code(response, err_code);
        return;
    }
    else {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_NOT_ALLOWED);
    }
}

COAP_RESOURCE_DEFINE("borneo/v1/ota/coap/status", false, coap_hnd_status_get, NULL, NULL, NULL);
COAP_RESOURCE_DEFINE("borneo/v1/ota/coap/download", false, NULL, coap_hnd_download, coap_hnd_download, NULL);

#endif // CONFIG_BORNEO_EDITION_CE