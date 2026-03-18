#include <string.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/devices/sensor.h>
#include <borneo/power.h>
#include <borneo/nvs.h>

#include "fan.h"
#include "protect.h"
#include "thermal.h"
#include "lyfi-events.h"

#define TEMP_WINDOW_SIZE 8

#if CONFIG_LYFI_THERMAL_ENABLED

struct pid {
    int32_t prev_error;
    int32_t integral;
    int32_t last_output;
};

struct thermal_state {
    const struct drvfx_device* temp_dev;
    esp_timer_handle_t timer;
    struct pid pid;
    int current_temp;
    int8_t temp_window[TEMP_WINDOW_SIZE];
    uint8_t temp_window_index;
};

static int load_factory_settings();
static int load_user_settings();
static void thermal_timer_callback(void* args);
static int thermal_reinit();

#if CONFIG_LYFI_NTC_SUPPORT
static uint8_t thermal_pid_step(int32_t current_temp);
static int update_temp_average(int new_sample);
#endif

#if CONFIG_LYFI_NTC_SUPPORT
static void _timer_callback_pid(void* args);
#endif // CONFIG_LYFI_NTC_SUPPORT

#define CLAMP(x, _min, _max)                                                                                           \
    if ((x) > (_max))                                                                                                  \
        (x) = (_max);                                                                                                  \
    if ((x) < (_min))                                                                                                  \
        (x) = (_min);

#define TAG "thermal"

#define THERMAL_NVS_USER_NS "thermal"
#define THERMAL_NVS_FACTORY_NS "thermal"
#define THERMAL_NVS_KEY_KP "kp"
#define THERMAL_NVS_KEY_KI "ki"
#define THERMAL_NVS_KEY_KD "kd"
#define THERMAL_NVS_KEY_KEEP_TEMP "ktemp"
#define THERMAL_NVS_KEY_FAN_MODE "fmode"
#define THERMAL_NVS_KEY_FAN_MANUAL_POWER "fanmanpwr"

#define PID_Q 100
#define PID_PERIOD (1000)
#define PID_INTEGRAL_MAX 10000
#define PID_INTEGRAL_MIN -10000

#define OUTPUT_MIN 10
#define OUTPUT_MAX 100

#define KEEP_TEMP_MIN 35

// Output slew rate limit: restrict the maximum change per cycle to improve user experience and suppress
// noise-induced jumps
#define PID_MAX_STEP 15

const struct thermal_settings THERMAL_DEFAULT_SETTINGS = {
    .kp = 250,
    .ki = 10,
    .kd = 50,
    .keep_temp = 45,
    .fan_mode = CONFIG_LYFI_THERMAL_FAN_MODE_DEFAULT,
    .fan_manual_power = 100,
};

static struct thermal_settings _settings = { 0 };
static struct thermal_state _thermal = { 0 };

static int thermal_reinit()
{
    _thermal.pid.integral = 0;
    _thermal.pid.prev_error = 0;
    _thermal.pid.last_output = 0;
    thermal_timer_callback(NULL);
    return 0;
}

