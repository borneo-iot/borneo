#include <string.h>
#include <time.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <ctype.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include <driver/ledc.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <esp_rom_md5.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>

#include "../lyfi-events.h"
#include "led.h"

#define LED_NVS_NS "led"
#define LED_NVS_KEY_USAGE "usage"
#define LED_NVS_KEY_RUNNING_MODE "mode"
#define LED_NVS_KEY_MANUAL_COLOR "mcolor"
#define LED_NVS_KEY_SUN_COLOR "suncolor"
#define LED_NVS_KEY_MOON_COLOR "mooncolor"
#define LED_NVS_KEY_SCHEDULER "sch"
#define LED_NVS_KEY_TEMPORARY_DURATION "tmpdur"
#define LED_NVS_KEY_CORRECTION_METHOD "corrmtd"
#define LED_NVS_KEY_NOMINAL_PFD "npfd"
#define LED_NVS_KEY_NOMINAL_POWER "npower"
#define LED_NVS_KEY_PWM_FREQ "pwmfreq"
#define LED_NVS_KEY_CHANNEL_COUNT "chcount"
#define LED_NVS_KEY_LOC "loc"
#define LED_NVS_KEY_TZ_ENABLED "tz_en"
#define LED_NVS_KEY_TZ_OFFSET "tz_off"
#define LED_NVS_KEY_ACCLIMATION_ENABLED "acc.en"
#define LED_NVS_KEY_ACCLIMATION_START "acc.start"
#define LED_NVS_KEY_ACCLIMATION_DURATION "acc.days"
#define LED_NVS_KEY_ACCLIMATION_START_PERCENT "acc.pc"
#define LED_NVS_KEY_CLOUD_ENABLED "cloud.en"
#define LED_NVS_KEY_MOON_ENABLED "moon.en"

#define TAG "led.settings"

extern const struct led_user_settings LED_USER_DEFAULT_SETTINGS;
extern const struct led_factory_settings LED_FACTORY_DEFAULT_SETTINGS;

static struct led_factory_settings s_factory_settings;

