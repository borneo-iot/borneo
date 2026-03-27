
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

#include <driver/dac_oneshot.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>

#include "vreg.h"

#if CONFIG_LYFI_FAN_CTRL_VREG_DEVICE_DAC

#define TAG "vreg.h"

struct dac_data {
    dac_oneshot_handle_t handle;
};

static int _vreg_init(const struct drvfx_device* dev)
{
    ESP_LOGI(TAG, "Create DAC channel %u for fan internal voltage regulator...", CONFIG_LYFI_FAN_CTRL_VREG_DAC_CHANNEL);

    if (dev == NULL) {
        return -ENODEV;
    }

    struct dac_data* data = (struct dac_data*)dev->data;
    if (data == NULL) {
        return -ENODATA;
    }

    dac_oneshot_config_t oneshot_cfg = {
        .chan_id = CONFIG_LYFI_FAN_CTRL_VREG_DAC_CHANNEL,
    };

    BO_TRY(dac_oneshot_new_channel(&oneshot_cfg, &data->handle));
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
    struct dac_data* data = (struct dac_data*)dev->data;
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
        duty = 0xFF; // DAC_MAX_DUTY
    }

    BO_TRY(dac_oneshot_output_voltage(data->handle, duty));
    return 0;
}

const static struct vreg_driver_api s_api = {
    .set_output = &_set_output,
};

static struct dac_data s_data = { 0 };

DRVFX_DEVICE_DEFINE("vreg", _vreg_init, &s_data, NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &s_api);

#endif // CONFIG_LYFI_FAN_CTRL_VREG_DEVICE_DAC