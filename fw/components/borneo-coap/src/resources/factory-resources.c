#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_mac.h>
#include <nvs_flash.h>
#include <sys/socket.h>

#include "coap3/coap.h"
#include <cbor.h>

#include <ctype.h>
#include <limits.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include <borneo/rtc.h>
#include <borneo/common.h>
#include <borneo/coap.h>
#include <borneo/wifi.h>
#include <borneo/system.h>
#include <borneo/power.h>
#include <borneo/nvs.h>
#include <borneo/rpc/common.h>

#define TAG "borneo-core-coap"

#define FACTORY_NVS_STRING_MAX_SIZE 512

static void coap_hnd_borneo_factory_reset_post(coap_resource_t* resource, coap_session_t* session,
                                               const coap_pdu_t* request, const coap_string_t* query,
                                               coap_pdu_t* response)
{
    BO_COAP_TRY(bo_rpc_borneo_factory_reset_post(NULL, NULL), response);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE(204));
}

#if CONFIG_BORNEO_PRODUCT_MODE_STANDALONE

typedef enum {
    FACTORY_NVS_KIND_U8,
    FACTORY_NVS_KIND_U16,
    FACTORY_NVS_KIND_U32,
    FACTORY_NVS_KIND_U64,
    FACTORY_NVS_KIND_I8,
    FACTORY_NVS_KIND_I32,
    FACTORY_NVS_KIND_I64,
    FACTORY_NVS_KIND_BLOB,
    FACTORY_NVS_KIND_STRING,
} factory_nvs_kind_t;

static int factory_nvs_prepare(const coap_pdu_t* request, CborParser* parser, CborValue* map, char* ns, size_t ns_len,
                               char* key, size_t key_len)
{
    size_t data_size = 0;
    const uint8_t* data = NULL;
    coap_get_data(request, &data_size, &data);

    BO_TRY(cbor_parser_init(data, data_size, 0, parser, map));
    if (!cbor_value_is_map(map)) {
        return -EINVAL;
    }

    CborValue value;

    size_t len = ns_len;
    BO_TRY(cbor_value_map_find_value(map, "ns", &value));
    if (!cbor_value_is_text_string(&value)) {
        return -EINVAL;
    }
    BO_TRY(cbor_value_copy_text_string(&value, ns, &len, NULL));

    len = key_len;
    BO_TRY(cbor_value_map_find_value(map, "k", &value));
    if (!cbor_value_is_text_string(&value)) {
        return -EINVAL;
    }
    BO_TRY(cbor_value_copy_text_string(&value, key, &len, NULL));

    return 0;
}

static int factory_nvs_hex(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'A' && c <= 'F') {
        return 10 + (c - 'A');
    }
    if (c >= 'a' && c <= 'f') {
        return 10 + (c - 'a');
    }
    return -1;
}

static int factory_nvs_query_copy_value(const char* src, char* dst, size_t dst_len)
{
    size_t out = 0;
    while (*src != '\0') {
        char ch = *src++;
        if (ch == '+') {
            ch = ' ';
        }
        else if (ch == '%') {
            if (src[0] == '\0' || src[1] == '\0') {
                return -EINVAL;
            }
            int hi = factory_nvs_hex(src[0]);
            int lo = factory_nvs_hex(src[1]);
            if (hi < 0 || lo < 0) {
                return -EINVAL;
            }
            ch = (char)((hi << 4) | lo);
            src += 2;
        }

        if (out + 1 >= dst_len) {
            return -EINVAL;
        }
        dst[out++] = ch;
    }

    dst[out] = '\0';
    return 0;
}

