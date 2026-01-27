#include <string.h>
#include <time.h>

#include <mbedtls/md.h>

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#include <esp_log.h>
#include <nvs_flash.h>

#include <borneo/nvs.h>
#include <borneo/auth.h>

#define TAG "bo_auth"
#define AUTH_NVS_NS "auth"
#define AUTH_NVS_KEY_ADMIN "admin_key"
#define AUTH_NVS_KEY_API "api_key"
#define AUTH_KEY_LENGTH 16 // 128-bit keys

static SemaphoreHandle_t _auth_mutex = NULL; // Protects auth_context access
static portMUX_TYPE _auth_ctx_spinlock = portMUX_INITIALIZER_UNLOCKED; // Protects auth_context
static struct auth_context _auth_ctx = { 0 }; // Global authentication context

esp_err_t bo_auth_init()
{
    esp_err_t err;

    // Create mutex for auth context operations
    _auth_mutex = xSemaphoreCreateMutex();
    if (_auth_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create auth mutex");
        return ESP_ERR_NO_MEM;
    }

    // Load keys from NVS if they exist
    nvs_handle_t handle;
    err = bo_nvs_user_open(AUTH_NVS_NS, NVS_READONLY, &handle);
    if (err == ESP_OK) {
        size_t key_len = AUTH_KEY_LENGTH;
        err = nvs_get_blob(handle, AUTH_NVS_KEY_ADMIN, _auth_ctx.admin_key, &key_len);
        if (err == ESP_OK && key_len == AUTH_KEY_LENGTH) {
            key_len = AUTH_KEY_LENGTH;
            err = nvs_get_blob(handle, AUTH_NVS_KEY_API, _auth_ctx.api_key, &key_len);
            if (err == ESP_OK && key_len == AUTH_KEY_LENGTH) {
                _auth_ctx.keys_loaded = true;
            }
        }
        nvs_close(handle);
    }

    return ESP_OK;
}

esp_err_t bo_auth_bind(const uint8_t* admin_token, size_t admin_token_len, const uint8_t* api_token,
                       size_t api_token_len, uint64_t timestamp)
{
    if (admin_token_len != AUTH_KEY_LENGTH || api_token_len != AUTH_KEY_LENGTH) {
        return ESP_ERR_INVALID_ARG;
    }

    // Validate timestamp (max 5 minutes difference)
    if (timestamp == 0) {
        ESP_LOGE(TAG, "Invalid timestamp: zero");
        return ESP_ERR_INVALID_ARG;
    }

    uint64_t current_time = (uint64_t)time(NULL);
    uint64_t time_diff = (current_time > timestamp) ? (current_time - timestamp) : (timestamp - current_time);
    const uint64_t max_diff = 300; // 5 minutes

    if (time_diff > max_diff) {
        ESP_LOGE(TAG, "Timestamp too old or too far in future. Diff: %llu seconds", time_diff);
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err;
    nvs_handle_t handle;

    // Open NVS for writing
    err = bo_nvs_user_open(AUTH_NVS_NS, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS namespace: %s", esp_err_to_name(err));
        return err;
    }

    // Store admin key
    err = nvs_set_blob(handle, AUTH_NVS_KEY_ADMIN, admin_token, AUTH_KEY_LENGTH);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to store admin key: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    // Store API key
    err = nvs_set_blob(handle, AUTH_NVS_KEY_API, api_token, AUTH_KEY_LENGTH);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to store API key: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(err));
        return err;
    }

    // Update memory cache with mutex protection
    if (xSemaphoreTake(_auth_mutex, portMAX_DELAY) == pdTRUE) {
        memcpy(_auth_ctx.admin_key, admin_token, AUTH_KEY_LENGTH);
        memcpy(_auth_ctx.api_key, api_token, AUTH_KEY_LENGTH);
        _auth_ctx.keys_loaded = true;
        xSemaphoreGive(_auth_mutex);
    }

    return ESP_OK;
}

/**
 * @brief Compute HMAC-SHA256 for authentication
 *
 * @param key 128-bit key (16 bytes)
 * @param timestamp Current system timestamp
 * @param output Output buffer for 32-byte HMAC result
 * @return ESP_OK on success, error code otherwise
 */
static esp_err_t _compute_hmac(const uint8_t* key, time_t timestamp, uint8_t* output)
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

    ret = mbedtls_md_hmac_starts(&ctx, key, AUTH_KEY_LENGTH);
    if (ret != 0) {
        ESP_LOGE(TAG, "mbedtls_md_hmac_starts failed: %d", ret);
        mbedtls_md_free(&ctx);
        return ESP_FAIL;
    }

    // Convert timestamp to bytes (big-endian)
    uint8_t timestamp_bytes[8];
    timestamp_bytes[0] = (timestamp >> 56) & 0xFF;
    timestamp_bytes[1] = (timestamp >> 48) & 0xFF;
    timestamp_bytes[2] = (timestamp >> 40) & 0xFF;
    timestamp_bytes[3] = (timestamp >> 32) & 0xFF;
    timestamp_bytes[4] = (timestamp >> 24) & 0xFF;
    timestamp_bytes[5] = (timestamp >> 16) & 0xFF;
    timestamp_bytes[6] = (timestamp >> 8) & 0xFF;
    timestamp_bytes[7] = timestamp & 0xFF;

    ret = mbedtls_md_hmac_update(&ctx, timestamp_bytes, sizeof(timestamp_bytes));
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

