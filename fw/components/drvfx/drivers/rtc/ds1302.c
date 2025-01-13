
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stddef.h>
#include <assert.h>
#include <time.h>

#include <driver/gpio.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>

#include "drvfx/drvfx.h"
#include "drvfx/drivers/rtc.h"

#ifdef CONFIG_DRIVER_RTC_DS1302_ENABLED


#define DEC2BCD(dec) ((dec / 10 * 16) + (dec % 10))

#define BCD2DEC(bcd) ((bcd / 16 * 10) + (bcd % 16))

struct ds1302_config {
    // struct i2c_dt_spec bus;
    // struct gpio_dt_spec isw_gpios;
};

struct ds1302_data {
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

// TODO FXIME configurable
#define PIN_CE 13
#define PIN_CLK 14
#define PIN_IO 12

enum {
    DS1302_REG_SECONDS = 0x80,
    DS1302_REG_MINUTES = 0x82,
    DS1302_REG_HOUR = 0x84,
    DS1302_REG_DATE = 0x86,
    DS1302_REG_MONTH = 0x88,
    DS1302_REG_DAY = 0x8A,
    DS1302_REG_YEAR = 0x8C,
    DS1302_REG_WP = 0x8E,
    DS1302_REG_BURST = 0xBE,
    DS1302_REG_TRICKLE_CHARGER = 0x90
};

static int begin_read(uint8_t address);
static int begin_write(uint8_t address);
static uint8_t read_byte();
static int write_byte(uint8_t value);
static int next_bit();
static int end_io();
static int ds1302_set_trickle_charger(uint8_t value);

static int ds1302_init(const struct drvfx_device* dev)
{
    struct ds1302_data* rt = (struct ds1302_data*)dev->data;

    rt->lock = xSemaphoreCreateBinaryStatic(&rt->lock_buf);
    if (rt->lock == NULL) {
        return -1;
    }

    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    uint64_t pins_mask = (1ULL << PIN_CE) | (1ULL << PIN_CLK);
    // 初始化 GPIO
    gpio_config_t io_conf;

    // 初始化输出端口
    io_conf.intr_type = GPIO_INTR_DISABLE; // 禁止中断
    io_conf.mode = GPIO_MODE_OUTPUT; // 输出模式
    io_conf.pin_bit_mask = pins_mask; // 选定端口
    io_conf.pull_down_en = 1; // 打开下拉
    io_conf.pull_up_en = 0; // 禁止上拉
    K_TRY_OR_UNLOCK(gpio_config(&io_conf), rt->lock);

    pins_mask = (1ULL << PIN_IO);
    io_conf.intr_type = GPIO_INTR_DISABLE; // disable interrupt
    io_conf.mode = GPIO_MODE_INPUT_OUTPUT; // 模式
    io_conf.pin_bit_mask = pins_mask; // 选定端口
    io_conf.pull_down_en = 0; // 下拉
    io_conf.pull_up_en = 0; // 上拉
    K_TRY_OR_UNLOCK(gpio_config(&io_conf), rt->lock);

    K_TRY_OR_UNLOCK(gpio_set_level(PIN_CE, 0), rt->lock);
    K_TRY_OR_UNLOCK(gpio_set_level(PIN_CLK, 0), rt->lock);

    // 为超级电容打开涓流充电器，如果是锂电池，需要不同的参数
    // Maximum 1 Diode, 2kOhm
    ds1302_set_trickle_charger(0xA5);

    // 充电电池参考下面的参数
    // Minimum 2 Diodes, 8kOhm
    // DS1302_set_trickle_charger(0xAB);

    xSemaphoreGive(rt->lock);
    return 0;
}

static int ds1302_is_halted(const struct drvfx_device* dev, bool* halted)
{
    struct ds1302_data* rt = (struct ds1302_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    K_TRY_OR_UNLOCK(begin_read(DS1302_REG_SECONDS), rt->lock);
    uint8_t seconds = read_byte();
    K_TRY_OR_UNLOCK(end_io(), rt->lock);
    *halted = (seconds & 0b10000000);

    xSemaphoreGive(rt->lock);
    return 0;
}

static int ds1302_now(const struct drvfx_device* dev, struct tm* now)
{
    struct ds1302_data* rt = (struct ds1302_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    K_TRY_OR_UNLOCK(begin_read(DS1302_REG_BURST), rt->lock);
    now->tm_sec = (uint8_t)BCD2DEC(read_byte() & 0b01111111);
    now->tm_min = (uint8_t)BCD2DEC(read_byte() & 0b01111111);
    now->tm_hour = (uint8_t)BCD2DEC(read_byte() & 0b00111111);
    now->tm_mday = (uint8_t)BCD2DEC(read_byte() & 0b00111111);
    now->tm_mon = (uint8_t)BCD2DEC(read_byte() & 0b00011111) - 1;
    now->tm_wday = (uint8_t)BCD2DEC(read_byte() & 0b00000111) % 7;
    now->tm_year = 100 + (uint8_t)BCD2DEC(read_byte() & 0b01111111);
    now->tm_isdst = -1;
    K_TRY_OR_UNLOCK(end_io(), rt->lock);

    xSemaphoreGive(rt->lock);
    return 0;
}

static int ds1302_set_datetime(const struct drvfx_device* dev, const struct tm* dt)
{
    struct ds1302_data* rt = (struct ds1302_data*)dev->data;
    if (xSemaphoreTake(rt->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    K_TRY_OR_UNLOCK(begin_write(DS1302_REG_WP), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(0b00000000), rt->lock);
    K_TRY_OR_UNLOCK(end_io(), rt->lock);

    K_TRY_OR_UNLOCK(begin_write(DS1302_REG_BURST), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_sec % 60)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_min % 60)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_hour % 24)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_mday % 32)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD((dt->tm_mon + 1) % 13)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_wday == 0 ? 7 : dt->tm_wday)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(DEC2BCD(dt->tm_year % 100)), rt->lock);
    K_TRY_OR_UNLOCK(write_byte(0b10000000), rt->lock);
    K_TRY_OR_UNLOCK(end_io(), rt->lock);

