/**
 * @file model_registry.cpp
 * @brief RunAnywhere Commons - Model Registry Implementation
 *
 * C++ port of Swift's ModelInfoService.
 * Swift Source: Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelInfoService.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 *
 * This is an in-memory model metadata store.
 */

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_model_registry {
    // Model storage (model_id -> model_info)
    std::map<std::string, rac_model_info_t*> models;

    // Thread safety
    std::mutex mutex;
};

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

static rac_model_info_t* deep_copy_model(const rac_model_info_t* src) {
    if (!src)
        return nullptr;

    rac_model_info_t* copy = static_cast<rac_model_info_t*>(calloc(1, sizeof(rac_model_info_t)));
    if (!copy)
        return nullptr;

    copy->id = rac_strdup(src->id);
    copy->name = rac_strdup(src->name);
    copy->category = src->category;
    copy->format = src->format;
    copy->framework = src->framework;
    copy->download_url = rac_strdup(src->download_url);
    copy->local_path = rac_strdup(src->local_path);
    // Copy artifact info struct (shallow copy for basic fields, deep copy for pointers)
    copy->artifact_info.kind = src->artifact_info.kind;
    copy->artifact_info.archive_type = src->artifact_info.archive_type;
    copy->artifact_info.archive_structure = src->artifact_info.archive_structure;
    copy->artifact_info.expected_files = nullptr;  // Complex structure, leave null for now
    copy->artifact_info.file_descriptors = nullptr;
    copy->artifact_info.file_descriptor_count = 0;
    copy->artifact_info.strategy_id = rac_strdup(src->artifact_info.strategy_id);
    copy->download_size = src->download_size;
    copy->memory_required = src->memory_required;
    copy->context_length = src->context_length;
    copy->supports_thinking = src->supports_thinking;

    // Copy tags
    if (src->tags && src->tag_count > 0) {
        copy->tags = static_cast<char**>(malloc(sizeof(char*) * src->tag_count));
        if (copy->tags) {
            for (size_t i = 0; i < src->tag_count; ++i) {
                copy->tags[i] = rac_strdup(src->tags[i]);
            }
            copy->tag_count = src->tag_count;
        }
    }

    copy->description = rac_strdup(src->description);
    copy->source = src->source;
    copy->created_at = src->created_at;
    copy->updated_at = src->updated_at;
    copy->last_used = src->last_used;
    copy->usage_count = src->usage_count;

    return copy;
}

static void free_model_info(rac_model_info_t* model) {
    if (!model)
        return;

    if (model->id)
        free(model->id);
    if (model->name)
        free(model->name);
    if (model->download_url)
        free(model->download_url);
    if (model->local_path)
        free(model->local_path);
    if (model->description)
        free(model->description);

    // Free artifact info strings
    if (model->artifact_info.strategy_id) {
        free(const_cast<char*>(model->artifact_info.strategy_id));
    }

    if (model->tags) {
        for (size_t i = 0; i < model->tag_count; ++i) {
            if (model->tags[i])
                free(model->tags[i]);
        }
        free(model->tags);
    }

    free(model);
}

// =============================================================================
// PUBLIC API - LIFECYCLE
// =============================================================================

rac_result_t rac_model_registry_create(rac_model_registry_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_model_registry* registry = new rac_model_registry();

    RAC_LOG_INFO("ModelRegistry", "Model registry created");

    *out_handle = registry;
    return RAC_SUCCESS;
}

void rac_model_registry_destroy(rac_model_registry_handle_t handle) {
    if (!handle) {
        return;
    }

    // Free all stored models
    for (auto& pair : handle->models) {
        free_model_info(pair.second);
    }
    handle->models.clear();

    delete handle;
    RAC_LOG_DEBUG("ModelRegistry", "Model registry destroyed");
}

// =============================================================================
// PUBLIC API - MODEL INFO
// =============================================================================

