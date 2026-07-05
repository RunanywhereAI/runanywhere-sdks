/**
 * @file rac_model_registry.h
 * @brief Model Information Registry - In-Memory Model Metadata Management
 *
 * C port of Swift's ModelInfoService and ModelInfo structures.
 * Swift Source:
 * Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelInfoService.swift
 * Swift Source:
 * Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/ModelInfo.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_MODEL_REGISTRY_H
#define RAC_MODEL_REGISTRY_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_model_types.h"
#include "rac_proto_buffer.h"
#include "rac_types.h"

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
typedef struct rac_model_registry *rac_model_registry_handle_t;

// =============================================================================
// LIFECYCLE API
// =============================================================================

/**
 * @brief Create a model registry instance.
 *
 * @param out_handle Output: Handle to the created registry
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t
rac_model_registry_create(rac_model_registry_handle_t *out_handle);

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
                                             const rac_model_info_t *model);

/**
 * @brief Get model metadata by ID.
 *
 * Mirrors Swift's ModelInfoService.getModel(by:).
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @param out_model Output: Model info (owned, must be freed with
 * rac_model_info_free)
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_get(rac_model_registry_handle_t handle,
                                            const char *model_id,
                                            rac_model_info_t **out_model);

/**
 * @brief Get model metadata by local path.
 *
 * Searches through all registered models and returns the one with matching
 * local_path. This is useful when loading models by path instead of model_id.
 *
 * @param handle Registry handle
 * @param local_path Local path to search for
 * @param out_model Output: Model info (owned, must be freed with
 * rac_model_info_free)
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t rac_model_registry_get_by_path(
    rac_model_registry_handle_t handle, const char *local_path,
    rac_model_info_t **out_model);

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
RAC_API rac_result_t
rac_model_registry_get_all(rac_model_registry_handle_t handle,
                           rac_model_info_t ***out_models, size_t *out_count);

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
    rac_model_registry_handle_t handle,
    const rac_inference_framework_t *frameworks, size_t framework_count,
    rac_model_info_t ***out_models, size_t *out_count);

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
RAC_API rac_result_t rac_model_registry_update_last_used(
    rac_model_registry_handle_t handle, const char *model_id);

/**
 * @brief Remove model metadata.
 *
 * Mirrors Swift's ModelInfoService.removeModel(_:).
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_remove(
    rac_model_registry_handle_t handle, const char *model_id);

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
RAC_API rac_result_t rac_model_registry_get_downloaded(
    rac_model_registry_handle_t handle, rac_model_info_t ***out_models,
    size_t *out_count);

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
RAC_API rac_result_t rac_model_registry_update_download_status(
    rac_model_registry_handle_t handle, const char *model_id,
    const char *local_path);

/**
 * @brief Persist the durable model-folder manifest sidecar for a model.
 *
 * Best-effort and idempotent: serializes the registry entry (volatile
 * absolute paths stripped) into
 * `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/` under the filename
 * from rac_model_folder_manifest_filename(), creating the folder if needed.
 * The download orchestrator calls this when a download STARTS so a process
 * death mid-download still leaves a restorable identity on disk — cold-launch
 * and lookup-miss restore then re-register the entry as incomplete and a
 * pull/download by id resumes from the partial bytes. Also refreshed
 * automatically on download completion.
 *
 * @param handle Registry handle
 * @param model_id Model identifier
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND when the id is unknown, or an
 *         error code when the folder cannot be created.
 */
RAC_API rac_result_t rac_model_registry_persist_folder_manifest(
    rac_model_registry_handle_t handle, const char *model_id);

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
 * Merge-not-replace on existing entries: when the model_id is already in the
 * registry, runtime fields the caller did not set (local_path, is_downloaded,
 * checksum_sha256, expected_files, multi_file per-file local_path) are
 * preserved from the existing snapshot. Callers reseeding a curated catalog
 * on app launch therefore retain previous download progress without needing
 * an example-app skip-if-present workaround. To force a clean reset, callers
 * must explicitly populate the desired field on the incoming ModelInfo (the
 * "absent" check is field-presence-based via the proto `has_*` accessors).
 *
 * @param handle Registry handle
 * @param proto_bytes Serialized runanywhere.v1.ModelInfo bytes
 * @param proto_size Byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_register_proto(
    rac_model_registry_handle_t handle, const uint8_t *proto_bytes,
    size_t proto_size);

