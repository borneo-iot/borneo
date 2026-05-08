#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include "coap3/coap.h"
#include <cbor.h>

#include <borneo/system.h>
#include <borneo/coap.h>
#include <borneo/rtc.h>

#include "../led/led.h"
#include "../fan.h"
#include "../coap-paths.h"
#include "../rpc/cbor-common.h"
#include "../rpc/rpc.h"

#define TAG "lyfi-coap"

static void coap_hnd_color_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                               const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_color_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_color_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                               const coap_string_t* query, coap_pdu_t* response)
{
    size_t data_size;
    const uint8_t* data;

    coap_resource_notify_observers(resource, NULL);

    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_color_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_schedule_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                  const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_schedule_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_schedule_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                  const coap_string_t* query, coap_pdu_t* response)
{
    size_t data_size;
    const uint8_t* data;

    coap_resource_notify_observers(resource, NULL);

    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue it;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &it), response);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_schedule_put(&it, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_info_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                              const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_info_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_status_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_status_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_output_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_output_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_temp_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                              const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_temp_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_state_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                               const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;

    uint8_t buf[128];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_state_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_state_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                               const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_state_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_correction_method_get(coap_resource_t* resource, coap_session_t* session,
                                           const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_correction_method_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_correction_method_put(coap_resource_t* resource, coap_session_t* session,
                                           const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_correction_method_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_mode_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                              const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_mode_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_mode_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                              const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_mode_put(&value, NULL), response);
    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_temporary_duration_get(coap_resource_t* resource, coap_session_t* session,
                                            const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[32];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_temporary_duration_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_temporary_duration_put(coap_resource_t* resource, coap_session_t* session,
                                            const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_temporary_duration_put(&value, NULL), response);
    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_geo_location_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[128];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_geo_location_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_geo_location_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue iter;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &iter), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_geo_location_put(&iter, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_tz_enabled_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                    const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[16];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_tz_enabled_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_tz_enabled_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                    const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_tz_enabled_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_tz_offset_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[16];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_tz_offset_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_tz_offset_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_tz_offset_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_cloud_enabled_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[16];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_cloud_enabled_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_cloud_enabled_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_cloud_enabled_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void coap_hnd_output_invert_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[16];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_output_invert_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void coap_hnd_output_invert_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_output_invert_put(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/color", false, coap_hnd_color_get, NULL, coap_hnd_color_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/schedule", false, coap_hnd_schedule_get, NULL, coap_hnd_schedule_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/info", false, coap_hnd_info_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/status", false, coap_hnd_status_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/output", true, coap_hnd_output_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/temperature", true, coap_hnd_temp_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE(LYFI_COAP_PATH_LED_STATE, true, coap_hnd_state_get, NULL, coap_hnd_state_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/correction-method", false, coap_hnd_correction_method_get, NULL,
                     coap_hnd_correction_method_put, NULL);

COAP_RESOURCE_DEFINE(LYFI_COAP_PATH_LED_MODE, true, coap_hnd_mode_get, NULL, coap_hnd_mode_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/temporary-duration", false, coap_hnd_temporary_duration_get, NULL,
                     coap_hnd_temporary_duration_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/geo-location", false, coap_hnd_geo_location_get, NULL, coap_hnd_geo_location_put,
                     NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/tz/enabled", false, coap_hnd_tz_enabled_get, NULL, coap_hnd_tz_enabled_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/tz/offset", false, coap_hnd_tz_offset_get, NULL, coap_hnd_tz_offset_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/cloud/enabled", false, coap_hnd_cloud_enabled_get, NULL,
                     coap_hnd_cloud_enabled_put, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/output/invert", false, coap_hnd_output_invert_get, NULL,
                     coap_hnd_output_invert_put, NULL);