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
#include "../rpc/rpc.h"

#define TAG "lyfi-coap"

static void coap_hnd_acclimation_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                     const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[128];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_acclimation_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_acclimation_post(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue iter;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &iter), response);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_acclimation_post(&iter, NULL), response);

    coap_pdu_set_code(response, BO_COAP_CODE_201_CREATED);
}

static void coap_hnd_acclimation_delete(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                        const coap_string_t* query, coap_pdu_t* response)
{
    BO_COAP_TRY(bo_rpc_borneo_lyfi_acclimation_delete(NULL, NULL), response);

    coap_pdu_set_code(response, COAP_RESPONSE_CODE_DELETED);
}

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/acclimation", false, coap_hnd_acclimation_get, coap_hnd_acclimation_post, NULL,
                     coap_hnd_acclimation_delete);