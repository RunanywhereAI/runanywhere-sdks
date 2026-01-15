/**
 * @file rac_model_strategy.h
 * @brief Model Storage and Download Strategy Protocols
 *
 * Defines callback-based protocols for backend-specific model handling:
 * - Storage Strategy: How models are stored, detected, and validated
 * - Download Strategy: How models are downloaded and post-processed
 *
 * Each backend (ONNX, LlamaCPP, etc.) registers its strategies during
 * backend registration. The SDK uses these strategies for model management.
 *
 * Architecture:
 * - Strategies are registered per-framework via rac_model_strategy_register()
 * - Swift/platform code provides file system operations via callbacks
 * - Business logic (path resolution, validation, extraction) lives in C++
 */

#ifndef RAC_MODEL_STRATEGY_H
#define RAC_MODEL_STRATEGY_H

#include <stddef.h>
#include <stdint.h>

#include <RACommons/rac_error.h>
#include <RACommons/rac_types.h>
#include <RACommons/rac_model_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STORAGE STRATEGY - How models are stored and detected on disk
// =============================================================================

/**
 * @brief Model storage details returned by storage strategy
 */
typedef struct {
    /** Model format detected */
    rac_model_format_t format;

    /** Total size on disk in bytes */
    int64_t total_size;

    /** Number of files in the model directory */
    int file_count;

    /** Primary model file name (e.g., "model.onnx") - owned, must free */
    char* primary_file;

    /** Whether this is a directory-based model (vs single file) */
    rac_bool_t is_directory_based;

    /** Whether the model storage is valid/complete */
    rac_bool_t is_valid;
} rac_model_storage_details_t;

/**
 * @brief Free storage details resources
 */
RAC_API void rac_model_storage_details_free(rac_model_storage_details_t* details);

/**
 * @brief Storage strategy callbacks - implemented by backend
 *
 * These callbacks define how a backend handles model storage detection.
 * Each backend registers these during rac_backend_xxx_register().
 */
typedef struct {
    /**
     * @brief Find the primary model path within a model folder
     *
     * For single-file models: returns path to the model file
     * For directory-based models: returns path to primary model file or directory
     *
     * @param model_id Model identifier
     * @param model_folder Path to the model's folder
     * @param out_path Output buffer for the resolved path
     * @param path_size Size of output buffer
     * @param user_data Backend-specific context
     * @return RAC_SUCCESS if found, RAC_ERROR_NOT_FOUND otherwise
     */
    rac_result_t (*find_model_path)(const char* model_id, const char* model_folder, char* out_path,
                                    size_t path_size, void* user_data);

    /**
     * @brief Detect model format and size in a folder
     *
     * @param model_folder Path to check
     * @param out_details Output storage details
     * @param user_data Backend-specific context
     * @return RAC_SUCCESS if model detected, RAC_ERROR_NOT_FOUND otherwise
     */
    rac_result_t (*detect_model)(const char* model_folder, rac_model_storage_details_t* out_details,
                                 void* user_data);

    /**
     * @brief Validate that model storage is complete and usable
     *
     * @param model_folder Path to the model folder
     * @param user_data Backend-specific context
     * @return RAC_TRUE if valid, RAC_FALSE otherwise
     */
    rac_bool_t (*is_valid_storage)(const char* model_folder, void* user_data);

    /**
     * @brief Get list of expected file patterns for this backend
     *
     * @param out_patterns Output array of pattern strings (owned by backend)
     * @param out_count Number of patterns
     * @param user_data Backend-specific context
     */
    void (*get_expected_patterns)(const char*** out_patterns, size_t* out_count, void* user_data);

    /** Backend-specific context passed to all callbacks */
    void* user_data;

    /** Human-readable name for logging */
    const char* name;
} rac_storage_strategy_t;

// =============================================================================
// DOWNLOAD STRATEGY - How models are downloaded and post-processed
// =============================================================================

/**
 * @brief Model download task configuration (strategy-specific)
 *
 * Note: This is separate from rac_model_download_config_t in rac_download.h which
 * is used for the download manager. This struct is strategy-specific.
 */
typedef struct rac_model_download_config {
    /** Model ID being downloaded */
    const char* model_id;

    /** Source URL for download */
    const char* source_url;

    /** Destination folder path */
    const char* destination_folder;

    /** Expected archive type (or RAC_ARCHIVE_TYPE_NONE for direct files) */
    rac_archive_type_t archive_type;

    /** Expected total size in bytes (0 if unknown) */
    int64_t expected_size;

    /** Whether to resume partial downloads */
    rac_bool_t allow_resume;
} rac_model_download_config_t;

/**
 * @brief Download result information
 */
typedef struct {
    /** Final path to the downloaded/extracted model */
    char* final_path;

    /** Actual size downloaded in bytes */
    int64_t downloaded_size;

    /** Whether extraction was performed */
    rac_bool_t was_extracted;

    /** Number of files after extraction (1 for single file) */
    int file_count;
} rac_download_result_t;

/**
 * @brief Free download result resources
 */
RAC_API void rac_download_result_free(rac_download_result_t* result);

/**
 * @brief Download strategy callbacks - implemented by backend
 *
 * These callbacks define how a backend handles model downloads.
 * Actual HTTP transport is provided by platform (Swift/Kotlin).
 */
