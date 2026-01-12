/**
 * @file StorageBridge.cpp
 * @brief C++ bridge for storage operations.
 *
 * Mirrors Swift's CppBridge+Storage.swift pattern.
 */

#include "StorageBridge.hpp"
#include <cstring>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "StorageBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[StorageBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[StorageBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[StorageBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// Static storage for callbacks (needed for C function pointers)
// =============================================================================

static StoragePlatformCallbacks* g_storageCallbacks = nullptr;

// =============================================================================
// C Callback Implementations (called by RACommons)
// =============================================================================

static int64_t storageCalculateDirSizeCallback(const char* path, void* userData) {
    if (!path || !g_storageCallbacks || !g_storageCallbacks->calculateDirSize) {
        return 0;
    }
    return g_storageCallbacks->calculateDirSize(path);
}

static int64_t storageGetFileSizeCallback(const char* path, void* userData) {
    if (!path || !g_storageCallbacks || !g_storageCallbacks->getFileSize) {
        return -1;
    }
    return g_storageCallbacks->getFileSize(path);
}

static rac_bool_t storagePathExistsCallback(
    const char* path,
    rac_bool_t* isDirectory,
    void* userData
) {
    if (!path || !g_storageCallbacks || !g_storageCallbacks->pathExists) {
        return RAC_FALSE;
    }

    auto [exists, isDir] = g_storageCallbacks->pathExists(path);
    if (isDirectory) {
        *isDirectory = isDir ? RAC_TRUE : RAC_FALSE;
    }
    return exists ? RAC_TRUE : RAC_FALSE;
}

static int64_t storageGetAvailableSpaceCallback(void* userData) {
    if (!g_storageCallbacks || !g_storageCallbacks->getAvailableSpace) {
        return 0;
    }
    return g_storageCallbacks->getAvailableSpace();
}

static int64_t storageGetTotalSpaceCallback(void* userData) {
    if (!g_storageCallbacks || !g_storageCallbacks->getTotalSpace) {
        return 0;
    }
    return g_storageCallbacks->getTotalSpace();
}

// =============================================================================
// StorageBridge Implementation
// =============================================================================

StorageBridge& StorageBridge::shared() {
    static StorageBridge instance;
    return instance;
}

StorageBridge::~StorageBridge() {
    shutdown();
}

void StorageBridge::setPlatformCallbacks(const StoragePlatformCallbacks& callbacks) {
    platformCallbacks_ = callbacks;

    // Store in global for C callbacks
    static StoragePlatformCallbacks storedCallbacks;
    storedCallbacks = callbacks;
    g_storageCallbacks = &storedCallbacks;

    LOGI("Storage platform callbacks set");
}

rac_result_t StorageBridge::initialize() {
    if (handle_) {
        LOGD("Storage analyzer already initialized");
        return RAC_SUCCESS;
    }

    // Setup callback struct
    memset(&racCallbacks_, 0, sizeof(racCallbacks_));
    racCallbacks_.calculate_dir_size = storageCalculateDirSizeCallback;
    racCallbacks_.get_file_size = storageGetFileSizeCallback;
    racCallbacks_.path_exists = storagePathExistsCallback;
    racCallbacks_.get_available_space = storageGetAvailableSpaceCallback;
    racCallbacks_.get_total_space = storageGetTotalSpaceCallback;
    racCallbacks_.user_data = nullptr;

    // Create analyzer
    rac_result_t result = rac_storage_analyzer_create(&racCallbacks_, &handle_);

    if (result == RAC_SUCCESS) {
        LOGI("Storage analyzer created successfully");
    } else {
        LOGE("Failed to create storage analyzer: %d", result);
        handle_ = nullptr;
    }

    return result;
}

void StorageBridge::shutdown() {
    if (handle_) {
        rac_storage_analyzer_destroy(handle_);
        handle_ = nullptr;
        LOGI("Storage analyzer destroyed");
    }
}

