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
#include <condition_variable>

// Include runanywhere-commons C API headers
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// NOTE: Backend headers are NOT included here.
// Backend registration is handled by their respective JNI libraries:
//   - backends/llamacpp/src/jni/rac_backend_llamacpp_jni.cpp
//   - backends/onnx/src/jni/rac_backend_onnx_jni.cpp

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

static rac_result_t jni_file_read_callback(const char* path, void** out_data, size_t* out_size, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_read == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
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
    *out_data = malloc(len);
    env->GetByteArrayRegion(result, 0, len, reinterpret_cast<jbyte*>(*out_data));

    env->DeleteLocalRef(result);
    return RAC_SUCCESS;
}

static rac_result_t jni_file_write_callback(const char* path, const void* data, size_t size, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_write == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jbyteArray jData = env->NewByteArray(static_cast<jsize>(size));
    env->SetByteArrayRegion(jData, 0, static_cast<jsize>(size), reinterpret_cast<const jbyte*>(data));

    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_write, jPath, jData);

    env->DeleteLocalRef(jPath);
    env->DeleteLocalRef(jData);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

static rac_result_t jni_file_delete_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_delete == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_delete, jPath);
    env->DeleteLocalRef(jPath);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

static rac_result_t jni_secure_get_callback(const char* key, char** out_value, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_get == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
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
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jstring jValue = env->NewStringUTF(value ? value : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_set, jKey, jValue);

    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(jValue);

    return result ? RAC_SUCCESS : RAC_ERROR_STORAGE_ERROR;
}

static rac_result_t jni_secure_delete_callback(const char* key, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_delete == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_delete, jKey);
    env->DeleteLocalRef(jKey);

    return result ? RAC_SUCCESS : RAC_ERROR_STORAGE_ERROR;
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
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    // Initialize with the C adapter struct
    rac_config_t config = {};
    config.platform_adapter = &g_c_adapter;
    config.log_level = RAC_LOG_DEBUG;
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

    rac_log(static_cast<rac_log_level_t>(level), tagStr.c_str(), msgStr.c_str());
}

// =============================================================================
// JNI FUNCTIONS - LLM Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCreate(JNIEnv* env, jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_llm_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create LLM component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    LOGi("racLlmComponentLoadModel called with handle=%lld", (long long)handle);
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    LOGi("racLlmComponentLoadModel model_id=%s", path.c_str());

    // Debug: List registered providers BEFORE loading
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_TEXT_GENERATION, &provider_names, &provider_count);
    LOGi("Before load_model - TEXT_GENERATION providers: count=%zu, list_result=%d", provider_count, list_result);
    if (provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            LOGi("  Provider[%zu]: %s", i, provider_names[i] ? provider_names[i] : "NULL");
        }
    } else {
        LOGw("NO providers registered for TEXT_GENERATION!");
    }

    rac_result_t result = rac_llm_component_load_model(
        reinterpret_cast<rac_handle_t>(handle),
        path.c_str()
    );
    LOGi("rac_llm_component_load_model returned: %d", result);

    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerate(JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
    LOGi("racLlmComponentGenerate called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racLlmComponentGenerate: invalid handle");
        return nullptr;
    }

    std::string promptStr = getCString(env, prompt);
    LOGi("racLlmComponentGenerate prompt length=%zu", promptStr.length());

    std::string configStorage;
    const char* config = getNullableCString(env, configJson, configStorage);

    rac_llm_options_t options = {};
    options.max_tokens = 512;
    options.temperature = 0.7f;
    options.top_p = 1.0f;
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t result = {};
    LOGi("racLlmComponentGenerate calling rac_llm_component_generate...");

    rac_result_t status = rac_llm_component_generate(
        reinterpret_cast<rac_handle_t>(handle),
        promptStr.c_str(),
        &options,
        &result
    );

    LOGi("racLlmComponentGenerate status=%d", status);

    if (status != RAC_SUCCESS) {
        LOGe("racLlmComponentGenerate failed with status=%d", status);
        return nullptr;
    }

    // Return result as JSON string
    if (result.text != nullptr) {
        LOGi("racLlmComponentGenerate result text length=%zu", strlen(result.text));

        // Build JSON result - keys must match what Kotlin expects
        std::string json = "{";
        json += "\"text\":\"";
        // Escape special characters in text for JSON
        for (const char* p = result.text; *p; p++) {
            switch (*p) {
                case '"': json += "\\\""; break;
                case '\\': json += "\\\\"; break;
                case '\n': json += "\\n"; break;
                case '\r': json += "\\r"; break;
                case '\t': json += "\\t"; break;
                default: json += *p; break;
            }
        }
        json += "\",";
        // Kotlin expects these keys:
        json += "\"tokens_generated\":" + std::to_string(result.completion_tokens) + ",";
        json += "\"tokens_evaluated\":" + std::to_string(result.prompt_tokens) + ",";
        json += "\"stop_reason\":" + std::to_string(0) + ",";  // 0 = normal completion
        json += "\"total_time_ms\":" + std::to_string(result.total_time_ms) + ",";
        json += "\"tokens_per_second\":" + std::to_string(result.tokens_per_second);
        json += "}";

        LOGi("racLlmComponentGenerate returning JSON: %zu bytes", json.length());

        jstring jResult = env->NewStringUTF(json.c_str());
        rac_llm_result_free(&result);
        return jResult;
    }

    LOGw("racLlmComponentGenerate: result.text is null");
    return env->NewStringUTF("{\"text\":\"\",\"completion_tokens\":0}");
}

