/**
 * @file InitBridge.cpp
 * @brief SDK initialization bridge implementation
 *
 * Implements platform adapter registration and SDK initialization.
 * Mirrors Swift's CppBridge.initialize() pattern.
 */

#include "InitBridge.hpp"
#include "rac_model_paths.h"
#include "rac_environment.h"  // For rac_sdk_init, rac_sdk_config_t
#include <cstring>
#include <cstdlib>
#include <chrono>
#include <mutex>
#include <tuple>

// Platform-specific logging and bridges
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#include <jni.h>
#define LOG_TAG "InitBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Global JavaVM for JNI calls
static JavaVM* g_javaVM = nullptr;

// JNI_OnLoad - called when native library is loaded
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_javaVM = vm;
    LOGI("JNI_OnLoad: JavaVM stored for secure storage callbacks");
    return JNI_VERSION_1_6;
}

// Helper to get JNIEnv for current thread
static JNIEnv* getJNIEnv() {
    if (!g_javaVM) {
        LOGE("JavaVM not initialized");
        return nullptr;
    }
    
    JNIEnv* env = nullptr;
    int status = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    
    if (status == JNI_EDETACHED) {
        // Attach current thread
        if (g_javaVM->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGE("Failed to attach current thread to JVM");
            return nullptr;
        }
    } else if (status != JNI_OK) {
        LOGE("Failed to get JNI environment: %d", status);
        return nullptr;
    }
    
    return env;
}

