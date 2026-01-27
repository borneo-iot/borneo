
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>

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

#include <network_provisioning/manager.h>
#include <network_provisioning/scheme_ble.h>
#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/wifi.h>

#include "np.h"

#if CONFIG_BORNEO_PROV_METHOD_NP

#define TAG "network-prov"
#define SSID_PREFIX "BOPROV_"
#define PROV_BINDING_ENDPOINT "binding"

// 7b76e0cd-0d0c-4be2-9bea-c5ed333382b7

/* LSB <------------------------------------------------------------------------------> MSB */
#define BINDING_SERVICE_UUID                                                                                           \
    {                                                                                                                  \
        0xcd, 0xe0, 0x76, 0x7b, 0x0c, 0x0d, 0xe2, 0x4b, 0x9b, 0xea, 0xc5, 0xed, 0x33, 0x33, 0x82, 0xb7,                \
    }

typedef struct {
    char service_name[16];
} np_context_t;

static void get_device_service_name(char* service_name, size_t max);
esp_err_t prov_binding_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
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

    BO_TRY_ESP(network_prov_mgr_endpoint_create(PROV_BINDING_ENDPOINT));
    BO_TRY_ESP(network_prov_mgr_start_provisioning(security, sec_params, s_np_ctx->service_name, service_key));
    network_prov_mgr_endpoint_register(PROV_BINDING_ENDPOINT, prov_binding_data_handler, NULL);

    return 0;
}

static void get_device_service_name(char* service_name, size_t max)
{
    uint8_t eth_mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, eth_mac);
    snprintf(service_name, max, "%s%02X%02X%02X", SSID_PREFIX, eth_mac[3], eth_mac[4], eth_mac[5]);
}

esp_err_t prov_binding_data_handler(uint32_t session_id, const uint8_t* inbuf, ssize_t inlen, uint8_t** outbuf,
                                    ssize_t* outlen, void* priv_data)
{
    if (inbuf) {
        ESP_LOGI(TAG, "Received data: %.*s", inlen, (char*)inbuf);
    }
    char response[] = "SUCCESS";
    *outbuf = (uint8_t*)strdup(response);
    if (*outbuf == NULL) {
        ESP_LOGE(TAG, "System out of memory");
        return ESP_ERR_NO_MEM;
    }
    *outlen = strlen(response) + 1; /* +1 for NULL terminating byte */

    return ESP_OK;
}

#endif // CONFIG_BORNEO_PROV_METHOD_NP