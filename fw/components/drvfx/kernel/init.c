#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <esp_log.h>
#include <esp_private/startup_internal.h>

#include "drvfx/kernel/common.h"
#include "drvfx/drvfx.h"

#define TAG "kernel.init"

extern const struct drvfx_init_entry _drvfx_init_EARLY_start[];
extern const struct drvfx_init_entry _drvfx_init_EARLY_end[];
extern const struct drvfx_init_entry _drvfx_init_PRE_KERNEL_1_start[];
extern const struct drvfx_init_entry _drvfx_init_PRE_KERNEL_1_end[];
extern const struct drvfx_init_entry _drvfx_init_PRE_KERNEL_2_start[];
extern const struct drvfx_init_entry _drvfx_init_PRE_KERNEL_2_end[];
extern const struct drvfx_init_entry _drvfx_init_POST_KERNEL_start[];
extern const struct drvfx_init_entry _drvfx_init_POST_KERNEL_end[];
extern const struct drvfx_init_entry _drvfx_init_APPLICATION_start[];
extern const struct drvfx_init_entry _drvfx_init_APPLICATION_end[];

enum init_level {
    DRVFX_INIT_LEVEL_EARLY = 0,
    DRVFX_INIT_LEVEL_PRE_KERNEL_1,
    DRVFX_INIT_LEVEL_PRE_KERNEL_2,
    DRVFX_INIT_LEVEL_POST_KERNEL,
    DRVFX_INIT_LEVEL_APPLICATION,
};

static int drvfx_device_check_dependencies(const struct drvfx_device* dev)
{
    if ((dev == NULL) || (dev->required_devices == NULL)) {
        return 0;
    }

    for (size_t index = 0; index < dev->required_device_count; index++) {
        const char* dep_name = dev->required_devices[index];
        if ((dep_name == NULL) || (dep_name[0] == '\0')) {
            continue;
        }

        if (k_device_get_binding(dep_name) == NULL) {
            ESP_LOGE(TAG, "Dependency not ready: %s requires %s", dev->name, dep_name);
            return -ENODEV;
        }
    }

    return 0;
}

static void drvfx_sys_init_run_level(enum init_level level)
{
    static const struct drvfx_init_entry* levels[] = {
        // EARLY pair
        _drvfx_init_EARLY_start,
        _drvfx_init_EARLY_end,

        // PRE_KERNEL_1 pair
        _drvfx_init_PRE_KERNEL_1_start,
        _drvfx_init_PRE_KERNEL_1_end,

        // PRE_KRENEL_2 pair
        _drvfx_init_PRE_KERNEL_2_start,
        _drvfx_init_PRE_KERNEL_2_end,

        // POST_KERNEL pair
        _drvfx_init_POST_KERNEL_start,
        _drvfx_init_POST_KERNEL_end,

        // APPLICATION pair
        _drvfx_init_APPLICATION_start,
        _drvfx_init_APPLICATION_end,
    };

    int pos = level * 2;
    for (const struct drvfx_init_entry* entry = levels[pos]; entry != levels[pos + 1]; entry++) {
        const struct drvfx_device* dev = entry->dev;
        int rc = 0;

        if (dev != NULL) {
            rc = drvfx_device_check_dependencies(dev);
            if (rc == 0) {
                rc = entry->init(dev);
            }
        }
        else {
            rc = entry->init(dev);
        }

        if (dev != NULL) {
            /* Mark device initialized.  If initialization
             * failed, record the error condition.
             */
            dev->state->init_res = rc;
            if (rc != 0) {
                ESP_LOGE(TAG, "Failed to initialize: %s (rc=%d)", dev->name, rc);
            }
            dev->state->initialized = true;
        }
        else if (rc != 0) {
            ESP_LOGE(TAG, "Subsystem init failed (rc=%d)", rc);
        }
    }
}

ESP_SYSTEM_INIT_FN(drvfx_kernel_init, SECONDARY, BIT(0), 1000)
{
    ESP_LOGI(TAG, "Drvfx kernel initializing...");
    k_init();

    ESP_LOGI(TAG, "Drvfx DRVFX_INIT_LEVEL_EARLY...");
    drvfx_sys_init_run_level(DRVFX_INIT_LEVEL_EARLY);

    ESP_LOGI(TAG, "Drvfx DRVFX_INIT_LEVEL_PRE_KERNEL_1...");
    drvfx_sys_init_run_level(DRVFX_INIT_LEVEL_PRE_KERNEL_1);

    ESP_LOGI(TAG, "Drvfx DRVFX_INIT_LEVEL_PRE_KERNEL_2...");
    drvfx_sys_init_run_level(DRVFX_INIT_LEVEL_PRE_KERNEL_2);
    return 0;
}

ESP_SYSTEM_INIT_FN(drvfx_post_kernel_init, SECONDARY, BIT(0), 2000)
{
    ESP_LOGI(TAG, "Drvfx DRVFX_INIT_LEVEL_POST_KERNEL...");
    drvfx_sys_init_run_level(DRVFX_INIT_LEVEL_POST_KERNEL);
    return 0;
}

void __attribute__((weak)) drvfx_app_main()
{
    //
    ESP_LOGI(TAG, "Entering the default `drvfx_app_main` ...");
}

void app_main()
{
    ESP_LOGI(TAG, "User land initializing...");
    drvfx_sys_init_run_level(DRVFX_INIT_LEVEL_APPLICATION);

    k_ready();
    ESP_LOGI(TAG, "Main thread initialized.");
    drvfx_app_main();
}