int thermal_init()
{
    ESP_LOGI(TAG, "Initializing thermal management subsystem...");

    BO_TRY(load_factory_settings());
    BO_TRY(load_user_settings());

#if CONFIG_LYFI_NTC_SUPPORT
    _thermal.temp_dev = k_device_get_binding("sensor.temp");
    if (_thermal.temp_dev == NULL) {
        return -ENODEV;
    }
    {
        // Fill the window
        for (size_t ti = 0; ti < TEMP_WINDOW_SIZE; ti++) {
            int32_t temp;
            int rc = sensor_get_value(_thermal.temp_dev, &temp);
            if (rc == 0) {
                _thermal.temp_window[ti] = temp;
                _thermal.current_temp = temp;
            }
            else {
                _thermal.temp_window[ti] = -1;
            }
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
#else
    _thermal.temp_dev = NULL;
#endif // CONFIG_LYFI_NTC_SUPPORT

#if CONFIG_LYFI_FAN_CTRL_SUPPORT
    if (_settings.fan_mode == THERMAL_FAN_MODE_MANUAL && bo_power_is_on()) {
        fan_set_power(_settings.fan_manual_power);
    }
    else {
        fan_set_power(0);
    }
#endif

    const esp_timer_create_args_t timer_args = {
        .callback = &thermal_timer_callback,
        .name = "thermal_timer",
    };
    BO_TRY_ESP(esp_timer_create(&timer_args, &_thermal.timer));
    BO_TRY_ESP(esp_timer_start_periodic(_thermal.timer, (uint64_t)PID_PERIOD * 1000));

    BO_TRY(thermal_reinit());

    ESP_LOGI(TAG, "Thermal management module has been initialized successfully.");

    return 0;
}

int load_factory_settings()
{
    nvs_handle_t handle;
    BO_TRY(bo_nvs_factory_open(THERMAL_NVS_FACTORY_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    bool changed = false;

    BO_TRY(bo_nvs_get_or_set_i32(handle, THERMAL_NVS_KEY_KP, &_settings.kp, THERMAL_DEFAULT_SETTINGS.kp, &changed));
    BO_TRY(bo_nvs_get_or_set_i32(handle, THERMAL_NVS_KEY_KI, &_settings.ki, THERMAL_DEFAULT_SETTINGS.ki, &changed));
    BO_TRY(bo_nvs_get_or_set_i32(handle, THERMAL_NVS_KEY_KD, &_settings.kd, THERMAL_DEFAULT_SETTINGS.kd, &changed));
    BO_TRY(bo_nvs_get_or_set_u8(handle, THERMAL_NVS_KEY_KEEP_TEMP, &_settings.keep_temp,
                                THERMAL_DEFAULT_SETTINGS.keep_temp, &changed));

    if (_settings.keep_temp < KEEP_TEMP_MIN) {
        _settings.keep_temp = KEEP_TEMP_MIN;
        BO_TRY(nvs_set_u8(handle, THERMAL_NVS_KEY_KEEP_TEMP, _settings.keep_temp));
        changed = true;
    }

    if (changed) {
        BO_TRY(nvs_commit(handle));
    }

    return 0;
}

int load_user_settings()
{
    nvs_handle_t handle;
    BO_TRY(bo_nvs_user_open(THERMAL_NVS_USER_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);
    bool changed = false;

    BO_TRY(bo_nvs_get_or_set_u8(handle, THERMAL_NVS_KEY_FAN_MODE, &_settings.fan_mode,
                                THERMAL_DEFAULT_SETTINGS.fan_mode, &changed));

    BO_TRY(bo_nvs_get_or_set_u8(handle, THERMAL_NVS_KEY_FAN_MANUAL_POWER, &_settings.fan_manual_power,
                                THERMAL_DEFAULT_SETTINGS.fan_manual_power, &changed));

    if (changed) {
        BO_TRY(nvs_commit(handle));
    }
    return 0;
}

static void thermal_timer_callback(void* args)
{

    switch (_settings.fan_mode) {
    case THERMAL_FAN_MODE_PID: {
#if CONFIG_LYFI_NTC_SUPPORT
        _timer_callback_pid(args);
#endif
    } break;

    case THERMAL_FAN_MODE_MANUAL: {
#if CONFIG_LYFI_FAN_CTRL_SUPPORT
        if (bo_power_is_on()) {
            fan_set_power(_settings.fan_manual_power);
        }
        else {
            fan_set_power(0);
        }
#endif
    } break;

    default:
#if CONFIG_LYFI_FAN_CTRL_SUPPORT
        fan_set_power(0);
#endif
        break;
    }
}

const struct thermal_settings* thermal_get_settings() { return &_settings; }

int thermal_set_pid(int32_t kp, int32_t ki, int32_t kd)
{
    _settings.kp = kp;
    _settings.ki = ki;
    _settings.kd = kd;

    BO_TRY(thermal_reinit());
    return 0;
}

#if CONFIG_LYFI_NTC_SUPPORT

int thermal_get_current_temp() { return _thermal.current_temp; }

static void _timer_callback_pid(void* args)
{
    int32_t new_temp = -1;
    int rc = sensor_get_value(_thermal.temp_dev, &new_temp);
    if (rc != 0) {
        ESP_LOGE(TAG, "Temperature sensor fault or not connected.");
        if (bo_power_is_on()) {

            fan_set_power(OUTPUT_MAX);
        }
        else {
            fan_set_power(0);
        }
        return;
    }
    update_temp_average(new_temp);

    uint8_t fan_power_to_set = OUTPUT_MAX;

    // If the device has been shut down and the temperature is suitable, turn off the fan.
    if (_thermal.current_temp <= _settings.keep_temp && !bo_power_is_on()) {
        if (fan_get_power() > 0) {
            fan_set_power(0);
            // pid_clear(&_pid);
            // Respond to shutdown event to clear PID.
        }
        return;
    }

    // Below the emergency shutdown temperature, execute PID fan speed control.
    fan_power_to_set = thermal_pid_step(_thermal.current_temp);

    if (fan_power_to_set != fan_get_power()) {
        fan_set_power(fan_power_to_set);
        ESP_LOGI(TAG, "Changing fan power: temp=%d, keep_temp=%d, fan=%u%%\t", _thermal.current_temp,
                 _settings.keep_temp, fan_power_to_set);
    }
}

int update_temp_average(int new_sample)
{
    _thermal.temp_window[_thermal.temp_window_index % TEMP_WINDOW_SIZE] = new_sample;
    _thermal.temp_window_index++;

    int sum = 0;
    int n = 0;
    for (size_t i = 0; i < TEMP_WINDOW_SIZE; i++) {
        if (_thermal.temp_window[i] >= 0) {
            sum += _thermal.temp_window[i];
            n++;
        }
    }
    if (n == 0) {
        return -1;
    }
    int old_temp = _thermal.current_temp;
    _thermal.current_temp = (int)((sum + (n / 2)) / n);

    if (_thermal.current_temp != old_temp) {
        esp_err_t err = esp_event_post(LYFI_EVENTS, LYFI_EVENT_LED_TEMPERATURE_CHANGED, NULL, 0, 0);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Failed to post temperature change event: %s", esp_err_to_name(err));
        }
    }

    return 0;
}

uint8_t thermal_pid_step(int32_t current_temp)
{
    struct pid* pid = &_thermal.pid;

    int32_t error = current_temp - _settings.keep_temp;

    // Dead zone: Keep the last output within ±1°C and gently release the integral to avoid long-term historical error
    // residue
    if (abs(error) <= 1) {
        pid->integral -= pid->integral / 8;
        return (uint8_t)(pid->last_output);
    }

    // Period normalization: Make PID_PERIOD changes not affect the feel (based on seconds)
    const int32_t dt_ms = PID_PERIOD;
    const int32_t ki_eff = (int32_t)((int64_t)_settings.ki * dt_ms / 1000); // Ki * dt
    const int32_t kd_eff = (int32_t)((int64_t)_settings.kd * 1000 / dt_ms); // Kd / dt

    // Calculate each term (still in PID_Q amplified domain)
    int32_t p_term = _settings.kp * error;
    int32_t d_term = kd_eff * (error - pid->prev_error);

    // Estimate unsaturated output
    int32_t out_unsat = p_term + pid->integral + d_term;

    // Saturation boundaries (Q domain)
    const int32_t hi_q = OUTPUT_MAX * PID_Q;
    const int32_t lo_q = OUTPUT_MIN * PID_Q;
    // Below this threshold, the fan is considered off

    bool sat_hi = out_unsat > hi_q;
    bool sat_lo = out_unsat < lo_q;

    // Conditional integration:
    // - Can integrate if not saturated
    // - If already high saturated, allow integration only when error decreases (error < 0) to help "desaturate"
    // - If already low saturated, allow integration only when error increases (error > 0)
    bool allow_i = true;
    if (sat_hi && error > 0)
        allow_i = false;
    if (sat_lo && error < 0)
        allow_i = false;

    if (abs(error) > 1 && allow_i) {
        int64_t new_i = (int64_t)pid->integral + (int64_t)ki_eff * error;
        if (new_i > PID_INTEGRAL_MAX)
            new_i = PID_INTEGRAL_MAX;
        if (new_i < PID_INTEGRAL_MIN)
            new_i = PID_INTEGRAL_MIN;
        pid->integral = (int32_t)new_i;
    }

    pid->prev_error = error;

    // Recalculate and quantize to 0..100
    int32_t out_q = p_term + pid->integral + d_term;
    uint8_t out;
    if (out_q <= lo_q) {
        out = 0;
        // Turn off if below the starting threshold
    }
    else if (out_q >= hi_q) {
        out = OUTPUT_MAX;
    }
    else {
        out = (uint8_t)(out_q / PID_Q);
    }

    int32_t delta = (int32_t)out - pid->last_output;
    if (delta > PID_MAX_STEP)
        delta = PID_MAX_STEP;
    if (delta < -PID_MAX_STEP)
        delta = -PID_MAX_STEP;
    out = (uint8_t)(pid->last_output + delta);

    pid->last_output = out;
    return out;
}

#endif // CONFIG_LYFI_NTC_SUPPORT

int thermal_set_fan_mode(int fan_mode)
{
    if (fan_mode < 0 || fan_mode >= THERMAL_FAN_MODE_SIZE) {
        return -EINVAL;
    }

    if (fan_mode == _settings.fan_mode) {
        return 0;
    }

    nvs_handle_t handle;
    BO_TRY(bo_nvs_user_open(THERMAL_NVS_USER_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    BO_TRY(nvs_set_u8(handle, THERMAL_NVS_KEY_FAN_MODE, fan_mode));
    _settings.fan_mode = fan_mode;

    BO_TRY(nvs_commit(handle));
    BO_TRY(thermal_reinit());
    return 0;
}

int thermal_set_manual_fan_power(uint8_t power)
{
    if (power > 100) {
        return -EINVAL;
    }

    if (power == _settings.fan_manual_power) {
        return 0;
    }

    nvs_handle_t handle;
    BO_TRY(bo_nvs_user_open(THERMAL_NVS_USER_NS, NVS_READWRITE, &handle));
    BO_NVS_AUTO_CLOSE(handle);

    BO_TRY(nvs_set_u8(handle, THERMAL_NVS_KEY_FAN_MANUAL_POWER, power));
    _settings.fan_manual_power = power;

    BO_TRY(nvs_commit(handle));
    return 0;
}

#endif // CONFIG_LYFI_THERMAL_ENABLED