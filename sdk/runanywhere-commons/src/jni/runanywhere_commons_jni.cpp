/**
 * RunAnywhere Commons JNI Bridge
 *
 * JNI layer that wraps the runanywhere-commons C API (rac_*.h) for Android/JVM.
 * This provides a thin wrapper that exposes all rac_* C API functions via JNI.
 *
 * Package: com.runanywhere.sdk.native.bridge
 * Class: RunAnywhereBridge
 *
 * Design principles:
 * 1. Thin wrapper - minimal logic, just data conversion
 * 2. Direct mapping to C API functions
 * 3. Consistent error handling
 * 4. Memory safety with proper cleanup
 */

#include <jni.h>
#include <string>
#include <cstring>
#include <mutex>

// Include runanywhere-commons C API headers
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_component.h"

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RACCommonsJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGd(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGi(...) fprintf(stdout, "[INFO] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGe(...) fprintf(stderr, "[ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGw(...) fprintf(stdout, "[WARN] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGd(...) fprintf(stdout, "[DEBUG] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

// =============================================================================
// Global State for Platform Adapter JNI Callbacks
// =============================================================================

static JavaVM* g_jvm = nullptr;
static jobject g_platform_adapter = nullptr;
static std::mutex g_adapter_mutex;

// Method IDs for platform adapter callbacks (cached)
static jmethodID g_method_log = nullptr;
static jmethodID g_method_file_exists = nullptr;
static jmethodID g_method_file_read = nullptr;
static jmethodID g_method_file_write = nullptr;
static jmethodID g_method_file_delete = nullptr;
static jmethodID g_method_secure_get = nullptr;
static jmethodID g_method_secure_set = nullptr;
static jmethodID g_method_secure_delete = nullptr;
static jmethodID g_method_now_ms = nullptr;

// =============================================================================
// JNI OnLoad/OnUnload
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnLoad: runanywhere_commons_jni loaded");
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnUnload: runanywhere_commons_jni unloading");

    std::lock_guard<std::mutex> lock(g_adapter_mutex);
    if (g_platform_adapter != nullptr) {
        JNIEnv* env = nullptr;
        if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            env->DeleteGlobalRef(g_platform_adapter);
        }
        g_platform_adapter = nullptr;
    }
    g_jvm = nullptr;
}

// =============================================================================
// Helper Functions
// =============================================================================

static JNIEnv* getJNIEnv() {
    if (g_jvm == nullptr) return nullptr;

    JNIEnv* env = nullptr;
    int status = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);

    if (status == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            return nullptr;
        }
    }
    return env;
}

static std::string getCString(JNIEnv* env, jstring str) {
    if (str == nullptr) return "";
    const char* chars = env->GetStringUTFChars(str, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(str, chars);
    return result;
}

static const char* getNullableCString(JNIEnv* env, jstring str, std::string& storage) {
    if (str == nullptr) return nullptr;
    storage = getCString(env, str);
    return storage.c_str();
}

// =============================================================================
// Platform Adapter C Callbacks (called by C++ library)
// =============================================================================

// Forward declaration of the adapter struct
static rac_platform_adapter_t g_c_adapter;

static void jni_log_callback(rac_log_level_t level, const char* tag, const char* message, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_log == nullptr) {
        // Fallback to native logging
        LOGd("[%s] %s", tag ? tag : "RAC", message ? message : "");
        return;
    }

    jstring jTag = env->NewStringUTF(tag ? tag : "RAC");
    jstring jMessage = env->NewStringUTF(message ? message : "");

    env->CallVoidMethod(g_platform_adapter, g_method_log, static_cast<jint>(level), jTag, jMessage);

    env->DeleteLocalRef(jTag);
    env->DeleteLocalRef(jMessage);
}

static rac_bool_t jni_file_exists_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_exists == nullptr) {
        return RAC_FALSE;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_exists, jPath);
    env->DeleteLocalRef(jPath);

    return result ? RAC_TRUE : RAC_FALSE;
}

