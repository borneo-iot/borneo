
#include <errno.h>
#include <nvs_flash.h>

#include "sdkconfig.h"

#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include <esp_timer.h>
#include <esp_attr.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_sntp.h>
#include <esp_system.h>
#include <driver/gpio.h>
#include <esp_adc/adc_oneshot.h>

#include <drvfx/drvfx.h>

#include <borneo/algo/filters.h>
#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/devices/adc.h>
#include <borneo/devices/sensor.h>

#define TAG "sensor.led_power"

#define BO_ADC_WINDOW_SIZE 5

#if CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT

#ifndef CONFIG_LYFI_MEAS_CURRENT_OFFSET
#define CONFIG_LYFI_MEAS_CURRENT_OFFSET 0
#endif

struct sensor_data {
    struct sensor_runtime runtime;
    const struct drvfx_device* vdev;
    const struct drvfx_device* cdev;
    int32_t power_mw;
};

static int _fetch_sample(const struct drvfx_device* dev)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    if (dev->data == NULL) {
        return -ENOSYS;
    }
    struct sensor_data* data = (struct sensor_data*)dev->data;

    int32_t v_mv;
    int rc = sensor_get_value(data->vdev, &v_mv);
    if (rc != 0) {
        sensor_runtime_error(&data->runtime, rc);
        return rc;
    }

    int32_t c_ma;
    rc = sensor_get_value(data->cdev, &c_ma);
    if (rc != 0) {
        sensor_runtime_error(&data->runtime, rc);
        return rc;
    }

    data->power_mw = (v_mv * c_ma + 500) / 1000; // Convert to mW
    sensor_runtime_ok(&data->runtime);
    return 0;
}

static int _get_value(const struct drvfx_device* dev, int32_t* value)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    if (dev->data == NULL) {
        return -ENOSYS;
    }
    struct sensor_data* data = (struct sensor_data*)dev->data;
    if (!data->runtime.valid)
        return data->runtime.last_error != 0 ? data->runtime.last_error : -EAGAIN;
    *value = data->power_mw;
    return 0;
}

static int sensor_led_power_init(const struct drvfx_device* dev)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    ESP_LOGI(TAG, "Initializing current sensor '%s'...", dev->name);

    if (dev->data == NULL) {
        return -ENOSYS;
    }
    struct sensor_data* data = (struct sensor_data*)dev->data;

    data->vdev = k_device_get_binding("sensor.voltage");
    if (data->vdev == NULL) {
        ESP_LOGE(TAG, "Failed to get device 'sensor.voltage'");
    }

    data->cdev = k_device_get_binding("sensor.led_current");
    if (data->cdev == NULL) {
        ESP_LOGE(TAG, "Failed to get device 'sensor.led_current'");
    }

    int rc = _fetch_sample(dev);
    if (rc != 0)
        ESP_LOGW(TAG, "Initial power sample failed: %d; sensor will retry", rc);

    return 0;
}

const static struct sensor_api s_api = {
    .fetch_sample = &_fetch_sample,
    .get_value = &_get_value,
};

static struct sensor_data s_data = { 0 };

DRVFX_DEVICE_DEFINE("sensor.led_power", sensor_led_power_init, &s_data, NULL, DRVFX_INIT_POST_KERNEL_LOWER_PRIORITY,
                    &s_api);

#endif // CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT
