/**
 * @file rac_device_manager.h
 * @brief Device Registration Manager - C++ Business Logic Layer
 *
 * Handles device registration orchestration with all business logic in C++.
 * Platform SDKs (Swift, Kotlin) provide callbacks for:
 * - Device info gathering (platform-specific APIs)
 * - Device ID retrieval (Keychain/Keystore)
 * - Registration persistence (UserDefaults/SharedPreferences)
 * - HTTP transport (URLSession/OkHttp)
 *
 * Events are emitted via rac_analytics_event_emit().
 */

#ifndef RAC_DEVICE_MANAGER_H
#define RAC_DEVICE_MANAGER_H

#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CALLBACK TYPES
// =============================================================================

/**
 * @brief HTTP response for device registration
 */
typedef struct rac_device_http_response {
    rac_result_t result;        // RAC_SUCCESS on success
    int32_t status_code;        // HTTP status code (200, 400, etc.)
    const char* response_body;  // Response JSON (can be NULL)
    const char* error_message;  // Error message (can be NULL)
} rac_device_http_response_t;

/**
 * @brief Callback function types for platform-specific operations
 */

/**
 * Get device information (Swift calls DeviceInfo.current)
 * @param out_info Output parameter for device info
 * @param user_data User-provided context
 */
typedef void (*rac_device_get_info_fn)(rac_device_registration_info_t* out_info, void* user_data);

/**
 * Get persistent device ID (Swift calls DeviceIdentity.persistentUUID)
 * @param user_data User-provided context
 * @return Device ID string (must remain valid during callback)
 */
typedef const char* (*rac_device_get_id_fn)(void* user_data);

/**
 * Check if device is already registered (Swift checks UserDefaults)
 * @param user_data User-provided context
 * @return RAC_TRUE if registered, RAC_FALSE otherwise
 */
typedef rac_bool_t (*rac_device_is_registered_fn)(void* user_data);

/**
 * Mark device as registered/unregistered (Swift sets UserDefaults)
 * @param registered RAC_TRUE to mark as registered, RAC_FALSE to clear
 * @param user_data User-provided context
 */
typedef void (*rac_device_set_registered_fn)(rac_bool_t registered, void* user_data);

/**
 * Make HTTP POST request for device registration
 * @param endpoint Full endpoint URL
 * @param json_body JSON body to POST
 * @param requires_auth Whether authentication header is required
 * @param out_response Output parameter for response
 * @param user_data User-provided context
 * @return RAC_SUCCESS on success, error code otherwise
 */
typedef rac_result_t (*rac_device_http_post_fn)(const char* endpoint, const char* json_body,
                                                rac_bool_t requires_auth,
                                                rac_device_http_response_t* out_response,
                                                void* user_data);

/**
 * @brief Callback structure for platform-specific operations
 *
 * Platform SDKs set these callbacks at initialization.
 * C++ device manager calls these to access platform services.
 */
typedef struct rac_device_callbacks {
    /** Get device hardware/OS information */
    rac_device_get_info_fn get_device_info;

    /** Get persistent device UUID (Keychain/Keystore) */
    rac_device_get_id_fn get_device_id;

    /** Check if device is registered (UserDefaults/SharedPreferences) */
    rac_device_is_registered_fn is_registered;

    /** Set registration status */
    rac_device_set_registered_fn set_registered;

    /** Make HTTP POST request */
    rac_device_http_post_fn http_post;

    /** User data passed to all callbacks */
    void* user_data;
} rac_device_callbacks_t;

// =============================================================================
// DEVICE MANAGER API
// =============================================================================

/**
 * @brief Set callbacks for device manager operations
 *
 * Must be called before any other device manager functions.
 * Typically called during SDK initialization.
 *
 * @param callbacks Callback structure (copied internally)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_device_manager_set_callbacks(const rac_device_callbacks_t* callbacks);

/**
 * @brief Register device with backend if not already registered
 *
 * This is the main entry point for device registration.
 * Business logic:
 * 1. Check if already registered (via callback)
 * 2. If not, gather device info (via callback)
 * 3. Build JSON payload (C++ implementation)
 * 4. POST to backend (via callback)
 * 5. On success, mark as registered (via callback)
 * 6. Emit appropriate analytics event
 *
 * @param env Current SDK environment
 * @param build_token Optional build token for development mode (can be NULL)
 * @return RAC_SUCCESS on success or if already registered, error code otherwise
 */
RAC_API rac_result_t rac_device_manager_register_if_needed(rac_environment_t env,
                                                           const char* build_token);

/**
 * @brief Check if device is registered
 *
 * Delegates to the is_registered callback.
 *
 * @return RAC_TRUE if registered, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_device_manager_is_registered(void);

/**
 * @brief Clear device registration status
 *
 * Delegates to the set_registered callback with RAC_FALSE.
 * Useful for testing or user-initiated reset.
 */
RAC_API void rac_device_manager_clear_registration(void);

/**
 * @brief Get the current device ID
 *
 * Delegates to the get_device_id callback.
 *
 * @return Device ID string or NULL if callbacks not set
 */
RAC_API const char* rac_device_manager_get_device_id(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DEVICE_MANAGER_H */
