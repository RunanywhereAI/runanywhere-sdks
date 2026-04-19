/**
 * @file rac_sdk_state.h
 * @brief Centralized SDK state management (C++ equivalent of ServiceContainer)
 *
 * This is the single source of truth for all SDK runtime state.
 * Platform SDKs (Swift, Kotlin, Flutter) should query state from here
 * rather than maintaining their own copies.
 *
 * Pattern mirrors Swift's ServiceContainer:
 * - Singleton access via rac_state_get_instance()
 * - Lazy initialization for sub-components
 * - Thread-safe access via internal mutex
 * - Reset capability for testing
 *
 * State Categories:
 * 1. Auth State     - Tokens, user/org IDs, authentication status
 * 2. Device State   - Device ID, registration status
 * 3. Environment    - SDK environment, API key, base URL
 * 4. Services       - Telemetry manager, model registry handles
 */

#ifndef RAC_SDK_STATE_H
#define RAC_SDK_STATE_H

#include <stdbool.h>
#include <stdint.h>

#include "rac_types.h"                          // For rac_result_t, RAC_SUCCESS
#include "rac_environment.h"  // For rac_environment_t

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// State Structure (Opaque - internal structure hidden from C API)
// =============================================================================

/**
 * @brief Opaque handle to SDK state
 *
 * The internal structure is hidden to allow C++ implementation
 * while exposing a clean C API for platform interop.
 */
typedef struct rac_sdk_state* rac_sdk_state_handle_t;

// =============================================================================
// Auth Data Input Structure (Public - for platform to populate)
// =============================================================================

/**
 * @brief Authentication data input
 *
 * Platforms use this to set auth state after successful HTTP authentication.
 * C++ copies the data internally and manages lifetime.
 *
 * Note: This is distinct from rac_auth_state_t in rac_auth_manager.h which
 * is the internal state structure.
 */
typedef struct {
    const char* access_token;
    const char* refresh_token;
    int64_t expires_at_unix;  // Unix timestamp (seconds)
    const char* user_id;      // Nullable
    const char* organization_id;
    const char* device_id;
} rac_auth_data_t;

// =============================================================================
// Singleton Access
// =============================================================================

/**
 * @brief Get the singleton SDK state instance
 *
 * Creates the instance on first call (lazy initialization).
 * Thread-safe.
 *
 * @return Handle to the SDK state (never NULL after first call)
 */
rac_sdk_state_handle_t rac_state_get_instance(void);

// =============================================================================
// Initialization & Lifecycle
// =============================================================================

/**
 * @brief Initialize SDK state with configuration
 *
 * Called during SDK initialization. Sets up environment and base config.
 *
 * @param env The SDK environment (development, staging, production)
 * @param api_key The API key (copied internally)
 * @param base_url The base URL (copied internally)
 * @param device_id The persistent device ID (copied internally)
 * @return RAC_SUCCESS on success
 */
rac_result_t rac_state_initialize(rac_environment_t env, const char* api_key, const char* base_url,
                                  const char* device_id);

/**
 * @brief Check if SDK state is initialized
 * @return true if initialized
 */
bool rac_state_is_initialized(void);

/**
 * @brief Reset all state (for testing or re-initialization)
 *
 * Clears all state including auth tokens, handles, etc.
 * Does NOT free the singleton - just resets to initial state.
 */
void rac_state_reset(void);

/**
 * @brief Shutdown and free all resources
 *
 * Called during SDK shutdown. Frees all memory and destroys handles.
 */
void rac_state_shutdown(void);

// =============================================================================
// Environment Queries
// =============================================================================

/**
 * @brief Get current environment
 * @return The SDK environment
 */
rac_environment_t rac_state_get_environment(void);

/**
 * @brief Get base URL
 * @return The base URL string (do not free)
 */
const char* rac_state_get_base_url(void);

/**
 * @brief Get API key
 * @return The API key string (do not free)
 */
