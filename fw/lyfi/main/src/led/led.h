#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#include <smf/smf.h>
#include <stdatomic.h>
#include <freertos/FreeRTOS.h>

#include <borneo/algo/astronomy.h>
#include <freertos/portmacro.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LYFI_LEDC_SCHEDULER_ITEMS_CAPACITY 48

typedef uint16_t led_brightness_t;
typedef uint16_t led_duty_t;
typedef uint16_t led_virtual_brightness_t;
typedef led_brightness_t led_color_t[CONFIG_LYFI_LED_CHANNEL_COUNT];
typedef led_duty_t led_duties_t[CONFIG_LYFI_LED_CHANNEL_COUNT];
typedef led_virtual_brightness_t led_virtual_color_t[CONFIG_LYFI_LED_CHANNEL_COUNT];

#define LED_BRIGHTNESS_MIN ((led_brightness_t)0)
#define LED_BRIGHTNESS_MAX ((led_brightness_t)4095)
#define LED_VIRTUAL_BRIGHTNESS_MAX ((led_virtual_brightness_t)65535)

#define LED_ACCLIMATION_DAYS_MAX 100
#define LED_ACCLIMATION_DAYS_MIN 5

enum led_usage_enum {
    LED_USAGE_GENERAL = 0,
    LED_USAGE_FRESHWATER = 1,
    LED_USAGE_MARINE = 2,
    LED_USAGE_TERRA = 3,
    LED_USAGE_CINEMA = 4,
    LED_USAGE_HOME = 4,
};

enum led_correction_methods {
    LED_CORRECTION_LOG = 0,
    LED_CORRECTION_LINEAR = 1,
    LED_CORRECTION_EXP = 2, ///< Default
    LED_CORRECTION_GAMMA = 3,
    LED_CORRECTION_CIE1931 = 4,

    LED_CORRECTION_COUNT,
};

enum led_status_enum {
    LED_STATE_NORMAL = 0,
    LED_STATE_DIMMING = 1,
    LED_STATE_TEMPORARY = 2,
    LED_STATE_PREVIEW = 3,
    LED_STATE_DISCO = 4,

    LED_STATE_COUNT,
};

enum led_running_modes {
    LED_MODE_MANUAL = 0,
    LED_MODE_SCHEDULED = 1,
    LED_MODE_SUN = 2,

    LED_MODE_COUNT,
};

enum led_option_flags {
    LED_OPTION_MOON_ENABLED = 1,
    LED_OPTION_HAS_GEO_LOCATION = 2,
    LED_OPTION_ACCLIMATION_ENABLED = 4, ///< Whether acclimation is enabled
    LED_OPTION_TZ_ENABLED = 8, ///< Whether timezone is enabled
    LED_OPTION_CLOUD_ENABLED = 16, ///< Whether cloud overlay is enabled
};

struct led_scheduler_item {
    uint32_t instant;
    led_color_t color;
};

struct led_scheduler {
    size_t item_count;
    struct led_scheduler_item items[LYFI_LEDC_SCHEDULER_ITEMS_CAPACITY];
    // struct led_scheduler_item items[]; FIXME TODO
};

struct led_channel_settings {
    char name[16]; ///< Channel name (15 chars + \0)
    char color[8]; ///< Channel color in hex format (e.g., "#F44336")
    int16_t wavelength; ///< Channel wavelength in nm (0 = unknown)
    int16_t wavelength2; ///< Channel wavelength2 in nm (0 = unknown)
    float factor; ///< Power factor of this channel
    float ratio; ///< The power ratio of the two wavelength beads
};

struct led_factory_settings {
    uint8_t usage; ///< Usage
    uint16_t nominal_pfd; ///< Nominal pfd
    uint16_t nominal_power; ///< Nominal power in Watts
    uint8_t channel_count; ///< PWM channel count
    uint16_t pwm_freq; ///< The frequency of PWM signals
    struct led_channel_settings channels[CONFIG_LYFI_LED_CHANNEL_COUNT]; ///< Channel settings (name, color)
};

struct led_acclimation_settings {
    time_t start_utc;
    uint8_t duration; ///< In days
    uint8_t start_percent; ///< [0, 100%]
};

struct led_user_settings {
    uint8_t mode; ///< Running mode, see `enum led_running_modes`

    uint32_t temporary_duration; ///< Night lighting state duration (in seconds)
    struct led_scheduler scheduler; ///< Scheduling scheduler for scheduled state
    led_color_t manual_color; ///< Manual dimming color settings.
    led_color_t sun_color; ///< Sun simulation color settings.
    led_color_t moon_color; ///< Moon simulation color settings.
    uint8_t correction_method; ///< Brightness correction method: Log/Exp/Linear/CIE1931

    struct geo_location location; ///< The location for Solar and Lunar simulation.
    int32_t tz_offset; ///< The timezone offset in seconds

    struct led_acclimation_settings acclimation;

    uint32_t flags; ///< The option flags
};

struct led_status {
    struct smf_ctx ctx; ///< SMF context, must be the first member

    led_color_t color; ///< Current hardware LED power percentage for each channel
    int64_t temporary_off_time; ///< Time point after temporary lighting state to turn off, this time point is when
                                ///< fading out starts
    time_t preview_state_clock; ///< Clock for preview state
    led_color_t color_to_resume; ///< Color to be resumed

