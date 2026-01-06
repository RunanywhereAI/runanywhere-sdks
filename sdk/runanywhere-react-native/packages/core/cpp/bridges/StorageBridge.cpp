/**
 * @file StorageBridge.cpp
 * @brief Storage management bridge implementation
 */

#include "StorageBridge.hpp"
#include <cstdio>
#include <cstdlib>

#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#include <sys/statvfs.h>
#define LOG_TAG "StorageBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#elif defined(__APPLE__)
#include <sys/statvfs.h>
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#endif

#ifdef HAS_RACOMMONS
#include "rac/infrastructure/storage/rac_storage_analyzer.h"
#endif

namespace runanywhere {
namespace bridges {

StorageBridge& StorageBridge::shared() {
    static StorageBridge instance;
    return instance;
}

StorageInfo StorageBridge::getStorageInfo() {
    StorageInfo info;

#ifdef HAS_RACOMMONS
    rac_storage_info_t cInfo = {};
    if (rac_storage_get_info(&cInfo) == 0) {
        info.totalBytes = cInfo.total_bytes;
        info.availableBytes = cInfo.available_bytes;
        info.usedByModelsBytes = cInfo.models_bytes;
        info.usedByCacheBytes = cInfo.cache_bytes;
    }
#else
    // Fallback: Get basic disk info
#if defined(__APPLE__) || defined(ANDROID) || defined(__ANDROID__)
    struct statvfs stat;
    if (statvfs("/", &stat) == 0) {
        info.totalBytes = static_cast<int64_t>(stat.f_blocks) * stat.f_frsize;
        info.availableBytes = static_cast<int64_t>(stat.f_bavail) * stat.f_frsize;
    }
#endif
#endif

    return info;
}

bool StorageBridge::clearCache() {
    LOGI("Clearing cache...");

#ifdef HAS_RACOMMONS
    return rac_storage_clear_cache() == 0;
#else
    // TODO: Implement cache clearing via platform adapter
    return true;
#endif
}

bool StorageBridge::deleteModel(const std::string& modelId) {
    LOGI("Deleting model: %s", modelId.c_str());

#ifdef HAS_RACOMMONS
    return rac_storage_delete_model(modelId.c_str()) == 0;
#else
    // TODO: Implement via model registry and file system
    return false;
#endif
}

std::string StorageBridge::getModelsDirectory() {
#ifdef HAS_RACOMMONS
    const char* path = rac_storage_get_models_directory();
    return path ? std::string(path) : "";
#else
    return "";
#endif
}

std::string StorageBridge::getCacheDirectory() {
#ifdef HAS_RACOMMONS
    const char* path = rac_storage_get_cache_directory();
    return path ? std::string(path) : "";
#else
    return "";
#endif
}

} // namespace bridges
} // namespace runanywhere
