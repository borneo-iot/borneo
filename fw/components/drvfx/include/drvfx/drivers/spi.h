#pragma once

#include <errno.h>
#include <stdint.h>
#include <stddef.h>

#include "drvfx/drvfx.h"

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device;

struct drvfx_spi_device_config {
    int cs_gpio;
    uint32_t clock_hz;
    uint8_t mode;
    uint8_t queue_size;
    uint8_t command_bits;
    uint8_t address_bits;
};

struct drvfx_spi_driver_api {
    int (*acquire)(const struct drvfx_device* dev, const struct drvfx_spi_device_config* config, void** handle);
    int (*release)(const struct drvfx_device* dev, void* handle);
    int (*transceive)(const struct drvfx_device* dev, void* handle, const void* tx_buf, void* rx_buf, size_t len);
};

__SYSCALL int drvfx_spi_acquire(const struct drvfx_device* dev, const struct drvfx_spi_device_config* config,
                                void** handle)
{
    const struct drvfx_spi_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->acquire == NULL)) {
        return -ENOSYS;
    }

    return api->acquire(dev, config, handle);
}

__SYSCALL int drvfx_spi_release(const struct drvfx_device* dev, void* handle)
{
    const struct drvfx_spi_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->release == NULL)) {
        return -ENOSYS;
    }

    return api->release(dev, handle);
}

__SYSCALL int drvfx_spi_transceive(const struct drvfx_device* dev, void* handle, const void* tx_buf, void* rx_buf,
                                   size_t len)
{
    const struct drvfx_spi_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->transceive == NULL)) {
        return -ENOSYS;
    }

    return api->transceive(dev, handle, tx_buf, rx_buf, len);
}

#ifdef __cplusplus
}
#endif