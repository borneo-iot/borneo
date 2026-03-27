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

#include "fpwm.h"
#include "../rmtpwm.h"

#define TAG "fpwm_rmtpwm"

#define RMTPWM_FREQ_HZ 25000 // 25 kHz PWM
#define RMT_PWM_RESOLUTION_HZ 10000000 // 10MHz resolution

#if CONFIG_LYFI_FAN_CTRL_PWM_DEVICE_RMTPWM

static int _fpwm_init(const struct drvfx_device* dev)
{
    ESP_LOGI(TAG, "Create RMT TX channel (GPIO%u) for fan PWM...", CONFIG_LYFI_FAN_CTRL_PWM_GPIO);

    if (dev == NULL) {
        return -ENODEV;
    }

    rmtpwm_generator_t* data = (rmtpwm_generator_t*)dev->data;
    if (data == NULL) {
        return -ENODATA;
    }

    rmtpwm_encoder_config_t config = {
        .resolution = RMT_PWM_RESOLUTION_HZ,
        .pwm_freq = RMTPWM_FREQ_HZ,
        .gpio_num = CONFIG_LYFI_FAN_CTRL_PWM_GPIO,
    };
    BO_TRY(rmtpwm_generator_init(data, &config));

    return 0;
}

static int _set_duty(const struct drvfx_device* dev, uint8_t duty)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    rmtpwm_generator_t* data = (rmtpwm_generator_t*)dev->data;
    if (data == NULL) {
        return -ENODATA;
    }

    BO_TRY(rmtpwm_set_duty(data, duty));
    return 0;
}

const static struct fpwm_driver_api s_api = {
    .set_duty = &_set_duty,
};

static rmtpwm_generator_t s_rmtpwm = { 0 };

DRVFX_DEVICE_DEFINE("fpwm", _fpwm_init, &s_rmtpwm, NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &s_api);

#endif // CONFIG_LYFI_FAN_CTRL_PWM_DEVICE_RMTPWM