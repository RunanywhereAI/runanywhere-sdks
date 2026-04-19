/**
 * @file FileManagerBridge.hpp
 * @brief C++ bridge for file manager operations via rac_file_manager_* API.
 *
 * Uses POSIX I/O directly (works on both iOS and Android) to implement
 * rac_file_callbacks_t. C++ handles all business logic (recursive traversal,
 * cache clearing, storage info); no JS callbacks needed.
 *
 * Reference: sdk/runanywhere-commons/include/rac/infrastructure/file_management/rac_file_manager.h
 */

#pragma once

#include <string>
#include <cstdint>

#include "rac_types.h"
#include "rac_file_manager.h"

namespace runanywhere {
namespace bridges {

/**
 * FileManagerBridge - File management via rac_file_manager_* API
 *
 * Provides POSIX-based rac_file_callbacks_t implementation so C++
 * handles all recursion and business logic. SDKs only call high-level methods.
 */
class FileManagerBridge {
public:
    /**
     * Get shared instance
     */
    static FileManagerBridge& shared();

    /**
     * Initialize the file manager bridge.
     * Sets up POSIX-based file callbacks.
     */
    void initialize();

    /**
     * Shutdown and cleanup
     */
    void shutdown();

    /**
     * Check if initialized
     */
    bool isInitialized() const { return isInitialized_; }

    /**
     * Get the file callbacks struct (for use by StorageBridge if needed)
     */
    const rac_file_callbacks_t* getCallbacks() const { return &callbacks_; }

    // =========================================================================
    // Public API (wraps rac_file_manager_* functions)
    // =========================================================================

    /**
     * Create standard directory structure (Models/Cache/Temp/Downloads)
     */
    bool createDirectoryStructure();

    /**
     * Calculate directory size recursively (in C++)
     * Replaces FileSystem.ts getDirectorySize() and calculateExtractionStats()
     */
    int64_t calculateDirectorySize(const std::string& path);

    /**
     * Get total models storage used
     */
    int64_t modelsStorageUsed();

    /**
     * Clear cache directory (delete + recreate)
     */
    bool clearCache();

    /**
     * Clear temp directory (delete + recreate)
     */
    bool clearTemp();

    /**
     * Get cache directory size
     */
    int64_t cacheSize();

    /**
     * Delete a model folder
     */
    bool deleteModel(const std::string& modelId, int framework);

    /**
     * Get combined storage info (device + app)
     */
    rac_file_manager_storage_info_t getStorageInfo();

private:
    FileManagerBridge() = default;
    ~FileManagerBridge() = default;
    FileManagerBridge(const FileManagerBridge&) = delete;
    FileManagerBridge& operator=(const FileManagerBridge&) = delete;

    bool isInitialized_ = false;
    rac_file_callbacks_t callbacks_{};
};

} // namespace bridges
} // namespace runanywhere
