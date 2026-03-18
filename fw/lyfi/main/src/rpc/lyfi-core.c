#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <errno.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>

#include <cbor.h>

#include <drvfx/drvfx.h>
#include <borneo/system.h>
#include <borneo/common.h>
#include <borneo/devices/sensor.h>

#include "../fan.h"
#include "../led/led.h"
#include "../thermal.h"
#include "../coap-paths.h"
#include "../rpc/cbor-common.h"

#define TAG "lyfi-core-rpc"

static int _encode_channel_info_entry(CborEncoder* parent, const struct led_channel_settings* channel)
{
    CborEncoder ch_map;
    BO_TRY(cbor_encoder_create_map(parent, &ch_map, CborIndefiniteLength));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "n"));
    BO_TRY(cbor_encode_text_stringz(&ch_map, channel->name));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "c"));
    BO_TRY(cbor_encode_text_stringz(&ch_map, channel->color));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "w"));
    BO_TRY(cbor_encode_int(&ch_map, channel->wavelength));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "w2"));
    BO_TRY(cbor_encode_int(&ch_map, channel->wavelength2));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "f"));
    BO_TRY(cbor_encode_float(&ch_map, channel->factor));

    BO_TRY(cbor_encode_text_stringz(&ch_map, "r"));
    BO_TRY(cbor_encode_float(&ch_map, channel->ratio));

    BO_TRY(cbor_encoder_close_container(parent, &ch_map));

    return 0;
}

static int _encode_channel_info_array(CborEncoder* parent)
{
    size_t chcount = led_channel_count();
    CborEncoder channels_array;
    BO_TRY(cbor_encoder_create_array(parent, &channels_array, chcount));

    const struct led_factory_settings* factory = led_get_factory_settings();

    for (size_t ch = 0; ch < chcount; ch++) {
        BO_TRY(_encode_channel_info_entry(&channels_array, &factory->channels[ch]));
    }

    BO_TRY(cbor_encoder_close_container(parent, &channels_array));

    return 0;
}

static int _encode_channels_output_array(CborEncoder* parent, size_t chcount, const led_duties_t duties)
{
    CborEncoder channels_array;
    BO_TRY(cbor_encoder_create_array(parent, &channels_array, chcount));
    for (size_t ch = 0; ch < chcount; ch++) {
        led_duty_t duty = duties[ch];
        BO_TRY(cbor_encode_uint(&channels_array, duty));
    }
    BO_TRY(cbor_encoder_close_container(parent, &channels_array));

    return 0;
}

int bo_rpc_borneo_lyfi_color_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    led_color_t color;
    BO_TRY(led_get_color(color));
    BO_TRY(cbor_encode_color(retvals, color));

    return 0;
}

int bo_rpc_borneo_lyfi_color_put(const CborValue* args, CborEncoder* retvals)
{
    led_color_t color;
    CborValue value = *args;
    BO_TRY(cbor_value_get_led_color(&value, color));
    BO_TRY(led_set_color(color));

    return 0;
}

int bo_rpc_borneo_lyfi_schedule_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    const struct led_scheduler* sch = led_get_schedule();
    CborEncoder root_array;
    BO_TRY(cbor_encoder_create_array(retvals, &root_array, sch->item_count));
    for (size_t i = 0; i < sch->item_count; i++) {
        const struct led_scheduler_item* sch_item = &sch->items[i];
        BO_TRY(cbor_encode_led_sch_item(&root_array, sch_item));
    }
    BO_TRY(cbor_encoder_close_container(retvals, &root_array));

    return 0;
}

int bo_rpc_borneo_lyfi_schedule_put(const CborValue* args, CborEncoder* retvals)
{
    if (!cbor_value_is_container(args)) {
        return -EINVAL;
    }

    CborValue container = *args;

    struct led_scheduler scheduler;
    memset(&scheduler, 0, sizeof(scheduler));

    // [[hour, minute, []], ...]
    size_t item_count = 0;

    CborValue root_array;
    BO_TRY(cbor_value_enter_container(&container, &root_array));
    BO_TRY(cbor_value_get_array_length(&container, &item_count));
    scheduler.item_count = item_count;
    ESP_LOGI(TAG, "received schedule, item count: %u", item_count);
    for (size_t i = 0; i < item_count; i++) {
        CborValue item_array;
        BO_TRY(cbor_value_enter_container(&root_array, &item_array));
        struct led_scheduler_item* sch_item = &scheduler.items[i];

        int instant;
        BO_TRY(cbor_value_get_int(&item_array, &instant));
        sch_item->instant = (uint32_t)instant;
        BO_TRY(cbor_value_advance(&item_array));

        BO_TRY(cbor_value_get_led_color(&item_array, sch_item->color));
        BO_TRY(cbor_value_leave_container(&root_array, &item_array));
    }
    BO_TRY(cbor_value_leave_container(&container, &root_array));

    BO_TRY(led_set_schedule(scheduler.items, scheduler.item_count));

    return 0;
}

