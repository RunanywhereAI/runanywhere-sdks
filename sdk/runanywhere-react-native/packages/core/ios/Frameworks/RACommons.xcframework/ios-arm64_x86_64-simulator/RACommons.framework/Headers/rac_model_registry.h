/**
 * @file rac_model_registry.h
 * @brief Model Information Registry - In-Memory Model Metadata Management
 *
 * C port of Swift's ModelInfoService and ModelInfo structures.
 * Swift Source: Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelInfoService.swift
 * Swift Source: Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/ModelInfo.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_MODEL_REGISTRY_H
#define RAC_MODEL_REGISTRY_H

#include <RACommons/rac_error.h>
#include <RACommons/rac_types.h>
#include <RACommons/rac_model_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES - Uses types from rac_model_types.h
// =============================================================================

// NOTE: All model types (rac_model_category_t, rac_model_format_t,
// rac_inference_framework_t, rac_model_source_t, rac_artifact_type_kind_t,
// rac_model_info_t) are defined in rac_model_types.h

// =============================================================================
// OPAQUE HANDLE
// =============================================================================

/**
 * @brief Opaque handle for model registry instance.
 */
typedef struct rac_model_registry* rac_model_registry_handle_t;

// =============================================================================
// LIFECYCLE API
// =============================================================================

/**
 * @brief Create a model registry instance.
 *
 * @param out_handle Output: Handle to the created registry
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_create(rac_model_registry_handle_t* out_handle);

/**
 * @brief Destroy a model registry instance.
 *
 * @param handle Registry handle
 */
RAC_API void rac_model_registry_destroy(rac_model_registry_handle_t handle);

// =============================================================================
// MODEL INFO API - Mirrors Swift's ModelInfoService
// =============================================================================

/**
 * @brief Save model metadata.
 *
 * Mirrors Swift's ModelInfoService.saveModel(_:).
 *
 * @param handle Registry handle
 * @param model Model info to save
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_save(rac_model_registry_handle_t handle,
                                             const rac_model_info_t* model);

/**
 * @brief Get model metadata by ID.
 *
 * Mirrors Swift's ModelInfoService.getModel(by:).
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @param out_model Output: Model info (owned, must be freed with rac_model_info_free)
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_get(rac_model_registry_handle_t handle,
                                            const char* model_id, rac_model_info_t** out_model);

/**
 * @brief Load all stored models.
 *
 * Mirrors Swift's ModelInfoService.loadStoredModels().
 *
 * @param handle Registry handle
 * @param out_models Output: Array of model info (owned, each must be freed)
 * @param out_count Output: Number of models
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_get_all(rac_model_registry_handle_t handle,
                                                rac_model_info_t*** out_models, size_t* out_count);

/**
 * @brief Load models for specific frameworks.
 *
 * Mirrors Swift's ModelInfoService.loadModels(for:).
 *
 * @param handle Registry handle
 * @param frameworks Array of frameworks to filter by
 * @param framework_count Number of frameworks
 * @param out_models Output: Array of model info (owned, each must be freed)
 * @param out_count Output: Number of models
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_get_by_frameworks(
    rac_model_registry_handle_t handle, const rac_inference_framework_t* frameworks,
    size_t framework_count, rac_model_info_t*** out_models, size_t* out_count);

/**
 * @brief Update model last used date.
 *
 * Mirrors Swift's ModelInfoService.updateLastUsed(for:).
 * Also increments usage count.
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_update_last_used(rac_model_registry_handle_t handle,
                                                         const char* model_id);

/**
 * @brief Remove model metadata.
 *
 * Mirrors Swift's ModelInfoService.removeModel(_:).
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_remove(rac_model_registry_handle_t handle,
                                               const char* model_id);

/**
 * @brief Get downloaded models.
 *
 * Mirrors Swift's ModelInfoService.getDownloadedModels().
 *
 * @param handle Registry handle
 * @param out_models Output: Array of model info (owned, each must be freed)
 * @param out_count Output: Number of models
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_get_downloaded(rac_model_registry_handle_t handle,
                                                       rac_model_info_t*** out_models,
                                                       size_t* out_count);

/**
 * @brief Update download status for a model.
 *
 * Mirrors Swift's ModelInfoService.updateDownloadStatus(for:localPath:).
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @param local_path Path to downloaded model (can be NULL to clear)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_update_download_status(rac_model_registry_handle_t handle,
                                                               const char* model_id,
                                                               const char* local_path);

// =============================================================================
// QUERY HELPERS
// =============================================================================

/**
 * @brief Check if a model is downloaded and available.
 *
 * Mirrors Swift's ModelInfo.isDownloaded computed property.
 *
 * @param model Model info
 * @return RAC_TRUE if downloaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_model_info_is_downloaded(const rac_model_info_t* model);

/**
 * @brief Check if model category requires context length.
 *
 * @param category Model category
 * @return RAC_TRUE if requires context length
 */
