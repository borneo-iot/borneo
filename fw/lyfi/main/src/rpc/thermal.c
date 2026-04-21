#include <errno.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>

#include <cbor.h>

#include <borneo/system.h>
#include "../thermal.h"
#include "../protect.h"

#define TAG "thermal-rpc"

#if CONFIG_LYFI_THERMAL_ENABLED

int bo_rpc_borneo_lyfi_thermal_current_temp_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
#if CONFIG_LYFI_NTC_SUPPORT
    if (!thermal_is_available()) {
        BO_TRY(cbor_encode_null(retvals));
        return 0;
    }

    int temp = thermal_get_current_temp();
    if (temp < 0) {
        BO_TRY(cbor_encode_null(retvals));
    }
    else {
        BO_TRY(cbor_encode_uint(retvals, temp));
    }
#else
    BO_TRY(cbor_encode_null(retvals));
#endif // CONFIG_LYFI_NTC_SUPPORT

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_keep_temp_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    const struct thermal_settings* settings = thermal_get_settings();
    BO_TRY(cbor_encode_uint(retvals, settings->keep_temp));

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_settings_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    CborEncoder root_map;
    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

    const struct thermal_settings* settings = thermal_get_settings();

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "kp"));
        BO_TRY(cbor_encode_int(&root_map, settings->kp));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "ki"));
        BO_TRY(cbor_encode_int(&root_map, settings->ki));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "kd"));
        BO_TRY(cbor_encode_int(&root_map, settings->kd));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "tempKeep"));
        BO_TRY(cbor_encode_int(&root_map, settings->keep_temp));
    }

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "tempOverheated"));
        BO_TRY(cbor_encode_int(&root_map, bo_protect_get_overheated_temp()));
    }
#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_fan_mode_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    const struct thermal_settings* settings = thermal_get_settings();

    switch (settings->fan_mode) {
    case THERMAL_FAN_MODE_PID:
        BO_TRY(cbor_encode_text_stringz(retvals, "pid"));
        break;

    case THERMAL_FAN_MODE_MANUAL:
        BO_TRY(cbor_encode_text_stringz(retvals, "manual"));
        break;

    default:
        BO_TRY(cbor_encode_undefined(retvals));
        break;
    }

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_fan_mode_put(const CborValue* args, CborEncoder* retvals)
{
    int mode = -1;

    /* Decode a text string from CBOR into a stack buffer and map it to enum */
    char mode_str[16] = { 0 };
    size_t mode_len = sizeof(mode_str);

    BO_TRY(cbor_value_copy_text_string(args, mode_str, &mode_len, NULL));

    if (mode_len == 0) {
        return -ERANGE;
    }

    if (strcmp(mode_str, "pid") == 0) {
        mode = THERMAL_FAN_MODE_PID;
    }
    else if (strcmp(mode_str, "manual") == 0) {
        mode = THERMAL_FAN_MODE_MANUAL;
    }
    else {
        return -EINVAL;
    }

    BO_TRY(thermal_set_fan_mode(mode));

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_manual_fan_get(const CborValue* args, CborEncoder* retvals)
{
    const struct thermal_settings* settings = thermal_get_settings();
    BO_TRY(cbor_encode_uint(retvals, settings->fan_manual_power));

    return 0;
}

int bo_rpc_borneo_lyfi_thermal_manual_fan_put(const CborValue* args, CborEncoder* retvals)
{
    int power;
    BO_TRY(cbor_value_get_int(args, &power));
    if (power > 100 || power < 0) {
        return -ERANGE;
    }
    BO_TRY(thermal_set_manual_fan_power((uint8_t)power));

    return 0;
}

#endif // CONFIG_LYFI_THERMAL_ENABLED