/**
 * @brief Update existing model metadata from serialized
 * runanywhere.v1.ModelInfo bytes.
 *
 * Unlike register_proto, this returns RAC_ERROR_NOT_FOUND when the model id is
 * not already present in the registry.
 *
 * @param handle Registry handle
 * @param proto_bytes Serialized runanywhere.v1.ModelInfo bytes
 * @param proto_size Byte count
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND, or other error code
 */
RAC_API rac_result_t
rac_model_registry_update_proto(rac_model_registry_handle_t handle,
                                const uint8_t *proto_bytes, size_t proto_size);

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
RAC_API rac_result_t rac_model_registry_get_proto(
    rac_model_registry_handle_t handle, const char *model_id,
    uint8_t **proto_bytes_out, size_t *proto_size_out);

/**
 * @brief List all model metadata as serialized runanywhere.v1.ModelInfoList
 * bytes.
 *
 * The caller owns the returned buffer and must free it with
 * rac_model_registry_proto_free().
 *
 * @param handle Registry handle
 * @param proto_bytes_out Output: allocated proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_list_proto(
    rac_model_registry_handle_t handle, uint8_t **proto_bytes_out,
    size_t *proto_size_out);

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
RAC_API rac_result_t rac_model_registry_query_proto(
    rac_model_registry_handle_t handle, const uint8_t *query_proto_bytes,
    size_t query_proto_size, uint8_t **proto_bytes_out, size_t *proto_size_out);

/**
 * @brief List downloaded model metadata as serialized
 * runanywhere.v1.ModelInfoList bytes.
 *
 * This is equivalent to a ModelQuery with downloaded_only=true. The caller owns
 * the returned buffer and must free it with rac_model_registry_proto_free().
 *
 * @param handle Registry handle
 * @param proto_bytes_out Output: allocated ModelInfoList proto bytes
 * @param proto_size_out Output: byte count
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_registry_list_downloaded_proto(
    rac_model_registry_handle_t handle, uint8_t **proto_bytes_out,
    size_t *proto_size_out);

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
RAC_API rac_result_t rac_model_registry_remove_proto(
    rac_model_registry_handle_t handle, const char *model_id);

/**
 * @brief Free buffers returned by registry proto-byte APIs.
 *
 * @param proto_bytes Buffer to free (may be NULL)
 */
RAC_API void rac_model_registry_proto_free(uint8_t *proto_bytes);

// =============================================================================
// CANONICAL PROTO-BUFFER MODEL REGISTRY API
// =============================================================================

/**
 * @brief Save serialized runanywhere.v1.ModelInfo and return the saved
 * ModelInfo.
 *
 * Output uses the canonical rac_proto_buffer_t ownership/error convention.
 */
RAC_API rac_result_t rac_model_registry_register_proto_buffer(
    rac_model_registry_handle_t handle, const uint8_t *proto_bytes,
    size_t proto_size, rac_proto_buffer_t *out_model);

/**
 * @brief Update an existing runanywhere.v1.ModelInfo and return the saved
 * ModelInfo.
 *
 * Missing model ids return RAC_ERROR_NOT_FOUND in out_model->status.
 */
RAC_API rac_result_t rac_model_registry_update_proto_buffer(
    rac_model_registry_handle_t handle, const uint8_t *proto_bytes,
    size_t proto_size, rac_proto_buffer_t *out_model);

/**
 * @brief Get a model as serialized runanywhere.v1.ModelInfo bytes.
 */
RAC_API rac_result_t rac_model_registry_get_proto_buffer(
    rac_model_registry_handle_t handle, const char *model_id,
    rac_proto_buffer_t *out_model);

