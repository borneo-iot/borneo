#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/event_groups.h>
#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include <esp_netif.h>
#include <nvs_flash.h>

#include <esp_netif.h>

#include <drvfx/drvfx.h>

#include "borneo/common.h"
#include "borneo/nvs.h"
#include "borneo/power.h"
#include "borneo/wifi.h"

#include "borneo/devices/indicator.h"

#include "borneo/sntp.h"
#include "borneo/mdns.h"
#include "borneo/system.h"
#include "borneo/rtc.h"

#if CONFIG_SOC_USB_SERIAL_JTAG_SUPPORTED
#include "soc/usb_serial_jtag_reg.h"
#endif // CONFIG_SOC_USB_SERIAL_JTAG_SUPPORTED

#define TAG "bo-init"

static int _borneo_early_init(const struct drvfx_device* dev)
{
    ESP_LOGI(TAG, "Initializing Borneo Core...");
#if CONFIG_SOC_USB_SERIAL_JTAG_SUPPORTED && (!CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG)
    CLEAR_PERI_REG_MASK(USB_SERIAL_JTAG_CONF0_REG, USB_SERIAL_JTAG_DP_PULLUP);
#endif

    ESP_LOGI(TAG, "Initializing early stuff...");

    // Initialize NVS
    BO_TRY(bo_nvs_init());
    BO_TRY(esp_event_loop_create_default());
    ESP_LOGI(TAG, "Early stuff has been initialized successfully.");
    return 0;
}

static int _borneo_core_init(const struct drvfx_device* dev)
{

#if CONFIG_BORNEO_INDICATOR_ENABLED
    BO_TRY(bo_indicator_init());
#endif

    BO_TRY(bo_system_init());
    BO_TRY(bo_power_init());
    BO_TRY(bo_rtc_init());

    ESP_LOGI(TAG, "Borneo Core has been initialized successfully.");
    return 0;
}

static int _borneo_net_init(const struct drvfx_device* dev)
{
    ESP_LOGI(TAG, "Initializing Borneo networking...");

    BO_TRY(esp_netif_init());

    BO_TRY(bo_wifi_init());

    BO_TRY(bo_mdns_init());

    BO_TRY(bo_sntp_init());

    ESP_LOGI(TAG, "Borneo networking has been initialized successfully.");
    return 0;
}

DRVFX_SYS_INIT(_borneo_early_init, EARLY, DRVFX_INIT_EARLY_DEFAULT_PRIORITY);
DRVFX_SYS_INIT(_borneo_core_init, APPLICATION, DRVFX_INIT_APP_HIGHEST_PRIORITY);
DRVFX_SYS_INIT(_borneo_net_init, APPLICATION, DRVFX_INIT_APP_HIGH_PRIORITY);