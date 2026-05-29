/**
 * @file InitBridge.cpp
 * @brief SDK initialization bridge implementation
 *
 * Implements platform adapter registration and SDK initialization.
 * Mirrors Swift's CppBridge.initialize() pattern.
 */

#include "InitBridge.hpp"
#include "AuthBridge.hpp"
#include "DeviceBridge.hpp"
#include "ExternalConfigGuard.hpp"
#include "PlatformDownloadBridge.h"
#include "rac_dev_config.h"
#include "rac_model_paths.h"
#include "rac_environment.h"  // For rac_sdk_init, rac_sdk_config_t
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/device/rac_device_identity.h"  // rac_device_get_or_create_persistent_id

#include <cstddef>

#if __has_include("rac/lifecycle/rac_sdk_init.h")
#include "rac/lifecycle/rac_sdk_init.h"
#define RN_HAS_RAC_SDK_INIT_HEADER 1
#elif __has_include("rac_sdk_init.h")
#include "rac_sdk_init.h"
#define RN_HAS_RAC_SDK_INIT_HEADER 1
#else
#define RN_HAS_RAC_SDK_INIT_HEADER 0
#endif

#if __has_include("rac/foundation/rac_proto_buffer.h")
#include "rac/foundation/rac_proto_buffer.h"
#define RN_HAS_RAC_PROTO_BUFFER_HEADER 1
#elif __has_include("rac_proto_buffer.h")
#include "rac_proto_buffer.h"
#define RN_HAS_RAC_PROTO_BUFFER_HEADER 1
#else
#define RN_HAS_RAC_PROTO_BUFFER_HEADER 0
extern "C" {
typedef struct rac_proto_buffer {
    uint8_t* data;
    size_t size;
    rac_result_t status;
    char* error_message;
} rac_proto_buffer_t;
}
#endif

#include <cstring>
#include <cstdlib>
#include <chrono>
#include <atomic>
#include <cstdint>
#include <dlfcn.h>
#include <functional>
#include <memory>
#include <mutex>
#include <tuple>
#include <unordered_map>
#include <vector>

// Platform-specific logging and bridges
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#include <jni.h>
#define LOG_TAG "InitBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Use the JavaVM from cpp-adapter.cpp (set in JNI_OnLoad there)
// NOTE: JNI_OnLoad is defined in cpp-adapter.cpp - do NOT define it here!
extern JavaVM* g_javaVM;

// Use cached class and method references from cpp-adapter.cpp
// These are set in JNI_OnLoad to avoid FindClass from background threads
extern jclass g_platformAdapterBridgeClass;
extern jmethodID g_secureSetMethod;
extern jmethodID g_secureGetMethod;
extern jmethodID g_secureDeleteMethod;
extern jmethodID g_secureExistsMethod;
extern jmethodID g_getPersistentDeviceUUIDMethod;
extern jmethodID g_getModelBaseDirectoryMethod;
extern jmethodID g_getDeviceModelMethod;
extern jmethodID g_getOSVersionMethod;
extern jmethodID g_getChipNameMethod;
extern jmethodID g_getTotalMemoryMethod;
extern jmethodID g_getAvailableMemoryMethod;
extern jmethodID g_getCoreCountMethod;
extern jmethodID g_getArchitectureMethod;
extern jmethodID g_getGPUFamilyMethod;
extern jmethodID g_isTabletMethod;
extern jmethodID g_httpDownloadMethod;
extern jmethodID g_httpDownloadCancelMethod;
// Directory enumeration slots populated by Kotlin PlatformAdapterBridge so
// the C++ model-registry refresh path (rescan_local) and
// rac_model_info_make_proto's is_downloaded probe for multi-file artifacts
// behave the same on Android as they do on iOS / Web.
extern jmethodID g_fileListDirectoryMethod;
extern jmethodID g_isNonEmptyDirectoryMethod;

