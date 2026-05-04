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

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

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
 * @brief Get model metadata by local path.
 *
 * Searches through all registered models and returns the one with matching local_path.
 * This is useful when loading models by path instead of model_id.
 *
 * @param handle Registry handle
 * @param local_path Local path to search for
 * @param out_model Output: Model info (owned, must be freed with rac_model_info_free)
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_get_by_path(rac_model_registry_handle_t handle,
                                                    const char* local_path,
                                                    rac_model_info_t** out_model);

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
// PROTO-BYTE MODEL INFO API
// =============================================================================

/**
 * @brief Save model metadata from serialized runanywhere.v1.ModelInfo bytes.
 *
 * This is the canonical SDK-facing write path for generated proto adapters.
 * The registry converts the proto to its internal C++/C representation and
 * applies the same semantics as rac_model_registry_save().
 *
 * @param handle Registry handle
 * @param proto_bytes Serialized runanywhere.v1.ModelInfo bytes
 * @param proto_size Byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_register_proto(rac_model_registry_handle_t handle,
                                                       const uint8_t* proto_bytes,
                                                       size_t proto_size);

/**
 * @brief Update existing model metadata from serialized runanywhere.v1.ModelInfo bytes.
 *
 * Unlike register_proto, this returns RAC_ERROR_NOT_FOUND when the model id is
 * not already present in the registry.
 *
 * @param handle Registry handle
 * @param proto_bytes Serialized runanywhere.v1.ModelInfo bytes
 * @param proto_size Byte count
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_update_proto(rac_model_registry_handle_t handle,
                                                     const uint8_t* proto_bytes,
                                                     size_t proto_size);

/**
 * @brief Get model metadata as serialized runanywhere.v1.ModelInfo bytes.
 *
 * The caller owns the returned buffer and must free it with
 * rac_model_registry_proto_free().
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @param proto_bytes_out Output: allocated proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_get_proto(rac_model_registry_handle_t handle,
                                                  const char* model_id,
                                                  uint8_t** proto_bytes_out,
                                                  size_t* proto_size_out);

/**
 * @brief List all model metadata as serialized runanywhere.v1.ModelInfoList bytes.
 *
 * The caller owns the returned buffer and must free it with
 * rac_model_registry_proto_free().
 *
 * @param handle Registry handle
 * @param proto_bytes_out Output: allocated proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_list_proto(rac_model_registry_handle_t handle,
                                                   uint8_t** proto_bytes_out,
                                                   size_t* proto_size_out);

/**
 * @brief Query model metadata using serialized runanywhere.v1.ModelQuery bytes.
 *
 * Returns serialized runanywhere.v1.ModelInfoList bytes. The caller owns the
 * returned buffer and must free it with rac_model_registry_proto_free().
 *
 * The current generated ModelQuery schema supports framework/category/format/
 * source, downloaded_only, available_only, max_size_bytes, and search_query
 * filters, plus schema-defined sort_field/sort_order ordering.
 *
 * @param handle Registry handle
 * @param query_proto_bytes Serialized runanywhere.v1.ModelQuery bytes
 * @param query_proto_size Byte count
 * @param proto_bytes_out Output: allocated ModelInfoList proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_query_proto(rac_model_registry_handle_t handle,
                                                    const uint8_t* query_proto_bytes,
                                                    size_t query_proto_size,
                                                    uint8_t** proto_bytes_out,
                                                    size_t* proto_size_out);

/**
 * @brief List downloaded model metadata as serialized runanywhere.v1.ModelInfoList bytes.
 *
 * This is equivalent to a ModelQuery with downloaded_only=true. The caller owns
 * the returned buffer and must free it with rac_model_registry_proto_free().
 *
 * @param handle Registry handle
 * @param proto_bytes_out Output: allocated ModelInfoList proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_list_downloaded_proto(rac_model_registry_handle_t handle,
                                                              uint8_t** proto_bytes_out,
                                                              size_t* proto_size_out);

/**
 * @brief Remove model metadata by id.
 *
 * Provided as part of the proto-byte ABI surface so SDK adapters can stop
 * depending on struct/JSON registry paths for mutations.
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_remove_proto(rac_model_registry_handle_t handle,
                                                     const char* model_id);

/**
 * @brief Free buffers returned by registry proto-byte APIs.
 *
 * @param proto_bytes Buffer to free (may be NULL)
 */
