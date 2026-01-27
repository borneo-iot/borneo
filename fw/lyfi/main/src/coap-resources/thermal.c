#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include "coap3/coap.h"
#include <cbor.h>

#include <borneo/common.h>
#include <borneo/coap.h>
#include "../thermal.h"
#include "../protect.h"
#include "../rpc/rpc.h"

#define TAG "thermal-coap"

#if CONFIG_LYFI_THERMAL_ENABLED

static void _coap_hnd_thermal_current_temp_get(coap_resource_t* resource, coap_session_t* session,
                                               const coap_pdu_t* request, const coap_string_t* query,
                                               coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;

    uint8_t buf[32];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_current_temp_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_resource_notify_observers(resource, NULL);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void _coap_hnd_thermal_keep_temp_get(coap_resource_t* resource, coap_session_t* session,
                                            const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[32];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_keep_temp_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void _coap_hnd_thermal_settings_get(coap_resource_t* resource, coap_session_t* session,
                                           const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_settings_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void _coap_hnd_fan_mode_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;

    uint8_t buf[64];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_fan_mode_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void _coap_hnd_fan_mode_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue it;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &it), response);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_fan_mode_put(&it, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void _coap_hnd_manual_fan_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                     const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;

    uint8_t buf[32];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_manual_fan_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void _coap_hnd_manual_fan_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                     const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue it;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &it), response);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_thermal_manual_fan_put(&it, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

COAP_RESOURCE_DEFINE("borneo/lyfi/thermal/temp/current", true, _coap_hnd_thermal_current_temp_get, NULL, NULL, NULL,
                     AUTH_PERM_PUBLIC);
COAP_RESOURCE_DEFINE("borneo/lyfi/thermal/temp/keep", false, _coap_hnd_thermal_keep_temp_get, NULL, NULL, NULL,
                     AUTH_PERM_PUBLIC);
COAP_RESOURCE_DEFINE("borneo/lyfi/thermal/settings", false, _coap_hnd_thermal_settings_get, NULL, NULL, NULL,
                     AUTH_PERM_PUBLIC);
COAP_RESOURCE_DEFINE("borneo/lyfi/thermal/fan/mode", false, _coap_hnd_fan_mode_get, NULL, _coap_hnd_fan_mode_put, NULL,
                     AUTH_PERM_PUBLIC);
COAP_RESOURCE_DEFINE("borneo/lyfi/thermal/fan/manual", false, _coap_hnd_manual_fan_get, NULL, _coap_hnd_manual_fan_put,
                     NULL, AUTH_PERM_PUBLIC);

#endif // CONFIG_LYFI_THERMAL_ENABLED