    led_color_t fade_start_color;
    led_color_t fade_end_color;
    led_virtual_color_t fade_start_virtual_color;
    led_virtual_color_t fade_end_virtual_color;
    led_virtual_color_t fade_current_virtual_color;
    int64_t fade_start_time_ms; ///< Time point of fading started
    uint32_t fade_duration_ms; ///< The duration of fading
    atomic_bool fade_active; ///< Lock-free flag for whether fading is active

    time_t sun_next_reschedule_time_utc; ///< The next rescheduling time in UTC
    struct led_scheduler sun_scheduler; ///< The scheduler of sun simulation for today

    time_t moon_next_recalc_time_utc; ///< The next recalculation time in UTC
    struct led_scheduler moon_scheduler; ///< The scheduler of moon simulation for today
    bool moon_activated;

    struct led_user_settings settings;
    SemaphoreHandle_t settings_lock;

    bool acclimation_activated;

    // Cloud overlay (micro cloud shadow) runtime state
    bool cloud_activated; ///< Whether cloud event is currently active
    uint32_t cloud_start_ms;
    uint32_t cloud_duration_ms;
    uint32_t cloud_next_fire_ms;
    uint16_t cloud_drop_bp; ///< Drop in basis points (1% = 100 bp)

    int64_t dimming_timeout_deadline_ms; ///< Deadline timestamp for DIMMING mode timeout
};

extern struct led_status _led;
extern portMUX_TYPE g_led_spinlock;

extern const led_duty_t LED_CORLUT_CIE1931[LED_BRIGHTNESS_MAX + 1];
extern const led_duty_t LED_CORLUT_LOG[LED_BRIGHTNESS_MAX + 1];
extern const led_duty_t LED_CORLUT_GAMMA[LED_BRIGHTNESS_MAX + 1];
extern const led_duty_t LED_CORLUT_EXP[LED_BRIGHTNESS_MAX + 1];

int led_init();

size_t led_channel_count();

void led_blank();

int led_set_color(const led_color_t color);

int led_get_color(led_color_t color);

int led_get_duties(led_duty_t* duties);

led_brightness_t led_get_channel_power(uint8_t ch);

int led_set_channel_brightness(uint8_t ch, led_brightness_t value);

int led_update_color(const led_color_t color);

int led_set_schedule(const struct led_scheduler_item* items, size_t count);
const struct led_scheduler* led_get_schedule();

const struct led_user_settings* led_get_settings();
const struct led_factory_settings* led_get_factory_settings();
const char* led_get_channel_name(uint8_t ch);
const char* led_get_channel_color(uint8_t ch);
int16_t led_get_channel_wavelength(uint8_t ch);
const struct led_status* led_get_status();

portMUX_TYPE* led_get_lock();

uint8_t led_get_state();
uint8_t led_get_previous_state();

int led_switch_state(uint8_t state);

int led_switch_mode(uint8_t mode);

bool led_is_blank();

int led_set_temporary_duration(uint32_t duration);
int32_t led_get_temporary_remaining();

int led_set_dimming_timeout(uint32_t timeout_sec);
uint32_t led_get_dimming_timeout();

int led_set_correction_method(uint8_t correction_method);

int led_fade_to_color(const led_color_t color, uint32_t milssecs);
bool led_is_fading();
int led_fade_stop();
int led_fade_to_normal();
void led_fade_drive();
int led_fade_black();

bool led_has_geo_location();
int led_set_geo_location(const struct geo_location* location);

int led_tz_enable(bool enabled);
int led_tz_set_offset(int32_t offset);

int led_load_factory_settings();
int led_load_user_settings();
int led_save_user_settings();

void led_sch_compute_color(const struct led_scheduler* sch, const struct tm* local_tm, led_color_t color);
void led_sch_compute_color_in_range(led_color_t color, const struct tm* tm_local,
                                    const struct led_scheduler_item* range_begin,
                                    const struct led_scheduler_item* range_end);

int led_sun_init();
int led_sun_update_scheduler();
bool led_sun_is_in_progress(const struct tm* local_tm);
void led_sun_drive(time_t utc_now, led_color_t color);
bool led_sun_can_active();

int led_moon_init();
int led_moon_update_scheduler();
bool led_moon_is_enabled();
int led_moon_set(const led_color_t color, bool enabled);
int led_moon_apply_filter(time_t utc_now, led_color_t color);

bool led_acclimation_is_enabled();
bool led_acclimation_is_activated();
int led_acclimation_drive(time_t utc_now, led_color_t color);
int led_acclimation_set(const struct led_acclimation_settings* settings, bool enabled);
int led_acclimation_terminate();

int led_cloud_init();
int led_cloud_enable(bool enabled);
bool led_cloud_is_enabled();
bool led_cloud_is_activated();
void led_cloud_drive(led_color_t color);

// Disco mode functions
int led_disco_init();
void led_disco_drive(time_t utc_now, led_color_t color);

static inline led_virtual_brightness_t led_brightness_to_virtual(led_brightness_t brightness)
{
    return (led_virtual_brightness_t)(((uint32_t)brightness * LED_VIRTUAL_BRIGHTNESS_MAX + (LED_BRIGHTNESS_MAX / 2))
                                      / LED_BRIGHTNESS_MAX);
}

static inline led_brightness_t led_virtual_to_brightness(led_virtual_brightness_t brightness)
{
    return (led_brightness_t)(((uint32_t)brightness * LED_BRIGHTNESS_MAX + (LED_VIRTUAL_BRIGHTNESS_MAX / 2))
                              / LED_VIRTUAL_BRIGHTNESS_MAX);
}

#ifdef __cplusplus
}
#endif