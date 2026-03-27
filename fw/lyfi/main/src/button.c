#include <string.h>
#include <time.h>
#include <errno.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <esp_rom_md5.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>

#include <iot_button.h>
#include <button_gpio.h>
#include <borneo/wifi.h>

#include "lyfi-events.h"

#if CONFIG_LYFI_PRESS_BUTTON_ENABLED

#define LONG_PRESS_DURATION_MS 15000

#define TAG "button"

static button_handle_t s_button = NULL;

static void button_long_press_cb(void* arg, void* usr_data);

static void button_single_click_cb(void* arg, void* usr_data);

int button_init()
{
    // create gpio button
    const button_config_t btn_cfg = { 0 };
    const button_gpio_config_t btn_gpio_cfg = {
        .gpio_num = CONFIG_LYFI_PRESS_BUTTON_GPIO,
        .active_level = 0,
        .disable_pull = 1,
    };
    BO_TRY_ESP(iot_button_new_gpio_device(&btn_cfg, &btn_gpio_cfg, &s_button));
    if (NULL == s_button) {
        ESP_LOGE(TAG, "Press button create failed");
        return -EIO;
    }

    BO_TRY_ESP(iot_button_set_param(s_button, BUTTON_LONG_PRESS_TIME_MS, (void*)LONG_PRESS_DURATION_MS));

    BO_TRY_ESP(iot_button_register_cb(s_button, BUTTON_SINGLE_CLICK, NULL, button_single_click_cb, NULL));

    BO_TRY_ESP(iot_button_register_cb(s_button, BUTTON_LONG_PRESS_UP, NULL, button_long_press_cb, NULL));

    return 0;
}

static void button_single_click_cb(void* arg, void* usr_data)
{
    if (bo_power_is_on()) {
        BO_MUST_ESP(esp_event_post(LYFI_EVENTS, LYFI_EVENT_LED_NOTIFY_TEMPORARY_STATE, NULL, 0, portMAX_DELAY));
    }
    else {
        // Turn the power on
        BO_MUST(bo_power_on());
    }
}

static void button_long_press_cb(void* arg, void* usr_data)
{
    int rc = bo_wifi_forget();
    if (rc) {
        ESP_LOGE(TAG, "Failed to forget WiFi configuration!");
    }
    bo_system_reboot_later(5000);
}

#endif // CONFIG_LYFI_PRESS_BUTTON_ENABLED