// Helper to get JNIEnv for current thread
static JNIEnv* getJNIEnv() {
    if (!g_javaVM) {
        LOGE("JavaVM not initialized - cpp-adapter JNI_OnLoad may not have been called");
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
// Uses cached class/method references from cpp-adapter.cpp to avoid FindClass from bg threads
namespace AndroidBridge {
    bool secureSet(const char* key, const char* value) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;

        // Use cached references from JNI_OnLoad
        if (!g_platformAdapterBridgeClass || !g_secureSetMethod) {
            LOGE("PlatformAdapterBridge class or secureSet method not cached");
            return false;
        }

        jstring jKey = env->NewStringUTF(key);
        jstring jValue = env->NewStringUTF(value);
        jboolean result = env->CallStaticBooleanMethod(g_platformAdapterBridgeClass, g_secureSetMethod, jKey, jValue);

        LOGD("secureSet (Android): key=%s, success=%d", key, result);

        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(jValue);

        return result;
    }

    bool secureGet(const char* key, std::string& outValue) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;

        // Use cached references from JNI_OnLoad
        if (!g_platformAdapterBridgeClass || !g_secureGetMethod) {
            LOGE("PlatformAdapterBridge class or secureGet method not cached");
            return false;
        }

        jstring jKey = env->NewStringUTF(key);
        jstring jResult = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_secureGetMethod, jKey);

        env->DeleteLocalRef(jKey);

        if (jResult == nullptr) {
            LOGD("secureGet (Android): key=%s not found", key);
            return false;
        }

        const char* resultStr = env->GetStringUTFChars(jResult, nullptr);
        if (resultStr) {
            outValue = resultStr;
            env->ReleaseStringUTFChars(jResult, resultStr);
        }
        env->DeleteLocalRef(jResult);

        LOGD("secureGet (Android): key=%s found", key);
        return !outValue.empty();
    }

    bool secureDelete(const char* key) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;

        // Use cached references from JNI_OnLoad
        if (!g_platformAdapterBridgeClass || !g_secureDeleteMethod) {
            LOGE("PlatformAdapterBridge class or secureDelete method not cached");
            return false;
        }

        jstring jKey = env->NewStringUTF(key);
        jboolean result = env->CallStaticBooleanMethod(g_platformAdapterBridgeClass, g_secureDeleteMethod, jKey);

        LOGD("secureDelete (Android): key=%s, success=%d", key, result);

        env->DeleteLocalRef(jKey);

        return result;
    }

    bool secureExists(const char* key) {
        // For secureExists, we'll try secureGet and check if value is non-empty
        // since we don't have a cached method for it
        std::string value;
        return secureGet(key, value);
    }

    std::string getPersistentDeviceUUID() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "";

        // Use cached references from JNI_OnLoad
        if (!g_platformAdapterBridgeClass || !g_getPersistentDeviceUUIDMethod) {
            LOGE("PlatformAdapterBridge class or getPersistentDeviceUUID method not cached");
            return "";
        }

        jstring jResult = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getPersistentDeviceUUIDMethod);
        if (!jResult) return "";

        const char* resultStr = env->GetStringUTFChars(jResult, nullptr);
        std::string uuid = resultStr ? resultStr : "";

        if (resultStr) env->ReleaseStringUTFChars(jResult, resultStr);
        env->DeleteLocalRef(jResult);

        LOGD("getPersistentDeviceUUID (Android): %s", uuid.c_str());
        return uuid;
    }

    std::string getModelBaseDirectory() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "";

        if (!g_platformAdapterBridgeClass || !g_getModelBaseDirectoryMethod) {
            LOGE("PlatformAdapterBridge class or getModelBaseDirectory method not cached");
            return "";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(
            g_platformAdapterBridgeClass,
            g_getModelBaseDirectoryMethod
        );
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            LOGE("Exception in PlatformAdapterBridge.getModelBaseDirectory");
            return "";
        }
        if (!result) return "";

        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string path = str ? str : "";
        if (str) {
            env->ReleaseStringUTFChars(result, str);
        }
        env->DeleteLocalRef(result);

        LOGD("getModelBaseDirectory (Android): %s", path.c_str());
        return path;
    }

    // Device info methods - use cached references from JNI_OnLoad
    std::string getDeviceModel() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "Unknown";

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getDeviceModelMethod) {
            LOGE("PlatformAdapterBridge class or getDeviceModel method not cached");
            return "Unknown";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getDeviceModelMethod);

        if (!result) return "Unknown";

        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string modelName = str ? str : "Unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);

        LOGD("getDeviceModel (Android): %s", modelName.c_str());
        return modelName;
    }

    std::string getOSVersion() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "Unknown";

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getOSVersionMethod) {
            LOGE("PlatformAdapterBridge class or getOSVersion method not cached");
            return "Unknown";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getOSVersionMethod);

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

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getChipNameMethod) {
            LOGE("PlatformAdapterBridge class or getChipName method not cached");
            return "Unknown";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getChipNameMethod);

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

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getTotalMemoryMethod) {
            LOGE("PlatformAdapterBridge class or getTotalMemory method not cached");
            return 0;
        }

        jlong result = env->CallStaticLongMethod(g_platformAdapterBridgeClass, g_getTotalMemoryMethod);

        return static_cast<uint64_t>(result);
    }

    uint64_t getAvailableMemory() {
        JNIEnv* env = getJNIEnv();
        if (!env) return 0;

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getAvailableMemoryMethod) {
            LOGE("PlatformAdapterBridge class or getAvailableMemory method not cached");
            return 0;
        }

        jlong result = env->CallStaticLongMethod(g_platformAdapterBridgeClass, g_getAvailableMemoryMethod);

        return static_cast<uint64_t>(result);
    }

    int getCoreCount() {
        JNIEnv* env = getJNIEnv();
        if (!env) return 1;

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getCoreCountMethod) {
            LOGE("PlatformAdapterBridge class or getCoreCount method not cached");
            return 1;
        }

        jint result = env->CallStaticIntMethod(g_platformAdapterBridgeClass, g_getCoreCountMethod);

        return static_cast<int>(result);
    }

    std::string getArchitecture() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "unknown";

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getArchitectureMethod) {
            LOGE("PlatformAdapterBridge class or getArchitecture method not cached");
            return "unknown";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getArchitectureMethod);

        if (!result) return "unknown";

        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string arch = str ? str : "unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);

        return arch;
    }

    std::string getGPUFamily() {
        JNIEnv* env = getJNIEnv();
        if (!env) return "unknown";

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_getGPUFamilyMethod) {
            LOGE("PlatformAdapterBridge class or getGPUFamily method not cached");
            return "unknown";
        }

        jstring result = (jstring)env->CallStaticObjectMethod(g_platformAdapterBridgeClass, g_getGPUFamilyMethod);

        if (!result) return "unknown";

        const char* str = env->GetStringUTFChars(result, nullptr);
        std::string gpuFamily = str ? str : "unknown";
        env->ReleaseStringUTFChars(result, str);
        env->DeleteLocalRef(result);

        return gpuFamily;
    }

    bool isTablet() {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;

        // Use cached references
        if (!g_platformAdapterBridgeClass || !g_isTabletMethod) {
            LOGE("PlatformAdapterBridge class or isTablet method not cached");
            return false;
        }

        jboolean result = env->CallStaticBooleanMethod(g_platformAdapterBridgeClass, g_isTabletMethod);
        return result == JNI_TRUE;
    }

    rac_result_t httpDownload(const char* url, const char* destinationPath, const char* taskId) {
        JNIEnv* env = getJNIEnv();
        if (!env) return RAC_ERROR_NOT_SUPPORTED;

        if (!g_platformAdapterBridgeClass || !g_httpDownloadMethod) {
            LOGE("PlatformAdapterBridge class or httpDownload method not cached");
            return RAC_ERROR_NOT_SUPPORTED;
        }

        jstring jUrl = env->NewStringUTF(url ? url : "");
        jstring jDest = env->NewStringUTF(destinationPath ? destinationPath : "");
        jstring jTaskId = env->NewStringUTF(taskId ? taskId : "");

        jint result = env->CallStaticIntMethod(g_platformAdapterBridgeClass,
                                               g_httpDownloadMethod,
                                               jUrl,
                                               jDest,
                                               jTaskId);

        env->DeleteLocalRef(jUrl);
        env->DeleteLocalRef(jDest);
        env->DeleteLocalRef(jTaskId);

        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            LOGE("Exception in httpDownload");
            return RAC_ERROR_DOWNLOAD_FAILED;
        }

        return static_cast<rac_result_t>(result);
    }

    bool httpDownloadCancel(const char* taskId) {
        JNIEnv* env = getJNIEnv();
        if (!env) return false;

        if (!g_platformAdapterBridgeClass || !g_httpDownloadCancelMethod) {
            LOGE("PlatformAdapterBridge class or httpDownloadCancel method not cached");
            return false;
        }

        jstring jTaskId = env->NewStringUTF(taskId ? taskId : "");
        jboolean result = env->CallStaticBooleanMethod(g_platformAdapterBridgeClass,
                                                       g_httpDownloadCancelMethod,
                                                       jTaskId);
        env->DeleteLocalRef(jTaskId);

        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            LOGE("Exception in httpDownloadCancel");
            return false;
        }

        return result == JNI_TRUE;
    }

    // CLUSTER-280-SPLIT-sdk-react-native: directory enumeration via
    // java.io.File.listFiles(). Two-call semantics matching
    // rac_file_list_directory_fn. Truncation contract: skip oversized
    // names rather than write a half-name that aliases a different
    // artifact (Kotlin side already filters; we defend on this side too).
    rac_result_t fileListDirectory(const char* dir_path,
                                   rac_directory_entry_t* out_entries,
                                   size_t* in_out_count) {
        if (!in_out_count) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }

        JNIEnv* env = getJNIEnv();
        if (!env) {
            return RAC_ERROR_ADAPTER_NOT_SET;
        }
        if (!g_platformAdapterBridgeClass || !g_fileListDirectoryMethod) {
            return RAC_ERROR_NOT_SUPPORTED;
        }

        jstring jPath = env->NewStringUTF(dir_path ? dir_path : "");
        jobjectArray result = static_cast<jobjectArray>(env->CallStaticObjectMethod(
            g_platformAdapterBridgeClass, g_fileListDirectoryMethod, jPath));
        env->DeleteLocalRef(jPath);

        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            LOGE("Exception in fileListDirectory");
            return RAC_ERROR_INTERNAL;
        }
        // Kotlin returns null when the path does not exist or is not a
        // directory — map to RAC_ERROR_FILE_NOT_FOUND per the C ABI contract.
        if (!result) {
            return RAC_ERROR_FILE_NOT_FOUND;
        }

        const jsize total = env->GetArrayLength(result);

        if (!out_entries) {
            *in_out_count = static_cast<size_t>(total);
            env->DeleteLocalRef(result);
            return RAC_SUCCESS;
        }

        const size_t capacity = *in_out_count;
        const size_t write_count =
            (capacity < static_cast<size_t>(total)) ? capacity : static_cast<size_t>(total);
        size_t written = 0;

        for (size_t i = 0; i < write_count; ++i) {
            jobject entryObj = env->GetObjectArrayElement(result, static_cast<jsize>(i));
            if (!entryObj) {
                continue;
            }
            jclass entryClass = env->GetObjectClass(entryObj);
            jfieldID nameField = env->GetFieldID(entryClass, "name", "Ljava/lang/String;");
            jfieldID isDirField = env->GetFieldID(entryClass, "isDir", "Z");
            jfieldID sizeField = env->GetFieldID(entryClass, "sizeBytes", "J");

            jstring jName = static_cast<jstring>(env->GetObjectField(entryObj, nameField));
            jboolean jIsDir = env->GetBooleanField(entryObj, isDirField);
            jlong jSize = env->GetLongField(entryObj, sizeField);

            const char* nameChars =
                jName ? env->GetStringUTFChars(jName, nullptr) : nullptr;
            if (nameChars) {
                const size_t nameLen = std::strlen(nameChars);
                if (nameLen + 1 <= RAC_DIRECTORY_ENTRY_NAME_MAX) {
                    std::memset(out_entries[written].name, 0, RAC_DIRECTORY_ENTRY_NAME_MAX);
                    std::memcpy(out_entries[written].name, nameChars, nameLen);
                    out_entries[written].is_dir = jIsDir ? RAC_TRUE : RAC_FALSE;
                    out_entries[written].size_bytes = static_cast<int64_t>(jSize);
                    written++;
                }
                env->ReleaseStringUTFChars(jName, nameChars);
            }

            if (jName) {
                env->DeleteLocalRef(jName);
            }
            env->DeleteLocalRef(entryClass);
            env->DeleteLocalRef(entryObj);
        }

        *in_out_count = written;
        env->DeleteLocalRef(result);
        return RAC_SUCCESS;
    }

    bool isNonEmptyDirectory(const char* path) {
        JNIEnv* env = getJNIEnv();
        if (!env || !g_platformAdapterBridgeClass || !g_isNonEmptyDirectoryMethod) {
            return false;
        }
        jstring jPath = env->NewStringUTF(path ? path : "");
        jboolean result = env->CallStaticBooleanMethod(
            g_platformAdapterBridgeClass, g_isNonEmptyDirectoryMethod, jPath);
        env->DeleteLocalRef(jPath);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            return false;
        }
        return result == JNI_TRUE;
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

    // Device type detection
    bool PlatformAdapter_isTablet(void);
    bool PlatformAdapter_getPersistentDeviceUUID(char** outValue);
    bool PlatformAdapter_getModelBaseDirectory(char** outValue);

    // Device info (synchronous)
    bool PlatformAdapter_getDeviceModel(char** outValue);
    bool PlatformAdapter_getOSVersion(char** outValue);
    bool PlatformAdapter_getChipName(char** outValue);
    uint64_t PlatformAdapter_getTotalMemory(void);
    uint64_t PlatformAdapter_getAvailableMemory(void);
    int PlatformAdapter_getCoreCount(void);
    bool PlatformAdapter_getArchitecture(char** outValue);
    bool PlatformAdapter_getGPUFamily(char** outValue);

    // Platform HTTP download fallback used by the RACommons platform adapter.
    // Public RN downloads enter commons through the rac_download_*_proto ABI.
    int PlatformAdapter_httpDownload(
        const char* url,
        const char* destinationPath,
        const char* taskId
    );

    bool PlatformAdapter_httpDownloadCancel(const char* taskId);

    // Directory enumeration + Apple vendor-id (CLUSTER-280-SPLIT-sdk-react-native).
    // Mirrors `PlatformDirectoryEntry` in PlatformAdapterBridge.h field-for-field
    // with `rac_directory_entry_t` so we can memcpy entries straight across.
    typedef struct PlatformDirectoryEntry {
        char name[512];  // RAC_DIRECTORY_ENTRY_NAME_MAX
        bool is_dir;
        int64_t size_bytes;
    } PlatformDirectoryEntry;

    void PlatformAdapter_listDirectory(const char* dirPath,
                                       PlatformDirectoryEntry* outEntries,
                                       size_t* inOutCount,
                                       int* outResult);
    bool PlatformAdapter_isNonEmptyDirectory(const char* path);
    int PlatformAdapter_getVendorId(char* outBuffer, size_t bufferSize);
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
// HTTP download callback state (platform adapter)
// =============================================================================

