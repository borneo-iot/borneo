#include <time.h>
#include <sys/time.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include <drvfx/drvfx.h>

#include "borneo/system.h"
#include "borneo/utils/time.h"
#include "borneo/common.h"
#include "borneo/nvs.h"
#include "borneo/devices/sensor.h"

struct sensors {
    size_t count;
    const struct drvfx_device* devices[];
};

#define TAG "sensors"

static struct sensors* s_sensors = NULL;

static void sensor_task(void* arg)
{
    struct sensors* sensors = (struct sensors*)arg;
    while (1) {
        for (size_t i = 0; i < sensors->count; i++) {
            int ret = sensor_fetch_sample(sensors->devices[i]);
            if (ret != 0) {
                ESP_LOGE(TAG, "Failed to fetch sample from %s: %d", sensors->devices[i]->name, ret);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

static int _sensors_init(const struct drvfx_device* dev)
{
    (void)dev;

    const struct drvfx_device* devices = NULL;
    size_t ndevices = k_device_get_all_static(&devices);

    // Count sensor devices
    size_t sensor_count = 0;
    for (size_t i = 0; i < ndevices; i++) {
        if (strncmp(devices[i].name, "sensor.", 7) == 0) {
            sensor_count++;
        }
    }

    // Allocate sensors struct
    struct sensors* sensors = calloc(1, sizeof(struct sensors) + sensor_count * sizeof(const struct drvfx_device*));
    if (!sensors) {
        ESP_LOGE(TAG, "Failed to allocate sensors");
        return -ENOMEM;
    }

    sensors->count = sensor_count;
    size_t idx = 0;
    for (size_t i = 0; i < ndevices; i++) {
        if (strncmp(devices[i].name, "sensor.", 7) == 0) {
            sensors->devices[idx++] = &devices[i];
        }
    }

    // Create task
    xTaskCreate(sensor_task, "sensor_task", 2048, sensors, 8, NULL);

    s_sensors = sensors;

    return 0;
}

size_t sensors_get_device_count(void) { return s_sensors ? s_sensors->count : 0; }

const struct drvfx_device** sensors_get_devices(void) { return s_sensors ? s_sensors->devices : NULL; }

DRVFX_SYS_INIT(_sensors_init, APPLICATION, DRVFX_INIT_APP_HIGH_PRIORITY);