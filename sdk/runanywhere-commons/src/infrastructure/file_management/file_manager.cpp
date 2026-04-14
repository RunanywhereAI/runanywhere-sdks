/**
 * @file file_manager.cpp
 * @brief File Manager - Centralized File Management Business Logic
 *
 * Consolidates duplicated file management logic from Swift, Kotlin, Flutter, and RN SDKs.
 * All file I/O is performed via platform callbacks (rac_file_callbacks_t).
 * Business logic (recursive traversal, path computation, threshold checks) lives here.
 */

#include "rac/infrastructure/file_management/rac_file_manager.h"

#include <cstring>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

static const char* LOG_CATEGORY = "FileManager";

/** Storage warning threshold: 1 GB */
static const int64_t STORAGE_WARNING_THRESHOLD = 1024LL * 1024LL * 1024LL;

/**
 * Validate that required callbacks are present.
 */
static rac_result_t validate_callbacks(const rac_file_callbacks_t* cb) {
    if (cb == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (cb->create_directory == nullptr || cb->delete_path == nullptr ||
        cb->list_directory == nullptr || cb->free_entries == nullptr ||
        cb->path_exists == nullptr || cb->get_file_size == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

/**
 * Build a full path by joining parent and child with '/'.
 */
static std::string join_path(const char* parent, const char* child) {
    std::string result(parent);
    if (!result.empty() && result.back() != '/') {
        result += '/';
    }
    result += child;
    return result;
}

/**
 * Recursive directory size calculation.
 * This is the core logic duplicated across all SDKs.
 *
 * Algorithm (identical in Swift/Kotlin/Flutter/RN):
 *   1. List directory entries
 *   2. For each entry: if directory → recurse, else → add file size
 */
static rac_result_t calculate_dir_size_recursive(const rac_file_callbacks_t* cb, const char* path,
                                                  int64_t* out_size) {
    char** entries = nullptr;
    size_t count = 0;

    rac_result_t result = cb->list_directory(path, &entries, &count, cb->user_data);
    if (RAC_FAILED(result)) {
        // Directory doesn't exist or can't be listed — treat as 0 size
        *out_size = 0;
        return RAC_SUCCESS;
    }

    int64_t total = 0;

    for (size_t i = 0; i < count; i++) {
        // Skip . and ..
        if (std::strcmp(entries[i], ".") == 0 || std::strcmp(entries[i], "..") == 0) {
            continue;
        }

        std::string entry_path = join_path(path, entries[i]);
        rac_bool_t is_directory = RAC_FALSE;
        rac_bool_t exists = cb->path_exists(entry_path.c_str(), &is_directory, cb->user_data);

        if (exists == RAC_TRUE) {
            if (is_directory == RAC_TRUE) {
                int64_t sub_size = 0;
                calculate_dir_size_recursive(cb, entry_path.c_str(), &sub_size);
                total += sub_size;
            } else {
                int64_t file_size = cb->get_file_size(entry_path.c_str(), cb->user_data);
                if (file_size > 0) {
                    total += file_size;
                }
            }
        }
    }

    cb->free_entries(entries, count, cb->user_data);
    *out_size = total;
    return RAC_SUCCESS;
}

/**
 * Clear a directory: delete all contents, then recreate the empty directory.
 */
static rac_result_t clear_directory_impl(const rac_file_callbacks_t* cb, const char* path) {
    rac_bool_t is_dir = RAC_FALSE;
    rac_bool_t exists = cb->path_exists(path, &is_dir, cb->user_data);

    if (exists == RAC_TRUE && is_dir == RAC_TRUE) {
        // Delete the directory and all contents
        rac_result_t result = cb->delete_path(path, 1 /* recursive */, cb->user_data);
        if (RAC_FAILED(result)) {
            return result;
        }
    }

    // Recreate the empty directory
    return cb->create_directory(path, 1 /* recursive */, cb->user_data);
}

// =============================================================================
// DIRECTORY STRUCTURE
// =============================================================================

rac_result_t rac_file_manager_create_directory_structure(const rac_file_callbacks_t* cb) {
    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Get paths from rac_model_paths
    char models_dir[1024];
    char cache_dir[1024];
    char temp_dir[1024];
    char downloads_dir[1024];

    result = rac_model_paths_get_models_directory(models_dir, sizeof(models_dir));
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to get models directory path");
        return result;
    }

    result = rac_model_paths_get_cache_directory(cache_dir, sizeof(cache_dir));
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to get cache directory path");
        return result;
    }

    result = rac_model_paths_get_temp_directory(temp_dir, sizeof(temp_dir));
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to get temp directory path");
        return result;
    }

    result = rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir));
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to get downloads directory path");
        return result;
    }

    // Create each directory
    const char* dirs[] = {models_dir, cache_dir, temp_dir, downloads_dir};
    for (const char* dir : dirs) {
        result = cb->create_directory(dir, 1 /* recursive */, cb->user_data);
        if (RAC_FAILED(result)) {
            RAC_LOG_ERROR(LOG_CATEGORY, "Failed to create directory");
            return result;
        }
    }

    RAC_LOG_INFO(LOG_CATEGORY, "Directory structure created successfully");
    return RAC_SUCCESS;
}

