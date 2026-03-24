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
#include "../solar.h"
#include "../rpc/rpc.h"

#define TAG "lyfi-coap"

static void coap_hnd_sun_schedule_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                      const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[1024];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    BO_COAP_TRY(bo_rpc_borneo_lyfi_sun_schedule_get(NULL, &encoder), response);

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

static void coap_hnd_sun_curve_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                   const coap_string_t* query, coap_pdu_t* response)
{
    size_t encoded_size = 0;
    uint8_t buf[512];

    CborEncoder encoder;
    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);

    int rc = bo_rpc_borneo_lyfi_sun_curve_get(NULL, &encoder);
    if (rc == -1) {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_BAD_REQUEST);
        return;
    }
    else if (rc == -2) {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_INTERNAL_ERROR);
        return;
    }
    else if (rc != 0) {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_INTERNAL_ERROR);
        return;
    }

    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
}

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/sun/schedule", false, coap_hnd_sun_schedule_get, NULL, NULL, NULL);

COAP_RESOURCE_DEFINE("borneo/lyfi/v1/sun/curve", false, coap_hnd_sun_curve_get, NULL, NULL, NULL);