// ========================================================================
// STREAMING CONTEXT - for collecting tokens during stream generation
// ========================================================================

struct LLMStreamContext {
    std::string accumulated_text;
    int token_count = 0;
    bool is_complete = false;
    bool has_error = false;
    rac_result_t error_code = RAC_SUCCESS;
    std::string error_message;
    rac_llm_result_t final_result = {};
    std::mutex mtx;
    std::condition_variable cv;
};

static rac_bool_t llm_stream_token_callback(const char* token, void* user_data) {
    if (!user_data || !token) return RAC_TRUE;

    auto* ctx = static_cast<LLMStreamContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    ctx->accumulated_text += token;
    ctx->token_count++;

    // Log every 10 tokens to avoid spam
    if (ctx->token_count % 10 == 0) {
        LOGi("Streaming: %d tokens accumulated", ctx->token_count);
    }

    return RAC_TRUE; // Continue streaming
}

static void llm_stream_complete_callback(const rac_llm_result_t* result, void* user_data) {
    if (!user_data) return;

    auto* ctx = static_cast<LLMStreamContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    LOGi("Streaming complete: %d tokens", ctx->token_count);

    // Copy final result metrics if available
    if (result) {
        ctx->final_result.completion_tokens = result->completion_tokens > 0 ? result->completion_tokens : ctx->token_count;
        ctx->final_result.prompt_tokens = result->prompt_tokens;
        ctx->final_result.total_tokens = result->total_tokens;
        ctx->final_result.total_time_ms = result->total_time_ms;
        ctx->final_result.tokens_per_second = result->tokens_per_second;
    } else {
        ctx->final_result.completion_tokens = ctx->token_count;
    }

    ctx->is_complete = true;
    ctx->cv.notify_one();
}

static void llm_stream_error_callback(rac_result_t error_code, const char* error_message, void* user_data) {
    if (!user_data) return;

    auto* ctx = static_cast<LLMStreamContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    LOGe("Streaming error: %d - %s", error_code, error_message ? error_message : "Unknown");

    ctx->has_error = true;
    ctx->error_code = error_code;
    ctx->error_message = error_message ? error_message : "Unknown error";
    ctx->is_complete = true;
    ctx->cv.notify_one();
}

// ========================================================================
// STREAMING WITH CALLBACK - Real-time token streaming to Kotlin
// ========================================================================

struct LLMStreamCallbackContext {
    JavaVM* jvm = nullptr;
    jobject callback = nullptr;
    jmethodID onTokenMethod = nullptr;
    std::string accumulated_text;
    int token_count = 0;
    bool is_complete = false;
    bool has_error = false;
    rac_result_t error_code = RAC_SUCCESS;
    std::string error_message;
    rac_llm_result_t final_result = {};
};