struct http_download_context {
    rac_http_progress_callback_fn progress_callback;
    rac_http_complete_callback_fn complete_callback;
    void* user_data;
};

static std::mutex g_http_download_mutex;
static std::unordered_map<std::string, http_download_context> g_http_downloads;
static std::atomic<uint64_t> g_http_download_counter{0};

static std::string appendOnConflictForSupabaseUpsert(const std::string& url) {
    if (url.find("/rest/v1/sdk_devices") == std::string::npos ||
        url.find("on_conflict=") != std::string::npos) {
        return url;
    }

    return url + (url.find('?') == std::string::npos ? "?" : "&") + "on_conflict=device_id";
}

static std::tuple<bool, int, std::string, std::string> postJsonViaRacHttpClient(
    const std::string& url,
    const std::string& jsonBody,
    const std::string& apiKey
) {
    std::string finalUrl = appendOnConflictForSupabaseUpsert(url);

    std::vector<rac_http_header_kv_t> headers = {
        {"Content-Type", "application/json"},
        {"Accept", "application/json"},
    };
    std::string bearer;
    if (!apiKey.empty()) {
        headers.push_back({"apikey", apiKey.c_str()});
        bearer = "Bearer " + apiKey;
        headers.push_back({"Authorization", bearer.c_str()});
        headers.push_back({"Prefer", "resolution=merge-duplicates"});
    }

    rac_http_client_t* client = nullptr;
    rac_result_t createResult = rac_http_client_create(&client);
    if (createResult != RAC_SUCCESS || !client) {
        return {false, 0, "", "rac_http_client_create failed: " + std::to_string(createResult)};
    }

    rac_http_request_t req{};
    req.method = "POST";
    req.url = finalUrl.c_str();
    req.headers = headers.data();
    req.header_count = headers.size();
    req.body_bytes = reinterpret_cast<const uint8_t*>(jsonBody.data());
    req.body_len = jsonBody.size();
    req.timeout_ms = 30000;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    rac_http_response_t resp{};
    rac_result_t sendResult = rac_http_request_send(client, &req, &resp);
    rac_http_client_destroy(client);

    if (sendResult != RAC_SUCCESS) {
        rac_http_response_free(&resp);
        return {false, 0, "", "rac_http_request_send failed: " + std::to_string(sendResult)};
    }

    std::string responseBody;
    if (resp.body_bytes && resp.body_len > 0) {
        responseBody.assign(reinterpret_cast<const char*>(resp.body_bytes), resp.body_len);
    }
    int statusCode = resp.status;
    rac_http_response_free(&resp);

    bool success = (statusCode >= 200 && statusCode < 300) || statusCode == 409;
    std::string errorMessage = success ? "" : "HTTP " + std::to_string(statusCode) + ": " + responseBody;
    return {success, statusCode, responseBody, errorMessage};
}

