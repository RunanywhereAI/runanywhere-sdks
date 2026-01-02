/**
 * @file rac_download.h
 * @brief Download Manager - Model Download Orchestration
 *
 * C port of Swift's DownloadService protocol and related types.
 * Swift Source: Sources/RunAnywhere/Infrastructure/Download/
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 *
 * NOTE: The actual HTTP download is delegated to the platform adapter
 * (Swift/Kotlin/etc). This C layer handles orchestration logic:
 * - Progress tracking
 * - State management
 * - Retry logic
 * - Post-download extraction
 */

#ifndef RAC_DOWNLOAD_H
#define RAC_DOWNLOAD_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES - Mirrors Swift's DownloadState, DownloadStage, DownloadProgress
// =============================================================================

/**
 * @brief Download state enumeration.
 * Mirrors Swift's DownloadState enum.
 */
typedef enum rac_download_state {
    RAC_DOWNLOAD_STATE_PENDING = 0,     /**< Download is pending */
    RAC_DOWNLOAD_STATE_DOWNLOADING = 1, /**< Currently downloading */
    RAC_DOWNLOAD_STATE_EXTRACTING = 2,  /**< Extracting archive contents */
    RAC_DOWNLOAD_STATE_RETRYING = 3,    /**< Retrying after failure */
    RAC_DOWNLOAD_STATE_COMPLETED = 4,   /**< Download completed successfully */
    RAC_DOWNLOAD_STATE_FAILED = 5,      /**< Download failed */
    RAC_DOWNLOAD_STATE_CANCELLED = 6    /**< Download was cancelled */
} rac_download_state_t;

/**
 * @brief Download stage enumeration.
 * Mirrors Swift's DownloadStage enum.
 */
typedef enum rac_download_stage {
    RAC_DOWNLOAD_STAGE_DOWNLOADING = 0, /**< Downloading the file(s) */
    RAC_DOWNLOAD_STAGE_EXTRACTING = 1,  /**< Extracting archive contents */
    RAC_DOWNLOAD_STAGE_VALIDATING = 2,  /**< Validating downloaded files */
    RAC_DOWNLOAD_STAGE_COMPLETED = 3    /**< Download and processing complete */
} rac_download_stage_t;

/**
 * @brief Get display name for download stage.
 *
 * @param stage The download stage
 * @return Display name string (static, do not free)
 */
RAC_API const char* rac_download_stage_display_name(rac_download_stage_t stage);

/**
 * @brief Get progress range for download stage.
 * Download: 0-80%, Extraction: 80-95%, Validation: 95-99%, Completed: 100%
 *
 * @param stage The download stage
 * @param out_start Output: Start of progress range (0.0-1.0)
 * @param out_end Output: End of progress range (0.0-1.0)
 */
RAC_API void rac_download_stage_progress_range(rac_download_stage_t stage, double* out_start,
                                               double* out_end);

/**
 * @brief Download progress information.
 * Mirrors Swift's DownloadProgress struct.
 */
typedef struct rac_download_progress {
    /** Current stage of the download pipeline */
    rac_download_stage_t stage;

    /** Bytes downloaded (for download stage) */
    int64_t bytes_downloaded;

    /** Total bytes to download */
    int64_t total_bytes;

    /** Progress within current stage (0.0 to 1.0) */
    double stage_progress;

    /** Overall progress across all stages (0.0 to 1.0) */
    double overall_progress;

    /** Current state */
    rac_download_state_t state;

    /** Download speed in bytes per second (0 if unknown) */
    double speed;

    /** Estimated time remaining in seconds (-1 if unknown) */
    double estimated_time_remaining;

    /** Retry attempt number (for RETRYING state) */
    int32_t retry_attempt;

    /** Error code (for FAILED state) */
    rac_result_t error_code;

    /** Error message (for FAILED state, can be NULL) */
    const char* error_message;
} rac_download_progress_t;

/**
 * @brief Default download progress values.
 */
