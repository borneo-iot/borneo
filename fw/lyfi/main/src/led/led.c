#include <string.h>
#include <errno.h>
#include <math.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>
#include <driver/ledc.h>
#include <esp_err.h>
#include <esp_log.h>
#include <nvs_flash.h>
#include <esp_rom_md5.h>
#include <esp_task_wdt.h>

#include <smf/smf.h>
#include <drvfx/drvfx.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/algo/astronomy.h>
#include <borneo/wifi.h>
#include <borneo/timer.h>

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
#include <borneo/devices/sensor.h>
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

#include "../lyfi-events.h"
#include "../algo.h"
#include "led.h"

static const struct smf_state LED_STATE_TABLE[];

void led_sch_drive(time_t utc_now, led_color_t color);

static void system_events_handler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data);
static void led_events_handler(void* handler_args, esp_event_base_t base, int32_t id, void* event_data);

static void led_render_task(void*);
static void led_handle_pending_requests(uint32_t notifications);
static void led_handle_temporary_toggle_request();
static void led_handle_fault_shutdown_request();
static void led_handle_scheduled_shutdown_request();
static void led_handle_power_on_request();
static int led_switch_state_now(uint8_t state);
static int led_request_state_switch(uint8_t state, bool wait_for_completion);
static bool led_is_render_task_context();

static void led_temporary_state_entry(void*);
static void led_temporary_state_run(void*);
static void led_temporary_state_exit(void*);

static void disco_state_entry(void*);
static void disco_state_run(void*);
static void disco_state_exit(void*);

static void normal_state_entry(void*);
static void normal_state_run(void*);
static void normal_state_exit(void*);

static void preview_state_entry(void*);
static void preview_state_run(void*);
static void preview_state_exit(void*);

static void dimming_state_entry(void*);
static void dimming_state_run(void*);
static void dimming_state_exit(void*);

static inline void led_dimming_reset_timeout();

#define TAG "lyfi-ledc"

#define TASK_PRIORITY 15
#define SECS_PER_DAY 86400
#define LED_MAX_DUTY ((1 << LEDC_TIMER_12_BIT) - 1)
#define LED_DUTY_RES LEDC_TIMER_12_BIT

#define LED_UPDATE_PERIOD_US 10000 // 10ms
#define LED_UPDATE_PERIOD_TICKS (pdMS_TO_TICKS(10)) // Ticks in 10ms
#define TEMPORARY_FADE_PERIOD_MS 7000
#define LED_CHANNEL_SELF_TEST_WAIT_MS 500

#define LED_TASK_NOTIFY_TEMPORARY_TOGGLE BIT0
#define LED_TASK_NOTIFY_FAULT_SHUTDOWN BIT1
#define LED_TASK_NOTIFY_SCHEDULED_SHUTDOWN BIT2
#define LED_TASK_NOTIFY_POWER_ON BIT3
#define LED_TASK_NOTIFY_STATE_SWITCH BIT4

static inline led_duty_t channel_brightness_to_duty(led_brightness_t power);
static inline led_duty_t channel_virtual_brightness_to_duty(led_virtual_brightness_t brightness);
static inline void color_to_duties(const led_color_t color, led_duty_t* duties);
static int led_set_channel_duty(uint8_t ch, led_duty_t duty);
static int __attribute__((unused)) led_set_duties(const led_duty_t* duties);
static int led_set_channel_virtual_brightness(uint8_t ch, led_virtual_brightness_t brightness);

static int led_mode_manual_entry();
static int led_mode_scheduled_entry();
static int led_mode_sun_entry();

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
static int led_channel_self_test();
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

ESP_EVENT_DEFINE_BASE(LYFI_EVENTS);
/*
    LED_STATE_NORMAL = 0,
    LED_STATE_DIMMING = 1,
    LED_STATE_TEMPORARY = 2,
    LED_STATE_PREVIEW = 3,

    LED_STATE_COUNT,

    LED_STATE_NORMAL_MANUAL_MODE,
    LED_STATE_NORMAL_SCHEDULED_MODE,
    LED_STATE_NORMAL_SUN_MODE,
    */

static const struct smf_state LED_STATE_TABLE[] = {
    [LED_STATE_NORMAL] = SMF_CREATE_STATE(normal_state_entry, normal_state_run, normal_state_exit, NULL, NULL),

    [LED_STATE_DIMMING] = SMF_CREATE_STATE(dimming_state_entry, dimming_state_run, dimming_state_exit, NULL, NULL),

    [LED_STATE_TEMPORARY]
    = SMF_CREATE_STATE(led_temporary_state_entry, led_temporary_state_run, led_temporary_state_exit, NULL, NULL),

    [LED_STATE_PREVIEW] = SMF_CREATE_STATE(preview_state_entry, preview_state_run, preview_state_exit, NULL, NULL),

    [LED_STATE_DISCO] = SMF_CREATE_STATE(disco_state_entry, disco_state_run, disco_state_exit, NULL, NULL),
};

static const uint8_t LED_GPIOS[CONFIG_LYFI_LED_CHANNEL_COUNT] = {

#if CONFIG_LYFI_LED_CH0_GPIO >= 0
    CONFIG_LYFI_LED_CH0_GPIO,
#endif

#if CONFIG_LYFI_LED_CH1_GPIO >= 0
    CONFIG_LYFI_LED_CH1_GPIO,
#endif

#if CONFIG_LYFI_LED_CH2_GPIO >= 0
    CONFIG_LYFI_LED_CH2_GPIO,
#endif

#if CONFIG_LYFI_LED_CH3_GPIO >= 0
    CONFIG_LYFI_LED_CH3_GPIO,
#endif

#if CONFIG_LYFI_LED_CH4_GPIO >= 0
    CONFIG_LYFI_LED_CH4_GPIO,
#endif

#if CONFIG_LYFI_LED_CH5_GPIO >= 0
    CONFIG_LYFI_LED_CH5_GPIO,
#endif

#if CONFIG_LYFI_LED_CH6_GPIO >= 0
    CONFIG_LYFI_LED_CH6_GPIO,
#endif

#if CONFIG_LYFI_LED_CH7_GPIO >= 0
    CONFIG_LYFI_LED_CH7_GPIO,
#endif

#if CONFIG_LYFI_LED_CH8_GPIO >= 0
    CONFIG_LYFI_LED_CH8_GPIO,
#endif

#if CONFIG_LYFI_LED_CH9_GPIO >= 0
    CONFIG_LYFI_LED_CH9_GPIO,
#endif
};