esp_err_t bo_auth_verify_token(const uint8_t* token, size_t token_len)
{
    if (token_len != 32 || !_auth_ctx.keys_loaded) {
        // Update global context with failure state
        portENTER_CRITICAL(&_auth_ctx_spinlock);
        _auth_ctx.authenticated = false;
        _auth_ctx.is_admin = false;
        _auth_ctx.token_expiry = 0;
        portEXIT_CRITICAL(&_auth_ctx_spinlock);
        return ESP_ERR_INVALID_ARG;
    }

    // Get current timestamp
    time_t now = time(NULL);
    if (now == 0) {
        ESP_LOGE(TAG, "System time not set, cannot verify token");
        portENTER_CRITICAL(&_auth_ctx_spinlock);
        _auth_ctx.authenticated = false;
        _auth_ctx.is_admin = false;
        _auth_ctx.token_expiry = 0;
        portEXIT_CRITICAL(&_auth_ctx_spinlock);
        return ESP_ERR_INVALID_STATE;
    }

    uint8_t computed[32];
    esp_err_t result = ESP_FAIL;

    // Take mutex for thread-safe key access
    if (xSemaphoreTake(_auth_mutex, pdMS_TO_TICKS(1000)) != pdTRUE) {
        ESP_LOGE(TAG, "Failed to acquire auth mutex");
        portENTER_CRITICAL(&_auth_ctx_spinlock);
        _auth_ctx.authenticated = false;
        _auth_ctx.is_admin = false;
        _auth_ctx.token_expiry = 0;
        portEXIT_CRITICAL(&_auth_ctx_spinlock);
        return ESP_ERR_TIMEOUT;
    }

    // Check admin token
    esp_err_t err = _compute_hmac(_auth_ctx.admin_key, now, computed);
    if (err == ESP_OK && memcmp(token, computed, 32) == 0) {
        // Update global context with success state
        portENTER_CRITICAL(&_auth_ctx_spinlock);
        _auth_ctx.authenticated = true;
        _auth_ctx.is_admin = true;
        _auth_ctx.token_expiry = (uint32_t)now + 3600; // Auto-refresh: 1 hour expiry
        portEXIT_CRITICAL(&_auth_ctx_spinlock);
        result = ESP_OK;
    }
    else {
        // Check API token
        err = _compute_hmac(_auth_ctx.api_key, now, computed);
        if (err == ESP_OK && memcmp(token, computed, 32) == 0) {
            // Update global context with success state
            portENTER_CRITICAL(&_auth_ctx_spinlock);
            _auth_ctx.authenticated = true;
            _auth_ctx.is_admin = false;
            _auth_ctx.token_expiry = 0; // API token never expires
            portEXIT_CRITICAL(&_auth_ctx_spinlock);
            result = ESP_OK;
        }
    }

    xSemaphoreGive(_auth_mutex);

    if (result != ESP_OK) {
        // Update global context with failure state
        portENTER_CRITICAL(&_auth_ctx_spinlock);
        _auth_ctx.authenticated = false;
        _auth_ctx.is_admin = false;
        _auth_ctx.token_expiry = 0;
        portEXIT_CRITICAL(&_auth_ctx_spinlock);
    }

    return result;
}

bool bo_auth_check_perm(auth_resource_permission_t required_perm)
{
    // Enter critical section for reading auth context
    portENTER_CRITICAL(&_auth_ctx_spinlock);

    bool result;
    if (required_perm == AUTH_PERM_PUBLIC) {
        result = true;
    }
    else if (!_auth_ctx.authenticated) {
        result = false;
    }
    else if (required_perm == AUTH_PERM_AUTHENTICATED) {
        result = true;
    }
    else if (required_perm == AUTH_PERM_ADMIN) {
        result = _auth_ctx.is_admin;
    }
    else {
        result = false;
    }

    portEXIT_CRITICAL(&_auth_ctx_spinlock);
    return result;
}

bool bo_auth_is_token_expired()
{
    // Enter critical section for reading auth context
    portENTER_CRITICAL(&_auth_ctx_spinlock);

    bool result;
    if (!_auth_ctx.authenticated) {
        result = true; // Unauthenticated is considered expired
    }
    else if (_auth_ctx.token_expiry == 0) {
        result = false; // token_expiry == 0 means never expires (API key)
    }
    else {
        time_t now = time(NULL);
        result = (uint32_t)now >= _auth_ctx.token_expiry;
    }

    portEXIT_CRITICAL(&_auth_ctx_spinlock);
    return result;
}

/**
 * @brief Get current authentication context (thread-safe)
 *
 * @param ctx Output buffer for authentication context
 * @return ESP_OK on success
 */
esp_err_t bo_auth_get_context(struct auth_context* ctx)
{
    if (ctx == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    // Enter critical section for reading auth context
    portENTER_CRITICAL(&_auth_ctx_spinlock);
    memcpy(ctx, &_auth_ctx, sizeof(struct auth_context));
    portEXIT_CRITICAL(&_auth_ctx_spinlock);

    return ESP_OK;
}
