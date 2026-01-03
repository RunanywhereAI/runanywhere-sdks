/**
 * @file rac_lifecycle.h
 * @brief RunAnywhere Commons - Lifecycle Management API
 *
 * C port of Swift's ManagedLifecycle.swift from:
 * Sources/RunAnywhere/Core/Capabilities/ManagedLifecycle.swift
 *
 * Provides unified lifecycle management with integrated event tracking.
 * Tracks lifecycle events (load, unload) via EventPublisher.
 */

#ifndef RAC_LIFECYCLE_H
#define RAC_LIFECYCLE_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES - Mirrors Swift's CapabilityLoadingState
// =============================================================================

/**
 * @brief Capability loading state
 *
 * Mirrors Swift's CapabilityLoadingState enum.
 */
typedef enum rac_lifecycle_state {
    RAC_LIFECYCLE_STATE_IDLE = 0,    /**< Not loaded */
    RAC_LIFECYCLE_STATE_LOADING = 1, /**< Currently loading */
    RAC_LIFECYCLE_STATE_LOADED = 2,  /**< Successfully loaded */
    RAC_LIFECYCLE_STATE_FAILED = 3   /**< Load failed */
} rac_lifecycle_state_t;

/**
 * @brief Resource type for lifecycle tracking
 *
 * Mirrors Swift's CapabilityResourceType enum.
 */
typedef enum rac_resource_type {
    RAC_RESOURCE_TYPE_LLM_MODEL = 0,
    RAC_RESOURCE_TYPE_STT_MODEL = 1,
    RAC_RESOURCE_TYPE_TTS_VOICE = 2,
    RAC_RESOURCE_TYPE_VAD_MODEL = 3,
    RAC_RESOURCE_TYPE_DIARIZATION_MODEL = 4
} rac_resource_type_t;

/**
 * @brief Lifecycle metrics
 *
 * Mirrors Swift's ModelLifecycleMetrics struct.
 */
typedef struct rac_lifecycle_metrics {
    /** Total lifecycle events */
    int32_t total_events;

    /** Start time (ms since epoch) */
    int64_t start_time_ms;

    /** Last event time (ms since epoch, 0 if none) */
    int64_t last_event_time_ms;

    /** Total load attempts */
    int32_t total_loads;

    /** Successful loads */
    int32_t successful_loads;

    /** Failed loads */
    int32_t failed_loads;

    /** Average load time in milliseconds */
    double average_load_time_ms;

    /** Total unloads */
    int32_t total_unloads;
} rac_lifecycle_metrics_t;

/**
 * @brief Lifecycle configuration
 */
typedef struct rac_lifecycle_config {
    /** Resource type for event tracking */
    rac_resource_type_t resource_type;

    /** Logger category (can be NULL for default) */
    const char* logger_category;

    /** User data for callbacks */
    void* user_data;
} rac_lifecycle_config_t;

/**
 * @brief Service creation callback
 *
 * Called by the lifecycle manager to create a service for a given model ID.
 *
 * @param model_id The model ID to load
 * @param user_data User-provided context
 * @param out_service Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_lifecycle_create_service_fn)(const char* model_id, void* user_data,
                                                        rac_handle_t* out_service);

/**
 * @brief Service destroy callback
 *
 * Called by the lifecycle manager to destroy a service.
 *
 * @param service Handle to the service to destroy
 * @param user_data User-provided context
 */
typedef void (*rac_lifecycle_destroy_service_fn)(rac_handle_t service, void* user_data);

// =============================================================================
// LIFECYCLE API - Mirrors Swift's ManagedLifecycle
// =============================================================================

/**
 * @brief Create a lifecycle manager
 *
 * @param config Lifecycle configuration
 * @param create_fn Service creation callback
 * @param destroy_fn Service destruction callback (can be NULL)
 * @param out_handle Output: Handle to the lifecycle manager
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_lifecycle_create(const rac_lifecycle_config_t* config,
                                          rac_lifecycle_create_service_fn create_fn,
                                          rac_lifecycle_destroy_service_fn destroy_fn,
                                          rac_handle_t* out_handle);

/**
 * @brief Load a model with automatic event tracking
 *
 * Mirrors Swift's ManagedLifecycle.load(_:)
 * If already loaded with same ID, skips duplicate load.
 *
 * @param handle Lifecycle manager handle
 * @param model_id Model ID to load
 * @param out_service Output: Handle to the loaded service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_lifecycle_load(rac_handle_t handle, const char* model_id,
                                        rac_handle_t* out_service);

/**
 * @brief Unload the currently loaded model
 *
 * Mirrors Swift's ManagedLifecycle.unload()
 *
 * @param handle Lifecycle manager handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_lifecycle_unload(rac_handle_t handle);

/**
 * @brief Reset all state
 *
 * Mirrors Swift's ManagedLifecycle.reset()
 *
 * @param handle Lifecycle manager handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_lifecycle_reset(rac_handle_t handle);

/**
 * @brief Get current lifecycle state
 *
 * Mirrors Swift's ManagedLifecycle.state
 *
 * @param handle Lifecycle manager handle
 * @return Current state
 */
RAC_API rac_lifecycle_state_t rac_lifecycle_get_state(rac_handle_t handle);

/**
 * @brief Check if a model is loaded
 *
 * Mirrors Swift's ManagedLifecycle.isLoaded
 *
 * @param handle Lifecycle manager handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_lifecycle_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * Mirrors Swift's ManagedLifecycle.currentModelId
 *
 * @param handle Lifecycle manager handle
 * @return Current model ID (may be NULL if not loaded)
 */
RAC_API const char* rac_lifecycle_get_model_id(rac_handle_t handle);

/**
 * @brief Get current service handle
 *
 * Mirrors Swift's ManagedLifecycle.currentService
 *
 * @param handle Lifecycle manager handle
 * @return Current service handle (may be NULL if not loaded)
 */
RAC_API rac_handle_t rac_lifecycle_get_service(rac_handle_t handle);

/**
 * @brief Require service or return error
 *
 * Mirrors Swift's ManagedLifecycle.requireService()
 *
 * @param handle Lifecycle manager handle
 * @param out_service Output: Service handle
 * @return RAC_SUCCESS or RAC_ERROR_NOT_INITIALIZED if not loaded
 */
RAC_API rac_result_t rac_lifecycle_require_service(rac_handle_t handle, rac_handle_t* out_service);

/**
 * @brief Track an operation error
 *
 * Mirrors Swift's ManagedLifecycle.trackOperationError(_:operation:)
 *
 * @param handle Lifecycle manager handle
 * @param error_code Error code
 * @param operation Operation name
 */
RAC_API void rac_lifecycle_track_error(rac_handle_t handle, rac_result_t error_code,
                                       const char* operation);

/**
 * @brief Get lifecycle metrics
 *
 * Mirrors Swift's ManagedLifecycle.getLifecycleMetrics()
 *
 * @param handle Lifecycle manager handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_lifecycle_get_metrics(rac_handle_t handle,
                                               rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy a lifecycle manager
 *
 * @param handle Lifecycle manager handle
 */
RAC_API void rac_lifecycle_destroy(rac_handle_t handle);

// =============================================================================
// CONVENIENCE STATE HELPERS
// =============================================================================

/**
 * @brief Get state name string
 *
 * @param state Lifecycle state
 * @return Human-readable state name
 */
RAC_API const char* rac_lifecycle_state_name(rac_lifecycle_state_t state);

/**
 * @brief Get resource type name string
 *
 * @param type Resource type
 * @return Human-readable resource type name
 */
RAC_API const char* rac_resource_type_name(rac_resource_type_t type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LIFECYCLE_H */
