/**
 * @file ModelRegistryBridge.cpp
 * @brief C++ bridge for model registry operations.
 *
 * Mirrors Swift's CppBridge+ModelRegistry.swift pattern.
 */

#include "ModelRegistryBridge.hpp"
#include "rac_core.h"  // For rac_get_model_registry()
#include <cstring>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "ModelRegistryBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[ModelRegistryBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[ModelRegistryBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[ModelRegistryBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

ModelRegistryBridge& ModelRegistryBridge::shared() {
    static ModelRegistryBridge instance;
    return instance;
}

ModelRegistryBridge::~ModelRegistryBridge() {
    shutdown();
}

rac_result_t ModelRegistryBridge::initialize() {
    if (handle_) {
        LOGD("Model registry already initialized");
        return RAC_SUCCESS;
    }

    // Use the GLOBAL model registry (same as Swift SDK)
    // This ensures models registered by backends are visible to the SDK
    handle_ = rac_get_model_registry();

    if (handle_) {
        LOGI("Using global C++ model registry");
        return RAC_SUCCESS;
    } else {
        LOGE("Failed to get global model registry");
        return RAC_ERROR_NOT_INITIALIZED;
    }
}

void ModelRegistryBridge::shutdown() {
    // NOTE: We're using the GLOBAL registry - DO NOT clear the handle
    // The global registry persists for the lifetime of the app
    // Just log that shutdown was called, but don't actually release the handle
    LOGI("Model registry shutdown called (global registry handle retained)");
    // DO NOT: handle_ = nullptr;
}

ModelInfo ModelRegistryBridge::fromRac(const rac_model_info_t& cModel) {
    ModelInfo model;

    model.id = cModel.id ? cModel.id : "";
    model.name = cModel.name ? cModel.name : "";
    model.description = cModel.description ? cModel.description : "";
    model.category = cModel.category;
    model.format = cModel.format;
    model.framework = cModel.framework;
    model.downloadUrl = cModel.download_url ? cModel.download_url : "";
    model.localPath = cModel.local_path ? cModel.local_path : "";
    model.downloadSize = cModel.download_size;
    model.memoryRequired = cModel.memory_required;
    model.contextLength = cModel.context_length;
    model.supportsThinking = cModel.supports_thinking == RAC_TRUE;
    model.source = cModel.source;

    // Copy tags
    if (cModel.tags && cModel.tag_count > 0) {
        for (size_t i = 0; i < cModel.tag_count; i++) {
            if (cModel.tags[i]) {
                model.tags.push_back(cModel.tags[i]);
            }
        }
    }

    // Check if downloaded
    model.isDownloaded = !model.localPath.empty() && model.localPath[0] != '\0';

    return model;
}

void ModelRegistryBridge::toRac(const ModelInfo& model, rac_model_info_t& cModel) {
    // Note: This allocates strings that must be freed
    // For now we use static storage for simplicity
    static std::string s_id, s_name, s_desc, s_url, s_path;
    static std::vector<std::string> s_tags;
    static std::vector<const char*> s_tagPtrs;

    s_id = model.id;
    s_name = model.name;
    s_desc = model.description;
    s_url = model.downloadUrl;
    s_path = model.localPath;

    memset(&cModel, 0, sizeof(cModel));

    cModel.id = const_cast<char*>(s_id.c_str());
    cModel.name = const_cast<char*>(s_name.c_str());
    cModel.description = s_desc.empty() ? nullptr : const_cast<char*>(s_desc.c_str());
    cModel.category = model.category;
    cModel.format = model.format;
    cModel.framework = model.framework;
    cModel.download_url = s_url.empty() ? nullptr : const_cast<char*>(s_url.c_str());
    cModel.local_path = s_path.empty() ? nullptr : const_cast<char*>(s_path.c_str());
    cModel.download_size = model.downloadSize;
    cModel.memory_required = model.memoryRequired;
    cModel.context_length = model.contextLength;
    cModel.supports_thinking = model.supportsThinking ? RAC_TRUE : RAC_FALSE;
    cModel.source = model.source;

    // Setup tags
    s_tags = model.tags;
    s_tagPtrs.clear();
    for (const auto& tag : s_tags) {
        s_tagPtrs.push_back(tag.c_str());
    }
    if (!s_tagPtrs.empty()) {
        cModel.tags = const_cast<char**>(s_tagPtrs.data());
        cModel.tag_count = s_tagPtrs.size();
    }
}

rac_result_t ModelRegistryBridge::addModel(const ModelInfo& model) {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_model_info_t cModel;
    toRac(model, cModel);

    // Use rac_model_registry_save to add/update a model
    rac_result_t result = rac_model_registry_save(handle_, &cModel);

    if (result == RAC_SUCCESS) {
        LOGI("Added model: %s", model.id.c_str());
    } else {
        LOGE("Failed to add model %s: %d", model.id.c_str(), result);
    }

    return result;
}

rac_result_t ModelRegistryBridge::removeModel(const std::string& modelId) {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t result = rac_model_registry_remove(handle_, modelId.c_str());

    if (result == RAC_SUCCESS) {
        LOGI("Removed model: %s", modelId.c_str());
    } else {
        LOGE("Failed to remove model %s: %d", modelId.c_str(), result);
    }

    return result;
}

rac_result_t ModelRegistryBridge::updateModelPath(const std::string& modelId, const std::string& localPath) {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Use rac_model_registry_update_download_status to update the model's local path
    rac_result_t result = rac_model_registry_update_download_status(handle_, modelId.c_str(), localPath.c_str());

    if (result == RAC_SUCCESS) {
        LOGI("Updated model path: %s -> %s", modelId.c_str(), localPath.c_str());
    } else {
        LOGE("Failed to update model path %s: %d", modelId.c_str(), result);
    }

    return result;
}

