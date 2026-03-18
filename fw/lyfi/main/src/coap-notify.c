#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include <coap3/coap.h>
#include <cbor.h>

#include <drvfx/drvfx.h>

#include <borneo/system.h>
#include <borneo/coap.h>
#include <borneo/rtc.h>

#include "led/led.h"
#include "lyfi-events.h"
#include "fan.h"
#include "coap-paths.h"

#define TAG "lyfi-coap-notify"

static void led_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);

static void led_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    switch (event_id) {

    case LYFI_EVENT_LED_STATE_CHANGED: {
        coap_str_const_t uri
            = { .s = (const uint8_t*)LYFI_COAP_PATH_LED_STATE, .length = sizeof(LYFI_COAP_PATH_LED_STATE) - 1 };
        BO_MUST(bo_coap_notify_resource_changed(&uri));
    } break;

    case LYFI_EVENT_LED_MODE_CHANGED: {
        coap_str_const_t uri
            = { .s = (const uint8_t*)LYFI_COAP_PATH_LED_MODE, .length = sizeof(LYFI_COAP_PATH_LED_MODE) - 1 };
        BO_MUST(bo_coap_notify_resource_changed(&uri));
    } break;

    case LYFI_EVENT_LED_TEMPERATURE_CHANGED: {
        coap_str_const_t uri
            = { .s = (const uint8_t*)LYFI_COAP_PATH_TEMPERATURE, .length = sizeof(LYFI_COAP_PATH_TEMPERATURE) - 1 };
        BO_MUST(bo_coap_notify_resource_changed(&uri));
    } break;

    default:
        break;
    }
}

int _coap_notify_init()
{
    ESP_LOGI(TAG, "Initializing LyFi CoAP notification sub-system...");
    BO_TRY_ESP(esp_event_handler_register(LYFI_EVENTS, ESP_EVENT_ANY_ID, &led_event_handler, NULL));
    return 0;
}

DRVFX_SYS_INIT(_coap_notify_init, APPLICATION, DRVFX_INIT_APP_DEFAULT_PRIORITY);