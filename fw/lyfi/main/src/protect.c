#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include <esp_system.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <driver/ledc.h>
#include <nvs_flash.h>
#include <driver/gpio.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/common.h>
#include <borneo/devices/sensor.h>
#include <borneo/power.h>
#include <borneo/nvs.h>

#include "fan.h"
#include "thermal.h"
#include "protect.h"

#if CONFIG_LYFI_PROTECTION_ENABLED

static int load_factory_settings();
static void protect_task(void*);

#define TASK_PRIORITY 12

#define PROTECT_NVS_NAMESPACE "protect"
#define NVS_KEY_ENABLED "en"
#define NVS_KEY_OPP_VALUE "opp.v"
#define NVS_KEY_OPP_ENABLED "opp.en"
#define NVS_KEY_OVERHEATED_TEMP "ot.v"
#define NVS_KEY_OVERHEATED_ENABLED "ot.en"

#define OVERHEATED_TEMP_COUNT_MAX 10
#define PROTECT_OVERHEATED_TEMP_DEFAULT 65

#define TAG "protect"

struct bo_protect_settings {

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
    uint8_t overpower_enabled; // Overpower protection enabled
    int32_t overpower_mw; // Overpower protection value
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
    uint8_t overheated_enabled; // Overheated temperature enabled
    uint8_t overheated_temp; // Overheated temperature threshold
#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
};

struct bo_protect_status {

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
    volatile int overheated_count; // Count of overheated events
    volatile int temp_read_fail_count; // Count of temperature read failures
#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
    const struct drvfx_device* power_sensor_dev;
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
};

static struct bo_protect_status _protect = { 0 };
static struct bo_protect_settings _settings = { 0 };

int bo_protect_init()
{
    ESP_LOGI(TAG, "Initializing protection...");

    ESP_LOGI(TAG, "Loading factory settings...");
    BO_TRY(load_factory_settings());

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
    {
        _protect.power_sensor_dev = k_device_get_binding("sensor.led_power");
        if (_protect.power_sensor_dev == NULL) {
            return -ENODEV;
        }
    }
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

    xTaskCreate(protect_task, "protect_task", 2048, NULL, TASK_PRIORITY, NULL);

    ESP_LOGI(TAG, "Protection initialized");
    return 0;
}

uint8_t bo_protect_get_overheated_temp() { return _settings.overheated_temp; }

int bo_protect_set_overheated_temp(uint8_t temp)
{
    if (temp < 40 || temp > 85) {
        ESP_LOGE(TAG, "Invalid overheated temperature: %u", temp);
        return -1;
    }

    _settings.overheated_temp = temp;

    nvs_handle_t nvs_handle;
    BO_TRY_ESP(nvs_open(PROTECT_NVS_NAMESPACE, NVS_READWRITE, &nvs_handle));

    int rc = nvs_set_u8(nvs_handle, NVS_KEY_OVERHEATED_TEMP, temp);
    if (rc) {
        goto __EXIT_CLOSE;
    }

    rc = nvs_commit(nvs_handle);
    if (rc) {
        goto __EXIT_CLOSE;
    }

__EXIT_CLOSE:
    nvs_close(nvs_handle);
    return rc;
}

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
int32_t bo_protect_get_over_power_mw()
{
    //
    return _settings.overpower_mw;
}
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

int load_factory_settings()
{
    nvs_handle_t handle;
    BO_TRY_ESP(bo_nvs_factory_open(PROTECT_NVS_NAMESPACE, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);
    bool changed = false;

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
    BO_TRY(bo_nvs_get_or_set_u8(handle, NVS_KEY_OPP_ENABLED, &_settings.overpower_enabled, 1, &changed));
    BO_TRY(bo_nvs_get_or_set_i32(handle, NVS_KEY_OPP_VALUE, &_settings.overpower_mw,
                                 CONFIG_LYFI_PROTECTION_OVER_POWER_DEFAULT_VALUE, &changed));
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
    BO_TRY(bo_nvs_get_or_set_u8(handle, NVS_KEY_OVERHEATED_TEMP, &_settings.overheated_temp,
                                PROTECT_OVERHEATED_TEMP_DEFAULT, &changed));
    BO_TRY(bo_nvs_get_or_set_u8(handle, NVS_KEY_OVERHEATED_ENABLED, &_settings.overheated_enabled, 1, &changed));
#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

    if (changed) {
        BO_TRY(nvs_commit(handle));
    }
    return 0;
}

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

static void check_overheated_protection()
{
    // Continuous detection of high temperatures multiple times will trigger an emergency shutdown of the
    // lights.
    if (!_settings.overheated_enabled) {
        return;
    }
    if (!thermal_is_available()) {
        _protect.temp_read_fail_count = 0;
        _protect.overheated_count = 0;
        return;
    }
    int current_temp = thermal_get_current_temp();
    if (current_temp < 0) {
        _protect.temp_read_fail_count++;
        if (_protect.temp_read_fail_count >= 5) {
            ESP_LOGE(TAG, "thermal_get_current_temp failed 5 times, assuming overheated!");
            fan_set_power(100);
            bo_power_shutdown(BO_SHUTDOWN_REASON_OVERHEATED);
            _protect.temp_read_fail_count = 0;
        }
    }
    else {
        _protect.temp_read_fail_count = 0;
        if (current_temp >= _settings.overheated_temp) {
            _protect.overheated_count++;
            ESP_LOGW(TAG, "[%u/%u] Too hot!", _protect.overheated_count, OVERHEATED_TEMP_COUNT_MAX);
            if (_protect.overheated_count >= OVERHEATED_TEMP_COUNT_MAX) {
                fan_set_power(100);
                ESP_LOGW(TAG, "Over temperature(temp=%d, set=%u)! shutting down...", current_temp,
                         _settings.overheated_temp);
                bo_power_shutdown(BO_SHUTDOWN_REASON_OVERHEATED);
                _protect.overheated_count = 0;
            }
        }
        else {
            _protect.overheated_count = 0;
        }
    }
}

#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

static void check_overpower_protection()
{
    if (!_settings.overpower_enabled) {
        return;
    }

    static int power_read_fail_count = 0;
    int32_t power_mw;
    int ret = sensor_get_value(_protect.power_sensor_dev, &power_mw);
    if (ret != 0) {
        power_read_fail_count++;
        if (power_read_fail_count >= 5) {
            ESP_LOGE(TAG, "bo_power_read failed 5 times, panic!");
            bo_panic();
        }
    }
    else {
        power_read_fail_count = 0;
        if (_settings.overpower_mw > 0 && power_mw > _settings.overpower_mw) {
            ESP_LOGE(TAG, "Over-power protection triggered! Shutdown in progress...");
            ESP_LOGE(TAG, "%ld mW >= %ld mW", power_mw, _settings.overpower_mw);
            BO_MUST(bo_power_shutdown(BO_SHUTDOWN_REASON_OVER_POWER));
        }
    }
}

#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

void protect_task(void*)
{
    for (;;) {
        if (bo_power_is_on()) {

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
            check_overpower_protection();
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
            check_overheated_protection();
#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
        }

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

#endif // CONFIG_LYFI_PROTECTION_ENABLED