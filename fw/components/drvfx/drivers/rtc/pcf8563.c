
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stddef.h>
#include <assert.h>
#include <time.h>

#include <esp_err.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include "drvfx/drvfx.h"
#include "drvfx/drivers/i2c.h"
#include "drvfx/drivers/rtc.h"

#define TAG "pcf8563"

#define DEC2BCD(dec) ((((dec) / 10) * 16) + ((dec) % 10))
#define BCD2DEC(bcd) ((((bcd) / 16) * 10) + ((bcd) % 16))

#define PCF8563_BIT_VL 7
#define PCF8563_BIT_YEAR_CENTURY 7

#define PCF8563_MASK_SECONDS 0x7F
#define PCF8563_MASK_MINUTES 0x7F
#define PCF8563_MASK_HOURS 0x3F
#define PCF8563_MASK_DAYS 0x3F
#define PCF8563_MASK_WEEKDAYS 0x07
#define PCF8563_MASK_MONTHS 0x1F

struct pcf8563_config {
    const char* bus_name;
    uint16_t addr;
    TickType_t timeout;
};

struct pcf8563_data {
    const struct drvfx_device* bus;
    void* bus_device;
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

enum {
    PCF8563_REG_CONTROL_STATUS_1 = 0x00,
    PCF8563_REG_CONTROL_STATUS_2 = 0x01,
    PCF8563_REG_VL_SECONDS = 0x02,
    PCF8563_REG_MINUTES = 0x03,
    PCF8563_REG_HOURS = 0x04,
    PCF8563_REG_DAYS = 0x05,
    PCF8563_REG_WEEKDAYS = 0x06,
    PCF8563_REG_CENTURY_MONTHS = 0x07,
    PCF8563_REG_YEARS = 0x08,
};

static int pcf8563_read_reg(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t reg,
                            uint8_t* value);
static int pcf8563_write_reg(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t reg,
                             uint8_t value);
static int pcf8563_read_regs(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t start_reg,
                             uint8_t* buf, size_t len);
static int pcf8563_write_regs(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t start_reg,
                              const uint8_t* buf, size_t len);
static void pcf8563_decode_datetime(const uint8_t* buf, struct tm* now);
static int pcf8563_encode_datetime(const struct tm* dt, uint8_t* buf, size_t len);

static int pcf8563_init(const struct drvfx_device* dev)
{
    const struct pcf8563_config* config = (const struct pcf8563_config*)dev->config;
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;

    rt->lock = xSemaphoreCreateMutexStatic(&rt->lock_buf);
    if (rt->lock == NULL) {
        return -1;
    }

    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    rt->bus = k_device_get_binding(config->bus_name);
    if (rt->bus == NULL) {
        ESP_LOGE(TAG, "Bus device not found: %s", config->bus_name);
        xSemaphoreGive(rt->lock);
        return -ENODEV;
    }

    const struct drvfx_i2c_device_config bus_device_config = {
        .device_address = config->addr,
        .scl_speed_hz = 0,
        .scl_wait_us = 0,
        .dev_addr_length = DRVFX_I2C_ADDR_BIT_LEN_7,
        .disable_ack_check = false,
    };

    ESP_LOGI(TAG, "Attaching PCF8563 bus=%s addr=0x%02x", config->bus_name, config->addr);

    int ret = drvfx_i2c_attach_device(rt->bus, &bus_device_config, &rt->bus_device);
    if (ret != 0) {
        ESP_LOGE(TAG, "Attach failed addr=0x%02x err=%s", config->addr, esp_err_to_name((esp_err_t)ret));
        xSemaphoreGive(rt->lock);
        return ret;
    }

    ESP_LOGI(TAG, "PCF8563 Attached bus=%s addr=0x%02x", config->bus_name, config->addr);
    ESP_LOGI(TAG, "PCF8563 attach complete; probe deferred until first transaction");

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_is_halted(const struct drvfx_device* dev, bool* halted)
{
    const struct pcf8563_config* config = (const struct pcf8563_config*)dev->config;
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t seconds;
    int ret = pcf8563_read_reg(config, rt, PCF8563_REG_VL_SECONDS, &seconds);
    if (ret == 0) {
        *halted = (seconds & 0x80) != 0;
    }

    xSemaphoreGive(rt->lock);
    return ret;
}

static int pcf8563_now(const struct drvfx_device* dev, struct tm* now)
{
    const struct pcf8563_config* config = (const struct pcf8563_config*)dev->config;
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t buf[7];
    int ret = pcf8563_read_regs(config, rt, PCF8563_REG_VL_SECONDS, buf, sizeof(buf));
    if (ret != 0) {
        xSemaphoreGive(rt->lock);
        return ret;
    }

    pcf8563_decode_datetime(buf, now);

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_set_datetime(const struct drvfx_device* dev, const struct tm* dt)
{
    const struct pcf8563_config* config = (const struct pcf8563_config*)dev->config;
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t buf[7];
    int ret = pcf8563_encode_datetime(dt, buf, sizeof(buf));
    if (ret != 0) {
        xSemaphoreGive(rt->lock);
        return ret;
    }

    ret = pcf8563_write_regs(config, rt, PCF8563_REG_VL_SECONDS, buf, sizeof(buf));
    if (ret != 0) {
        xSemaphoreGive(rt->lock);
        return ret;
    }

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_halt(const struct drvfx_device* dev)
{
    const struct pcf8563_config* config = (const struct pcf8563_config*)dev->config;
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t seconds;
    int ret = pcf8563_read_reg(config, rt, PCF8563_REG_VL_SECONDS, &seconds);
    if (ret != 0) {
        xSemaphoreGive(rt->lock);
        return ret;
    }

    seconds |= 0x80;
    ret = pcf8563_write_reg(config, rt, PCF8563_REG_VL_SECONDS, seconds);

    xSemaphoreGive(rt->lock);
    return ret;
}

static int pcf8563_read_reg(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t reg,
                            uint8_t* value)
{
    return drvfx_i2c_transmit_receive(data->bus, data->bus_device, &reg, 1, value, 1, config->timeout);
}

static int pcf8563_write_reg(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t reg,
                             uint8_t value)
{
    uint8_t buf[2] = { reg, value };
    return drvfx_i2c_transmit(data->bus, data->bus_device, buf, sizeof(buf), config->timeout);
}

static int pcf8563_read_regs(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t start_reg,
                             uint8_t* buf, size_t len)
{
    return drvfx_i2c_transmit_receive(data->bus, data->bus_device, &start_reg, 1, buf, len, config->timeout);
}

static int pcf8563_write_regs(const struct pcf8563_config* config, const struct pcf8563_data* data, uint8_t start_reg,
                              const uint8_t* buf, size_t len)
{
    uint8_t tx_buf[8];
    if (len > (sizeof(tx_buf) - 1)) {
        return -EINVAL;
    }

    tx_buf[0] = start_reg;
    memcpy(&tx_buf[1], buf, len);
    return drvfx_i2c_transmit(data->bus, data->bus_device, tx_buf, len + 1, config->timeout);
}

static void pcf8563_decode_datetime(const uint8_t* buf, struct tm* now)
{
    now->tm_sec = BCD2DEC(buf[0] & PCF8563_MASK_SECONDS);
    now->tm_min = BCD2DEC(buf[1] & PCF8563_MASK_MINUTES);
    now->tm_hour = BCD2DEC(buf[2] & PCF8563_MASK_HOURS);
    now->tm_mday = BCD2DEC(buf[3] & PCF8563_MASK_DAYS);
    now->tm_wday = BCD2DEC(buf[4] & PCF8563_MASK_WEEKDAYS);
    now->tm_mon = BCD2DEC(buf[5] & PCF8563_MASK_MONTHS) - 1;
    now->tm_year = BCD2DEC(buf[6]) + ((buf[5] & (1U << PCF8563_BIT_YEAR_CENTURY)) ? 200 : 100);
    now->tm_isdst = -1;
}

static int pcf8563_encode_datetime(const struct tm* dt, uint8_t* buf, size_t len)
{
    if ((dt == NULL) || (buf == NULL) || (len < 7)) {
        return -EINVAL;
    }

    if ((dt->tm_sec < 0) || (dt->tm_sec > 59) || (dt->tm_min < 0) || (dt->tm_min > 59) || (dt->tm_hour < 0)
        || (dt->tm_hour > 23) || (dt->tm_mday < 1) || (dt->tm_mday > 31) || (dt->tm_wday < 0) || (dt->tm_wday > 6)
        || (dt->tm_mon < 0) || (dt->tm_mon > 11) || (dt->tm_year < 100) || (dt->tm_year > 299)) {
        return -EINVAL;
    }

    bool overflow_century = dt->tm_year >= 200;

    buf[0] = DEC2BCD(dt->tm_sec);
    buf[1] = DEC2BCD(dt->tm_min);
    buf[2] = DEC2BCD(dt->tm_hour);
    buf[3] = DEC2BCD(dt->tm_mday);
    buf[4] = DEC2BCD(dt->tm_wday);
    buf[5] = DEC2BCD(dt->tm_mon + 1) | (overflow_century ? (1U << PCF8563_BIT_YEAR_CENTURY) : 0);
    buf[6] = DEC2BCD(dt->tm_year - (overflow_century ? 200 : 100));

    return 0;
}

static const struct pcf8563_config _pcf8563_config = {
    .bus_name = CONFIG_DRIVER_RTC_PCF8563_BUS_NAME,
    .addr = CONFIG_DRIVER_RTC_PCF8563_ADDR,
    .timeout = pdMS_TO_TICKS(CONFIG_DRIVER_RTC_PCF8563_TIMEOUT_MS),
};

static struct pcf8563_data _pcf8563_data = { 0 };

static const char* const _pcf8563_required_devices[] = {
    CONFIG_DRIVER_RTC_PCF8563_BUS_NAME,
};

static const struct rtc_driver_api _pcf8563_api = {
    .now = &pcf8563_now,
    .set_datetime = &pcf8563_set_datetime,
    .is_halted = &pcf8563_is_halted,
    .halt = &pcf8563_halt,
};

DRVFX_DEVICE_DEFINE_WITH_DEPS("rtc_dev", pcf8563_init, &_pcf8563_data, &_pcf8563_config,
                              DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &_pcf8563_api, _pcf8563_required_devices, 1);