rac_result_t rac_model_registry_save(rac_model_registry_handle_t handle,
                                     const rac_model_info_t* model) {
    if (!handle || !model || !model->id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string model_id = model->id;

    // If model already exists, free the old one
    auto it = handle->models.find(model_id);
    if (it != handle->models.end()) {
        free_model_info(it->second);
    }

    // Store a deep copy
    rac_model_info_t* copy = deep_copy_model(model);
    if (!copy) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    handle->models[model_id] = copy;

    RAC_LOG_DEBUG("ModelRegistry", "Model saved");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get(rac_model_registry_handle_t handle, const char* model_id,
                                    rac_model_info_t** out_model) {
    if (!handle || !model_id || !out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    *out_model = deep_copy_model(it->second);
    if (!*out_model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_all(rac_model_registry_handle_t handle,
                                        rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    *out_count = handle->models.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    size_t i = 0;
    for (const auto& pair : handle->models) {
        (*out_models)[i] = deep_copy_model(pair.second);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        ++i;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_by_frameworks(rac_model_registry_handle_t handle,
                                                  const rac_inference_framework_t* frameworks,
                                                  size_t framework_count,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    if (!handle || !frameworks || framework_count == 0 || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect matching models
    std::vector<rac_model_info_t*> matches;

    for (const auto& pair : handle->models) {
        for (size_t i = 0; i < framework_count; ++i) {
            if (pair.second->framework == frameworks[i]) {
                matches.push_back(pair.second);
                break;
            }
        }
    }

    *out_count = matches.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < matches.size(); ++i) {
        (*out_models)[i] = deep_copy_model(matches[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_last_used(rac_model_registry_handle_t handle,
                                                 const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;
    model->last_used = rac_get_current_time_ms() / 1000;  // Convert to seconds
    model->usage_count++;

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_remove(rac_model_registry_handle_t handle, const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    free_model_info(it->second);
    handle->models.erase(it);

    RAC_LOG_DEBUG("ModelRegistry", "Model removed");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_downloaded(rac_model_registry_handle_t handle,
                                               rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect downloaded models
    std::vector<rac_model_info_t*> downloaded;

    for (const auto& pair : handle->models) {
        if (pair.second->local_path && strlen(pair.second->local_path) > 0) {
            downloaded.push_back(pair.second);
        }
    }

    *out_count = downloaded.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < downloaded.size(); ++i) {
        (*out_models)[i] = deep_copy_model(downloaded[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_download_status(rac_model_registry_handle_t handle,
                                                       const char* model_id,
                                                       const char* local_path) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;

    // Free old local path
    if (model->local_path) {
        free(model->local_path);
    }

    // Set new local path
    model->local_path = rac_strdup(local_path);
    model->updated_at = rac_get_current_time_ms() / 1000;

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API - QUERY HELPERS
// =============================================================================

rac_bool_t rac_model_info_is_downloaded(const rac_model_info_t* model) {
    if (!model) {
        return RAC_FALSE;
    }
    return (model->local_path && strlen(model->local_path) > 0) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_model_category_requires_context_length(rac_model_category_t category) {
    return (category == RAC_MODEL_CATEGORY_LANGUAGE) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_model_category_supports_thinking(rac_model_category_t category) {
    return (category == RAC_MODEL_CATEGORY_LANGUAGE) ? RAC_TRUE : RAC_FALSE;
}

rac_artifact_type_kind_t rac_model_infer_artifact_type(const char* url, rac_model_format_t format) {
    // Infer from URL extension
    if (url) {
        size_t len = strlen(url);

        if (len > 4 && strcmp(url + len - 4, ".zip") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tar") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 7 && strcmp(url + len - 7, ".tar.gz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tgz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
    }

    // Default to single file for most formats
    switch (format) {
        case RAC_MODEL_FORMAT_GGUF:
        case RAC_MODEL_FORMAT_ONNX:
        case RAC_MODEL_FORMAT_BIN:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
        default:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
    }
}

// =============================================================================
// PUBLIC API - MODEL DISCOVERY
// =============================================================================

// Helper to check if a folder contains valid model files for a framework
static bool is_valid_model_folder(const rac_discovery_callbacks_t* callbacks,
                                  const char* folder_path, rac_inference_framework_t framework) {
    if (!callbacks || !callbacks->list_directory || !folder_path) {
        return false;
    }

    char** entries = nullptr;
    size_t count = 0;

    // List directory contents
    if (callbacks->list_directory(folder_path, &entries, &count, callbacks->user_data) !=
        RAC_SUCCESS) {
        return false;
    }

    bool found_model_file = false;

    for (size_t i = 0; i < count && !found_model_file; i++) {
        if (!entries[i])
            continue;

        // Build full path
        std::string full_path = std::string(folder_path) + "/" + entries[i];

        // Check if it's a model file for this framework
        if (callbacks->is_model_file) {
            if (callbacks->is_model_file(full_path.c_str(), framework, callbacks->user_data) ==
                RAC_TRUE) {
                found_model_file = true;
            }
        }

        // For nested directories, recursively check (one level deep)
        if (!found_model_file && callbacks->is_directory) {
            if (callbacks->is_directory(full_path.c_str(), callbacks->user_data) == RAC_TRUE) {
                // Check subdirectory for model files
                char** sub_entries = nullptr;
                size_t sub_count = 0;
                if (callbacks->list_directory(full_path.c_str(), &sub_entries, &sub_count,
                                              callbacks->user_data) == RAC_SUCCESS) {
                    for (size_t j = 0; j < sub_count && !found_model_file; j++) {
                        if (!sub_entries[j])
                            continue;
                        std::string sub_path = full_path + "/" + sub_entries[j];
                        if (callbacks->is_model_file &&
                            callbacks->is_model_file(sub_path.c_str(), framework,
                                                     callbacks->user_data) == RAC_TRUE) {
                            found_model_file = true;
                        }
                    }
                    if (callbacks->free_entries) {
                        callbacks->free_entries(sub_entries, sub_count, callbacks->user_data);
                    }
                }
            }
        }
    }

    if (callbacks->free_entries) {
        callbacks->free_entries(entries, count, callbacks->user_data);
    }

    return found_model_file;
}

rac_result_t rac_model_registry_discover_downloaded(rac_model_registry_handle_t handle,
                                                    const rac_discovery_callbacks_t* callbacks,
                                                    rac_discovery_result_t* out_result) {
    if (!handle || !callbacks || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize result
    out_result->discovered_count = 0;
    out_result->discovered_models = nullptr;
    out_result->unregistered_count = 0;

    // Check required callbacks
    if (!callbacks->list_directory || !callbacks->path_exists || !callbacks->is_directory) {
        RAC_LOG_WARNING("ModelRegistry", "Discovery: Missing required callbacks");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("ModelRegistry", "Starting model discovery scan...");

    // Get models directory path
    char models_dir[1024];
    if (rac_model_paths_get_models_directory(models_dir, sizeof(models_dir)) != RAC_SUCCESS) {
        RAC_LOG_WARNING("ModelRegistry", "Discovery: Base directory not configured");
        return RAC_SUCCESS;  // Not an error, just nothing to discover
    }

    // Check if models directory exists
    if (callbacks->path_exists(models_dir, callbacks->user_data) != RAC_TRUE) {
        RAC_LOG_DEBUG("ModelRegistry", "Discovery: Models directory does not exist yet");
        return RAC_SUCCESS;
    }

    // Frameworks to scan
    rac_inference_framework_t frameworks[] = {RAC_FRAMEWORK_LLAMACPP, RAC_FRAMEWORK_ONNX,
                                              RAC_FRAMEWORK_FOUNDATION_MODELS,
                                              RAC_FRAMEWORK_SYSTEM_TTS};
    size_t framework_count = sizeof(frameworks) / sizeof(frameworks[0]);

    // Collect discovered models
    std::vector<rac_discovered_model_t> discovered;
    size_t unregistered = 0;

    std::lock_guard<std::mutex> lock(handle->mutex);

    for (size_t f = 0; f < framework_count; f++) {
        rac_inference_framework_t framework = frameworks[f];

        // Get framework directory path
        char framework_dir[1024];
        if (rac_model_paths_get_framework_directory(framework, framework_dir,
                                                    sizeof(framework_dir)) != RAC_SUCCESS) {
            continue;
        }

        // Check if framework directory exists
        if (callbacks->path_exists(framework_dir, callbacks->user_data) != RAC_TRUE) {
            continue;
        }

        // List model folders in this framework directory
        char** model_folders = nullptr;
        size_t folder_count = 0;

        if (callbacks->list_directory(framework_dir, &model_folders, &folder_count,
                                      callbacks->user_data) != RAC_SUCCESS) {
            continue;
        }

        for (size_t i = 0; i < folder_count; i++) {
            if (!model_folders[i])
                continue;

            // Skip hidden files
            if (model_folders[i][0] == '.')
                continue;

            const char* model_id = model_folders[i];

            // Build full path to model folder
            std::string model_path = std::string(framework_dir) + "/" + model_id;

            // Check if it's a directory
            if (callbacks->is_directory(model_path.c_str(), callbacks->user_data) != RAC_TRUE) {
                continue;
            }

            // Check if it contains valid model files
            if (!is_valid_model_folder(callbacks, model_path.c_str(), framework)) {
                continue;
            }

            // Check if this model is registered
            auto it = handle->models.find(model_id);
            if (it != handle->models.end()) {
                // Model is registered - check if it needs update
                rac_model_info_t* model = it->second;

                if (!model->local_path || strlen(model->local_path) == 0) {
                    // Update the local path
                    if (model->local_path) {
                        free(model->local_path);
                    }
                    model->local_path = rac_strdup(model_path.c_str());
                    model->updated_at = rac_get_current_time_ms() / 1000;

                    // Add to discovered list
                    rac_discovered_model_t disc;
                    disc.model_id = rac_strdup(model_id);
                    disc.local_path = rac_strdup(model_path.c_str());
                    disc.framework = framework;
                    discovered.push_back(disc);

                    RAC_LOG_INFO("ModelRegistry", "Discovered downloaded model");
                }
            } else {
                // Model folder exists but not registered
                unregistered++;
                RAC_LOG_DEBUG("ModelRegistry", "Found unregistered model folder");
            }
        }

        if (callbacks->free_entries) {
            callbacks->free_entries(model_folders, folder_count, callbacks->user_data);
        }
    }

    // Build result
    out_result->discovered_count = discovered.size();
    out_result->unregistered_count = unregistered;

    if (!discovered.empty()) {
        out_result->discovered_models = static_cast<rac_discovered_model_t*>(
            malloc(sizeof(rac_discovered_model_t) * discovered.size()));
        if (out_result->discovered_models) {
            for (size_t i = 0; i < discovered.size(); i++) {
                out_result->discovered_models[i] = discovered[i];
            }
        }
    }

    RAC_LOG_INFO("ModelRegistry", "Model discovery complete");

    return RAC_SUCCESS;
}

void rac_discovery_result_free(rac_discovery_result_t* result) {
    if (!result)
        return;

    if (result->discovered_models) {
        for (size_t i = 0; i < result->discovered_count; i++) {
            if (result->discovered_models[i].model_id) {
                free(const_cast<char*>(result->discovered_models[i].model_id));
            }
            if (result->discovered_models[i].local_path) {
                free(const_cast<char*>(result->discovered_models[i].local_path));
            }
        }
        free(result->discovered_models);
    }

    result->discovered_models = nullptr;
    result->discovered_count = 0;
    result->unregistered_count = 0;
}
