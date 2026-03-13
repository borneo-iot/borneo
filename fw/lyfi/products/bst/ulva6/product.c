#include <stdint.h>
#include <stdbool.h>
#include <../../main/src/led/led.h>

const struct led_user_settings LED_USER_DEFAULT_SETTINGS = {
    .mode = LED_MODE_MANUAL,
    .temporary_duration = 20,
    .manual_color = { 205, 205, 205, 205, 205, 205,},
    .correction_method = LED_CORRECTION_CIE1931,
    .sun_color = { 0 },
    .moon_color = { 0 },
    .scheduler = { 0 },
    .location = { // Kunming, China
        .lat = 25.0f,
        .lng = 102.7f,
    },
    .tz_offset = 8 * 3600, // UTC+8
    .flags = 0ULL,
    .acclimation = {
        .start_utc = 0,
        .duration = 30,
        .start_percent = 30,
    },
};

const struct led_factory_settings LED_FACTORY_DEFAULT_SETTINGS = {
    .nominal_pfd = 450,
    .nominal_power = 60,
    .pwm_freq = 19530,
    .channel_count = CONFIG_LYFI_LED_CHANNEL_COUNT,
    .channels = {
        { .name = "CW", .color = "#78909C", .wavelength = 15000, .factor = 0.16666 },
        { .name = "RB", .color = "#5C6BC0", .wavelength = 450, .factor = 0.25 },
        { .name = "B", .color = "#42A5F5", .wavelength = 470, .factor = 0.25 },
        { .name = "R", .color = "#EF5350", .wavelength = 620, .factor = 0.08333 },
        { .name = "G", .color = "#66BB6A", .wavelength = 520, .factor = 0.08333 },
        { .name = "VUV", .color = "#AB47BC", .wavelength = 415, .factor = 0.16666 },
    },
};