static bool factory_nvs_parse_query(const coap_pdu_t* request, const coap_string_t* query, char* ns, size_t ns_len,
                                    char* key, size_t key_len)
{
    const coap_string_t* opt_query = query;
    if (opt_query == NULL || opt_query->length == 0) {
        opt_query = coap_get_query(request);
    }

    if (opt_query == NULL || opt_query->length == 0) {
        return -EINVAL;
    }

    if (opt_query->length >= 128) {
        return -EINVAL;
    }

    char buf[128] = { 0 };
    memcpy(buf, opt_query->s, opt_query->length);

    bool has_ns = false;
    bool has_key = false;

    char* token = buf;
    while (token != NULL && *token != '\0') {
        char* next = token;
        while (*next != '\0' && *next != '&' && *next != ';') {
            next++;
        }
        if (*next != '\0') {
            *next = '\0';
            next++;
        }
        else {
            next = NULL;
        }

        if (*token != '\0') {
            char* equal = strchr(token, '=');
            if (equal != NULL) {
                *equal = '\0';
                const char* value = equal + 1;
                if (strcmp(token, "ns") == 0) {
                    BO_TRY(factory_nvs_query_copy_value(value, ns, ns_len));
                    has_ns = true;
                }
                else if (strcmp(token, "k") == 0) {
                    BO_TRY(factory_nvs_query_copy_value(value, key, key_len));
                    has_key = true;
                }
            }
        }

        token = next;
    }

    if (!has_ns || !has_key) {
        return -EINVAL;
    }

    return 0;
}

static bool factory_nvs_kind_is_signed(factory_nvs_kind_t kind)
{
    switch (kind) {
    case FACTORY_NVS_KIND_I8:
    case FACTORY_NVS_KIND_I32:
    case FACTORY_NVS_KIND_I64:
        return true;
    default:
        return false;
    }
}

static uint64_t factory_nvs_unsigned_max(factory_nvs_kind_t kind)
{
    switch (kind) {
    case FACTORY_NVS_KIND_U8:
        return UINT8_MAX;
    case FACTORY_NVS_KIND_U16:
        return UINT16_MAX;
    case FACTORY_NVS_KIND_U32:
        return UINT32_MAX;
    case FACTORY_NVS_KIND_U64:
        return UINT64_MAX;
    default:
        return 0;
    }
}

static int64_t factory_nvs_signed_min(factory_nvs_kind_t kind)
{
    switch (kind) {
    case FACTORY_NVS_KIND_I8:
        return INT8_MIN;
    case FACTORY_NVS_KIND_I32:
        return INT32_MIN;
    case FACTORY_NVS_KIND_I64:
        return INT64_MIN;
    default:
        return 0;
    }
}

static int64_t factory_nvs_signed_max(factory_nvs_kind_t kind)
{
    switch (kind) {
    case FACTORY_NVS_KIND_I8:
        return INT8_MAX;
    case FACTORY_NVS_KIND_I32:
        return INT32_MAX;
    case FACTORY_NVS_KIND_I64:
        return INT64_MAX;
    default:
        return 0;
    }
}