int led_load_factory_settings()
{
    memset(&s_factory_settings, 0, sizeof(s_factory_settings));

    nvs_handle_t handle;
    BO_TRY(bo_nvs_factory_open(LED_NVS_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    bool changed = false;

    BO_TRY(bo_nvs_get_or_set_u8(handle, LED_NVS_KEY_USAGE, &s_factory_settings.usage,
                                LED_FACTORY_DEFAULT_SETTINGS.usage, &changed));

    BO_TRY(bo_nvs_get_or_set_u16(handle, LED_NVS_KEY_NOMINAL_PFD, &s_factory_settings.nominal_pfd,
                                 LED_FACTORY_DEFAULT_SETTINGS.nominal_pfd, &changed));

    BO_TRY(bo_nvs_get_or_set_u16(handle, LED_NVS_KEY_NOMINAL_POWER, &s_factory_settings.nominal_power,
                                 LED_FACTORY_DEFAULT_SETTINGS.nominal_power, &changed));

    BO_TRY(bo_nvs_get_or_set_u16(handle, LED_NVS_KEY_PWM_FREQ, &s_factory_settings.pwm_freq,
                                 LED_FACTORY_DEFAULT_SETTINGS.pwm_freq, &changed));

    BO_TRY(bo_nvs_get_or_set_u8(handle, LED_NVS_KEY_CHANNEL_COUNT, &s_factory_settings.channel_count,
                                CONFIG_LYFI_LED_CHANNEL_COUNT, &changed));

    // Load channel names and colors from NVS with Kconfig defaults
    for (uint8_t ch = 0; ch < CONFIG_LYFI_LED_CHANNEL_COUNT; ch++) {
        const struct led_channel_settings* defaults = &LED_FACTORY_DEFAULT_SETTINGS.channels[ch];
        if (strlen(defaults->name) == 0 || strlen(defaults->color) == 0) {
            continue;
        }

        char key[16];

        size_t len = sizeof(s_factory_settings.channels[ch].name);
        snprintf(key, sizeof(key), "ch%u.name", ch);
        BO_TRY(
            bo_nvs_get_or_set_str(handle, key, s_factory_settings.channels[ch].name, &len, defaults->name, &changed));

        len = sizeof(s_factory_settings.channels[ch].color);
        snprintf(key, sizeof(key), "ch%u.color", ch);
        BO_TRY(
            bo_nvs_get_or_set_str(handle, key, s_factory_settings.channels[ch].color, &len, defaults->color, &changed));

        snprintf(key, sizeof(key), "ch%u.wl", ch);
        BO_TRY(bo_nvs_get_or_set_u16(handle, key, (uint16_t*)&s_factory_settings.channels[ch].wavelength,
                                     defaults->wavelength, &changed));

        snprintf(key, sizeof(key), "ch%u.wl2", ch);
        BO_TRY(bo_nvs_get_or_set_u16(handle, key, (uint16_t*)&s_factory_settings.channels[ch].wavelength2,
                                     defaults->wavelength2, &changed));

        snprintf(key, sizeof(key), "ch%u.f", ch);
        len = sizeof(float);
        BO_TRY(bo_nvs_get_or_set_blob(handle, key, &s_factory_settings.channels[ch].factor, &len,
                                      &defaults->wavelength2, sizeof(float), &changed));
    }

    if (changed) {
        BO_TRY(nvs_commit(handle));
    }

    return 0;
}

int led_load_user_settings()
{
    struct led_user_settings* settings = &_led.settings;
    size_t size;

    nvs_handle_t handle;
    BO_TRY(bo_nvs_user_open(LED_NVS_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    int rc;

    {
        rc = nvs_get_u8(handle, LED_NVS_KEY_RUNNING_MODE, &settings->mode);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->mode = LED_USER_DEFAULT_SETTINGS.mode;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        rc = nvs_get_u32(handle, LED_NVS_KEY_TEMPORARY_DURATION, &settings->temporary_duration);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->temporary_duration = LED_USER_DEFAULT_SETTINGS.temporary_duration;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        size = sizeof(struct led_scheduler);
        rc = nvs_get_blob(handle, LED_NVS_KEY_SCHEDULER, &settings->scheduler, &size);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            memcpy(&settings->scheduler, &LED_USER_DEFAULT_SETTINGS.scheduler, sizeof(struct led_scheduler));
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        size = sizeof(led_color_t);
        rc = nvs_get_blob(handle, LED_NVS_KEY_MANUAL_COLOR, &settings->manual_color, &size);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            memcpy(&settings->manual_color, &LED_USER_DEFAULT_SETTINGS.manual_color, sizeof(led_color_t));
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        size = sizeof(led_color_t);
        rc = nvs_get_blob(handle, LED_NVS_KEY_SUN_COLOR, &settings->sun_color, &size);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            memset(settings->sun_color, 0, sizeof(led_color_t));
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        size = sizeof(led_color_t);
        rc = nvs_get_blob(handle, LED_NVS_KEY_MOON_COLOR, &settings->moon_color, &size);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            memset(settings->moon_color, 0, sizeof(led_color_t));
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        rc = nvs_get_u8(handle, LED_NVS_KEY_CORRECTION_METHOD, &settings->correction_method);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->correction_method = LED_USER_DEFAULT_SETTINGS.correction_method;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        size = sizeof(struct geo_location);
        rc = nvs_get_blob(handle, LED_NVS_KEY_LOC, &settings->location, &size);
        if (rc == 0) {
            settings->flags |= LED_OPTION_HAS_GEO_LOCATION;
        }
        else if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->flags &= ~LED_OPTION_HAS_GEO_LOCATION;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        uint8_t tz_en = 0;
        rc = nvs_get_u8(handle, LED_NVS_KEY_TZ_ENABLED, &tz_en);
        if (rc == 0) {
            if (tz_en) {
                settings->flags |= LED_OPTION_TZ_ENABLED;
            }
            else {
                settings->flags &= ~LED_OPTION_TZ_ENABLED;
            }
        }
        else if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->flags &= ~LED_OPTION_TZ_ENABLED;
        }
        else if (rc) {
            return rc;
        }
    }

    {
        rc = nvs_get_i32(handle, LED_NVS_KEY_TZ_OFFSET, &settings->tz_offset);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->tz_offset = LED_USER_DEFAULT_SETTINGS.tz_offset;
        }
        else if (rc) {
            return rc;
        }
    }

    {
        uint8_t acc_en = 0;
        rc = nvs_get_u8(handle, LED_NVS_KEY_ACCLIMATION_ENABLED, &acc_en);
        if (rc == 0) {
            if (acc_en) {
                settings->flags |= LED_OPTION_ACCLIMATION_ENABLED;
            }
            else {
                settings->flags &= ~LED_OPTION_ACCLIMATION_ENABLED;
            }
        }
        else if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->flags &= ~LED_OPTION_ACCLIMATION_ENABLED;
        }
        else if (rc) {
            return rc;
        }
    }

    {
        rc = nvs_get_i64(handle, LED_NVS_KEY_ACCLIMATION_START, &settings->acclimation.start_utc);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->acclimation.start_utc = LED_USER_DEFAULT_SETTINGS.acclimation.start_utc;
        }
        else if (rc) {
            return rc;
        }
    }

    {
        rc = nvs_get_u8(handle, LED_NVS_KEY_ACCLIMATION_DURATION, &settings->acclimation.duration);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->acclimation.duration = LED_USER_DEFAULT_SETTINGS.acclimation.duration;
            rc = 0;
        }
        else if (rc) {
            return rc;
        }
        // Validate loaded value
        if (settings->acclimation.duration < LED_ACCLIMATION_DAYS_MIN
            || settings->acclimation.duration > LED_ACCLIMATION_DAYS_MAX) {
            settings->acclimation.duration = LED_USER_DEFAULT_SETTINGS.acclimation.duration;
        }
    }

    {
        rc = nvs_get_u8(handle, LED_NVS_KEY_ACCLIMATION_START_PERCENT, &settings->acclimation.start_percent);
        if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->acclimation.start_percent = LED_USER_DEFAULT_SETTINGS.acclimation.start_percent;
            rc = 0;
        }
        else if (rc) {
            return rc;
        }
        // Validate loaded value
        if (settings->acclimation.start_percent < 10 || settings->acclimation.start_percent > 90) {
            settings->acclimation.start_percent = LED_USER_DEFAULT_SETTINGS.acclimation.start_percent;
        }
    }

    {
        uint8_t cloud_en = 0;
        rc = nvs_get_u8(handle, LED_NVS_KEY_CLOUD_ENABLED, &cloud_en);
        if (rc == 0) {
            if (cloud_en) {
                settings->flags |= LED_OPTION_CLOUD_ENABLED;
            }
            else {
                settings->flags &= ~LED_OPTION_CLOUD_ENABLED;
            }
        }
        else if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->flags &= ~LED_OPTION_CLOUD_ENABLED;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    {
        uint8_t moon_en = 0;
        rc = nvs_get_u8(handle, LED_NVS_KEY_MOON_ENABLED, &moon_en);
        if (rc == 0) {
            if (moon_en) {
                settings->flags |= LED_OPTION_MOON_ENABLED;
            }
            else {
                settings->flags &= ~LED_OPTION_MOON_ENABLED;
            }
        }
        else if (rc == ESP_ERR_NVS_NOT_FOUND) {
            settings->flags &= ~LED_OPTION_MOON_ENABLED;
            rc = 0;
        }
        if (rc) {
            return rc;
        }
    }

    // TODO
    // Loading the brightness and power settings...
    // #ifdef CONFIG_LYFI_STANDALONE_CONTROLLER
    // #endif // CONFIG_LYFI_STANDALONE_CONTROLLER

    return rc;
}

