#include <stdint.h>
#include <time.h>

#include <esp_system.h>
#include <esp_log.h>
#include <esp_event.h>

#include <drvfx/drvfx.h>

#include <borneo/system.h>
#include <borneo/common.h>

#include "protect.h"
#include "led/led.h"
#include "thermal.h"
#include "button.h"

#define TAG "lyfi_init"

static int _lyfi_init(const struct drvfx_device*)
{
#if CONFIG_LYFI_THERMAL_ENABLED
    BO_TRY(thermal_init());
#endif

#if CONFIG_LYFI_PROTECTION_ENABLED
    BO_TRY(bo_protect_init());
#endif

    BO_TRY(led_init());

#if CONFIG_LYFI_PRESS_BUTTON_ENABLED
    BO_TRY(button_init());
#endif

    ESP_LOGI(TAG, "Borneo LyFi has been initialized successfully.");
    return 0;
}

static int _app_init(const struct drvfx_device*)
{
    // At this point, power-on is complete, send the power-on completion message.
    return 0;
}

DRVFX_SYS_INIT(_lyfi_init, APPLICATION, DRVFX_INIT_APP_DEFAULT_PRIORITY);
DRVFX_SYS_INIT(_app_init, APPLICATION, DRVFX_INIT_APP_LOWEST_PRIORITY);