static void factory_nvs_handle_numeric_get(const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response,
                                           factory_nvs_kind_t kind)
{
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_parse_query(request, query, ns, sizeof(ns), key, sizeof(key)), response);

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);

    uint64_t uvalue = 0;
    int64_t svalue = 0;
    bool is_signed = factory_nvs_kind_is_signed(kind);

    switch (kind) {
    case FACTORY_NVS_KIND_U8: {
        uint8_t tmp;
        BO_COAP_TRY(nvs_get_u8(nvs, key, &tmp), response);
        uvalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_U16: {
        uint16_t tmp;
        BO_COAP_TRY(nvs_get_u16(nvs, key, &tmp), response);
        uvalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_U32: {
        uint32_t tmp;
        BO_COAP_TRY(nvs_get_u32(nvs, key, &tmp), response);
        uvalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_U64: {
        uint64_t tmp;
        BO_COAP_TRY(nvs_get_u64(nvs, key, &tmp), response);
        uvalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_I8: {
        int8_t tmp;
        BO_COAP_TRY(nvs_get_i8(nvs, key, &tmp), response);
        svalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_I32: {
        int32_t tmp;
        BO_COAP_TRY(nvs_get_i32(nvs, key, &tmp), response);
        svalue = tmp;
        break;
    }
    case FACTORY_NVS_KIND_I64: {
        int64_t tmp;
        BO_COAP_TRY(nvs_get_i64(nvs, key, &tmp), response);
        svalue = tmp;
        break;
    }
    default:
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    uint8_t encode_buf[32] = { 0 };
    CborEncoder encoder;
    cbor_encoder_init(&encoder, encode_buf, sizeof(encode_buf), 0);
    CborError err = is_signed ? cbor_encode_int(&encoder, svalue) : cbor_encode_uint(&encoder, uvalue);
    if (err != CborNoError) {
        coap_pdu_set_code(response, BO_COAP_CODE_500_INTERNAL_SERVER_ERROR);
        return;
    }

    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, encode_buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, encode_buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void factory_nvs_handle_numeric_set(const coap_pdu_t* request, coap_pdu_t* response, factory_nvs_kind_t kind)
{
    CborParser parser;
    CborValue map;
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_prepare(request, &parser, &map, ns, sizeof(ns), key, sizeof(key)), response);

    CborValue value_item;
    BO_COAP_TRY(cbor_value_map_find_value(&map, "v", &value_item), response);
    BO_COAP_REQUIRES(!cbor_value_is_undefined(&value_item), response);

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);

    if (factory_nvs_kind_is_signed(kind)) {
        int64_t value = 0;
        if (cbor_value_get_int64(&value_item, &value) != CborNoError || value < factory_nvs_signed_min(kind)
            || value > factory_nvs_signed_max(kind)) {
            coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
            return;
        }

        switch (kind) {
        case FACTORY_NVS_KIND_I8:
            BO_COAP_TRY(nvs_set_i8(nvs, key, (int8_t)value), response);
            break;
        case FACTORY_NVS_KIND_I32:
            BO_COAP_TRY(nvs_set_i32(nvs, key, (int32_t)value), response);
            break;
        case FACTORY_NVS_KIND_I64:
            BO_COAP_TRY(nvs_set_i64(nvs, key, value), response);
            break;
        default:
            coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
            return;
        }
    }
    else {
        uint64_t value = 0;
        if (cbor_value_get_uint64(&value_item, &value) != CborNoError || value > factory_nvs_unsigned_max(kind)) {
            coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
            return;
        }

        switch (kind) {
        case FACTORY_NVS_KIND_U8:
            BO_COAP_TRY(nvs_set_u8(nvs, key, (uint8_t)value), response);
            break;
        case FACTORY_NVS_KIND_U16:
            BO_COAP_TRY(nvs_set_u16(nvs, key, (uint16_t)value), response);
            break;
        case FACTORY_NVS_KIND_U32:
            BO_COAP_TRY(nvs_set_u32(nvs, key, (uint32_t)value), response);
            break;
        case FACTORY_NVS_KIND_U64:
            BO_COAP_TRY(nvs_set_u64(nvs, key, value), response);
            break;
        default:
            coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
            return;
        }
    }

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void factory_nvs_handle_blob_get(const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_parse_query(request, query, ns, sizeof(ns), key, sizeof(key)), response);

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);

    size_t blob_len = 0;
    BO_COAP_TRY(nvs_get_blob(nvs, key, NULL, &blob_len), response);

    if (blob_len > 512) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    uint8_t blob[512] = { 0 };
    if (blob_len > 0) {
        BO_COAP_TRY(nvs_get_blob(nvs, key, blob, &blob_len), response);
    }

    uint8_t encode_buf[512 + 16] = { 0 };
    CborEncoder encoder;
    cbor_encoder_init(&encoder, encode_buf, sizeof(encode_buf), 0);
    BO_COAP_TRY_ENCODE(cbor_encode_byte_string(&encoder, blob, blob_len), response);

    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, encode_buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, encode_buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void factory_nvs_handle_blob_set(const coap_pdu_t* request, coap_pdu_t* response)
{
    CborParser parser;
    CborValue map;
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_prepare(request, &parser, &map, ns, sizeof(ns), key, sizeof(key)), response);

    CborValue value_item;
    CborError err = cbor_value_map_find_value(&map, "v", &value_item);
    if (err != CborNoError || !cbor_value_is_byte_string(&value_item)) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    size_t expected_len = 0;
    if (cbor_value_calculate_string_length(&value_item, &expected_len) != CborNoError || expected_len > 512) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    uint8_t blob[512] = { 0 };
    size_t blob_len = sizeof(blob);
    if (cbor_value_copy_byte_string(&value_item, blob, &blob_len, NULL) != CborNoError) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);
    BO_COAP_TRY(nvs_set_blob(nvs, key, blob, blob_len), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

static void factory_nvs_handle_string_get(const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_parse_query(request, query, ns, sizeof(ns), key, sizeof(key)), response);

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);

    size_t str_len = 0;
    BO_COAP_TRY(nvs_get_str(nvs, key, NULL, &str_len), response);

    BO_COAP_REQUIRES(str_len <= FACTORY_NVS_STRING_MAX_SIZE, response);

    char str[FACTORY_NVS_STRING_MAX_SIZE] = { 0 };
    if (str_len > 0) {
        BO_COAP_TRY_DECODE(nvs_get_str(nvs, key, str, &str_len), response);
    }

    size_t payload_len = str_len > 0 ? str_len - 1 : 0;
    uint8_t encode_buf[512 + 16] = { 0 };
    CborEncoder encoder;
    cbor_encoder_init(&encoder, encode_buf, sizeof(encode_buf), 0);
    BO_COAP_TRY_ENCODE(cbor_encode_text_string(&encoder, str, payload_len), response);

    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, encode_buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, encode_buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

static void factory_nvs_handle_string_set(const coap_pdu_t* request, coap_pdu_t* response)
{
    CborParser parser;
    CborValue map;
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_prepare(request, &parser, &map, ns, sizeof(ns), key, sizeof(key)), response);

    CborValue value_item;
    BO_COAP_TRY(cbor_value_map_find_value(&map, "v", &value_item), response);
    BO_COAP_REQUIRES(cbor_value_is_text_string(&value_item), response);

    size_t expected_len = 0;
    if (cbor_value_calculate_string_length(&value_item, &expected_len) != CborNoError
        || expected_len > FACTORY_NVS_STRING_MAX_SIZE - 1) {
        coap_pdu_set_code(response, BO_COAP_CODE_400_BAD_REQUEST);
        return;
    }

    char str[FACTORY_NVS_STRING_MAX_SIZE] = { 0 };
    size_t str_len = sizeof(str);
    BO_COAP_TRY_DECODE(cbor_value_copy_text_string(&value_item, str, &str_len, NULL), response);

    nvs_handle_t nvs;
    BO_COAP_TRY(bo_nvs_factory_open(ns, NVS_READWRITE, &nvs), response);
    BO_NVS_AUTO_CLOSE(nvs);
    BO_COAP_TRY(nvs_set_str(nvs, key, str), response);

    coap_pdu_set_code(response, BO_COAP_CODE_204_CHANGED);
}

#define DEFINE_FACTORY_NUMERIC_HANDLERS(name, kind_value)                                                              \
    static void coap_hnd_factory_nvs_##name##_get(coap_resource_t* resource, coap_session_t* session,                  \
                                                  const coap_pdu_t* request, const coap_string_t* query,               \
                                                  coap_pdu_t* response)                                                \
    {                                                                                                                  \
        factory_nvs_handle_numeric_get(request, query, response, kind_value);                                          \
    }                                                                                                                  \
                                                                                                                       \
    static void coap_hnd_factory_nvs_##name##_set(coap_resource_t* resource, coap_session_t* session,                  \
                                                  const coap_pdu_t* request, const coap_string_t* query,               \
                                                  coap_pdu_t* response)                                                \
    {                                                                                                                  \
        factory_nvs_handle_numeric_set(request, response, kind_value);                                                 \
    }

