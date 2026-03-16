#include <driver/i2c_master.h>
#include <esp_err.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <stdbool.h>

#include "drvfx/drivers/i2c.h"
#include "drvfx/drvfx.h"

#define TAG "drvfx.i2c"

struct drvfx_i2c_idf_config {
    i2c_port_num_t port;
    gpio_num_t sda_gpio;
    gpio_num_t scl_gpio;
    uint32_t freq_hz;
    bool pullup;
};

struct drvfx_i2c_idf_data {
    i2c_master_bus_handle_t bus_handle;
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

static int drvfx_i2c_timeout_ms(TickType_t timeout)
{
    if (timeout == portMAX_DELAY) {
        return -1;
    }

    return (int)pdTICKS_TO_MS(timeout);
}

static i2c_addr_bit_len_t drvfx_i2c_addr_len_to_idf(uint8_t len)
{
    return len == DRVFX_I2C_ADDR_BIT_LEN_10 ? I2C_ADDR_BIT_LEN_10 : I2C_ADDR_BIT_LEN_7;
}

static int drvfx_i2c_idf_attach_device_impl(const struct drvfx_device* dev,
                                            const struct drvfx_i2c_device_config* config, void** handle)
{
    const struct drvfx_i2c_idf_config* bus_config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if ((config == NULL) || (handle == NULL)) {
        return ESP_ERR_INVALID_ARG;
    }

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    i2c_device_config_t device_config = {
        .dev_addr_length = drvfx_i2c_addr_len_to_idf(config->dev_addr_length),
        .device_address = config->device_address,
        .scl_speed_hz = config->scl_speed_hz == 0 ? bus_config->freq_hz : config->scl_speed_hz,
        .scl_wait_us = config->scl_wait_us,
        .flags.disable_ack_check = config->disable_ack_check,
    };

    i2c_master_dev_handle_t device_handle = NULL;
    esp_err_t rc = i2c_master_bus_add_device(data->bus_handle, &device_config, &device_handle);
    xSemaphoreGive(data->lock);

    if (rc == ESP_OK) {
        *handle = device_handle;
    }

    return rc;
}

static int drvfx_i2c_idf_detach_device_impl(const struct drvfx_device* dev, void* handle)
{
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if (handle == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = i2c_master_bus_rm_device((i2c_master_dev_handle_t)handle);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_i2c_idf_probe_impl(const struct drvfx_device* dev, uint16_t addr, TickType_t timeout)
{
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = i2c_master_probe(data->bus_handle, addr, drvfx_i2c_timeout_ms(timeout));
    xSemaphoreGive(data->lock);

    if (rc == ESP_OK) {
        ESP_LOGI(TAG, "Probe ok bus=%s addr=0x%02x", dev->name, addr);
    }
    else {
        ESP_LOGE(TAG, "Probe failed bus=%s addr=0x%02x err=%s", dev->name, addr, esp_err_to_name(rc));
    }

    return rc;
}

static int drvfx_i2c_idf_transmit_receive_impl(const struct drvfx_device* dev, void* handle, const void* tx_buf,
                                               size_t tx_len, void* rx_buf, size_t rx_len, TickType_t timeout)
{
    (void)dev;

    if (handle == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    return i2c_master_transmit_receive((i2c_master_dev_handle_t)handle, tx_buf, tx_len, rx_buf, rx_len,
                                       drvfx_i2c_timeout_ms(timeout));
}

static int drvfx_i2c_idf_transmit_impl(const struct drvfx_device* dev, void* handle, const void* buf, size_t len,
                                       TickType_t timeout)
{
    (void)dev;

    if (handle == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    return i2c_master_transmit((i2c_master_dev_handle_t)handle, buf, len, drvfx_i2c_timeout_ms(timeout));
}

static int drvfx_i2c_idf_receive_impl(const struct drvfx_device* dev, void* handle, void* buf, size_t len,
                                      TickType_t timeout)
{
    (void)dev;

    if (handle == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    return i2c_master_receive((i2c_master_dev_handle_t)handle, buf, len, drvfx_i2c_timeout_ms(timeout));
}

static int drvfx_i2c_idf_init(const struct drvfx_device* dev)
{
    const struct drvfx_i2c_idf_config* config = (const struct drvfx_i2c_idf_config*)dev->config;
    struct drvfx_i2c_idf_data* data = (struct drvfx_i2c_idf_data*)dev->data;

    data->lock = xSemaphoreCreateMutexStatic(&data->lock_buf);
    if (data->lock == NULL) {
        return -1;
    }

    i2c_master_bus_config_t bus_config = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = config->port,
        .sda_io_num = config->sda_gpio,
        .scl_io_num = config->scl_gpio,
        .glitch_ignore_cnt = 7,
        .intr_priority = 0,
        .trans_queue_depth = 0,
        .flags.enable_internal_pullup = config->pullup,
        .flags.allow_pd = false,
    };

    esp_err_t rc = i2c_new_master_bus(&bus_config, &data->bus_handle);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize %s: %s", dev->name, esp_err_to_name(rc));
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
    .attach_device = drvfx_i2c_idf_attach_device_impl,
    .detach_device = drvfx_i2c_idf_detach_device_impl,
    .probe = drvfx_i2c_idf_probe_impl,
    .transmit_receive = drvfx_i2c_idf_transmit_receive_impl,
    .transmit = drvfx_i2c_idf_transmit_impl,
    .receive = drvfx_i2c_idf_receive_impl,
};

DRVFX_NAMED_DEVICE_DEFINE(i2c0, CONFIG_DRVFX_I2C0_NAME, drvfx_i2c_idf_init, &s_i2c0_data, &s_i2c0_config,
                          DRVFX_INIT_POST_KERNEL_HIGH_PRIORITY, &s_i2c_api);