/**
 * @file storage_analyzer.cpp
 * @brief Storage Analyzer Implementation
 *
 * Business logic for storage analysis.
 * - Uses rac_model_registry for model listing
 * - Uses rac_model_paths for path calculations
 * - Calls platform callbacks for file operations
 */

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_storage_analyzer {
    rac_storage_callbacks_t callbacks;
};

// =============================================================================
// LIFECYCLE
// =============================================================================

rac_result_t rac_storage_analyzer_create(const rac_storage_callbacks_t* callbacks,
                                         rac_storage_analyzer_handle_t* out_handle) {
    if (!callbacks || !out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate required callbacks
    if (!callbacks->calculate_dir_size || !callbacks->get_available_space ||
        !callbacks->get_total_space) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* analyzer = new (std::nothrow) rac_storage_analyzer();
    if (!analyzer) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    analyzer->callbacks = *callbacks;
    *out_handle = analyzer;
    return RAC_SUCCESS;
}

void rac_storage_analyzer_destroy(rac_storage_analyzer_handle_t handle) {
    delete handle;
}

// =============================================================================
// STORAGE ANALYSIS
// =============================================================================

rac_result_t rac_storage_analyzer_analyze(rac_storage_analyzer_handle_t handle,
                                          rac_model_registry_handle_t registry_handle,
                                          rac_storage_info_t* out_info) {
    if (!handle || !registry_handle || !out_info) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    memset(out_info, 0, sizeof(rac_storage_info_t));

    // Get device storage via callbacks
    out_info->device_storage.free_space =
        handle->callbacks.get_available_space(handle->callbacks.user_data);
    out_info->device_storage.total_space =
        handle->callbacks.get_total_space(handle->callbacks.user_data);
    out_info->device_storage.used_space =
        out_info->device_storage.total_space - out_info->device_storage.free_space;

    // Get app storage - calculate base directory size
    char base_dir[1024];
    if (rac_model_paths_get_base_directory(base_dir, sizeof(base_dir)) == RAC_SUCCESS) {
        out_info->app_storage.documents_size =
            handle->callbacks.calculate_dir_size(base_dir, handle->callbacks.user_data);
        out_info->app_storage.total_size = out_info->app_storage.documents_size;
    }

    // Get downloaded models from registry
    rac_model_info_t** models = nullptr;
    size_t model_count = 0;

    rac_result_t result = rac_model_registry_get_downloaded(registry_handle, &models, &model_count);
    if (result != RAC_SUCCESS) {
        // No models is okay, just return empty
        out_info->models = nullptr;
        out_info->model_count = 0;
        return RAC_SUCCESS;
    }

    // Allocate model metrics array
    if (model_count > 0) {
        out_info->models = static_cast<rac_model_storage_metrics_t*>(
            calloc(model_count, sizeof(rac_model_storage_metrics_t)));
        if (!out_info->models) {
            rac_model_info_array_free(models, model_count);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    out_info->model_count = model_count;
    out_info->total_models_size = 0;

    // Calculate metrics for each model
    for (size_t i = 0; i < model_count; i++) {
        const rac_model_info_t* model = models[i];
        rac_model_storage_metrics_t* metrics = &out_info->models[i];

        // Copy model info
        metrics->model_id = model->id ? strdup(model->id) : nullptr;
        metrics->model_name = model->name ? strdup(model->name) : nullptr;
        metrics->framework = model->framework;
        metrics->format = model->format;
        metrics->artifact_info = model->artifact_info;

        // Get path - either from model or calculate from model_paths
        char path_buffer[1024];
        const char* path_to_use = nullptr;

        if (model->local_path && strlen(model->local_path) > 0) {
            path_to_use = model->local_path;
            metrics->local_path = strdup(model->local_path);
        } else if (model->id) {
            // Calculate path using rac_model_paths
            if (rac_model_paths_get_model_folder(model->id, model->framework, path_buffer,
                                                 sizeof(path_buffer)) == RAC_SUCCESS) {
                path_to_use = path_buffer;
                metrics->local_path = strdup(path_buffer);
            }
        }

        // Calculate size via callback
        if (path_to_use) {
            metrics->size_on_disk =
                handle->callbacks.calculate_dir_size(path_to_use, handle->callbacks.user_data);
        } else {
            // Fallback to download size if we can't calculate
            metrics->size_on_disk = model->download_size;
        }

        out_info->total_models_size += metrics->size_on_disk;
    }

    // Free the models array from registry
    rac_model_info_array_free(models, model_count);

    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_get_model_metrics(rac_storage_analyzer_handle_t handle,
                                                    rac_model_registry_handle_t registry_handle,
                                                    const char* model_id,
                                                    rac_inference_framework_t framework,
                                                    rac_model_storage_metrics_t* out_metrics) {
    if (!handle || !registry_handle || !model_id || !out_metrics) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Get model from registry
    rac_model_info_t* model = nullptr;
    rac_result_t result = rac_model_registry_get(registry_handle, model_id, &model);
    if (result != RAC_SUCCESS || !model) {
        return RAC_ERROR_NOT_FOUND;
    }

    // Initialize output
    memset(out_metrics, 0, sizeof(rac_model_storage_metrics_t));

    // Copy model info
    out_metrics->model_id = model->id ? strdup(model->id) : nullptr;
    out_metrics->model_name = model->name ? strdup(model->name) : nullptr;
    out_metrics->framework = model->framework;
    out_metrics->format = model->format;
    out_metrics->artifact_info = model->artifact_info;

    // Get path
    char path_buffer[1024];
    const char* path_to_use = nullptr;

    if (model->local_path && strlen(model->local_path) > 0) {
        path_to_use = model->local_path;
        out_metrics->local_path = strdup(model->local_path);
    } else {
        if (rac_model_paths_get_model_folder(model_id, framework, path_buffer,
                                             sizeof(path_buffer)) == RAC_SUCCESS) {
            path_to_use = path_buffer;
            out_metrics->local_path = strdup(path_buffer);
        }
    }

    // Calculate size
    if (path_to_use) {
        out_metrics->size_on_disk =
            handle->callbacks.calculate_dir_size(path_to_use, handle->callbacks.user_data);
    } else {
        out_metrics->size_on_disk = model->download_size;
    }

    rac_model_info_free(model);
    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_check_available(rac_storage_analyzer_handle_t handle,
                                                  int64_t model_size, double safety_margin,
                                                  rac_storage_availability_t* out_availability) {
    if (!handle || !out_availability) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    memset(out_availability, 0, sizeof(rac_storage_availability_t));

    // Get available space via callback
    int64_t available = handle->callbacks.get_available_space(handle->callbacks.user_data);
    int64_t required =
        static_cast<int64_t>(static_cast<double>(model_size) * (1.0 + safety_margin));

    out_availability->available_space = available;
    out_availability->required_space = required;
    out_availability->is_available = available > required ? RAC_TRUE : RAC_FALSE;
    out_availability->has_warning = available < required * 2 ? RAC_TRUE : RAC_FALSE;

    // Generate recommendation message
    if (out_availability->is_available == RAC_FALSE) {
        int64_t shortfall = required - available;
        // Simple message - platform can format with locale-specific formatter
        char msg[256];
        snprintf(msg, sizeof(msg), "Need %lld more bytes of space.", (long long)shortfall);
        out_availability->recommendation = strdup(msg);
    } else if (out_availability->has_warning == RAC_TRUE) {
        out_availability->recommendation = strdup("Storage space is getting low.");
    }

    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_calculate_size(rac_storage_analyzer_handle_t handle,
                                                 const char* path, int64_t* out_size) {
    if (!handle || !path || !out_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if path exists and is directory
    rac_bool_t is_directory = RAC_FALSE;
    if (handle->callbacks.path_exists) {
        rac_bool_t exists =
            handle->callbacks.path_exists(path, &is_directory, handle->callbacks.user_data);
        if (exists == RAC_FALSE) {
            return RAC_ERROR_NOT_FOUND;
        }
    }

    // Calculate size based on type
    if (is_directory == RAC_TRUE) {
        *out_size = handle->callbacks.calculate_dir_size(path, handle->callbacks.user_data);
    } else if (handle->callbacks.get_file_size) {
        *out_size = handle->callbacks.get_file_size(path, handle->callbacks.user_data);
    } else {
        // Fallback to dir size calculator for files too
        *out_size = handle->callbacks.calculate_dir_size(path, handle->callbacks.user_data);
    }

    return RAC_SUCCESS;
}

// =============================================================================
// CLEANUP
// =============================================================================

void rac_storage_info_free(rac_storage_info_t* info) {
    if (!info)
        return;

    if (info->models) {
        for (size_t i = 0; i < info->model_count; i++) {
            free(const_cast<char*>(info->models[i].model_id));
            free(const_cast<char*>(info->models[i].model_name));
            free(const_cast<char*>(info->models[i].local_path));
        }
        free(info->models);
    }

    memset(info, 0, sizeof(rac_storage_info_t));
}

void rac_storage_availability_free(rac_storage_availability_t* availability) {
    if (!availability)
        return;

    free(const_cast<char*>(availability->recommendation));
    memset(availability, 0, sizeof(rac_storage_availability_t));
}
