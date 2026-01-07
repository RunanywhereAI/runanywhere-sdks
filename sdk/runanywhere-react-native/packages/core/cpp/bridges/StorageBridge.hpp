/**
 * @file StorageBridge.hpp
 * @brief C++ bridge for storage operations.
 *
 * Mirrors Swift's CppBridge+Storage.swift pattern:
 * - C++ handles business logic (which models, path calculations, aggregation)
 * - Platform provides file operation callbacks
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Storage.swift
 */

#pragma once

#include <string>
#include <vector>
#include <functional>
#include <cstdint>

#include "rac_types.h"
#include "rac_storage_analyzer.h"
#include "rac_model_registry.h"

namespace runanywhere {
namespace bridges {

/**
 * App storage info
 */
struct AppStorageInfo {
    int64_t documentsSize = 0;
    int64_t cacheSize = 0;
    int64_t appSupportSize = 0;
    int64_t totalSize = 0;
};

/**
 * Device storage info
 */
struct DeviceStorageInfo {
    int64_t totalSpace = 0;
    int64_t freeSpace = 0;
    int64_t usedSpace = 0;
};

/**
 * Model storage metrics
 */
struct ModelStorageMetrics {
    std::string modelId;
    std::string modelName;
    std::string localPath;
    int64_t sizeOnDisk = 0;
};

/**
 * Overall storage info
 */
struct StorageInfo {
    AppStorageInfo appStorage;
    DeviceStorageInfo deviceStorage;
    std::vector<ModelStorageMetrics> models;
    int64_t totalModelsSize = 0;
};

/**
 * Storage availability result
 */
struct StorageAvailability {
    bool isAvailable = false;
    int64_t requiredSpace = 0;
    int64_t availableSpace = 0;
    bool hasWarning = false;
    std::string recommendation;
};

/**
 * Platform callbacks for storage file operations
 */
struct StoragePlatformCallbacks {
    // Calculate directory size
    std::function<int64_t(const std::string& path)> calculateDirSize;

    // Get file size
    std::function<int64_t(const std::string& path)> getFileSize;

    // Check if path exists (returns: exists, isDirectory)
    std::function<std::pair<bool, bool>(const std::string& path)> pathExists;

    // Get available disk space
    std::function<int64_t()> getAvailableSpace;

    // Get total disk space
    std::function<int64_t()> getTotalSpace;
};

/**
 * StorageBridge - Storage analysis via rac_storage_analyzer_* API
 *
 * Mirrors Swift's CppBridge.Storage pattern:
 * - Handle-based API
 * - Platform provides file callbacks
 * - C++ handles business logic
 */
class StorageBridge {
public:
    /**
     * Get shared instance
     */
    static StorageBridge& shared();

    /**
     * Set platform callbacks for file operations
     * Must be called during SDK initialization
     */
    void setPlatformCallbacks(const StoragePlatformCallbacks& callbacks);

    /**
     * Initialize the storage analyzer
     * Creates handle with registered callbacks
     */
    rac_result_t initialize();

    /**
     * Shutdown and cleanup
     */
    void shutdown();

    /**
     * Check if initialized
     */
    bool isInitialized() const { return handle_ != nullptr; }

    /**
     * Analyze overall storage
     *
     * @param registryHandle Model registry handle for model enumeration
     * @return Storage info
     */
    StorageInfo analyzeStorage(rac_model_registry_handle_t registryHandle);

    /**
     * Get storage metrics for a specific model
     */
    std::optional<ModelStorageMetrics> getModelStorageMetrics(
        rac_model_registry_handle_t registryHandle,
        const std::string& modelId,
        rac_inference_framework_t framework
    );

    /**
     * Check if storage is available for a download
     */
    StorageAvailability checkStorageAvailable(int64_t modelSize, double safetyMargin = 0.1);

    /**
     * Calculate size at a path
     */
    int64_t calculateSize(const std::string& path);

private:
    StorageBridge() = default;
    ~StorageBridge();
    StorageBridge(const StorageBridge&) = delete;
    StorageBridge& operator=(const StorageBridge&) = delete;

    rac_storage_analyzer_handle_t handle_ = nullptr;
    StoragePlatformCallbacks platformCallbacks_{};
    rac_storage_callbacks_t racCallbacks_{};
};

} // namespace bridges
} // namespace runanywhere
