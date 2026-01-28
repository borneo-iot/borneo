
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>

#include <cbor.h>

#include <esp_event.h>
#include <esp_log.h>
#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_netif.h>
#include <nvs_flash.h>

#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include <network_provisioning/manager.h>
#include <network_provisioning/scheme_ble.h>
#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/wifi.h>
#include <borneo/auth.h>

#include "np.h"

#if CONFIG_BORNEO_PROV_METHOD_NP

#define TAG "network-prov"
#define SSID_PREFIX "BOPROV_"
#define PROV_PAIR_ENDPOINT "pair"

// 7b76e0cd-0d0c-4be2-9bea-c5ed333382b7

/* LSB <------------------------------------------------------------------------------> MSB */
#define PAIR_SERVICE_UUID                                                                                              \
    {                                                                                                                  \
        0xcd, 0xe0, 0x76, 0x7b, 0x0c, 0x0d, 0xe2, 0x4b, 0x9b, 0xea, 0xc5, 0xed, 0x33, 0x33, 0x82, 0xb7,                \
    }

typedef struct {
    char service_name[16];
} np_context_t;

static void get_device_service_name(char* service_name, size_t max);
esp_err_t prov_pair_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
                                 ssize_t* outlen, void* priv_data);

static np_context_t* s_np_ctx = NULL;

/* Event handler for NETWORK_PROV_EVENT */
static void network_prov_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case NETWORK_PROV_START: {
        ESP_LOGI(TAG, "Provisioning started");
        esp_event_post(BO_WIFI_EVENTS, BO_EVENT_WIFI_PROVISIONING_START, NULL, 0, portMAX_DELAY);
    } break;

    case NETWORK_PROV_WIFI_CRED_RECV: {
        wifi_sta_config_t* wifi_sta_cfg = (wifi_sta_config_t*)event_data;
        ESP_LOGI(TAG,
                 "Received Wi-Fi credentials"
                 "\n\tSSID     : %s\n\tPassword : %s",
                 (const char*)wifi_sta_cfg->ssid, (const char*)wifi_sta_cfg->password);
    } break;

    case NETWORK_PROV_WIFI_CRED_FAIL: {
        BO_MUST_ESP(network_prov_mgr_reset_wifi_sm_state_on_failure());
        ESP_LOGE(TAG, "Provisioning failed! Reseting the wifi provisioning...");
        esp_event_post(BO_WIFI_EVENTS, BO_EVENT_WIFI_PROVISIONING_FAIL, NULL, 0, portMAX_DELAY);
    } break;

    case NETWORK_PROV_WIFI_CRED_SUCCESS: {
        ESP_LOGI(TAG, "Provisioning successful");
        esp_event_post(BO_WIFI_EVENTS, BO_EVENT_WIFI_PROVISIONING_SUCCESS, NULL, 0, portMAX_DELAY);
    } break;

    case NETWORK_PROV_END: {
        /* De-initialize manager once provisioning is finished */
        ESP_LOGI(TAG, "Provisioning ended.");
        network_prov_mgr_deinit();
        BO_MUST_ESP(esp_event_handler_unregister(NETWORK_PROV_EVENT, ESP_EVENT_ANY_ID, &network_prov_event_handler));
        if (s_np_ctx != NULL) {
            free(s_np_ctx);
            s_np_ctx = NULL;
        }
        break;
    }

    default:
        break;
    }
}

int bo_wifi_np_init()
{
    ESP_LOGI(TAG, "Initializing provisioning");

    s_np_ctx = malloc(sizeof(np_context_t));
    if (!s_np_ctx) {
        ESP_LOGE(TAG, "Failed to allocate memory for np_context");
        return -ENOMEM;
    }
    memset(s_np_ctx, 0, sizeof(np_context_t));

    BO_TRY_ESP(esp_event_handler_register(NETWORK_PROV_EVENT, ESP_EVENT_ANY_ID, &network_prov_event_handler, NULL));

    network_prov_mgr_config_t config = {
        .scheme = network_prov_scheme_ble,
        .scheme_event_handler = NETWORK_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
    };

    BO_TRY_ESP(network_prov_mgr_init(config));

    get_device_service_name(s_np_ctx->service_name, sizeof(s_np_ctx->service_name));

    return 0;
}

int bo_wifi_np_start()
{
    /* Use security level 0 (no security, no POP) */
    network_prov_security_t security = NETWORK_PROV_SECURITY_0;
    const void* sec_params = NULL;
    const char* service_key = NULL;

    BO_TRY_ESP(network_prov_mgr_endpoint_create(PROV_PAIR_ENDPOINT));
    BO_TRY_ESP(network_prov_mgr_start_provisioning(security, sec_params, s_np_ctx->service_name, service_key));
    network_prov_mgr_endpoint_register(PROV_PAIR_ENDPOINT, prov_pair_data_handler, NULL);

    return 0;
}