// =============================================================================
// SDK init proto helpers
// =============================================================================

struct SdkInitResultSummary {
    bool hasSuccess = false;
    bool success = false;
    bool httpConfigured = false;
    bool deviceRegistered = false;
    uint32_t linkedModelsCount = 0;
    std::string warning;
};

using ProtoBufferInitFn = void (*)(rac_proto_buffer_t*);
using ProtoBufferFreeFn = void (*)(rac_proto_buffer_t*);
using SdkInitProtoFn = rac_result_t (*)(const uint8_t*, size_t, rac_proto_buffer_t*);

template <typename Fn>
Fn loadOptionalSymbol(const char* name) {
    return reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, name));
}

static void initProtoBuffer(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }
#if defined(__APPLE__) && RN_HAS_RAC_PROTO_BUFFER_HEADER
    rac_proto_buffer_init(buffer);
    return;
#endif
    if (auto fn = loadOptionalSymbol<ProtoBufferInitFn>("rac_proto_buffer_init")) {
        fn(buffer);
        return;
    }
    buffer->data = nullptr;
    buffer->size = 0;
    buffer->status = RAC_SUCCESS;
    buffer->error_message = nullptr;
}

static void freeProtoBuffer(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }
#if defined(__APPLE__) && RN_HAS_RAC_PROTO_BUFFER_HEADER
    rac_proto_buffer_free(buffer);
    return;
#endif
    if (auto fn = loadOptionalSymbol<ProtoBufferFreeFn>("rac_proto_buffer_free")) {
        fn(buffer);
        return;
    }
    std::free(buffer->data);
    std::free(buffer->error_message);
    initProtoBuffer(buffer);
}

static void appendVarint(std::vector<uint8_t>& out, uint64_t value) {
    while (value >= 0x80) {
        out.push_back(static_cast<uint8_t>(value | 0x80));
        value >>= 7;
    }
    out.push_back(static_cast<uint8_t>(value));
}

static void appendStringField(std::vector<uint8_t>& out,
                              uint32_t fieldNumber,
                              const std::string& value) {
    if (value.empty()) {
        return;
    }
    appendVarint(out, (static_cast<uint64_t>(fieldNumber) << 3) | 2U);
    appendVarint(out, value.size());
    out.insert(out.end(), value.begin(), value.end());
}

static std::vector<uint8_t> makePhase1RequestBytes(SDKEnvironment environment,
                                                   const std::string& apiKey,
                                                   const std::string& baseURL,
                                                   const std::string& deviceId) {
    std::vector<uint8_t> bytes;
    appendVarint(bytes, 0x08);  // field 1: environment
    appendVarint(bytes, static_cast<uint64_t>(InitBridge::toRacEnvironment(environment)));
    appendStringField(bytes, 2, apiKey);
    appendStringField(bytes, 3, baseURL);
    appendStringField(bytes, 4, deviceId);
    return bytes;
}

static bool readVarint(const uint8_t*& cursor,
                       const uint8_t* end,
                       uint64_t& value) {
    value = 0;
    uint32_t shift = 0;
    while (cursor < end && shift <= 63) {
        uint8_t byte = *cursor++;
        value |= static_cast<uint64_t>(byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            return true;
        }
        shift += 7;
    }
    return false;
}

