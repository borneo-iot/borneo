/**
 * LED PWM driver – ESP-IDF LEDC backend
 *
 * Wraps the ESP-IDF LEDC peripheral as a ledpwm drvfx driver.
 *
 * Features preserved from the original implementation:
 *  - Configurable duty resolution (CONFIG_LYFI_LED_PWM_RESOLUTION_BITS, default 12-bit)
 *  - Phase-shifted hpoints distributed evenly across all channels to
 *    reduce simultaneous switching noise and EMI
 *  - HS-mode channels on ESP32 targets that support them (SOC_LEDC_SUPPORT_HS_MODE)
 *  - Second timer for >8 channels
 *  - Output invert flag
 *
 * Activated by CONFIG_LYFI_LED_PWM_BACKEND_LEDC.
 */

#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>

#include <driver/ledc.h>
#include <esp_log.h>
#include <esp_err.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>

#include "ledpwm.h"

#define TAG "ledpwm_ledc"

#define LEDPWM_LEDC_DUTY_RESOLUTION ((ledc_timer_bit_t)CONFIG_LYFI_LED_PWM_RESOLUTION_BITS)
#define LEDPWM_LEDC_MAX_DUTY ((1u << CONFIG_LYFI_LED_PWM_RESOLUTION_BITS) - 1u)
#define LEDPWM_LEDC_MAX_CHANNELS CONFIG_LYFI_LED_CHANNEL_COUNT

struct ledpwm_ledc_data {
    ledc_channel_config_t channels[LEDPWM_LEDC_MAX_CHANNELS];
    bool configured;
};

#if CONFIG_LYFI_LED_PWM_BACKEND_LEDC

static int _init(const struct drvfx_device* dev)
{
    struct ledpwm_ledc_data* data = (struct ledpwm_ledc_data*)dev->data;
    memset(data, 0, sizeof(*data));
    return 0;
}

static int _configure(const struct drvfx_device* dev, uint8_t channel_count, uint32_t freq_hz, const uint8_t* gpios,
                      bool output_invert)
{
    struct ledpwm_ledc_data* data = (struct ledpwm_ledc_data*)dev->data;

    if (channel_count == 0 || channel_count > LEDPWM_LEDC_MAX_CHANNELS) {
        ESP_LOGE(TAG, "Invalid channel count: %u (max %d)", channel_count, LEDPWM_LEDC_MAX_CHANNELS);
        return -EINVAL;
    }

    ESP_LOGI(TAG, "Configuring LEDC: %u channels at %lu Hz", channel_count, freq_hz);

    ledc_timer_config_t ledc_timer = {
        .clk_cfg = LEDC_AUTO_CLK,
        .duty_resolution = LEDPWM_LEDC_DUTY_RESOLUTION,
        .freq_hz = freq_hz,
#if SOC_LEDC_SUPPORT_HS_MODE
        .speed_mode = LEDC_HIGH_SPEED_MODE,
        .timer_num = LEDC_TIMER_0,
#else
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .timer_num = LEDC_TIMER_1,
#endif
    };
    BO_TRY_ESP(ledc_timer_config(&ledc_timer));

    /* A second low-speed timer is needed when more than 8 channels are used
     * because LEDC provides only 8 HS + 8 LS channels.                      */
    if (channel_count > 8) {
        ledc_timer.speed_mode = LEDC_LOW_SPEED_MODE;
        ledc_timer.timer_num = LEDC_TIMER_1;
        BO_TRY_ESP(ledc_timer_config(&ledc_timer));
    }

    for (size_t ch = 0; ch < channel_count; ch++) {
        /* Distribute hpoints evenly across channels to phase-shift PWM edges.
         * This prevents all channels switching simultaneously, reducing peak
         * current draw and EMI.                                                */
        data->channels[ch].hpoint = (uint32_t)((uint64_t)ch * LEDPWM_LEDC_MAX_DUTY / channel_count);
        data->channels[ch].gpio_num = (int)gpios[ch];
        data->channels[ch].duty = 0;
        data->channels[ch].channel = (ledc_channel_t)(ch % 8);
        data->channels[ch].flags.output_invert = (unsigned int)output_invert;

#if SOC_LEDC_SUPPORT_HS_MODE
        if (ch < 8) {
            data->channels[ch].speed_mode = LEDC_HIGH_SPEED_MODE;
            data->channels[ch].timer_sel = LEDC_TIMER_0;
        }
        else {
            data->channels[ch].speed_mode = LEDC_LOW_SPEED_MODE;
            data->channels[ch].timer_sel = LEDC_TIMER_1;
        }
#else
        data->channels[ch].speed_mode = LEDC_LOW_SPEED_MODE;
        data->channels[ch].timer_sel = LEDC_TIMER_1;
#endif

        ESP_LOGI(TAG, "  ch%zu: GPIO=%d ledc_ch=%d hpoint=%lu invert=%d", ch, data->channels[ch].gpio_num,
                 (int)data->channels[ch].channel, data->channels[ch].hpoint, output_invert ? 1 : 0);
        BO_TRY_ESP(ledc_channel_config(&data->channels[ch]));
    }

    /* ledc_set_duty_and_update requires the fade ISR to be installed even when
     * not using hardware fades; install it here once per configuration.        */
    BO_TRY_ESP(ledc_fade_func_install(0));

    data->configured = true;
    ESP_LOGI(TAG, "LEDC configuration complete.");
    return 0;
}

static int _set_channel_duty(const struct drvfx_device* dev, uint8_t ch, uint32_t duty)
{
    const struct ledpwm_ledc_data* data = (const struct ledpwm_ledc_data*)dev->data;

    /* Skip the HW write when the duty has not changed (avoids unnecessary
     * register access and interrupt churn).                                    */
    if (ledc_get_duty(data->channels[ch].speed_mode, data->channels[ch].channel) == duty) {
        return 0;
    }

    /* ledc_set_duty_and_update atomically applies duty and hpoint so the
     * phase-shift relationship is preserved.                                   */
    BO_TRY_ESP(ledc_set_duty_and_update(data->channels[ch].speed_mode, data->channels[ch].channel, duty,
                                        data->channels[ch].hpoint));
    return 0;
}

static int _get_channel_duty(const struct drvfx_device* dev, uint8_t ch, uint32_t* duty_out)
{
    const struct ledpwm_ledc_data* data = (const struct ledpwm_ledc_data*)dev->data;
    uint32_t duty = ledc_get_duty(data->channels[ch].speed_mode, data->channels[ch].channel);
    if (duty == LEDC_ERR_DUTY) {
        return -EIO;
    }
    *duty_out = duty;
    return 0;
}

static uint32_t _get_max_duty(const struct drvfx_device* dev)
{
    (void)dev;
    return LEDPWM_LEDC_MAX_DUTY;
}

static const struct ledpwm_driver_api s_api = {
    .configure = _configure,
    .set_channel_duty = _set_channel_duty,
    .get_channel_duty = _get_channel_duty,
    .get_max_duty = _get_max_duty,
};

static struct ledpwm_ledc_data s_data = { 0 };

DRVFX_DEVICE_DEFINE(LEDPWM_DEVICE_NAME, _init, &s_data, NULL, DRVFX_INIT_POST_KERNEL_DEFAULT_PRIORITY, &s_api);

#endif /* CONFIG_LYFI_LED_PWM_BACKEND_LEDC */