static rac_bool_t llm_stream_callback_token(const char* token, void* user_data) {
    if (!user_data || !token) return RAC_TRUE;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);

    // Accumulate token
    ctx->accumulated_text += token;
    ctx->token_count++;

    // Call back to Kotlin
    if (ctx->jvm && ctx->callback && ctx->onTokenMethod) {
        JNIEnv* env = nullptr;
        bool needsDetach = false;

        jint result = ctx->jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
        if (result == JNI_EDETACHED) {
            if (ctx->jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
                needsDetach = true;
            } else {
                LOGe("Failed to attach thread for streaming callback");
                return RAC_TRUE;
            }
        }

        if (env) {
            jstring jToken = env->NewStringUTF(token);
            jboolean continueGen = env->CallBooleanMethod(ctx->callback, ctx->onTokenMethod, jToken);
            env->DeleteLocalRef(jToken);

            if (env->ExceptionCheck()) {
                env->ExceptionDescribe();
                env->ExceptionClear();
            }

            if (needsDetach) {
                ctx->jvm->DetachCurrentThread();
            }

            if (!continueGen) {
                LOGi("Streaming cancelled by callback");
                return RAC_FALSE; // Stop streaming
            }
        }
    }

    return RAC_TRUE; // Continue streaming
}

static void llm_stream_callback_complete(const rac_llm_result_t* result, void* user_data) {
    if (!user_data) return;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);

    LOGi("Streaming with callback complete: %d tokens", ctx->token_count);

    if (result) {
        ctx->final_result.completion_tokens = result->completion_tokens > 0 ? result->completion_tokens : ctx->token_count;
        ctx->final_result.prompt_tokens = result->prompt_tokens;
        ctx->final_result.total_tokens = result->total_tokens;
        ctx->final_result.total_time_ms = result->total_time_ms;
        ctx->final_result.tokens_per_second = result->tokens_per_second;
    } else {
        ctx->final_result.completion_tokens = ctx->token_count;
    }

    ctx->is_complete = true;
}

static void llm_stream_callback_error(rac_result_t error_code, const char* error_message, void* user_data) {
    if (!user_data) return;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);

    LOGe("Streaming with callback error: %d - %s", error_code, error_message ? error_message : "Unknown");

    ctx->has_error = true;
    ctx->error_code = error_code;
    ctx->error_message = error_message ? error_message : "Unknown error";
    ctx->is_complete = true;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerateStream(JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
    LOGi("racLlmComponentGenerateStream called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racLlmComponentGenerateStream: invalid handle");
        return nullptr;
    }

    std::string promptStr = getCString(env, prompt);
    LOGi("racLlmComponentGenerateStream prompt length=%zu", promptStr.length());

    std::string configStorage;
    const char* config = getNullableCString(env, configJson, configStorage);

    // Parse config for options
    rac_llm_options_t options = {};
    options.max_tokens = 512;
    options.temperature = 0.7f;
    options.top_p = 1.0f;
    options.streaming_enabled = RAC_TRUE;

    // Create streaming context
    LLMStreamContext ctx;

    LOGi("racLlmComponentGenerateStream calling rac_llm_component_generate_stream...");

    rac_result_t status = rac_llm_component_generate_stream(
        reinterpret_cast<rac_handle_t>(handle),
        promptStr.c_str(),
        &options,
        llm_stream_token_callback,
        llm_stream_complete_callback,
        llm_stream_error_callback,
        &ctx
    );

    if (status != RAC_SUCCESS) {
        LOGe("rac_llm_component_generate_stream failed with status=%d", status);
        return nullptr;
    }

    // Wait for streaming to complete
    {
        std::unique_lock<std::mutex> lock(ctx.mtx);
        ctx.cv.wait(lock, [&ctx] { return ctx.is_complete; });
    }

    if (ctx.has_error) {
        LOGe("Streaming failed: %s", ctx.error_message.c_str());
        return nullptr;
    }

    LOGi("racLlmComponentGenerateStream result text length=%zu, tokens=%d",
         ctx.accumulated_text.length(), ctx.token_count);

    // Build JSON result - keys must match what Kotlin expects
    std::string json = "{";
    json += "\"text\":\"";
    // Escape special characters in text for JSON
    for (char c : ctx.accumulated_text) {
        switch (c) {
            case '"': json += "\\\""; break;
            case '\\': json += "\\\\"; break;
            case '\n': json += "\\n"; break;
            case '\r': json += "\\r"; break;
            case '\t': json += "\\t"; break;
            default: json += c; break;
        }
    }
    json += "\",";
    // Kotlin expects these keys:
    json += "\"tokens_generated\":" + std::to_string(ctx.final_result.completion_tokens) + ",";
    json += "\"tokens_evaluated\":" + std::to_string(ctx.final_result.prompt_tokens) + ",";
    json += "\"stop_reason\":" + std::to_string(0) + ",";  // 0 = normal completion
    json += "\"total_time_ms\":" + std::to_string(ctx.final_result.total_time_ms) + ",";
    json += "\"tokens_per_second\":" + std::to_string(ctx.final_result.tokens_per_second);
    json += "}";

    LOGi("racLlmComponentGenerateStream returning JSON: %zu bytes", json.length());

    return env->NewStringUTF(json.c_str());
}

