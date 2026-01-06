/**
 * @file DownloadBridge.cpp
 * @brief C++ bridge for download operations.
 *
 * Mirrors Swift's CppBridge+Download.swift pattern.
 */

#include "DownloadBridge.hpp"
#include <cstdlib>
#include <cstring>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "DownloadBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[DownloadBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[DownloadBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[DownloadBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

DownloadBridge& DownloadBridge::shared() {
    static DownloadBridge instance;
    return instance;
}

DownloadBridge::~DownloadBridge() {
    shutdown();
}

rac_result_t DownloadBridge::initialize(const DownloadConfig* config) {
    if (handle_) {
        LOGD("Download manager already initialized");
        return RAC_SUCCESS;
    }

    // Setup config if provided
    const rac_download_config_t* racConfig = nullptr;
    rac_download_config_t configStruct = RAC_DOWNLOAD_CONFIG_DEFAULT;

    if (config) {
        configStruct.max_concurrent_downloads = config->maxConcurrentDownloads;
        configStruct.request_timeout_seconds = config->requestTimeoutSeconds;
        configStruct.max_retry_attempts = config->maxRetryAttempts;
        configStruct.retry_delay_seconds = config->retryDelaySeconds;
        configStruct.allow_cellular = config->allowCellular ? RAC_TRUE : RAC_FALSE;
        configStruct.allow_constrained_network = config->allowConstrainedNetwork ? RAC_TRUE : RAC_FALSE;
        racConfig = &configStruct;
    }

    // Create manager
    rac_result_t result = rac_download_manager_create(racConfig, &handle_);

    if (result == RAC_SUCCESS) {
        LOGI("Download manager created successfully");
    } else {
        LOGE("Failed to create download manager: %d", result);
        handle_ = nullptr;
    }

    return result;
}

void DownloadBridge::shutdown() {
    if (handle_) {
        rac_download_manager_destroy(handle_);
        handle_ = nullptr;
        progressCallbacks_.clear();
        LOGI("Download manager destroyed");
    }
}

std::string DownloadBridge::startDownload(
    const std::string& modelId,
    const std::string& url,
    const std::string& destinationPath,
    bool requiresExtraction,
    std::function<void(const DownloadProgress&)> progressHandler
) {
    if (!handle_) {
        LOGE("Download manager not initialized");
        return "";
    }

    char* taskIdPtr = nullptr;

    rac_result_t result = rac_download_manager_start(
        handle_,
        modelId.c_str(),
        url.c_str(),
        destinationPath.c_str(),
        requiresExtraction ? RAC_TRUE : RAC_FALSE,
        nullptr,  // Progress callback - we poll instead
        nullptr,  // Complete callback - we poll instead
        nullptr,  // User data
        &taskIdPtr
    );

    if (result != RAC_SUCCESS || !taskIdPtr) {
        LOGE("Failed to start download: %d", result);
        return "";
    }

    std::string taskId(taskIdPtr);
    free(taskIdPtr);

    // Store progress callback
    if (progressHandler) {
        progressCallbacks_[taskId] = progressHandler;
    }

    LOGI("Started download task: %s for model: %s", taskId.c_str(), modelId.c_str());
    return taskId;
}

rac_result_t DownloadBridge::cancelDownload(const std::string& taskId) {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t result = rac_download_manager_cancel(handle_, taskId.c_str());

    if (result == RAC_SUCCESS) {
        progressCallbacks_.erase(taskId);
        LOGI("Cancelled download task: %s", taskId.c_str());
    } else {
        LOGE("Failed to cancel download %s: %d", taskId.c_str(), result);
    }

    return result;
}

rac_result_t DownloadBridge::pauseAll() {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t result = rac_download_manager_pause_all(handle_);

    if (result == RAC_SUCCESS) {
        LOGI("Paused all downloads");
    } else {
        LOGE("Failed to pause downloads: %d", result);
    }

    return result;
}

rac_result_t DownloadBridge::resumeAll() {
    if (!handle_) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t result = rac_download_manager_resume_all(handle_);

    if (result == RAC_SUCCESS) {
        LOGI("Resumed all downloads");
    } else {
        LOGE("Failed to resume downloads: %d", result);
    }

    return result;
}

