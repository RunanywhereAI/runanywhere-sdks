/**
 * @file CompatibilityBridge.cpp
 * @brief C++ bridge for model compatibility checks.
 *
 * Uses DeviceBridge for RAM and POSIX statvfs for disk space,
 * then calls rac_model_check_compatibility() from runanywhere-commons.
 */

#include "CompatibilityBridge.hpp"
#include "DeviceBridge.hpp"

#include <sys/statvfs.h>  // POSIX filesystem statistics

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "CompatibilityBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[CompatibilityBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[CompatibilityBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[CompatibilityBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

CompatibilityResult CompatibilityBridge::checkCompatibility(
    const std::string& modelId,
    rac_model_registry_handle_t registryHandle) {
    
    CompatibilityResult result;

    if (!registryHandle) {
        LOGE("Model registry handle is null");
        return result;
    }

    // Get available RAM from DeviceBridge
    int64_t availableRAM = 0;
    if (DeviceBridge::shared().isCallbacksRegistered()) {
        auto deviceInfo = DeviceBridge::shared().getDeviceInfo();
        availableRAM = deviceInfo.availableMemory;
        LOGD("Available RAM from DeviceBridge: %lld bytes", 
             static_cast<long long>(availableRAM));
    } else {
        LOGD("DeviceBridge not initialized, RAM check will be skipped");
    }

    // Get available storage using POSIX statvfs
    // This queries the filesystem directly - same as what FileManager/StatFs use underneath
    int64_t availableStorage = 0;
    {
        struct statvfs stat;
        // Query root filesystem - works on both iOS and Android
        if (statvfs("/", &stat) == 0) {
            // f_bavail = available blocks for unprivileged users
            // f_frsize = fragment size (fundamental block size)
            availableStorage = static_cast<int64_t>(stat.f_bavail) * static_cast<int64_t>(stat.f_frsize);
            
            LOGD("Available storage from statvfs: %lld bytes (%.2f GB)",
                 static_cast<long long>(availableStorage),
                 static_cast<double>(availableStorage) / (1024.0 * 1024.0 * 1024.0));
        } else {
            LOGE("statvfs failed (errno=%d), storage check will be skipped", errno);
        }
    }

    // Call the RACommons C API
    rac_model_compatibility_result_t cResult;
    rac_result_t rc = rac_model_check_compatibility(
        registryHandle,
        modelId.c_str(),
        availableRAM,
        availableStorage,
        &cResult);

    if (rc == RAC_SUCCESS) {
        result.isCompatible = cResult.is_compatible == RAC_TRUE;
        result.canRun = cResult.can_run == RAC_TRUE;
        result.canFit = cResult.can_fit == RAC_TRUE;
        result.requiredMemory = cResult.required_memory;
        result.availableMemory = cResult.available_memory;
        result.requiredStorage = cResult.required_storage;
        result.availableStorage = cResult.available_storage;
        
        LOGI("Compatibility check for %s: compatible=%d, canRun=%d, canFit=%d, RAM=%lld/%lld, Storage=%lld/%lld",
             modelId.c_str(), 
             result.isCompatible, 
             result.canRun, 
             result.canFit,
             static_cast<long long>(result.availableMemory),
             static_cast<long long>(result.requiredMemory),
             static_cast<long long>(result.availableStorage),
             static_cast<long long>(result.requiredStorage));
    } else {
        LOGE("Compatibility check failed for %s: error %d", modelId.c_str(), rc);
    }

    return result;
}

} // namespace bridges
} // namespace runanywhere