static rac_result_t jni_file_read_callback(const char* path, char** out_data, size_t* out_size, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_read == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jbyteArray result = static_cast<jbyteArray>(env->CallObjectMethod(g_platform_adapter, g_method_file_read, jPath));
    env->DeleteLocalRef(jPath);

    if (result == nullptr) {
        *out_data = nullptr;
        *out_size = 0;
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    jsize len = env->GetArrayLength(result);
    *out_size = static_cast<size_t>(len);
    *out_data = static_cast<char*>(malloc(len + 1));
    env->GetByteArrayRegion(result, 0, len, reinterpret_cast<jbyte*>(*out_data));
    (*out_data)[len] = '\0';

    env->DeleteLocalRef(result);
    return RAC_SUCCESS;
}

static rac_result_t jni_file_write_callback(const char* path, const char* data, size_t size, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_write == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jbyteArray jData = env->NewByteArray(static_cast<jsize>(size));
    env->SetByteArrayRegion(jData, 0, static_cast<jsize>(size), reinterpret_cast<const jbyte*>(data));

    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_write, jPath, jData);

    env->DeleteLocalRef(jPath);
    env->DeleteLocalRef(jData);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_IO;
}

static rac_result_t jni_file_delete_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_delete == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_delete, jPath);
    env->DeleteLocalRef(jPath);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_IO;
}

static rac_result_t jni_secure_get_callback(const char* key, char** out_value, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_get == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jstring result = static_cast<jstring>(env->CallObjectMethod(g_platform_adapter, g_method_secure_get, jKey));
    env->DeleteLocalRef(jKey);

    if (result == nullptr) {
        *out_value = nullptr;
        return RAC_ERROR_NOT_FOUND;
    }

    const char* chars = env->GetStringUTFChars(result, nullptr);
    *out_value = strdup(chars);
    env->ReleaseStringUTFChars(result, chars);
    env->DeleteLocalRef(result);

    return RAC_SUCCESS;
}

static rac_result_t jni_secure_set_callback(const char* key, const char* value, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_set == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jstring jValue = env->NewStringUTF(value ? value : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_set, jKey, jValue);

    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(jValue);

    return result ? RAC_SUCCESS : RAC_ERROR_STORAGE;
}

static rac_result_t jni_secure_delete_callback(const char* key, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_delete == nullptr) {
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_delete, jKey);
    env->DeleteLocalRef(jKey);

    return result ? RAC_SUCCESS : RAC_ERROR_STORAGE;
}

static int64_t jni_now_ms_callback(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_now_ms == nullptr) {
        // Fallback to system time
        return static_cast<int64_t>(time(nullptr)) * 1000;
    }

    return env->CallLongMethod(g_platform_adapter, g_method_now_ms);
}