DEFINE_FACTORY_NUMERIC_HANDLERS(u8, FACTORY_NVS_KIND_U8)
DEFINE_FACTORY_NUMERIC_HANDLERS(u16, FACTORY_NVS_KIND_U16)
DEFINE_FACTORY_NUMERIC_HANDLERS(u32, FACTORY_NVS_KIND_U32)
DEFINE_FACTORY_NUMERIC_HANDLERS(u64, FACTORY_NVS_KIND_U64)
DEFINE_FACTORY_NUMERIC_HANDLERS(i8, FACTORY_NVS_KIND_I8)
DEFINE_FACTORY_NUMERIC_HANDLERS(i32, FACTORY_NVS_KIND_I32)
DEFINE_FACTORY_NUMERIC_HANDLERS(i64, FACTORY_NVS_KIND_I64)

static void coap_hnd_factory_nvs_blob_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                          const coap_string_t* query, coap_pdu_t* response)
{
    factory_nvs_handle_blob_get(request, query, response);
}

static void coap_hnd_factory_nvs_blob_set(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                          const coap_string_t* query, coap_pdu_t* response)
{
    factory_nvs_handle_blob_set(request, response);
}

static void coap_hnd_factory_nvs_str_get(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                         const coap_string_t* query, coap_pdu_t* response)
{
    factory_nvs_handle_string_get(request, query, response);
}