DownloadProgress DownloadBridge::fromRac(const rac_download_progress_t& cProgress) {
    DownloadProgress progress;
    progress.stage = static_cast<DownloadStage>(cProgress.stage);
    progress.bytesDownloaded = cProgress.bytes_downloaded;
    progress.totalBytes = cProgress.total_bytes;
    progress.stageProgress = cProgress.stage_progress;
    progress.overallProgress = cProgress.overall_progress;
    progress.state = static_cast<DownloadState>(cProgress.state);
    progress.speed = cProgress.speed;
    progress.estimatedTimeRemaining = cProgress.estimated_time_remaining;
    progress.retryAttempt = cProgress.retry_attempt;
    progress.errorCode = cProgress.error_code;
    progress.errorMessage = cProgress.error_message ? cProgress.error_message : "";
    return progress;
}

std::optional<DownloadProgress> DownloadBridge::getProgress(const std::string& taskId) {
    if (!handle_) {
        return std::nullopt;
    }

    rac_download_progress_t cProgress = RAC_DOWNLOAD_PROGRESS_DEFAULT;
    rac_result_t result = rac_download_manager_get_progress(handle_, taskId.c_str(), &cProgress);

    if (result != RAC_SUCCESS) {
        return std::nullopt;
    }

    return fromRac(cProgress);
}

std::vector<std::string> DownloadBridge::getActiveTasks() {
    std::vector<std::string> tasks;

    if (!handle_) {
        return tasks;
    }

    char** taskIdsPtr = nullptr;
    size_t count = 0;

    rac_result_t result = rac_download_manager_get_active_tasks(handle_, &taskIdsPtr, &count);

    if (result != RAC_SUCCESS || !taskIdsPtr) {
        return tasks;
    }

    for (size_t i = 0; i < count; i++) {
        if (taskIdsPtr[i]) {
            tasks.push_back(taskIdsPtr[i]);
        }
    }

    rac_download_task_ids_free(taskIdsPtr, count);

    return tasks;
}

bool DownloadBridge::isHealthy() {
    if (!handle_) {
        return false;
    }

    rac_bool_t healthy = RAC_FALSE;
    rac_result_t result = rac_download_manager_is_healthy(handle_, &healthy);

    return result == RAC_SUCCESS && healthy == RAC_TRUE;
}

void DownloadBridge::updateProgress(const std::string& taskId, int64_t bytesDownloaded, int64_t totalBytes) {
    if (!handle_) {
        return;
    }

    rac_download_manager_update_progress(handle_, taskId.c_str(), bytesDownloaded, totalBytes);

    // Notify callback
    auto it = progressCallbacks_.find(taskId);
    if (it != progressCallbacks_.end()) {
        auto progress = getProgress(taskId);
        if (progress) {
            it->second(*progress);
        }
    }
}

void DownloadBridge::markComplete(const std::string& taskId, const std::string& downloadedPath) {
    if (!handle_) {
        return;
    }

    rac_download_manager_mark_complete(handle_, taskId.c_str(), downloadedPath.c_str());

    // Notify final progress
    auto it = progressCallbacks_.find(taskId);
    if (it != progressCallbacks_.end()) {
        auto progress = getProgress(taskId);
        if (progress) {
            it->second(*progress);
        }
        progressCallbacks_.erase(it);
    }

    LOGI("Download completed: %s", taskId.c_str());
}

void DownloadBridge::markFailed(const std::string& taskId, rac_result_t errorCode, const std::string& errorMessage) {
    if (!handle_) {
        return;
    }

    rac_download_manager_mark_failed(handle_, taskId.c_str(), errorCode, errorMessage.c_str());

    // Notify final progress
    auto it = progressCallbacks_.find(taskId);
    if (it != progressCallbacks_.end()) {
        auto progress = getProgress(taskId);
        if (progress) {
            it->second(*progress);
        }
        progressCallbacks_.erase(it);
    }

    LOGE("Download failed: %s - %s", taskId.c_str(), errorMessage.c_str());
}

} // namespace bridges
} // namespace runanywhere
