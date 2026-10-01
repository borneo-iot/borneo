
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

#define TAG "sensor.led_current"

#define BO_ADC_WINDOW_SIZE 5

#if CONFIG_LYFI_MEAS_CURRENT_SUPPORT

#define LED_NVS_NS "led"
#define LED_NVS_KEY_MEAS_CURRENT_ENABLED "curr.en"

#ifndef CONFIG_LYFI_MEAS_CURRENT_OFFSET
#define CONFIG_LYFI_MEAS_CURRENT_OFFSET 0
#endif

struct sensor_current_data {
    struct sensor_runtime runtime;
    const struct drvfx_device* adc_dev;
    int32_t current_ma;
    int32_t filtered_current;
};

struct power_meas_factory_settings {
    bool measurement_enabled;
};

/*
static struct power_meas_factory_settings s_factory_settings = {
    .measurement_enabled = true,
};
*/

/*
static int factory_settings_load(void)
{
    nvs_handle_t nvs_handle;
    BO_TRY(bo_nvs_factory_open(LED_NVS_NS, NVS_READWRITE, &nvs_handle));
    BO_NVS_AUTO_CLOSE(nvs_handle);

    bool changed = false;
    uint8_t enabled = 1;

    BO_TRY(bo_nvs_get_or_set_u8(nvs_handle, LED_NVS_KEY_MEAS_CURRENT_ENABLED, &enabled, 1, &changed));

    if (changed) {
        BO_TRY(nvs_commit(nvs_handle));
    }

    s_factory_settings.measurement_enabled = (enabled != 0);

    return 0;
}
*/

static int _fetch_sample(const struct drvfx_device* dev)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    if (dev->data == NULL) {
        return -ENOSYS;
    }
    struct sensor_current_data* data = (struct sensor_current_data*)dev->data;

    int32_t adc_mv;
    int rc = adc_read_mv(data->adc_dev, CONFIG_LYFI_MEAS_CURRENT_ADC_CHANNEL, &adc_mv);
    if (rc != 0) { sensor_runtime_error(&data->runtime, rc); return rc; }
    adc_mv -= CONFIG_LYFI_MEAS_CURRENT_OFFSET;
    if (adc_mv < 0) {
        adc_mv = 0;
    }
    int32_t raw_ma = (adc_mv * 1000 + (CONFIG_LYFI_MEAS_CURRENT_FACTOR / 2)) / CONFIG_LYFI_MEAS_CURRENT_FACTOR;
    data->current_ma = ema_filter(raw_ma, &data->filtered_current, 1, 10);
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
    struct sensor_current_data* data = (struct sensor_current_data*)dev->data;
    if (!data->runtime.valid) return data->runtime.last_error != 0 ? data->runtime.last_error : -EAGAIN;
    *value = data->current_ma;
    return 0;
}

static int sensor_current_init(const struct drvfx_device* dev)
{
    if (dev == NULL) {
        return -ENODEV;
    }
    ESP_LOGI(TAG, "Initializing current sensor '%s'...", dev->name);

    if (dev->data == NULL) {
        return -ENOSYS;
    }
    struct sensor_current_data* data = (struct sensor_current_data*)dev->data;

    data->adc_dev = k_device_get_binding("adc");
    if (data->adc_dev == NULL) {
        ESP_LOGE(TAG, "Failed to get device 'adc'");
    }

    int rc = _fetch_sample(dev);
    if (rc != 0) ESP_LOGW(TAG, "Initial current sample failed: %d; sensor will retry", rc);

    return 0;
}

const static struct sensor_api s_api = {
    .fetch_sample = &_fetch_sample,
    .get_value = &_get_value,
};

static struct sensor_current_data s_data = { 0 };

DRVFX_DEVICE_DEFINE("sensor.led_current", sensor_current_init, &s_data, NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY,
                    &s_api);

#endif // CONFIG_LYFI_MEAS_CURRENT_SUPPORT
