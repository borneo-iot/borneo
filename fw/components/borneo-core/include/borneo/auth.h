#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <esp_err.h>
#include <stdint.h>
#include <stdbool.h>

// Resource permission enumeration
typedef enum {
    AUTH_PERM_PUBLIC = 0, ///< Public resource, no authentication required
    AUTH_PERM_AUTHENTICATED = 1, ///< Requires authentication
    AUTH_PERM_ADMIN = 2, ///< Requires admin privileges
} auth_resource_permission_t;

// Authentication context
struct auth_context {
    bool authenticated;
    bool is_admin;
    uint32_t token_expiry; // Expiration timestamp
};

// Initialize authentication module
esp_err_t bo_auth_init();

// Bind authentication tokens, provided externally with admin_token and api_token
// admin_token: Admin token (32 bytes)
// api_token: API token for automated operations (32 bytes)
esp_err_t bo_auth_bind(const uint8_t* admin_token, size_t admin_token_len, const uint8_t* api_token,
                       size_t api_token_len);

// Verify token and set context
// token: Provided token (32 bytes)
// nonce: Timestamp or random number
// ctx: Output authentication context
esp_err_t bo_auth_verify_token(const uint8_t* token, size_t token_len, uint32_t nonce, struct auth_context* ctx);

// Check permissions
// required_perm: Required permission
// ctx: Current authentication context
bool bo_auth_check_perm(auth_resource_permission_t required_perm, const struct auth_context* ctx);

// Deinitialize authentication module
void bo_auth_deinit();

#ifdef __cplusplus
}
#endif