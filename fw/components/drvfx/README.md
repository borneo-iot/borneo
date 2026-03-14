# DRVFX: ESP-IDF modular device driver framework

## Overview

Borrowed from Zephyr RTOS: an ESP-IDF modular device driver framework.

## Purpose

This component provides a small, modular driver/kernel abstraction for device drivers used by the project. It centralizes device registration, initialization, and driver interfaces so platform drivers can be developed and reused consistently.

It is not a hardware abstraction layer for every ESP-IDF peripheral. The intended split is:

- bus controller drivers own shared resources such as I2C and SPI hosts;
- peripheral drivers bind to those bus devices by name and only implement device-specific behavior.

## Layout

- `include/drvfx/`: public headers for the framework and drivers.
- `drivers/`: example and platform drivers (RTC driver located under `drivers/rtc`).
- `kernel/`: core implementation (kernel/device/init source files).
- `LICENSE.txt`: licensing for this component.

Key headers are under `include/drvfx/kernel` and `include/drvfx/drivers` and provide the API surface for integrating drivers.

## Usage

Add the component to your ESP-IDF project as usual (CMake/IDF component). Include the public headers from `include/drvfx` and use the provided kernel/device APIs to register and manage drivers. Consult the `drivers/` directory for usage examples.

### Subsystem init

Use `DRVFX_SUBSYS_INIT` to register a subsystem initialization function that runs at the POST_KERNEL stage. The init function signature is:

```c
int init_fn(const struct drvfx_device *dev);
```

For subsystem entries `dev` will be NULL. Return 0 on success; non-zero indicates failure. Priority controls ordering (use constants like `DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY`).

Example:

```c
/* module.c */
#include <drvfx/kernel/init.h>

static int my_subsys_init(const struct drvfx_device *dev)
{
    (void)dev; /* subsys entries have no device */
    /* perform subsystem setup here */
    return 0;
}

/* Register the subsystem init at post-kernel default priority */
DRVFX_SUBSYS_INIT(my_subsys_init, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY);
```

Notes:

- Use `DRVFX_SYS_INIT` / `DRVFX_SYS_INIT_NAMED` when you need a system init entry associated with the init function name.
- Subsystem inits run automatically as part of the `drvfx` startup path. `k_init()` initializes kernel state, and the framework then runs EARLY/PRE_KERNEL/POST_KERNEL/APPLICATION entries in order.
- After init, use `k_device_get_binding()` and `k_device_is_ready()` to access devices.

### Device dependencies

When a device depends on another registered device, declare the dependency names with `DRVFX_DEVICE_DEFINE_WITH_DEPS` or `DRVFX_NAMED_DEVICE_DEFINE_WITH_DEPS`.

If any dependency is missing or not ready at init time, the framework now fails that device initialization with an explicit log instead of silently continuing.

This is intentionally lightweight: ordering is still controlled by init priority, but the dependency list makes failures obvious and keeps child devices from probing a bus/controller that never came up.

### Bus drivers

`drvfx` now exposes dedicated bus APIs in `include/drvfx/drivers/i2c.h` and `include/drvfx/drivers/spi.h`.

- I2C controllers own controller setup, locking, and transfers.
- SPI controllers own host setup and per-device attachment handles.
- Peripheral drivers such as RTCs should depend on the bus device and use the bus API instead of directly installing the underlying ESP-IDF driver.

## Driver development example — foo

This example shows a minimal driver API for a device type `foo` whose API exposes a single function `foo_read(dev, buf, size)`.

Header (`foo.h`):

```c
#pragma once

#include <errno.h>
#include <drvfx/drvfx.h>

#ifdef __cplusplus
extern "C" {
#endif

struct foo_api {
    int (*read)(const struct drvfx_device *dev, void *buf, size_t size);
};

/* User-land API: forwards the call to the driver implementation. */
static inline int foo_read(const struct drvfx_device *dev, void *buf, size_t size)
{
    const struct foo_api *api = (const struct foo_api *)dev->api;
    return api->read(dev, buf, size);
}

#ifdef __cplusplus
}
#endif
```

Driver implementation (`foo.c`):

```c
#include <drvfx/drvfx.h>

static int foo_read_impl(const struct drvfx_device *dev, void *buf, size_t size)
{
    (void)dev;
    /* perform read into buf up to size bytes */
    return 0; /* return number of bytes read or negative on error */
}

static int foo_init(const struct drvfx_device *dev)
{
    (void)dev;
    /* hardware init for foo */
    return 0;
}

static const struct foo_api foo_api_impl = {
    .read = foo_read_impl,
};

/* Define a static device and attach the API pointer */
DRVFX_DEVICE_DEFINE(
    "foo0",
    foo_init,
    NULL,
    NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY,
    &foo_api_impl
);
```

Runtime usage:

```c
#include <drvfx/drvfx.h>
#include "your_drivers_dir/foo.h"

void drvfx_app_main(void)
{
    const struct drvfx_device *dev = k_device_get_binding("foo0");
    if (dev && k_device_is_ready(dev)) {
        const struct foo_api *api = (const struct foo_api *)dev->api;
        if (api && api->read) {
            char buf[32];
            int rc = api->read(dev, buf, sizeof(buf));
            // ...
        }
    }
}
```

Notes:

- Place the API definition in a public header, like under `include/your_porj/drivers/` so consumers can include it.
- Provide driver-specific `init` that sets up hardware and returns `0` on success.
- Attach the API pointer as the last argument to `DRVFX_DEVICE_DEFINE` so callers can cast `dev->api` to the driver API.

## Contributing / Contact

Follow the repository contribution guidelines. Open an issue or pull request in the main repository for feedback or improvements.

## License

This component is licensed in Apache 2.0 License.
See `LICENSE.txt` in this component for licensing details.

Copyright (C) 2024-TODAY Yunnan BinaryStars Technologies, Co., Ltd. All rights reserved.
