/**
 * @file InitBridge.cpp
 * @brief SDK initialization bridge implementation
 *
 * Implements platform adapter registration and SDK initialization.
 * Mirrors Swift's CppBridge.initialize() pattern.
 */

#include "InitBridge.hpp"
#include "rac_model_paths.h"
#include <cstring>
#include <cstdlib>
#include <chrono>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "InitBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[InitBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[InitBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[InitBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// Static storage for callbacks (needed for C function pointers)
// =============================================================================

static PlatformCallbacks* g_platformCallbacks = nullptr;

// =============================================================================
// C Callback Implementations (called by RACommons)
// =============================================================================

static rac_bool_t platformFileExistsCallback(const char* path, void* userData) {
    if (!path || !g_platformCallbacks || !g_platformCallbacks->fileExists) {
        return RAC_FALSE;
    }
    return g_platformCallbacks->fileExists(path) ? RAC_TRUE : RAC_FALSE;
}

static rac_result_t platformFileReadCallback(
    const char* path,
    void** outData,
    size_t* outSize,
    void* userData
) {
    if (!path || !outData || !outSize) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->fileRead) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        std::string content = g_platformCallbacks->fileRead(path);
        if (content.empty()) {
            return RAC_ERROR_FILE_NOT_FOUND;
        }

        // Allocate buffer and copy data
        char* buffer = static_cast<char*>(malloc(content.size()));
        if (!buffer) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        memcpy(buffer, content.data(), content.size());
        *outData = buffer;
        *outSize = content.size();

        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
}

static rac_result_t platformFileWriteCallback(
    const char* path,
    const void* data,
    size_t size,
    void* userData
) {
    if (!path || !data) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->fileWrite) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        std::string content(static_cast<const char*>(data), size);
        bool success = g_platformCallbacks->fileWrite(path, content);
        return success ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
    } catch (...) {
        return RAC_ERROR_FILE_WRITE_FAILED;
    }
}

static rac_result_t platformFileDeleteCallback(const char* path, void* userData) {
    if (!path) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->fileDelete) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        bool success = g_platformCallbacks->fileDelete(path);
        return success ? RAC_SUCCESS : RAC_ERROR_FILE_NOT_FOUND;
    } catch (...) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
}

static rac_result_t platformSecureGetCallback(
    const char* key,
    char** outValue,
    void* userData
) {
    if (!key || !outValue) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->secureGet) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        std::string value = g_platformCallbacks->secureGet(key);
        if (value.empty()) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }

        *outValue = strdup(value.c_str());
        return *outValue ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
}

static rac_result_t platformSecureSetCallback(
    const char* key,
    const char* value,
    void* userData
) {
    if (!key || !value) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->secureSet) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        bool success = g_platformCallbacks->secureSet(key, value);
        return success ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
    } catch (...) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
}

static rac_result_t platformSecureDeleteCallback(const char* key, void* userData) {
    if (!key) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (!g_platformCallbacks || !g_platformCallbacks->secureDelete) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    try {
        bool success = g_platformCallbacks->secureDelete(key);
        return success ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
    } catch (...) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
}

static void platformLogCallback(
    rac_log_level_t level,
    const char* category,
    const char* message,
    void* userData
) {
    if (!message) return;

    // Always log to Android/iOS native logging
    const char* levelStr = "INFO";
    switch (level) {
        case RAC_LOG_TRACE: levelStr = "TRACE"; break;
        case RAC_LOG_DEBUG: levelStr = "DEBUG"; break;
        case RAC_LOG_INFO: levelStr = "INFO"; break;
        case RAC_LOG_WARNING: levelStr = "WARN"; break;
        case RAC_LOG_ERROR: levelStr = "ERROR"; break;
        case RAC_LOG_FATAL: levelStr = "FATAL"; break;
    }

    const char* cat = category ? category : "RAC";

#if defined(ANDROID) || defined(__ANDROID__)
    int androidLevel = ANDROID_LOG_INFO;
    switch (level) {
        case RAC_LOG_TRACE:
        case RAC_LOG_DEBUG: androidLevel = ANDROID_LOG_DEBUG; break;
        case RAC_LOG_INFO: androidLevel = ANDROID_LOG_INFO; break;
        case RAC_LOG_WARNING: androidLevel = ANDROID_LOG_WARN; break;
        case RAC_LOG_ERROR:
        case RAC_LOG_FATAL: androidLevel = ANDROID_LOG_ERROR; break;
    }
    __android_log_print(androidLevel, cat, "%s", message);
#else
    printf("[%s] [%s] %s\n", levelStr, cat, message);
#endif

    // Also forward to JS callback if available
    if (g_platformCallbacks && g_platformCallbacks->log) {
        g_platformCallbacks->log(static_cast<int>(level), cat, message);
    }
}

static int64_t platformNowMsCallback(void* userData) {
    if (g_platformCallbacks && g_platformCallbacks->nowMs) {
        return g_platformCallbacks->nowMs();
    }

    // Fallback to system time
    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()
    ).count();
    return static_cast<int64_t>(ms);
}