static void get_device_service_name(char* service_name, size_t max)
{
    uint8_t eth_mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, eth_mac);
    snprintf(service_name, max, "%s%02X%02X%02X", SSID_PREFIX, eth_mac[3], eth_mac[4], eth_mac[5]);
}

esp_err_t prov_pair_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
                                 ssize_t* outlen, void* priv_data)
{
    esp_err_t ret = ESP_OK;

    if (!inbuf || inlen <= 0) {
        ESP_LOGW(TAG, "Invalid input buffer");
        ret = ESP_ERR_INVALID_ARG;
        goto error;
    }

    ESP_LOGI(TAG, "Received pairing data: %d bytes", inlen);

    // Parse CBOR data
    CborParser parser;
    CborValue root;
    CborError err = cbor_parser_init(inbuf, inlen, 0, &parser, &root);

    if (err != CborNoError) {
        ESP_LOGE(TAG, "CBOR parser init failed: %d", err);
        ret = ESP_ERR_INVALID_ARG;
        goto error;
    }

    if (!cbor_value_is_map(&root)) {
        ESP_LOGE(TAG, "Expected CBOR map");
        ret = ESP_ERR_INVALID_ARG;
        goto error;
    }

    CborValue it;
    cbor_value_enter_container(&root, &it);

    uint64_t timestamp = 0;
    uint8_t admin_token[16] = { 0 };
    uint8_t api_token[16] = { 0 };
    size_t admin_token_len = 0;
    size_t api_token_len = 0;

    // Parse the map entries
    while (!cbor_value_at_end(&it)) {
        // Get key
        if (!cbor_value_is_text_string(&it)) {
            ESP_LOGW(TAG, "Expected text string key");
            cbor_value_advance(&it);
            continue;
        }

        char key[32] = { 0 };
        size_t key_len = sizeof(key) - 1;
        cbor_value_copy_text_string(&it, key, &key_len, &it);
        key[key_len] = '\0';

        // Parse value based on key
        if (strcmp(key, "timestamp") == 0) {
            if (cbor_value_is_unsigned_integer(&it)) {
                cbor_value_get_uint64(&it, &timestamp);
                ESP_LOGI(TAG, "Timestamp: %llu", timestamp);
            }
            cbor_value_advance(&it);
        }
        else if (strcmp(key, "adminToken") == 0) {
            if (cbor_value_is_byte_string(&it)) {
                admin_token_len = sizeof(admin_token);
                cbor_value_copy_byte_string(&it, admin_token, &admin_token_len, &it);
                ESP_LOGI(TAG, "Admin token length: %u", admin_token_len);
            }
            else {
                cbor_value_advance(&it);
            }
        }
        else if (strcmp(key, "apiToken") == 0) {
            if (cbor_value_is_byte_string(&it)) {
                api_token_len = sizeof(api_token);
                cbor_value_copy_byte_string(&it, api_token, &api_token_len, &it);
                ESP_LOGI(TAG, "API token length: %u", api_token_len);
            }
            else {
                cbor_value_advance(&it);
            }
        }
        else {
            ESP_LOGW(TAG, "Unknown key: %s", key);
            cbor_value_advance(&it);
        }
    }

    cbor_value_leave_container(&root, &it);

    ret = bo_auth_pair(admin_token, admin_token_len, api_token, api_token_len, timestamp);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "bo_auth_pair failed: %s", esp_err_to_name(ret));
    }
    else {
        ESP_LOGI(TAG, "Pairing tokens saved successfully");
    }

error:
    // Prepare CBOR response
    uint8_t response_buf[256];
    CborEncoder encoder;
    cbor_encoder_init(&encoder, response_buf, sizeof(response_buf), 0);

    // Create response map
    CborEncoder map_encoder;
    cbor_encoder_create_map(&encoder, &map_encoder, CborIndefiniteLength);

    // Add error code (0 for success, non-zero for error)
    int error_code = (ret == ESP_OK) ? 0 : (int)ret;
    cbor_encode_text_stringz(&map_encoder, "code");
    cbor_encode_int(&map_encoder, error_code);

    // Add error message only if there's an error
    if (ret != ESP_OK) {
        cbor_encode_text_stringz(&map_encoder, "message");
        cbor_encode_text_stringz(&map_encoder, esp_err_to_name(ret));
    }

    cbor_encoder_close_container(&encoder, &map_encoder);

    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, response_buf);

    // Allocate and copy encoded response
    *outbuf = (uint8_t*)malloc(encoded_size);
    if (*outbuf == NULL) {
        ESP_LOGE(TAG, "System out of memory");
        return ESP_ERR_NO_MEM;
    }

    memcpy(*outbuf, response_buf, encoded_size);
    *outlen = encoded_size;

    return ESP_OK;
}

#endif // CONFIG_BORNEO_PROV_METHOD_NP