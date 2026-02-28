/**
 * @file rac_extraction.h
 * @brief RunAnywhere Commons - Native Archive Extraction
 *
 * Native archive extraction using libarchive.
 * Supports ZIP, TAR.GZ, TAR.BZ2, TAR.XZ with streaming extraction
 * (constant memory usage regardless of archive size).
 *
 * Security features:
 * - Zip-slip protection (path traversal prevention)
 * - macOS resource fork skipping (._files, __MACOSX/)
 * - Symbolic link safety (contained within destination)
 * - Archive type auto-detection via magic bytes
 */

#ifndef RAC_EXTRACTION_H
#define RAC_EXTRACTION_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXTRACTION OPTIONS
// =============================================================================

/**
 * @brief Options for archive extraction.
 */
typedef struct rac_extraction_options {
    /** Skip macOS resource forks (._ files, __MACOSX/ directories).
     *  Default: RAC_TRUE */
    rac_bool_t skip_macos_resources;

    /** Skip symbolic links entirely.
     *  Default: RAC_FALSE (symlinks are created if safe) */
    rac_bool_t skip_symlinks;

    /** Archive type hint. RAC_ARCHIVE_TYPE_NONE = auto-detect from magic bytes.
     *  Default: RAC_ARCHIVE_TYPE_NONE */
    rac_archive_type_t archive_type_hint;
} rac_extraction_options_t;

/**
 * @brief Default extraction options.
 */
static const rac_extraction_options_t RAC_EXTRACTION_OPTIONS_DEFAULT = {
    RAC_TRUE,             /* skip_macos_resources */
    RAC_FALSE,            /* skip_symlinks */
    RAC_ARCHIVE_TYPE_NONE /* archive_type_hint */
};

// =============================================================================
// EXTRACTION RESULT
// =============================================================================

/**
 * @brief Result of an extraction operation.
 */
typedef struct rac_extraction_result {
    /** Number of files extracted */
    int32_t files_extracted;

    /** Number of directories created */
    int32_t directories_created;

    /** Total bytes written to disk */
    int64_t bytes_extracted;

    /** Number of entries skipped (resource forks, unsafe paths) */
    int32_t entries_skipped;
} rac_extraction_result_t;

// =============================================================================
// EXTRACTION PROGRESS CALLBACK
// =============================================================================

/**
 * @brief Progress callback for extraction.
 *
 * @param files_extracted Number of files extracted so far
 * @param total_files Total files in archive (0 if unknown for streaming formats)
 * @param bytes_extracted Bytes written to disk so far
 * @param user_data User-provided context
 */
typedef void (*rac_extraction_progress_fn)(int32_t files_extracted, int32_t total_files,
                                           int64_t bytes_extracted, void* user_data);

// =============================================================================
// EXTRACTION API
// =============================================================================

/**
 * @brief Extract an archive using native libarchive.
 *
 * Performs streaming extraction with constant memory usage.
 * Auto-detects archive format from magic bytes if archive_type_hint
 * is RAC_ARCHIVE_TYPE_NONE.
 *
 * @param archive_path Path to the archive file
 * @param destination_dir Directory to extract into (created if needed)
 * @param options Extraction options (NULL for defaults)
 * @param progress_callback Progress callback (can be NULL)
 * @param user_data Context for progress callback
 * @param out_result Output: extraction statistics (can be NULL)
 * @return RAC_SUCCESS on success, error code on failure
 *
 * Error codes:
 *  - RAC_ERROR_EXTRACTION_FAILED: General extraction error
 *  - RAC_ERROR_UNSUPPORTED_ARCHIVE: Unrecognized archive format
 *  - RAC_ERROR_FILE_NOT_FOUND: Archive file does not exist
 *  - RAC_ERROR_NULL_POINTER: archive_path or destination_dir is NULL
 */
RAC_API rac_result_t rac_extract_archive_native(const char* archive_path,
                                                 const char* destination_dir,
                                                 const rac_extraction_options_t* options,
                                                 rac_extraction_progress_fn progress_callback,
                                                 void* user_data,
                                                 rac_extraction_result_t* out_result);

/**
 * @brief Detect archive type from file magic bytes.
 *
 * Reads the first few bytes of the file to determine the archive format.
 * More reliable than file extension detection.
 *
 * @param file_path Path to the file
 * @param out_type Output: detected archive type
 * @return RAC_TRUE if archive type detected, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_detect_archive_type(const char* file_path, rac_archive_type_t* out_type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_EXTRACTION_H */