std::optional<ModelInfo> ModelRegistryBridge::getModel(const std::string& modelId) {
    if (!handle_) {
        return std::nullopt;
    }

    rac_model_info_t* cModel = nullptr;
    rac_result_t result = rac_model_registry_get(handle_, modelId.c_str(), &cModel);

    if (result != RAC_SUCCESS || !cModel) {
        return std::nullopt;
    }

    ModelInfo model = fromRac(*cModel);
    rac_model_info_free(cModel);

    return model;
}

std::vector<ModelInfo> ModelRegistryBridge::getAllModels() {
    std::vector<ModelInfo> models;

    if (!handle_) {
        LOGE("getAllModels: Registry not initialized!");
        return models;
    }

    rac_model_info_t** cModels = nullptr;
    size_t count = 0;

    LOGD("getAllModels: Calling rac_model_registry_get_all with handle=%p", handle_);

    rac_result_t result = rac_model_registry_get_all(handle_, &cModels, &count);

    LOGI("getAllModels: result=%d, count=%zu", result, count);

    if (result != RAC_SUCCESS || !cModels) {
        LOGE("getAllModels: Failed with result=%d, cModels=%p", result, (void*)cModels);
        return models;
    }

    for (size_t i = 0; i < count; i++) {
        if (cModels[i]) {
            models.push_back(fromRac(*cModels[i]));
            LOGD("getAllModels: Added model %s", cModels[i]->id);
        }
    }

    rac_model_info_array_free(cModels, count);

    LOGI("getAllModels: Returning %zu models", models.size());

    return models;
}

std::vector<ModelInfo> ModelRegistryBridge::getModels(const ModelFilter& filter) {
    std::vector<ModelInfo> models;

    if (!handle_) {
        return models;
    }

    // Get all models first
    rac_model_info_t** cModels = nullptr;
    size_t count = 0;

    rac_result_t result = rac_model_registry_get_all(handle_, &cModels, &count);

    if (result != RAC_SUCCESS || !cModels) {
        return models;
    }

    // Setup filter
    rac_model_filter_t cFilter = {};
    cFilter.framework = filter.framework;
    cFilter.format = filter.format;
    cFilter.max_size = filter.maxSize;
    cFilter.search_query = filter.searchQuery.empty() ? nullptr : filter.searchQuery.c_str();

    // Apply filter using rac_model_matches_filter helper
    for (size_t i = 0; i < count; i++) {
        if (cModels[i]) {
            if (rac_model_matches_filter(cModels[i], &cFilter) == RAC_TRUE) {
                models.push_back(fromRac(*cModels[i]));
            }
        }
    }

    rac_model_info_array_free(cModels, count);

    return models;
}

std::vector<ModelInfo> ModelRegistryBridge::getModelsByFramework(rac_inference_framework_t framework) {
    ModelFilter filter;
    filter.framework = framework;
    return getModels(filter);
}

std::vector<ModelInfo> ModelRegistryBridge::getDownloadedModels() {
    std::vector<ModelInfo> models;

    if (!handle_) {
        return models;
    }

    rac_model_info_t** cModels = nullptr;
    size_t count = 0;

    rac_result_t result = rac_model_registry_get_downloaded(handle_, &cModels, &count);

    if (result != RAC_SUCCESS || !cModels) {
        return models;
    }

    for (size_t i = 0; i < count; i++) {
        if (cModels[i]) {
            models.push_back(fromRac(*cModels[i]));
        }
    }

    rac_model_info_array_free(cModels, count);

    return models;
}

bool ModelRegistryBridge::modelExists(const std::string& modelId) {
    if (!handle_) {
        return false;
    }

    // Check existence by trying to get the model
    rac_model_info_t* cModel = nullptr;
    rac_result_t result = rac_model_registry_get(handle_, modelId.c_str(), &cModel);

    if (result == RAC_SUCCESS && cModel) {
        rac_model_info_free(cModel);
        return true;
    }

    return false;
}

bool ModelRegistryBridge::isModelDownloaded(const std::string& modelId) {
    if (!handle_) {
        return false;
    }

    // Get the model and check its download status
    rac_model_info_t* cModel = nullptr;
    rac_result_t result = rac_model_registry_get(handle_, modelId.c_str(), &cModel);

    if (result != RAC_SUCCESS || !cModel) {
        return false;
    }

    rac_bool_t downloaded = rac_model_info_is_downloaded(cModel);
    rac_model_info_free(cModel);

    return downloaded == RAC_TRUE;
}

std::optional<std::string> ModelRegistryBridge::getModelPath(const std::string& modelId) {
    if (!handle_) {
        return std::nullopt;
    }

    // Get the model and extract its local_path
    rac_model_info_t* cModel = nullptr;
    rac_result_t result = rac_model_registry_get(handle_, modelId.c_str(), &cModel);

    if (result != RAC_SUCCESS || !cModel) {
        return std::nullopt;
    }

    std::string pathStr;
    if (cModel->local_path && cModel->local_path[0] != '\0') {
        pathStr = cModel->local_path;
    }

    rac_model_info_free(cModel);

    return pathStr.empty() ? std::nullopt : std::make_optional(pathStr);
}

size_t ModelRegistryBridge::getModelCount() {
    if (!handle_) {
        return 0;
    }

    // Get count by getting all models
    rac_model_info_t** cModels = nullptr;
    size_t count = 0;

    rac_result_t result = rac_model_registry_get_all(handle_, &cModels, &count);

    if (result == RAC_SUCCESS && cModels) {
        rac_model_info_array_free(cModels, count);
    }

    return count;
}

} // namespace bridges
} // namespace runanywhere