// =============================================================================
// JNI FUNCTIONS - Core Initialization
// =============================================================================

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racInit(JNIEnv* env, jclass clazz) {
    LOGi("racInit called");

    // Check if platform adapter is set
    if (g_platform_adapter == nullptr) {
        LOGe("racInit: Platform adapter not set! Call racSetPlatformAdapter first.");
        return RAC_ERROR_PLATFORM_ADAPTER_NOT_SET;
    }

    // Initialize with the C adapter struct
    rac_config_t config = {};
    config.platform_adapter = &g_c_adapter;
    config.log_level = RAC_LOG_LEVEL_DEBUG;
    config.log_tag = "RAC";

    rac_result_t result = rac_init(&config);

    if (result != RAC_SUCCESS) {
        LOGe("racInit failed with code: %d", result);
    } else {
        LOGi("racInit succeeded");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racShutdown(JNIEnv* env, jclass clazz) {
    LOGi("racShutdown called");
    rac_shutdown();
    return RAC_SUCCESS;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racIsInitialized(JNIEnv* env, jclass clazz) {
    return rac_is_initialized() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSetPlatformAdapter(JNIEnv* env, jclass clazz, jobject adapter) {
    LOGi("racSetPlatformAdapter called");

    std::lock_guard<std::mutex> lock(g_adapter_mutex);

    // Clean up previous adapter
    if (g_platform_adapter != nullptr) {
        env->DeleteGlobalRef(g_platform_adapter);
        g_platform_adapter = nullptr;
    }

    if (adapter == nullptr) {
        LOGw("racSetPlatformAdapter: null adapter provided");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Create global reference to adapter
    g_platform_adapter = env->NewGlobalRef(adapter);

    // Cache method IDs
    jclass adapterClass = env->GetObjectClass(adapter);

    g_method_log = env->GetMethodID(adapterClass, "log", "(ILjava/lang/String;Ljava/lang/String;)V");
    g_method_file_exists = env->GetMethodID(adapterClass, "fileExists", "(Ljava/lang/String;)Z");
    g_method_file_read = env->GetMethodID(adapterClass, "fileRead", "(Ljava/lang/String;)[B");
    g_method_file_write = env->GetMethodID(adapterClass, "fileWrite", "(Ljava/lang/String;[B)Z");
    g_method_file_delete = env->GetMethodID(adapterClass, "fileDelete", "(Ljava/lang/String;)Z");
    g_method_secure_get = env->GetMethodID(adapterClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
    g_method_secure_set = env->GetMethodID(adapterClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
    g_method_secure_delete = env->GetMethodID(adapterClass, "secureDelete", "(Ljava/lang/String;)Z");
    g_method_now_ms = env->GetMethodID(adapterClass, "nowMs", "()J");

    env->DeleteLocalRef(adapterClass);

    // Initialize the C adapter struct with our JNI callbacks
    memset(&g_c_adapter, 0, sizeof(g_c_adapter));
    g_c_adapter.log = jni_log_callback;
    g_c_adapter.file_exists = jni_file_exists_callback;
    g_c_adapter.file_read = jni_file_read_callback;
    g_c_adapter.file_write = jni_file_write_callback;
    g_c_adapter.file_delete = jni_file_delete_callback;
    g_c_adapter.secure_get = jni_secure_get_callback;
    g_c_adapter.secure_set = jni_secure_set_callback;
    g_c_adapter.secure_delete = jni_secure_delete_callback;
    g_c_adapter.now_ms = jni_now_ms_callback;
    g_c_adapter.user_data = nullptr;

    LOGi("racSetPlatformAdapter: adapter set successfully");
    return RAC_SUCCESS;
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racGetPlatformAdapter(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(g_adapter_mutex);
    return g_platform_adapter;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racConfigureLogging(JNIEnv* env, jclass clazz, jint level, jstring logFilePath) {
    // For now, just configure the log level
    // The log file path is not used in the current implementation
    rac_result_t result = rac_configure_logging(static_cast<rac_environment_t>(0)); // Development
    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLog(JNIEnv* env, jclass clazz, jint level, jstring tag, jstring message) {
    std::string tagStr = getCString(env, tag);
    std::string msgStr = getCString(env, message);

    rac_log(static_cast<rac_log_level_t>(level), tagStr.c_str(), "%s", msgStr.c_str());
}

// =============================================================================
// JNI FUNCTIONS - LLM Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCreate(JNIEnv* env, jclass clazz) {
    rac_llm_component_t* component = rac_llm_component_create();
    return reinterpret_cast<jlong>(component);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_destroy(reinterpret_cast<rac_llm_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    std::string configStorage;
    const char* config = getNullableCString(env, configJson, configStorage);

    rac_llm_config_t llm_config = {};
    // Parse config JSON if provided

    return static_cast<jint>(rac_llm_component_load_model(
        reinterpret_cast<rac_llm_component_t*>(handle),
        path.c_str(),
        &llm_config
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_unload(reinterpret_cast<rac_llm_component_t*>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerate(JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
    if (handle == 0) return nullptr;

    std::string promptStr = getCString(env, prompt);
    std::string configStorage;
    const char* config = getNullableCString(env, configJson, configStorage);

    rac_llm_options_t options = {};
    options.max_tokens = 100;
    options.temperature = 0.7f;
    options.top_p = 1.0f;
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t result = {};
    rac_result_t status = rac_llm_component_generate(
        reinterpret_cast<rac_llm_component_t*>(handle),
        promptStr.c_str(),
        &options,
        &result
    );

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    // Return result as JSON string
    if (result.text != nullptr) {
        jstring jResult = env->NewStringUTF(result.text);
        rac_llm_result_free(&result);
        return jResult;
    }

    return env->NewStringUTF("{}");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerateStream(JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
    // Streaming implementation - for now, delegate to non-streaming
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerate(env, clazz, handle, prompt, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_cancel(reinterpret_cast<rac_llm_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetContextSize(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_llm_component_get_context_size(reinterpret_cast<rac_llm_component_t*>(handle)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentTokenize(JNIEnv* env, jclass clazz, jlong handle, jstring text) {
    if (handle == 0) return 0;
    std::string textStr = getCString(env, text);
    return static_cast<jint>(rac_llm_component_tokenize(
        reinterpret_cast<rac_llm_component_t*>(handle),
        textStr.c_str()
    ));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_llm_component_get_state(reinterpret_cast<rac_llm_component_t*>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_llm_component_is_loaded(reinterpret_cast<rac_llm_component_t*>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmSetCallbacks(JNIEnv* env, jclass clazz, jobject streamCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - STT Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCreate(JNIEnv* env, jclass clazz) {
    rac_stt_component_t* component = rac_stt_component_create();
    return reinterpret_cast<jlong>(component);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_stt_component_destroy(reinterpret_cast<rac_stt_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    rac_stt_config_t config = {};

    return static_cast<jint>(rac_stt_component_load_model(
        reinterpret_cast<rac_stt_component_t*>(handle),
        path.c_str(),
        &config
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_stt_component_unload(reinterpret_cast<rac_stt_component_t*>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribe(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    if (handle == 0 || audioData == nullptr) return nullptr;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    rac_stt_options_t options = {};
    rac_stt_result_t result = {};

    rac_result_t status = rac_stt_component_transcribe(
        reinterpret_cast<rac_stt_component_t*>(handle),
        reinterpret_cast<const float*>(data),
        static_cast<size_t>(len / sizeof(float)),
        &options,
        &result
    );

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    if (result.text != nullptr) {
        jstring jResult = env->NewStringUTF(result.text);
        rac_stt_result_free(&result);
        return jResult;
    }

    return env->NewStringUTF("{}");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribeFile(JNIEnv* env, jclass clazz, jlong handle, jstring audioPath, jstring configJson) {
    if (handle == 0) return nullptr;

    std::string path = getCString(env, audioPath);
    rac_stt_options_t options = {};
    rac_stt_result_t result = {};

    rac_result_t status = rac_stt_component_transcribe_file(
        reinterpret_cast<rac_stt_component_t*>(handle),
        path.c_str(),
        &options,
        &result
    );

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    if (result.text != nullptr) {
        jstring jResult = env->NewStringUTF(result.text);
        rac_stt_result_free(&result);
        return jResult;
    }

    return env->NewStringUTF("{}");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribeStream(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribe(env, clazz, handle, audioData, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_stt_component_cancel(reinterpret_cast<rac_stt_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_stt_component_get_state(reinterpret_cast<rac_stt_component_t*>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_stt_component_is_loaded(reinterpret_cast<rac_stt_component_t*>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentGetLanguages(JNIEnv* env, jclass clazz, jlong handle) {
    // Return empty array for now
    return env->NewStringUTF("[]");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDetectLanguage(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData) {
    // Return null for now - language detection not implemented
    return nullptr;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttSetCallbacks(JNIEnv* env, jclass clazz, jobject partialCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - TTS Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCreate(JNIEnv* env, jclass clazz) {
    rac_tts_component_t* component = rac_tts_component_create();
    return reinterpret_cast<jlong>(component);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_tts_component_destroy(reinterpret_cast<rac_tts_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    rac_tts_config_t config = {};

    return static_cast<jint>(rac_tts_component_load_model(
        reinterpret_cast<rac_tts_component_t*>(handle),
        path.c_str(),
        &config
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_tts_component_unload(reinterpret_cast<rac_tts_component_t*>(handle));
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesize(JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring configJson) {
    if (handle == 0) return nullptr;

    std::string textStr = getCString(env, text);
    rac_tts_options_t options = {};
    rac_tts_result_t result = {};

    rac_result_t status = rac_tts_component_synthesize(
        reinterpret_cast<rac_tts_component_t*>(handle),
        textStr.c_str(),
        &options,
        &result
    );

    if (status != RAC_SUCCESS || result.audio_data == nullptr) {
        return nullptr;
    }

    jbyteArray jResult = env->NewByteArray(static_cast<jsize>(result.audio_size));
    env->SetByteArrayRegion(jResult, 0, static_cast<jsize>(result.audio_size),
                           reinterpret_cast<const jbyte*>(result.audio_data));

    rac_tts_result_free(&result);
    return jResult;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesizeStream(JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesize(env, clazz, handle, text, configJson);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesizeToFile(JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring outputPath, jstring configJson) {
    if (handle == 0) return -1;

    std::string textStr = getCString(env, text);
    std::string pathStr = getCString(env, outputPath);
    rac_tts_options_t options = {};

    rac_result_t status = rac_tts_component_synthesize_to_file(
        reinterpret_cast<rac_tts_component_t*>(handle),
        textStr.c_str(),
        pathStr.c_str(),
        &options
    );

    return status == RAC_SUCCESS ? 0 : -1;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_tts_component_cancel(reinterpret_cast<rac_tts_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_tts_component_get_state(reinterpret_cast<rac_tts_component_t*>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_tts_component_is_loaded(reinterpret_cast<rac_tts_component_t*>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetVoices(JNIEnv* env, jclass clazz, jlong handle) {
    return env->NewStringUTF("[]");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSetVoice(JNIEnv* env, jclass clazz, jlong handle, jstring voiceId) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;
    std::string voice = getCString(env, voiceId);
    return static_cast<jint>(rac_tts_component_set_voice(
        reinterpret_cast<rac_tts_component_t*>(handle),
        voice.c_str()
    ));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetLanguages(JNIEnv* env, jclass clazz, jlong handle) {
    return env->NewStringUTF("[]");
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsSetCallbacks(JNIEnv* env, jclass clazz, jobject audioCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - VAD Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCreate(JNIEnv* env, jclass clazz) {
    rac_vad_component_t* component = rac_vad_component_create();
    return reinterpret_cast<jlong>(component);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_destroy(reinterpret_cast<rac_vad_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    rac_vad_config_t config = {};

    return static_cast<jint>(rac_vad_component_load_model(
        reinterpret_cast<rac_vad_component_t*>(handle),
        path.c_str(),
        &config
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_unload(reinterpret_cast<rac_vad_component_t*>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    if (handle == 0 || audioData == nullptr) return nullptr;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    rac_vad_options_t options = {};
    rac_vad_result_t result = {};

    rac_result_t status = rac_vad_component_process(
        reinterpret_cast<rac_vad_component_t*>(handle),
        reinterpret_cast<const float*>(data),
        static_cast<size_t>(len / sizeof(float)),
        &options,
        &result
    );

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    // Return JSON result
    char jsonBuf[256];
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"is_speech\":%s,\"probability\":%.4f}",
             result.is_speech ? "true" : "false",
             result.probability);

    return env->NewStringUTF(jsonBuf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcessStream(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(env, clazz, handle, audioData, configJson);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcessFrame(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(env, clazz, handle, audioData, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_cancel(reinterpret_cast<rac_vad_component_t*>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentReset(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_reset(reinterpret_cast<rac_vad_component_t*>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_vad_component_get_state(reinterpret_cast<rac_vad_component_t*>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_vad_component_is_loaded(reinterpret_cast<rac_vad_component_t*>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetMinFrameSize(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_vad_component_get_min_frame_size(reinterpret_cast<rac_vad_component_t*>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetSampleRates(JNIEnv* env, jclass clazz, jlong handle) {
    return env->NewStringUTF("[16000]");
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadSetCallbacks(JNIEnv* env, jclass clazz, jobject frameCallback, jobject speechStartCallback, jobject speechEndCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - Backend Registration (for LlamaCPP and ONNX modules)
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racBackendLlamacppRegister(JNIEnv* env, jclass clazz) {
    LOGi("racBackendLlamacppRegister called");
    // This will be implemented by linking against the llamacpp backend library
    // For now, return success - the actual registration happens in the C++ library
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racBackendLlamacppUnregister(JNIEnv* env, jclass clazz) {
    LOGi("racBackendLlamacppUnregister called");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racBackendOnnxRegister(JNIEnv* env, jclass clazz) {
    LOGi("racBackendOnnxRegister called");
    // This will be implemented by linking against the onnx backend library
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racBackendOnnxUnregister(JNIEnv* env, jclass clazz) {
    LOGi("racBackendOnnxUnregister called");
    return RAC_SUCCESS;
}

} // extern "C"