/**
 * @brief List models as serialized runanywhere.v1.ModelInfoList bytes.
 */
RAC_API rac_result_t rac_model_registry_list_proto_buffer(
    rac_model_registry_handle_t handle, rac_proto_buffer_t *out_models);

/**
 * @brief Query models using serialized runanywhere.v1.ModelQuery bytes.
 */
RAC_API rac_result_t rac_model_registry_query_proto_buffer(
    rac_model_registry_handle_t handle, const uint8_t *query_proto_bytes,
    size_t query_proto_size, rac_proto_buffer_t *out_models);

/**
 * @brief List downloaded models as serialized runanywhere.v1.ModelInfoList
 * bytes.
 */
RAC_API rac_result_t rac_model_registry_list_downloaded_proto_buffer(
    rac_model_registry_handle_t handle, rac_proto_buffer_t *out_models);

/**
 * @brief Remove model metadata and return serialized
 * runanywhere.v1.ModelDeleteResult bytes.
 *
 * File deletion remains platform-owned; this function only unregisters the
 * portable registry row.
 */
RAC_API rac_result_t rac_model_registry_remove_proto_buffer(
    rac_model_registry_handle_t handle, const char *model_id,
    rac_proto_buffer_t *out_result);

/**
 * @brief Handle serialized runanywhere.v1.ModelGetRequest bytes.
 *
 * Returns serialized runanywhere.v1.ModelGetResult bytes in out_result.
 */
RAC_API rac_result_t rac_model_registry_get_model_proto(
    rac_model_registry_handle_t handle, const uint8_t *request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t *out_result);

/**
 * @brief Handle serialized runanywhere.v1.ModelListRequest bytes.
 *
 * Returns serialized runanywhere.v1.ModelListResult bytes in out_result.
 */
RAC_API rac_result_t rac_model_registry_list_models_proto(
    rac_model_registry_handle_t handle, const uint8_t *request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t *out_result);

/**
 * @brief Handle serialized runanywhere.v1.ModelImportRequest bytes.
 *
 * The input source_path must already be a stable platform-normalized path.
 * Commons records registry metadata only; it does not copy files or acquire OS
 * handles.
 */
RAC_API rac_result_t rac_model_registry_import_proto(
    rac_model_registry_handle_t handle, const uint8_t *request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t *out_result);

/**
 * @brief Handle serialized runanywhere.v1.ModelDiscoveryRequest bytes.
 *
 * Platform adapters own filesystem traversal. This portable entry point shapes
 * discovery results from registry state and normalized local_path values.
 */
RAC_API rac_result_t rac_model_registry_discover_proto(
    rac_model_registry_handle_t handle, const uint8_t *request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t *out_result);

/**
 * @brief Handle serialized runanywhere.v1.ModelRegistryRefreshRequest bytes.
 *
 * Returns serialized runanywhere.v1.ModelRegistryRefreshResult bytes.
 */
RAC_API rac_result_t rac_model_registry_refresh_proto(
    rac_model_registry_handle_t handle, const uint8_t *request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t *out_result);

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
RAC_API rac_bool_t rac_model_info_is_downloaded(const rac_model_info_t *model);

// NOTE: rac_model_category_requires_context_length() and
// rac_model_category_supports_thinking() are declared in rac_model_types.h
// (the canonical home for rac_model_category_t helpers) and intentionally
// not re-declared here to avoid double-declaration drift.

/**
 * @brief Infer artifact type from URL and format.
 *
 * Mirrors Swift's ModelArtifactType.infer(from:format:).
 *
 * @param url Download URL (can be NULL)
 * @param format Model format
 * @return Inferred artifact type kind
 */