int led_save_user_settings()
{
    xSemaphoreTake(_led.settings_lock, portMAX_DELAY);
    BO_SEM_AUTO_RELEASE(_led.settings_lock);

    ESP_LOGI(TAG, "Saving dimming settings...");

    const struct led_user_settings* settings = &_led.settings;
    nvs_handle_t handle;
    BO_TRY(bo_nvs_user_open(LED_NVS_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_RUNNING_MODE, settings->mode));
    BO_TRY(nvs_set_u32(handle, LED_NVS_KEY_TEMPORARY_DURATION, settings->temporary_duration));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_CORRECTION_METHOD, settings->correction_method));
    BO_TRY(nvs_set_blob(handle, LED_NVS_KEY_SCHEDULER, &settings->scheduler, sizeof(struct led_scheduler)));
    BO_TRY(nvs_set_blob(handle, LED_NVS_KEY_MANUAL_COLOR, settings->manual_color, sizeof(led_color_t)));
    BO_TRY(nvs_set_blob(handle, LED_NVS_KEY_SUN_COLOR, settings->sun_color, sizeof(led_color_t)));
    BO_TRY(nvs_set_blob(handle, LED_NVS_KEY_MOON_COLOR, settings->moon_color, sizeof(led_color_t)));

    if (led_has_geo_location()) {
        BO_TRY(nvs_set_blob(handle, LED_NVS_KEY_LOC, &settings->location, sizeof(struct geo_location)));
    }

    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_TZ_ENABLED, (uint8_t)(settings->flags & LED_OPTION_TZ_ENABLED)));
    BO_TRY(nvs_set_i32(handle, LED_NVS_KEY_TZ_OFFSET, settings->tz_offset));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_ACCLIMATION_ENABLED, (uint8_t)led_acclimation_is_enabled()));
    BO_TRY(nvs_set_i64(handle, LED_NVS_KEY_ACCLIMATION_START, settings->acclimation.start_utc));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_ACCLIMATION_DURATION, settings->acclimation.duration));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_ACCLIMATION_START_PERCENT, settings->acclimation.start_percent));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_CLOUD_ENABLED, (uint8_t)(settings->flags & LED_OPTION_CLOUD_ENABLED)));
    BO_TRY(nvs_set_u8(handle, LED_NVS_KEY_MOON_ENABLED, (uint8_t)(settings->flags & LED_OPTION_MOON_ENABLED)));

    BO_TRY(nvs_commit(handle));
    ESP_LOGI(TAG, "Dimming settings updated.");

    return 0;
}