static const rac_download_progress_t RAC_DOWNLOAD_PROGRESS_DEFAULT = {
    .stage = RAC_DOWNLOAD_STAGE_DOWNLOADING,
    .bytes_downloaded = 0,
    .total_bytes = 0,
    .stage_progress = 0.0,
    .overall_progress = 0.0,
    .state = RAC_DOWNLOAD_STATE_PENDING,
    .speed = 0.0,
    .estimated_time_remaining = -1.0,
    .retry_attempt = 0,
    .error_code = RAC_SUCCESS,
    .error_message = RAC_NULL};

/**
 * @brief Download task information.
 * Mirrors Swift's DownloadTask struct.
 */
typedef struct rac_download_task {
    /** Unique task ID */
    char* task_id;

    /** Model ID being downloaded */
    char* model_id;

    /** Download URL */
    char* url;

    /** Destination path */
    char* destination_path;

    /** Whether extraction is required */
    rac_bool_t requires_extraction;

    /** Current progress */
    rac_download_progress_t progress;
} rac_download_task_t;

/**
 * @brief Download configuration.
 * Mirrors Swift's DownloadConfiguration struct.
 */
typedef struct rac_download_config {
    /** Maximum concurrent downloads (default: 1) */
    int32_t max_concurrent_downloads;

    /** Request timeout in seconds (default: 60) */
    int32_t request_timeout_seconds;

    /** Maximum retry attempts (default: 3) */
    int32_t max_retry_attempts;

    /** Retry delay in seconds (default: 5) */
    int32_t retry_delay_seconds;

    /** Whether to allow cellular downloads (default: true) */
    rac_bool_t allow_cellular;

    /** Whether to allow downloads on low data mode (default: false) */
    rac_bool_t allow_constrained_network;
} rac_download_config_t;

/**
 * @brief Default download configuration.
 */
static const rac_download_config_t RAC_DOWNLOAD_CONFIG_DEFAULT = {.max_concurrent_downloads = 1,
                                                                  .request_timeout_seconds = 60,
                                                                  .max_retry_attempts = 3,
                                                                  .retry_delay_seconds = 5,
                                                                  .allow_cellular = RAC_TRUE,
                                                                  .allow_constrained_network =
                                                                      RAC_FALSE};

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief Callback for download progress updates.
 * Mirrors Swift's AsyncStream<DownloadProgress> pattern.
 *
 * @param progress Current progress information
 * @param user_data User-provided context
 */
typedef void (*rac_download_progress_callback_fn)(const rac_download_progress_t* progress,
                                                  void* user_data);

/**
 * @brief Callback for download completion.
 *
 * @param task_id The task ID
 * @param result RAC_SUCCESS or error code
 * @param final_path Path to the downloaded/extracted file (NULL on failure)
 * @param user_data User-provided context
 */
typedef void (*rac_download_complete_callback_fn)(const char* task_id, rac_result_t result,
                                                  const char* final_path, void* user_data);

// =============================================================================
// OPAQUE HANDLE
// =============================================================================

/**
 * @brief Opaque handle for download manager instance.
 */
typedef struct rac_download_manager* rac_download_manager_handle_t;

// =============================================================================
// LIFECYCLE API
// =============================================================================

/**
 * @brief Create a download manager instance.
 *
 * @param config Configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created manager
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_create(const rac_download_config_t* config,
                                                 rac_download_manager_handle_t* out_handle);

/**
 * @brief Destroy a download manager instance.
 *
 * @param handle Manager handle
 */
RAC_API void rac_download_manager_destroy(rac_download_manager_handle_t handle);

// =============================================================================
// DOWNLOAD API
// =============================================================================

