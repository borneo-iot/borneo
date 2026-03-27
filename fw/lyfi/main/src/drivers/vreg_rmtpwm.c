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
#include <driver/gpio.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>

#include "vreg.h"
#include "../rmtpwm.h"

#define TAG "vreg_rmtpwm"

#define RMTPWM_FREQ_HZ 25000 // 25 kHz PWM
#define RMT_PWM_RESOLUTION_HZ 10000000 // 10MHz resolution

#if CONFIG_LYFI_FAN_CTRL_VREG_DEVICE_RMTPWM

static int _vreg_init(const struct drvfx_device* dev)
{
    ESP_LOGI(TAG, "Create RMT TX channel (GPIO%u) for fan internal voltage regulator...",
             CONFIG_LYFI_FAN_CTRL_VREG_GPIO);

    if (dev == NULL) {
        return -ENODEV;
    }

    rmtpwm_generator_t* data = (rmtpwm_generator_t*)dev->data;
    if (data == NULL) {
        return -ENODATA;
    }

    rmtpwm_encoder_config_t dac_config = {
        .resolution = RMT_PWM_RESOLUTION_HZ,
        .pwm_freq = RMTPWM_FREQ_HZ,
        .gpio_num = CONFIG_LYFI_FAN_CTRL_VREG_GPIO,
    };
    BO_TRY(rmtpwm_generator_init(data, &dac_config));

    return 0;
}

static int _set_output(const struct drvfx_device* dev, uint8_t percent)
{
    if (percent > 100) {
        return -EINVAL;
    }

    if (dev == NULL) {
        return -ENODEV;
    }
    rmtpwm_generator_t* data = (rmtpwm_generator_t*)dev->data;
    if (data == NULL) {
        return -ENODATA;
    }

    const int DUTY_RANGE = CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MAX - CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MIN;
    int duty = (DUTY_RANGE * percent + 100 / 2) / 100;
    duty = CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MAX - duty;

    if (duty <= CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MIN) {
        duty = CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MIN;
    }
    if (duty >= CONFIG_LYFI_FAN_CTRL_VREG_DUTY_MAX) {
        duty = 0xFF;
    }

    BO_TRY(rmtpwm_set_duty(data, duty));
    return 0;
}

const static struct vreg_driver_api s_api = {
    .set_output = &_set_output,
};

static rmtpwm_generator_t s_dac = { 0 };

DRVFX_DEVICE_DEFINE("vreg", _vreg_init, &s_dac, NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &s_api);

#endif // CONFIG_LYFI_FAN_CTRL_VREG_DEVICE_RMTPWM