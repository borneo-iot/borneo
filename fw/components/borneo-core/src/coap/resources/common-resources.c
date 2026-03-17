#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_app_desc.h>
#include <esp_mac.h>
#include <esp_timer.h>
#include <nvs_flash.h>
#include <sys/socket.h>

#include <coap3/coap.h>
#include <cbor.h>

#include <borneo/common.h>
#include <borneo/system.h>

#include <borneo/rtc.h>
#include <borneo/coap.h>
#include <borneo/wifi.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/timer.h>
#include <borneo/product.h>
#include <borneo/rpc/common.h>

#define TAG "borneo-core-coap"

static void coap_hnd_borneo_info_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                     const coap_string_t* query, coap_pdu_t* response)
{
    uint8_t buf[1024];
    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_info_get(NULL, &encoder), response);

    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_borneo_reboot_post(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                        const coap_string_t* query, coap_pdu_t* response)
{
    BO_COAP_TRY(bo_rpc_borneo_reboot_post(NULL, NULL), response);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
}

static void coap_hnd_borneo_status_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_status_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_borneo_fw_ver_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_fw_ver_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_borneo_compatible_get(coap_resource_t* resource, coap_session_t* session,
                                           const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_compatible_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_heartbeat_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_heartbeat_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_borneo_system_mode_get(coap_resource_t* resource, coap_session_t* session,
                                            const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[256] = { 0 };
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_system_mode_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);

    return;
}

static void coap_hnd_borneo_settings_timezone_get(coap_resource_t* resource, coap_session_t* session,
                                                  const coap_pdu_t* request, const coap_string_t* query,
                                                  coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[256] = { 0 };
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_settings_timezone_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);

    return;
}

static void coap_hnd_borneo_settings_timezone_put(coap_resource_t* resource, coap_session_t* session,
                                                  const coap_pdu_t* request, const coap_string_t* query,
                                                  coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_settings_timezone_put(&value, NULL), response);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
    return;
}

static void coap_hnd_borneo_settings_name_get(coap_resource_t* resource, coap_session_t* session,
                                              const coap_pdu_t* request, const coap_string_t* query,
                                              coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[256] = { 0 };
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_settings_name_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);

    return;
}

static void coap_hnd_borneo_settings_name_put(coap_resource_t* resource, coap_session_t* session,
                                              const coap_pdu_t* request, const coap_string_t* query,
                                              coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_settings_name_put(&value, NULL), response);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
    return;
}

static void coap_hnd_rtc_local_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);

    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_rtc_local_get(&value, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_rtc_local_post(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                    const coap_string_t* query, coap_pdu_t* response)
{
    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);

    BO_COAP_TRY(bo_rpc_rtc_local_post(&value, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_201_CREATED);
}

static void coap_hnd_rtc_timestamp_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                       const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[64] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_rtc_timestamp_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_sensors_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                 const coap_string_t* query, coap_pdu_t* response)
{
    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);

    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[512] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_sensors_get(&value, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_borneo_network_reset_post(coap_resource_t* resource, coap_session_t* session,
                                               const coap_pdu_t* request, const coap_string_t* query,
                                               coap_pdu_t* response)
{
    BO_COAP_TRY(bo_rpc_borneo_network_reset_post(NULL, NULL), response);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
}

COAP_RESOURCE_DEFINE("borneo/info", false, coap_hnd_borneo_info_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/reboot", false, NULL, coap_hnd_borneo_reboot_post, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/status", false, coap_hnd_borneo_status_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/fwver", false, coap_hnd_borneo_fw_ver_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/compatible", false, coap_hnd_borneo_compatible_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/heartbeat", true, coap_hnd_heartbeat_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/mode", true, coap_hnd_borneo_system_mode_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/settings/timezone", false, coap_hnd_borneo_settings_timezone_get, NULL,
                     coap_hnd_borneo_settings_timezone_put, NULL);

COAP_RESOURCE_DEFINE("borneo/settings/name", false, coap_hnd_borneo_settings_name_get, NULL,
                     coap_hnd_borneo_settings_name_put, NULL);

COAP_RESOURCE_DEFINE("borneo/rtc/local", false, coap_hnd_rtc_local_get, coap_hnd_rtc_local_post, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/rtc/ts", true, coap_hnd_rtc_timestamp_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/sensors", false, coap_hnd_sensors_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/network/reset", false, NULL, coap_hnd_borneo_network_reset_post, NULL, NULL);