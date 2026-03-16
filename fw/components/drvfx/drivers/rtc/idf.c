
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stddef.h>
#include <assert.h>
#include <time.h>
#include <sys/time.h>

#include <driver/gpio.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include "drvfx/drvfx.h"
#include "drvfx/drivers/rtc.h"

struct idf_config {
    // No configuration needed for software RTC
};

struct idf_data {
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

static int idf_init(const struct drvfx_device* dev)
{
    struct idf_data* rt = (struct idf_data*)dev->data;

    rt->lock = xSemaphoreCreateMutexStatic(&rt->lock_buf);
    if (rt->lock == NULL) {
        return -1;
    }

    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    // No hardware initialization needed for software RTC

    xSemaphoreGive(rt->lock);
    return 0;
}

static int idf_is_halted(const struct drvfx_device* dev, bool* halted)
{
    struct idf_data* rt = (struct idf_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    // Software RTC is never halted
    *halted = false;

    xSemaphoreGive(rt->lock);
    return 0;
}

static int idf_now(const struct drvfx_device* dev, struct tm* now)
{
    struct idf_data* rt = (struct idf_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    time_t t = time(NULL);
    struct tm* tm = localtime(&t);
    if (tm == NULL) {
        xSemaphoreGive(rt->lock);
        return -1;
    }
    memcpy(now, tm, sizeof(struct tm));

    xSemaphoreGive(rt->lock);
    return 0;
}

static int idf_set_datetime(const struct drvfx_device* dev, const struct tm* dt)
{
    struct idf_data* rt = (struct idf_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    struct tm dt_copy = *dt;
    time_t t = mktime(&dt_copy);
    if (t == -1) {
        xSemaphoreGive(rt->lock);
        return -1;
    }

    struct timeval tv;
    tv.tv_sec = t;
    tv.tv_usec = 0;
    if (settimeofday(&tv, NULL) != 0) {
        xSemaphoreGive(rt->lock);
        return -1;
    }

    xSemaphoreGive(rt->lock);
    return 0;
}

static int idf_halt(const struct drvfx_device* dev)
{
    struct idf_data* rt = (struct idf_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    // No operation for software RTC halt
    xSemaphoreGive(rt->lock);
    return 0;
}

static const struct idf_config _idf_config = {};

static struct idf_data _idf_data = { 0 };

static const struct rtc_driver_api _idf_api = {
    .now = &idf_now,
    .set_datetime = &idf_set_datetime,
    .is_halted = &idf_is_halted,
    .halt = &idf_halt,
};

DRVFX_DEVICE_DEFINE("idf", idf_init, &_idf_data, &_idf_config, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &_idf_api);