RAC_API void rac_model_registry_proto_free(uint8_t* proto_bytes);

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

// =============================================================================
// REFRESH - Unified cross-SDK registry refresh (T4.9)
// =============================================================================

/**
 * @brief Options for rac_model_registry_refresh().
 *
 * Semantic fields (per task spec):
 *   - include_remote_catalog: RAC_TRUE to fetch the remote model assignment
 *       catalog via rac_model_assignment_fetch(force_refresh=TRUE). Requires
 *       that rac_model_assignment_set_callbacks() has previously been called
 *       (usually at SDK init); otherwise this step no-ops and returns success.
 *   - rescan_local: RAC_TRUE to rescan on-disk model folders and link any
 *       newly-discovered downloads back to registered model entries.
 *       Requires discovery_callbacks to be non-NULL; otherwise this step is
 *       skipped silently.
 *   - prune_orphans: RAC_TRUE to clear local_path on models whose recorded
 *       path no longer exists on disk (detected via
 *       discovery_callbacks->path_exists). Requires discovery_callbacks to
 *       be non-NULL; otherwise this step is skipped silently.
 *
 * discovery_callbacks mirrors rac_model_registry_discover_downloaded's
 * callback struct. It stays optional in the ABI so consumers that only want
 * `include_remote_catalog` don't have to wire platform file-IO stubs.
 */
typedef struct {
    rac_bool_t include_remote_catalog;
    rac_bool_t rescan_local;
    rac_bool_t prune_orphans;
    /** Optional — required only when rescan_local or prune_orphans is set. */
    const rac_discovery_callbacks_t* discovery_callbacks;
} rac_model_registry_refresh_opts_t;

/**
 * @brief Refresh the model registry.
 *
 * Unifies what used to be three separate SDK-specific calls (Kotlin's
 * fetchModelAssignments, Flutter's discoverDownloadedModels, Swift's
 * discoverDownloadedModels) behind a single C ABI. Each step is independent;
 * a failure in one does not abort the others — the first non-success code
 * encountered is returned so callers can still observe errors.
 *
 * @param handle Registry handle (usually rac_get_model_registry()).
 * @param opts   Refresh options (passed by value).
 * @return       RAC_SUCCESS if all requested steps succeeded.
 *               RAC_ERROR_INVALID_ARGUMENT if handle is NULL.
 *               Propagated error code from the first failing step otherwise.
 */
RAC_API rac_result_t rac_model_registry_refresh(rac_model_registry_handle_t handle,
                                                rac_model_registry_refresh_opts_t opts);

// =============================================================================
// FETCH ASSIGNMENTS — Unified cross-SDK entry point (Task 5 / Web WASM)
// =============================================================================

/**
 * @brief Fetch model assignments from the server and populate the registry.
 *
 * Thin wrapper over rac_model_assignment_fetch() that keeps the results in
 * the global model registry.  Intended for the Web/WASM binding
 * (fetchModelAssignments) and any other SDK frontend that needs a single
 * C ABI call instead of the two-step fetch+register pattern.
 *
 * If rac_model_assignment_set_callbacks() has not been called yet the
 * function returns RAC_SUCCESS with zero models so that WASM callers that
 * operate offline don't see an error.
 *
 * @param force_refresh     Pass RAC_TRUE to bypass the cache.
 * @param out_models        Output: caller-owned array (free with
 *                          rac_model_info_array_free).  May be NULL if the
 *                          caller only wants the side-effect of populating the
 *                          registry.
 * @param out_count         Output: number of models.  May be NULL.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_model_registry_fetch_assignments(rac_bool_t force_refresh,
                                                          rac_model_info_t*** out_models,
                                                          size_t* out_count);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_REGISTRY_H */