typedef struct {
    /**
     * @brief Prepare download - validate and configure
     *
     * Called before download starts to validate config and prepare destination.
     *
     * @param config Download configuration
     * @param user_data Backend-specific context
     * @return RAC_SUCCESS if ready to download
     */
    rac_result_t (*prepare_download)(const rac_model_download_config_t* config, void* user_data);

    /**
     * @brief Get the destination file path for download
     *
     * @param config Download configuration
     * @param out_path Output buffer for destination path
     * @param path_size Size of output buffer
     * @param user_data Backend-specific context
     * @return RAC_SUCCESS on success
     */
    rac_result_t (*get_destination_path)(const rac_model_download_config_t* config, char* out_path,
                                         size_t path_size, void* user_data);

    /**
     * @brief Post-process after download (extraction, validation)
     *
     * Called after download completes. Handles extraction and validation.
     *
     * @param config Original download configuration
     * @param downloaded_path Path to downloaded file
     * @param out_result Output result information
     * @param user_data Backend-specific context
     * @return RAC_SUCCESS if post-processing succeeded
     */
    rac_result_t (*post_process)(const rac_model_download_config_t* config,
                                 const char* downloaded_path, rac_download_result_t* out_result,
                                 void* user_data);

    /**
     * @brief Cleanup failed or cancelled download
     *
     * @param config Download configuration
     * @param user_data Backend-specific context
     */
    void (*cleanup)(const rac_model_download_config_t* config, void* user_data);

    /** Backend-specific context passed to all callbacks */
    void* user_data;

    /** Human-readable name for logging */
    const char* name;
} rac_download_strategy_t;

// =============================================================================
// STRATEGY REGISTRATION API
// =============================================================================

/**
 * @brief Register storage strategy for a framework
 *
 * Called by backends during rac_backend_xxx_register().
 *
 * @param framework Framework this strategy applies to
 * @param strategy Storage strategy callbacks
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_storage_strategy_register(rac_inference_framework_t framework,
                                                   const rac_storage_strategy_t* strategy);

/**
 * @brief Register download strategy for a framework
 *
 * Called by backends during rac_backend_xxx_register().
 *
 * @param framework Framework this strategy applies to
 * @param strategy Download strategy callbacks
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_download_strategy_register(rac_inference_framework_t framework,
                                                    const rac_download_strategy_t* strategy);

/**
 * @brief Unregister strategies for a framework
 *
 * Called by backends during unregistration.
 *
 * @param framework Framework to unregister
 */
RAC_API void rac_model_strategy_unregister(rac_inference_framework_t framework);

// =============================================================================
// STRATEGY LOOKUP API - Used by SDK core
// =============================================================================

/**
 * @brief Get storage strategy for a framework
 *
 * @param framework Framework to query
 * @return Strategy pointer or NULL if not registered
 */
RAC_API const rac_storage_strategy_t* rac_storage_strategy_get(rac_inference_framework_t framework);

/**
 * @brief Get download strategy for a framework
 *
 * @param framework Framework to query
 * @return Strategy pointer or NULL if not registered
 */
RAC_API const rac_download_strategy_t*
rac_download_strategy_get(rac_inference_framework_t framework);

// =============================================================================
// CONVENIENCE API - High-level operations using registered strategies
// =============================================================================

/**
 * @brief Find model path using framework's storage strategy
 *
 * @param framework Inference framework
 * @param model_id Model identifier
 * @param model_folder Model folder path
 * @param out_path Output buffer for resolved path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS if found
 */
RAC_API rac_result_t rac_model_strategy_find_path(rac_inference_framework_t framework,
                                                  const char* model_id, const char* model_folder,
                                                  char* out_path, size_t path_size);

/**
 * @brief Detect model using framework's storage strategy
 *
 * @param framework Inference framework
 * @param model_folder Model folder path
 * @param out_details Output storage details
 * @return RAC_SUCCESS if model detected
 */
RAC_API rac_result_t rac_model_strategy_detect(rac_inference_framework_t framework,
                                               const char* model_folder,
                                               rac_model_storage_details_t* out_details);

/**
 * @brief Validate model storage using framework's strategy
 *
 * @param framework Inference framework
 * @param model_folder Model folder path
 * @return RAC_TRUE if valid
 */
RAC_API rac_bool_t rac_model_strategy_is_valid(rac_inference_framework_t framework,
                                               const char* model_folder);

/**
 * @brief Prepare download using framework's strategy
 *
 * @param framework Inference framework
 * @param config Download configuration
 * @return RAC_SUCCESS if ready
 */
RAC_API rac_result_t rac_model_strategy_prepare_download(rac_inference_framework_t framework,
                                                         const rac_model_download_config_t* config);

/**
 * @brief Get download destination using framework's strategy
 *
 * @param framework Inference framework
 * @param config Download configuration
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_model_strategy_get_download_dest(rac_inference_framework_t framework,
                                                          const rac_model_download_config_t* config,
                                                          char* out_path, size_t path_size);

/**
 * @brief Post-process download using framework's strategy
 *
 * @param framework Inference framework
 * @param config Download configuration
 * @param downloaded_path Path to downloaded file
 * @param out_result Output result
 * @return RAC_SUCCESS if successful
 */
RAC_API rac_result_t rac_model_strategy_post_process(rac_inference_framework_t framework,
                                                     const rac_model_download_config_t* config,
                                                     const char* downloaded_path,
                                                     rac_download_result_t* out_result);

#ifdef __cplusplus
}
#endif

#endif  // RAC_MODEL_STRATEGY_H
