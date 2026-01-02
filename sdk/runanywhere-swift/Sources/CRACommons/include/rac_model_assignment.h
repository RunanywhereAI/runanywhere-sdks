/**
 * @file rac_model_assignment.h
 * @brief Model Assignment Manager - Fetches models assigned to device from backend
 *
 * Handles fetching model assignments from the backend API.
 * Business logic (caching, JSON parsing, registry saving) is in C++.
 * Platform SDKs provide HTTP GET callback for network transport.
 *
 * Events are emitted via rac_analytics_event_emit().
 */

#ifndef RAC_MODEL_ASSIGNMENT_H
#define RAC_MODEL_ASSIGNMENT_H

#include "rac_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CALLBACK TYPES
// =============================================================================

/**
 * @brief HTTP response for model assignment fetch
 */
typedef struct rac_assignment_http_response {
    rac_result_t result;        // RAC_SUCCESS on success
    int32_t status_code;        // HTTP status code (200, 400, etc.)
    const char* response_body;  // Response JSON (must remain valid during processing)
    size_t response_length;     // Length of response body
    const char* error_message;  // Error message (can be NULL)
} rac_assignment_http_response_t;

/**
 * @brief Device info for model assignment request
 */
typedef struct rac_assignment_device_info {
    const char* device_type;  // e.g., "iPhone15,2"
    const char* platform;     // e.g., "iOS"
} rac_assignment_device_info_t;

/**
 * Make HTTP GET request for model assignments
 * @param endpoint Full endpoint URL with query params
 * @param requires_auth Whether authentication header is required
 * @param out_response Output parameter for response
 * @param user_data User-provided context
 * @return RAC_SUCCESS on success, error code otherwise
 */
typedef rac_result_t (*rac_assignment_http_get_fn)(const char* endpoint, rac_bool_t requires_auth,
                                                   rac_assignment_http_response_t* out_response,
                                                   void* user_data);

/**
 * Get device info for model assignment request
 * @param out_info Output parameter for device info
 * @param user_data User-provided context
 */
typedef void (*rac_assignment_get_device_info_fn)(rac_assignment_device_info_t* out_info,
                                                  void* user_data);

/**
 * @brief Callback structure for model assignment operations
 */
typedef struct rac_assignment_callbacks {
    /** Make HTTP GET request */
    rac_assignment_http_get_fn http_get;

    /** Get device info for request */
    rac_assignment_get_device_info_fn get_device_info;

    /** User data passed to all callbacks */
    void* user_data;
} rac_assignment_callbacks_t;

// =============================================================================
// MODEL ASSIGNMENT API
// =============================================================================

/**
 * @brief Set callbacks for model assignment operations
 *
 * Must be called before any other model assignment functions.
 * Typically called during SDK initialization.
 *
 * @param callbacks Callback structure (copied internally)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t
rac_model_assignment_set_callbacks(const rac_assignment_callbacks_t* callbacks);

/**
 * @brief Fetch model assignments from backend
 *
 * Fetches models assigned to this device from the backend API.
 * Results are cached for cache_timeout_seconds.
 *
 * Business logic:
 * 1. Check cache if not force_refresh
 * 2. Get device info (via callback)
 * 3. Build endpoint URL
 * 4. Make HTTP GET (via callback)
 * 5. Parse JSON response
 * 6. Save models to registry
 * 7. Update cache
 * 8. Emit analytics event
 *
 * @param force_refresh If true, bypass cache
 * @param out_models Output array of model infos (caller must free with rac_model_info_array_free)
 * @param out_count Number of models returned
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_model_assignment_fetch(rac_bool_t force_refresh,
                                                rac_model_info_t*** out_models, size_t* out_count);

/**
 * @brief Get cached model assignments for a specific framework
 *
 * Filters cached models by framework. Does not make network request.
 * Call rac_model_assignment_fetch first to populate cache.
 *
 * @param framework Framework to filter by
 * @param out_models Output array of model infos (caller must free)
 * @param out_count Number of models returned
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_model_assignment_get_by_framework(rac_inference_framework_t framework,
                                                           rac_model_info_t*** out_models,
                                                           size_t* out_count);

/**
 * @brief Get cached model assignments for a specific category
 *
 * Filters cached models by category. Does not make network request.
 * Call rac_model_assignment_fetch first to populate cache.
 *
 * @param category Category to filter by
 * @param out_models Output array of model infos (caller must free)
 * @param out_count Number of models returned
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_model_assignment_get_by_category(rac_model_category_t category,
                                                          rac_model_info_t*** out_models,
                                                          size_t* out_count);

/**
 * @brief Clear model assignment cache
 *
 * Clears the in-memory cache. Next fetch will make network request.
 */
RAC_API void rac_model_assignment_clear_cache(void);

/**
 * @brief Set cache timeout in seconds
 *
 * Default is 3600 (1 hour).
 *
 * @param timeout_seconds Cache timeout in seconds
 */
RAC_API void rac_model_assignment_set_cache_timeout(uint32_t timeout_seconds);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_ASSIGNMENT_H */