static rac_result_t platformGetMemoryInfoCallback(rac_memory_info_t* outInfo, void* userData) {
    // Memory info not easily available in React Native
    // Return not supported - platform can query via JS if needed
    return RAC_ERROR_NOT_SUPPORTED;
}

static void platformTrackErrorCallback(const char* errorJson, void* userData) {
    // Forward error tracking to logging for now
    if (errorJson) {
        LOGE("Track error: %s", errorJson);
    }
}

// =============================================================================
// InitBridge Implementation
// =============================================================================

InitBridge& InitBridge::shared() {
    static InitBridge instance;
    return instance;
}

InitBridge::~InitBridge() {
    shutdown();
}

void InitBridge::setPlatformCallbacks(const PlatformCallbacks& callbacks) {
    callbacks_ = callbacks;

    // Store in global for C callbacks
    static PlatformCallbacks storedCallbacks;
    storedCallbacks = callbacks_;
    g_platformCallbacks = &storedCallbacks;

    LOGI("Platform callbacks registered");
}

void InitBridge::registerPlatformAdapter() {
    if (adapterRegistered_) {
        return;
    }

    // Reset adapter
    memset(&adapter_, 0, sizeof(adapter_));

    // File operations
    adapter_.file_exists = platformFileExistsCallback;
    adapter_.file_read = platformFileReadCallback;
    adapter_.file_write = platformFileWriteCallback;
    adapter_.file_delete = platformFileDeleteCallback;

    // Secure storage
    adapter_.secure_get = platformSecureGetCallback;
    adapter_.secure_set = platformSecureSetCallback;
    adapter_.secure_delete = platformSecureDeleteCallback;

    // Logging
    adapter_.log = platformLogCallback;

    // Clock
    adapter_.now_ms = platformNowMsCallback;

    // Memory info (not implemented)
    adapter_.get_memory_info = platformGetMemoryInfoCallback;

    // Error tracking
    adapter_.track_error = platformTrackErrorCallback;

    // HTTP download (handled by JS layer)
    adapter_.http_download = nullptr;
    adapter_.http_download_cancel = nullptr;

    // Archive extraction (handled by JS layer)
    adapter_.extract_archive = nullptr;

    adapter_.user_data = nullptr;

    // Register with RACommons
    rac_result_t result = rac_set_platform_adapter(&adapter_);
    if (result == RAC_SUCCESS) {
        adapterRegistered_ = true;
        LOGI("Platform adapter registered with RACommons");
    } else {
        LOGE("Failed to register platform adapter: %d", result);
    }
}

rac_environment_t InitBridge::toRacEnvironment(SDKEnvironment env) {
    switch (env) {
        case SDKEnvironment::Development:
            return RAC_ENV_DEVELOPMENT;
        case SDKEnvironment::Staging:
            return RAC_ENV_STAGING;
        case SDKEnvironment::Production:
            return RAC_ENV_PRODUCTION;
        default:
            return RAC_ENV_DEVELOPMENT;
    }
}

rac_result_t InitBridge::initialize(
    SDKEnvironment environment,
    const std::string& apiKey,
    const std::string& baseURL,
    const std::string& deviceId
) {
    if (initialized_) {
        LOGI("SDK already initialized");
        return RAC_SUCCESS;
    }

    environment_ = environment;
    apiKey_ = apiKey;
    baseURL_ = baseURL;
    deviceId_ = deviceId;

    // Step 1: Register platform adapter FIRST
    registerPlatformAdapter();

    // Step 2: Configure logging based on environment
    rac_environment_t racEnv = toRacEnvironment(environment);
    rac_result_t logResult = rac_configure_logging(racEnv);
    if (logResult != RAC_SUCCESS) {
        LOGE("Failed to configure logging: %d", logResult);
        // Continue anyway - logging is not critical
    }

    // Step 3: Initialize RACommons using rac_init
    // NOTE: rac_init takes a config struct, not individual parameters
    // The actual auth/state management is done at the platform level
    rac_config_t config = {};
    config.platform_adapter = &adapter_;
    config.log_level = RAC_LOG_INFO;
    config.log_tag = "RunAnywhere";
    config.reserved = nullptr;

    rac_result_t initResult = rac_init(&config);

    if (initResult != RAC_SUCCESS) {
        LOGE("Failed to initialize RACommons: %d", initResult);
        return initResult;
    }

    initialized_ = true;
    LOGI("SDK initialized successfully for environment %d", static_cast<int>(environment));

    return RAC_SUCCESS;
}

rac_result_t InitBridge::setBaseDirectory(const std::string& documentsPath) {
    if (documentsPath.empty()) {
        LOGE("Base directory path is empty");
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = rac_model_paths_set_base_dir(documentsPath.c_str());
    if (result == RAC_SUCCESS) {
        LOGI("Model paths base directory set to: %s", documentsPath.c_str());
    } else {
        LOGE("Failed to set model paths base directory: %d", result);
    }

    return result;
}

void InitBridge::shutdown() {
    if (!initialized_) {
        return;
    }

    LOGI("Shutting down SDK...");

    // Shutdown RACommons
    rac_shutdown();

    // Note: Platform adapter callbacks remain valid (static)

    initialized_ = false;
    LOGI("SDK shutdown complete");
}

} // namespace bridges
} // namespace runanywhere
