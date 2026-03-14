
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stddef.h>
#include <assert.h>
#include <time.h>

#include <driver/gpio.h>
#include <driver/i2c.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include "drvfx/drvfx.h"
#include "drvfx/drivers/rtc.h"

#ifdef CONFIG_DRIVER_RTC_PCF8563

#define DEC2BCD(dec) ((dec / 10 * 16) + (dec % 10))
#define BCD2DEC(bcd) ((bcd / 16 * 10) + (bcd % 16))

struct pcf8563_config {
    // TODO: configurable I2C port and address
};

struct pcf8563_data {
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

// TODO: make configurable
#define PCF8563_I2C_PORT CONFIG_DRIVER_RTC_PCF8563_I2C_PORT
#define PCF8563_I2C_ADDR CONFIG_DRIVER_RTC_PCF8563_ADDR

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

static int pcf8563_read_reg(uint8_t reg, uint8_t* value);
static int pcf8563_write_reg(uint8_t reg, uint8_t value);

static int pcf8563_init(const struct drvfx_device* dev)
{
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;

    rt->lock = xSemaphoreCreateBinaryStatic(&rt->lock_buf);
    if (rt->lock == NULL) {
        return -1;
    }

    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    // Initialize I2C
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = CONFIG_DRIVER_RTC_PCF8563_SDA_GPIO,
        .scl_io_num = CONFIG_DRIVER_RTC_PCF8563_SCL_GPIO,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 100000, // 100kHz
    };
    esp_err_t ret = i2c_param_config(PCF8563_I2C_PORT, &conf);
    if (ret != ESP_OK) {
        xSemaphoreGive(rt->lock);
        return -1;
    }
    ret = i2c_driver_install(PCF8563_I2C_PORT, conf.mode, 0, 0, 0);
    if (ret != ESP_OK) {
        xSemaphoreGive(rt->lock);
        return -1;
    }

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_is_halted(const struct drvfx_device* dev, bool* halted)
{
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t seconds;
    int ret = pcf8563_read_reg(PCF8563_REG_VL_SECONDS, &seconds);
    if (ret == 0) {
        *halted = (seconds & 0x80) != 0;
    }

    xSemaphoreGive(rt->lock);
    return ret;
}

static int pcf8563_now(const struct drvfx_device* dev, struct tm* now)
{
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t buf[7];
    // Read from VL_SECONDS to YEARS
    for (int i = 0; i < 7; i++) {
        int ret = pcf8563_read_reg(PCF8563_REG_VL_SECONDS + i, &buf[i]);
        if (ret != 0) {
            xSemaphoreGive(rt->lock);
            return ret;
        }
    }

    now->tm_sec = BCD2DEC(buf[0] & 0x7F);
    now->tm_min = BCD2DEC(buf[1] & 0x7F);
    now->tm_hour = BCD2DEC(buf[2] & 0x3F);
    now->tm_mday = BCD2DEC(buf[3] & 0x3F);
    now->tm_wday = BCD2DEC(buf[4] & 0x07);
    now->tm_mon = BCD2DEC(buf[5] & 0x1F) - 1;
    now->tm_year = BCD2DEC(buf[6]) + 100; // Assuming 2000+
    now->tm_isdst = -1;

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_set_datetime(const struct drvfx_device* dev, const struct tm* dt)
{
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t buf[7];
    buf[0] = DEC2BCD(dt->tm_sec % 60);
    buf[1] = DEC2BCD(dt->tm_min % 60);
    buf[2] = DEC2BCD(dt->tm_hour % 24);
    buf[3] = DEC2BCD(dt->tm_mday % 32);
    buf[4] = DEC2BCD(dt->tm_wday % 7);
    buf[5] = DEC2BCD((dt->tm_mon + 1) % 13);
    buf[6] = DEC2BCD(dt->tm_year % 100);

    for (int i = 0; i < 7; i++) {
        int ret = pcf8563_write_reg(PCF8563_REG_VL_SECONDS + i, buf[i]);
        if (ret != 0) {
            xSemaphoreGive(rt->lock);
            return ret;
        }
    }

    xSemaphoreGive(rt->lock);
    return 0;
}

static int pcf8563_halt(const struct drvfx_device* dev)
{
    struct pcf8563_data* rt = (struct pcf8563_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint8_t seconds;
    int ret = pcf8563_read_reg(PCF8563_REG_VL_SECONDS, &seconds);
    if (ret != 0) {
        xSemaphoreGive(rt->lock);
        return ret;
    }

    seconds |= 0x80;
    ret = pcf8563_write_reg(PCF8563_REG_VL_SECONDS, seconds);

    xSemaphoreGive(rt->lock);
    return ret;
}

static int pcf8563_read_reg(uint8_t reg, uint8_t* value)
{
    return i2c_master_write_read_device(PCF8563_I2C_PORT, PCF8563_I2C_ADDR, &reg, 1, value, 1, pdMS_TO_TICKS(1000));
}

static int pcf8563_write_reg(uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = { reg, value };
    return i2c_master_write_to_device(PCF8563_I2C_PORT, PCF8563_I2C_ADDR, buf, 2, pdMS_TO_TICKS(1000));
}

static const struct pcf8563_config _pcf8563_config = {};

static struct pcf8563_data _pcf8563_data = { 0 };

static const struct rtc_driver_api _pcf8563_api = {
    .now = &pcf8563_now,
    .set_datetime = &pcf8563_set_datetime,
    .is_halted = &pcf8563_is_halted,
    .halt = &pcf8563_halt,
};

DRVFX_DEVICE_DEFINE("rtc_dev", pcf8563_init, &_pcf8563_data, &_pcf8563_config, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY,
                    &_pcf8563_api);

#endif // CONFIG_DRIVER_RTC_PCF8563