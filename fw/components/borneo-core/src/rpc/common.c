#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include <esp_mac.h>
#include <esp_timer.h>
#include <nvs_flash.h>
#include <cbor.h>
#include <esp_app_desc.h>

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
#include <borneo/transport.h>

#define TAG "borneo-rpc-common"

int bo_rpc_borneo_info_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    const struct system_info* sysinfo = bo_system_get_info();

    CborEncoder root_map;
    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "id"));
        BO_TRY(cbor_encode_text_stringz(&root_map, sysinfo->hex_id));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "compatible"));
        BO_TRY(cbor_encode_text_stringz(&root_map, CONFIG_BORNEO_DEVICE_COMPATIBLE));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "name"));
        BO_TRY(cbor_encode_text_stringz(&root_map, sysinfo->name));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "pid"));
        BO_TRY(cbor_encode_text_stringz(&root_map, CONFIG_BORNEO_PRODUCT_ID));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "serno"));
        BO_TRY(cbor_encode_text_stringz(&root_map, sysinfo->hex_id));
    }

    // Product Mode
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "productMode"));
#if CONFIG_BORNEO_PRODUCT_MODE_STANDALONE
        BO_TRY(cbor_encode_uint(&root_map, BORNEO_PRODUCT_MODE_STANDALONE));
#elif CONFIG_BORNEO_PRODUCT_MODE_FULL
        BO_TRY(cbor_encode_uint(&root_map, BORNEO_PRODUCT_MODE_FULL));
#else
        BO_TRY(cbor_encode_uint(&root_map, BORNEO_PRODUCT_MODE_OEM));
#endif
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "transport"));
        BO_TRY(cbor_encode_uint(&root_map, BO_TRANSPORT_CHANNEL_WIFI));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "hasBT"));
#if CONFIG_BT_BLE_ENABLED
        BO_TRY(cbor_encode_boolean(&root_map, true));
#else
        BO_TRY(cbor_encode_boolean(&root_map, false));
#endif
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "hasWifi"));
        BO_TRY(cbor_encode_boolean(&root_map, true));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "hasMqtt"));
        BO_TRY(cbor_encode_boolean(&root_map, false));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "manuf"));
        BO_TRY(cbor_encode_text_stringz(&root_map, sysinfo->manuf));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "model"));
        BO_TRY(cbor_encode_text_stringz(&root_map, sysinfo->model));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "hwVer"));
        BO_TRY(cbor_encode_text_stringz(&root_map, CONFIG_BORNEO_HW_VER));
    }

    {
        const esp_app_desc_t* app_desc = esp_app_get_description();
        if (app_desc == NULL) {
            return -1;
        }
        BO_TRY(cbor_encode_text_stringz(&root_map, "fwVer"));
        BO_TRY(cbor_encode_text_stringz(&root_map, app_desc->version));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "isCE"));

#if CONFIG_BORNEO_EDITION_CE
        BO_TRY(cbor_encode_boolean(&root_map, true));
#else
        BO_TRY(cbor_encode_boolean(&root_map, false));
#endif
    }

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_reboot_post(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input data for reboot
    (void)retvals; // No output for reboot
    bo_system_reboot_later(5000);
    return 0;
}

int bo_rpc_borneo_status_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    CborEncoder root_map;
    uint32_t timestamp = 0;

    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

    BO_TRY(cbor_encode_text_stringz(&root_map, "mode"));
    BO_TRY(cbor_encode_uint(&root_map, k_get_mode()));

    BO_TRY(cbor_encode_text_stringz(&root_map, "power"));
    BO_TRY(cbor_encode_boolean(&root_map, bo_power_is_on()));

    BO_TRY(cbor_encode_text_stringz(&root_map, "timestamp"));
    BO_TRY(bo_rtc_get_timestamp(&timestamp));
    BO_TRY(cbor_encode_uint(&root_map, timestamp));

    BO_TRY(cbor_encode_text_stringz(&root_map, "bootDuration"));
    BO_TRY(cbor_encode_int(&root_map, bo_timer_uptime_ms()));

    BO_TRY(cbor_encode_text_stringz(&root_map, "timezone"));
    char* tz_name = getenv("TZ");
    if (tz_name == NULL) {
        BO_TRY(cbor_encode_null(&root_map));
    }
    else {
        BO_TRY(cbor_encode_text_stringz(&root_map, tz_name));
    }

    // TODO FIXME
    BO_TRY(cbor_encode_text_stringz(&root_map, "wifiStatus"));
    BO_TRY(cbor_encode_uint(&root_map, 0));

    // WiFi RSSI
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "wifiRssi"));
        int wifi_rssi;
        if (bo_wifi_get_rssi(&wifi_rssi) == 0) {
            BO_TRY(cbor_encode_int(&root_map, wifi_rssi));
        }
        else {
            BO_TRY(cbor_encode_null(&root_map));
        }
    }

