#pragma once

#ifdef __cplusplus
extern "C" {
#endif

ESP_EVENT_DECLARE_BASE(LYFI_EVENTS);

enum {
    LYFI_EVENT_LED_STATE_CHANGED,
    LYFI_EVENT_LED_MODE_CHANGED,
    LYFI_EVENT_LED_TEMPERATURE_CHANGED,
    LYFI_EVENT_LED_NOTIFY_TEMPORARY_STATE,
};

#ifdef __cplusplus
}
#endif