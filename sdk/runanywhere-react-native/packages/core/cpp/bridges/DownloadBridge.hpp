/**
 * @file DownloadBridge.hpp
 * @brief C++ bridge for download operations.
 *
 * Mirrors Swift's CppBridge+Download.swift pattern:
 * - Handle-based API via rac_download_manager_*
 * - Platform provides HTTP download implementation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift
 */

#pragma once

#include <string>
#include <vector>
#include <functional>
#include <unordered_map>
#include <cstdint>

#include "rac_types.h"
#include "rac_download.h"

namespace runanywhere {
namespace bridges {

/**
 * Download stage enum matching RAC
 */
enum class DownloadStage {
    Downloading = 0,
    Extracting = 1,
    Validating = 2,
    Completed = 3
};

/**
 * Download state enum matching RAC
 */
enum class DownloadState {
    Pending = 0,
    Downloading = 1,
    Extracting = 2,
    Retrying = 3,
    Completed = 4,
    Failed = 5,
    Cancelled = 6
};

/**
 * Download progress info
 */
struct DownloadProgress {
    DownloadStage stage = DownloadStage::Downloading;
    int64_t bytesDownloaded = 0;
    int64_t totalBytes = 0;
    double stageProgress = 0.0;
    double overallProgress = 0.0;
    DownloadState state = DownloadState::Pending;
    double speed = 0.0;  // bytes per second
    double estimatedTimeRemaining = -1.0;  // seconds
    int32_t retryAttempt = 0;
    rac_result_t errorCode = RAC_SUCCESS;
    std::string errorMessage;
};

/**
 * Download configuration
 */
struct DownloadConfig {
    int32_t maxConcurrentDownloads = 1;
    int32_t requestTimeoutSeconds = 60;
    int32_t maxRetryAttempts = 3;
    int32_t retryDelaySeconds = 5;
    bool allowCellular = true;
    bool allowConstrainedNetwork = false;
};

/**
 * DownloadBridge - Download orchestration via rac_download_manager_* API
 *
 * Mirrors Swift's CppBridge.Download pattern:
 * - Handle-based API
 * - Progress callbacks stored and invoked
 * - Platform provides actual HTTP downloads
 */
class DownloadBridge {
public:
    /**
     * Get shared instance
     */
    static DownloadBridge& shared();

    /**
     * Initialize the download manager
     * @param config Optional configuration
     */
    rac_result_t initialize(const DownloadConfig* config = nullptr);

    /**
     * Shutdown and cleanup
     */
    void shutdown();

    /**
     * Check if initialized
     */
    bool isInitialized() const { return handle_ != nullptr; }

    // =========================================================================
    // Download Operations
    // =========================================================================

    /**
     * Start a download task
     *
     * @param modelId Model identifier
     * @param url Download URL
     * @param destinationPath Where to save the file
     * @param requiresExtraction Whether to extract archive after download
     * @param progressHandler Callback for progress updates
     * @return Task ID for tracking, empty on error
     */
    std::string startDownload(
        const std::string& modelId,
        const std::string& url,
        const std::string& destinationPath,
        bool requiresExtraction,
        std::function<void(const DownloadProgress&)> progressHandler
    );

    /**
     * Cancel a download task
     */
    rac_result_t cancelDownload(const std::string& taskId);

    /**
     * Pause all active downloads
     */
    rac_result_t pauseAll();

    /**
     * Resume all paused downloads
     */
    rac_result_t resumeAll();

    // =========================================================================
    // Progress Tracking
    // =========================================================================

    /**
     * Get progress for a task
     */
    std::optional<DownloadProgress> getProgress(const std::string& taskId);

    /**
     * Get list of active task IDs
     */
    std::vector<std::string> getActiveTasks();

    /**
     * Check if download service is healthy
     */
    bool isHealthy();

    // =========================================================================
    // Progress Updates (called by platform HTTP layer)
    // =========================================================================

    /**
     * Update download progress (called by platform)
     */
    void updateProgress(const std::string& taskId, int64_t bytesDownloaded, int64_t totalBytes);

    /**
     * Mark download as complete (called by platform)
     */
    void markComplete(const std::string& taskId, const std::string& downloadedPath);

    /**
     * Mark download as failed (called by platform)
     */
    void markFailed(const std::string& taskId, rac_result_t errorCode, const std::string& errorMessage);

private:
    DownloadBridge() = default;
    ~DownloadBridge();
    DownloadBridge(const DownloadBridge&) = delete;
    DownloadBridge& operator=(const DownloadBridge&) = delete;

    static DownloadProgress fromRac(const rac_download_progress_t& cProgress);

    rac_download_manager_handle_t handle_ = nullptr;
    std::unordered_map<std::string, std::function<void(const DownloadProgress&)>> progressCallbacks_;
};

} // namespace bridges
} // namespace runanywhere
