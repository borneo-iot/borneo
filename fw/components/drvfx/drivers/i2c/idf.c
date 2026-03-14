#include <driver/gpio.h>
#include <driver/i2c.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <stdbool.h>

#include "drvfx/drivers/i2c.h"
#include "drvfx/drvfx.h"

#ifdef CONFIG_DRVFX_I2C_IDF

#define TAG "drvfx.i2c"

struct drvfx_i2c_idf_config {
    i2c_port_t port;
    gpio_num_t sda_gpio;
    gpio_num_t scl_gpio;
    uint32_t freq_hz;
    bool pullup;
};

struct drvfx_i2c_idf_data {
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

static int drvfx_i2c_idf_write_read_impl(const struct drvfx_device* dev, uint16_t addr, const void* tx_buf,
                                         size_t tx_len, void* rx_buf, size_t rx_len, TickType_t timeout)
{
    const struct drvfx_i2c_idf_config* config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = i2c_master_write_read_device(config->port, addr, tx_buf, tx_len, rx_buf, rx_len, timeout);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_i2c_idf_write_impl(const struct drvfx_device* dev, uint16_t addr, const void* buf, size_t len,
                                    TickType_t timeout)
{
    const struct drvfx_i2c_idf_config* config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = i2c_master_write_to_device(config->port, addr, buf, len, timeout);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_i2c_idf_read_impl(const struct drvfx_device* dev, uint16_t addr, void* buf, size_t len,
                                   TickType_t timeout)
{
    const struct drvfx_i2c_idf_config* config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = i2c_master_read_from_device(config->port, addr, buf, len, timeout);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_i2c_idf_init(const struct drvfx_device* dev)
{
    const struct drvfx_i2c_idf_config* config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    data->lock = xSemaphoreCreateMutexStatic(&data->lock_buf);
    if (data->lock == NULL) {
        return -1;
    }

    i2c_config_t bus_config = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = config->sda_gpio,
        .scl_io_num = config->scl_gpio,
        .sda_pullup_en = config->pullup ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE,
        .scl_pullup_en = config->pullup ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE,
        .master.clk_speed = config->freq_hz,
    };

    esp_err_t rc = i2c_param_config(config->port, &bus_config);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure %s: %s", dev->name, esp_err_to_name(rc));
        return rc;
    }

    rc = i2c_driver_install(config->port, bus_config.mode, 0, 0, 0);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install %s: %s", dev->name, esp_err_to_name(rc));
        return rc;
    }

    return 0;
}

static const struct drvfx_i2c_idf_config s_i2c0_config = {
    .port = CONFIG_DRVFX_I2C0_PORT,
    .sda_gpio = CONFIG_DRVFX_I2C0_SDA_GPIO,
    .scl_gpio = CONFIG_DRVFX_I2C0_SCL_GPIO,
    .freq_hz = CONFIG_DRVFX_I2C0_FREQ_HZ,
    .pullup = CONFIG_DRVFX_I2C0_PULLUP,
};

static struct drvfx_i2c_idf_data s_i2c0_data = { 0 };

static const struct drvfx_i2c_driver_api s_i2c_api = {
    .write_read = drvfx_i2c_idf_write_read_impl,
    .write = drvfx_i2c_idf_write_impl,
    .read = drvfx_i2c_idf_read_impl,
};

DRVFX_NAMED_DEVICE_DEFINE(i2c0, CONFIG_DRVFX_I2C0_NAME, drvfx_i2c_idf_init, &s_i2c0_data, &s_i2c0_config,
                          DRVFX_INIT_POST_KERNEL_HIGH_PRIORITY, &s_i2c_api);

#endif