// Android JNI bridge for secure storage
namespace AndroidBridge {
    bool secureSet(const char* key, const char* value) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) {
            LOGE("Failed to find PlatformAdapterBridge class");
            return false;
        }
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
        if (!method) {
            LOGE("Failed to find secureSet method");
            return false;
        }
        
        jstring jKey = env->NewStringUTF(key);
        jstring jValue = env->NewStringUTF(value);
        jboolean result = env->CallStaticBooleanMethod(bridgeClass, method, jKey, jValue);
        
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(jValue);
        env->DeleteLocalRef(bridgeClass);
        
        return result;
    }
    
    bool secureGet(const char* key, std::string& outValue) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) {
            LOGE("Failed to find PlatformAdapterBridge class");
            return false;
        }
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
        if (!method) {
            LOGE("Failed to find secureGet method");
            return false;
        }
        
        jstring jKey = env->NewStringUTF(key);
        jstring jResult = (jstring)env->CallStaticObjectMethod(bridgeClass, method, jKey);
        
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(bridgeClass);
        
        if (jResult == nullptr) {
            return false;
        }
        
        const char* resultStr = env->GetStringUTFChars(jResult, nullptr);
        if (resultStr) {
            outValue = resultStr;
            env->ReleaseStringUTFChars(jResult, resultStr);
        }
        env->DeleteLocalRef(jResult);
        
        return !outValue.empty();
    }
    
    bool secureDelete(const char* key) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return false;
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "secureDelete", "(Ljava/lang/String;)Z");
        if (!method) return false;
        
        jstring jKey = env->NewStringUTF(key);
        jboolean result = env->CallStaticBooleanMethod(bridgeClass, method, jKey);
        
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(bridgeClass);
        
        return result;
    }
    
    bool secureExists(const char* key) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return false;
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "secureExists", "(Ljava/lang/String;)Z");
        if (!method) return false;
        
        jstring jKey = env->NewStringUTF(key);
        jboolean result = env->CallStaticBooleanMethod(bridgeClass, method, jKey);
        
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(bridgeClass);
        
        return result;
    }
    
    std::string getPersistentDeviceUUID() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "";
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return "";
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getPersistentDeviceUUID", "()Ljava/lang/String;");
        if (!method) return "";
        
        jstring jResult = (jstring)env->CallStaticObjectMethod(bridgeClass, method);
        if (!jResult) return "";
        
        const char* resultStr = env->GetStringUTFChars(jResult, nullptr);
        std::string uuid = resultStr ? resultStr : "";
        
        if (resultStr) env->ReleaseStringUTFChars(jResult, resultStr);
        env->DeleteLocalRef(jResult);
        env->DeleteLocalRef(bridgeClass);
        
        return uuid;
    }

    // HTTP POST for device registration (synchronous)
    // Returns: (success, statusCode, responseBody, errorMessage)
    std::tuple<bool, int, std::string, std::string> httpPostSync(
        const std::string& url,
        const std::string& jsonBody,
        const std::string& supabaseKey
    ) {
        JNIEnv* env = getJNIEnv();
        if (!env) {
            return {false, 0, "", "JNI not available"};
        }
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) {
            return {false, 0, "", "Bridge class not found"};
        }
        
        // Get the HttpResponse inner class
        jclass responseClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge$HttpResponse");
        if (!responseClass) {
            env->DeleteLocalRef(bridgeClass);
            return {false, 0, "", "HttpResponse class not found"};
        }
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "httpPostSync",
            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lcom/margelo/nitro/runanywhere/PlatformAdapterBridge$HttpResponse;");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            env->DeleteLocalRef(responseClass);
            return {false, 0, "", "httpPostSync method not found"};
        }
        
        jstring jUrl = env->NewStringUTF(url.c_str());
        jstring jBody = env->NewStringUTF(jsonBody.c_str());
        jstring jKey = supabaseKey.empty() ? nullptr : env->NewStringUTF(supabaseKey.c_str());
        
        jobject response = env->CallStaticObjectMethod(bridgeClass, method, jUrl, jBody, jKey);
        
        env->DeleteLocalRef(jUrl);
        env->DeleteLocalRef(jBody);
        if (jKey) env->DeleteLocalRef(jKey);
        
        if (!response) {
            env->DeleteLocalRef(bridgeClass);
            env->DeleteLocalRef(responseClass);
            return {false, 0, "", "httpPostSync returned null"};
        }
        
        // Extract fields from HttpResponse
        jfieldID successField = env->GetFieldID(responseClass, "success", "Z");
        jfieldID statusCodeField = env->GetFieldID(responseClass, "statusCode", "I");
        jfieldID responseBodyField = env->GetFieldID(responseClass, "responseBody", "Ljava/lang/String;");
        jfieldID errorMessageField = env->GetFieldID(responseClass, "errorMessage", "Ljava/lang/String;");
        
        bool success = env->GetBooleanField(response, successField);
        int statusCode = env->GetIntField(response, statusCodeField);
        
        std::string responseBody;
        jstring jResponseBody = (jstring)env->GetObjectField(response, responseBodyField);
        if (jResponseBody) {
            const char* str = env->GetStringUTFChars(jResponseBody, nullptr);
            if (str) {
                responseBody = str;
                env->ReleaseStringUTFChars(jResponseBody, str);
            }
            env->DeleteLocalRef(jResponseBody);
        }
        
        std::string errorMessage;
        jstring jErrorMessage = (jstring)env->GetObjectField(response, errorMessageField);
        if (jErrorMessage) {
            const char* str = env->GetStringUTFChars(jErrorMessage, nullptr);
            if (str) {
                errorMessage = str;
                env->ReleaseStringUTFChars(jErrorMessage, str);
            }
            env->DeleteLocalRef(jErrorMessage);
        }
        
        env->DeleteLocalRef(response);
        env->DeleteLocalRef(bridgeClass);
        env->DeleteLocalRef(responseClass);
        
        return {success, statusCode, responseBody, errorMessage};
    }

    // Device info methods
    std::string getDeviceModel() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "Unknown";
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return "Unknown";
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getDeviceModel", "()Ljava/lang/String;");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return "Unknown";
        }
        
        jstring result = (jstring)env->CallStaticObjectMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        if (!result) return "Unknown";
        
        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string modelName = str ? str : "Unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);
        
        return modelName;
    }

    std::string getOSVersion() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "Unknown";
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return "Unknown";
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getOSVersion", "()Ljava/lang/String;");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return "Unknown";
        }
        
        jstring result = (jstring)env->CallStaticObjectMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        if (!result) return "Unknown";
        
        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string version = str ? str : "Unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);
        
        return version;
    }

    std::string getChipName() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "Unknown";
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return "Unknown";
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getChipName", "()Ljava/lang/String;");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return "Unknown";
        }
        
        jstring result = (jstring)env->CallStaticObjectMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        if (!result) return "Unknown";
        
        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string chipName = str ? str : "Unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);
        
        return chipName;
    }

    uint64_t getTotalMemory() {
        JNIEnv* env = getJNIEnv();
        if (!env) return 0;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return 0;
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getTotalMemory", "()J");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return 0;
        }
        
        jlong result = env->CallStaticLongMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        return static_cast<uint64_t>(result);
    }

    uint64_t getAvailableMemory() {
        JNIEnv* env = getJNIEnv();
        if (!env) return 0;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return 0;
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getAvailableMemory", "()J");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return 0;
        }
        
        jlong result = env->CallStaticLongMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        return static_cast<uint64_t>(result);
    }

    int getCoreCount() {
        JNIEnv* env = getJNIEnv();
        if (!env) return 1;
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return 1;
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getCoreCount", "()I");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return 1;
        }
        
        jint result = env->CallStaticIntMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        return static_cast<int>(result);
    }

    std::string getArchitecture() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "unknown";
        
        jclass bridgeClass = env->FindClass("com/margelo/nitro/runanywhere/PlatformAdapterBridge");
        if (!bridgeClass) return "unknown";
        
        jmethodID method = env->GetStaticMethodID(bridgeClass, "getArchitecture", "()Ljava/lang/String;");
        if (!method) {
            env->DeleteLocalRef(bridgeClass);
            return "unknown";
        }
        
        jstring result = (jstring)env->CallStaticObjectMethod(bridgeClass, method);
        env->DeleteLocalRef(bridgeClass);
        
        if (!result) return "unknown";
        
        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string arch = str ? str : "unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);
        
        return arch;
    }
} // namespace AndroidBridge
#elif defined(__APPLE__)
#include <cstdio>
// iOS platform bridge for Keychain, HTTP, and Device Info
extern "C" {
    // Secure storage
    bool PlatformAdapter_secureSet(const char* key, const char* value);
    bool PlatformAdapter_secureGet(const char* key, char** outValue);
    bool PlatformAdapter_secureDelete(const char* key);
    bool PlatformAdapter_secureExists(const char* key);
    bool PlatformAdapter_getPersistentDeviceUUID(char** outValue);
    
    // Device info (synchronous)
    bool PlatformAdapter_getDeviceModel(char** outValue);
    bool PlatformAdapter_getOSVersion(char** outValue);
    bool PlatformAdapter_getChipName(char** outValue);
    uint64_t PlatformAdapter_getTotalMemory(void);
    uint64_t PlatformAdapter_getAvailableMemory(void);
    int PlatformAdapter_getCoreCount(void);
    bool PlatformAdapter_getArchitecture(char** outValue);
    
    // HTTP
    bool PlatformAdapter_httpPostSync(
        const char* url,
        const char* jsonBody,
        const char* supabaseKey,
        int* outStatusCode,
        char** outResponseBody,
        char** outErrorMessage
    );
}
#define LOGI(...) printf("[InitBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[InitBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[InitBridge WARN] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[InitBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#else
#include <cstdio>
#define LOGI(...) printf("[InitBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[InitBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[InitBridge WARN] "); printf(__VA_ARGS__); printf("\n")
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

    // Step 4: Initialize SDK config with version (required for device registration)
    // This populates rac_sdk_get_config() which device registration uses
    // Matches Swift: CppBridge+State.swift initialize()
    rac_sdk_config_t sdkConfig = {};
    sdkConfig.platform = "react-native";
    sdkConfig.sdk_version = "0.2.0";  // TODO: Make configurable
    sdkConfig.device_id = getPersistentDeviceUUID().c_str();
    
    rac_validation_result_t validResult = rac_sdk_init(&sdkConfig);
    if (validResult != RAC_VALIDATION_OK) {
        LOGW("SDK config validation warning: %d (non-fatal)", validResult);
        // Non-fatal - device registration can still work without this
    } else {
        LOGI("SDK config initialized with version: %s", sdkConfig.sdk_version);
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

// =============================================================================
// Secure Storage Methods
// Matches Swift: KeychainManager
// =============================================================================

bool InitBridge::secureSet(const std::string& key, const std::string& value) {
#if defined(__APPLE__)
    // Use iOS Keychain bridge directly
    bool success = PlatformAdapter_secureSet(key.c_str(), value.c_str());
    LOGD("secureSet (iOS): key=%s, success=%d", key.c_str(), success);
    return success;
#elif defined(ANDROID) || defined(__ANDROID__)
    // Use Android JNI bridge
    bool success = AndroidBridge::secureSet(key.c_str(), value.c_str());
    LOGD("secureSet (Android): key=%s, success=%d", key.c_str(), success);
    return success;
#else
    if (!g_platformCallbacks || !g_platformCallbacks->secureSet) {
        LOGE("secureSet: Platform callback not available");
        return false;
    }

    try {
        bool success = g_platformCallbacks->secureSet(key, value);
        LOGD("secureSet: key=%s, success=%d", key.c_str(), success);
        return success;
    } catch (...) {
        LOGE("secureSet: Exception for key=%s", key.c_str());
        return false;
    }
#endif
}

bool InitBridge::secureGet(const std::string& key, std::string& outValue) {
#if defined(__APPLE__)
    // Use iOS Keychain bridge directly
    char* value = nullptr;
    bool success = PlatformAdapter_secureGet(key.c_str(), &value);
    if (success && value != nullptr) {
        outValue = value;
        free(value);
        LOGD("secureGet (iOS): key=%s found", key.c_str());
        return true;
    }
    LOGD("secureGet (iOS): key=%s not found", key.c_str());
    return false;
#elif defined(ANDROID) || defined(__ANDROID__)
    // Use Android JNI bridge
    bool success = AndroidBridge::secureGet(key.c_str(), outValue);
    LOGD("secureGet (Android): key=%s, found=%d", key.c_str(), success);
    return success;
#else
    if (!g_platformCallbacks || !g_platformCallbacks->secureGet) {
        LOGE("secureGet: Platform callback not available");
        return false;
    }

    try {
        std::string value = g_platformCallbacks->secureGet(key);
        if (value.empty()) {
            LOGD("secureGet: key=%s not found", key.c_str());
            return false;
        }
        outValue = value;
        LOGD("secureGet: key=%s found", key.c_str());
        return true;
    } catch (...) {
        LOGE("secureGet: Exception for key=%s", key.c_str());
        return false;
    }
#endif
}

bool InitBridge::secureDelete(const std::string& key) {
#if defined(__APPLE__)
    // Use iOS Keychain bridge directly
    bool success = PlatformAdapter_secureDelete(key.c_str());
    LOGD("secureDelete (iOS): key=%s, success=%d", key.c_str(), success);
    return success;
#elif defined(ANDROID) || defined(__ANDROID__)
    // Use Android JNI bridge
    bool success = AndroidBridge::secureDelete(key.c_str());
    LOGD("secureDelete (Android): key=%s, success=%d", key.c_str(), success);
    return success;
#else
    if (!g_platformCallbacks || !g_platformCallbacks->secureDelete) {
        LOGE("secureDelete: Platform callback not available");
        return false;
    }

    try {
        bool success = g_platformCallbacks->secureDelete(key);
        LOGD("secureDelete: key=%s, success=%d", key.c_str(), success);
        return success;
    } catch (...) {
        LOGE("secureDelete: Exception for key=%s", key.c_str());
        return false;
    }
#endif
}

bool InitBridge::secureExists(const std::string& key) {
#if defined(__APPLE__)
    // Use iOS Keychain bridge directly
    bool exists = PlatformAdapter_secureExists(key.c_str());
    LOGD("secureExists (iOS): key=%s, exists=%d", key.c_str(), exists);
    return exists;
#elif defined(ANDROID) || defined(__ANDROID__)
    // Use Android JNI bridge
    bool exists = AndroidBridge::secureExists(key.c_str());
    LOGD("secureExists (Android): key=%s, exists=%d", key.c_str(), exists);
    return exists;
#else
    if (!g_platformCallbacks || !g_platformCallbacks->secureGet) {
        LOGE("secureExists: Platform callback not available");
        return false;
    }

    try {
        std::string value = g_platformCallbacks->secureGet(key);
        bool exists = !value.empty();
        LOGD("secureExists: key=%s, exists=%d", key.c_str(), exists);
        return exists;
    } catch (...) {
        LOGE("secureExists: Exception for key=%s", key.c_str());
        return false;
    }
#endif
}

std::string InitBridge::getPersistentDeviceUUID() {
    // Key matches Swift: KeychainManager.KeychainKey.deviceUUID
    static const char* DEVICE_UUID_KEY = "com.runanywhere.sdk.device.uuid";

    // Thread-safe: cached result (matches Swift pattern)
    static std::string cachedUUID;
    static std::mutex uuidMutex;

    {
        std::lock_guard<std::mutex> lock(uuidMutex);
        if (!cachedUUID.empty()) {
            return cachedUUID;
        }
    }

    // Strategy 1: Try to load from secure storage (survives reinstalls)
    std::string storedUUID;
    if (secureGet(DEVICE_UUID_KEY, storedUUID) && !storedUUID.empty()) {
        std::lock_guard<std::mutex> lock(uuidMutex);
        cachedUUID = storedUUID;
        LOGI("Loaded persistent device UUID from keychain");
        return cachedUUID;
    }

    // Strategy 2: Generate new UUID
    // Generate a UUID4-like string: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    auto generateUUID = []() -> std::string {
        static const char hexChars[] = "0123456789abcdef";

        // Use high-resolution clock and random for seeding
        auto now = std::chrono::high_resolution_clock::now();
        auto seed = static_cast<unsigned>(
            now.time_since_epoch().count() ^
            reinterpret_cast<uintptr_t>(&now)
        );
        srand(seed);

        char uuid[37];
        for (int i = 0; i < 36; i++) {
            if (i == 8 || i == 13 || i == 18 || i == 23) {
                uuid[i] = '-';
            } else if (i == 14) {
                uuid[i] = '4'; // UUID version 4
            } else if (i == 19) {
                uuid[i] = hexChars[(rand() & 0x03) | 0x08]; // variant bits
            } else {
                uuid[i] = hexChars[rand() & 0x0F];
            }
        }
        uuid[36] = '\0';
        return std::string(uuid);
    };

    std::string newUUID = generateUUID();

    // Store in secure storage
    if (secureSet(DEVICE_UUID_KEY, newUUID)) {
        LOGI("Generated and stored new persistent device UUID");
    } else {
        LOGW("Generated device UUID but failed to persist (will regenerate on restart)");
    }

    {
        std::lock_guard<std::mutex> lock(uuidMutex);
        cachedUUID = newUUID;
    }

    return newUUID;
}