/**
 * @brief Start downloading a model.
 *
 * Mirrors Swift's DownloadService.downloadModel(_:).
 * The actual HTTP download is performed by the platform adapter.
 *
 * @param handle Manager handle
 * @param model_id Model identifier
 * @param url Download URL
 * @param destination_path Path where the model should be saved
 * @param requires_extraction Whether the download needs to be extracted
 * @param progress_callback Callback for progress updates (can be NULL)
 * @param complete_callback Callback for completion (can be NULL)
 * @param user_data User context passed to callbacks
 * @param out_task_id Output: Task ID for tracking (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_start(rac_download_manager_handle_t handle,
                                                const char* model_id, const char* url,
                                                const char* destination_path,
                                                rac_bool_t requires_extraction,
                                                rac_download_progress_callback_fn progress_callback,
                                                rac_download_complete_callback_fn complete_callback,
                                                void* user_data, char** out_task_id);

/**
 * @brief Cancel a download.
 *
 * Mirrors Swift's DownloadService.cancelDownload(taskId:).
 *
 * @param handle Manager handle
 * @param task_id Task ID to cancel
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_cancel(rac_download_manager_handle_t handle,
                                                 const char* task_id);

/**
 * @brief Pause all active downloads.
 *
 * Mirrors Swift's AlamofireDownloadService.pauseAll().
 *
 * @param handle Manager handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_pause_all(rac_download_manager_handle_t handle);

/**
 * @brief Resume all paused downloads.
 *
 * Mirrors Swift's AlamofireDownloadService.resumeAll().
 *
 * @param handle Manager handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_resume_all(rac_download_manager_handle_t handle);

// =============================================================================
// STATUS API
// =============================================================================

/**
 * @brief Get current progress for a download task.
 *
 * @param handle Manager handle
 * @param task_id Task ID
 * @param out_progress Output: Current progress
 * @return RAC_SUCCESS or error code (RAC_ERROR_NOT_FOUND if task doesn't exist)
 */
RAC_API rac_result_t rac_download_manager_get_progress(rac_download_manager_handle_t handle,
                                                       const char* task_id,
                                                       rac_download_progress_t* out_progress);

/**
 * @brief Get list of active download task IDs.
 *
 * @param handle Manager handle
 * @param out_task_ids Output: Array of task IDs (owned, each must be freed with rac_free)
 * @param out_count Output: Number of tasks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_get_active_tasks(rac_download_manager_handle_t handle,
                                                           char*** out_task_ids, size_t* out_count);

/**
 * @brief Check if the download service is healthy.
 *
 * Mirrors Swift's AlamofireDownloadService.isHealthy().
 *
 * @param handle Manager handle
 * @param out_is_healthy Output: RAC_TRUE if healthy
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_is_healthy(rac_download_manager_handle_t handle,
                                                     rac_bool_t* out_is_healthy);

// =============================================================================
// PROGRESS HELPERS
// =============================================================================

/**
 * @brief Update download progress from HTTP callback.
 *
 * Called by platform adapter when download progress updates.
 *
 * @param handle Manager handle
 * @param task_id Task ID
 * @param bytes_downloaded Bytes downloaded so far
 * @param total_bytes Total bytes to download
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_update_progress(rac_download_manager_handle_t handle,
                                                          const char* task_id,
                                                          int64_t bytes_downloaded,
                                                          int64_t total_bytes);

/**
 * @brief Mark download as completed.
 *
 * Called by platform adapter when HTTP download finishes.
 *
 * @param handle Manager handle
 * @param task_id Task ID
 * @param downloaded_path Path to the downloaded file
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_mark_complete(rac_download_manager_handle_t handle,
                                                        const char* task_id,
                                                        const char* downloaded_path);

/**
 * @brief Mark download as failed.
 *
 * Called by platform adapter when HTTP download fails.
 *
 * @param handle Manager handle
 * @param task_id Task ID
 * @param error_code Error code
 * @param error_message Error message (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_download_manager_mark_failed(rac_download_manager_handle_t handle,
                                                      const char* task_id, rac_result_t error_code,
                                                      const char* error_message);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free a download task.
 *
 * @param task Task to free
 */
RAC_API void rac_download_task_free(rac_download_task_t* task);

/**
 * @brief Free an array of task IDs.
 *
 * @param task_ids Array of task IDs
 * @param count Number of task IDs
 */
RAC_API void rac_download_task_ids_free(char** task_ids, size_t count);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DOWNLOAD_H */