static void coap_hnd_factory_nvs_str_set(coap_resource_t* resource, coap_session_t* session, const coap_pdu_t* request,
                                         const coap_string_t* query, coap_pdu_t* response)
{
    factory_nvs_handle_string_set(request, response);
}

static void coap_hnd_factory_nvs_exists_get(coap_resource_t* resource, coap_session_t* session,
                                            const coap_pdu_t* request, const coap_string_t* query, coap_pdu_t* response)
{
    char ns[32] = { 0 };
    char key[32] = { 0 };

    BO_COAP_TRY(factory_nvs_parse_query(request, query, ns, sizeof(ns), key, sizeof(key)), response);

    uint8_t encode_buf[16] = { 0 };
    CborEncoder encoder;
    cbor_encoder_init(&encoder, encode_buf, sizeof(encode_buf), 0);

    nvs_handle_t nvs;
    esp_err_t open_err = bo_nvs_factory_open(ns, NVS_READONLY, &nvs);
    if (open_err == ESP_ERR_NVS_NOT_FOUND) {
        // Namespace not found, so key doesn't exist
        BO_COAP_TRY_ENCODE(cbor_encode_boolean(&encoder, false), response);
        size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, encode_buf);
        coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, encode_buf);
        coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
        return;
    }
    else if (open_err != ESP_OK) {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE(400));
        return;
    }
    BO_NVS_AUTO_CLOSE(nvs);

    nvs_type_t type;
    esp_err_t err = nvs_find_key(nvs, key, &type);
    bool exists = (err == ESP_OK);
    if (err != ESP_OK && err != ESP_ERR_NVS_NOT_FOUND) {
        coap_pdu_set_code(response, COAP_RESPONSE_CODE(400));
        return;
    }

    BO_COAP_TRY_ENCODE(cbor_encode_boolean(&encoder, exists), response);
    size_t encoded_size = cbor_encoder_get_buffer_size(&encoder, encode_buf);
    coap_add_data_blocked_response(request, response, COAP_MEDIATYPE_APPLICATION_CBOR, 0, encoded_size, encode_buf);
    coap_pdu_set_code(response, COAP_RESPONSE_CODE_CONTENT);
}

#endif // CONFIG_BORNEO_PRODUCT_MODE_STANDALONE

COAP_RESOURCE_DEFINE("borneo/factory/reset", false, NULL, coap_hnd_borneo_factory_reset_post, NULL, NULL);

#if CONFIG_BORNEO_PRODUCT_MODE_STANDALONE

COAP_RESOURCE_DEFINE("borneo/factory/nvs/u8", false, coap_hnd_factory_nvs_u8_get, coap_hnd_factory_nvs_u8_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/u16", false, coap_hnd_factory_nvs_u16_get, coap_hnd_factory_nvs_u16_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/u32", false, coap_hnd_factory_nvs_u32_get, coap_hnd_factory_nvs_u32_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/u64", false, coap_hnd_factory_nvs_u64_get, coap_hnd_factory_nvs_u64_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/i8", false, coap_hnd_factory_nvs_i8_get, coap_hnd_factory_nvs_i8_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/i32", false, coap_hnd_factory_nvs_i32_get, coap_hnd_factory_nvs_i32_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/i64", false, coap_hnd_factory_nvs_i64_get, coap_hnd_factory_nvs_i64_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/blob", false, coap_hnd_factory_nvs_blob_get, coap_hnd_factory_nvs_blob_set,
                     NULL, NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/str", false, coap_hnd_factory_nvs_str_get, coap_hnd_factory_nvs_str_set, NULL,
                     NULL);
COAP_RESOURCE_DEFINE("borneo/factory/nvs/exists", false, coap_hnd_factory_nvs_exists_get, NULL, NULL, NULL);

#endif // CONFIG_BORNEO_PRODUCT_MODE_STANDALONE