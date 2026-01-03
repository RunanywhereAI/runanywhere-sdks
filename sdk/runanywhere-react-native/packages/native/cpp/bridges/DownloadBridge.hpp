/**
 * DownloadBridge.hpp
 *
 * C++ bridge for download operations.
 * Calls rac_download_* API from runanywhere-commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift
 */

#pragma once

#include <string>
#include <functional>
#include <map>

namespace runanywhere {
namespace bridges {

/**
 * Download state
 */
enum class DownloadState {
    Idle,
    Queued,
    Downloading,
    Paused,
    Completed,
    Failed,
    Cancelled
};

/**
 * Download progress information
 */
struct DownloadProgress {
    std::string taskId;
    std::string modelId;
    int64_t bytesDownloaded;
    int64_t totalBytes;
    float progress;  // 0.0 - 1.0
    DownloadState state;
    std::string error;
};

/**
 * Download progress callback
 */
using DownloadProgressCallback = std::function<void(const DownloadProgress&)>;

/**
 * Download completion callback
 */
using DownloadCompletionCallback = std::function<void(const std::string& localPath, const std::string& error)>;

/**
 * DownloadBridge - Download operations via rac_download_* API
 */
class DownloadBridge {
public:
    /**
     * Get shared instance
     */
    static DownloadBridge& shared();

    /**
     * Start model download
     * @param modelId Model ID to download
     * @param url Download URL
     * @param destPath Destination path
     * @param progressCallback Progress updates
     * @param completionCallback Completion callback
     * @return Task ID
     */
    std::string startDownload(
        const std::string& modelId,
        const std::string& url,
        const std::string& destPath,
        DownloadProgressCallback progressCallback,
        DownloadCompletionCallback completionCallback
    );

    /**
     * Cancel download
     * @param taskId Task ID to cancel
     */
    void cancelDownload(const std::string& taskId);

    /**
     * Pause download
     * @param taskId Task ID to pause
     */
    void pauseDownload(const std::string& taskId);

    /**
     * Resume download
     * @param taskId Task ID to resume
     */
    void resumeDownload(const std::string& taskId);

    /**
     * Pause all downloads
     */
    void pauseAllDownloads();

    /**
     * Resume all downloads
     */
    void resumeAllDownloads();

    /**
     * Cancel all downloads
     */
    void cancelAllDownloads();

    /**
     * Get download progress
     * @param taskId Task ID
     * @return Current progress
     */
    DownloadProgress getProgress(const std::string& taskId);

    /**
     * Check if service is healthy
     * @return true if healthy
     */
    bool isHealthy() const;

    /**
     * Configure download service
     * @param maxConcurrent Maximum concurrent downloads
     * @param timeoutMs Request timeout in milliseconds
     */
    void configure(int maxConcurrent, int timeoutMs);

private:
    DownloadBridge() = default;
    ~DownloadBridge() = default;
    DownloadBridge(const DownloadBridge&) = delete;
    DownloadBridge& operator=(const DownloadBridge&) = delete;

    std::map<std::string, DownloadProgress> activeDownloads_;
    int taskIdCounter_ = 0;
};

} // namespace bridges
} // namespace runanywhere
