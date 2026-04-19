/**
 * @file rac_file_manager.h
 * @brief File Manager - Centralized File Management Business Logic
 *
 * Consolidates common file management operations that were duplicated
 * across SDKs (Swift, Kotlin, Flutter, React Native):
 * - Directory size calculation (recursive traversal)
 * - Directory structure creation (Models/Cache/Temp/Downloads)
 * - Cache and temp cleanup
 * - Model folder management (create, delete, check existence)
 * - Storage availability checking
 *
 * Platform-specific file I/O is provided via callbacks (rac_file_callbacks_t).
 * C++ handles all business logic; SDKs only provide thin I/O implementations.
 *
 * Uses rac_model_paths for path computation.
 */

#ifndef RAC_FILE_MANAGER_H
#define RAC_FILE_MANAGER_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_model_types.h"
#include "rac_storage_analyzer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// PLATFORM I/O CALLBACKS
// =============================================================================

/**
 * @brief Platform-specific file I/O callbacks.
 *
 * SDKs implement these thin wrappers around native file operations.
 * C++ business logic calls these for all file system access.
 */
typedef struct {
    /**
     * Create a directory (optionally recursive).
     * @param path Directory path to create
     * @param recursive If non-zero, create intermediate directories
     * @param user_data Platform context
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*create_directory)(const char* path, int recursive, void* user_data);

    /**
     * Delete a file or directory.
     * @param path Path to delete
     * @param recursive If non-zero, delete directory contents recursively
     * @param user_data Platform context
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*delete_path)(const char* path, int recursive, void* user_data);

    /**
     * List directory contents (entry names only, not full paths).
     * @param path Directory path
     * @param out_entries Output: Array of entry name strings (allocated by callback)
     * @param out_count Output: Number of entries
     * @param user_data Platform context
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*list_directory)(const char* path, char*** out_entries, size_t* out_count,
                                   void* user_data);

    /**
     * Free directory entries returned by list_directory.
     * @param entries Array of entry names
     * @param count Number of entries
     * @param user_data Platform context
     */
    void (*free_entries)(char** entries, size_t count, void* user_data);

    /**
     * Check if a path exists.
     * @param path Path to check
     * @param out_is_directory Output: non-zero if path is a directory (can be NULL)
     * @param user_data Platform context
     * @return RAC_TRUE if exists, RAC_FALSE otherwise
     */
    rac_bool_t (*path_exists)(const char* path, rac_bool_t* out_is_directory, void* user_data);

    /**
     * Get file size in bytes.
     * @param path File path
     * @param user_data Platform context
     * @return File size in bytes, or -1 on error
     */
    int64_t (*get_file_size)(const char* path, void* user_data);

    /**
     * Get available disk space in bytes.
     * @param user_data Platform context
     * @return Available space in bytes, or -1 on error
     */
    int64_t (*get_available_space)(void* user_data);

    /**
     * Get total disk space in bytes.
     * @param user_data Platform context
     * @return Total space in bytes, or -1 on error
     */
    int64_t (*get_total_space)(void* user_data);

    /** Platform-specific context passed to all callbacks */
    void* user_data;
} rac_file_callbacks_t;

// =============================================================================
// DATA STRUCTURES
// =============================================================================

/**
 * @brief Combined storage information.
 *
 * Aggregates device storage, app storage (models/cache/temp), and
 * computed totals. Replaces per-SDK storage info structs.
 */
typedef struct {
    /** Total device storage in bytes */
    int64_t device_total;
    /** Free device storage in bytes */
    int64_t device_free;
    /** Total models directory size in bytes */
    int64_t models_size;
    /** Cache directory size in bytes */
    int64_t cache_size;
    /** Temp directory size in bytes */
    int64_t temp_size;
    /** Total app storage (models + cache + temp) */
    int64_t total_app_size;
} rac_file_manager_storage_info_t;

// =============================================================================
// DIRECTORY STRUCTURE
// =============================================================================