static const led_color_t LED_COLOR_BLANK = { 0 };

struct led_status _led;

portMUX_TYPE g_led_spinlock = portMUX_INITIALIZER_UNLOCKED;

struct led_state_switch_request {
    bool pending;
    uint8_t state;
    int* result_out;
    SemaphoreHandle_t completion;
};

static ledc_channel_config_t _ledc_channels[CONFIG_LYFI_LED_CHANNEL_COUNT] = { 0 };
static TaskHandle_t s_led_render_task_handle;
static struct led_state_switch_request s_led_state_switch_request;
/**
 * Initialize the LED controller
 *
 */
int led_init()
{
    ESP_LOGI(TAG, "Initializing LED controller....");

    memset(&_led, 0, sizeof(_led));
    memset(_ledc_channels, 0, sizeof(_ledc_channels));
    _led.fade_active = ATOMIC_VAR_INIT(false);

    _led.settings_lock = xSemaphoreCreateMutex();

    BO_TRY(led_load_factory_settings());
    const struct led_factory_settings* factory_settings = led_get_factory_settings();

    BO_TRY(led_load_user_settings());

    ESP_LOGI(TAG, "Initializing PWM timer for LEDC....");
    ESP_LOGI(TAG, "Total channel count: %u", CONFIG_LYFI_LED_CHANNEL_COUNT);
    ESP_LOGI(TAG, "Enabled channel count: %u", factory_settings->channel_count);

    // Initialize the first timer
    // TODO allow set the freq in product definition
    ledc_timer_config_t ledc_timer = {
        .clk_cfg = LEDC_AUTO_CLK,
        .duty_resolution = LEDC_TIMER_12_BIT,
        .freq_hz = factory_settings->pwm_freq,

#if SOC_LEDC_SUPPORT_HS_MODE
        .speed_mode = LEDC_HIGH_SPEED_MODE,
        .timer_num = LEDC_TIMER_0,
#else
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .timer_num = LEDC_TIMER_1,
#endif
    };

    BO_TRY_ESP(ledc_timer_config(&ledc_timer));

    // More than 8 channels need to initialize the second timer
    if (CONFIG_LYFI_LED_CHANNEL_COUNT > 8) {
        ledc_timer.speed_mode = LEDC_LOW_SPEED_MODE;
        ledc_timer.timer_num = LEDC_TIMER_1;
        BO_TRY_ESP(ledc_timer_config(&ledc_timer));
    }

    ESP_LOGI(TAG, "PWM timer initialized.");

    // Initialize all channels
    for (size_t ch = 0; ch < CONFIG_LYFI_LED_CHANNEL_COUNT; ch++) {
        _ledc_channels[ch].gpio_num = LED_GPIOS[ch];
        _ledc_channels[ch].hpoint = (ch * LED_MAX_DUTY) / led_channel_count();
#if SOC_LEDC_SUPPORT_HS_MODE
        if (ch <= 7) { // the next timer
            _ledc_channels[ch].speed_mode = LEDC_HIGH_SPEED_MODE;
            _ledc_channels[ch].timer_sel = LEDC_TIMER_0;
        }
        else {
            _ledc_channels[ch].speed_mode = LEDC_LOW_SPEED_MODE;
            _ledc_channels[ch].timer_sel = LEDC_TIMER_1;
        }
#else
        _ledc_channels[ch].speed_mode = LEDC_LOW_SPEED_MODE;
        _ledc_channels[ch].timer_sel = LEDC_TIMER_1;
#endif
        _ledc_channels[ch].duty = 0;
        _ledc_channels[ch].channel = (uint8_t)ch % 8;
        ESP_LOGI(TAG, "Configure GPIO [%u] as PWM Channel [%u], hpoint=[%u]", _ledc_channels[ch].gpio_num,
                 _ledc_channels[ch].channel, _ledc_channels[ch].hpoint);
        BO_TRY_ESP(ledc_channel_config(&_ledc_channels[ch]));
    }

    // Initialize fade service.
    BO_TRY_ESP(ledc_fade_func_install(0));

    smf_set_initial(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_NORMAL]);

    BO_TRY_ESP(esp_event_handler_register(LYFI_EVENTS, ESP_EVENT_ANY_ID, led_events_handler, NULL));
    BO_TRY_ESP(esp_event_handler_register(BO_SYSTEM_EVENTS, ESP_EVENT_ANY_ID, system_events_handler, NULL));

    BO_TRY(led_cloud_init());

    ESP_LOGI(TAG, "Starting LED controller...");

    if (_led.settings.mode == LED_MODE_SUN) {
        BO_TRY(led_sun_init());
    }

    BO_TRY(led_moon_init());

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
    // Perform LED channel self-test
    BO_TRY(led_channel_self_test());
#endif

    if (xTaskCreate(&led_render_task, "led_render_task", 8 * 1024, NULL, TASK_PRIORITY, &s_led_render_task_handle)
        != pdPASS) {
        s_led_render_task_handle = NULL;
        return -ENOMEM;
    }

    ESP_LOGI(TAG, "LED Controller module has been initialized successfully.");
    return 0;
}

