#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "common.h"

#define BO_COAP_HEARTBEAT_INTERVAL_MS (5000)

struct coap_resource_desc {
    coap_str_const_t path;
    coap_method_handler_t get_handler;
    coap_method_handler_t post_handler;
    coap_method_handler_t put_handler;
    coap_method_handler_t delete_handler;
    bool is_observable;
};

#define __COAP_MAKE_UNIQUE_TOKEN(x, y) _CONCAT(x, y)

#define COAP_RESOURCE_DEFINE(res_path, res_is_observable, res_get, res_post, res_put, res_delete)                      \
    static const struct coap_resource_desc                                                                             \
        __attribute__((section(".coap_resource_desc"), used)) __COAP_MAKE_UNIQUE_TOKEN(__coap_resource_desc_,          \
                                                                                       __LINE__)                       \
        = {                                                                                                            \
              .path = {                                                                                                  \
                  .s = (const uint8_t *)res_path,                                                                                       \
                  .length = sizeof(res_path) - 1,                                                                      \
              },                                                                                                       \
              .is_observable = (res_is_observable),                                                                    \
              .get_handler = (res_get),                                                                                \
              .post_handler = (res_post),                                                                              \
              .put_handler = (res_put),                                                                                \
              .delete_handler = (res_delete),                                                                          \
          };

#define BO_COAP_TRY(expression, response)                                                                              \
    ({                                                                                                                 \
        int _rc = (expression);                                                                                        \
        if (_rc == -EINVAL) {                                                                                          \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(400));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
        else if (_rc == -ENOTSUP) {                                                                                    \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(501));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
        else if (_rc == -ENOMEM) {                                                                                     \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(500));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
        else if (_rc != 0) {                                                                                           \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(500));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
    })

#define BO_COAP_TRY_DECODE(expression, response)                                                                       \
    ({                                                                                                                 \
        int _rc = (expression);                                                                                        \
        if (_rc) {                                                                                                     \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(400));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
    })

#define BO_COAP_TRY_ENCODE(expression, response)                                                                       \
    ({                                                                                                                 \
        CborError _rc = (expression);                                                                                  \
        if (_rc != CborNoError) {                                                                                      \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(501));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
    })

#define BO_COAP_REQUIRES(expression, response)                                                                         \
    ({                                                                                                                 \
        typeof(expression) _rr = (expression);                                                                         \
        if (!_rr) {                                                                                                    \
            coap_pdu_set_code(response, COAP_RESPONSE_CODE(400));                                                      \
            return;                                                                                                    \
        }                                                                                                              \
    })

#define BO_COAP_CODE_201_CREATED COAP_RESPONSE_CODE(201)
#define BO_COAP_CODE_202_DELETED COAP_RESPONSE_CODE(202)
#define BO_COAP_CODE_203_VALID COAP_RESPONSE_CODE(203)
#define BO_COAP_CODE_204_CHANGED COAP_RESPONSE_CODE(204)
#define BO_COAP_CODE_205_CONTENT COAP_RESPONSE_CODE(205)
#define BO_COAP_CODE_231_CONTINUE COAP_RESPONSE_CODE(231)
#define BO_COAP_CODE_400_BAD_REQUEST COAP_RESPONSE_CODE(400)
#define BO_COAP_CODE_401_UNAUTHORIZED COAP_RESPONSE_CODE(401)
#define BO_COAP_CODE_405_METHOD_NOT_ALLOWED COAP_RESPONSE_CODE(405)
#define BO_COAP_CODE_406_NOT_ACCEPTABLE COAP_RESPONSE_CODE(406)
#define BO_COAP_CODE_500_INTERNAL_SERVER_ERROR COAP_RESPONSE_CODE(500)
#define BO_COAP_CODE_501_NOT_IMPLEMENTED COAP_RESPONSE_CODE(501)

// Known resource paths

#define BO_COAP_PATH_HEARTBEAT "borneo/heartbeat"
#define BO_COAP_PATH_POWER "borneo/power"

int bo_coap_notify_resource_changed(const coap_str_const_t* resource_uri);

#ifdef __cplusplus
}
#endif