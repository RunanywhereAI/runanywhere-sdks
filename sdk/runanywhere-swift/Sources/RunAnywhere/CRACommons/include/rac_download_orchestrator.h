/**
 * @file rac_download_orchestrator.h
 * @brief Download Orchestrator - High-Level Model Download Lifecycle Management
 *
 * Consolidates download business logic from all platform SDKs into C++.
 * Handles the full download lifecycle: path resolution, extraction detection,
 * HTTP download (via platform-registered transport), post-download extraction,
 * model path finding, registry updates, and archive cleanup.
 *
 * HTTP transport is registered by each SDK via rac_http_transport_register().
 * This layer exposes the proto-byte download workflow ABI; each SDK invokes:
 *   1. rac_download_plan_proto() to validate the model + plan files
 *   2. rac_download_start_proto() to launch the worker
 *   3. rac_download_cancel_proto / _resume_proto / _progress_poll_proto /
 *      _cleanup_terminal_tasks_proto for lifecycle management
 *
 * Depends on:
 *  - rac_download.h (download manager state machine, progress tracking)
 *  - rac_http_transport.h (SDK-registered HTTP transport)
 *  - rac_extraction.h (rac_extract_archive_native for archive extraction)
 *  - rac_model_paths.h (destination path resolution)
 *  - rac_model_types.h (model types, archive types, frameworks)
 */

#ifndef RAC_DOWNLOAD_ORCHESTRATOR_H
#define RAC_DOWNLOAD_ORCHESTRATOR_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_proto_buffer.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// PROTO-BYTE DOWNLOAD WORKFLOW ABI

typedef void (*rac_download_proto_progress_callback_fn)(const uint8_t* proto_bytes,
                                                        size_t proto_size,
                                                        void* user_data);

RAC_API rac_result_t rac_download_set_progress_proto_callback(
    rac_download_proto_progress_callback_fn callback, void* user_data);

RAC_API rac_result_t rac_download_plan_proto(const uint8_t* request_bytes,
                                             size_t request_size,
                                             rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_download_start_proto(const uint8_t* request_bytes,
                                              size_t request_size,
                                              rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_download_cancel_proto(const uint8_t* request_bytes,
                                               size_t request_size,
                                               rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_download_resume_proto(const uint8_t* request_bytes,
                                               size_t request_size,
                                               rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_download_progress_poll_proto(const uint8_t* request_bytes,
                                                      size_t request_size,
                                                      rac_proto_buffer_t* out_result);

// POST-EXTRACTION MODEL PATH FINDING

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
RAC_API rac_result_t rac_find_model_path_after_extraction(const char* extracted_dir,
                                                          rac_archive_structure_t structure,
                                                          rac_inference_framework_t framework,
                                                          rac_model_format_t format, char* out_path,
                                                          size_t path_size);

// UTILITY FUNCTIONS

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
RAC_API rac_result_t rac_download_compute_destination(
    const char* model_id, const char* download_url, rac_inference_framework_t framework,
    rac_model_format_t format, char* out_path, size_t path_size, rac_bool_t* out_needs_extraction);

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