inline uint8_t led_get_state() { return _led.ctx.current - &LED_STATE_TABLE[0]; }

inline uint8_t led_get_previous_state()
{
    if (_led.ctx.previous == NULL) {
        return LED_STATE_COUNT;
    }
    return _led.ctx.previous - &LED_STATE_TABLE[0];
}

inline portMUX_TYPE* led_get_lock() { return &g_led_spinlock; }

#if CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT
static int led_channel_self_test()
{
    ESP_LOGI(TAG, "Starting LED channel self-test...");

    const struct drvfx_device* power_sensor_dev = k_device_get_binding("sensor.led_power");
    if (power_sensor_dev == NULL) {
        ESP_LOGW(TAG, "Power sensor not available, skipping self-test");
        return 0;
    }

    // Self-test each channel
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        ESP_LOGI(TAG, "Testing channel %u...", ch);

        // Set channel to 100% (max duty)
        led_duty_t max_duty = LED_MAX_DUTY;
        int rc = led_set_channel_duty(ch, max_duty);
        if (rc != 0) {
            ESP_LOGW(TAG, "Channel %u: Failed to set duty", ch);
            continue;
        }

        // Wait for stable reading
        vTaskDelay(pdMS_TO_TICKS(LED_CHANNEL_SELF_TEST_WAIT_MS));

        // Read power, voltage, and current
        int32_t power_mw;
        rc = sensor_get_value(power_sensor_dev, &power_mw);
        if (rc == 0) {
            ESP_LOGI(TAG, "Channel %u: Power = %ld mW", ch, power_mw);
        }
        else {
            ESP_LOGW(TAG, "Channel %u: Failed to read power (error %d)", ch, rc);
        }

        // Turn off channel
        rc = led_set_channel_duty(ch, 0);
        if (rc != 0) {
            ESP_LOGW(TAG, "Channel %u: Failed to turn off", ch);
        }

        // Small delay before next channel
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    ESP_LOGI(TAG, "LED channel self-test completed");
    return 0;
}
#endif // CONFIG_LYFI_PROTECTION_OVERPOWER_SUPPORT

void led_blank()
{
    if (memcmp(_led.color, LED_COLOR_BLANK, sizeof(led_color_t)) != 0) {
        led_update_color(LED_COLOR_BLANK);
    }
}

int led_set_color(const led_color_t color)
{
    if (k_get_mode() != KERNEL_MODE_NORMAL) {
        return -EINVAL;
    }

    if (!(bo_power_is_on() && led_get_state() == LED_STATE_DIMMING)) {
        return -EINVAL;
    }
    // Verify the colors
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        if (color[ch] > LED_BRIGHTNESS_MAX) {
            return -EINVAL;
        }
    }

    portENTER_CRITICAL(&g_led_spinlock);
    switch (_led.settings.mode) {
    case LED_MODE_MANUAL:
        memcpy(_led.settings.manual_color, color, sizeof(led_color_t));
        break;
    case LED_MODE_SUN:
        memcpy(_led.settings.sun_color, color, sizeof(led_color_t));
        break;
    default:
        break;
    }
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_TRY(led_update_color(color));

    if (led_get_state() == LED_STATE_DIMMING) {
        led_dimming_reset_timeout();
    }

    return 0;
}

int led_get_color(led_color_t color)
{
    portENTER_CRITICAL(&g_led_spinlock);
    memcpy(color, _led.color, sizeof(led_color_t));
    portEXIT_CRITICAL(&g_led_spinlock);
    return ESP_OK;
}

led_brightness_t led_get_channel_power(uint8_t ch)
{
    BO_MUST(ch < led_channel_count());
    portENTER_CRITICAL(&g_led_spinlock);
    led_brightness_t value = _led.color[ch];
    portEXIT_CRITICAL(&g_led_spinlock);
    return value;
}

inline led_duty_t channel_brightness_to_duty(led_brightness_t brightness)
{
    switch (_led.settings.correction_method) {
    case LED_CORRECTION_CIE1931:
        return LED_CORLUT_CIE1931[brightness];

    case LED_CORRECTION_GAMMA:
        return LED_CORLUT_GAMMA[brightness];

    case LED_CORRECTION_LOG:
        return LED_CORLUT_LOG[brightness];

    case LED_CORRECTION_EXP:
        return LED_CORLUT_EXP[brightness];

    default: {
        if (LED_MAX_DUTY == LED_BRIGHTNESS_MAX) {
            return brightness;
        }
        else {
            return (led_duty_t)(((uint32_t)brightness * LED_MAX_DUTY + (LED_BRIGHTNESS_MAX / 2)) / LED_BRIGHTNESS_MAX);
        }
    } break;
    }
}

inline led_duty_t channel_virtual_brightness_to_duty(led_virtual_brightness_t brightness)
{
    const led_duty_t* lut = NULL;

    switch (_led.settings.correction_method) {
    case LED_CORRECTION_CIE1931:
        lut = LED_CORLUT_CIE1931;
        break;

    case LED_CORRECTION_GAMMA:
        lut = LED_CORLUT_GAMMA;
        break;

    case LED_CORRECTION_LOG:
        lut = LED_CORLUT_LOG;
        break;

    case LED_CORRECTION_EXP:
        lut = LED_CORLUT_EXP;
        break;

    default:
        return (led_duty_t)(((uint32_t)brightness * LED_MAX_DUTY + (LED_VIRTUAL_BRIGHTNESS_MAX / 2))
                            / LED_VIRTUAL_BRIGHTNESS_MAX);
    }

    uint32_t position = (uint32_t)brightness * LED_BRIGHTNESS_MAX;
    uint32_t index = position / LED_VIRTUAL_BRIGHTNESS_MAX;
    uint32_t fraction = position % LED_VIRTUAL_BRIGHTNESS_MAX;

    if (index >= LED_BRIGHTNESS_MAX) {
        return lut[LED_BRIGHTNESS_MAX];
    }

    uint32_t low = lut[index];
    uint32_t high = lut[index + 1];
    return (led_duty_t)(low
                        + (((high - low) * fraction + (LED_VIRTUAL_BRIGHTNESS_MAX / 2)) / LED_VIRTUAL_BRIGHTNESS_MAX));
}

