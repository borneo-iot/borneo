#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include <cbor.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/rtc.h>
#include <borneo/rpc/common.h>

#define TAG "borneo-rpc-rtc"

int bo_rpc_rtc_local_get(const CborValue* args, CborEncoder* retvals)
{
    int64_t t1 = 0LL;
    BO_TRY(cbor_value_get_int64_checked(args, &t1));

    if (t1 <= 0LL) {
        return -1; // Bad request
    }

    int64_t t2 = bo_rtc_get_timestamp_us();
    int64_t t3 = bo_rtc_get_timestamp_us();

    CborEncoder map_encoder;
    BO_TRY(cbor_encoder_create_map(retvals, &map_encoder, CborIndefiniteLength));
    BO_TRY(cbor_encode_text_stringz(&map_encoder, "t1"));
    BO_TRY(cbor_encode_int(&map_encoder, t1));
    BO_TRY(cbor_encode_text_stringz(&map_encoder, "t2"));
    BO_TRY(cbor_encode_int(&map_encoder, t2));
    BO_TRY(cbor_encode_text_stringz(&map_encoder, "t3"));
    BO_TRY(cbor_encode_int(&map_encoder, t3));
    BO_TRY(cbor_encoder_close_container(retvals, &map_encoder));

    return 0;
}

int bo_rpc_rtc_local_post(const CborValue* args, CborEncoder* retvals)
{
    (void)retvals; // No output for POST
    int64_t time_skew_us;
    int rc = 0;
    BO_TRY(cbor_value_get_int64_checked(args, &time_skew_us));

    if (time_skew_us > -1000LL && time_skew_us < 1000LL) {
        return -1; // Bad request
    }
    int64_t timestamp_us = bo_rtc_get_timestamp_us();
    timestamp_us += time_skew_us;
    BO_TRY(bo_rtc_set_time(timestamp_us));
    rc = bo_rtc_ext_update();
    if (rc != 0) {
        // Manual/local time sync should remain usable even if persisting time to the external RTC fails.
        // TODO: Route this to a user-visible fault/alarm channel once RTC health reporting exists.
        ESP_LOGW(TAG, "Local RTC sync updated system time, but external RTC update failed: %d", rc);
    }

    return 0;
}

int bo_rpc_rtc_timestamp_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    uint32_t timestamp = 0;
    BO_TRY(bo_rtc_get_timestamp(&timestamp));
    BO_TRY(cbor_encode_uint(retvals, timestamp));
    return 0;
}