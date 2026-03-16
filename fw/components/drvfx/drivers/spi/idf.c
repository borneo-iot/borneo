#include <driver/spi_master.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#include "drvfx/drivers/spi.h"
#include "drvfx/drvfx.h"

#define TAG "drvfx.spi"

struct drvfx_spi_idf_config {
    spi_host_device_t host;
    int mosi_gpio;
    int miso_gpio;
    int sclk_gpio;
    int max_transfer_sz;
};

struct drvfx_spi_idf_data {
    SemaphoreHandle_t lock;
    StaticSemaphore_t lock_buf;
};

static int drvfx_spi_idf_acquire_impl(const struct drvfx_device* dev, const struct drvfx_spi_device_config* config,
                                      void** handle)
{
    struct drvfx_spi_idf_data* data = (struct drvfx_spi_idf_data*)dev->data;
    if ((config == NULL) || (handle == NULL)) {
        return -EINVAL;
    }

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    spi_device_interface_config_t device_config = {
        .clock_speed_hz = (int)config->clock_hz,
        .mode = config->mode,
        .spics_io_num = config->cs_gpio,
        .queue_size = config->queue_size == 0 ? 1 : config->queue_size,
        .command_bits = config->command_bits,
        .address_bits = config->address_bits,
    };

    const struct drvfx_spi_idf_config* bus_config = (const struct drvfx_spi_idf_config*)dev->config;
    spi_device_handle_t spi_handle = NULL;
    esp_err_t rc = spi_bus_add_device(bus_config->host, &device_config, &spi_handle);
    xSemaphoreGive(data->lock);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to acquire SPI device on %s: %s", dev->name, esp_err_to_name(rc));
        return rc;
    }

    *handle = spi_handle;
    return 0;
}

static int drvfx_spi_idf_release_impl(const struct drvfx_device* dev, void* handle)
{
    struct drvfx_spi_idf_data* data = (struct drvfx_spi_idf_data*)dev->data;
    if (handle == NULL) {
        return -EINVAL;
    }

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    esp_err_t rc = spi_bus_remove_device((spi_device_handle_t)handle);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_spi_idf_transceive_impl(const struct drvfx_device* dev, void* handle, const void* tx_buf, void* rx_buf,
                                         size_t len)
{
    struct drvfx_spi_idf_data* data = (struct drvfx_spi_idf_data*)dev->data;
    if ((handle == NULL) || (len == 0)) {
        return -EINVAL;
    }

    if (xSemaphoreTake(data->lock, portMAX_DELAY) != pdTRUE) {
        return -1;
    }

    spi_transaction_t transaction = {
        .length = len * 8,
        .tx_buffer = tx_buf,
        .rx_buffer = rx_buf,
    };
    esp_err_t rc = spi_device_transmit((spi_device_handle_t)handle, &transaction);
    xSemaphoreGive(data->lock);
    return rc;
}

static int drvfx_spi_idf_init(const struct drvfx_device* dev)
{
    const struct drvfx_spi_idf_config* config = (const struct drvfx_spi_idf_config*)dev->config;
    struct drvfx_spi_idf_data* data = (struct drvfx_spi_idf_data*)dev->data;

    data->lock = xSemaphoreCreateMutexStatic(&data->lock_buf);
    if (data->lock == NULL) {
        return -1;
    }

    spi_bus_config_t bus_config = {
        .mosi_io_num = config->mosi_gpio,
        .miso_io_num = config->miso_gpio,
        .sclk_io_num = config->sclk_gpio,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = config->max_transfer_sz,
    };

    esp_err_t rc = spi_bus_initialize(config->host, &bus_config, SPI_DMA_CH_AUTO);
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize %s: %s", dev->name, esp_err_to_name(rc));
        return rc;
    }

    return 0;
}

static const struct drvfx_spi_idf_config s_spi0_config = {
    .host = CONFIG_DRVFX_SPI0_HOST,
    .mosi_gpio = CONFIG_DRVFX_SPI0_MOSI_GPIO,
    .miso_gpio = CONFIG_DRVFX_SPI0_MISO_GPIO,
    .sclk_gpio = CONFIG_DRVFX_SPI0_SCLK_GPIO,
    .max_transfer_sz = CONFIG_DRVFX_SPI0_MAX_TRANSFER_SZ,
};

static struct drvfx_spi_idf_data s_spi0_data = { 0 };

static const struct drvfx_spi_driver_api s_spi_api = {
    .acquire = drvfx_spi_idf_acquire_impl,
    .release = drvfx_spi_idf_release_impl,
    .transceive = drvfx_spi_idf_transceive_impl,
};

DRVFX_NAMED_DEVICE_DEFINE(spi0, CONFIG_DRVFX_SPI0_NAME, drvfx_spi_idf_init, &s_spi0_data, &s_spi0_config,
                          DRVFX_INIT_POST_KERNEL_HIGH_PRIORITY, &s_spi_api);