/**
 * @file DownloadBridge.cpp
 * @brief Download-manager lifecycle bridge.
 *
 * Mirrors Swift's CppBridge+Download.swift pattern.
 */

#include "DownloadBridge.hpp"

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
        LOGI("Download manager destroyed");
    }
}

} // namespace bridges
} // namespace runanywhere
