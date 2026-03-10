#include <string.h>
#include <errno.h>
#include <math.h>
#include <assert.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <driver/ledc.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <esp_rom_md5.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/utils/time.h>
#include <borneo/timer.h>

#include "../lyfi-events.h"
#include "../algo.h"
#include "led.h"

#define TAG "led.fade"

#define FADE_ON_PERIOD_MS 5000
#define FADE_OFF_PERIOD_MS 3000

int led_fade_to_color(const led_color_t color, uint32_t duration_ms)
{
    if (led_is_fading()) {
        BO_TRY(led_fade_stop());
    }

    if (led_get_state() == LED_STATE_DIMMING) {
        return -EINVAL;
    }

    if (duration_ms < 10) {
        return -EINVAL;
    }

    int64_t now = bo_timer_uptime_ms();
    portENTER_CRITICAL(&g_led_spinlock);
    _led.fade_start_time_ms = now;
    _led.fade_duration_ms = duration_ms;
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_TRY(led_get_color(_led.fade_start_color));
    portENTER_CRITICAL(&g_led_spinlock);
    memcpy(_led.fade_end_color, color, sizeof(led_color_t));
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        _led.fade_start_virtual_color[ch] = led_brightness_to_virtual(_led.fade_start_color[ch]);
        _led.fade_end_virtual_color[ch] = led_brightness_to_virtual(color[ch]);
        _led.fade_current_virtual_color[ch] = _led.fade_start_virtual_color[ch];
    }
    portEXIT_CRITICAL(&g_led_spinlock);
    // publish fade active after all state is set
    atomic_store_explicit(&_led.fade_active, true, memory_order_release);
    return 0;
}

int led_fade_to_normal()
{
    led_color_t end_color;

    time_t now = time(NULL) * 1000;
    now += FADE_ON_PERIOD_MS;
    now /= 1000;
    struct tm local_tm = { 0 };
    localtime_r(&now, &local_tm);

    if (bo_power_is_on()) {
        portENTER_CRITICAL(&g_led_spinlock);
        switch (_led.settings.mode) {
        case LED_MODE_MANUAL: {
            memcpy(end_color, _led.settings.manual_color, sizeof(led_color_t));
        } break;

        case LED_MODE_SCHEDULED: {
            led_sch_compute_color(&_led.settings.scheduler, &local_tm, end_color);
        } break;

        case LED_MODE_SUN: {
            led_sch_compute_color(&_led.sun_scheduler, &local_tm, end_color);
        } break;

        default:
            assert(false);
            break;
        }
        portEXIT_CRITICAL(&g_led_spinlock);
    }
    else {
        memset(end_color, 0, sizeof(led_color_t));
    }

    BO_TRY(led_fade_to_color(end_color, FADE_ON_PERIOD_MS));

    return 0;
}

int led_fade_stop()
{
    portENTER_CRITICAL(&g_led_spinlock);
    _led.fade_start_time_ms = 0LL;
    portEXIT_CRITICAL(&g_led_spinlock);
    atomic_store_explicit(&_led.fade_active, false, memory_order_release);
    return 0;
}

int led_fade_black()
{
    led_color_t off_color;
    memset(off_color, 0, sizeof(led_color_t));
    BO_TRY(led_fade_to_color(off_color, FADE_OFF_PERIOD_MS));
    return 0;
}

void led_fade_drive()
{
    portENTER_CRITICAL(&g_led_spinlock);
    int64_t fade_start_time_ms = _led.fade_start_time_ms;
    int64_t fade_duration_ms = _led.fade_duration_ms;
    led_color_t fade_start_color;
    led_color_t fade_end_color;
    led_virtual_color_t fade_start_virtual_color;
    led_virtual_color_t fade_end_virtual_color;
    memcpy(fade_start_color, _led.fade_start_color, sizeof(led_color_t));
    memcpy(fade_end_color, _led.fade_end_color, sizeof(led_color_t));
    memcpy(fade_start_virtual_color, _led.fade_start_virtual_color, sizeof(led_virtual_color_t));
    memcpy(fade_end_virtual_color, _led.fade_end_virtual_color, sizeof(led_virtual_color_t));
    portEXIT_CRITICAL(&g_led_spinlock);

    int64_t now = bo_timer_uptime_ms();
    if (now >= fade_start_time_ms + fade_duration_ms) {
        BO_MUST(led_fade_stop());
        BO_MUST(led_update_color(fade_end_color));
        return;
    }

    uint32_t elapsed_time_ms = (uint32_t)(now - fade_start_time_ms);
    uint32_t progress = ((elapsed_time_ms << 16) + (fade_duration_ms >> 1)) / fade_duration_ms;

    led_color_t color;
    led_virtual_color_t virtual_color;
    for (size_t ich = 0; ich < led_channel_count(); ich++) {
        uint64_t blended = ((uint64_t)fade_start_virtual_color[ich] * (65536U - progress))
            + ((uint64_t)fade_end_virtual_color[ich] * progress) + (1U << 15);
        virtual_color[ich] = (led_virtual_brightness_t)(blended >> 16);
        color[ich] = led_virtual_to_brightness(virtual_color[ich]);
    }

    portENTER_CRITICAL(&g_led_spinlock);
    memcpy(_led.fade_current_virtual_color, virtual_color, sizeof(led_virtual_color_t));
    portEXIT_CRITICAL(&g_led_spinlock);

    BO_MUST(led_update_color(color));
}

inline bool led_is_fading()
{
    //
    return atomic_load_explicit(&_led.fade_active, memory_order_acquire);
}
