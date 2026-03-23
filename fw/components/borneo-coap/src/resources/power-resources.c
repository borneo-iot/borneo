#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_app_desc.h>
#include <esp_mac.h>
#include <nvs_flash.h>
#include <sys/socket.h>

#include "coap3/coap.h"
#include <cbor.h>

#include <borneo/common.h>
#include <borneo/rtc.h>
#include <borneo/coap.h>
#include <borneo/wifi.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/rpc/common.h>

#define TAG "borneo-power-coap"

static void coap_hnd_borneo_power_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_power_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_borneo_power_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue value;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &value), response);
    BO_COAP_TRY(bo_rpc_borneo_power_put(&value, NULL), response);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
}

static void coap_hnd_borneo_power_behavior_get(coap_resource_t* resource, coap_session_t* session,
                                               const coap_pdu_t* request, const coap_string_t* query,
                                               coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[32] = { 0 };

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_power_behavior_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    return;
}

static void coap_hnd_borneo_power_behavior_put(coap_resource_t* resource, coap_session_t* session,
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
    BO_COAP_TRY(bo_rpc_borneo_power_behavior_put(&value, NULL), response);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
}

COAP_RESOURCE_DEFINE(BO_COAP_PATH_POWER, true, coap_hnd_borneo_power_get, NULL, coap_hnd_borneo_power_put, NULL);
COAP_RESOURCE_DEFINE("borneo/power/behavior", false, coap_hnd_borneo_power_behavior_get, NULL,
                     coap_hnd_borneo_power_behavior_put, NULL);