static bool skipProtoField(uint32_t wireType,
                           const uint8_t*& cursor,
                           const uint8_t* end) {
    uint64_t length = 0;
    switch (wireType) {
        case 0:
            return readVarint(cursor, end, length);
        case 1:
            if (end - cursor < 8) return false;
            cursor += 8;
            return true;
        case 2:
            if (!readVarint(cursor, end, length)) return false;
            if (static_cast<uint64_t>(end - cursor) < length) return false;
            cursor += length;
            return true;
        case 5:
            if (end - cursor < 4) return false;
            cursor += 4;
            return true;
        default:
            return false;
    }
}

static SdkInitResultSummary parseSdkInitResult(const rac_proto_buffer_t& buffer) {
    SdkInitResultSummary summary;
    if (!buffer.data || buffer.size == 0) {
        return summary;
    }

    const uint8_t* cursor = buffer.data;
    const uint8_t* end = buffer.data + buffer.size;
    while (cursor < end) {
        uint64_t tag = 0;
        if (!readVarint(cursor, end, tag)) {
            break;
        }
        const uint32_t fieldNumber = static_cast<uint32_t>(tag >> 3);
        const uint32_t wireType = static_cast<uint32_t>(tag & 0x07);

        if (wireType == 0) {
            uint64_t value = 0;
            if (!readVarint(cursor, end, value)) {
                break;
            }
            switch (fieldNumber) {
                case 2:
                    summary.hasSuccess = true;
                    summary.success = value != 0;
                    break;
                case 4:
                    summary.httpConfigured = value != 0;
                    break;
                case 5:
                    summary.deviceRegistered = value != 0;
                    break;
                case 6:
                    summary.linkedModelsCount = static_cast<uint32_t>(value);
                    break;
                default:
                    break;
            }
            continue;
        }

        if (fieldNumber == 8 && wireType == 2) {
            uint64_t length = 0;
            if (!readVarint(cursor, end, length) ||
                static_cast<uint64_t>(end - cursor) < length) {
                break;
            }
            summary.warning.assign(reinterpret_cast<const char*>(cursor), length);
            cursor += length;
            continue;
        }

        if (!skipProtoField(wireType, cursor, end)) {
            break;
        }
    }
    return summary;
}

static rac_result_t callSdkInitProto(const char* symbolName,
                                     const std::vector<uint8_t>& requestBytes,
                                     SdkInitResultSummary* outSummary) {
#if RN_HAS_RAC_SDK_INIT_HEADER
    SdkInitProtoFn fn = nullptr;
#if defined(__APPLE__)
    if (std::strcmp(symbolName, "rac_sdk_init_phase1_proto") == 0) {
        fn = rac_sdk_init_phase1_proto;
    } else if (std::strcmp(symbolName, "rac_sdk_init_phase2_proto") == 0) {
        fn = rac_sdk_init_phase2_proto;
    }
#else
    fn = loadOptionalSymbol<SdkInitProtoFn>(symbolName);
#endif
    if (!fn) {
        LOGW("%s unavailable in bundled RACommons; using legacy RN init path", symbolName);
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }

    rac_proto_buffer_t out;
    initProtoBuffer(&out);
    const uint8_t* data = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(data, requestBytes.size(), &out);
    SdkInitResultSummary summary = parseSdkInitResult(out);
    if (outSummary) {
        *outSummary = summary;
    }

    if (rc != RAC_SUCCESS) {
        if (out.error_message) {
            LOGE("%s failed: %s", symbolName, out.error_message);
        } else {
            LOGE("%s failed: %d", symbolName, rc);
        }
        freeProtoBuffer(&out);
        return rc;
    }

    if (out.status != RAC_SUCCESS) {
        rac_result_t status = out.status;
        if (out.error_message) {
            LOGE("%s returned proto error: %s", symbolName, out.error_message);
        } else {
            LOGE("%s returned proto error: %d", symbolName, status);
        }
        freeProtoBuffer(&out);
        return status;
    }

    freeProtoBuffer(&out);
    if (summary.hasSuccess && !summary.success) {
        LOGE("%s completed with success=false", symbolName);
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
    return RAC_SUCCESS;
#else
    (void)symbolName;
    (void)requestBytes;
    (void)outSummary;
    LOGW("rac_sdk_init.h unavailable in bundled headers; using legacy RN init path");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

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
            // Contract (rac_platform_adapter.h secure_get): a clean key-miss
            // MUST return RAC_ERROR_FILE_NOT_FOUND so commons consumers (e.g.
            // rac_device_get_or_create_persistent_id) can distinguish a benign
            // miss from a real secure-storage failure. The JS/TS bridge
            // signals the miss case by resolving with an empty string.
            return RAC_ERROR_FILE_NOT_FOUND;
        }

        *outValue = strdup(value.c_str());
        return *outValue ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        // Real failure path stays distinct from the not-found code so the
        // discrimination above remains meaningful.
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
    if (!outInfo) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const uint64_t totalBytes = InitBridge::shared().getTotalMemory();
    if (totalBytes == 0) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    uint64_t availableBytes = InitBridge::shared().getAvailableMemory();
    if (availableBytes > totalBytes) {
        availableBytes = totalBytes;
    }

    outInfo->total_bytes = totalBytes;
    outInfo->available_bytes = availableBytes;
    outInfo->used_bytes = totalBytes >= availableBytes ? (totalBytes - availableBytes) : 0;

    return RAC_SUCCESS;
}

static void platformTrackErrorCallback(const char* errorJson, void* userData) {
    // Forward error tracking to logging for now
    if (errorJson) {
        LOGE("Track error: %s", errorJson);
    }
}

// =============================================================================
// Directory Enumeration + Vendor ID Callbacks (Platform Adapter)
//
// Cross-SDK parity with Swift (CppBridge+PlatformAdapter), Kotlin
// (CppBridgePlatformAdapter), and Flutter (dart_bridge_platform.dart) — the
// commons model-registry refresh path and rac_model_info_make_proto rely on
// these three slots being populated for rescan_local to succeed and for the
// is_downloaded gating on multi-file artifacts (mmproj + GGUF pairs,
// tokenizer + ONNX bundles) to report TRUE. See rac_platform_adapter.h.
// =============================================================================

