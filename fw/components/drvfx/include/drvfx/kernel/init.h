#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct drvfx_device;

/** @brief Structure to store initialization entry information. */
struct drvfx_init_entry {
    int (*init)(const struct drvfx_device* dev);
    const struct drvfx_device* dev;
};

/*
Available level:
    * EARLY
    * PRE_KERNEL_1
    * PRE_KERNEL_2
    * POST_KERNEL
    * APPLICATION
*/

#define DRVFX_INIT_EARLY_DEFAULT_PRIORITY 1000
#define DRVFX_INIT_PRE_KERNEL_DEFAULT_PRIORITY 2000
#define DRVFX_INIT_KERNEL_DEFAULT_PRIORITY 3000
#define DRVFX_INIT_DRIVER_DEFAULT_PRIORITY 4000
#define DRVFX_INIT_POST_KERNEL_HIGH_PRIORITY 5000
#define DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY 5100
#define DRVFX_INIT_POST_KERNEL_LOW_PRIORITY 5200
#define DRVFX_INIT_APP_HIGHEST_PRIORITY 6000
#define DRVFX_INIT_APP_HIGH_PRIORITY 6100
#define DRVFX_INIT_APP_DEFAULT_PRIORITY 6200
#define DRVFX_INIT_APP_LOW_PRIORITY 6300
#define DRVFX_INIT_APP_LOWEST_PRIORITY 6400

#define DRVFX_INIT_ENTRY_NAME(init_id) _CONCAT(__init_, init_id)

#define DRVFX_INIT_ENTRY_SECTION(level, prio)                                                                          \
    __attribute__((__section__(".drvfx_init_" #level "." _STRINGIFY(prio) "_"), used))

#define DRVFX_INIT_ENTRY_DEFINE(init_id, init_fn, device, level, prio)                                                 \
    static const DRVFX_DECL_ALIGN(struct drvfx_init_entry) DRVFX_INIT_ENTRY_SECTION(level, prio)                       \
        DRVFX_USED __DRVFX_NOASAN                                                                                      \
        DRVFX_INIT_ENTRY_NAME(init_id)                                                                                 \
        = {                                                                                                            \
              .init = (init_fn),                                                                                       \
              .dev = (device),                                                                                         \
          }

#define DRVFX_SYS_INIT(init_fn, level, prio) DRVFX_SYS_INIT_NAMED(init_fn, init_fn, level, prio)

#define DRVFX_SYS_INIT_NAMED(name, init_fn, level, prio) DRVFX_INIT_ENTRY_DEFINE(name, init_fn, NULL, level, prio)

#define DRVFX_SUBSYS_INIT(init_fn, prio) DRVFX_SYS_INIT_NAMED(init_fn, init_fn, POST_KERNEL, prio)

#define DRVFX_SUBSYS_INIT_NAMED(name, init_fn, prio) DRVFX_INIT_ENTRY_DEFINE(name, init_fn, NULL, POST_KERNEL, prio)

#ifdef __cplusplus
}
#endif