#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// RPC function declarations for reusable CBOR operations
int bo_rpc_borneo_info_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_reboot_post(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_status_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_fw_ver_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_compatible_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_system_mode_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_heartbeat_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_health_get(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for power-related CBOR operations
int bo_rpc_borneo_power_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_power_put(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_power_behavior_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_power_behavior_put(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for RTC-related CBOR operations
int bo_rpc_rtc_local_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_rtc_local_post(const CborValue* args, CborEncoder* retvals);
int bo_rpc_rtc_timestamp_get(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for settings-related CBOR operations
int bo_rpc_borneo_settings_timezone_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_settings_timezone_put(const CborValue* args, CborEncoder* retvals);

int bo_rpc_borneo_settings_name_get(const CborValue* args, CborEncoder* retvals);
int bo_rpc_borneo_settings_name_put(const CborValue* args, CborEncoder* retvals);

// RPC function declarations for sensors
int bo_rpc_borneo_sensors_get(const CborValue* args, CborEncoder* retvals);

// Networking Methods
int bo_rpc_borneo_network_reset_post(const CborValue* args, CborEncoder* retvals);

// Factory functions
int bo_rpc_borneo_factory_reset_post(const CborValue* args, CborEncoder* retvals);

#ifdef __cplusplus
}
#endif