static rac_result_t platformFileListDirectoryCallback(const char* dir_path,
                                                      rac_directory_entry_t* out_entries,
                                                      size_t* in_out_count,
                                                      void* user_data) {
    (void)user_data;
    if (!dir_path || !in_out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#if defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::fileListDirectory(dir_path, out_entries, in_out_count);
#elif defined(__APPLE__)
    // Use a stack/heap PlatformDirectoryEntry buffer that mirrors
    // rac_directory_entry_t field-for-field so we can copy across without
    // an additional marshalling pass.
    int result = -805;  // RAC_ERROR_INTERNAL
    if (!out_entries) {
        PlatformAdapter_listDirectory(dir_path, nullptr, in_out_count, &result);
        return static_cast<rac_result_t>(result);
    }

    const size_t capacity = *in_out_count;
    std::vector<PlatformDirectoryEntry> buffer(capacity);
    PlatformAdapter_listDirectory(dir_path, buffer.data(), in_out_count, &result);
    if (result != 0) {
        return static_cast<rac_result_t>(result);
    }

    const size_t written = *in_out_count;
    for (size_t i = 0; i < written; ++i) {
        std::memcpy(out_entries[i].name, buffer[i].name, RAC_DIRECTORY_ENTRY_NAME_MAX);
        out_entries[i].is_dir = buffer[i].is_dir ? RAC_TRUE : RAC_FALSE;
        out_entries[i].size_bytes = buffer[i].size_bytes;
    }
    return RAC_SUCCESS;
#else
    (void)out_entries;
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

static rac_bool_t platformIsNonEmptyDirectoryCallback(const char* path, void* user_data) {
    (void)user_data;
    if (!path) {
        return RAC_FALSE;
    }
#if defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::isNonEmptyDirectory(path) ? RAC_TRUE : RAC_FALSE;
#elif defined(__APPLE__)
    return PlatformAdapter_isNonEmptyDirectory(path) ? RAC_TRUE : RAC_FALSE;
#else
    return RAC_FALSE;
#endif
}

#if defined(__APPLE__)
// Apple-only: populates UIDevice.identifierForVendor.uuidString into the
// commons device-identity chain. Non-Apple platforms intentionally leave
// adapter_.get_vendor_id NULL — commons then walks
// secure_get -> synthesized UUID per the cross-SDK contract on
// rac_platform_adapter.h:get_vendor_id (Android has no equivalent stable
// per-app vendor ID).
static rac_result_t platformGetVendorIdCallback(char* out_buffer,
                                                size_t buffer_size,
                                                void* user_data) {
    (void)user_data;
    int result = PlatformAdapter_getVendorId(out_buffer, buffer_size);
    return static_cast<rac_result_t>(result);
}
#endif

// =============================================================================
// HTTP Download Callbacks (Platform Adapter)
// =============================================================================

static int reportHttpDownloadProgressInternal(const char* task_id,
                                              int64_t downloaded_bytes,
                                              int64_t total_bytes) {
    if (!task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_http_download_mutex);
    auto it = g_http_downloads.find(task_id);
    if (it == g_http_downloads.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    if (it->second.progress_callback) {
        it->second.progress_callback(downloaded_bytes, total_bytes, it->second.user_data);
    }

    return RAC_SUCCESS;
}

static int reportHttpDownloadCompleteInternal(const char* task_id,
                                              int result,
                                              const char* downloaded_path) {
    if (!task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    http_download_context ctx{};
    {
        std::lock_guard<std::mutex> lock(g_http_download_mutex);
        auto it = g_http_downloads.find(task_id);
        if (it == g_http_downloads.end()) {
            return RAC_ERROR_NOT_FOUND;
        }
        ctx = it->second;
        g_http_downloads.erase(it);
    }

    if (ctx.complete_callback) {
        ctx.complete_callback(static_cast<rac_result_t>(result), downloaded_path, ctx.user_data);
    }

    return RAC_SUCCESS;
}

static rac_result_t platformHttpDownloadCallback(const char* url,
                                                 const char* destination_path,
                                                 rac_http_progress_callback_fn progress_callback,
                                                 rac_http_complete_callback_fn complete_callback,
                                                 void* callback_user_data,
                                                 char** out_task_id,
                                                 void* user_data) {
    (void)user_data;

    if (!url || !destination_path || !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string task_id =
        "http_" + std::to_string(g_http_download_counter.fetch_add(1, std::memory_order_relaxed));

    *out_task_id = strdup(task_id.c_str());
    if (!*out_task_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    {
        std::lock_guard<std::mutex> lock(g_http_download_mutex);
        g_http_downloads[task_id] = {progress_callback, complete_callback, callback_user_data};
    }

    rac_result_t start_result = RAC_ERROR_NOT_SUPPORTED;

#if defined(ANDROID) || defined(__ANDROID__)
    start_result = AndroidBridge::httpDownload(url, destination_path, task_id.c_str());
#elif defined(__APPLE__)
    start_result = static_cast<rac_result_t>(
        PlatformAdapter_httpDownload(url, destination_path, task_id.c_str()));
#endif

    if (start_result != RAC_SUCCESS) {
        http_download_context ctx{};
        {
            std::lock_guard<std::mutex> lock(g_http_download_mutex);
            auto it = g_http_downloads.find(task_id);
            if (it != g_http_downloads.end()) {
                ctx = it->second;
                g_http_downloads.erase(it);
            }
        }

        if (ctx.complete_callback) {
            ctx.complete_callback(start_result, nullptr, ctx.user_data);
        }
    }

    return start_result;
}

static rac_result_t platformHttpDownloadCancelCallback(const char* task_id, void* user_data) {
    (void)user_data;

    if (!task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    {
        std::lock_guard<std::mutex> lock(g_http_download_mutex);
        if (g_http_downloads.find(task_id) == g_http_downloads.end()) {
            return RAC_ERROR_NOT_FOUND;
        }
    }

    bool cancelled = false;

#if defined(ANDROID) || defined(__ANDROID__)
    cancelled = AndroidBridge::httpDownloadCancel(task_id);
#elif defined(__APPLE__)
    cancelled = PlatformAdapter_httpDownloadCancel(task_id);
#endif

    return cancelled ? RAC_SUCCESS : RAC_ERROR_CANCELLED;
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

    // Memory info
    adapter_.get_memory_info = platformGetMemoryInfoCallback;

    // Error tracking
    adapter_.track_error = platformTrackErrorCallback;

    // HTTP download fallback for RACommons platform-adapter callers.
    // Public RN model downloads use the rac_download_*_proto ABI.
    adapter_.http_download = platformHttpDownloadCallback;
    adapter_.http_download_cancel = platformHttpDownloadCancelCallback;

    // Archive extraction (handled by JS layer)
    adapter_.extract_archive = nullptr;

    // CLUSTER-280-SPLIT-sdk-react-native: directory enumeration + Apple
    // vendor-id slots. Cross-SDK parity with Swift / Kotlin / Flutter / Web.
    // file_list_directory + is_non_empty_directory are populated on both
    // platforms (FileManager.contentsOfDirectory on iOS, java.io.File.listFiles
    // on Android via JNI). get_vendor_id is Apple-only — Android leaves it
    // NULL per the cross-SDK contract on rac_platform_adapter.h:get_vendor_id
    // (commons synthesizes + persists a UUID via secure_set on Android).
    adapter_.file_list_directory = platformFileListDirectoryCallback;
    adapter_.is_non_empty_directory = platformIsNonEmptyDirectoryCallback;
#if defined(__APPLE__)
    adapter_.get_vendor_id = platformGetVendorIdCallback;
#else
    adapter_.get_vendor_id = nullptr;
#endif

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
    // Use actual platform (ios/android) as backend only accepts these values
#if defined(__APPLE__)
    sdkConfig.platform = "ios";
#elif defined(ANDROID) || defined(__ANDROID__)
    sdkConfig.platform = "android";
#else
    sdkConfig.platform = "ios"; // Default to ios for unknown platforms
#endif
    // Use centralized SDK version (set from TypeScript SDKConstants via setSdkVersion)
    static std::string s_sdkVersion;
    s_sdkVersion = getSdkVersion();
    sdkConfig.sdk_version = s_sdkVersion.c_str();
    static std::string s_deviceId;
    s_deviceId = deviceId_.empty() ? getPersistentDeviceUUID() : deviceId_;
    sdkConfig.device_id = s_deviceId.c_str();

    rac_validation_result_t validResult = rac_sdk_init(&sdkConfig);
    if (validResult != RAC_VALIDATION_OK) {
        LOGW("SDK config validation warning: %d (non-fatal)", validResult);
        // Non-fatal - device registration can still work without this
    } else {
        LOGI("SDK config initialized with version: %s", sdkConfig.sdk_version);
    }

    // Step 5: Phase 1 proto (canonical commons owner for state init) when
    // bundled headers/native symbols expose rac_sdk_init_phase1_proto. Older
    // packaged natives continue through the legacy RN init path.
    {
        SdkInitResultSummary phase1Summary;
        std::vector<uint8_t> phase1Bytes = makePhase1RequestBytes(
            environment,
            apiKey_,
            baseURL_,
            s_deviceId);
        rac_result_t phase1Result = callSdkInitProto(
            "rac_sdk_init_phase1_proto",
            phase1Bytes,
            &phase1Summary);
        if (phase1Result != RAC_SUCCESS &&
            phase1Result != RAC_ERROR_FEATURE_NOT_AVAILABLE) {
            LOGE("SDK Phase 1 proto initialization failed: %d", phase1Result);
            rac_shutdown();
            return phase1Result;
        }
        if (phase1Result == RAC_SUCCESS) {
            LOGI("SDK Phase 1 proto initialized");
        }
    }

    initialized_ = true;
    LOGI("SDK initialized successfully for environment %d", static_cast<int>(environment));

    return RAC_SUCCESS;
}

rac_result_t InitBridge::registerDeviceCallbacks() {
    DevicePlatformCallbacks callbacks;

    callbacks.getDeviceInfo = []() -> DeviceInfo {
        DeviceInfo info;
        info.deviceId = InitBridge::shared().getPersistentDeviceUUID();
#if defined(__APPLE__)
        info.platform = "ios";
        info.osName = "iOS";
        info.hasNeuralEngine = true;
        info.neuralEngineCores = 16;
#elif defined(ANDROID) || defined(__ANDROID__)
        info.platform = "android";
        info.osName = "Android";
        info.hasNeuralEngine = false;
        info.neuralEngineCores = 0;
#else
        info.platform = "unknown";
        info.osName = "Unknown";
        info.hasNeuralEngine = false;
        info.neuralEngineCores = 0;
#endif
        info.sdkVersion = InitBridge::shared().getSdkVersion();
        info.deviceModel = InitBridge::shared().getDeviceModel();
        info.deviceName = info.deviceModel;
        info.osVersion = InitBridge::shared().getOSVersion();
        info.chipName = InitBridge::shared().getChipName();
        info.architecture = InitBridge::shared().getArchitecture();
        info.totalMemory = InitBridge::shared().getTotalMemory();
        info.availableMemory = InitBridge::shared().getAvailableMemory();
        info.coreCount = InitBridge::shared().getCoreCount();
        info.gpuFamily = InitBridge::shared().getGPUFamily();
        info.formFactor = InitBridge::shared().isTablet() ? "tablet" : "phone";
        info.batteryLevel = -1.0f;
        info.batteryState = "";
        info.isLowPowerMode = false;
        info.performanceCores = info.coreCount > 4 ? 2 : 1;
        info.efficiencyCores = info.coreCount - info.performanceCores;
        return info;
    };

    callbacks.getDeviceId = []() -> std::string {
        return InitBridge::shared().getPersistentDeviceUUID();
    };

    callbacks.isRegistered = []() -> bool {
        std::string value;
        if (InitBridge::shared().secureGet("com.runanywhere.sdk.deviceRegistered", value)) {
            return value == "true";
        }
        return false;
    };

    callbacks.setRegistered = [](bool registered) {
        InitBridge::shared().secureSet(
            "com.runanywhere.sdk.deviceRegistered",
            registered ? "true" : "false");
    };

    callbacks.httpPost = [](
        const std::string& endpoint,
        const std::string& jsonBody,
        bool requiresAuth
    ) -> std::tuple<bool, int, std::string, std::string> {
        (void)requiresAuth;

        rac_environment_t env = InitBridge::toRacEnvironment(
            InitBridge::shared().getEnvironment());
        std::string baseURL;
        std::string token;

        if (env == RAC_ENV_DEVELOPMENT) {
            auto supabaseConfig = config::makeEndpointConfig(
                rac_dev_config_get_supabase_url() ? rac_dev_config_get_supabase_url() : "",
                rac_dev_config_get_supabase_key() ? rac_dev_config_get_supabase_key() : "");
            if (!supabaseConfig.usable) {
                LOGI("Skipping development device registration: no usable config");
                return {true, 204, "{}", ""};
            }
            baseURL = supabaseConfig.baseURL;
            token = supabaseConfig.token;
        } else {
            baseURL = config::trim(InitBridge::shared().getBaseURL());
            std::string accessToken = AuthBridge::shared().getAccessToken();
            token = config::isUsableSecret(accessToken)
                ? accessToken
                : config::trim(InitBridge::shared().getApiKey());
            if (!config::isUsableHttpUrl(baseURL) || !config::isUsableSecret(token)) {
                LOGI("Skipping device registration: no usable external config");
                return {true, 204, "{}", ""};
            }
        }

        std::string fullURL = config::appendEndpointPath(baseURL, endpoint);
        return InitBridge::shared().httpPostSync(fullURL, jsonBody, token);
    };

    DeviceBridge::shared().setPlatformCallbacks(callbacks);
    return DeviceBridge::shared().registerCallbacks();
}

rac_result_t InitBridge::completeServicesInitialization() {
    if (!initialized_) {
        LOGE("completeServicesInitialization called before initialize");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_result_t callbacksResult = registerDeviceCallbacks();
    if (callbacksResult != RAC_SUCCESS) {
        LOGE("Failed to register device callbacks for Phase 2: %d", callbacksResult);
        return callbacksResult;
    }

    SdkInitResultSummary phase2Summary;
    std::vector<uint8_t> emptyPhase2Request;
    rac_result_t phase2Result = callSdkInitProto(
        "rac_sdk_init_phase2_proto",
        emptyPhase2Request,
        &phase2Summary);
    if (phase2Result == RAC_ERROR_FEATURE_NOT_AVAILABLE) {
        return RAC_SUCCESS;
    }
    if (phase2Result != RAC_SUCCESS) {
        return phase2Result;
    }

    if (!phase2Summary.warning.empty()) {
        LOGI("SDK Phase 2 warning: %s", phase2Summary.warning.c_str());
    }
    LOGI("SDK Phase 2 complete (http=%d, device=%d, linked=%u)",
         phase2Summary.httpConfigured ? 1 : 0,
         phase2Summary.deviceRegistered ? 1 : 0,
         phase2Summary.linkedModelsCount);
    return RAC_SUCCESS;
}

rac_result_t InitBridge::setBaseDirectory(const std::string& baseDirectory) {
    if (baseDirectory.empty()) {
        LOGE("Base directory path is empty");
        return RAC_ERROR_NULL_POINTER;
    }

    rac_result_t result = rac_model_paths_set_base_dir(baseDirectory.c_str());
    if (result == RAC_SUCCESS) {
        LOGI("Model paths base directory set to: %s", baseDirectory.c_str());
    } else {
        LOGE("Failed to set model paths base directory: %d", result);
    }

    return result;
}

std::string InitBridge::getDefaultModelBaseDirectory() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getModelBaseDirectory(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "";
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getModelBaseDirectory();
#else
    return "";
#endif
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
    // Delegate to the canonical commons resolver so RN shares one device-id
    // stream with the native Swift / Kotlin SDKs. Commons walks
    // secure_get -> get_vendor_id (Apple UIDevice.identifierForVendor, populated
    // above) -> synthesized UUIDv4, then persists via secure_set. Caching,
    // the secure-storage key, and UUID generation all live in commons; a local
    // copy here is exactly the divergence rn-012 flags.
    char buffer[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {0};
    rac_result_t result = rac_device_get_or_create_persistent_id(buffer, sizeof(buffer));
    if (result != RAC_SUCCESS) {
        LOGE("rac_device_get_or_create_persistent_id failed: %d", result);
        return "";
    }
    return std::string(buffer);
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

std::string InitBridge::getGPUFamily() {
#if defined(__APPLE__)
    char* value = nullptr;
    if (PlatformAdapter_getGPUFamily(&value) && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return "apple"; // Default GPU family for iOS/macOS
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::getGPUFamily();
#else
    return "unknown";
#endif
}

bool InitBridge::isTablet() {
#if defined(__APPLE__)
    return PlatformAdapter_isTablet();
#elif defined(ANDROID) || defined(__ANDROID__)
    return AndroidBridge::isTablet();
#else
    return false;
#endif
}

// =============================================================================
// HTTP POST for Device Registration / Telemetry (Synchronous)
// Matches Swift: CppBridge+Device.swift http_post callback
// =============================================================================

std::tuple<bool, int, std::string, std::string> InitBridge::httpPostSync(
    const std::string& url,
    const std::string& jsonBody,
    const std::string& supabaseKey
) {
    LOGI("httpPostSync via rac_http_client_* to: %s", url.c_str());
    auto result = postJsonViaRacHttpClient(url, jsonBody, supabaseKey);
    LOGI("httpPostSync result: success=%d statusCode=%d", std::get<0>(result), std::get<1>(result));
    return result;
}

} // namespace bridges
} // namespace runanywhere

// =============================================================================
// Global C API for platform download reporting
// =============================================================================

extern "C" int RunAnywhereHttpDownloadReportProgress(const char* task_id,
                                                     int64_t downloaded_bytes,
                                                     int64_t total_bytes) {
    return runanywhere::bridges::reportHttpDownloadProgressInternal(task_id,
                                                                    downloaded_bytes,
                                                                    total_bytes);
}

extern "C" int RunAnywhereHttpDownloadReportComplete(const char* task_id,
                                                     int result,
                                                     const char* downloaded_path) {
    return runanywhere::bridges::reportHttpDownloadCompleteInternal(task_id,
                                                                    result,
                                                                    downloaded_path);
}

// M5: The `SyncHttpDownload` helper that used to live here — the B-RN-3-001 /
// G-A6 platform-adapter workaround around libcurl HTTPS on Android — has been
// deleted. RN downloads now enter commons through the rac_download_*_proto ABI,
// which routes via the registered platform HTTP transport (OkHttp / URLSession).
