#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include <esp_app_desc.h>
#include <esp_mac.h>
#include <esp_timer.h>
#include <nvs_flash.h>
#include <cbor.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/devices/sensor.h>
#include <borneo/sensors.h>
#include <borneo/sntp.h>
#include <borneo/rpc/common.h>
#include <borneo/rtc.h>
#include <borneo/common.h>
#include <borneo/wifi.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/timer.h>
#include <borneo/product.h>

#define TAG "borneo-rpc-factory"

int bo_rpc_borneo_factory_reset_post(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input data for reboot
    (void)retvals; // No output for reboot
    BO_TRY(bo_power_shutdown(0));
    BO_TRY(bo_wifi_forget_later(1000));

    BO_TRY(bo_system_factory_reset());

    // First, return the result, wait for three seconds, and then restart.
    bo_system_reboot_later(5000);

    return 0;
}
