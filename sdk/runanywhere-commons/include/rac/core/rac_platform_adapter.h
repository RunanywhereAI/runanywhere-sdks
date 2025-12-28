/**
 * @file rac_platform_adapter.h
 * @brief RunAnywhere Commons - Platform Adapter Interface
 *
 * Platform adapter provides callbacks for platform-specific operations.
 * Swift/Kotlin SDK implements these callbacks and passes them during init.
 *
 * NOTE: HTTP networking is delegated to the platform layer (Swift/Kotlin).
 * The C++ layer only handles orchestration logic.
 */

#ifndef RAC_PLATFORM_ADAPTER_H
#define RAC_PLATFORM_ADAPTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CALLBACK TYPES (defined outside struct for C compatibility)
// =============================================================================

/**
 * HTTP download progress callback type.
 * @param bytes_downloaded Bytes downloaded so far
 * @param total_bytes Total bytes to download (0 if unknown)
 * @param callback_user_data Context passed to http_download
 */
typedef void (*rac_http_progress_callback_fn)(int64_t bytes_downloaded, int64_t total_bytes,
                                              void* callback_user_data);

/**
 * HTTP download completion callback type.
 * @param result RAC_SUCCESS or error code
 * @param downloaded_path Path to downloaded file (NULL on failure)
 * @param callback_user_data Context passed to http_download
 */
typedef void (*rac_http_complete_callback_fn)(rac_result_t result, const char* downloaded_path,
                                              void* callback_user_data);

/**
 * Archive extraction progress callback type.
 * @param files_extracted Number of files extracted so far
 * @param total_files Total files to extract
 * @param callback_user_data Context passed to extract_archive
 */
typedef void (*rac_extract_progress_callback_fn)(int32_t files_extracted, int32_t total_files,
                                                 void* callback_user_data);

// =============================================================================
// PLATFORM ADAPTER STRUCTURE
// =============================================================================

/**
 * Platform adapter structure.
 *
 * Implements platform-specific operations via callbacks.
 * The SDK layer (Swift/Kotlin) provides these implementations.
 */
typedef struct rac_platform_adapter {
    // -------------------------------------------------------------------------
    // File System Operations
    // -------------------------------------------------------------------------

    /**
     * Check if a file exists.
     * @param path File path
     * @param user_data Platform context
     * @return RAC_TRUE if file exists, RAC_FALSE otherwise
     */
    rac_bool_t (*file_exists)(const char* path, void* user_data);

    /**
     * Read file contents.
     * @param path File path
     * @param out_data Output buffer (caller must free with rac_free)
     * @param out_size Output file size
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_read)(const char* path, void** out_data, size_t* out_size, void* user_data);

    /**
     * Write file contents.
     * @param path File path
     * @param data Data to write
     * @param size Data size
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data);

    /**
     * Delete a file.
     * @param path File path
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*file_delete)(const char* path, void* user_data);

    // -------------------------------------------------------------------------
    // Secure Storage (Keychain/KeyStore)
    // -------------------------------------------------------------------------

    /**
     * Get a value from secure storage.
     * @param key Key name
     * @param out_value Output value (caller must free with rac_free)
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, RAC_ERROR_FILE_NOT_FOUND if not found
     */
    rac_result_t (*secure_get)(const char* key, char** out_value, void* user_data);

    /**
     * Set a value in secure storage.
     * @param key Key name
     * @param value Value to store
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*secure_set)(const char* key, const char* value, void* user_data);

    /**
     * Delete a value from secure storage.
     * @param key Key name
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*secure_delete)(const char* key, void* user_data);

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------

    /**
     * Log a message.
     * @param level Log level
     * @param category Log category (e.g., "ModuleRegistry")
     * @param message Log message
     * @param user_data Platform context
     */
    void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data);

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------

    /**
     * Get current time in milliseconds since Unix epoch.
     * @param user_data Platform context
     * @return Current time in milliseconds
     */
    int64_t (*now_ms)(void* user_data);

    // -------------------------------------------------------------------------
    // Memory Info
    // -------------------------------------------------------------------------

    /**
     * Get memory information.
     * @param out_info Output memory info structure
     * @param user_data Platform context
     * @return RAC_SUCCESS on success, error code on failure
     */
    rac_result_t (*get_memory_info)(rac_memory_info_t* out_info, void* user_data);

    // -------------------------------------------------------------------------
    // HTTP Download (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Start an HTTP download.
     * Can be NULL - download orchestration in C++ will call back to Swift/Kotlin.
     *
     * @param url URL to download from
     * @param destination_path Where to save the downloaded file
     * @param progress_callback Progress callback (can be NULL)
     * @param complete_callback Completion callback
     * @param callback_user_data User context for callbacks
     * @param out_task_id Output: Task ID for cancellation (owned, must be freed)
     * @param user_data Platform context
     * @return RAC_SUCCESS if download started, error code otherwise
     */
    rac_result_t (*http_download)(const char* url, const char* destination_path,
                                  rac_http_progress_callback_fn progress_callback,
                                  rac_http_complete_callback_fn complete_callback,
                                  void* callback_user_data, char** out_task_id, void* user_data);

    /**
     * Cancel an HTTP download.
     * Can be NULL.
     *
     * @param task_id Task ID returned from http_download
     * @param user_data Platform context
     * @return RAC_SUCCESS if cancelled, error code otherwise
     */
    rac_result_t (*http_download_cancel)(const char* task_id, void* user_data);

    // -------------------------------------------------------------------------
    // Archive Extraction (Optional - can be NULL)
    // -------------------------------------------------------------------------

    /**
     * Extract an archive (ZIP or TAR).
     * Can be NULL - extraction will be handled by Swift/Kotlin.
     *
     * @param archive_path Path to the archive
     * @param destination_dir Where to extract files
     * @param progress_callback Progress callback (can be NULL)
     * @param callback_user_data User context for callback
     * @param user_data Platform context
     * @return RAC_SUCCESS if extracted, error code otherwise
     */
    rac_result_t (*extract_archive)(const char* archive_path, const char* destination_dir,
                                    rac_extract_progress_callback_fn progress_callback,
                                    void* callback_user_data, void* user_data);

    // -------------------------------------------------------------------------
    // User Data
    // -------------------------------------------------------------------------

    /** Platform-specific context passed to all callbacks */
    void* user_data;

} rac_platform_adapter_t;

