#include <stdint.h>
#include <stdbool.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <sys/socket.h>

#include "coap3/coap.h"
#include <cbor.h>

#include <borneo/common.h>
#include <borneo/coap.h>

#include "../fan.h"
#include "../rpc/rpc.h"

#define TAG "lyfi-coap"

static void _coap_hnd_fan_power_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                    const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;
    uint8_t buf[128];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_fan_power_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void _coap_hnd_fan_power_put(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                    const coap_string_t* query, coap_pdu_t* response)
{
    coap_resource_notify_observers(resource, NULL);

    size_t data_size;
    const uint8_t* data;
    coap_get_data(request, &data_size, &data);

    CborParser parser;
    CborValue it;
    BO_COAP_TRY(cbor_parser_init(data, data_size, 0, &parser, &it), response);

    int rc = bo_rpc_borneo_lyfi_fan_power_put(&it, NULL);
    if (rc == -1) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }
    BO_COAP_TRY(rc, response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
    return;
}

COAP_RESOURCE_DEFINE("borneo/lyfi/fan/power", false, _coap_hnd_fan_power_get, NULL, _coap_hnd_fan_power_put, NULL,
                     AUTH_PERM_PUBLIC);