#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT

// RPC function declarations for LyFi power measurement CBOR operations
int bo_rpc_lyfi_current_ma_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_lyfi_power_mw_get(const CborValue* args, CborEncoder* retvals);

#endif // CONFIG_BORNEO_MEAS_VOLTAGE_SUPPORT && CONFIG_LYFI_MEAS_CURRENT_SUPPORT

// RPC function declarations for LyFi fan CBOR operations
int bo_rpc_borneo_lyfi_fan_power_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_fan_power_put(const CborValue* args, CborEncoder* retvals);

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

// RPC function declarations for LyFi protection CBOR operations
int bo_rpc_borneo_lyfi_protection_overheated_temp_get(const CborValue* args, CborEncoder* retvals);

#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

#if CONFIG_LYFI_THERMAL_ENABLED

// RPC function declarations for LyFi thermal CBOR operations
int bo_rpc_borneo_lyfi_thermal_current_temp_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_keep_temp_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_settings_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_fan_mode_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_fan_mode_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_manual_fan_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_thermal_manual_fan_put(const CborValue* args, CborEncoder* retvals);

#endif // CONFIG_LYFI_THERMAL_ENABLED

// RPC function declarations for LyFi sun CBOR operations
int bo_rpc_borneo_lyfi_sun_schedule_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_sun_curve_get(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for LyFi moon CBOR operations
int bo_rpc_borneo_lyfi_moon_schedule_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_moon_curve_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_moon_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_moon_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_moon_status_get(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for LyFi acclimation CBOR operations
int bo_rpc_borneo_lyfi_acclimation_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_acclimation_post(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_acclimation_delete(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for LyFi core CBOR operations
int bo_rpc_borneo_lyfi_color_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_color_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_schedule_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_schedule_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_info_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_status_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_output_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_temp_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_state_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_state_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_correction_method_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_correction_method_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_mode_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_mode_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_temporary_duration_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_temporary_duration_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_geo_location_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_geo_location_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_tz_enabled_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_tz_enabled_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_tz_offset_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_tz_offset_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_cloud_enabled_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_cloud_enabled_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_output_invert_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_lyfi_output_invert_put(const CborValue* args, CborEncoder* retvals);

#ifdef __cplusplus
}
#endif
