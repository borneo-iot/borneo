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

#define TAG "protect"

#if CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT

static void _coap_hnd_overheated_temp_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                          const coap_string_t* query, coap_pdu_t* response)
{
    CborEncoder encoder;
    size_t encoded_size = 0;

    uint8_t buf[32];

    cbor_encoder_init(&encoder, buf, sizeof(buf), 0);
    BO_COAP_TRY(bo_rpc_borneo_lyfi_protection_overheated_temp_get(NULL, &encoder), response);
    encoded_size = cbor_encoder_get_buffer_size(&encoder, buf);

    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

COAP_RESOURCE_DEFINE("borneo/lyfi/protection/overheated-temp", false, _coap_hnd_overheated_temp_get, NULL, NULL, NULL,
                     AUTH_PERM_PUBLIC);

#endif // CONFIG_LYFI_PROTECTION_OVERHEATED_SUPPORT