/**
 * @brief Create the standard directory structure under the base directory.
 *
 * Creates: Models/, Cache/, Temp/, Downloads/ under {base_dir}/RunAnywhere/
 * Uses rac_model_paths for path computation.
 *
 * @param cb Platform I/O callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_create_directory_structure(const rac_file_callbacks_t* cb);

// =============================================================================
// MODEL FOLDER MANAGEMENT
// =============================================================================

/**
 * @brief Create a model folder and return its path.
 *
 * Creates: {base_dir}/RunAnywhere/Models/{framework}/{modelId}/
 *
 * @param cb Platform I/O callbacks
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param out_path Output buffer for the created folder path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_create_model_folder(const rac_file_callbacks_t* cb,
                                                           const char* model_id,
                                                           rac_inference_framework_t framework,
                                                           char* out_path, size_t path_size);

/**
 * @brief Check if a model folder exists and optionally if it has contents.
 *
 * @param cb Platform I/O callbacks
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param out_exists Output: RAC_TRUE if folder exists
 * @param out_has_contents Output: RAC_TRUE if folder has files (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_model_folder_exists(const rac_file_callbacks_t* cb,
                                                           const char* model_id,
                                                           rac_inference_framework_t framework,
                                                           rac_bool_t* out_exists,
                                                           rac_bool_t* out_has_contents);

/**
 * @brief Delete a model folder recursively.
 *
 * @param cb Platform I/O callbacks
 * @param model_id Model identifier
 * @param framework Inference framework
 * @return RAC_SUCCESS, or RAC_ERROR_FILE_NOT_FOUND if folder doesn't exist
 */
RAC_API rac_result_t rac_file_manager_delete_model(const rac_file_callbacks_t* cb,
                                                    const char* model_id,
                                                    rac_inference_framework_t framework);

// =============================================================================
// DIRECTORY SIZE CALCULATION
// =============================================================================

/**
 * @brief Calculate directory size recursively.
 *
 * @param cb Platform I/O callbacks
 * @param path Directory path to measure
 * @param out_size Output: Total size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_calculate_dir_size(const rac_file_callbacks_t* cb,
                                                          const char* path, int64_t* out_size);

/**
 * @brief Get total models directory storage used.
 *
 * @param cb Platform I/O callbacks
 * @param out_size Output: Total models size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_models_storage_used(const rac_file_callbacks_t* cb,
                                                           int64_t* out_size);

// =============================================================================
// CACHE & TEMP MANAGEMENT
// =============================================================================

/**
 * @brief Clear the cache directory.
 *
 * @param cb Platform I/O callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_clear_cache(const rac_file_callbacks_t* cb);

/**
 * @brief Clear the temp directory.
 *
 * @param cb Platform I/O callbacks
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_clear_temp(const rac_file_callbacks_t* cb);

/**
 * @brief Get the cache directory size.
 *
 * @param cb Platform I/O callbacks
 * @param out_size Output: Cache size in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_cache_size(const rac_file_callbacks_t* cb,
                                                  int64_t* out_size);

// =============================================================================
// STORAGE INFO
// =============================================================================

/**
 * @brief Get combined storage information.
 *
 * @param cb Platform I/O callbacks
 * @param out_info Output: Storage information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_get_storage_info(const rac_file_callbacks_t* cb,
                                                        rac_file_manager_storage_info_t* out_info);

/**
 * @brief Check storage availability for a download.
 *
 * @param cb Platform I/O callbacks
 * @param required_bytes Space needed in bytes
 * @param out_availability Output: Availability result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_check_storage(
    const rac_file_callbacks_t* cb, int64_t required_bytes,
    rac_storage_availability_t* out_availability);

// =============================================================================
// DIRECTORY CLEARING (INTERNAL HELPER)
// =============================================================================

/**
 * @brief Clear all contents of a directory (delete + recreate).
 *
 * @param cb Platform I/O callbacks
 * @param path Directory path to clear
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_file_manager_clear_directory(const rac_file_callbacks_t* cb,
                                                       const char* path);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FILE_MANAGER_H */
