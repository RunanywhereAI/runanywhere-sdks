/**
 * @file rac_auth_manager.h
 * @brief Authentication state management
 *
 * Manages authentication state including tokens, expiry, and refresh logic.
 * Platform SDKs provide HTTP transport and secure storage callbacks.
 */

#ifndef RAC_AUTH_MANAGER_H
#define RAC_AUTH_MANAGER_H

#include <stdbool.h>
#include <stdint.h>

#include "rac_api_types.h"
#include "rac_environment.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Auth State
// =============================================================================

/**
 * @brief Authentication state structure
 *
 * Managed internally - use accessor functions.
 */
typedef struct {
    char* access_token;
    char* refresh_token;
    char* device_id;
    char* user_id;  // Can be NULL
    char* organization_id;
    int64_t token_expires_at;  // Unix timestamp (seconds)
    bool is_authenticated;
} rac_auth_state_t;

// =============================================================================
// Platform Callbacks
// =============================================================================

/**
 * @brief Callback for secure storage operations
 *
 * Platform implements to store tokens in Keychain/KeyStore.
 */
typedef struct {
    /**
     * @brief Store string value securely
     * @param key Storage key
     * @param value Value to store
     * @return 0 on success, -1 on error
     */
    int (*store)(const char* key, const char* value, void* context);

    /**
     * @brief Retrieve string value
     * @param key Storage key
     * @param out_value Output buffer (caller provides)
     * @param buffer_size Size of output buffer
     * @return Length of value, or -1 on error/not found
     */
    int (*retrieve)(const char* key, char* out_value, size_t buffer_size, void* context);

    /**
     * @brief Delete stored value
     * @param key Storage key
     * @return 0 on success, -1 on error
     */
    int (*delete_key)(const char* key, void* context);

    /**
     * @brief Context pointer passed to all callbacks
     */
    void* context;
} rac_secure_storage_t;

// =============================================================================
// Keychain Keys (for platform implementations)
// =============================================================================

#define RAC_KEY_ACCESS_TOKEN "com.runanywhere.sdk.accessToken"
#define RAC_KEY_REFRESH_TOKEN "com.runanywhere.sdk.refreshToken"
#define RAC_KEY_DEVICE_ID "com.runanywhere.sdk.deviceId"
#define RAC_KEY_USER_ID "com.runanywhere.sdk.userId"
#define RAC_KEY_ORGANIZATION_ID "com.runanywhere.sdk.organizationId"

// =============================================================================
// Initialization
// =============================================================================

/**
 * @brief Initialize auth manager
 * @param storage Secure storage callbacks (can be NULL for in-memory only)
 */
void rac_auth_init(const rac_secure_storage_t* storage);

/**
 * @brief Reset auth manager state
 */
void rac_auth_reset(void);

// =============================================================================
// Token State
// =============================================================================

/**
 * @brief Check if currently authenticated
 * @return true if valid access token exists
 */
bool rac_auth_is_authenticated(void);

/**
 * @brief Check if token needs refresh
 *
 * Returns true if token expires within 60 seconds.
 *
 * @return true if token should be refreshed
 */
bool rac_auth_needs_refresh(void);

/**
 * @brief Get current access token
 * @return Access token string, or NULL if not authenticated
 */
const char* rac_auth_get_access_token(void);

/**
 * @brief Get current device ID
 * @return Device ID string, or NULL if not set
 */
const char* rac_auth_get_device_id(void);

/**
 * @brief Get current user ID
 * @return User ID string, or NULL if not set
 */
const char* rac_auth_get_user_id(void);

/**
 * @brief Get current organization ID
 * @return Organization ID string, or NULL if not set
 */
const char* rac_auth_get_organization_id(void);

// =============================================================================
// Request Building
// =============================================================================

/**
 * @brief Build authentication request JSON
 *
 * Creates JSON payload for POST /api/v1/auth/sdk/authenticate
 *
 * @param config SDK configuration with credentials
 * @return JSON string (caller must free), or NULL on error
 */
char* rac_auth_build_authenticate_request(const rac_sdk_config_t* config);

/**
 * @brief Build token refresh request JSON
 *
 * Creates JSON payload for POST /api/v1/auth/sdk/refresh
 *
 * @return JSON string (caller must free), or NULL if no refresh token
 */
char* rac_auth_build_refresh_request(void);

// =============================================================================
// Response Handling
// =============================================================================

/**
 * @brief Parse and store authentication response
 *
 * Updates internal auth state and optionally persists to secure storage.
 *
 * @param json JSON response body
 * @return 0 on success, -1 on parse error
 */
int rac_auth_handle_authenticate_response(const char* json);

/**
 * @brief Parse and store refresh response
 *
 * Updates internal auth state and optionally persists to secure storage.
 *
 * @param json JSON response body
 * @return 0 on success, -1 on parse error
 */
int rac_auth_handle_refresh_response(const char* json);

// =============================================================================
// Token Management
// =============================================================================

/**
 * @brief Get valid access token, triggering refresh if needed
 *
 * This is the main entry point for getting a token. If the current token
 * is expired or about to expire, it will:
 * 1. Build a refresh request
 * 2. Return a pending state indicating refresh is needed
 *
 * Platform must then:
 * 1. Execute the HTTP request
 * 2. Call rac_auth_handle_refresh_response with result
 * 3. Call this function again to get the new token
 *
 * @param out_token Output pointer for token string
 * @param out_needs_refresh Set to true if refresh HTTP call is needed
 * @return 0 on success (token valid), 1 if refresh needed, -1 on error
 */
int rac_auth_get_valid_token(const char** out_token, bool* out_needs_refresh);

/**
 * @brief Clear all authentication state
 *
 * Clears in-memory state and secure storage.
 */
void rac_auth_clear(void);

// =============================================================================
// Persistence
// =============================================================================

/**
 * @brief Load tokens from secure storage
 *
 * Call during initialization to restore saved auth state.
 *
 * @return 0 on success (tokens loaded), -1 if not found or error
 */
int rac_auth_load_stored_tokens(void);

/**
 * @brief Save current tokens to secure storage
 *
 * Called automatically by response handlers, but can be called manually.
 *
 * @return 0 on success, -1 on error
 */
int rac_auth_save_tokens(void);

#ifdef __cplusplus
}
#endif

#endif  // RAC_AUTH_MANAGER_H
