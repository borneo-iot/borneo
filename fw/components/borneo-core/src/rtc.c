#include <time.h>
#include <sys/time.h>
#include <string.h>
#include <errno.h>

#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include <drvfx/drvfx.h>
#include <drvfx/drivers/rtc.h>

#include "borneo/utils/time.h"
#include "borneo/common.h"
#include "borneo/system.h"
#include "borneo/nvs.h"
#include "borneo/rtc.h"

#define TAG "rtc"
#define TIMEZONE_DEFAULT "UTC"
#define NVS_RTC_NAMESPACE "rtc"
#define NVS_RTC_TZ_KEY "tz"
#define MAX_TZ_LEN 32

static StaticSemaphore_t s_lock_buf;
static SemaphoreHandle_t s_lock;

static int64_t bo_rtc_tm_to_utc_us(const struct tm* tm_utc)
{
    if (tm_utc == NULL) {
        return -EINVAL;
    }

    int64_t timestamp = to_unix_time(tm_utc->tm_year + 1900, tm_utc->tm_mon + 1, tm_utc->tm_mday, tm_utc->tm_hour,
                                     tm_utc->tm_min, tm_utc->tm_sec);
    return timestamp * 1000000LL;
}

static const struct drvfx_device* bo_rtc_ext_get_device()
{
    const struct drvfx_device* rtc = k_device_get_binding("rtc_dev");
    if (rtc == NULL || !k_device_is_ready(rtc)) {
        return NULL;
    }
    return rtc;
}

static int bo_rtc_ext_sync(const struct drvfx_device* rtc)
{
    if (rtc == NULL || !k_device_is_ready(rtc)) {
        ESP_LOGI(TAG, "No external RTC.");
        return 0;
    }

    struct tm ext_now = { 0 };
    int rc = rtc_now(rtc, &ext_now);
    if (rc != 0) {
        ESP_LOGE(TAG, "External RTC read failed: %d", rc);
        return rc;
    }

    int year = ext_now.tm_year + 1900;
    if (year < 2026) {
        ESP_LOGW(TAG, "External RTC time is invalid, skipping sync: %04d-%02d-%02d %02d:%02d:%02d", year,
                 ext_now.tm_mon + 1, ext_now.tm_mday, ext_now.tm_hour, ext_now.tm_min, ext_now.tm_sec);
        return 0;
    }

    int64_t ext_ts_us = bo_rtc_tm_to_utc_us(&ext_now);
    if (ext_ts_us < 0) {
        ESP_LOGW(TAG, "External RTC returned an invalid UTC time, skipping sync");
        return 0;
    }

    BO_TRY(bo_rtc_set_time(ext_ts_us));

    char strftime_buf[64];
    if (strftime(strftime_buf, sizeof(strftime_buf), "%c", &ext_now) > 0) {
        ESP_LOGI(TAG, "System time set from external RTC (UTC): %s", strftime_buf);
    }
    else {
        ESP_LOGI(TAG, "System time set from external RTC (UTC): %04d-%02d-%02d %02d:%02d:%02d", year,
                 ext_now.tm_mon + 1, ext_now.tm_mday, ext_now.tm_hour, ext_now.tm_min, ext_now.tm_sec);
    }

    return 0;
}

int bo_rtc_ext_update()
{
    const struct drvfx_device* rtc = bo_rtc_ext_get_device();
    if (rtc == NULL) {
        ESP_LOGI(TAG, "No external RTC.");
        return 0;
    }

    struct tm now = { 0 };
    if (xSemaphoreTake(s_lock, portMAX_DELAY) != pdTRUE) {
        return -EBUSY;
    }

    {
        BO_SEM_AUTO_RELEASE(s_lock);

        time_t current_time = time(NULL);
        if (current_time == (time_t)-1 || gmtime_r(&current_time, &now) == NULL) {
            ESP_LOGW(TAG, "Failed to convert system time to UTC for external RTC update");
            return -EINVAL;
        }
    }

    int rc = rtc_set_datetime(rtc, &now);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to update external RTC: %d", rc);
        return rc;
    }

    ESP_LOGI(TAG, "External RTC updated from system time (UTC)");
    return 0;
}

