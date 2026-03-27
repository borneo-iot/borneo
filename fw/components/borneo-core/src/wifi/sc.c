#include <stdlib.h>
#include <string.h>

#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include <esp_event.h>
#include <esp_log.h>
#include <esp_smartconfig.h>
#include <esp_system.h>
#include <esp_wifi.h>
#include <nvs_flash.h>
#include <esp_netif.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/wifi.h>

#if CONFIG_BORNEO_PROV_METHOD_SC

#define TAG "smartconfig"

/* The event group allows multiple bits for each event,
   but we only care about one event - are we connected
   to the AP with an IP? */
#define CONNECTED_BIT BIT0
#define SC_DONE_BIT BIT1
#define RVD_MAX_LEN 33
#define TASK_PRIORITY 12

static void sc_task(void* parm);
static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);
static void sc_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);
static void ip_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);

/**
 * @brief Provisioning status
 */
enum {
    SC_STATE_STARTED,
    SC_STATE_CONNECTING,
    SC_STATE_DONE,
};

static EventGroupHandle_t _wifi_event_group;
static volatile int _sc_state = SC_STATE_STARTED;

static void sc_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    if (event_base != SC_EVENT) {
        return;
    }

    switch (event_id) {

    case SC_EVENT_SCAN_DONE: {
        ESP_LOGI(TAG, "Scan done");
    } break;

    case SC_EVENT_FOUND_CHANNEL: {
        ESP_LOGI(TAG, "Found channel");
    } break;

    case SC_EVENT_SEND_ACK_DONE: {
        xEventGroupSetBits(_wifi_event_group, SC_DONE_BIT);
    } break;

    case SC_EVENT_GOT_SSID_PSWD: {

        ESP_LOGI(TAG, "Got SSID and password");

        smartconfig_event_got_ssid_pswd_t* evt = (smartconfig_event_got_ssid_pswd_t*)event_data;
        wifi_config_t wifi_config = { 0 };
        uint8_t ssid[33] = { 0 };
        uint8_t password[65] = { 0 };

        memcpy(wifi_config.sta.ssid, evt->ssid, sizeof(wifi_config.sta.ssid));
        memcpy(wifi_config.sta.password, evt->password, sizeof(wifi_config.sta.password));
        wifi_config.sta.bssid_set = evt->bssid_set;
        if (wifi_config.sta.bssid_set) {
            memcpy(wifi_config.sta.bssid, evt->bssid, sizeof(wifi_config.sta.bssid));
        }

        memcpy(ssid, evt->ssid, sizeof(evt->ssid));
        memcpy(password, evt->password, sizeof(evt->password));
        ESP_LOGI(TAG, "SSID:%s", ssid);
        ESP_LOGI(TAG, "PASSWORD:%s", password);

        if (evt->type == SC_TYPE_ESPTOUCH_V2) {
            uint8_t rvd_data[RVD_MAX_LEN] = { 0 };
            BO_MUST(esp_smartconfig_get_rvd_data(rvd_data, sizeof(rvd_data)));
            /*
            ESP_LOGI(TAG, "Got `RVD_DATA`");
            for (int i = 0; i < 33; i++) {
                printf("%02x ", rvd_data[i]);
            }
            printf("\n");
            */
        }

        BO_MUST(esp_wifi_disconnect());
        BO_MUST(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
        _sc_state = SC_STATE_CONNECTING;
        BO_MUST(esp_wifi_connect());
    } break;

    default: {
        ESP_LOGI(TAG, "Unknown SmartConfig status");
    } break;

    } // switch
}

static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    if (event_base != WIFI_EVENT) {
        return;
    }

    switch (event_id) {

    case WIFI_EVENT_STA_DISCONNECTED: {
        EventBits_t ux_bits = xEventGroupGetBits(_wifi_event_group);
        if (ux_bits & CONNECTED_BIT) {
            ESP_LOGI(TAG, "WiFi disconnected. Clearing 'CONNECTED_BIT' bit.");
            xEventGroupClearBits(_wifi_event_group, CONNECTED_BIT);
        }
    } break;

    default:
        break;
    }
}

static void ip_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    if (event_base != IP_EVENT) {
        return;
    }

    switch (event_id) {
    case IP_EVENT_STA_GOT_IP: {
        xEventGroupSetBits(_wifi_event_group, CONNECTED_BIT);
    } break;

    default:
        break;
    }
}

static void sc_task(void* parm)
{
    ESP_LOGD(TAG, "Starting the SmartConfig task");
    BO_MUST(esp_smartconfig_set_type(SC_TYPE_ESPTOUCH_AIRKISS));
    smartconfig_start_config_t cfg = SMARTCONFIG_START_CONFIG_DEFAULT();
    BO_MUST(esp_smartconfig_start(&cfg));
    _sc_state = SC_STATE_STARTED;
    while (1) {

        EventBits_t ux_bits
            = xEventGroupWaitBits(_wifi_event_group, CONNECTED_BIT | SC_DONE_BIT, true, false, portMAX_DELAY);

        if (ux_bits & CONNECTED_BIT) {
            ESP_LOGI(TAG, "WiFi Connected to ap");
        }

        if (ux_bits & SC_DONE_BIT) {
            ESP_LOGI(TAG, "SmartConfig is completed.");
            esp_smartconfig_stop();
            _sc_state = SC_STATE_DONE;
            vTaskDelete(NULL);
        }
    }
}

int bo_wifi_sc_init()
{
    _wifi_event_group = xEventGroupCreate();

    BO_TRY_ESP(esp_event_handler_register(IP_EVENT, ESP_EVENT_ANY_ID, &ip_event_handler, NULL));
    BO_TRY_ESP(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    BO_TRY_ESP(esp_event_handler_register(SC_EVENT, ESP_EVENT_ANY_ID, &sc_event_handler, NULL));
    return 0;
}

int bo_wifi_sc_start()
{
    xTaskCreate(sc_task, "smartconfig_task", 4096, NULL, TASK_PRIORITY, NULL);
    return 0;
}

#endif // CONFIG_BORNEO_PROV_METHOD_SC