inline void color_to_duties(const led_color_t color, led_duty_t* duties)
{
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        duties[ch] = channel_brightness_to_duty(color[ch]);
    }
}

int led_set_channel_duty(uint8_t ch, led_duty_t duty)
{
    if (ch >= led_channel_count() || duty > LED_MAX_DUTY) {
        return -1;
    }

    if (ledc_get_duty(_ledc_channels[ch].speed_mode, _ledc_channels[ch].channel) == (uint32_t)duty) {
        return 0;
    }

    uint32_t hpoint = _ledc_channels[ch].hpoint;
    BO_TRY_ESP(ledc_set_duty_and_update(_ledc_channels[ch].speed_mode, _ledc_channels[ch].channel, duty, hpoint));
    return 0;
}

int led_get_duties(led_duty_t* duties)
{
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        uint32_t duty = ledc_get_duty(_ledc_channels[ch].speed_mode, _ledc_channels[ch].channel);
        if (duty == LEDC_ERR_DUTY) {
            return -EIO;
        }
        duties[ch] = (led_duty_t)duty;
    }
    return 0;
}

int led_set_duties(const led_duty_t* duties)
{
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        led_duty_t duty = duties[ch];
        // Use pre-allocated hpoint from initialization, no dynamic recalculation
        uint32_t hpoint = _ledc_channels[ch].hpoint;
        BO_MUST(ledc_set_duty_and_update(_ledc_channels[ch].speed_mode, _ledc_channels[ch].channel, duty, hpoint));
    }
    return 0;
}

int led_set_channel_brightness(uint8_t ch, led_brightness_t brightness)
{
    if (ch >= led_channel_count() || brightness > LED_BRIGHTNESS_MAX) {
        return -EINVAL;
    }
    led_duty_t duty = channel_brightness_to_duty(brightness);
    BO_TRY_ESP(led_set_channel_duty(ch, duty));
    return 0;
}

int led_set_channel_virtual_brightness(uint8_t ch, led_virtual_brightness_t brightness)
{
    if (ch >= led_channel_count()) {
        return -EINVAL;
    }

    led_duty_t duty = channel_virtual_brightness_to_duty(brightness);
    BO_TRY_ESP(led_set_channel_duty(ch, duty));
    return 0;
}

int led_update_color(const led_color_t color)
{
    portENTER_CRITICAL(&g_led_spinlock);

    if (memcmp(color, _led.color, sizeof(led_color_t)) == 0) {
        goto __EXIT;
    }
    memcpy(_led.color, color, sizeof(led_color_t));

__EXIT:
    portEXIT_CRITICAL(&g_led_spinlock);
    return 0;
}

int led_set_schedule(const struct led_scheduler_item* items, size_t count)
{
    if (items == NULL) {
        return -EINVAL;
    }
    if (count > LYFI_LEDC_SCHEDULER_ITEMS_CAPACITY) {
        return -EINVAL;
    }

    if (count >= 2) {
        // Check the item array is sorted ascending and no duplicates
        for (size_t i = 1; i < count; i++) {
            if (items[i].instant <= items[i - 1].instant) {
                return -EINVAL;
            }
        }
        // Additional check for duplicate time points
        for (size_t i = 0; i < count; i++) {
            for (size_t j = i + 1; j < count; j++) {
                if (items[i].instant == items[j].instant) {
                    return -EINVAL;
                }
            }
        }
        // Check that the time range from first to last point does not exceed 24 hours
        if ((items[count - 1].instant - items[0].instant) >= SECS_PER_DAY) {
            return -EINVAL;
        }
    }

    if (count > 0 && items[count - 1].instant >= SECS_PER_DAY * 2) {
        return -EINVAL;
    }

    portENTER_CRITICAL(&g_led_spinlock);
    if (count > 0) {
        memcpy(_led.settings.scheduler.items, items, sizeof(struct led_scheduler_item) * count);
        _led.settings.scheduler.item_count = count;
    }
    else {
        memset(&_led.settings.scheduler, 0, sizeof(_led.settings.scheduler));
    }
    portEXIT_CRITICAL(&g_led_spinlock);

    return 0;
}

const struct led_scheduler* led_get_schedule() { return &_led.settings.scheduler; }

const struct led_user_settings* led_get_settings() { return &_led.settings; }

const struct led_status* led_get_status() { return &_led; }

bool led_is_blank()
{
    bool blank = true;
    portENTER_CRITICAL(&g_led_spinlock);
    for (size_t ch = 0; ch < led_channel_count(); ch++) {
        if (_led.color[ch] > 0) {
            blank = false;
            break;
        }
    }
    portEXIT_CRITICAL(&g_led_spinlock);
    return blank;
}