int bo_rtc_init()
{
    ESP_LOGI(TAG, "Initializing RTC...");

    s_lock = xSemaphoreCreateMutexStatic(&s_lock_buf);

    size_t tz_len = MAX_TZ_LEN;
    char tz[MAX_TZ_LEN];
    memset(tz, 0, MAX_TZ_LEN);

    nvs_handle_t nvs_handle;
    BO_TRY(bo_nvs_user_open(NVS_RTC_NAMESPACE, NVS_READWRITE, &nvs_handle));
    BO_NVS_AUTO_CLOSE(nvs_handle);
    int rc = nvs_get_str(nvs_handle, NVS_RTC_TZ_KEY, tz, &tz_len);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        strncpy(tz, TIMEZONE_DEFAULT, MAX_TZ_LEN);
        rc = 0;
        ESP_LOGI(TAG, "Time zone setting not found, using default time zone: %s", tz);
    }
    if (rc) {
        return rc;
    }

    BO_TRY(bo_tz_set(tz));

    ESP_LOGI(TAG, "Checking external RTC...");
    const struct drvfx_device* rtc = bo_rtc_ext_get_device();
    rc = bo_rtc_ext_sync(rtc);
    if (rc != 0) {
        // External RTC faults must not block boot because the device may still recover via SNTP later.
        // TODO: Report this through a dedicated fault/alarm path so users can notice RTC battery or bus issues.
        ESP_LOGW(TAG, "External RTC sync failed during boot, continuing without it: %d", rc);
    }

    return 0;
}

int bo_rtc_get_timestamp(uint32_t* timestamp)
{
    if (timestamp == NULL) {
        return -EINVAL;
    }

    if (xSemaphoreTake(s_lock, portMAX_DELAY) == pdTRUE) {
        BO_SEM_AUTO_RELEASE(s_lock);
        struct timeval tv;
        gettimeofday(&tv, NULL);
        *timestamp = (uint32_t)tv.tv_sec;
        return 0;
    }
    else {
        return -EBUSY;
    }
}

int64_t bo_rtc_get_timestamp_us()
{
    if (xSemaphoreTake(s_lock, portMAX_DELAY) == pdTRUE) {
        BO_SEM_AUTO_RELEASE(s_lock);
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (int64_t)tv.tv_sec * 1000000LL + tv.tv_usec;
    }
    else {
        return -EBUSY;
    }
}

int bo_rtc_set_time(int64_t timestamp_us)
{
    if (xSemaphoreTake(s_lock, portMAX_DELAY) == pdTRUE) {
        BO_SEM_AUTO_RELEASE(s_lock);
        struct timeval tv;
        tv.tv_sec = timestamp_us / 1000000LL; // seconds
        tv.tv_usec = timestamp_us % 1000000LL; // microseconds
        if (settimeofday(&tv, NULL) == -1) {
            ESP_LOGE(TAG, "settimeofday failed: %s\n", strerror(errno));
            return -1;
        }
        return 0;
    }
    else {
        return -EBUSY;
    }
}

const char* bo_rtc_get_tz()
{
    //
    const char* tz = NULL;
    if (xSemaphoreTake(s_lock, portMAX_DELAY) == pdTRUE) {
        BO_SEM_AUTO_RELEASE(s_lock);
        tz = getenv("TZ");
    }
    return tz;
}

int bo_rtc_set_tz(const char* tz)
{
    if (tz == NULL) {
        return -EINVAL;
    }
    size_t tz_len = strnlen(tz, MAX_TZ_LEN);
    if (tz_len >= MAX_TZ_LEN) {
        return -EINVAL;
    }

    if (xSemaphoreTake(s_lock, portMAX_DELAY) == pdTRUE) {
        BO_SEM_AUTO_RELEASE(s_lock);

        BO_TRY(bo_tz_set(tz));

        // Saving the time-zone into the NVS
        nvs_handle_t nvs_handle;
        BO_TRY(bo_nvs_user_open(NVS_RTC_NAMESPACE, NVS_READWRITE, &nvs_handle));
        BO_NVS_AUTO_CLOSE(nvs_handle);

        BO_TRY_ESP(nvs_set_str(nvs_handle, NVS_RTC_TZ_KEY, tz));

        // TODO Post message
    }

    return 0;
}