// ========================================================================
// STREAMING WITH KOTLIN CALLBACK - Real-time token-by-token streaming
// ========================================================================

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerateStreamWithCallback(
    JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson, jobject tokenCallback) {

    LOGi("racLlmComponentGenerateStreamWithCallback called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racLlmComponentGenerateStreamWithCallback: invalid handle");
        return nullptr;
    }

    if (!tokenCallback) {
        LOGe("racLlmComponentGenerateStreamWithCallback: null callback");
        return nullptr;
    }

    std::string promptStr = getCString(env, prompt);
    LOGi("racLlmComponentGenerateStreamWithCallback prompt length=%zu", promptStr.length());

    std::string configStorage;
    const char* config = getNullableCString(env, configJson, configStorage);

    // Get JVM and callback method
    JavaVM* jvm = nullptr;
    env->GetJavaVM(&jvm);

    jclass callbackClass = env->GetObjectClass(tokenCallback);
    jmethodID onTokenMethod = env->GetMethodID(callbackClass, "onToken", "(Ljava/lang/String;)Z");

    if (!onTokenMethod) {
        LOGe("racLlmComponentGenerateStreamWithCallback: could not find onToken method");
        return nullptr;
    }

    // Create global ref to callback to ensure it survives across threads
    jobject globalCallback = env->NewGlobalRef(tokenCallback);

    // Parse config for options
    rac_llm_options_t options = {};
    options.max_tokens = 512;
    options.temperature = 0.7f;
    options.top_p = 1.0f;
    options.streaming_enabled = RAC_TRUE;

    // Create streaming callback context
    LLMStreamCallbackContext ctx;
    ctx.jvm = jvm;
    ctx.callback = globalCallback;
    ctx.onTokenMethod = onTokenMethod;

    LOGi("racLlmComponentGenerateStreamWithCallback calling rac_llm_component_generate_stream...");

    rac_result_t status = rac_llm_component_generate_stream(
        reinterpret_cast<rac_handle_t>(handle),
        promptStr.c_str(),
        &options,
        llm_stream_callback_token,
        llm_stream_callback_complete,
        llm_stream_callback_error,
        &ctx
    );

    // Clean up global ref
    env->DeleteGlobalRef(globalCallback);

    if (status != RAC_SUCCESS) {
        LOGe("rac_llm_component_generate_stream failed with status=%d", status);
        return nullptr;
    }

    if (ctx.has_error) {
        LOGe("Streaming failed: %s", ctx.error_message.c_str());
        return nullptr;
    }

    LOGi("racLlmComponentGenerateStreamWithCallback result text length=%zu, tokens=%d",
         ctx.accumulated_text.length(), ctx.token_count);

    // Build JSON result
    std::string json = "{";
    json += "\"text\":\"";
    for (char c : ctx.accumulated_text) {
        switch (c) {
            case '"': json += "\\\""; break;
            case '\\': json += "\\\\"; break;
            case '\n': json += "\\n"; break;
            case '\r': json += "\\r"; break;
            case '\t': json += "\\t"; break;
            default: json += c; break;
        }
    }
    json += "\",";
    json += "\"tokens_generated\":" + std::to_string(ctx.final_result.completion_tokens) + ",";
    json += "\"tokens_evaluated\":" + std::to_string(ctx.final_result.prompt_tokens) + ",";
    json += "\"stop_reason\":" + std::to_string(0) + ",";
    json += "\"total_time_ms\":" + std::to_string(ctx.final_result.total_time_ms) + ",";
    json += "\"tokens_per_second\":" + std::to_string(ctx.final_result.tokens_per_second);
    json += "}";

    LOGi("racLlmComponentGenerateStreamWithCallback returning JSON: %zu bytes", json.length());

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_llm_component_cancel(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetContextSize(JNIEnv* env, jclass clazz, jlong handle) {
    // NOTE: rac_llm_component_get_context_size is not in current API, returning default
    if (handle == 0) return 0;
    return 4096; // Default context size
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentTokenize(JNIEnv* env, jclass clazz, jlong handle, jstring text) {
    // NOTE: rac_llm_component_tokenize is not in current API, returning estimate
    if (handle == 0) return 0;
    std::string textStr = getCString(env, text);
    // Rough token estimate: ~4 chars per token
    return static_cast<jint>(textStr.length() / 4);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_llm_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_llm_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE : JNI_FALSE;
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
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_stt_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create STT component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_stt_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    LOGi("racSttComponentLoadModel called with handle=%lld", (long long)handle);
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    LOGi("racSttComponentLoadModel model_id=%s", path.c_str());

    // Debug: List registered providers BEFORE loading
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);
    LOGi("Before load_model - STT providers: count=%zu, list_result=%d", provider_count, list_result);
    if (provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            LOGi("  Provider[%zu]: %s", i, provider_names[i] ? provider_names[i] : "NULL");
        }
    } else {
        LOGw("NO providers registered for STT!");
    }

    rac_result_t result = rac_stt_component_load_model(
        reinterpret_cast<rac_handle_t>(handle),
        path.c_str()
    );
    LOGi("rac_stt_component_load_model returned: %d", result);

    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_stt_component_unload(reinterpret_cast<rac_handle_t>(handle));
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
        reinterpret_cast<rac_handle_t>(handle),
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
    // NOTE: rac_stt_component_transcribe_file does not exist in current API
    // This is a stub - actual implementation would need to read file and call transcribe
    if (handle == 0) return nullptr;
    return env->NewStringUTF("{\"error\": \"transcribe_file not implemented\"}");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribeStream(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribe(env, clazz, handle, audioData, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    // STT component doesn't have a cancel method, just unload
    if (handle != 0) {
        rac_stt_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_stt_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_stt_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE : JNI_FALSE;
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
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_tts_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create TTS component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_tts_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    std::string voiceId = getCString(env, modelPath);  // modelPath is actually voiceId for TTS

    // TTS component uses load_voice instead of load_model
    return static_cast<jint>(rac_tts_component_load_voice(
        reinterpret_cast<rac_handle_t>(handle),
        voiceId.c_str()
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_tts_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesize(JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring configJson) {
    if (handle == 0) return nullptr;

    std::string textStr = getCString(env, text);
    rac_tts_options_t options = {};
    rac_tts_result_t result = {};

    rac_result_t status = rac_tts_component_synthesize(
        reinterpret_cast<rac_handle_t>(handle),
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
    rac_tts_result_t result = {};

    rac_result_t status = rac_tts_component_synthesize(
        reinterpret_cast<rac_handle_t>(handle),
        textStr.c_str(),
        &options,
        &result
    );

    // TODO: Write result to file
    rac_tts_result_free(&result);

    return status == RAC_SUCCESS ? 0 : -1;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCancel(JNIEnv* env, jclass clazz, jlong handle) {
    // TTS component doesn't have a cancel method, just unload
    if (handle != 0) {
        rac_tts_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_tts_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_tts_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetVoices(JNIEnv* env, jclass clazz, jlong handle) {
    return env->NewStringUTF("[]");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSetVoice(JNIEnv* env, jclass clazz, jlong handle, jstring voiceId) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;
    std::string voice = getCString(env, voiceId);
    return static_cast<jint>(rac_tts_component_load_voice(
        reinterpret_cast<rac_handle_t>(handle),
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
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_vad_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create VAD component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentDestroy(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentLoadModel(JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0) return RAC_ERROR_INVALID_HANDLE;

    // Initialize and configure the VAD component
    return static_cast<jint>(rac_vad_component_initialize(
        reinterpret_cast<rac_handle_t>(handle)
    ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentUnload(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_cleanup(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    if (handle == 0 || audioData == nullptr) return nullptr;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    rac_bool_t out_is_speech = RAC_FALSE;
    rac_result_t status = rac_vad_component_process(
        reinterpret_cast<rac_handle_t>(handle),
        reinterpret_cast<const float*>(data),
        static_cast<size_t>(len / sizeof(float)),
        &out_is_speech
    );

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    // Return JSON result
    char jsonBuf[256];
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"is_speech\":%s,\"probability\":%.4f}",
             out_is_speech ? "true" : "false",
             out_is_speech ? 1.0f : 0.0f);

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
        rac_vad_component_stop(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentReset(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle != 0) {
        rac_vad_component_reset(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetState(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return 0;
    return static_cast<jint>(rac_vad_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentIsLoaded(JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) return JNI_FALSE;
    return rac_vad_component_is_initialized(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetMinFrameSize(JNIEnv* env, jclass clazz, jlong handle) {
    // Default minimum frame size: 512 samples at 16kHz = 32ms
    if (handle == 0) return 0;
    return 512;
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
// JNI FUNCTIONS - Model Registry (mirrors Swift CppBridge+ModelRegistry.swift)
// =============================================================================

// Helper to convert Java ModelInfo to C struct
static rac_model_info_t* javaModelInfoToC(JNIEnv* env, jobject modelInfo) {
    if (!modelInfo) return nullptr;

    jclass cls = env->GetObjectClass(modelInfo);
    if (!cls) return nullptr;

    rac_model_info_t* model = rac_model_info_alloc();
    if (!model) return nullptr;

    // Get fields
    jfieldID idField = env->GetFieldID(cls, "modelId", "Ljava/lang/String;");
    jfieldID nameField = env->GetFieldID(cls, "name", "Ljava/lang/String;");
    jfieldID categoryField = env->GetFieldID(cls, "category", "I");
    jfieldID formatField = env->GetFieldID(cls, "format", "I");
    jfieldID frameworkField = env->GetFieldID(cls, "framework", "I");
    jfieldID downloadUrlField = env->GetFieldID(cls, "downloadUrl", "Ljava/lang/String;");
    jfieldID localPathField = env->GetFieldID(cls, "localPath", "Ljava/lang/String;");
    jfieldID downloadSizeField = env->GetFieldID(cls, "downloadSize", "J");
    jfieldID contextLengthField = env->GetFieldID(cls, "contextLength", "I");
    jfieldID supportsThinkingField = env->GetFieldID(cls, "supportsThinking", "Z");
    jfieldID descriptionField = env->GetFieldID(cls, "description", "Ljava/lang/String;");

    // Read and convert values
    jstring jId = (jstring)env->GetObjectField(modelInfo, idField);
    if (jId) {
        const char* str = env->GetStringUTFChars(jId, nullptr);
        model->id = strdup(str);
        env->ReleaseStringUTFChars(jId, str);
    }

    jstring jName = (jstring)env->GetObjectField(modelInfo, nameField);
    if (jName) {
        const char* str = env->GetStringUTFChars(jName, nullptr);
        model->name = strdup(str);
        env->ReleaseStringUTFChars(jName, str);
    }

    model->category = static_cast<rac_model_category_t>(env->GetIntField(modelInfo, categoryField));
    model->format = static_cast<rac_model_format_t>(env->GetIntField(modelInfo, formatField));
    model->framework = static_cast<rac_inference_framework_t>(env->GetIntField(modelInfo, frameworkField));

    jstring jDownloadUrl = (jstring)env->GetObjectField(modelInfo, downloadUrlField);
    if (jDownloadUrl) {
        const char* str = env->GetStringUTFChars(jDownloadUrl, nullptr);
        model->download_url = strdup(str);
        env->ReleaseStringUTFChars(jDownloadUrl, str);
    }

    jstring jLocalPath = (jstring)env->GetObjectField(modelInfo, localPathField);
    if (jLocalPath) {
        const char* str = env->GetStringUTFChars(jLocalPath, nullptr);
        model->local_path = strdup(str);
        env->ReleaseStringUTFChars(jLocalPath, str);
    }

    model->download_size = env->GetLongField(modelInfo, downloadSizeField);
    model->context_length = env->GetIntField(modelInfo, contextLengthField);
    model->supports_thinking = env->GetBooleanField(modelInfo, supportsThinkingField) ? RAC_TRUE : RAC_FALSE;

    jstring jDesc = (jstring)env->GetObjectField(modelInfo, descriptionField);
    if (jDesc) {
        const char* str = env->GetStringUTFChars(jDesc, nullptr);
        model->description = strdup(str);
        env->ReleaseStringUTFChars(jDesc, str);
    }

    return model;
}

// Helper to convert C model info to JSON string for Kotlin
static std::string modelInfoToJson(const rac_model_info_t* model) {
    if (!model) return "null";

    std::string json = "{";
    json += "\"model_id\":\"" + std::string(model->id ? model->id : "") + "\",";
    json += "\"name\":\"" + std::string(model->name ? model->name : "") + "\",";
    json += "\"category\":" + std::to_string(static_cast<int>(model->category)) + ",";
    json += "\"format\":" + std::to_string(static_cast<int>(model->format)) + ",";
    json += "\"framework\":" + std::to_string(static_cast<int>(model->framework)) + ",";
    json += "\"download_url\":" + (model->download_url ? ("\"" + std::string(model->download_url) + "\"") : "null") + ",";
    json += "\"local_path\":" + (model->local_path ? ("\"" + std::string(model->local_path) + "\"") : "null") + ",";
    json += "\"download_size\":" + std::to_string(model->download_size) + ",";
    json += "\"context_length\":" + std::to_string(model->context_length) + ",";
    json += "\"supports_thinking\":" + std::string(model->supports_thinking ? "true" : "false") + ",";
    json += "\"description\":" + (model->description ? ("\"" + std::string(model->description) + "\"") : "null");
    json += "}";

    return json;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistrySave(JNIEnv* env, jclass clazz,
    jstring modelId, jstring name, jint category, jint format, jint framework,
    jstring downloadUrl, jstring localPath, jlong downloadSize, jint contextLength,
    jboolean supportsThinking, jstring description) {

    LOGi("racModelRegistrySave called");

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("Model registry not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Allocate and populate model info
    rac_model_info_t* model = rac_model_info_alloc();
    if (!model) {
        LOGe("Failed to allocate model info");
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Convert strings
    const char* id_str = modelId ? env->GetStringUTFChars(modelId, nullptr) : nullptr;
    const char* name_str = name ? env->GetStringUTFChars(name, nullptr) : nullptr;
    const char* url_str = downloadUrl ? env->GetStringUTFChars(downloadUrl, nullptr) : nullptr;
    const char* path_str = localPath ? env->GetStringUTFChars(localPath, nullptr) : nullptr;
    const char* desc_str = description ? env->GetStringUTFChars(description, nullptr) : nullptr;

    model->id = id_str ? strdup(id_str) : nullptr;
    model->name = name_str ? strdup(name_str) : nullptr;
    model->category = static_cast<rac_model_category_t>(category);
    model->format = static_cast<rac_model_format_t>(format);
    model->framework = static_cast<rac_inference_framework_t>(framework);
    model->download_url = url_str ? strdup(url_str) : nullptr;
    model->local_path = path_str ? strdup(path_str) : nullptr;
    model->download_size = downloadSize;
    model->context_length = contextLength;
    model->supports_thinking = supportsThinking ? RAC_TRUE : RAC_FALSE;
    model->description = desc_str ? strdup(desc_str) : nullptr;

    // Release Java strings
    if (id_str) env->ReleaseStringUTFChars(modelId, id_str);
    if (name_str) env->ReleaseStringUTFChars(name, name_str);
    if (url_str) env->ReleaseStringUTFChars(downloadUrl, url_str);
    if (path_str) env->ReleaseStringUTFChars(localPath, path_str);
    if (desc_str) env->ReleaseStringUTFChars(description, desc_str);

    LOGi("Saving model to C++ registry: %s (framework=%d)", model->id, framework);

    rac_result_t result = rac_model_registry_save(registry, model);

    // Free the model info (registry makes a copy)
    rac_model_info_free(model);

    if (result != RAC_SUCCESS) {
        LOGe("Failed to save model to registry: %d", result);
    } else {
        LOGi("Model saved to C++ registry successfully");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGet(JNIEnv* env, jclass clazz, jstring modelId) {
    if (!modelId) return nullptr;

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("Model registry not initialized");
        return nullptr;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);

    rac_model_info_t* model = nullptr;
    rac_result_t result = rac_model_registry_get(registry, id_str, &model);

    env->ReleaseStringUTFChars(modelId, id_str);

    if (result != RAC_SUCCESS || !model) {
        return nullptr;
    }

    std::string json = modelInfoToJson(model);
    rac_model_info_free(model);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGetAll(JNIEnv* env, jclass clazz) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("Model registry not initialized");
        return env->NewStringUTF("[]");
    }

    rac_model_info_t** models = nullptr;
    size_t count = 0;

    rac_result_t result = rac_model_registry_get_all(registry, &models, &count);

    if (result != RAC_SUCCESS || !models || count == 0) {
        return env->NewStringUTF("[]");
    }

    std::string json = "[";
    for (size_t i = 0; i < count; i++) {
        if (i > 0) json += ",";
        json += modelInfoToJson(models[i]);
    }
    json += "]";

    rac_model_info_array_free(models, count);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGetDownloaded(JNIEnv* env, jclass clazz) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return env->NewStringUTF("[]");
    }

    rac_model_info_t** models = nullptr;
    size_t count = 0;

    rac_result_t result = rac_model_registry_get_downloaded(registry, &models, &count);

    if (result != RAC_SUCCESS || !models || count == 0) {
        return env->NewStringUTF("[]");
    }

    std::string json = "[";
    for (size_t i = 0; i < count; i++) {
        if (i > 0) json += ",";
        json += modelInfoToJson(models[i]);
    }
    json += "]";

    rac_model_info_array_free(models, count);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryRemove(JNIEnv* env, jclass clazz, jstring modelId) {
    if (!modelId) return RAC_ERROR_NULL_POINTER;

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    rac_result_t result = rac_model_registry_remove(registry, id_str);
    env->ReleaseStringUTFChars(modelId, id_str);

    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryUpdateDownloadStatus(JNIEnv* env, jclass clazz, jstring modelId, jstring localPath) {
    if (!modelId) return RAC_ERROR_NULL_POINTER;

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    const char* path_str = localPath ? env->GetStringUTFChars(localPath, nullptr) : nullptr;

    LOGi("Updating download status: %s -> %s", id_str, path_str ? path_str : "null");

    rac_result_t result = rac_model_registry_update_download_status(registry, id_str, path_str);

    env->ReleaseStringUTFChars(modelId, id_str);
    if (path_str) env->ReleaseStringUTFChars(localPath, path_str);

    return static_cast<jint>(result);
}

} // extern "C"

// =============================================================================
// NOTE: Backend registration functions have been MOVED to their respective
// backend JNI libraries:
//
//   LlamaCPP: backends/llamacpp/src/jni/rac_backend_llamacpp_jni.cpp
//             -> Java class: com.runanywhere.sdk.llm.llamacpp.LlamaCPPBridge
//
//   ONNX:     backends/onnx/src/jni/rac_backend_onnx_jni.cpp
//             -> Java class: com.runanywhere.sdk.core.onnx.ONNXBridge
//
// This mirrors the Swift SDK architecture where each backend has its own
// XCFramework (RABackendLlamaCPP, RABackendONNX).
// =============================================================================