int bo_rpc_borneo_lyfi_info_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    CborEncoder root_map;
    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

    const struct led_factory_settings* factory = led_get_factory_settings();

    BO_TRY(cbor_encode_text_stringz(&root_map, "usage"));
    BO_TRY(cbor_encode_uint(&root_map, factory->usage));

    if (factory->nominal_pfd > 0) {
        BO_TRY(cbor_encode_text_stringz(&root_map, "nominalPfd"));
        BO_TRY(cbor_encode_uint(&root_map, factory->nominal_pfd));
    }

    if (factory->nominal_power > 0) {
        BO_TRY(cbor_encode_text_stringz(&root_map, "nominalPower"));
        BO_TRY(cbor_encode_uint(&root_map, factory->nominal_power));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "channelCountMax"));
        BO_TRY(cbor_encode_uint(&root_map, CONFIG_LYFI_LED_CHANNEL_COUNT));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "channelCount"));
        BO_TRY(cbor_encode_uint(&root_map, led_channel_count()));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "channels"));
        BO_TRY(_encode_channel_info_array(&root_map));
    }

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_lyfi_status_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    CborEncoder root_map;
    BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

    const struct led_user_settings* led_settings = led_get_settings();

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "state"));
        BO_TRY(cbor_encode_uint(&root_map, led_get_state()));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "mode"));
        BO_TRY(cbor_encode_uint(&root_map, led_settings->mode));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "unscheduled"));
        BO_TRY(cbor_encode_boolean(&root_map, led_get_state() == LED_STATE_TEMPORARY));
    }

#if CONFIG_LYFI_NTC_SUPPORT
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "temperature"));
        int32_t temp;
        const struct drvfx_device* temp_dev = k_device_get_binding("sensor.temp");
        int rc = sensor_get_value(temp_dev, &temp);
        if (rc != 0) {
            BO_TRY(cbor_encode_null(&root_map));
        }
        else {
            BO_TRY(cbor_encode_int(&root_map, temp));
        }
    }
#endif // CONFIG_LYFI_NTC_SUPPORT

#if CONFIG_LYFI_MEAS_CURRENT_SUPPORT
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "powerCurrent"));
        int32_t ma;
        const struct drvfx_device* sensor_dev = k_device_get_binding("sensor.led_current");
        int rc = sensor_get_value(sensor_dev, &ma);
        if (rc != 0) {
            BO_TRY(cbor_encode_null(&root_map));
        }
        else {
            BO_TRY(cbor_encode_int(&root_map, ma));
        }
    }
#endif // CONFIG_LYFI_MEAS_CURRENT_SUPPORT

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "tempRemain"));
        int32_t remaining = led_get_temporary_remaining();
        if (remaining < 0) {
            remaining = 0;
        }
        BO_TRY(cbor_encode_uint(&root_map, (uint32_t)remaining));
    }

#if CONFIG_LYFI_FAN_CTRL_SUPPORT
    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "fanPower"));
        const struct fan_status fs = fan_get_status();
        BO_TRY(cbor_encode_uint(&root_map, fs.power));
    }
#endif // CONFIG_LYFI_FAN_CTRL_SUPPORT

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "output"));
        led_duties_t duties;
        BO_TRY(led_get_duties(duties));
        BO_TRY(_encode_channels_output_array(&root_map, led_channel_count(), duties));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "currentColor"));
        led_color_t color;
        BO_TRY(led_get_color(color));
        BO_TRY(cbor_encode_color(&root_map, color));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "manualColor"));
        BO_TRY(cbor_encode_color(&root_map, led_get_settings()->manual_color));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "sunColor"));
        BO_TRY(cbor_encode_color(&root_map, led_get_settings()->sun_color));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "acclimationEnabled"));
        BO_TRY(cbor_encode_boolean(&root_map, led_acclimation_is_enabled()));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "acclimationActivated"));
        BO_TRY(cbor_encode_boolean(&root_map, led_acclimation_is_activated()));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "cloudEnabled"));
        BO_TRY(cbor_encode_boolean(&root_map, led_cloud_is_enabled()));
    }

    {
        BO_TRY(cbor_encode_text_stringz(&root_map, "cloudActivated"));
        BO_TRY(cbor_encode_boolean(&root_map, led_cloud_is_activated()));
    }

    BO_TRY(cbor_encoder_close_container(retvals, &root_map));

    return 0;
}

int bo_rpc_borneo_output_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    led_duties_t duties;
    BO_TRY(led_get_duties(duties));
    BO_TRY(_encode_channels_output_array(retvals, led_channel_count(), duties));
    return 0;
}

int bo_rpc_borneo_lyfi_temp_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
#if CONFIG_LYFI_NTC_SUPPORT
    int32_t temp;
    const struct drvfx_device* temp_dev = k_device_get_binding("sensor.temp");
    int rc = sensor_get_value(temp_dev, &temp);
    if (rc != 0) {
        BO_TRY(cbor_encode_int(retvals, temp));
    }
    else {
        BO_TRY(cbor_encode_null(retvals));
    }