static void system_events_handler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case BO_EVENT_SHUTDOWN_FAULT:
    case BO_EVENT_FATAL_ERROR: {
        if (s_led_render_task_handle != NULL) {
            xTaskNotify(s_led_render_task_handle, LED_TASK_NOTIFY_FAULT_SHUTDOWN, eSetBits);
        }
    } break;

    case BO_EVENT_SHUTDOWN_SCHEDULED: {
        if (s_led_render_task_handle != NULL) {
            xTaskNotify(s_led_render_task_handle, LED_TASK_NOTIFY_SCHEDULED_SHUTDOWN, eSetBits);
        }
    } break;

    case BO_EVENT_POWER_ON: {
        if (s_led_render_task_handle != NULL) {
            xTaskNotify(s_led_render_task_handle, LED_TASK_NOTIFY_POWER_ON, eSetBits);
        }
    } break;

    case BO_EVENT_GEO_LOCATION_CHANGED: {
        int rc = led_sun_update_scheduler();
        if (rc) {
            ESP_LOGE(TAG, "Failed to update solar scheduler");
        }

        if (led_moon_is_enabled()) {
            rc = led_moon_update_scheduler();
            if (rc) {
                ESP_LOGE(TAG, "Failed to update moon scheduler");
            }
        }
    } break;

    default:
        break;
    }
}

static void led_events_handler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data)
{
    switch (event_id) {

    case LYFI_EVENT_LED_NOTIFY_TEMPORARY_STATE: {
        if (s_led_render_task_handle != NULL) {
            xTaskNotify(s_led_render_task_handle, LED_TASK_NOTIFY_TEMPORARY_TOGGLE, eSetBits);
        }
    } break;

    default:
        break;
    }
}

int led_mode_manual_entry()
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        return -EINVAL;
    }

    if (led_get_state() != LED_STATE_DIMMING) {
        return -EINVAL;
    }

    if (_led.settings.mode == LED_MODE_MANUAL) {
        return 0;
    }

    return 0;
}

int led_mode_scheduled_entry()
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        return -EINVAL;
    }

    if (led_get_state() != LED_STATE_DIMMING && led_get_state() != LED_STATE_PREVIEW) {
        return -EINVAL;
    }

    if (_led.settings.mode == LED_MODE_SCHEDULED) {
        return 0;
    }

    if (led_get_state() == LED_STATE_PREVIEW) {
        BO_TRY(led_switch_state(LED_STATE_DIMMING));
    }

    return 0;
}

int led_mode_sun_entry()
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        return -EINVAL;
    }

    if (!led_sun_can_active()) {
        return -EINVAL;
    }

    if (led_get_state() != LED_STATE_DIMMING) {
        return -EINVAL;
    }

    if (_led.settings.mode == LED_MODE_SUN) {
        return 0;
    }

    BO_TRY(led_sun_update_scheduler());

    return 0;
}

void led_render_task(void*)
{
    led_color_t last_color;
    led_virtual_color_t last_virtual_color = { 0 };
    memcpy(last_color, LED_COLOR_BLANK, sizeof(led_color_t));

    if (bo_power_is_on() && k_get_mode() != KERNEL_MODE_NORMAL) {
        BO_MUST(led_fade_to_normal());
    }

    BO_MUST_ESP(esp_task_wdt_add(NULL));

    // Maintain a strict 10ms refresh cadence; if work exceeds 10ms, skip this frame's HW update.
    TickType_t last_wake = xTaskGetTickCount();

    while (true) {
        esp_task_wdt_reset();

        int64_t frame_start_us = esp_timer_get_time();
        uint32_t notifications = 0;
        xTaskNotifyWait(0, UINT32_MAX, &notifications, 0);
        led_handle_pending_requests(notifications);

        int smf_ret = smf_run_state(SMF_CTX(&_led));
        if (smf_ret) {
            bo_panic();
        }

        // If SMF and other ops already exceed budget, skip this frame's HW sync to catch up.
        bool skip_hw_update = (esp_timer_get_time() - frame_start_us) >= LED_UPDATE_PERIOD_US;

        if (!skip_hw_update) {
            // Copy shared color state under lock only - HW update must NOT be inside critical section
            // because ledc_set_duty_and_update lazily allocates FreeRTOS objects (semaphores) on the
            // first call per channel, and creating FreeRTOS primitives with interrupts disabled is
            // undefined behaviour that corrupts scheduler state.
            led_color_t new_color;
            led_virtual_color_t new_virtual_color;
            bool fade_active;
            portENTER_CRITICAL(&g_led_spinlock);
            memcpy(new_color, _led.color, sizeof(led_color_t));
            memcpy(new_virtual_color, _led.fade_current_virtual_color, sizeof(led_virtual_color_t));
            fade_active = atomic_load_explicit(&_led.fade_active, memory_order_acquire);
            portEXIT_CRITICAL(&g_led_spinlock);

            // Sync color to hardware outside critical section
            bool color_changed = memcmp(last_color, new_color, sizeof(led_color_t)) != 0;
            bool virtual_changed = memcmp(last_virtual_color, new_virtual_color, sizeof(led_virtual_color_t)) != 0;
            if (fade_active && virtual_changed) {
                for (size_t ch = 0; ch < led_channel_count(); ch++) {
                    if (last_virtual_color[ch] != new_virtual_color[ch]) {
                        last_virtual_color[ch] = new_virtual_color[ch];
                        last_color[ch] = new_color[ch];
                        BO_MUST(led_set_channel_virtual_brightness(ch, last_virtual_color[ch]));
                    }
                }
            }
            else if (color_changed) {
                for (size_t ch = 0; ch < led_channel_count(); ch++) {
                    if (last_color[ch] != new_color[ch]) {
                        last_color[ch] = new_color[ch];
                        BO_MUST(led_set_channel_brightness(ch, last_color[ch]));
                    }
                }
            }
        }
        else {
            int64_t over_us = (esp_timer_get_time() - frame_start_us) - LED_UPDATE_PERIOD_US;
            // Log only when severely over budget to avoid spam
            if (over_us > LED_UPDATE_PERIOD_US) {
                ESP_LOGW(TAG, "LED render task overrun, skipping frame (over by %lld us)", over_us);
            }
        }

        // Wait until the next 10ms boundary; if overran, this returns immediately.
        vTaskDelayUntil(&last_wake, LED_UPDATE_PERIOD_TICKS);
    }
}