// =============================================================================
// PLATFORM ADAPTER API
// =============================================================================

/**
 * Sets the platform adapter.
 *
 * Called during rac_init() - the adapter pointer must remain valid
 * until rac_shutdown() is called.
 *
 * @param adapter Platform adapter (must not be NULL)
 * @return RAC_SUCCESS on success, error code on failure
 */
RAC_API rac_result_t rac_set_platform_adapter(const rac_platform_adapter_t* adapter);

/**
 * Gets the current platform adapter.
 *
 * @return The current adapter, or NULL if not set
 */
RAC_API const rac_platform_adapter_t* rac_get_platform_adapter(void);

// =============================================================================
// CONVENIENCE FUNCTIONS (use platform adapter internally)
// =============================================================================

/**
 * Log a message using the platform adapter.
 * @param level Log level
 * @param category Category string
 * @param message Message string
 */
RAC_API void rac_log(rac_log_level_t level, const char* category, const char* message);

/**
 * Get current time in milliseconds.
 * @return Current time in milliseconds since epoch
 */
RAC_API int64_t rac_get_current_time_ms(void);

/**
 * Start an HTTP download using the platform adapter.
 * Returns RAC_ERROR_NOT_SUPPORTED if http_download callback is NULL.
 *
 * @param url URL to download
 * @param destination_path Where to save
 * @param progress_callback Progress callback (can be NULL)
 * @param complete_callback Completion callback
 * @param callback_user_data User data for callbacks
 * @param out_task_id Output: Task ID (owned, must be freed)
 * @return RAC_SUCCESS if started, error code otherwise
 */
RAC_API rac_result_t rac_http_download(const char* url, const char* destination_path,
                                       rac_http_progress_callback_fn progress_callback,
                                       rac_http_complete_callback_fn complete_callback,
                                       void* callback_user_data, char** out_task_id);

/**
 * Cancel an HTTP download.
 * Returns RAC_ERROR_NOT_SUPPORTED if http_download_cancel callback is NULL.
 *
 * @param task_id Task ID to cancel
 * @return RAC_SUCCESS if cancelled, error code otherwise
 */
RAC_API rac_result_t rac_http_download_cancel(const char* task_id);

/**
 * Extract an archive using the platform adapter.
 * Returns RAC_ERROR_NOT_SUPPORTED if extract_archive callback is NULL.
 *
 * @param archive_path Path to archive
 * @param destination_dir Where to extract
 * @param progress_callback Progress callback (can be NULL)
 * @param callback_user_data User data for callback
 * @return RAC_SUCCESS if extracted, error code otherwise
 */
RAC_API rac_result_t rac_extract_archive(const char* archive_path, const char* destination_dir,
                                         rac_extract_progress_callback_fn progress_callback,
                                         void* callback_user_data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLATFORM_ADAPTER_H */