#if CONFIG_BT_BLE_ENABLED
    // TODO FIXME
    BO_TRY(cbor_encode_text_stringz(&root_map, "btStatus"));
    BO_TRY(cbor_encode_uint(&root_map, 0));
#endif

    // TODO FIXME
    BO_TRY(cbor_encode_text_stringz(&root_map, "serverStatus"));
    BO_TRY(cbor_encode_uint(&root_map, 0));

    BO_TRY(cbor_encode_text_stringz(&root_map, "error"));
    BO_TRY(cbor_encode_int(&root_map, errno));

    BO_TRY(cbor_encode_text_stringz(&root_map, "shutdownReason"));
    BO_TRY(cbor_encode_uint(&root_map, bo_system_get_shutdown_reason()));

    BO_TRY(cbor_encode_text_stringz(&root_map, "shutdownTimestamp"));
    BO_TRY(cbor_encode_uint(&root_map, bo_system_get_shutdown_timestamp()));

#if CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "powerVoltage"));
        int32_t mv;
        const struct drvfx_device* vdev = k_device_get_binding("sensor.voltage");
        int rc = sensor_get_value(vdev, &mv);
        if (rc != 0) {
            BO_TRY(cbor_encode_null(&root_map));
        }
        else {
            BO_TRY(cbor_encode_int(&root_map, mv));
        }
    }
#endif // CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_fw_ver_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    const esp_app_desc_t* app_desc = esp_app_get_description();
    if (app_desc == NULL) {
        return -1;
    }
    BO_TRY(cbor_encode_text_stringz(retvals, app_desc->version));
    return 0;
}

int bo_rpc_borneo_compatible_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    BO_TRY(cbor_encode_text_stringz(retvals, CONFIG_BORNEO_DEVICE_COMPATIBLE));
    return 0;
}

int bo_rpc_heartbeat_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    BO_TRY(cbor_encode_int(retvals, (int64_t)time(NULL)));
    return 0;
}

int bo_rpc_system_mode_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    uint8_t mode = k_get_mode();
    BO_TRY(cbor_encode_uint(retvals, mode));
    return 0;
}

int bo_rpc_borneo_settings_timezone_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    const char* tz = bo_rtc_get_tz();
    if (tz != NULL) {
        BO_TRY(cbor_encode_text_stringz(retvals, tz));
    }
    else {
        BO_TRY(cbor_encode_null(retvals));
    }
    return 0;
}

int bo_rpc_borneo_settings_timezone_put(const CborValue* args, CborEncoder* retvals)
{
    (void)retvals; // No output for PUT
    char tz[256] = { 0 };
    size_t tz_len = sizeof(tz);
    BO_TRY(cbor_value_copy_text_string(args, tz, &tz_len, NULL));
    if (tz_len > 128 || tz_len == 0) {
        return -EINVAL; // Bad request
    }
    bo_rtc_set_tz(tz);
    return 0;
}

int bo_rpc_borneo_settings_name_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    const struct system_info* sysinfo = bo_system_get_info();
    BO_TRY(cbor_encode_text_stringz(retvals, sysinfo->name));
    return 0;
}

int bo_rpc_borneo_settings_name_put(const CborValue* args, CborEncoder* retvals)
{
    (void)retvals; // No output for PUT
    char name[BO_DEVICE_NAME_MAX] = { 0 };
    size_t name_len = sizeof(name);
    BO_TRY(cbor_value_copy_text_string(args, name, &name_len, NULL));
    if (name_len >= BO_DEVICE_NAME_MAX || name_len == 0) {
        return -EINVAL; // Bad request
    }
    BO_TRY(bo_system_set_user_name(name));
    return 0;
}

int bo_rpc_borneo_sensors_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    CborEncoder root_map;
    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));
    size_t n = sensors_get_device_count();
    const struct drvfx_device** devs = sensors_get_devices();
    for (size_t i = 0; i < n; i++) {
        const struct drvfx_device* sensor_dev = devs[i];
        BO_TRY(cbor_encode_text_stringz(&root_map, sensor_dev->name));
        int32_t value;
        BO_TRY(sensor_get_value(sensor_dev, &value));
        BO_TRY(cbor_encode_int(&root_map, value));
    }

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_network_reset_post(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input data for reboot
    (void)retvals; // No output for reboot
    BO_TRY(bo_power_shutdown(0));
    BO_TRY(bo_wifi_forget_later(1000));
    bo_system_reboot_later(5000);

    return 0;
}