static void led_handle_pending_requests(uint32_t notifications)
{
    if (notifications & LED_TASK_NOTIFY_TEMPORARY_TOGGLE) {
        led_handle_temporary_toggle_request();
    }

    if (notifications & LED_TASK_NOTIFY_FAULT_SHUTDOWN) {
        led_handle_fault_shutdown_request();
    }

    if (notifications & LED_TASK_NOTIFY_SCHEDULED_SHUTDOWN) {
        led_handle_scheduled_shutdown_request();
    }

    if (notifications & LED_TASK_NOTIFY_POWER_ON) {
        led_handle_power_on_request();
    }

    if (notifications & LED_TASK_NOTIFY_STATE_SWITCH) {
        struct led_state_switch_request request = { 0 };
        bool has_request = false;

        portENTER_CRITICAL(&g_led_spinlock);
        if (s_led_state_switch_request.pending) {
            request = s_led_state_switch_request;
            s_led_state_switch_request.pending = false;
            has_request = true;
        }
        portEXIT_CRITICAL(&g_led_spinlock);

        if (has_request) {
            int rc = led_switch_state_now(request.state);
            if (request.result_out != NULL) {
                *request.result_out = rc;
            }
            if (request.completion != NULL) {
                xSemaphoreGive(request.completion);
            }
        }
    }
}

static void led_handle_temporary_toggle_request()
{
    if (!(bo_power_is_on() && k_get_mode() == KERNEL_MODE_NORMAL)) {
        return;
    }

    if (led_get_state() == LED_STATE_NORMAL
        && (_led.settings.mode == LED_MODE_SCHEDULED || _led.settings.mode == LED_MODE_SUN)) {
        BO_MUST(led_switch_state_now(LED_STATE_TEMPORARY));
        return;
    }

    if (led_get_state() == LED_STATE_TEMPORARY) {
        BO_MUST(led_switch_state_now(LED_STATE_NORMAL));
    }
}

static void led_handle_fault_shutdown_request()
{
    if (led_is_fading()) {
        BO_MUST(led_fade_stop());
    }

    led_blank();

    if (led_get_state() != LED_STATE_NORMAL) {
        BO_MUST(led_switch_state_now(LED_STATE_NORMAL));
    }
}

static void led_handle_scheduled_shutdown_request()
{
    int rc = led_fade_black();
    if (rc) {
        ESP_LOGE(TAG, "Failed to invoke `led_fade_black()`, errcode=%d", rc);
    }

    if (led_get_state() != LED_STATE_NORMAL) {
        BO_MUST(led_switch_state_now(LED_STATE_NORMAL));
    }
}

static void led_handle_power_on_request()
{
    if (k_get_mode() != KERNEL_MODE_NORMAL) {
        return;
    }

    int rc = led_fade_to_normal();
    if (rc) {
        ESP_LOGE(TAG, "Failed to invoke `led_fade_to_normal()`, errcode=%d", rc);
    }

    if (led_get_state() != LED_STATE_NORMAL) {
        rc = led_switch_state_now(LED_STATE_NORMAL);
        if (rc) {
            ESP_LOGE(TAG, "Failed to switch state to normal, errcode=%d", rc);
        }
    }
}

int led_switch_state(uint8_t state)
{
    if (led_is_render_task_context()) {
        return led_switch_state_now(state);
    }

    return led_request_state_switch(state, true);
}

static int led_switch_state_now(uint8_t state)
{
    if (state >= LED_STATE_COUNT) {
        return -EINVAL;
    }

    if (led_get_state() == state) {
        return -EINVAL;
    }

    if (k_get_mode() != KERNEL_MODE_NORMAL) {
        return -EINVAL;
    }

    if (!bo_power_is_on() && state != LED_STATE_NORMAL) {
        return -EINVAL;
    }

    ESP_LOGI(TAG, "Switching state from %u to %u", led_get_state(), state);

    uint8_t current_state = led_get_state();

    switch (state) {

    case LED_STATE_NORMAL:
        smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_NORMAL]);
        break;

    case LED_STATE_DIMMING: {
        if (current_state == LED_STATE_NORMAL || current_state == LED_STATE_TEMPORARY) {
            smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_DIMMING]);
        }
        else {
            return -EINVAL;
        }
    } break;

    case LED_STATE_TEMPORARY: {
        if (current_state == LED_STATE_NORMAL) {
            smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_TEMPORARY]);
        }
        else {
            return -EINVAL;
        }
    } break;

    case LED_STATE_PREVIEW: {
        if (current_state == LED_STATE_DIMMING) {
            smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_PREVIEW]);
        }
        else {
            return -EINVAL;
        }
    } break;

    case LED_STATE_DISCO: {
        // Can switch to DISCO from NORMAL state
        if (current_state == LED_STATE_NORMAL || current_state == LED_STATE_TEMPORARY) {
            smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_DISCO]);
        }
        else {
            return -EINVAL;
        }
    } break;

    default:
        return -1;
    }

    BO_TRY_ESP(esp_event_post(LYFI_EVENTS, LYFI_EVENT_LED_STATE_CHANGED, NULL, 0, portMAX_DELAY));

    return 0;
}

