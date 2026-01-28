#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <esp_err.h>
#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Resource permission enumeration
 */
typedef enum {
    AUTH_PERM_PUBLIC = 0, ///< Public resource, no authentication required
    AUTH_PERM_AUTHENTICATED = 1, ///< Requires authentication
    AUTH_PERM_ADMIN = 2, ///< Requires admin privileges
} auth_resource_permission_t;

/**
 * @brief Authentication context structure
 */
struct auth_context {
    bool authenticated; ///< Whether the user is authenticated
    bool is_admin; ///< Whether the user has admin privileges
    uint64_t token_expiry; ///< Expiration timestamp (0 means never expires)
    uint8_t admin_key[16]; ///< Cached admin key (128-bit)
    uint8_t api_key[16]; ///< Cached API key (128-bit)
    bool keys_loaded; ///< Whether keys have been loaded from NVS
};

/**
 * @brief Initialize authentication module
 *
 * Opens NVS namespace and loads existing keys if available.
 * Creates mutex for thread-safe operations.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t bo_auth_init();

/**
 * @brief Pair authentication tokens
 *
 * Stores admin and API tokens in NVS and updates memory cache.
 * Both tokens must be 16 bytes (128-bit) long.
 * Validates timestamp to prevent replay attacks (max 5 minutes difference).
 *
 * @param admin_token Admin token (16 bytes, 128-bit)
 * @param admin_token_len Length of admin token (must be 16)
 * @param api_token API token for automated operations (16 bytes, 128-bit)
 * @param api_token_len Length of API token (must be 16)
 * @param timestamp Client timestamp for validation
 * @return ESP_OK on success, ESP_ERR_INVALID_ARG if lengths are wrong or timestamp invalid
 */
esp_err_t bo_auth_pair(const uint8_t* admin_token, size_t admin_token_len, const uint8_t* api_token,
                       size_t api_token_len, uint64_t timestamp);

/**
 * @brief Verify token and check permissions
 *
 * Uses current system timestamp for HMAC verification.
 * Admin tokens auto-refresh with 1 hour expiry, API tokens never expire.
 * Updates global authentication context on success/failure.
 * Checks if the required permission is granted after verification.
 *
 * @param token Provided token (32 bytes HMAC-SHA256 output)
 * @param token_len Length of token (must be 32)
 * @param required_perm Required permission level
 * @return true if token is valid and permission is granted, false otherwise
 */
bool bo_auth_verify_token(const uint8_t* token, size_t token_len, auth_resource_permission_t required_perm);

/**
 * @brief Check if the given token is expired
 *
 * @param token The token to check (32 bytes HMAC-SHA256 output)
 * @param token_len Length of token (must be 32)
 * @return true if expired or invalid, false if valid
 * @note Admin tokens expire after 1 hour, API tokens never expire
 */
bool bo_auth_is_token_expired(const uint8_t* token, size_t token_len);

/**
 * @brief Get current authentication context (thread-safe)
 *
 * @param ctx Output buffer for authentication context
 * @return ESP_OK on success
 */
esp_err_t bo_auth_get_context(struct auth_context* ctx);

#ifdef __cplusplus
}
#endif