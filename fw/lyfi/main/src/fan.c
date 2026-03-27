#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <errno.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include <esp_system.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <driver/gpio.h>

#if SOC_DAC_SUPPORTED && CONFIG_LYFI_FAN_CTRL_VREG_SUPPORT
#include <driver/dac_oneshot.h>
#endif

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/nvs.h>

#include "fan.h"
#include "drivers/vreg.h"
#include "drivers/fpwm.h"

#define NVS_FAN_NAMESPACE "fan"
#define FAN_NVS_KEY_VREG_ENABLED "vreg_en"
#define FAN_NVS_KEY_PWM_ENABLED "pwm_en"

#define TAG "fan"

#if CONFIG_LYFI_FAN_CTRL_SUPPORT

int fan_factory_settings_load();

static portMUX_TYPE _status_lock = portMUX_INITIALIZER_UNLOCKED;

static struct fan_status _status = { 0 };
static struct fan_factory_settings _factory_settings = { 0 };

int fan_set_power(uint8_t value)
{
    if (value > FAN_POWER_MAX) {
        value = FAN_POWER_MAX;
    }

    portENTER_CRITICAL(&_status_lock);
    if (_status.power == value) {
        portEXIT_CRITICAL(&_status_lock);
        return 0;
    }
    else {
        _status.power = value;
        portEXIT_CRITICAL(&_status_lock);
    }

#if CONFIG_LYFI_FAN_CTRL_SHUTDOWN_ENABLED
    if (value == 0) {
        BO_TRY(gpio_set_level(CONFIG_LYFI_FAN_CTRL_SHUTDOWN_GPIO, 0));
    }
    else {
        BO_TRY(gpio_set_level(CONFIG_LYFI_FAN_CTRL_SHUTDOWN_GPIO, 1));
    }
#endif // LYFI_FAN_CTRL_SHUTDOWN_ENABLED

#if CONFIG_LYFI_FAN_CTRL_PWM_SUPPORT
    if (_factory_settings.flags & FAN_FLAG_PWM_ENABLED) {
        const struct drvfx_device* fpwm = k_device_get_binding("fpwm");
        if (fpwm == NULL) {
            return -ENODEV;
        }
        uint8_t duty = (value * 0xFF + FAN_POWER_MAX / 2) / FAN_POWER_MAX;
        BO_TRY(fpwm_set_duty(fpwm, duty));
        ESP_LOGI(TAG, "Set fan power, method: PWM, power=%u%%", value);
    }
#endif // CONFIG_LYFI_FAN_CTRL_PWM_SUPPORT

#if CONFIG_LYFI_FAN_CTRL_VREG_SUPPORT
    if (_factory_settings.flags & FAN_FLAG_VREG_ENABLED) {
        const struct drvfx_device* vreg = k_device_get_binding("vreg");
        if (vreg == NULL) {
            return -ENODEV;
        }
        BO_TRY(vreg_set_output(vreg, value));
    }
#endif // CONFIG_LYFI_FAN_CTRL_VREG_SUPPORT

    return 0;
}

uint8_t fan_get_power()
{
    uint8_t power;
    portENTER_CRITICAL(&_status_lock);
    power = _status.power;
    portEXIT_CRITICAL(&_status_lock);
    return power;
}

struct fan_status fan_get_status()
{
    struct fan_status status;
    portENTER_CRITICAL(&_status_lock);
    status = _status;
    portEXIT_CRITICAL(&_status_lock);
    return status;
}

int fan_factory_settings_load()
{
    nvs_handle_t nvs_handle;
    BO_TRY(bo_nvs_factory_open(NVS_FAN_NAMESPACE, NVS_READWRITE, &nvs_handle));
    BO_NVS_AUTO_CLOSE(nvs_handle);
    bool changed = false;

    uint8_t en = 0;

    BO_TRY(bo_nvs_get_or_set_u8(nvs_handle, FAN_NVS_KEY_VREG_ENABLED, &en, 1, &changed));
    if (en) {
        _factory_settings.flags |= FAN_FLAG_VREG_ENABLED;
    }
    else {
        _factory_settings.flags &= ~FAN_FLAG_VREG_ENABLED;
    }

    BO_TRY(bo_nvs_get_or_set_u8(nvs_handle, FAN_NVS_KEY_PWM_ENABLED, &en, 1, &changed));
    if (en) {
        _factory_settings.flags |= FAN_FLAG_PWM_ENABLED;
    }
    else {
        _factory_settings.flags &= ~FAN_FLAG_PWM_ENABLED;
    }

    if (changed) {
        BO_TRY(nvs_commit(nvs_handle));
    }

    return 0;
}

static int fan_init(const struct drvfx_device* dev)
{
    ESP_UNUSED(dev);
    ESP_LOGI(TAG, "Initializing fan driver...");

    BO_TRY(fan_factory_settings_load());

#if CONFIG_LYFI_FAN_CTRL_SHUTDOWN_ENABLED
    {
        uint64_t selected_gpios = 0ULL;
        selected_gpios |= 1ULL << CONFIG_LYFI_FAN_CTRL_SHUTDOWN_GPIO;

        gpio_config_t io_conf = { 0 };
        io_conf.intr_type = GPIO_INTR_DISABLE;
        io_conf.mode = GPIO_MODE_OUTPUT;
        io_conf.pin_bit_mask = selected_gpios;
        io_conf.pull_down_en = GPIO_PULLDOWN_DISABLE;
        io_conf.pull_up_en = GPIO_PULLUP_DISABLE;
        BO_TRY(gpio_config(&io_conf));

        BO_TRY(gpio_set_level(CONFIG_LYFI_FAN_CTRL_SHUTDOWN_GPIO, 0));
        ESP_LOGI(TAG, "Fan shutdown GPIO%u initialized.", CONFIG_LYFI_FAN_CTRL_SHUTDOWN_GPIO);
    }
#endif // CONFIG_LYFI_FAN_CTRL_SHUTDOWN_ENABLED

    _status.power = FAN_POWER_MAX;
    BO_TRY(fan_set_power(FAN_POWER_MIN));

    ESP_LOGI(TAG, "Fan driver initizlied.");
    return 0;
}

DRVFX_SYS_INIT(fan_init, APPLICATION, DRVFX_INIT_APP_HIGH_PRIORITY);

#endif // CONFIG_LYFI_FAN_CTRL_SUPPORT