static int led_request_state_switch(uint8_t state, bool wait_for_completion)
{
    if (state >= LED_STATE_COUNT) {
        return -EINVAL;
    }

    if (s_led_render_task_handle == NULL) {
        return -EAGAIN;
    }

    SemaphoreHandle_t completion = NULL;
    int result = -EINPROGRESS;

    if (wait_for_completion) {
        completion = xSemaphoreCreateBinary();
        if (completion == NULL) {
            return -ENOMEM;
        }
    }

    portENTER_CRITICAL(&g_led_spinlock);
    if (s_led_state_switch_request.pending) {
        portEXIT_CRITICAL(&g_led_spinlock);
        if (completion != NULL) {
            vSemaphoreDelete(completion);
        }
        return -EBUSY;
    }

    s_led_state_switch_request.pending = true;
    s_led_state_switch_request.state = state;
    s_led_state_switch_request.result_out = wait_for_completion ? &result : NULL;
    s_led_state_switch_request.completion = completion;
    portEXIT_CRITICAL(&g_led_spinlock);

    xTaskNotify(s_led_render_task_handle, LED_TASK_NOTIFY_STATE_SWITCH, eSetBits);

    if (!wait_for_completion) {
        return 0;
    }

    xSemaphoreTake(completion, portMAX_DELAY);
    vSemaphoreDelete(completion);
    return result;
}

static bool led_is_render_task_context() { return xTaskGetCurrentTaskHandle() == s_led_render_task_handle; }

int led_switch_mode(uint8_t mode)
{
    if (mode >= LED_MODE_COUNT) {
        return -EINVAL;
    }

    if (mode == _led.settings.mode) {
        return -EINVAL;
    }

    if (!(led_get_state() == LED_STATE_DIMMING || led_get_state() == LED_STATE_PREVIEW)) {
        return -EINVAL;
    }

    switch (mode) {

    case LED_MODE_MANUAL: {
        BO_TRY(led_mode_manual_entry());
        ESP_LOGI(TAG, "Switched to LED mode: `manual`");
    } break;

    case LED_MODE_SCHEDULED: {
        BO_TRY(led_mode_scheduled_entry());
        ESP_LOGI(TAG, "Switched to LED mode: `scheduled`");
    } break;

    case LED_MODE_SUN: {
        BO_TRY(led_mode_sun_entry());
        ESP_LOGI(TAG, "Switched to LED mode: `sun`");
    } break;

    default:
        return -EINVAL;
    }

    portENTER_CRITICAL(&g_led_spinlock);
    _led.settings.mode = mode;
    portEXIT_CRITICAL(&g_led_spinlock);

    if (led_get_state() == LED_STATE_DIMMING) {
        led_dimming_reset_timeout();
    }

    BO_TRY_ESP(esp_event_post(LYFI_EVENTS, LYFI_EVENT_LED_MODE_CHANGED, NULL, 0, portMAX_DELAY));

    return 0;
}

int led_set_correction_method(uint8_t correction_method)
{
    if (correction_method >= LED_CORRECTION_COUNT) {
        return -EINVAL;
    }

    portENTER_CRITICAL(&g_led_spinlock);
    _led.settings.correction_method = correction_method;
    portEXIT_CRITICAL(&g_led_spinlock);

    BO_TRY(led_save_user_settings());
    return 0;
}

static void normal_state_entry(void*)
{
    if (_led.settings.mode == LED_MODE_SUN) {
        if (led_sun_can_active()) {
            BO_MUST(led_sun_update_scheduler());
        }
        else {
            ESP_LOGW(TAG, "Sun mode unavailable, fallback to MANUAL");
            _led.settings.mode = LED_MODE_MANUAL;
        }
    }

    if (led_get_previous_state() == LED_STATE_DIMMING || led_get_previous_state() == LED_STATE_PREVIEW) {
        BO_MUST(led_save_user_settings());
    }

    if (_led.ctx.previous != NULL) {
        BO_MUST(led_fade_to_normal());
    }
}

static void normal_state_run(void*)
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        if (led_is_fading()) {
            led_fade_drive();
            return;
        }
        led_blank();
        return;
    }

    if (led_is_fading()) {
        led_fade_drive();
        return;
    }

    led_color_t color;
    time_t utc_now = time(NULL);

    switch (_led.settings.mode) {
    case LED_MODE_MANUAL: {
        memcpy(color, _led.settings.manual_color, sizeof(led_color_t));
    } break;

    case LED_MODE_SCHEDULED: {
        led_sch_drive(utc_now, color);
    } break;

    case LED_MODE_SUN: {
        led_sun_drive(utc_now, color);
    } break;

    default:
        assert(false);
        break;
    }

    // Apply filters only when not fading and in proper state
    if (led_acclimation_is_enabled()) {
        BO_MUST(led_acclimation_drive(utc_now, color));
    }

    BO_MUST(led_moon_apply_filter(utc_now, color));

    // Optional cloud overlay (micro shadow) as a multiplicative filter

    if (_led.settings.flags & LED_OPTION_CLOUD_ENABLED) {
        led_cloud_drive(color);
    }

    BO_MUST(led_update_color(color));
}

void normal_state_exit(void*)
{
    if (led_is_fading()) {
        BO_MUST(led_fade_stop());
    }
    return;
}

void dimming_state_entry(void*)
{
    if (led_is_fading()) {
        BO_MUST(led_fade_stop());
    }

    ESP_LOGI(TAG, "Entering dimming mode.");

    led_dimming_reset_timeout();

    switch (_led.settings.mode) {

    case LED_MODE_MANUAL: {
        BO_MUST(led_mode_manual_entry());
    } break;

    case LED_MODE_SCHEDULED: {
        BO_MUST(led_mode_scheduled_entry());
    } break;

    case LED_MODE_SUN: {
        BO_MUST(led_mode_sun_entry());
    } break;

    default:
        return bo_panic();
    }
}