StorageInfo StorageBridge::analyzeStorage(rac_model_registry_handle_t registryHandle) {
    StorageInfo result;

    if (!handle_) {
        LOGE("Storage analyzer not initialized");
        return result;
    }

    if (!registryHandle) {
        LOGE("Model registry handle is null");
        return result;
    }

    rac_storage_info_t cInfo = {};
    rac_result_t status = rac_storage_analyzer_analyze(handle_, registryHandle, &cInfo);

    if (status != RAC_SUCCESS) {
        LOGE("Storage analysis failed: %d", status);
        return result;
    }

    // Convert app storage
    result.appStorage.documentsSize = cInfo.app_storage.documents_size;
    result.appStorage.cacheSize = cInfo.app_storage.cache_size;
    result.appStorage.appSupportSize = cInfo.app_storage.app_support_size;
    result.appStorage.totalSize = cInfo.app_storage.total_size;

    // Convert device storage
    result.deviceStorage.totalSpace = cInfo.device_storage.total_space;
    result.deviceStorage.freeSpace = cInfo.device_storage.free_space;
    result.deviceStorage.usedSpace = cInfo.device_storage.used_space;

    // Convert model metrics
    if (cInfo.models && cInfo.model_count > 0) {
        for (size_t i = 0; i < cInfo.model_count; i++) {
            const auto& cModel = cInfo.models[i];
            ModelStorageMetrics metrics;
            metrics.modelId = cModel.model_id ? cModel.model_id : "";
            metrics.modelName = cModel.model_name ? cModel.model_name : "";
            metrics.localPath = cModel.local_path ? cModel.local_path : "";
            metrics.sizeOnDisk = cModel.size_on_disk;
            result.models.push_back(metrics);
        }
    }

    result.totalModelsSize = cInfo.total_models_size;

    // Free C++ result
    rac_storage_info_free(&cInfo);

    LOGI("Storage analysis complete: %zu models, total size: %lld bytes",
         result.models.size(), static_cast<long long>(result.totalModelsSize));

    return result;
}

std::optional<ModelStorageMetrics> StorageBridge::getModelStorageMetrics(
    rac_model_registry_handle_t registryHandle,
    const std::string& modelId,
    rac_inference_framework_t framework
) {
    if (!handle_ || !registryHandle) {
        return std::nullopt;
    }

    rac_model_storage_metrics_t cMetrics = {};
    rac_result_t result = rac_storage_analyzer_get_model_metrics(
        handle_, registryHandle, modelId.c_str(), framework, &cMetrics
    );

    if (result != RAC_SUCCESS) {
        return std::nullopt;
    }

    ModelStorageMetrics metrics;
    metrics.modelId = cMetrics.model_id ? cMetrics.model_id : "";
    metrics.modelName = cMetrics.model_name ? cMetrics.model_name : "";
    metrics.localPath = cMetrics.local_path ? cMetrics.local_path : "";
    metrics.sizeOnDisk = cMetrics.size_on_disk;

    return metrics;
}

StorageAvailability StorageBridge::checkStorageAvailable(int64_t modelSize, double safetyMargin) {
    StorageAvailability result;

    // Use callbacks directly for synchronous check
    int64_t available = g_storageCallbacks && g_storageCallbacks->getAvailableSpace
        ? g_storageCallbacks->getAvailableSpace() : 0;

    int64_t required = static_cast<int64_t>(static_cast<double>(modelSize) * (1.0 + safetyMargin));

    result.isAvailable = available > required;
    result.requiredSpace = required;
    result.availableSpace = available;
    result.hasWarning = available < required * 2;

    if (!result.isAvailable) {
        int64_t shortfall = required - available;
        // Format shortfall in MB
        double shortfallMB = static_cast<double>(shortfall) / (1024.0 * 1024.0);
        result.recommendation = "Need " + std::to_string(static_cast<int>(shortfallMB)) + " MB more space.";
    } else if (result.hasWarning) {
        result.recommendation = "Storage space is getting low.";
    }

    return result;
}

int64_t StorageBridge::calculateSize(const std::string& path) {
    if (!handle_) {
        LOGE("Storage analyzer not initialized");
        return -1;
    }

    int64_t size = 0;
    rac_result_t result = rac_storage_analyzer_calculate_size(handle_, path.c_str(), &size);

    if (result != RAC_SUCCESS) {
        LOGE("Failed to calculate size for %s: %d", path.c_str(), result);
        return -1;
    }

    return size;
}

} // namespace bridges
} // namespace runanywhere
