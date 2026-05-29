#pragma once

/**
 * LED PWM driver abstraction
 *
 * Provides a hardware-independent interface for multi-channel LED PWM control.
 * Implemented by ledpwm_ledc.c (LEDC) and ledpwm_mcpwm.c (MCPWM).
 * The active backend is selected via Kconfig (LYFI_LED_PWM_BACKEND_*).
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <errno.h>

#include <drvfx/drvfx.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * LED PWM driver API – multi-channel hardware PWM abstraction.
 *
 * Drivers populate an instance of this struct and register it via
 * DRVFX_DEVICE_DEFINE so callers can use the inline wrappers below.
 */
struct ledpwm_driver_api {
    /**
     * Configure all PWM channels. Must be called once before set/get.
     *
     * @param dev           Driver device instance.
     * @param channel_count Number of active channels.
     * @param freq_hz       PWM carrier frequency in Hz.
     * @param gpios         GPIO number array, length must be >= channel_count.
     * @param output_invert True to invert all PWM outputs.
     * @return 0 on success, negative errno on failure.
     */
    int (*configure)(const struct drvfx_device* dev, uint8_t channel_count, uint32_t freq_hz, const uint8_t* gpios,
                     bool output_invert);

    /**
     * Set the duty cycle for a single channel.
     *
     * @param dev   Driver device instance.
     * @param ch    Channel index in [0, channel_count).
     * @param duty  Duty value in [0, get_max_duty()].
     * @return 0 on success, negative errno on failure.
     */
    int (*set_channel_duty)(const struct drvfx_device* dev, uint8_t ch, uint32_t duty);

    /**
     * Read back the current duty cycle of a channel.
     *
     * @param dev       Driver device instance.
     * @param ch        Channel index.
     * @param duty_out  Output pointer; receives current duty value.
     * @return 0 on success, negative errno on failure.
     */
    int (*get_channel_duty)(const struct drvfx_device* dev, uint8_t ch, uint32_t* duty_out);

    /**
     * Return the maximum duty value (inclusive) supported by this driver.
     * Typically 4095 for 12-bit resolution.
     */
    uint32_t (*get_max_duty)(const struct drvfx_device* dev);
};

/** drvfx device name used by k_device_get_binding(). */
#define LEDPWM_DEVICE_NAME "ledpwm"

/* ---- inline convenience wrappers ---- */

static inline int ledpwm_configure(const struct drvfx_device* dev, uint8_t channel_count, uint32_t freq_hz,
                                   const uint8_t* gpios, bool output_invert)
{
    const struct ledpwm_driver_api* api = dev ? (const struct ledpwm_driver_api*)dev->api : NULL;
    if (!api || !api->configure) {
        return -ENOSYS;
    }
    return api->configure(dev, channel_count, freq_hz, gpios, output_invert);
}

static inline int ledpwm_set_channel_duty(const struct drvfx_device* dev, uint8_t ch, uint32_t duty)
{
    const struct ledpwm_driver_api* api = dev ? (const struct ledpwm_driver_api*)dev->api : NULL;
    if (!api || !api->set_channel_duty) {
        return -ENOSYS;
    }
    return api->set_channel_duty(dev, ch, duty);
}

static inline int ledpwm_get_channel_duty(const struct drvfx_device* dev, uint8_t ch, uint32_t* duty_out)
{
    const struct ledpwm_driver_api* api = dev ? (const struct ledpwm_driver_api*)dev->api : NULL;
    if (!api || !api->get_channel_duty) {
        return -ENOSYS;
    }
    return api->get_channel_duty(dev, ch, duty_out);
}

static inline uint32_t ledpwm_get_max_duty(const struct drvfx_device* dev)
{
    const struct ledpwm_driver_api* api = dev ? (const struct ledpwm_driver_api*)dev->api : NULL;
    if (!api || !api->get_max_duty) {
        return 0;
    }
    return api->get_max_duty(dev);
}

#ifdef __cplusplus
}
#endif