RAC_API rac_bool_t rac_model_category_requires_context_length(rac_model_category_t category);

/**
 * @brief Check if model category supports thinking.
 *
 * @param category Model category
 * @return RAC_TRUE if supports thinking
 */
RAC_API rac_bool_t rac_model_category_supports_thinking(rac_model_category_t category);

/**
 * @brief Infer artifact type from URL and format.
 *
 * Mirrors Swift's ModelArtifactType.infer(from:format:).
 *
 * @param url Download URL (can be NULL)
 * @param format Model format
 * @return Inferred artifact type kind
 */
RAC_API rac_artifact_type_kind_t rac_model_infer_artifact_type(const char* url,
                                                               rac_model_format_t format);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Allocate a new model info struct.
 *
 * @return Allocated model info (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t* rac_model_info_alloc(void);

/**
 * @brief Free a model info struct and its contents.
 *
 * @param model Model info to free
 */
RAC_API void rac_model_info_free(rac_model_info_t* model);

/**
 * @brief Free an array of model info structs.
 *
 * @param models Array of model info pointers
 * @param count Number of models
 */
RAC_API void rac_model_info_array_free(rac_model_info_t** models, size_t count);

/**
 * @brief Copy a model info struct.
 *
 * @param model Model info to copy
 * @return Deep copy (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t* rac_model_info_copy(const rac_model_info_t* model);

// =============================================================================
// MODEL DISCOVERY - Scan file system for downloaded models
// =============================================================================

/**
 * @brief Callback to list directory contents
 * @param path Directory path
 * @param out_entries Output: Array of entry names (allocated by callback)
 * @param out_count Output: Number of entries
 * @param user_data User context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_list_directory_fn)(const char* path, char*** out_entries,
                                              size_t* out_count, void* user_data);

/**
 * @brief Callback to free directory entries
 * @param entries Array of entry names
 * @param count Number of entries
 * @param user_data User context
 */
typedef void (*rac_free_directory_entries_fn)(char** entries, size_t count, void* user_data);

/**
 * @brief Callback to check if path is a directory
 * @param path Path to check
 * @param user_data User context
 * @return RAC_TRUE if directory, RAC_FALSE otherwise
 */
typedef rac_bool_t (*rac_is_directory_fn)(const char* path, void* user_data);

/**
 * @brief Callback to check if path exists
 * @param path Path to check
 * @param user_data User context
 * @return RAC_TRUE if exists
 */
typedef rac_bool_t (*rac_path_exists_discovery_fn)(const char* path, void* user_data);

/**
 * @brief Callback to check if file has model extension
 * @param path File path
 * @param framework Expected framework
 * @param user_data User context
 * @return RAC_TRUE if valid model file
 */
typedef rac_bool_t (*rac_is_model_file_fn)(const char* path, rac_inference_framework_t framework,
                                           void* user_data);

/**
 * @brief Callbacks for model discovery file operations
 */
typedef struct {
    rac_list_directory_fn list_directory;
    rac_free_directory_entries_fn free_entries;
    rac_is_directory_fn is_directory;
    rac_path_exists_discovery_fn path_exists;
    rac_is_model_file_fn is_model_file;
    void* user_data;
} rac_discovery_callbacks_t;

/**
 * @brief Discovery result for a single model
 */
typedef struct {
    /** Model ID that was discovered */
    const char* model_id;
    /** Path where model was found */
    const char* local_path;
    /** Framework of the model */
    rac_inference_framework_t framework;
} rac_discovered_model_t;

/**
 * @brief Result of model discovery scan
 */
typedef struct {
    /** Number of models discovered as downloaded */
    size_t discovered_count;
    /** Array of discovered models */
    rac_discovered_model_t* discovered_models;
    /** Number of unregistered model folders found */
    size_t unregistered_count;
} rac_discovery_result_t;

/**
 * @brief Discover downloaded models on the file system.
 *
 * Scans the models directory for each framework, checks if folders
 * contain valid model files, and updates the registry for registered models.
 *
 * @param handle Registry handle
 * @param callbacks Platform file operation callbacks
 * @param out_result Output: Discovery result (caller must call rac_discovery_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_discover_downloaded(
    rac_model_registry_handle_t handle, const rac_discovery_callbacks_t* callbacks,
    rac_discovery_result_t* out_result);

/**
 * @brief Free discovery result
 * @param result Discovery result to free
 */
RAC_API void rac_discovery_result_free(rac_discovery_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_REGISTRY_H */