    xSemaphoreGive(rt->lock);
    return 0;
}

static int ds1302_halt()
{
    K_TRY(begin_write(DS1302_REG_SECONDS));
    K_TRY(write_byte(0b10000000));
    K_TRY(end_io());
    return 0;
}

static int ds1302_set_trickle_charger(uint8_t value)
{
    K_TRY(begin_write(DS1302_REG_TRICKLE_CHARGER));
    K_TRY(write_byte(value));
    K_TRY(end_io());
    return 0;
}

static int begin_read(uint8_t address)
{
    K_TRY(gpio_set_direction(PIN_IO, GPIO_MODE_OUTPUT));
    K_TRY(gpio_set_level(PIN_CE, 1));
    uint8_t command = 0b10000001 | address;
    K_TRY(write_byte(command));
    K_TRY(gpio_set_direction(PIN_IO, GPIO_MODE_INPUT));
    return 0;
}

static int begin_write(uint8_t address)
{
    K_TRY(gpio_set_direction(PIN_IO, GPIO_MODE_OUTPUT));
    K_TRY(gpio_set_level(PIN_CE, 1));
    uint8_t command = 0b10000000 | address;
    K_TRY(write_byte(command));
    return 0;
}

static int end_io()
{
    // CE 脚设置低电平
    K_TRY(gpio_set_level(PIN_CE, 0));
    return 0;
}

static uint8_t read_byte()
{
    uint8_t byte = 0;

    for (uint8_t b = 0; b < 8; b++) {
        if (gpio_get_level(PIN_IO)) {
            byte |= 0x01 << b;
        }
        next_bit();
    }

    return byte;
}

static int write_byte(uint8_t value)
{
    for (uint8_t b = 0; b < 8; b++) {
        int bit = value & 0x01;
        K_TRY(gpio_set_level(PIN_IO, bit));
        K_TRY(next_bit());
        value >>= 1;
    }
    return 0;
}

static int next_bit()
{
    K_TRY(gpio_set_level(PIN_CLK, 1));
    esp_rom_delay_us(5);

    K_TRY(gpio_set_level(PIN_CLK, 0));
    esp_rom_delay_us(5);

    return 0;
}


static const struct ds1302_config _ds1302_config = {};

static struct ds1302_data _ds1302_data = { 0 };

static const struct rtc_driver_api _ds1302_api = {
    .now = &ds1302_now,
    .set_datetime = &ds1302_set_datetime,
    .is_halted = &ds1302_is_halted,
    .halt = &ds1302_halt,
};


DRVFX_DEVICE_DEFINE("ds1302", ds1302_init, &_ds1302_data, &_ds1302_config, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY,
                    &_ds1302_api);

#endif