#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include <cbor.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/devices/sensor.h>
#include <borneo/power.h>
#include "rpc.h"

#if CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT

#define TAG "lyfi-rpc-power"

int bo_rpc_lyfi_current_ma_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    int32_t ma;
    const struct drvfx_device* sensor_dev = k_device_get_binding("sensor.led_current");
    BO_TRY(sensor_get_value(sensor_dev, &ma));
    BO_TRY(cbor_encode_uint(retvals, ma));
    return 0;
}

int bo_rpc_lyfi_power_mw_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    int32_t power_mw;
    const struct drvfx_device* sensor_dev = k_device_get_binding("sensor.led_power");
    BO_TRY(sensor_get_value(sensor_dev, &power_mw));
    BO_TRY(cbor_encode_uint(retvals, power_mw));
    return 0;
}

#endif // CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT