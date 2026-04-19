/**
 * @file rac_storage_analyzer.h
 * @brief Storage Analyzer - Centralized Storage Analysis Logic
 *
 * Business logic for storage analysis lives here in C++.
 * Platform-specific file operations are provided via callbacks.
 *
 * Storage structure: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
 */

#ifndef RAC_STORAGE_ANALYZER_H
#define RAC_STORAGE_ANALYZER_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_model_registry.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// DATA STRUCTURES
// =============================================================================

/**
 * @brief Storage metrics for a single model
 */
typedef struct {
    /** Model ID */
    const char* model_id;

    /** Model name */
    const char* model_name;

    /** Inference framework */
    rac_inference_framework_t framework;

    /** Local path to model */
    const char* local_path;

    /** Actual size on disk in bytes */
    int64_t size_on_disk;

    /** Model format */
    rac_model_format_t format;

    /** Artifact type info */
    rac_model_artifact_info_t artifact_info;
} rac_model_storage_metrics_t;

/**
 * @brief Device storage information
 */
typedef struct {
    /** Total device storage in bytes */
    int64_t total_space;

    /** Free space in bytes */
    int64_t free_space;

    /** Used space in bytes */
    int64_t used_space;
} rac_device_storage_t;

/**
 * @brief App storage information
 */
typedef struct {
    /** Documents directory size in bytes */
    int64_t documents_size;

    /** Cache directory size in bytes */
    int64_t cache_size;

    /** App support directory size in bytes */
    int64_t app_support_size;

    /** Total app storage */
    int64_t total_size;
} rac_app_storage_t;

/**
 * @brief Storage availability result
 */
typedef struct {
    /** Whether storage is available */
    rac_bool_t is_available;

    /** Required space in bytes */
    int64_t required_space;

    /** Available space in bytes */
    int64_t available_space;

    /** Whether there's a warning (low space) */
    rac_bool_t has_warning;

    /** Recommendation message (may be NULL) */
    const char* recommendation;
} rac_storage_availability_t;

/**
 * @brief Overall storage info
 */
typedef struct {
    /** App storage */
    rac_app_storage_t app_storage;

    /** Device storage */
    rac_device_storage_t device_storage;

    /** Array of model storage metrics */
    rac_model_storage_metrics_t* models;

    /** Number of models */
    size_t model_count;

    /** Total size of all models */
    int64_t total_models_size;
} rac_storage_info_t;

// =============================================================================
// PLATFORM CALLBACKS - Swift/Kotlin implements these
// =============================================================================

/**
 * @brief Callback to calculate directory size
 * @param path Directory path
 * @param user_data User context
 * @return Size in bytes
 */
typedef int64_t (*rac_calculate_dir_size_fn)(const char* path, void* user_data);

/**
 * @brief Callback to get file size
 * @param path File path
 * @param user_data User context
 * @return Size in bytes, or -1 if not found
 */
typedef int64_t (*rac_get_file_size_fn)(const char* path, void* user_data);

/**
 * @brief Callback to check if path exists
 * @param path Path to check
 * @param is_directory Output: true if directory
 * @param user_data User context
 * @return true if exists
 */
typedef rac_bool_t (*rac_path_exists_fn)(const char* path, rac_bool_t* is_directory,
                                         void* user_data);

/**
 * @brief Callback to get available disk space
 * @param user_data User context
 * @return Available space in bytes
 */
typedef int64_t (*rac_get_available_space_fn)(void* user_data);

/**
 * @brief Callback to get total disk space
 * @param user_data User context
 * @return Total space in bytes
 */
typedef int64_t (*rac_get_total_space_fn)(void* user_data);

/**
 * @brief Platform callbacks for file operations
 */
typedef struct {
    rac_calculate_dir_size_fn calculate_dir_size;
    rac_get_file_size_fn get_file_size;
    rac_path_exists_fn path_exists;
    rac_get_available_space_fn get_available_space;
    rac_get_total_space_fn get_total_space;
    void* user_data;
} rac_storage_callbacks_t;

// =============================================================================
// STORAGE ANALYZER API
// =============================================================================

/** Opaque handle to storage analyzer */
typedef struct rac_storage_analyzer* rac_storage_analyzer_handle_t;

/**
 * @brief Create a storage analyzer with platform callbacks
 *
 * @param callbacks Platform-specific file operation callbacks
 * @param out_handle Output: Created analyzer handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_storage_analyzer_create(const rac_storage_callbacks_t* callbacks,
                                                 rac_storage_analyzer_handle_t* out_handle);

/**
 * @brief Destroy a storage analyzer
 *
 * @param handle Analyzer handle to destroy
 */
RAC_API void rac_storage_analyzer_destroy(rac_storage_analyzer_handle_t handle);

/**
 * @brief Analyze overall storage
 *
 * Business logic in C++:
 * - Gets models from rac_model_registry
 * - Calculates paths via rac_model_paths
 * - Calls platform callbacks for sizes
 * - Aggregates results
 *
 * @param handle Analyzer handle
 * @param registry_handle Model registry handle
 * @param out_info Output: Storage info (caller must call rac_storage_info_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_storage_analyzer_analyze(rac_storage_analyzer_handle_t handle,
                                                  rac_model_registry_handle_t registry_handle,
                                                  rac_storage_info_t* out_info);

/**
 * @brief Get storage metrics for a specific model
 *
 * @param handle Analyzer handle
 * @param registry_handle Model registry handle
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param out_metrics Output: Model metrics
 * @return RAC_SUCCESS or RAC_ERROR_NOT_FOUND
 */
RAC_API rac_result_t rac_storage_analyzer_get_model_metrics(
    rac_storage_analyzer_handle_t handle, rac_model_registry_handle_t registry_handle,
    const char* model_id, rac_inference_framework_t framework,
    rac_model_storage_metrics_t* out_metrics);

/**
 * @brief Check if storage is available for a download
 *
 * @param handle Analyzer handle
 * @param model_size Size of model to download
 * @param safety_margin Safety margin (e.g., 0.1 for 10% extra)
 * @param out_availability Output: Availability result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_storage_analyzer_check_available(
    rac_storage_analyzer_handle_t handle, int64_t model_size, double safety_margin,
    rac_storage_availability_t* out_availability);

/**
 * @brief Calculate size at a path (file or directory)
 *
 * @param handle Analyzer handle
 * @param path Path to calculate size for
 * @param out_size Output: Size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_storage_analyzer_calculate_size(rac_storage_analyzer_handle_t handle,
                                                         const char* path, int64_t* out_size);

// =============================================================================
// CLEANUP
// =============================================================================

/**
 * @brief Free storage info returned by rac_storage_analyzer_analyze
 *
 * @param info Storage info to free
 */
RAC_API void rac_storage_info_free(rac_storage_info_t* info);

/**
 * @brief Free storage availability result
 *
 * @param availability Availability result to free
 */
RAC_API void rac_storage_availability_free(rac_storage_availability_t* availability);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STORAGE_ANALYZER_H */