const char* rac_state_get_api_key(void);

/**
 * @brief Get device ID
 * @return The device ID string (do not free)
 */
const char* rac_state_get_device_id(void);

// =============================================================================
// Auth State Management
// =============================================================================

/**
 * @brief Set authentication state after successful auth
 *
 * Called by platform after HTTP auth response is received.
 * Copies all strings internally.
 *
 * @param auth The auth data to set
 * @return RAC_SUCCESS on success
 */
rac_result_t rac_state_set_auth(const rac_auth_data_t* auth);

/**
 * @brief Get current access token
 * @return Access token string or NULL if not authenticated (do not free)
 */
const char* rac_state_get_access_token(void);

/**
 * @brief Get current refresh token
 * @return Refresh token string or NULL (do not free)
 */
const char* rac_state_get_refresh_token(void);

/**
 * @brief Check if currently authenticated
 * @return true if authenticated with valid (non-expired) token
 */
bool rac_state_is_authenticated(void);

/**
 * @brief Check if token needs refresh
 *
 * Returns true if token expires within the next 60 seconds.
 *
 * @return true if refresh is needed
 */
bool rac_state_token_needs_refresh(void);

/**
 * @brief Get token expiry timestamp
 * @return Unix timestamp (seconds) when token expires, or 0 if not set
 */
int64_t rac_state_get_token_expires_at(void);

/**
 * @brief Get user ID
 * @return User ID string or NULL (do not free)
 */
const char* rac_state_get_user_id(void);

/**
 * @brief Get organization ID
 * @return Organization ID string or NULL (do not free)
 */
const char* rac_state_get_organization_id(void);

/**
 * @brief Clear authentication state
 *
 * Called on logout or auth failure. Clears tokens but not device/env config.
 */
void rac_state_clear_auth(void);

// =============================================================================
// Device State Management
// =============================================================================

/**
 * @brief Set device registration status
 * @param registered Whether device is registered with backend
 */
void rac_state_set_device_registered(bool registered);

/**
 * @brief Check if device is registered
 * @return true if device has been registered
 */
bool rac_state_is_device_registered(void);

// =============================================================================
// State Change Callbacks (for platform observers)
// =============================================================================

/**
 * @brief Callback type for auth state changes
 * @param is_authenticated Current auth status
 * @param user_data User-provided context
 */
typedef void (*rac_auth_changed_callback_t)(bool is_authenticated, void* user_data);

/**
 * @brief Register callback for auth state changes
 *
 * Called whenever auth state changes (login, logout, token refresh).
 *
 * @param callback The callback function (NULL to unregister)
 * @param user_data Context passed to callback
 */
void rac_state_on_auth_changed(rac_auth_changed_callback_t callback, void* user_data);

// =============================================================================
// Persistence Bridge (Platform implements secure storage)
// =============================================================================

/**
 * @brief Callback type for persisting state to secure storage
 * @param key The key to store under
 * @param value The value to store (NULL to delete)
 * @param user_data User-provided context
 */
typedef void (*rac_persist_callback_t)(const char* key, const char* value, void* user_data);

/**
 * @brief Callback type for loading state from secure storage
 * @param key The key to load
 * @param user_data User-provided context
 * @return The stored value or NULL (caller must NOT free)
 */
typedef const char* (*rac_load_callback_t)(const char* key, void* user_data);

/**
 * @brief Register callbacks for secure storage
 *
 * Platform implements these to persist to Keychain/KeyStore.
 * C++ calls persist_callback when state changes.
 * C++ calls load_callback during initialization.
 *
 * @param persist Callback to persist a value
 * @param load Callback to load a value
 * @param user_data Context passed to callbacks
 */
void rac_state_set_persistence_callbacks(rac_persist_callback_t persist, rac_load_callback_t load,
                                         void* user_data);

#ifdef __cplusplus
}
#endif

#endif  // RAC_SDK_STATE_H
