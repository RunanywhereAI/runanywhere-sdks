/**
 * @file StorageBridge.hpp
 * @brief Storage management bridge for React Native
 *
 * Matches Swift's RunAnywhere+Storage.swift pattern, providing:
 * - Storage info (disk usage, available space)
 * - Cache clearing
 * - Model deletion
 */

#pragma once

#include <string>
#include <cstdint>

namespace runanywhere {
namespace bridges {

/**
 * @brief Storage info structure
 */
struct StorageInfo {
    int64_t totalBytes = 0;
    int64_t availableBytes = 0;
    int64_t usedByModelsBytes = 0;
    int64_t usedByCacheBytes = 0;
};

/**
 * @brief Storage bridge singleton
 */
class StorageBridge {
public:
    static StorageBridge& shared();

    /**
     * Get storage info
     */
    StorageInfo getStorageInfo();

    /**
     * Clear model cache
     */
    bool clearCache();

    /**
     * Delete a specific model
     */
    bool deleteModel(const std::string& modelId);

    /**
     * Get models directory path
     */
    std::string getModelsDirectory();

    /**
     * Get cache directory path
     */
    std::string getCacheDirectory();

private:
    StorageBridge() = default;
    ~StorageBridge() = default;

    StorageBridge(const StorageBridge&) = delete;
    StorageBridge& operator=(const StorageBridge&) = delete;
};

} // namespace bridges
} // namespace runanywhere
