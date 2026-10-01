#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device;

struct sensor_api {
    int (*fetch_sample)(const struct drvfx_device* dev);
    int (*get_value)(const struct drvfx_device* dev, int32_t* value);
};

struct sensor_runtime {
    bool valid;
    int16_t last_error;
    uint16_t failures;
};

__SYSCALL int sensor_fetch_sample(const struct drvfx_device* dev)
{
    const struct sensor_api* api = dev ? dev->api : NULL;
    if (api == NULL) {
        return -ENOSYS;
    }
    return api->fetch_sample(dev);
}

__SYSCALL int sensor_get_value(const struct drvfx_device* dev, int32_t* value)
{
    const struct sensor_api* api = dev ? dev->api : NULL;
    if (api == NULL) {
        return -ENOSYS;
    }
    return api->get_value(dev, value);
}

__SYSCALL void sensor_runtime_ok(struct sensor_runtime* runtime)
{
    runtime->valid = true;
    runtime->last_error = 0;
    runtime->failures = 0;
}

__SYSCALL void sensor_runtime_error(struct sensor_runtime* runtime, int error)
{
    runtime->valid = false;
    runtime->last_error = (int16_t)error;
    if (runtime->failures != UINT16_MAX) {
        runtime->failures++;
    }
}

#ifdef __cplusplus
}
#endif