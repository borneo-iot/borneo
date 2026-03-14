#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device_state {
    int init_res;
    bool initialized;
};

struct drvfx_device {
    const char* name;
    const void* config;
    const void* api;
    const char* const* required_devices;
    size_t required_device_count;
    struct drvfx_device_state* state;
    void* const data;
};

#define __DRVFX_DEVICE_MAKE_UNIQUE_TOKEN(x, y) _CONCAT(x, y)

#define DRVFX_DEVICE_NAME_GET(dev_id) _CONCAT(__device_, dev_id)

#define DRVFX_DEVICE_STATE_NAME(dev_id) _CONCAT(__devstate_, dev_id)

#define DRVFX_DEVICE_STATE_DEFINE(dev_id)                                                                              \
    static DRVFX_DECL_ALIGN(struct drvfx_device_state) DRVFX_DEVICE_STATE_NAME(dev_id)

#define DRVFX_DEVICE_SECTION(prio) __attribute__((__section__(".drvfx_device." _STRINGIFY(prio) "_")))

#define DRVFX_DEVICE_BASE_DEFINE(dev_id_, name_, init_fn_, data_, config_, prio_, api_, deps_, dep_count_)             \
    DRVFX_DEVICE_STATE_DEFINE(dev_id_);                                                                                \
    static const DRVFX_DECL_ALIGN(struct drvfx_device) DRVFX_DEVICE_SECTION(prio_)                                     \
        DRVFX_USED __DRVFX_NOASAN DRVFX_DEVICE_NAME_GET(dev_id_)                                                       \
        = {                                                                                                            \
              .name = (name_),                                                                                         \
              .config = (config_),                                                                                     \
              .api = (api_),                                                                                           \
              .required_devices = (deps_),                                                                             \
              .required_device_count = (dep_count_),                                                                   \
              .state = &(DRVFX_DEVICE_STATE_NAME(dev_id_)),                                                            \
              .data = (data_),                                                                                         \
          };                                                                                                           \
    DRVFX_INIT_ENTRY_DEFINE(DRVFX_DEVICE_NAME_GET(dev_id_), init_fn_, &DRVFX_DEVICE_NAME_GET(dev_id_), POST_KERNEL,    \
                            prio_)

#define DRVFX_NAMED_DEVICE_DEFINE(dev_id, name, init_fn, data, config, prio, api)                                      \
    DRVFX_DEVICE_BASE_DEFINE(dev_id, name, init_fn, data, config, prio, api, NULL, 0)

#define DRVFX_NAMED_DEVICE_DEFINE_WITH_DEPS(dev_id, name, init_fn, data, config, prio, api, deps, dep_count)           \
    DRVFX_DEVICE_BASE_DEFINE(dev_id, name, init_fn, data, config, prio, api, deps, dep_count)

#define DRVFX_DEVICE_DEFINE(name, init_fn, data, config, prio, api)                                                    \
    DRVFX_DEVICE_BASE_DEFINE(__DRVFX_DEVICE_MAKE_UNIQUE_TOKEN(_, __LINE__), name, init_fn, data, config, prio, api,    \
                             NULL, 0)

#define DRVFX_DEVICE_DEFINE_WITH_DEPS(name, init_fn, data, config, prio, api, deps, dep_count)                         \
    DRVFX_DEVICE_BASE_DEFINE(__DRVFX_DEVICE_MAKE_UNIQUE_TOKEN(_, __LINE__), name, init_fn, data, config, prio, api,    \
                             deps, dep_count)

#define DRVFX_MODULE_DEFINE(name, init_fn, data, config, prio, api)                                                    \
    DRVFX_DEVICE_BASE_DEFINE(__DRVFX_DEVICE_MAKE_UNIQUE_TOKEN(_, __LINE__), name, init_fn, data, config, prio, api,    \
                             NULL, 0)

// Functions:

bool k_device_is_ready(const struct drvfx_device* dev);
const struct drvfx_device* k_device_get_binding(const char* name);
size_t k_device_get_all_static(const struct drvfx_device** devices);

#ifdef __cplusplus
}
#endif