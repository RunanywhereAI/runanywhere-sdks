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

#include "rac/core/rac_platform_adapter.h"
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

    rac_log(RAC_LOG_INFO, "ModelRegistry", "Model registry created");

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
    rac_log(RAC_LOG_DEBUG, "ModelRegistry", "Model registry destroyed");
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

    rac_log(RAC_LOG_DEBUG, "ModelRegistry", "Model saved");

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

    rac_log(RAC_LOG_DEBUG, "ModelRegistry", "Model removed");

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
// PUBLIC API - MEMORY MANAGEMENT
// =============================================================================

rac_model_info_t* rac_model_info_alloc(void) {
    return static_cast<rac_model_info_t*>(calloc(1, sizeof(rac_model_info_t)));
}

void rac_model_info_free(rac_model_info_t* model) {
    free_model_info(model);
}

void rac_model_info_array_free(rac_model_info_t** models, size_t count) {
    if (!models) {
        return;
    }

    for (size_t i = 0; i < count; ++i) {
        if (models[i]) {
            free_model_info(models[i]);
        }
    }
    free(models);
}

rac_model_info_t* rac_model_info_copy(const rac_model_info_t* model) {
    return deep_copy_model(model);
}
