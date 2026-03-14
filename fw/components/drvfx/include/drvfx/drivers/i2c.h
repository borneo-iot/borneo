#pragma once

#include <errno.h>
#include <stdint.h>
#include <stddef.h>

#include <freertos/FreeRTOS.h>

#include "drvfx/drvfx.h"

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device;

struct drvfx_i2c_driver_api {
    int (*write_read)(const struct drvfx_device* dev, uint16_t addr, const void* tx_buf, size_t tx_len, void* rx_buf,
                      size_t rx_len, TickType_t timeout);
    int (*write)(const struct drvfx_device* dev, uint16_t addr, const void* buf, size_t len, TickType_t timeout);
    int (*read)(const struct drvfx_device* dev, uint16_t addr, void* buf, size_t len, TickType_t timeout);
};

__SYSCALL int drvfx_i2c_write_read(const struct drvfx_device* dev, uint16_t addr, const void* tx_buf, size_t tx_len,
                                   void* rx_buf, size_t rx_len, TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->write_read == NULL)) {
        return -ENOSYS;
    }

    return api->write_read(dev, addr, tx_buf, tx_len, rx_buf, rx_len, timeout);
}

__SYSCALL int drvfx_i2c_write(const struct drvfx_device* dev, uint16_t addr, const void* buf, size_t len,
                              TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->write == NULL)) {
        return -ENOSYS;
    }

    return api->write(dev, addr, buf, len, timeout);
}

__SYSCALL int drvfx_i2c_read(const struct drvfx_device* dev, uint16_t addr, void* buf, size_t len, TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->read == NULL)) {
        return -ENOSYS;
    }

    return api->read(dev, addr, buf, len, timeout);
}

#ifdef __cplusplus
}
#endif