RAC_API rac_artifact_type_kind_t
rac_model_infer_artifact_type(const char *url, rac_model_format_t format);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Allocate a new model info struct.
 *
 * @return Allocated model info (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t *rac_model_info_alloc(void);

/**
 * @brief Free a model info struct and its contents.
 *
 * @param model Model info to free
 */
RAC_API void rac_model_info_free(rac_model_info_t *model);

/**
 * @brief Free an array of model info structs.
 *
 * @param models Array of model info pointers
 * @param count Number of models
 */
RAC_API void rac_model_info_array_free(rac_model_info_t **models, size_t count);

/**
 * @brief Copy a model info struct.
 *
 * @param model Model info to copy
 * @return Deep copy (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t *rac_model_info_copy(const rac_model_info_t *model);

// =============================================================================
// REFRESH — proto entry point only
// =============================================================================
//
// The struct-opts `rac_model_registry_refresh` entry point and its
// `rac_model_registry_refresh_opts_t` / `rac_discovery_callbacks_t` types were
// removed. Refresh is now driven exclusively through the proto API
// (`rac_model_registry_refresh_proto`, declared further below in the PROTO
// section): callers serialize a `ModelRegistryRefreshRequest`
// (include_remote_catalog / rescan_local / prune_orphans / optional query) and
// read back a `ModelRegistryRefreshResult`. Filesystem reconciliation runs via
// the platform adapter's `file_list_directory` slot, not a discovery-callback
// struct.

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
RAC_API rac_result_t rac_model_registry_fetch_assignments(
    rac_bool_t force_refresh, rac_model_info_t ***out_models,
    size_t *out_count);

/**
 * @brief Fetch model assignments via the proto-byte ABI.
 *
 * Wraps rac_model_registry_fetch_assignments() so SDK bridges (RN, Web,
 * Kotlin JNI) can replace the per-SDK JSON shims with one canonical
 * proto-byte call. The implementation calls
 * rac_model_assignment_fetch() under the hood (so the platform adapter
 * still owns HTTP transport), then serializes the result into a
 * runanywhere.v1.ModelRegistryFetchAssignmentsResult message containing
 * the populated ModelInfoList plus error/timing metadata.
 *
 * Offline / pre-init behavior matches
 * rac_model_registry_fetch_assignments(): if the assignment callbacks
 * have not been registered yet, success is returned with zero models
 * and an empty ModelInfoList — equivalent to the WASM offline path.
 *
 * @param request_bytes Serialized
 *                      runanywhere.v1.ModelRegistryFetchAssignmentsRequest
 *                      bytes. May be empty (size==0); commons treats it
 *                      as a default request (force_refresh=false,
 *                      device_id="").
 * @param request_size  Byte count.
 * @param out_result    Receives serialized
 *                      runanywhere.v1.ModelRegistryFetchAssignmentsResult
 *                      bytes on success or an error envelope on failure.
 * @return RAC_SUCCESS or a negative rac_result_t.
 */
RAC_API rac_result_t rac_model_registry_fetch_assignments_proto(
    const uint8_t *request_bytes, size_t request_size,
    rac_proto_buffer_t *out_result);

// =============================================================================
// URL → ModelFormat / ArtifactType INFERENCE (proto-byte ABI)
//
// Canonical commons-owned heuristic shared by every SDK. Replaces the
// per-SDK Dart `protoModelFormatFromPath` / `withInferredArtifact` and
// Kotlin `detectFormatFromUrl` / `inferArtifactFields` helpers.
// =============================================================================

/**
 * @brief Infer a ModelFormat from a portable URL/file-path string.
 *
 * Consumes serialized runanywhere.v1.ModelFormatFromUrlRequest bytes and
 * returns serialized runanywhere.v1.ModelFormatFromUrlResult bytes. Only
 * the trailing file-suffix is inspected; no network or filesystem access.
 *
 * @param request_bytes Serialized ModelFormatFromUrlRequest (may be empty).
 * @param request_size  Byte count.
 * @param out_result    Receives serialized ModelFormatFromUrlResult bytes.
 * @return RAC_SUCCESS on success (including unknown-format), or a
 *         negative rac_result_t on encode/decode failure.
 */
RAC_API rac_result_t rac_model_format_from_url_proto(
    const uint8_t *request_bytes, size_t request_size,
    rac_proto_buffer_t *out_result);

/**
 * @brief Infer a ModelArtifactType from a portable URL/file-path string.
 *
 * Consumes serialized runanywhere.v1.ArtifactInferFromUrlRequest bytes and
 * returns serialized runanywhere.v1.ArtifactInferFromUrlResult bytes.
 * Recognizes the ".tar.gz" / ".tgz" / ".tar.bz2" / ".tbz2" / ".tar.xz" /
 * ".txz" / ".zip" archive suffixes and defaults to SINGLE_FILE otherwise.
 *
 * @param request_bytes Serialized ArtifactInferFromUrlRequest (may be empty).
 * @param request_size  Byte count.
 * @param out_result    Receives serialized ArtifactInferFromUrlResult bytes.
 * @return RAC_SUCCESS on success, or a negative rac_result_t on
 *         encode/decode failure.
 */
RAC_API rac_result_t rac_artifact_infer_from_url_proto(
    const uint8_t *request_bytes, size_t request_size,
    rac_proto_buffer_t *out_result);

// =============================================================================
// REGISTER MODEL FROM URL — single-call URL+name+framework → save
//
// Composes the canonical RAModelInfo factory (rac_model_info_make_proto)
// with the existing registry persistence path so SDKs replace the ~60 LOC
// build-and-save body of Swift's RunAnywhere.registerModel(...) (and the
// equivalent Kotlin/Flutter/RN/Web glue) with a single ABI call. Output is
// the saved ModelInfo bytes — same shape as
// rac_model_registry_register_proto_buffer.
// =============================================================================

/**
 * @brief Build a fully-populated ModelInfo from a URL+name+framework tuple and
 *        persist it to the global model registry.
 *
 * Consumes serialized runanywhere.v1.RegisterModelFromUrlRequest bytes and
 * returns serialized runanywhere.v1.ModelInfo bytes (the saved entry) in
 * out_proto. Internally:
 *
 *   1. Translates RegisterModelFromUrlRequest → ModelInfoMakeRequest.
 *   2. Calls rac_model_info_make_proto() to default the 18 ModelInfo fields
 *      (id from URL, name fallback, format/framework/category detection,
 *      artifact inference, source mark, timestamps, …).
 *   3. Saves the resulting ModelInfo through
 *      rac_model_registry_register_proto_buffer() on the global registry
 *      (rac_get_model_registry()), which round-trips through the same
 *      conversion + save path used by every other SDK adapter.
 *
 * On encode/decode failure the error envelope is set on out_proto via the
 * canonical rac_proto_buffer_set_error() convention.
 *
 * @param in_request_bytes Serialized RegisterModelFromUrlRequest bytes (may be
 *                         empty — treated as a default-zeroed request, which
 *                         results in a model with empty url/id/name and the
 *                         standard make() defaults).
 * @param in_size          Byte count.
 * @param out_proto        Receives serialized runanywhere.v1.ModelInfo bytes
 *                         on success or an error status on failure.
 * @return RAC_SUCCESS on success, or a negative rac_result_t on failure.
 */
RAC_API rac_result_t rac_register_model_from_url_proto(
    const uint8_t *in_request_bytes, size_t in_size,
    rac_proto_buffer_t *out_proto);

/**
 * Register a multi-file model from a RegisterMultiFileModelRequest.
 *
 * Builds a ModelInfo carrying a MultiFileArtifact (one ModelFileDescriptor per
 * file) plus the caller-supplied capability fields, and persists it through the
 * same registry save path. Replaces the hand-built MultiFileArtifact ModelInfo
 * every SDK assembles today.
 *
 * @param in_request_bytes Serialized RegisterMultiFileModelRequest bytes.
 * @param in_size          Byte count.
 * @param out_proto        Receives serialized runanywhere.v1.ModelInfo bytes on
 *                         success or an error status on failure.
 * @return RAC_SUCCESS on success, or a negative rac_result_t on failure.
 */
RAC_API rac_result_t rac_register_multi_file_model_proto(
    const uint8_t *in_request_bytes, size_t in_size,
    rac_proto_buffer_t *out_proto);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_REGISTRY_H */
