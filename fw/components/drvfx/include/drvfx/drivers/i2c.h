#pragma once

#include <errno.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#include <freertos/FreeRTOS.h>

#include "drvfx/drvfx.h"

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device;

enum drvfx_i2c_addr_bit_len {
    DRVFX_I2C_ADDR_BIT_LEN_7 = 7,
    DRVFX_I2C_ADDR_BIT_LEN_10 = 10,
};

struct drvfx_i2c_device_config {
    uint16_t device_address;
    uint32_t scl_speed_hz;
    uint32_t scl_wait_us;
    uint8_t dev_addr_length;
    bool disable_ack_check;
};

struct drvfx_i2c_driver_api {
    int (*attach_device)(const struct drvfx_device* dev, const struct drvfx_i2c_device_config* config, void** handle);
    int (*detach_device)(const struct drvfx_device* dev, void* handle);
    int (*probe)(const struct drvfx_device* dev, uint16_t addr, TickType_t timeout);
    int (*transmit_receive)(const struct drvfx_device* dev, void* handle, const void* tx_buf, size_t tx_len,
                            void* rx_buf, size_t rx_len, TickType_t timeout);
    int (*transmit)(const struct drvfx_device* dev, void* handle, const void* buf, size_t len, TickType_t timeout);
    int (*receive)(const struct drvfx_device* dev, void* handle, void* buf, size_t len, TickType_t timeout);
};

__SYSCALL int drvfx_i2c_attach_device(const struct drvfx_device* dev, const struct drvfx_i2c_device_config* config,
                                      void** handle)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->attach_device == NULL)) {
        return -ENOSYS;
    }

    return api->attach_device(dev, config, handle);
}

__SYSCALL int drvfx_i2c_detach_device(const struct drvfx_device* dev, void* handle)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->detach_device == NULL)) {
        return -ENOSYS;
    }

    return api->detach_device(dev, handle);
}

__SYSCALL int drvfx_i2c_probe(const struct drvfx_device* dev, uint16_t addr, TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->probe == NULL)) {
        return -ENOSYS;
    }

    return api->probe(dev, addr, timeout);
}

__SYSCALL int drvfx_i2c_transmit_receive(const struct drvfx_device* dev, void* handle, const void* tx_buf,
                                         size_t tx_len, void* rx_buf, size_t rx_len, TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->transmit_receive == NULL)) {
        return -ENOSYS;
    }

    return api->transmit_receive(dev, handle, tx_buf, tx_len, rx_buf, rx_len, timeout);
}

__SYSCALL int drvfx_i2c_transmit(const struct drvfx_device* dev, void* handle, const void* buf, size_t len,
                                 TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->transmit == NULL)) {
        return -ENOSYS;
    }

    return api->transmit(dev, handle, buf, len, timeout);
}

__SYSCALL int drvfx_i2c_receive(const struct drvfx_device* dev, void* handle, void* buf, size_t len, TickType_t timeout)
{
    const struct drvfx_i2c_driver_api* api = dev ? dev->api : NULL;
    if ((api == NULL) || (api->receive == NULL)) {
        return -ENOSYS;
    }

    return api->receive(dev, handle, buf, len, timeout);
}

#ifdef __cplusplus
}
#endif