// =============================================================================
// MODEL FOLDER MANAGEMENT
// =============================================================================

rac_result_t rac_file_manager_create_model_folder(const rac_file_callbacks_t* cb,
                                                   const char* model_id,
                                                   rac_inference_framework_t framework,
                                                   char* out_path, size_t path_size) {
    if (model_id == nullptr || out_path == nullptr || path_size == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Get model folder path from rac_model_paths
    result = rac_model_paths_get_model_folder(model_id, framework, out_path, path_size);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Create the directory
    result = cb->create_directory(out_path, 1 /* recursive */, cb->user_data);
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to create model folder");
        return result;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_file_manager_model_folder_exists(const rac_file_callbacks_t* cb,
                                                   const char* model_id,
                                                   rac_inference_framework_t framework,
                                                   rac_bool_t* out_exists,
                                                   rac_bool_t* out_has_contents) {
    if (model_id == nullptr || out_exists == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Get model folder path
    char folder_path[1024];
    result = rac_model_paths_get_model_folder(model_id, framework, folder_path, sizeof(folder_path));
    if (RAC_FAILED(result)) {
        *out_exists = RAC_FALSE;
        if (out_has_contents != nullptr) {
            *out_has_contents = RAC_FALSE;
        }
        return RAC_SUCCESS;
    }

    // Check existence
    rac_bool_t is_directory = RAC_FALSE;
    rac_bool_t exists = cb->path_exists(folder_path, &is_directory, cb->user_data);

    *out_exists = (exists == RAC_TRUE && is_directory == RAC_TRUE) ? RAC_TRUE : RAC_FALSE;

    // Check contents if requested
    if (out_has_contents != nullptr) {
        *out_has_contents = RAC_FALSE;
        if (*out_exists == RAC_TRUE) {
            char** entries = nullptr;
            size_t count = 0;
            result = cb->list_directory(folder_path, &entries, &count, cb->user_data);
            if (RAC_SUCCEEDED(result)) {
                // Count non-dot entries
                for (size_t i = 0; i < count; i++) {
                    if (std::strcmp(entries[i], ".") != 0 && std::strcmp(entries[i], "..") != 0) {
                        *out_has_contents = RAC_TRUE;
                        break;
                    }
                }
                cb->free_entries(entries, count, cb->user_data);
            }
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_file_manager_delete_model(const rac_file_callbacks_t* cb, const char* model_id,
                                            rac_inference_framework_t framework) {
    if (model_id == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Get model folder path
    char folder_path[1024];
    result = rac_model_paths_get_model_folder(model_id, framework, folder_path, sizeof(folder_path));
    if (RAC_FAILED(result)) {
        return result;
    }

    // Check if it exists
    rac_bool_t is_directory = RAC_FALSE;
    rac_bool_t exists = cb->path_exists(folder_path, &is_directory, cb->user_data);

    if (exists != RAC_TRUE) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Delete recursively
    result = cb->delete_path(folder_path, 1 /* recursive */, cb->user_data);
    if (RAC_FAILED(result)) {
        RAC_LOG_ERROR(LOG_CATEGORY, "Failed to delete model folder");
        return result;
    }

    RAC_LOG_INFO(LOG_CATEGORY, "Deleted model folder");
    return RAC_SUCCESS;
}

// =============================================================================
// DIRECTORY SIZE CALCULATION
// =============================================================================

rac_result_t rac_file_manager_calculate_dir_size(const rac_file_callbacks_t* cb, const char* path,
                                                  int64_t* out_size) {
    if (path == nullptr || out_size == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Check if path exists
    rac_bool_t is_directory = RAC_FALSE;
    rac_bool_t exists = cb->path_exists(path, &is_directory, cb->user_data);

    if (exists != RAC_TRUE) {
        *out_size = 0;
        return RAC_SUCCESS;
    }

    if (is_directory != RAC_TRUE) {
        // Single file
        *out_size = cb->get_file_size(path, cb->user_data);
        if (*out_size < 0) {
            *out_size = 0;
        }
        return RAC_SUCCESS;
    }

    return calculate_dir_size_recursive(cb, path, out_size);
}

rac_result_t rac_file_manager_models_storage_used(const rac_file_callbacks_t* cb,
                                                   int64_t* out_size) {
    if (out_size == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    char models_dir[1024];
    result = rac_model_paths_get_models_directory(models_dir, sizeof(models_dir));
    if (RAC_FAILED(result)) {
        *out_size = 0;
        return result;
    }

    return rac_file_manager_calculate_dir_size(cb, models_dir, out_size);
}

// =============================================================================
// CACHE & TEMP MANAGEMENT
// =============================================================================

rac_result_t rac_file_manager_clear_cache(const rac_file_callbacks_t* cb) {
    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    char cache_dir[1024];
    result = rac_model_paths_get_cache_directory(cache_dir, sizeof(cache_dir));
    if (RAC_FAILED(result)) {
        return result;
    }

    result = clear_directory_impl(cb, cache_dir);
    if (RAC_SUCCEEDED(result)) {
        RAC_LOG_INFO(LOG_CATEGORY, "Cache cleared");
    }
    return result;
}

rac_result_t rac_file_manager_clear_temp(const rac_file_callbacks_t* cb) {
    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    char temp_dir[1024];
    result = rac_model_paths_get_temp_directory(temp_dir, sizeof(temp_dir));
    if (RAC_FAILED(result)) {
        return result;
    }

    result = clear_directory_impl(cb, temp_dir);
    if (RAC_SUCCEEDED(result)) {
        RAC_LOG_INFO(LOG_CATEGORY, "Temp directory cleared");
    }
    return result;
}

rac_result_t rac_file_manager_cache_size(const rac_file_callbacks_t* cb, int64_t* out_size) {
    if (out_size == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    char cache_dir[1024];
    result = rac_model_paths_get_cache_directory(cache_dir, sizeof(cache_dir));
    if (RAC_FAILED(result)) {
        *out_size = 0;
        return result;
    }

    return rac_file_manager_calculate_dir_size(cb, cache_dir, out_size);
}

// =============================================================================
// STORAGE INFO
// =============================================================================

rac_result_t rac_file_manager_get_storage_info(const rac_file_callbacks_t* cb,
                                                rac_file_manager_storage_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Zero-initialize
    std::memset(out_info, 0, sizeof(rac_file_manager_storage_info_t));

    // Device storage (requires get_available_space and get_total_space)
    if (cb->get_available_space != nullptr) {
        out_info->device_free = cb->get_available_space(cb->user_data);
    }
    if (cb->get_total_space != nullptr) {
        out_info->device_total = cb->get_total_space(cb->user_data);
    }

    // Models size
    char models_dir[1024];
    if (RAC_SUCCEEDED(rac_model_paths_get_models_directory(models_dir, sizeof(models_dir)))) {
        rac_file_manager_calculate_dir_size(cb, models_dir, &out_info->models_size);
    }

    // Cache size
    char cache_dir[1024];
    if (RAC_SUCCEEDED(rac_model_paths_get_cache_directory(cache_dir, sizeof(cache_dir)))) {
        rac_file_manager_calculate_dir_size(cb, cache_dir, &out_info->cache_size);
    }

    // Temp size
    char temp_dir[1024];
    if (RAC_SUCCEEDED(rac_model_paths_get_temp_directory(temp_dir, sizeof(temp_dir)))) {
        rac_file_manager_calculate_dir_size(cb, temp_dir, &out_info->temp_size);
    }

    // Total app size
    out_info->total_app_size = out_info->models_size + out_info->cache_size + out_info->temp_size;

    return RAC_SUCCESS;
}

rac_result_t rac_file_manager_check_storage(const rac_file_callbacks_t* cb,
                                             int64_t required_bytes,
                                             rac_storage_availability_t* out_availability) {
    if (out_availability == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    // Zero-initialize
    std::memset(out_availability, 0, sizeof(rac_storage_availability_t));

    // Get available space
    int64_t available_space = 0;
    if (cb->get_available_space != nullptr) {
        available_space = cb->get_available_space(cb->user_data);
    }

    out_availability->required_space = required_bytes;
    out_availability->available_space = available_space;

    // Check availability
    if (available_space >= required_bytes) {
        out_availability->is_available = RAC_TRUE;

        // Check for warning (less than 1GB remaining after operation)
        int64_t remaining = available_space - required_bytes;
        if (remaining < STORAGE_WARNING_THRESHOLD) {
            out_availability->has_warning = RAC_TRUE;
            out_availability->recommendation =
                rac_strdup("Low storage warning: less than 1 GB will remain after this download. "
                           "Consider freeing space by removing unused models.");
        } else {
            out_availability->has_warning = RAC_FALSE;
            out_availability->recommendation = nullptr;
        }
    } else {
        out_availability->is_available = RAC_FALSE;
        out_availability->has_warning = RAC_TRUE;
        out_availability->recommendation =
            rac_strdup("Insufficient storage space for this download. "
                       "Please free space by removing unused models or clearing the cache.");
    }

    return RAC_SUCCESS;
}

// =============================================================================
// DIRECTORY CLEARING (PUBLIC HELPER)
// =============================================================================

rac_result_t rac_file_manager_clear_directory(const rac_file_callbacks_t* cb, const char* path) {
    if (path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = validate_callbacks(cb);
    if (RAC_FAILED(result)) {
        return result;
    }

    return clear_directory_impl(cb, path);
}
