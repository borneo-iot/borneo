
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <inttypes.h>

#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include <esp_event.h>
#include <esp_log.h>
#include <esp_smartconfig.h>
#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_netif.h>
#include <nvs_flash.h>

#include <cbor.h>

#include <network_provisioning/manager.h>
#include <network_provisioning/scheme_ble.h>
#include <borneo/common.h>
#include <borneo/rpc/common.h>
#include <borneo/system.h>
#include <borneo/wifi.h>

#include "np.h"

#if CONFIG_BORNEO_PROV_METHOD_NP

#define TAG "network-prov"
#define SSID_PREFIX "BOPROV_"

enum {
    BO_PROV_METHOD_GET_DEVICE_INFO = 1,
};

typedef struct {
    char service_name[16];
} np_context_t;

static np_context_t* s_np_ctx = NULL;

static void get_device_service_name(char* service_name, size_t max);
static esp_err_t cbor_prov_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
                                        ssize_t* outlen, void* priv_data);

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
    network_prov_security_t security = NETWORK_PROV_SECURITY_1;
    const void* sec_params = NULL;
    const char* service_key = NULL;
    BO_TRY_ESP(network_prov_mgr_endpoint_create("cbor"));
    BO_TRY_ESP(network_prov_mgr_start_provisioning(security, sec_params, s_np_ctx->service_name, service_key));
    BO_TRY_ESP(network_prov_mgr_endpoint_register("cbor", cbor_prov_data_handler, NULL));

    return 0;
}

static void get_device_service_name(char* service_name, size_t max)
{
    uint8_t eth_mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, eth_mac);
    snprintf(service_name, max, "%s%02X%02X%02X", SSID_PREFIX, eth_mac[3], eth_mac[4], eth_mac[5]);
}

static void send_error_response(uint8_t* buf, size_t buf_size, uint32_t req_id, uint8_t** outbuf, ssize_t* outlen)
{
    CborEncoder encoder, root_map;
    cbor_encoder_init(&encoder, buf, buf_size, 0);
    cbor_encoder_create_map(&encoder, &root_map, CborIndefiniteLength);
    cbor_encode_text_stringz(&root_map, "v");
    cbor_encode_int(&root_map, 1);
    cbor_encode_text_stringz(&root_map, "id");
    cbor_encode_uint(&root_map, req_id);
    cbor_encode_text_stringz(&root_map, "e");
    cbor_encode_int(&root_map, -1);
    cbor_encode_text_stringz(&root_map, "r");
    cbor_encode_null(&root_map);
    cbor_encoder_close_container(&encoder, &root_map);
    *outbuf = buf;
    *outlen = (ssize_t)cbor_encoder_get_buffer_size(&encoder, buf);
}

esp_err_t cbor_prov_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
                                 ssize_t* outlen, void* priv_data)
{
    /* BLE/protocomm assumes the response buffer is heap-allocated and will
       call free() on it once the data has been sent.  Allocate here and
       transfer ownership to the transport. */
    const size_t resp_buf_size = 1024;
    uint8_t* resp_buf = malloc(resp_buf_size);
    if (resp_buf == NULL) {
        ESP_LOGE(TAG, "RPC: failed to allocate response buffer");
        *outbuf = NULL;
        *outlen = 0;
        return ESP_ERR_NO_MEM;
    }

    if (!inbuf || inlen <= 0) {
        ESP_LOGE(TAG, "RPC: empty request");
        send_error_response(resp_buf, resp_buf_size, 0, outbuf, outlen);
        return ESP_OK;
    }

    /* Parse request */
    CborParser parser;
    CborValue it;
    if (cbor_parser_init(inbuf, (size_t)inlen, 0, &parser, &it) != CborNoError || !cbor_value_is_map(&it)) {
        ESP_LOGE(TAG, "RPC: malformed CBOR request");
        send_error_response(resp_buf, resp_buf_size, 0, outbuf, outlen);
        return ESP_OK;
    }

    /* Extract 'v' (protocol version) */
    CborValue field;
    int version = 0;
    if (cbor_value_map_find_value(&it, "v", &field) != CborNoError || !cbor_value_is_integer(&field)
        || cbor_value_get_int(&field, &version) != CborNoError || version != 1) {
        ESP_LOGE(TAG, "RPC: bad or missing version");
        send_error_response(resp_buf, resp_buf_size, 0, outbuf, outlen);
        return ESP_OK;
    }

    /* Extract 'id' (request id) */
    uint32_t req_id = 0;
    uint64_t req_id_raw = 0;
    if (cbor_value_map_find_value(&it, "id", &field) == CborNoError && cbor_value_is_unsigned_integer(&field)) {
        cbor_value_get_uint64(&field, &req_id_raw);
        req_id = (uint32_t)req_id_raw;
    }

    /* Extract 'm' (method) */
    int method = 0;
    if (cbor_value_map_find_value(&it, "m", &field) != CborNoError || !cbor_value_is_integer(&field)
        || cbor_value_get_int(&field, &method) != CborNoError) {
        ESP_LOGE(TAG, "RPC: missing method");
        send_error_response(resp_buf, resp_buf_size, req_id, outbuf, outlen);
        return ESP_OK;
    }

    ESP_LOGI(TAG, "RPC: method=%d id=%" PRIu32, method, req_id);

    /* Encode response envelope */
    CborEncoder encoder, root_map;
    cbor_encoder_init(&encoder, resp_buf, resp_buf_size, 0);
    BO_TRY(cbor_encoder_create_map(&encoder, &root_map, CborIndefiniteLength));
    BO_TRY(cbor_encode_text_stringz(&root_map, "v"));
    BO_TRY(cbor_encode_int(&root_map, 1));
    BO_TRY(cbor_encode_text_stringz(&root_map, "id"));
    BO_TRY(cbor_encode_uint(&root_map, req_id));

    /* Dispatch */
    int32_t err_code = 0;
    BO_TRY(cbor_encode_text_stringz(&root_map, "r"));
    switch (method) {
    case BO_PROV_METHOD_GET_DEVICE_INFO: {
        int rc = bo_rpc_borneo_info_get(NULL, &root_map);
        err_code = (rc != 0) ? -1 : 0;
        break;
    }
    default:
        ESP_LOGW(TAG, "RPC: unknown method %d", method);
        BO_TRY(cbor_encode_null(&root_map));
        err_code = -1;
        break;
    }

    BO_TRY(cbor_encode_text_stringz(&root_map, "e"));
    BO_TRY(cbor_encode_int(&root_map, err_code));
    BO_TRY(cbor_encoder_close_container(&encoder, &root_map));

    *outbuf = resp_buf;
    *outlen = (ssize_t)cbor_encoder_get_buffer_size(&encoder, resp_buf);

    return ESP_OK;
}

#endif // CONFIG_BORNEO_PROV_METHOD_NP