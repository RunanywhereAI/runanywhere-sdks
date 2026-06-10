/**
 * @file rac_sdk_state.h
 * @brief Centralized SDK state management (C++ equivalent of ServiceContainer)
 *
 * This holds non-auth SDK runtime state. Auth state (tokens, user/org IDs,
 * refresh-window math, persistence) lives exclusively in rac_auth_manager.h.
 * This file owns everything else: environment/api_key/base_url/device_id
 * (set once at init) and the device registration flag.
 *
 * Pattern mirrors Swift's ServiceContainer:
 * - Singleton access via rac_state_get_instance()
 * - Lazy initialization for sub-components
 * - Thread-safe access via internal mutex
 * - Reset capability for testing
 *
 * State Categories:
 * 1. Device State   - Device ID, registration status
 * 2. Environment    - SDK environment, API key, base URL
 *
 * For auth state (tokens, user/org IDs, expiry), see rac_auth_manager.h.
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
RAC_API rac_sdk_state_handle_t rac_state_get_instance(void);

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
RAC_API rac_result_t rac_state_initialize(rac_environment_t env, const char* api_key,
                                          const char* base_url, const char* device_id);

/**
 * @brief Check if SDK state is initialized
 * @return true if initialized
 */
RAC_API bool rac_state_is_initialized(void);

/**
 * @brief Reset all state (for testing or re-initialization)
 *
 * Clears all state including auth tokens, handles, etc.
 * Does NOT free the singleton - just resets to initial state.
 */
RAC_API void rac_state_reset(void);

/**
 * @brief Shutdown and free all resources
 *
 * Called during SDK shutdown. Frees all memory and destroys handles.
 */
RAC_API void rac_state_shutdown(void);

// =============================================================================
// Environment Queries
// =============================================================================

/**
 * @brief Get current environment
 * @return The SDK environment
 */
RAC_API rac_environment_t rac_state_get_environment(void);

/**
 * @brief Get base URL
 * @return The base URL string (do not free)
 */
RAC_API const char* rac_state_get_base_url(void);

/**
 * @brief Get API key
 * @return The API key string (do not free)
 */
RAC_API const char* rac_state_get_api_key(void);

/**
 * @brief Get device ID
 * @return The device ID string (do not free)
 */
RAC_API const char* rac_state_get_device_id(void);

// =============================================================================
// Device State Management
// =============================================================================

/**
 * @brief Set device registration status
 * @param registered Whether device is registered with backend
 */
RAC_API void rac_state_set_device_registered(bool registered);

/**
 * @brief Check if device is registered
 * @return true if device has been registered
 */
RAC_API bool rac_state_is_device_registered(void);

#ifdef __cplusplus
}
#endif

#endif  // RAC_SDK_STATE_H
