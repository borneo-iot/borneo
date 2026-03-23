#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include <cbor.h>
#include <coap3/coap.h>

#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/rpc/common.h>

#define TAG "borneo-rpc-power"

int bo_rpc_borneo_power_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    BO_TRY(cbor_encode_boolean(retvals, bo_power_is_on()));
    return 0;
}

int bo_rpc_borneo_power_put(const CborValue* args, CborEncoder* retvals)
{
    (void)retvals; // No output for PUT
    bool power_value;
    BO_TRY(cbor_value_get_boolean(args, &power_value));

    if (power_value == bo_power_is_on()) {
        return -1; // Bad request
    }

    if (power_value) {
        BO_TRY(bo_power_on());
    }
    else {
        BO_TRY(bo_power_shutdown(0));
    }

    return 0;
}

int bo_rpc_borneo_power_behavior_get(const CborValue* args, CborEncoder* retvals)
{
    (void)args; // No input args for GET
    BO_TRY(cbor_encode_uint(retvals, bo_power_get_behavior()));
    return 0;
}

int bo_rpc_borneo_power_behavior_put(const CborValue* args, CborEncoder* retvals)
{
    (void)retvals; // No output for PUT
    int behavior_value;
    BO_TRY(cbor_value_get_int_checked(args, &behavior_value));

    if (behavior_value < 0 || behavior_value >= POWER_INVALID_BEHAVIOR) {
        return -1; // Bad request
    }
    BO_TRY(bo_power_set_behavior((uint8_t)behavior_value));
    return 0;
}