#else
    BO_TRY(cbor_encode_null(retvals));
#endif // CONFIG_LYFI_NTC_SUPPORT

    return 0;
}

int bo_rpc_borneo_lyfi_state_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    BO_TRY(cbor_encode_uint(retvals, led_get_state()));

    return 0;
}

int bo_rpc_borneo_lyfi_state_put(const CborValue* args, CborEncoder* retvals)
{
    int state;
    BO_TRY(cbor_value_get_int_checked(args, &state));
    BO_TRY(led_switch_state((uint8_t)state));

    return 0;
}

int bo_rpc_borneo_lyfi_correction_method_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    const struct led_user_settings* settings = led_get_settings();
    BO_TRY(cbor_encode_uint(retvals, settings->correction_method));

    return 0;
}

int bo_rpc_borneo_lyfi_correction_method_put(const CborValue* args, CborEncoder* retvals)
{
    int correction_method;
    BO_TRY(cbor_value_get_int_checked(args, &correction_method));
    BO_TRY(led_set_correction_method((uint8_t)correction_method));

    return 0;
}

int bo_rpc_borneo_lyfi_mode_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    const struct led_user_settings* settings = led_get_settings();
    BO_TRY(cbor_encode_uint(retvals, settings->mode));

    return 0;
}

int bo_rpc_borneo_lyfi_mode_put(const CborValue* args, CborEncoder* retvals)
{
    uint64_t mode;
    BO_TRY(cbor_value_get_uint64(args, &mode));
    BO_TRY(led_switch_mode((uint8_t)mode));

    return 0;
}

int bo_rpc_borneo_lyfi_temporary_duration_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    const struct led_user_settings* settings = led_get_settings();
    BO_TRY(cbor_encode_uint(retvals, settings->temporary_duration));

    return 0;
}

int bo_rpc_borneo_lyfi_temporary_duration_put(const CborValue* args, CborEncoder* retvals)
{
    int duration;
    BO_TRY(cbor_value_get_int_checked(args, &duration));
    if (duration <= 0 || duration > INT32_MAX - 1) {
        return -1;
    }
    BO_TRY(led_set_temporary_duration((uint32_t)duration));

    return 0;
}

int bo_rpc_borneo_lyfi_geo_location_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;

    if (led_has_geo_location()) {
        CborEncoder root_map;
        BO_TRY(cbor_encoder_create_map(retvals, &root_map, CborIndefiniteLength));

        BO_TRY(cbor_encode_text_stringz(&root_map, "lat"));
        BO_TRY(cbor_encode_float(&root_map, _led.settings.location.lat));

        BO_TRY(cbor_encode_text_stringz(&root_map, "lng"));
        BO_TRY(cbor_encode_float(&root_map, _led.settings.location.lng));

        BO_TRY(cbor_encoder_close_container(retvals, &root_map));
    }
    else {
        BO_TRY(cbor_encode_null(retvals));
    }

    return 0;
}

int bo_rpc_borneo_lyfi_geo_location_put(const CborValue* args, CborEncoder* retvals)
{
    if (!cbor_value_is_map(args)) {
        return -1;
    }

    CborValue value;
    struct geo_location location;

    BO_TRY(cbor_value_map_find_value(args, "lat", &value));
    BO_TRY(cbor_value_get_float(&value, &location.lat));

    BO_TRY(cbor_value_map_find_value(args, "lng", &value));
    BO_TRY(cbor_value_get_float(&value, &location.lng));

    BO_TRY(led_set_geo_location(&location));

    return 0;
}

int bo_rpc_borneo_lyfi_tz_enabled_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    BO_TRY(cbor_encode_boolean(retvals, _led.settings.flags & LED_OPTION_TZ_ENABLED));
    return 0;
}

int bo_rpc_borneo_lyfi_tz_enabled_put(const CborValue* args, CborEncoder* retvals)
{
    bool enabled = false;
    BO_TRY(cbor_value_get_boolean(args, &enabled));
    BO_TRY(led_tz_enable(enabled));

    return 0;
}

int bo_rpc_borneo_lyfi_tz_offset_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    BO_TRY(cbor_encode_int(retvals, _led.settings.tz_offset));

    return 0;
}

int bo_rpc_borneo_lyfi_tz_offset_put(const CborValue* args, CborEncoder* retvals)
{
    int offset = 0;
    BO_TRY(cbor_value_get_int_checked(args, &offset));
    BO_TRY(led_tz_set_offset(offset));

    return 0;
}

int bo_rpc_borneo_lyfi_cloud_enabled_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args;
    BO_TRY(cbor_encode_boolean(retvals, led_cloud_is_enabled()));
    return 0;
}

int bo_rpc_borneo_lyfi_cloud_enabled_put(const CborValue* args, CborEncoder* retvals)
{
    bool enabled = false;
    BO_TRY(cbor_value_get_boolean(args, &enabled));
    BO_TRY(led_cloud_enable(enabled));
    BO_TRY(led_save_user_settings());

    return 0;
}