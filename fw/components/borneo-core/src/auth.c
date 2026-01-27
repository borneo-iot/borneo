#include <string.h>

#include <mbedtls/md.h>

#include <esp_log.h>
#include <nvs_flash.h>

#include <borneo/nvs.h>
#include <borneo/auth.h>

#define TAG "bo_auth"
#define AUTH_NVS_NS "auth"
#define AUTH_NVS_KEY_ADMIN "admin_key"
#define AUTH_NVS_KEY_API "api_key"

static nvs_handle_t _auth_handle = 0;
static uint8_t _admin_key[32];
static uint8_t _api_key[32];
static bool _keys_loaded = false;

esp_err_t bo_auth_init()
{
    esp_err_t err;

    // Open NVS namespace
    err = bo_nvs_user_open(AUTH_NVS_NS, NVS_READWRITE, &_auth_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS namespace: %s", esp_err_to_name(err));
        return err;
    }

    // Load keys if exist
    size_t key_len = 32;
    err = nvs_get_blob(_auth_handle, AUTH_NVS_KEY_ADMIN, _admin_key, &key_len);
    if (err == ESP_OK && key_len == 32) {
        err = nvs_get_blob(_auth_handle, AUTH_NVS_KEY_API, _api_key, &key_len);
        if (err == ESP_OK && key_len == 32) {
            _keys_loaded = true;
        }
    }

    return ESP_OK;
}

esp_err_t bo_auth_bind(const uint8_t* admin_token, size_t admin_token_len, const uint8_t* api_token,
                       size_t api_token_len)
{
    if (admin_token_len != 32 || api_token_len != 32) {
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err;

    // Store admin key
    err = nvs_set_blob(_auth_handle, AUTH_NVS_KEY_ADMIN, admin_token, 32);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to store admin key: %s", esp_err_to_name(err));
        return err;
    }

    // Store API key
    err = nvs_set_blob(_auth_handle, AUTH_NVS_KEY_API, api_token, 32);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to store API key: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_commit(_auth_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(err));
        return err;
    }

    memcpy(_admin_key, admin_token, 32);
    memcpy(_api_key, api_token, 32);
    _keys_loaded = true;

    return ESP_OK;
}

static esp_err_t _compute_hmac(const uint8_t* key, uint32_t nonce, uint8_t* output)
{
    const mbedtls_md_info_t* md_info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!md_info) {
        return ESP_FAIL;
    }

    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    int ret = mbedtls_md_setup(&ctx, md_info, 1); // 1 for HMAC
    if (ret != 0) {
        ESP_LOGE(TAG, "mbedtls_md_setup failed: %d", ret);
        return ESP_FAIL;
    }

    ret = mbedtls_md_hmac_starts(&ctx, key, 32);
    if (ret != 0) {
        ESP_LOGE(TAG, "mbedtls_md_hmac_starts failed: %d", ret);
        mbedtls_md_free(&ctx);
        return ESP_FAIL;
    }

    uint8_t nonce_bytes[4];
    nonce_bytes[0] = (nonce >> 24) & 0xFF;
    nonce_bytes[1] = (nonce >> 16) & 0xFF;
    nonce_bytes[2] = (nonce >> 8) & 0xFF;
    nonce_bytes[3] = nonce & 0xFF;

    ret = mbedtls_md_hmac_update(&ctx, nonce_bytes, 4);
    if (ret != 0) {
        ESP_LOGE(TAG, "mbedtls_md_hmac_update failed: %d", ret);
        mbedtls_md_free(&ctx);
        return ESP_FAIL;
    }

    ret = mbedtls_md_hmac_finish(&ctx, output);
    if (ret != 0) {
        ESP_LOGE(TAG, "mbedtls_md_hmac_finish failed: %d", ret);
        mbedtls_md_free(&ctx);
        return ESP_FAIL;
    }

    mbedtls_md_free(&ctx);
    return ESP_OK;
}

esp_err_t bo_auth_verify_token(const uint8_t* token, size_t token_len, uint32_t nonce, struct auth_context* ctx)
{
    if (token_len != 32 || !_keys_loaded) {
        ctx->authenticated = false;
        ctx->is_admin = false;
        ctx->token_expiry = 0;
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t computed[32];

    // Check admin token
    esp_err_t err = _compute_hmac(_admin_key, nonce, computed);
    if (err != ESP_OK) {
        return err;
    }
    if (memcmp(token, computed, 32) == 0) {
        ctx->authenticated = true;
        ctx->is_admin = true;
        ctx->token_expiry = nonce + 3600; // 1 hour expiry
        return ESP_OK;
    }

    // Check API token
    err = _compute_hmac(_api_key, nonce, computed);
    if (err != ESP_OK) {
        return err;
    }
    if (memcmp(token, computed, 32) == 0) {
        ctx->authenticated = true;
        ctx->is_admin = false;
        ctx->token_expiry = nonce + 3600; // 1 hour expiry
        return ESP_OK;
    }

    ctx->authenticated = false;
    ctx->is_admin = false;
    ctx->token_expiry = 0;
    return ESP_FAIL;
}

bool bo_auth_check_perm(auth_resource_permission_t required_perm, const struct auth_context* ctx)
{
    if (required_perm == AUTH_PERM_PUBLIC) {
        return true;
    }
    if (!ctx->authenticated) {
        return false;
    }
    if (required_perm == AUTH_PERM_AUTHENTICATED) {
        return true;
    }
    if (required_perm == AUTH_PERM_ADMIN) {
        return ctx->is_admin;
    }
    return false;
}

void bo_auth_deinit()
{
    if (_auth_handle) {
        bo_nvs_close(_auth_handle);
        _auth_handle = 0;
    }
    _keys_loaded = false;
}