// =============================================================================
// Device Info (Synchronous)
// For device registration callback which must be synchronous
// =============================================================================

std::string InitBridge::getDeviceModel() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getDeviceModel(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "Unknown";
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getDeviceModel();
#else
    return "Unknown";
#endif
}

std::string InitBridge::getOSVersion() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getOSVersion(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "Unknown";
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getOSVersion();
#else
    return "Unknown";
#endif
}

std::string InitBridge::getChipName() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getChipName(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "Apple Silicon";
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getChipName();
#else
    return "Unknown";
#endif
}

uint64_t InitBridge::getTotalMemory() {
#if defined(__APPLE__)
    return PlatformAdapter_getTotalMemory();
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getTotalMemory();
#else
    return 0;
#endif
}

uint64_t InitBridge::getAvailableMemory() {
#if defined(__APPLE__)
    return PlatformAdapter_getAvailableMemory();
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getAvailableMemory();
#else
    return 0;
#endif
}

int InitBridge::getCoreCount() {
#if defined(__APPLE__)
    return PlatformAdapter_getCoreCount();
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getCoreCount();
#else
    return 1;
#endif
}

std::string InitBridge::getArchitecture() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getArchitecture(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "arm64";
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getArchitecture();
#else
    return "unknown";
#endif
}

// =============================================================================
// HTTP POST for Device Registration (Synchronous)
// Matches Swift: CppBridge+Device.swift http_post callback
// =============================================================================

