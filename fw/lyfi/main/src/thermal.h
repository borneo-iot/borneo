#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if CONFIG_LYFI_THERMAL_ENABLED

enum thermal_fan_mode {
    THERMAL_FAN_MODE_MANUAL = 0,
    THERMAL_FAN_MODE_PID = 1,

    THERMAL_FAN_MODE_SIZE,
};

struct thermal_settings {
    int32_t kp; ///< PID P
    int32_t ki; ///< PID I
    int32_t kd; ///< PID D
    uint8_t keep_temp; ///< Maintaining temperature with PID
    uint8_t fan_mode; ///< The fan running mode, values in `enum thermal_fan_mode`
    uint8_t fan_manual_power; ///< The power ratio of the manual setting of the fan
};

int thermal_init();
const struct thermal_settings* thermal_get_settings();
int thermal_set_pid(int32_t kp, int32_t ki, int32_t kd);
bool thermal_is_available();

int thermal_set_manual_fan_power(uint8_t power);

#if CONFIG_LYFI_NTC_SUPPORT
int thermal_get_current_temp();
#endif

int thermal_set_fan_mode(int fan_mode);
int thermal_set_fan_manual(uint8_t fan_power);

#endif // CONFIG_LYFI_THERMAL_ENABLED

#ifdef __cplusplus
}
#endif