void dimming_state_run(void*)
{
    if (CONFIG_LYFI_DIMMING_TIMEOUT > 0) {
        int64_t now_ms = bo_timer_uptime_ms();
        int64_t deadline_ms;
        portENTER_CRITICAL(&g_led_spinlock);
        deadline_ms = _led.dimming_timeout_deadline_ms;
        portEXIT_CRITICAL(&g_led_spinlock);

        if (now_ms >= deadline_ms && deadline_ms > 0) {
            ESP_LOGW(TAG, "Dimming timeout reached (%lld >= %lld), switching back to NORMAL", now_ms, deadline_ms);
            smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_NORMAL]);
        }
    }
}

void dimming_state_exit(void*)
{
    portENTER_CRITICAL(&g_led_spinlock);
    _led.dimming_timeout_deadline_ms = 0;
    portEXIT_CRITICAL(&g_led_spinlock);
    ESP_LOGI(TAG, "Exiting dimming mode.");
}

static void preview_state_entry(void*)
{
    if (_led.settings.scheduler.item_count <= 1) {
        return;
    }
    time_t utc_now = time(NULL);
    struct tm local_today = { 0 };
    localtime_r(&utc_now, &local_today);
    local_today.tm_hour = 0;
    local_today.tm_min = 0;
    local_today.tm_sec = 0;

    portENTER_CRITICAL(&g_led_spinlock);
    memcpy(_led.color_to_resume, _led.color, sizeof(led_color_t));
    _led.preview_state_clock = mktime(&local_today) + _led.settings.scheduler.items[0].instant;
    portEXIT_CRITICAL(&g_led_spinlock);

    ESP_LOGI(TAG, "Preview state started.");
}

static void preview_state_run(void*)
{
    assert(led_get_state() == LED_STATE_PREVIEW);
    assert(_led.settings.scheduler.item_count > 0);

    time_t end_time
        = _led.preview_state_clock + _led.settings.scheduler.items[_led.settings.scheduler.item_count - 1].instant;
    led_color_t color;
    for (; led_get_state() == LED_STATE_PREVIEW && _led.preview_state_clock < end_time;
         _led.preview_state_clock += 60) {
        led_sch_drive(_led.preview_state_clock, color);
        BO_MUST(led_update_color(color));
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_DIMMING]);
}

static void preview_state_exit(void*)
{
    _led.preview_state_clock = 0;
    led_update_color(_led.color_to_resume);
    ESP_LOGI(TAG, "Preview state ended.");
}

// ========== DISCO State ==========

static void disco_state_entry(void*)
{
    ESP_LOGI(TAG, "Entering disco state.");

    // Initialize disco mode
    BO_MUST(led_disco_init());
}

static void disco_state_run(void*)
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        // If power off or not in normal kernel mode, return to normal state
        smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_NORMAL]);
        return;
    }

    led_color_t color;
    time_t utc_now = time(NULL);

    // Let disco drive function generate the color
    led_disco_drive(utc_now, color);

    // Update hardware
    BO_MUST(led_update_color(color));
}

static void disco_state_exit(void*) { ESP_LOGI(TAG, "Exiting disco state."); }

int led_set_temporary_duration(uint32_t duration)
{
    portENTER_CRITICAL(&g_led_spinlock);
    _led.settings.temporary_duration = duration;
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_TRY(led_save_user_settings());
    return 0;
}

int32_t led_get_temporary_remaining()
{
    if (led_get_state() == LED_STATE_TEMPORARY) {
        int64_t now = bo_timer_uptime_ms();
        return (int32_t)((_led.temporary_off_time - now + 500LL) / 1000LL);
    }
    else {
        return -1;
    }
}

static inline void led_dimming_reset_timeout()
{
    int64_t now_ms = bo_timer_uptime_ms();
    uint16_t timeout_sec = CONFIG_LYFI_DIMMING_TIMEOUT;

    if (timeout_sec > 0) {
        portENTER_CRITICAL(&g_led_spinlock);
        _led.dimming_timeout_deadline_ms = now_ms + (timeout_sec * 1000LL);
        portEXIT_CRITICAL(&g_led_spinlock);
    }
}

int led_set_dimming_timeout(uint32_t timeout_sec)
{
    // Dimming timeout is now fixed to CONFIG_LYFI_DIMMING_TIMEOUT
    return -ENOTSUP;
}

uint32_t led_get_dimming_timeout() { return CONFIG_LYFI_DIMMING_TIMEOUT; }

void led_temporary_state_entry(void*)
{
    if (!bo_power_is_on() || k_get_mode() != KERNEL_MODE_NORMAL) {
        return;
    }
    if (_led.settings.mode != LED_MODE_SUN && _led.settings.mode != LED_MODE_SCHEDULED) {
        return;
    }
    int64_t now = bo_timer_uptime_ms();
    portENTER_CRITICAL(&g_led_spinlock);
    _led.temporary_off_time = now + (_led.settings.temporary_duration * 60 * 1000);
    portEXIT_CRITICAL(&g_led_spinlock);
    BO_MUST(led_fade_to_color(_led.settings.manual_color, TEMPORARY_FADE_PERIOD_MS));
}

void led_temporary_state_exit(void*)
{
    assert(led_get_state() == LED_STATE_TEMPORARY);
    portENTER_CRITICAL(&g_led_spinlock);
    _led.temporary_off_time = 0;
    portEXIT_CRITICAL(&g_led_spinlock);
}

void led_temporary_state_run(void*)
{
    assert(led_get_state() == LED_STATE_TEMPORARY);

    int64_t now = bo_timer_uptime_ms();

    if (now >= _led.temporary_off_time) {
        smf_set_state(SMF_CTX(&_led), &LED_STATE_TABLE[LED_STATE_NORMAL]);
    }
    else {
        if (!led_is_fading()) {
            led_update_color(_led.settings.manual_color);
        }
        else {
            led_fade_drive();
        }
    }
}