std::tuple<bool, int, std::string, std::string> InitBridge::httpPostSync(
    const std::string& url,
    const std::string& jsonBody,
    const std::string& supabaseKey
) {
    LOGI("httpPostSync to: %s", url.c_str());

#if defined(ANDROID) || defined(__ANDROID__)
    // Android: Call JNI to PlatformAdapterBridge.httpPostSync
    return AndroidBridge::httpPostSync(url, jsonBody, supabaseKey);

#elif defined(__APPLE__)
    // iOS: Call PlatformAdapter_httpPostSync via extern C
    int statusCode = 0;
    char* responseBody = nullptr;
    char* errorMessage = nullptr;

    bool success = PlatformAdapter_httpPostSync(
        url.c_str(),
        jsonBody.c_str(),
        supabaseKey.empty() ? nullptr : supabaseKey.c_str(),
        &statusCode,
        &responseBody,
        &errorMessage
    );

    std::string responseBodyStr = responseBody ? responseBody : "";
    std::string errorMessageStr = errorMessage ? errorMessage : "";

    // Free allocated strings
    if (responseBody) free(responseBody);
    if (errorMessage) free(errorMessage);

    LOGI("httpPostSync result: success=%d statusCode=%d", success, statusCode);
    return {success, statusCode, responseBodyStr, errorMessageStr};

#else
    // Unsupported platform
    LOGE("httpPostSync: Unsupported platform");
    return {false, 0, "", "Unsupported platform"};
#endif
}

} // namespace bridges
} // namespace runanywhere