bool led_has_geo_location()
{
    bool has_location;
    portENTER_CRITICAL(&g_led_spinlock);
    has_location = _led.settings.flags & LED_OPTION_HAS_GEO_LOCATION;
    portEXIT_CRITICAL(&g_led_spinlock);
    return has_location;
}

int led_set_geo_location(const struct geo_location* location)
{
    if (location == NULL) {
        return -EINVAL;
    }

    if (isnan(location->lat) || isnan(location->lng) || isinf(location->lat) || isinf(location->lng)) {
        return -EINVAL;
    }

    // lat [-90.0, 90.0]
    if (location->lat < -90.0f || location->lat > 90.0f) {
        return -EINVAL;
    }
    // lng [-180.0, 180.0]
    if (location->lng < -180.0f || location->lng > 180.0f) {
        return -EINVAL;
    }
    portENTER_CRITICAL(&g_led_spinlock);
    _led.settings.location.lat = location->lat;
    _led.settings.location.lng = location->lng;
    _led.settings.flags |= LED_OPTION_HAS_GEO_LOCATION;
    portEXIT_CRITICAL(&g_led_spinlock);

    BO_TRY(led_save_user_settings());

    BO_TRY(esp_event_post(BO_SYSTEM_EVENTS, BO_EVENT_GEO_LOCATION_CHANGED, NULL, 0, portMAX_DELAY));

    return 0;
}

int led_tz_enable(bool enabled)
{
    portENTER_CRITICAL(&g_led_spinlock);
    if (enabled) {
        if (_led.settings.tz_offset < -43200 || _led.settings.tz_offset > 50400) {
            portEXIT_CRITICAL(&g_led_spinlock);
            return -EINVAL;
        }
        _led.settings.flags |= LED_OPTION_TZ_ENABLED;
    }
    else {
        _led.settings.flags &= ~LED_OPTION_TZ_ENABLED;
    }
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_TRY(led_save_user_settings());
    return 0;
}

int led_tz_set_offset(int32_t offset)
{
    // -12*3600 ~ +14*3600（-43200 ~ +50400），UTC-12:00 ~ UTC+14:00
    if (offset < -43200 || offset > 50400) {
        return -EINVAL;
    }
    portENTER_CRITICAL(&g_led_spinlock);
    _led.settings.tz_offset = offset;
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_TRY(led_save_user_settings());
    return 0;
}

inline const struct led_factory_settings* led_get_factory_settings()
{
    //
    return &s_factory_settings;
}

inline size_t led_channel_count()
{
    const struct led_factory_settings* factory_settings = led_get_factory_settings();
    return factory_settings->channel_count;
}

const char* led_get_channel_name(uint8_t ch)
{
    if (ch >= CONFIG_LYFI_LED_CHANNEL_COUNT) {
        return NULL;
    }
    return s_factory_settings.channels[ch].name;
}

const char* led_get_channel_color(uint8_t ch)
{
    if (ch >= CONFIG_LYFI_LED_CHANNEL_COUNT) {
        return NULL;
    }
    return s_factory_settings.channels[ch].color;
}

int16_t led_get_channel_wavelength(uint8_t ch)
{
    if (ch >= CONFIG_LYFI_LED_CHANNEL_COUNT) {
        return 0;
    }
    return s_factory_settings.channels[ch].wavelength;
}