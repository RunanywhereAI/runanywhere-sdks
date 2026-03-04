/**
 * @file rac_download_orchestrator.h
 * @brief Download Orchestrator - High-Level Model Download Lifecycle Management
 *
 * Consolidates download business logic from all platform SDKs into C++.
 * Handles the full download lifecycle: path resolution, extraction detection,
 * HTTP download (via platform adapter), post-download extraction, model path
 * finding, registry updates, and archive cleanup.
 *
 * HTTP transport remains platform-specific via rac_platform_adapter_t.http_download.
 * This layer handles ALL orchestration logic so each SDK reduces to:
 *   1. Register http_download callback
 *   2. Call rac_download_orchestrate()
 *   3. Wrap result in SDK types
 *
 * Depends on:
 *  - rac_download.h (download manager state machine, progress tracking)
 *  - rac_platform_adapter.h (http_download callback for HTTP transport)
 *  - rac_extraction.h (rac_extract_archive_native for archive extraction)
 *  - rac_model_paths.h (destination path resolution)
 *  - rac_model_types.h (model types, archive types, frameworks)
 */

#ifndef RAC_DOWNLOAD_ORCHESTRATOR_H
#define RAC_DOWNLOAD_ORCHESTRATOR_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/download/rac_download.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// DOWNLOAD ORCHESTRATION - Full Lifecycle Model Download
// =============================================================================

/**
 * @brief Orchestrate a single-file model download with full lifecycle management.
 *
 * This is the main entry point for downloading a model. It handles:
 *  1. Compute destination folder via rac_model_paths_get_model_folder()
 *  2. Detect if extraction is needed via rac_archive_type_from_path()
 *  3. Download to temp path if extraction needed, else download to model folder
 *  4. Invoke platform http_download via rac_http_download()
 *  5. On HTTP completion: extract if needed, find model path, cleanup archive
 *  6. Update download manager state (DOWNLOADING → EXTRACTING → COMPLETED)
 *  7. Invoke user callbacks with final model path
 *
 * @param dm_handle Download manager handle (for state tracking)
 * @param model_id Model identifier (used for folder naming and registry)
 * @param download_url URL to download from
 * @param framework Inference framework (determines storage directory)
 * @param format Model format (determines file extension and path finding)
 * @param archive_structure Archive structure hint (used for post-extraction path finding)
 * @param progress_callback Progress updates across all stages (can be NULL)
 * @param complete_callback Called when entire lifecycle completes or fails
 * @param user_data User context passed to callbacks
 * @param out_task_id Output: Task ID for tracking/cancellation (owned, free with rac_free)
 * @return RAC_SUCCESS if download started, error code if failed to start
 */
RAC_API rac_result_t rac_download_orchestrate(
    rac_download_manager_handle_t dm_handle, const char* model_id, const char* download_url,
    rac_inference_framework_t framework, rac_model_format_t format,
    rac_archive_structure_t archive_structure,
    rac_download_progress_callback_fn progress_callback,
    rac_download_complete_callback_fn complete_callback, void* user_data, char** out_task_id);

/**
 * @brief Orchestrate a multi-file model download (e.g., VLM with companion files).
 *
 * Downloads multiple files sequentially into the same model folder.
 * Progress is distributed across all files proportionally.
 * Extraction is applied to each file individually if needed.
 *
 * @param dm_handle Download manager handle (for state tracking)
 * @param model_id Model identifier
 * @param files Array of file descriptors (relative_path, destination_path, is_required)
 * @param file_count Number of files to download
 * @param base_download_url Base URL — file relative_path is appended to this
 * @param framework Inference framework
 * @param format Model format
 * @param progress_callback Progress updates across all files and stages (can be NULL)
 * @param complete_callback Called when all files complete or any required file fails
 * @param user_data User context passed to callbacks
 * @param out_task_id Output: Task ID for tracking/cancellation (owned, free with rac_free)
 * @return RAC_SUCCESS if download started, error code if failed to start
 */
RAC_API rac_result_t rac_download_orchestrate_multi(
    rac_download_manager_handle_t dm_handle, const char* model_id,
    const rac_model_file_descriptor_t* files, size_t file_count, const char* base_download_url,
    rac_inference_framework_t framework, rac_model_format_t format,
    rac_download_progress_callback_fn progress_callback,
    rac_download_complete_callback_fn complete_callback, void* user_data, char** out_task_id);

// =============================================================================
// POST-EXTRACTION MODEL PATH FINDING
// =============================================================================

/**
 * @brief Find the actual model path after extraction.
 *
 * Consolidates duplicated Swift/Kotlin logic for scanning extracted directories:
 *  - Finds .gguf, .onnx, .ort, .bin files
 *  - Handles nested directories (e.g., sherpa-onnx archives with subdirectory)
 *  - Handles single-file-nested pattern (model file inside one subdirectory)
 *  - Returns the directory itself for directory-based models (ONNX)
 *
 * Uses POSIX opendir/readdir for cross-platform compatibility (iOS/Android/Linux/macOS).
 *
 * @param extracted_dir Directory where archive was extracted
 * @param structure Archive structure hint (SINGLE_FILE_NESTED, NESTED_DIRECTORY, etc.)
 * @param framework Inference framework (used to determine if directory-based)
 * @param format Model format (used to determine expected file extensions)
 * @param out_path Output buffer for the found model path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS if model path found, RAC_ERROR_NOT_FOUND if no model file found
 */
RAC_API rac_result_t rac_find_model_path_after_extraction(
    const char* extracted_dir, rac_archive_structure_t structure,
    rac_inference_framework_t framework, rac_model_format_t format, char* out_path,
    size_t path_size);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * @brief Compute the download destination path for a model.
 *
 * If extraction is needed: returns a temp path in the downloads directory.
 * If no extraction: returns the final model folder path.
 *
 * @param model_id Model identifier
 * @param download_url URL to download (used for archive detection and extension)
 * @param framework Inference framework
 * @param format Model format
 * @param out_path Output buffer for destination path
 * @param path_size Size of output buffer
 * @param out_needs_extraction Output: RAC_TRUE if download needs extraction
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_compute_destination(const char* model_id,
                                                       const char* download_url,
                                                       rac_inference_framework_t framework,
                                                       rac_model_format_t format, char* out_path,
                                                       size_t path_size,
                                                       rac_bool_t* out_needs_extraction);

/**
 * @brief Check if a download URL requires extraction.
 *
 * Convenience wrapper around rac_archive_type_from_path().
 *
 * @param download_url URL to check
 * @return RAC_TRUE if URL points to an archive that needs extraction
 */
RAC_API rac_bool_t rac_download_requires_extraction(const char* download_url);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DOWNLOAD_ORCHESTRATOR_H */
