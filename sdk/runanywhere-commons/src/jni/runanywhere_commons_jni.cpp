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

#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>
#include <nlohmann/json.hpp>

// Include runanywhere-commons C API headers
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"
#include "rac/features/llm/rac_tool_calling.h"

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
#define LOGi(...)                           \
    fprintf(stdout, "[INFO] " __VA_ARGS__); \
    fprintf(stdout, "\n")
#define LOGe(...)                            \
    fprintf(stderr, "[ERROR] " __VA_ARGS__); \
    fprintf(stderr, "\n")
#define LOGw(...)                           \
    fprintf(stdout, "[WARN] " __VA_ARGS__); \
    fprintf(stdout, "\n")
#define LOGd(...)                            \
    fprintf(stdout, "[DEBUG] " __VA_ARGS__); \
    fprintf(stdout, "\n")
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
    if (g_jvm == nullptr)
        return nullptr;

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
    if (str == nullptr)
        return "";
    const char* chars = env->GetStringUTFChars(str, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(str, chars);
    return result;
}

static const char* getNullableCString(JNIEnv* env, jstring str, std::string& storage) {
    if (str == nullptr)
        return nullptr;
    storage = getCString(env, str);
    return storage.c_str();
}

// =============================================================================
// Platform Adapter C Callbacks (called by C++ library)
// =============================================================================

// Forward declaration of the adapter struct
static rac_platform_adapter_t g_c_adapter;

static void jni_log_callback(rac_log_level_t level, const char* tag, const char* message,
                             void* user_data) {
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

static rac_result_t jni_file_read_callback(const char* path, void** out_data, size_t* out_size,
                                           void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_read == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jbyteArray result = static_cast<jbyteArray>(
        env->CallObjectMethod(g_platform_adapter, g_method_file_read, jPath));
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

static rac_result_t jni_file_write_callback(const char* path, const void* data, size_t size,
                                            void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_write == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jbyteArray jData = env->NewByteArray(static_cast<jsize>(size));
    env->SetByteArrayRegion(jData, 0, static_cast<jsize>(size),
                            reinterpret_cast<const jbyte*>(data));

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
    jstring result =
        static_cast<jstring>(env->CallObjectMethod(g_platform_adapter, g_method_secure_get, jKey));
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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racIsInitialized(JNIEnv* env,
                                                                          jclass clazz) {
    return rac_is_initialized() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSetPlatformAdapter(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jobject adapter) {
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

    g_method_log =
        env->GetMethodID(adapterClass, "log", "(ILjava/lang/String;Ljava/lang/String;)V");
    g_method_file_exists = env->GetMethodID(adapterClass, "fileExists", "(Ljava/lang/String;)Z");
    g_method_file_read = env->GetMethodID(adapterClass, "fileRead", "(Ljava/lang/String;)[B");
    g_method_file_write = env->GetMethodID(adapterClass, "fileWrite", "(Ljava/lang/String;[B)Z");
    g_method_file_delete = env->GetMethodID(adapterClass, "fileDelete", "(Ljava/lang/String;)Z");
    g_method_secure_get =
        env->GetMethodID(adapterClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
    g_method_secure_set =
        env->GetMethodID(adapterClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
    g_method_secure_delete =
        env->GetMethodID(adapterClass, "secureDelete", "(Ljava/lang/String;)Z");
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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racGetPlatformAdapter(JNIEnv* env,
                                                                               jclass clazz) {
    std::lock_guard<std::mutex> lock(g_adapter_mutex);
    return g_platform_adapter;
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racConfigureLogging(
    JNIEnv* env, jclass clazz, jint level, jstring logFilePath) {
    // For now, just configure the log level
    // The log file path is not used in the current implementation
    rac_result_t result = rac_configure_logging(static_cast<rac_environment_t>(0));  // Development
    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLog(
    JNIEnv* env, jclass clazz, jint level, jstring tag, jstring message) {
    std::string tagStr = getCString(env, tag);
    std::string msgStr = getCString(env, message);

    rac_log(static_cast<rac_log_level_t>(level), tagStr.c_str(), msgStr.c_str());
}

// =============================================================================
// JNI FUNCTIONS - LLM Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_llm_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create LLM component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_llm_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    LOGi("racLlmComponentLoadModel called with handle=%lld", (long long)handle);
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    LOGi("racLlmComponentLoadModel path=%s, id=%s, name=%s", path.c_str(), id.c_str(),
         name.c_str());

    // Debug: List registered providers BEFORE loading
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_TEXT_GENERATION,
                                                          &provider_names, &provider_count);
    LOGi("Before load_model - TEXT_GENERATION providers: count=%zu, list_result=%d", provider_count,
         list_result);
    if (provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            LOGi("  Provider[%zu]: %s", i, provider_names[i] ? provider_names[i] : "NULL");
        }
    } else {
        LOGw("NO providers registered for TEXT_GENERATION!");
    }

    // Pass model_path, model_id, and model_name separately to C++ lifecycle
    rac_result_t result = rac_llm_component_load_model(
        reinterpret_cast<rac_handle_t>(handle),
        path.c_str(),                          // model_path
        id.c_str(),                            // model_id (for telemetry)
        name.empty() ? nullptr : name.c_str()  // model_name (optional, for telemetry)
    );
    LOGi("rac_llm_component_load_model returned: %d", result);

    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_llm_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerate(
    JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
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
    options.system_prompt = RAC_NULL;

    // Parse configJson if provided
    std::string sys_prompt_storage;
    if (config != nullptr) {
        try {
            auto j = nlohmann::json::parse(config);
            options.max_tokens = j.value("max_tokens", 512);
            options.temperature = j.value("temperature", 0.7f);
            options.top_p = j.value("top_p", 1.0f);
            sys_prompt_storage = j.value("system_prompt", std::string(""));
            if (!sys_prompt_storage.empty()) {
                options.system_prompt = sys_prompt_storage.c_str();
            }
        } catch (const nlohmann::json::exception& e) {
            LOGe("Failed to parse LLM config JSON: %s", e.what());
        }
    }

    LOGi("racLlmComponentGenerate options: temp=%.2f, max_tokens=%d, top_p=%.2f, system_prompt=%s",
         options.temperature, options.max_tokens, options.top_p,
         options.system_prompt ? "(set)" : "(none)");

    rac_llm_result_t result = {};
    LOGi("racLlmComponentGenerate calling rac_llm_component_generate...");

    rac_result_t status = rac_llm_component_generate(reinterpret_cast<rac_handle_t>(handle),
                                                     promptStr.c_str(), &options, &result);

    LOGi("racLlmComponentGenerate status=%d", status);

    if (status != RAC_SUCCESS) {
        LOGe("racLlmComponentGenerate failed with status=%d", status);
        rac_llm_result_free(&result);
        const char* msg = rac_error_message(status);
        jclass exClass = env->FindClass("java/lang/RuntimeException");
        if (exClass) {
            char fallback[64];
            if (!msg || !*msg) {
                snprintf(fallback, sizeof(fallback), "LLM generation failed (status=%d)", status);
                msg = fallback;
            }
            env->ThrowNew(exClass, msg);
            env->DeleteLocalRef(exClass);
        }
        return nullptr;
    }

    // Return result as JSON string
    if (result.text != nullptr) {
        LOGi("racLlmComponentGenerate result text length=%zu", strlen(result.text));

        // Build JSON result - keys must match what Kotlin expects
        nlohmann::json json_obj;
        json_obj["text"] = std::string(result.text);
        json_obj["tokens_generated"] = result.completion_tokens;
        json_obj["tokens_evaluated"] = result.prompt_tokens;
        json_obj["stop_reason"] = 0;  // 0 = normal completion
        json_obj["total_time_ms"] = result.total_time_ms;
        json_obj["tokens_per_second"] = result.tokens_per_second;
        std::string json = json_obj.dump();

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
    if (!user_data || !token)
        return RAC_TRUE;

    auto* ctx = static_cast<LLMStreamContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    ctx->accumulated_text += token;
    ctx->token_count++;

    // Log every 10 tokens to avoid spam
    if (ctx->token_count % 10 == 0) {
        LOGi("Streaming: %d tokens accumulated", ctx->token_count);
    }

    return RAC_TRUE;  // Continue streaming
}

static void llm_stream_complete_callback(const rac_llm_result_t* result, void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<LLMStreamContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    LOGi("Streaming complete: %d tokens", ctx->token_count);

    // Copy final result metrics if available
    if (result) {
        ctx->final_result.completion_tokens =
            result->completion_tokens > 0 ? result->completion_tokens : ctx->token_count;
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

static void llm_stream_error_callback(rac_result_t error_code, const char* error_message,
                                      void* user_data) {
    if (!user_data)
        return;

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
    bool onTokenExpectsBytes = true;
    std::mutex mtx;
    std::condition_variable cv;
    std::string accumulated_text;
    int token_count = 0;
    bool is_complete = false;
    bool has_error = false;
    rac_result_t error_code = RAC_SUCCESS;
    std::string error_message;
    rac_llm_result_t final_result = {};
};

static rac_bool_t llm_stream_callback_token(const char* token, void* user_data) {
    if (!user_data || !token)
        return RAC_TRUE;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);

    // Accumulate token (thread-safe)
    {
        std::lock_guard<std::mutex> lock(ctx->mtx);
        ctx->accumulated_text += token;
        ctx->token_count++;
    }

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
            jboolean continueGen = JNI_TRUE;

            if (ctx->onTokenExpectsBytes) {
                jsize len = static_cast<jsize>(strlen(token));
                jbyteArray jToken = env->NewByteArray(len);
                env->SetByteArrayRegion(
                    jToken,
                    0,
                    len,
                    reinterpret_cast<const jbyte*>(token)
                );
                continueGen = env->CallBooleanMethod(ctx->callback, ctx->onTokenMethod, jToken);
                env->DeleteLocalRef(jToken);
            } else {
                jstring jToken = env->NewStringUTF(token);
                continueGen = env->CallBooleanMethod(ctx->callback, ctx->onTokenMethod, jToken);
                env->DeleteLocalRef(jToken);
            }

            const bool hadException = env->ExceptionCheck();
            if (hadException) {
                env->ExceptionDescribe();
                env->ExceptionClear();
            }

            if (needsDetach) {
                ctx->jvm->DetachCurrentThread();
            }

            if (hadException) {
                // Ignore callback return value when JNI exception was thrown.
                return RAC_TRUE;
            }

            if (!continueGen) {
                LOGi("Streaming cancelled by callback");
                return RAC_FALSE;  // Stop streaming
            }
        }
    }

    return RAC_TRUE;  // Continue streaming
}

static void llm_stream_callback_complete(const rac_llm_result_t* result, void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    LOGi("Streaming with callback complete: %d tokens", ctx->token_count);

    if (result) {
        ctx->final_result.completion_tokens =
            result->completion_tokens > 0 ? result->completion_tokens : ctx->token_count;
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

static void llm_stream_callback_error(rac_result_t error_code, const char* error_message,
                                      void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);
    std::lock_guard<std::mutex> lock(ctx->mtx);

    LOGe("Streaming with callback error: %d - %s", error_code,
         error_message ? error_message : "Unknown");

    ctx->has_error = true;
    ctx->error_code = error_code;
    ctx->error_message = error_message ? error_message : "Unknown error";
    ctx->is_complete = true;
    ctx->cv.notify_one();
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerateStream(
    JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson) {
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
    options.system_prompt = RAC_NULL;

    // Parse configJson if provided
    std::string sys_prompt_storage;
    if (config != nullptr) {
        try {
            auto j = nlohmann::json::parse(config);
            options.max_tokens = j.value("max_tokens", 512);
            options.temperature = j.value("temperature", 0.7f);
            options.top_p = j.value("top_p", 1.0f);
            sys_prompt_storage = j.value("system_prompt", std::string(""));
            if (!sys_prompt_storage.empty()) {
                options.system_prompt = sys_prompt_storage.c_str();
            }
        } catch (const nlohmann::json::exception& e) {
            LOGe("Failed to parse LLM config JSON: %s", e.what());
        }
    }

    LOGi("racLlmComponentGenerateStream options: temp=%.2f, max_tokens=%d, top_p=%.2f, system_prompt=%s",
         options.temperature, options.max_tokens, options.top_p,
         options.system_prompt ? "(set)" : "(none)");

    // Create streaming context
    LLMStreamContext ctx;

    LOGi("racLlmComponentGenerateStream calling rac_llm_component_generate_stream...");

    rac_result_t status = rac_llm_component_generate_stream(
        reinterpret_cast<rac_handle_t>(handle), promptStr.c_str(), &options,
        llm_stream_token_callback, llm_stream_complete_callback, llm_stream_error_callback, &ctx);

    if (status != RAC_SUCCESS) {
        LOGe("rac_llm_component_generate_stream failed with status=%d", status);
        const char* msg = rac_error_message(status);
        jclass exClass = env->FindClass("java/lang/RuntimeException");
        if (exClass) {
            char fallback[64];
            if (!msg || !*msg) {
                snprintf(fallback, sizeof(fallback), "LLM stream generation failed (status=%d)", status);
                msg = fallback;
            }
            env->ThrowNew(exClass, msg);
            env->DeleteLocalRef(exClass);
        }
        return nullptr;
    }

    // Wait for streaming to complete
    {
        std::unique_lock<std::mutex> lock(ctx.mtx);
        constexpr auto kStreamWaitTimeout = std::chrono::minutes(10);
        if (!ctx.cv.wait_for(lock, kStreamWaitTimeout, [&ctx] { return ctx.is_complete; })) {
            ctx.has_error = true;
            ctx.error_message = "Streaming timed out waiting for completion callback";
            ctx.is_complete = true;
        }
    }

    if (ctx.has_error) {
        LOGe("Streaming failed: %s", ctx.error_message.c_str());
        return nullptr;
    }

    LOGi("racLlmComponentGenerateStream result text length=%zu, tokens=%d",
         ctx.accumulated_text.length(), ctx.token_count);

    // Build JSON result - keys must match what Kotlin expects
    nlohmann::json json_obj;
    json_obj["text"] = ctx.accumulated_text;
    json_obj["tokens_generated"] = ctx.final_result.completion_tokens;
    json_obj["tokens_evaluated"] = ctx.final_result.prompt_tokens;
    json_obj["stop_reason"] = 0;  // 0 = normal completion
    json_obj["total_time_ms"] = ctx.final_result.total_time_ms;
    json_obj["tokens_per_second"] = ctx.final_result.tokens_per_second;
    std::string json = json_obj.dump();

    LOGi("racLlmComponentGenerateStream returning JSON: %zu bytes", json.length());

    return env->NewStringUTF(json.c_str());
}

// ========================================================================
// STREAMING WITH KOTLIN CALLBACK - Real-time token-by-token streaming
// ========================================================================

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGenerateStreamWithCallback(
    JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring configJson,
    jobject tokenCallback) {
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
    bool onTokenExpectsBytes = true;
    jmethodID onTokenMethod = env->GetMethodID(callbackClass, "onToken", "([B)Z");
    if (!onTokenMethod) {
        env->ExceptionClear();
        onTokenMethod = env->GetMethodID(callbackClass, "onToken", "(Ljava/lang/String;)Z");
        onTokenExpectsBytes = false;
    }

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
    options.system_prompt = RAC_NULL;

    // Parse configJson if provided
    std::string sys_prompt_storage;
    if (config != nullptr) {
        try {
            auto j = nlohmann::json::parse(config);
            options.max_tokens = j.value("max_tokens", 512);
            options.temperature = j.value("temperature", 0.7f);
            options.top_p = j.value("top_p", 1.0f);
            sys_prompt_storage = j.value("system_prompt", std::string(""));
            if (!sys_prompt_storage.empty()) {
                options.system_prompt = sys_prompt_storage.c_str();
            }
        } catch (const nlohmann::json::exception& e) {
            LOGe("Failed to parse LLM config JSON: %s", e.what());
        }
    }

    LOGi("racLlmComponentGenerateStreamWithCallback options: temp=%.2f, max_tokens=%d, top_p=%.2f, system_prompt=%s",
         options.temperature, options.max_tokens, options.top_p,
         options.system_prompt ? "(set)" : "(none)");

    // Create streaming callback context
    LLMStreamCallbackContext ctx;
    ctx.jvm = jvm;
    ctx.callback = globalCallback;
    ctx.onTokenMethod = onTokenMethod;
    ctx.onTokenExpectsBytes = onTokenExpectsBytes;

    LOGi("racLlmComponentGenerateStreamWithCallback calling rac_llm_component_generate_stream...");

    rac_result_t status = rac_llm_component_generate_stream(
        reinterpret_cast<rac_handle_t>(handle), promptStr.c_str(), &options,
        llm_stream_callback_token, llm_stream_callback_complete, llm_stream_callback_error, &ctx);

    if (status != RAC_SUCCESS) {
        env->DeleteGlobalRef(globalCallback);
        LOGe("rac_llm_component_generate_stream failed with status=%d", status);
        return nullptr;
    }

    // Wait until completion/error before releasing callback/context.
    {
        std::unique_lock<std::mutex> lock(ctx.mtx);
        constexpr auto kStreamWaitTimeout = std::chrono::minutes(10);
        if (!ctx.cv.wait_for(lock, kStreamWaitTimeout, [&ctx] { return ctx.is_complete; })) {
            ctx.has_error = true;
            ctx.error_message = "Streaming timed out waiting for completion callback";
            ctx.is_complete = true;
        }
    }

    // Clean up global ref after callbacks have finished.
    env->DeleteGlobalRef(globalCallback);

    if (ctx.has_error) {
        LOGe("Streaming failed: %s", ctx.error_message.c_str());
        return nullptr;
    }

    LOGi("racLlmComponentGenerateStreamWithCallback result text length=%zu, tokens=%d",
         ctx.accumulated_text.length(), ctx.token_count);

    // Build JSON result
    nlohmann::json json_obj;
    json_obj["text"] = ctx.accumulated_text;
    json_obj["tokens_generated"] = ctx.final_result.completion_tokens;
    json_obj["tokens_evaluated"] = ctx.final_result.prompt_tokens;
    json_obj["stop_reason"] = 0;
    json_obj["total_time_ms"] = ctx.final_result.total_time_ms;
    json_obj["tokens_per_second"] = ctx.final_result.tokens_per_second;
    std::string json = json_obj.dump();

    LOGi("racLlmComponentGenerateStreamWithCallback returning JSON: %zu bytes", json.length());

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_llm_component_cancel(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetContextSize(
    JNIEnv* env, jclass clazz, jlong handle) {
    // NOTE: rac_llm_component_get_context_size is not in current API, returning default
    if (handle == 0)
        return 0;
    return 4096;  // Default context size
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentTokenize(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle,
                                                                                 jstring text) {
    // NOTE: rac_llm_component_tokenize is not in current API, returning estimate
    if (handle == 0)
        return 0;
    std::string textStr = getCString(env, text);
    // Rough token estimate: ~4 chars per token
    return static_cast<jint>(textStr.length() / 4);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetState(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return 0;
    return static_cast<jint>(rac_llm_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_llm_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                               : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmSetCallbacks(
    JNIEnv* env, jclass clazz, jobject streamCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - LLM LoRA Adapter Management
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentLoadLora(
    JNIEnv* env, jclass clazz, jlong handle, jstring adapterPath, jfloat scale) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    if (adapterPath == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;

    std::string path = getCString(env, adapterPath);

    LOGi("racLlmComponentLoadLora: handle=%lld, path=%s, scale=%.2f",
         (long long)handle, path.c_str(), (float)scale);

    rac_result_t result = rac_llm_component_load_lora(
        reinterpret_cast<rac_handle_t>(handle), path.c_str(), static_cast<float>(scale));

    LOGi("racLlmComponentLoadLora result=%d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentRemoveLora(
    JNIEnv* env, jclass clazz, jlong handle, jstring adapterPath) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    if (adapterPath == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;

    std::string path = getCString(env, adapterPath);

    rac_result_t result = rac_llm_component_remove_lora(
        reinterpret_cast<rac_handle_t>(handle), path.c_str());

    LOGi("racLlmComponentRemoveLora result=%d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentClearLora(
    JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    rac_result_t result = rac_llm_component_clear_lora(reinterpret_cast<rac_handle_t>(handle));
    LOGi("racLlmComponentClearLora result=%d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentGetLoraInfo(
    JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0) {
        return nullptr;
    }

    char* json = nullptr;
    rac_result_t result = rac_llm_component_get_lora_info(
        reinterpret_cast<rac_handle_t>(handle), &json);

    if (result != RAC_SUCCESS || !json) {
        return nullptr;
    }

    jstring jresult = env->NewStringUTF(json);
    rac_free(json);
    return jresult;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCheckLoraCompat(
    JNIEnv* env, jclass clazz, jlong handle, jstring loraPath) {
    if (handle == 0) return env->NewStringUTF("Invalid handle");
    if (loraPath == nullptr) return env->NewStringUTF("Invalid path");
    std::string path = getCString(env, loraPath);
    char* error = nullptr;
    rac_result_t result = rac_llm_component_check_lora_compat(
        reinterpret_cast<rac_handle_t>(handle), path.c_str(), &error);
    if (result == RAC_SUCCESS) {
        if (error) rac_free(error);
        return nullptr;  // null = compatible
    }
    jstring jresult = nullptr;
    if (error) {
        jresult = env->NewStringUTF(error);
        rac_free(error);
    } else {
        jresult = env->NewStringUTF("Incompatible LoRA adapter");
    }
    return jresult;
}

// ========================================================================
// LORA REGISTRY JNI
// ========================================================================

// Forward declaration (defined later alongside modelInfoToJson)
static std::string loraEntryToJson(const rac_lora_entry_t* entry);

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraRegistryRegister(
    JNIEnv* env, jclass clazz, jstring id, jstring name, jstring description,
    jstring downloadUrl, jstring filename, jobjectArray compatibleModelIds,
    jlong fileSize, jfloat defaultScale) {
    LOGi("racLoraRegistryRegister called");

    if (!id) {
        LOGe("LoRA adapter id is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* id_str = env->GetStringUTFChars(id, nullptr);
    const char* name_str = name ? env->GetStringUTFChars(name, nullptr) : nullptr;
    const char* desc_str = description ? env->GetStringUTFChars(description, nullptr) : nullptr;
    const char* url_str = downloadUrl ? env->GetStringUTFChars(downloadUrl, nullptr) : nullptr;
    const char* file_str = filename ? env->GetStringUTFChars(filename, nullptr) : nullptr;

    rac_lora_entry_t entry;
    memset(&entry, 0, sizeof(entry));
    entry.id = id_str ? strdup(id_str) : nullptr;
    entry.name = name_str ? strdup(name_str) : nullptr;
    entry.description = desc_str ? strdup(desc_str) : nullptr;
    entry.download_url = url_str ? strdup(url_str) : nullptr;
    entry.filename = file_str ? strdup(file_str) : nullptr;
    entry.file_size = fileSize;
    entry.default_scale = defaultScale;

    jsize model_count = compatibleModelIds ? env->GetArrayLength(compatibleModelIds) : 0;
    if (model_count > 0) {
        entry.compatible_model_ids = static_cast<char**>(malloc(sizeof(char*) * model_count));
        entry.compatible_model_count = model_count;
        for (jsize i = 0; i < model_count; ++i) {
            jstring jModelId = static_cast<jstring>(env->GetObjectArrayElement(compatibleModelIds, i));
            const char* mid_str = jModelId ? env->GetStringUTFChars(jModelId, nullptr) : nullptr;
            entry.compatible_model_ids[i] = mid_str ? strdup(mid_str) : nullptr;
            if (mid_str) env->ReleaseStringUTFChars(jModelId, mid_str);
        }
    }

    if (id_str) env->ReleaseStringUTFChars(id, id_str);
    if (name_str) env->ReleaseStringUTFChars(name, name_str);
    if (desc_str) env->ReleaseStringUTFChars(description, desc_str);
    if (url_str) env->ReleaseStringUTFChars(downloadUrl, url_str);
    if (file_str) env->ReleaseStringUTFChars(filename, file_str);

    LOGi("Registering LoRA adapter: %s", entry.id);
    rac_result_t result = rac_register_lora(&entry);

    // Free local copy (registry made a deep copy)
    free(entry.id); free(entry.name); free(entry.description);
    free(entry.download_url); free(entry.filename);
    if (entry.compatible_model_ids) {
        for (size_t i = 0; i < entry.compatible_model_count; ++i) free(entry.compatible_model_ids[i]);
        free(entry.compatible_model_ids);
    }

    if (result != RAC_SUCCESS) LOGe("Failed to register LoRA adapter: %d", result);
    else LOGi("LoRA adapter registered successfully");
    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraRegistryGetForModel(
    JNIEnv* env, jclass clazz, jstring modelId) {
    if (!modelId) return env->NewStringUTF("[]");
    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    rac_lora_entry_t** entries = nullptr;
    size_t count = 0;
    rac_result_t result = rac_get_lora_for_model(id_str, &entries, &count);
    env->ReleaseStringUTFChars(modelId, id_str);
    if (result != RAC_SUCCESS || !entries || count == 0) return env->NewStringUTF("[]");
    std::string json = "[";
    for (size_t i = 0; i < count; i++) {
        if (i > 0) json += ",";
        json += loraEntryToJson(entries[i]);
    }
    json += "]";
    rac_lora_entry_array_free(entries, count);
    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraRegistryGetAll(
    JNIEnv* env, jclass clazz) {
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry) {
        LOGe("LoRA registry not initialized");
        return env->NewStringUTF("[]");
    }
    rac_lora_entry_t** entries = nullptr;
    size_t count = 0;
    rac_result_t result = rac_lora_registry_get_all(registry, &entries, &count);
    if (result != RAC_SUCCESS || !entries || count == 0) return env->NewStringUTF("[]");
    std::string json = "[";
    for (size_t i = 0; i < count; i++) {
        if (i > 0) json += ",";
        json += loraEntryToJson(entries[i]);
    }
    json += "]";
    rac_lora_entry_array_free(entries, count);
    return env->NewStringUTF(json.c_str());
}

// =============================================================================
// JNI FUNCTIONS - STT Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_stt_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create STT component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_stt_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    LOGi("racSttComponentLoadModel called with handle=%lld", (long long)handle);
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    LOGi("racSttComponentLoadModel path=%s, id=%s, name=%s", path.c_str(), id.c_str(),
         name.c_str());

    // Debug: List registered providers BEFORE loading
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result =
        rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);
    LOGi("Before load_model - STT providers: count=%zu, list_result=%d", provider_count,
         list_result);
    if (provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            LOGi("  Provider[%zu]: %s", i, provider_names[i] ? provider_names[i] : "NULL");
        }
    } else {
        LOGw("NO providers registered for STT!");
    }

    // Pass model_path, model_id, and model_name separately to C++ lifecycle
    rac_result_t result = rac_stt_component_load_model(
        reinterpret_cast<rac_handle_t>(handle),
        path.c_str(),                          // model_path
        id.c_str(),                            // model_id (for telemetry)
        name.empty() ? nullptr : name.c_str()  // model_name (optional, for telemetry)
    );
    LOGi("rac_stt_component_load_model returned: %d", result);

    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_stt_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribe(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    if (handle == 0 || audioData == nullptr)
        return nullptr;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    // Use default options which properly initializes sample_rate to 16000
    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;

    // Parse configJson to override sample_rate if provided
    if (configJson != nullptr) {
        const char* json_str = env->GetStringUTFChars(configJson, nullptr);
        if (json_str != nullptr) {
            try {
                auto json = nlohmann::json::parse(json_str);
                if (json.contains("sample_rate") && json["sample_rate"].is_number()) {
                    int sample_rate = json["sample_rate"].get<int>();
                    if (sample_rate > 0) {
                        options.sample_rate = sample_rate;
                        LOGd("Using sample_rate from config: %d", sample_rate);
                    }
                }
            } catch (const nlohmann::json::exception& e) {
                LOGe("Failed to parse STT config JSON: %s", e.what());
            }
            env->ReleaseStringUTFChars(configJson, json_str);
        }
    }

    LOGd("STT transcribe: %d bytes, sample_rate=%d", (int)len, options.sample_rate);

    rac_stt_result_t result = {};

    // Audio data is 16-bit PCM (ByteArray from Android AudioRecord)
    // Pass the raw bytes - the audio_format in options tells C++ how to interpret it
    rac_result_t status = rac_stt_component_transcribe(reinterpret_cast<rac_handle_t>(handle),
                                                       data,  // Pass raw bytes (void*)
                                                       static_cast<size_t>(len),  // Size in bytes
                                                       &options, &result);

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    if (status != RAC_SUCCESS) {
        LOGe("STT transcribe failed with status: %d", status);
        return nullptr;
    }

    // Build JSON result
    nlohmann::json json_obj;
    json_obj["text"] = result.text ? std::string(result.text) : "";
    json_obj["language"] = result.detected_language ? std::string(result.detected_language) : "en";
    json_obj["duration_ms"] = result.processing_time_ms;
    json_obj["completion_reason"] = 1;  // END_OF_AUDIO
    json_obj["confidence"] = result.confidence;
    std::string json_result = json_obj.dump();

    rac_stt_result_free(&result);

    LOGd("STT transcribe result: %s", json_result.c_str());
    return env->NewStringUTF(json_result.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribeFile(
    JNIEnv* env, jclass clazz, jlong handle, jstring audioPath, jstring configJson) {
    // NOTE: rac_stt_component_transcribe_file does not exist in current API
    // This is a stub - actual implementation would need to read file and call transcribe
    if (handle == 0)
        return nullptr;
    return env->NewStringUTF("{\"error\": \"transcribe_file not implemented\"}");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribeStream(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentTranscribe(
        env, clazz, handle, audioData, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    // STT component doesn't have a cancel method, just unload
    if (handle != 0) {
        rac_stt_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentGetState(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return 0;
    return static_cast<jint>(rac_stt_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_stt_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                               : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentGetLanguages(JNIEnv* env,
                                                                                     jclass clazz,
                                                                                     jlong handle) {
    // Return empty array for now
    return env->NewStringUTF("[]");
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDetectLanguage(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData) {
    // Return null for now - language detection not implemented
    return nullptr;
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttSetCallbacks(
    JNIEnv* env, jclass clazz, jobject partialCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - TTS Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_tts_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create TTS component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_tts_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    std::string voicePath = getCString(env, modelPath);
    std::string voiceId = getCString(env, modelId);
    std::string voiceName = getCString(env, modelName);
    LOGi("racTtsComponentLoadModel path=%s, id=%s, name=%s", voicePath.c_str(), voiceId.c_str(),
         voiceName.c_str());

    // TTS component uses load_voice instead of load_model
    // Pass voice_path, voice_id, and voice_name separately to C++ lifecycle
    return static_cast<jint>(rac_tts_component_load_voice(
        reinterpret_cast<rac_handle_t>(handle),
        voicePath.c_str(),                               // voice_path
        voiceId.c_str(),                                 // voice_id (for telemetry)
        voiceName.empty() ? nullptr : voiceName.c_str()  // voice_name (optional, for telemetry)
        ));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_tts_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesize(
    JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring configJson) {
    if (handle == 0)
        return nullptr;

    std::string textStr = getCString(env, text);
    rac_tts_options_t options = {};
    rac_tts_result_t result = {};

    rac_result_t status = rac_tts_component_synthesize(reinterpret_cast<rac_handle_t>(handle),
                                                       textStr.c_str(), &options, &result);

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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesizeStream(
    JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesize(
        env, clazz, handle, text, configJson);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSynthesizeToFile(
    JNIEnv* env, jclass clazz, jlong handle, jstring text, jstring outputPath, jstring configJson) {
    if (handle == 0)
        return -1;

    std::string textStr = getCString(env, text);
    std::string pathStr = getCString(env, outputPath);
    rac_tts_options_t options = {};
    rac_tts_result_t result = {};

    rac_result_t status = rac_tts_component_synthesize(reinterpret_cast<rac_handle_t>(handle),
                                                       textStr.c_str(), &options, &result);

    // TODO: Write result to file
    rac_tts_result_free(&result);

    return status == RAC_SUCCESS ? 0 : -1;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    // TTS component doesn't have a cancel method, just unload
    if (handle != 0) {
        rac_tts_component_unload(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetState(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return 0;
    return static_cast<jint>(rac_tts_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_tts_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                               : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetVoices(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle) {
    return env->NewStringUTF("[]");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentSetVoice(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle,
                                                                                 jstring voiceId) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    std::string voice = getCString(env, voiceId);
    // voice_path, voice_id (use path as id), voice_name (optional)
    return static_cast<jint>(rac_tts_component_load_voice(reinterpret_cast<rac_handle_t>(handle),
                                                          voice.c_str(),  // voice_path
                                                          voice.c_str(),  // voice_id
                                                          nullptr         // voice_name (optional)
                                                          ));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentGetLanguages(JNIEnv* env,
                                                                                     jclass clazz,
                                                                                     jlong handle) {
    return env->NewStringUTF("[]");
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsSetCallbacks(
    JNIEnv* env, jclass clazz, jobject audioCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - VAD Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_vad_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create VAD component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_vad_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring configJson) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    // Initialize and configure the VAD component
    return static_cast<jint>(rac_vad_component_initialize(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_vad_component_cleanup(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    if (handle == 0 || audioData == nullptr)
        return nullptr;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    rac_bool_t out_is_speech = RAC_FALSE;
    rac_result_t status = rac_vad_component_process(
        reinterpret_cast<rac_handle_t>(handle), reinterpret_cast<const float*>(data),
        static_cast<size_t>(len / sizeof(float)), &out_is_speech);

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    if (status != RAC_SUCCESS) {
        return nullptr;
    }

    // Return JSON result
    char jsonBuf[256];
    snprintf(jsonBuf, sizeof(jsonBuf), "{\"is_speech\":%s,\"probability\":%.4f}",
             out_is_speech ? "true" : "false", out_is_speech ? 1.0f : 0.0f);

    return env->NewStringUTF(jsonBuf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcessStream(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(
        env, clazz, handle, audioData, configJson);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcessFrame(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jstring configJson) {
    return Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcess(
        env, clazz, handle, audioData, configJson);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_vad_component_stop(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentReset(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    if (handle != 0) {
        rac_vad_component_reset(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetState(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return 0;
    return static_cast<jint>(rac_vad_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_vad_component_is_initialized(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                                    : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetMinFrameSize(
    JNIEnv* env, jclass clazz, jlong handle) {
    // Default minimum frame size: 512 samples at 16kHz = 32ms
    if (handle == 0)
        return 0;
    return 512;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetSampleRates(
    JNIEnv* env, jclass clazz, jlong handle) {
    return env->NewStringUTF("[16000]");
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadSetCallbacks(
    JNIEnv* env, jclass clazz, jobject frameCallback, jobject speechStartCallback,
    jobject speechEndCallback, jobject progressCallback) {
    // TODO: Implement callback registration
}

// =============================================================================
// JNI FUNCTIONS - Model Registry (mirrors Swift CppBridge+ModelRegistry.swift)
// =============================================================================

// Helper to convert Java ModelInfo to C struct
static rac_model_info_t* javaModelInfoToC(JNIEnv* env, jobject modelInfo) {
    if (!modelInfo)
        return nullptr;

    jclass cls = env->GetObjectClass(modelInfo);
    if (!cls)
        return nullptr;

    rac_model_info_t* model = rac_model_info_alloc();
    if (!model)
        return nullptr;

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
    model->framework =
        static_cast<rac_inference_framework_t>(env->GetIntField(modelInfo, frameworkField));

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
    model->supports_thinking =
        env->GetBooleanField(modelInfo, supportsThinkingField) ? RAC_TRUE : RAC_FALSE;

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
    if (!model)
        return "null";

    nlohmann::json j;
    j["model_id"] = model->id ? model->id : "";
    j["name"] = model->name ? model->name : "";
    j["category"] = static_cast<int>(model->category);
    j["format"] = static_cast<int>(model->format);
    j["framework"] = static_cast<int>(model->framework);
    j["download_url"] = model->download_url ? nlohmann::json(model->download_url) : nlohmann::json(nullptr);
    j["local_path"] = model->local_path ? nlohmann::json(model->local_path) : nlohmann::json(nullptr);
    j["download_size"] = model->download_size;
    j["context_length"] = model->context_length;
    j["supports_thinking"] = static_cast<bool>(model->supports_thinking);
    j["supports_lora"] = static_cast<bool>(model->supports_lora);
    j["description"] = model->description ? nlohmann::json(model->description) : nlohmann::json(nullptr);
    return j.dump();
}

static std::string loraEntryToJson(const rac_lora_entry_t* entry) {
    if (!entry) return "null";
    nlohmann::json j;
    j["id"] = entry->id ? entry->id : "";
    j["name"] = entry->name ? entry->name : "";
    j["description"] = entry->description ? entry->description : "";
    j["download_url"] = entry->download_url ? entry->download_url : "";
    j["filename"] = entry->filename ? entry->filename : "";
    j["file_size"] = entry->file_size;
    j["default_scale"] = entry->default_scale;
    nlohmann::json ids = nlohmann::json::array();
    for (size_t i = 0; i < entry->compatible_model_count; ++i) {
        if (entry->compatible_model_ids[i])
            ids.push_back(entry->compatible_model_ids[i]);
    }
    j["compatible_model_ids"] = ids;
    return j.dump();
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistrySave(
    JNIEnv* env, jclass clazz, jstring modelId, jstring name, jint category, jint format,
    jint framework, jstring downloadUrl, jstring localPath, jlong downloadSize, jint contextLength,
    jboolean supportsThinking, jboolean supportsLora, jstring description) {
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
    model->supports_lora = supportsLora ? RAC_TRUE : RAC_FALSE;
    model->description = desc_str ? strdup(desc_str) : nullptr;

    // Release Java strings
    if (id_str)
        env->ReleaseStringUTFChars(modelId, id_str);
    if (name_str)
        env->ReleaseStringUTFChars(name, name_str);
    if (url_str)
        env->ReleaseStringUTFChars(downloadUrl, url_str);
    if (path_str)
        env->ReleaseStringUTFChars(localPath, path_str);
    if (desc_str)
        env->ReleaseStringUTFChars(description, desc_str);

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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGet(JNIEnv* env,
                                                                             jclass clazz,
                                                                             jstring modelId) {
    if (!modelId)
        return nullptr;

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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGetAll(JNIEnv* env,
                                                                                jclass clazz) {
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
        if (i > 0)
            json += ",";
        json += modelInfoToJson(models[i]);
    }
    json += "]";

    rac_model_info_array_free(models, count);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGetDownloaded(
    JNIEnv* env, jclass clazz) {
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
        if (i > 0)
            json += ",";
        json += modelInfoToJson(models[i]);
    }
    json += "]";

    rac_model_info_array_free(models, count);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryRemove(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jstring modelId) {
    if (!modelId)
        return RAC_ERROR_NULL_POINTER;

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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryUpdateDownloadStatus(
    JNIEnv* env, jclass clazz, jstring modelId, jstring localPath) {
    if (!modelId)
        return RAC_ERROR_NULL_POINTER;

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    const char* path_str = localPath ? env->GetStringUTFChars(localPath, nullptr) : nullptr;

    LOGi("Updating download status: %s -> %s", id_str, path_str ? path_str : "null");

    rac_result_t result = rac_model_registry_update_download_status(registry, id_str, path_str);

    env->ReleaseStringUTFChars(modelId, id_str);
    if (path_str)
        env->ReleaseStringUTFChars(localPath, path_str);

    return static_cast<jint>(result);
}

// =============================================================================
// JNI FUNCTIONS - Model Assignment (rac_model_assignment.h)
// =============================================================================
// Mirrors Swift SDK's CppBridge+ModelAssignment.swift

// Global state for model assignment callbacks
// NOTE: Using recursive_mutex to allow callback re-entry during auto_fetch
// The flow is: setCallbacks() -> rac_model_assignment_set_callbacks() -> fetch() -> http_get_callback()
// All on the same thread, so a recursive mutex is required
static struct {
    JavaVM* jvm;
    jobject callback_obj;
    jmethodID http_get_method;
    std::recursive_mutex mutex;  // Must be recursive to allow callback during auto_fetch
    bool callbacks_registered;
} g_model_assignment_state = {nullptr, nullptr, nullptr, {}, false};

// HTTP GET callback for model assignment (called from C++)
static rac_result_t model_assignment_http_get_callback(const char* endpoint,
                                                        rac_bool_t requires_auth,
                                                        rac_assignment_http_response_t* out_response,
                                                        void* user_data) {
    std::lock_guard<std::recursive_mutex> lock(g_model_assignment_state.mutex);

    if (!g_model_assignment_state.jvm || !g_model_assignment_state.callback_obj) {
        LOGe("model_assignment_http_get_callback: callbacks not registered");
        if (out_response) {
            out_response->result = RAC_ERROR_INVALID_STATE;
        }
        return RAC_ERROR_INVALID_STATE;
    }

    JNIEnv* env = nullptr;
    bool did_attach = false;
    jint get_result = g_model_assignment_state.jvm->GetEnv((void**)&env, JNI_VERSION_1_6);

    if (get_result == JNI_EDETACHED) {
        if (g_model_assignment_state.jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            did_attach = true;
        } else {
            LOGe("model_assignment_http_get_callback: failed to attach thread");
            if (out_response) {
                out_response->result = RAC_ERROR_INVALID_STATE;
            }
            return RAC_ERROR_INVALID_STATE;
        }
    }

    // Call Kotlin callback: httpGet(endpoint: String, requiresAuth: Boolean): String
    jstring jEndpoint = env->NewStringUTF(endpoint ? endpoint : "");
    jboolean jRequiresAuth = requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE;

    jstring jResponse =
        (jstring)env->CallObjectMethod(g_model_assignment_state.callback_obj,
                                       g_model_assignment_state.http_get_method, jEndpoint, jRequiresAuth);

    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        LOGe("model_assignment_http_get_callback: exception in Kotlin callback");
        env->DeleteLocalRef(jEndpoint);
        if (did_attach) {
            g_model_assignment_state.jvm->DetachCurrentThread();
        }
        if (out_response) {
            out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
        }
        return RAC_ERROR_HTTP_REQUEST_FAILED;
    }

    rac_result_t result = RAC_SUCCESS;
    if (jResponse) {
        const char* response_str = env->GetStringUTFChars(jResponse, nullptr);
        if (response_str && out_response) {
            // Check if response is an error (starts with "ERROR:")
            if (strncmp(response_str, "ERROR:", 6) == 0) {
                out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                out_response->error_message = strdup(response_str + 6);
                result = RAC_ERROR_HTTP_REQUEST_FAILED;
            } else {
                out_response->result = RAC_SUCCESS;
                out_response->status_code = 200;
                out_response->response_body = strdup(response_str);
                out_response->response_length = strlen(response_str);
            }
        }
        env->ReleaseStringUTFChars(jResponse, response_str);
        env->DeleteLocalRef(jResponse);
    } else {
        if (out_response) {
            out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
        }
        result = RAC_ERROR_HTTP_REQUEST_FAILED;
    }

    env->DeleteLocalRef(jEndpoint);
    if (did_attach) {
        g_model_assignment_state.jvm->DetachCurrentThread();
    }

    return result;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentSetCallbacks(
    JNIEnv* env, jclass clazz, jobject callback, jboolean autoFetch) {
    LOGi("racModelAssignmentSetCallbacks called, autoFetch=%d", autoFetch);

    std::lock_guard<std::recursive_mutex> lock(g_model_assignment_state.mutex);

    // Clear previous callback if any
    if (g_model_assignment_state.callback_obj) {
        JNIEnv* env_local = nullptr;
        if (g_model_assignment_state.jvm &&
            g_model_assignment_state.jvm->GetEnv((void**)&env_local, JNI_VERSION_1_6) == JNI_OK) {
            env_local->DeleteGlobalRef(g_model_assignment_state.callback_obj);
        }
        g_model_assignment_state.callback_obj = nullptr;
    }

    if (!callback) {
        // Just clearing callbacks
        g_model_assignment_state.callbacks_registered = false;
        LOGi("racModelAssignmentSetCallbacks: callbacks cleared");
        return RAC_SUCCESS;
    }

    // Store JVM reference
    env->GetJavaVM(&g_model_assignment_state.jvm);

    // Create global reference to callback object
    g_model_assignment_state.callback_obj = env->NewGlobalRef(callback);

    // Get method IDs
    jclass callback_class = env->GetObjectClass(callback);
    g_model_assignment_state.http_get_method =
        env->GetMethodID(callback_class, "httpGet", "(Ljava/lang/String;Z)Ljava/lang/String;");
    env->DeleteLocalRef(callback_class);

    if (!g_model_assignment_state.http_get_method) {
        LOGe("racModelAssignmentSetCallbacks: failed to get httpGet method ID");
        env->DeleteGlobalRef(g_model_assignment_state.callback_obj);
        g_model_assignment_state.callback_obj = nullptr;
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Set up C++ callbacks
    rac_assignment_callbacks_t callbacks = {};
    callbacks.http_get = model_assignment_http_get_callback;
    callbacks.user_data = nullptr;
    callbacks.auto_fetch = autoFetch ? RAC_TRUE : RAC_FALSE;

    rac_result_t result = rac_model_assignment_set_callbacks(&callbacks);

    if (result == RAC_SUCCESS) {
        g_model_assignment_state.callbacks_registered = true;
        LOGi("racModelAssignmentSetCallbacks: registered successfully");
    } else {
        LOGe("racModelAssignmentSetCallbacks: failed with code %d", result);
        env->DeleteGlobalRef(g_model_assignment_state.callback_obj);
        g_model_assignment_state.callback_obj = nullptr;
    }

    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentFetch(
    JNIEnv* env, jclass clazz, jboolean forceRefresh) {
    LOGi("racModelAssignmentFetch called, forceRefresh=%d", forceRefresh);

    rac_model_info_t** models = nullptr;
    size_t count = 0;

    rac_result_t result =
        rac_model_assignment_fetch(forceRefresh ? RAC_TRUE : RAC_FALSE, &models, &count);

    if (result != RAC_SUCCESS) {
        LOGe("racModelAssignmentFetch: failed with code %d", result);
        return env->NewStringUTF("[]");
    }

    // Build JSON array of models
    nlohmann::json json_array = nlohmann::json::array();
    for (size_t i = 0; i < count; i++) {
        rac_model_info_t* m = models[i];
        nlohmann::json obj;
        obj["id"] = m->id ? m->id : "";
        obj["name"] = m->name ? m->name : "";
        obj["category"] = static_cast<int>(m->category);
        obj["format"] = static_cast<int>(m->format);
        obj["framework"] = static_cast<int>(m->framework);
        obj["downloadUrl"] = m->download_url ? m->download_url : "";
        obj["downloadSize"] = m->download_size;
        obj["contextLength"] = m->context_length;
        obj["supportsThinking"] = static_cast<bool>(m->supports_thinking == RAC_TRUE);
        json_array.push_back(obj);
    }
    std::string json = json_array.dump();

    // Free models array
    if (models) {
        rac_model_info_array_free(models, count);
    }

    LOGi("racModelAssignmentFetch: returned %zu models", count);
    return env->NewStringUTF(json.c_str());
}

// =============================================================================
// JNI FUNCTIONS - Audio Utils (rac_audio_utils.h)
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioFloat32ToWav(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jbyteArray pcmData,
                                                                              jint sampleRate) {
    if (pcmData == nullptr) {
        LOGe("racAudioFloat32ToWav: null input data");
        return nullptr;
    }

    jsize pcmSize = env->GetArrayLength(pcmData);
    if (pcmSize == 0) {
        LOGe("racAudioFloat32ToWav: empty input data");
        return nullptr;
    }

    LOGi("racAudioFloat32ToWav: converting %d bytes at %d Hz", (int)pcmSize, sampleRate);

    // Get the input data
    jbyte* pcmBytes = env->GetByteArrayElements(pcmData, nullptr);
    if (pcmBytes == nullptr) {
        LOGe("racAudioFloat32ToWav: failed to get byte array elements");
        return nullptr;
    }

    // Convert Float32 PCM to WAV format
    void* wavData = nullptr;
    size_t wavSize = 0;

    rac_result_t result = rac_audio_float32_to_wav(pcmBytes, static_cast<size_t>(pcmSize),
                                                   sampleRate, &wavData, &wavSize);

    env->ReleaseByteArrayElements(pcmData, pcmBytes, JNI_ABORT);

    if (result != RAC_SUCCESS || wavData == nullptr) {
        LOGe("racAudioFloat32ToWav: conversion failed with code %d", result);
        return nullptr;
    }

    LOGi("racAudioFloat32ToWav: conversion successful, output %zu bytes", wavSize);

    // Create Java byte array for output
    jbyteArray jWavData = env->NewByteArray(static_cast<jsize>(wavSize));
    if (jWavData == nullptr) {
        LOGe("racAudioFloat32ToWav: failed to create output byte array");
        rac_free(wavData);
        return nullptr;
    }

    env->SetByteArrayRegion(jWavData, 0, static_cast<jsize>(wavSize),
                            reinterpret_cast<const jbyte*>(wavData));

    // Free the C-allocated memory
    rac_free(wavData);

    return jWavData;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioInt16ToWav(JNIEnv* env,
                                                                            jclass clazz,
                                                                            jbyteArray pcmData,
                                                                            jint sampleRate) {
    if (pcmData == nullptr) {
        LOGe("racAudioInt16ToWav: null input data");
        return nullptr;
    }

    jsize pcmSize = env->GetArrayLength(pcmData);
    if (pcmSize == 0) {
        LOGe("racAudioInt16ToWav: empty input data");
        return nullptr;
    }

    LOGi("racAudioInt16ToWav: converting %d bytes at %d Hz", (int)pcmSize, sampleRate);

    // Get the input data
    jbyte* pcmBytes = env->GetByteArrayElements(pcmData, nullptr);
    if (pcmBytes == nullptr) {
        LOGe("racAudioInt16ToWav: failed to get byte array elements");
        return nullptr;
    }

    // Convert Int16 PCM to WAV format
    void* wavData = nullptr;
    size_t wavSize = 0;

    rac_result_t result = rac_audio_int16_to_wav(pcmBytes, static_cast<size_t>(pcmSize), sampleRate,
                                                 &wavData, &wavSize);

    env->ReleaseByteArrayElements(pcmData, pcmBytes, JNI_ABORT);

    if (result != RAC_SUCCESS || wavData == nullptr) {
        LOGe("racAudioInt16ToWav: conversion failed with code %d", result);
        return nullptr;
    }

    LOGi("racAudioInt16ToWav: conversion successful, output %zu bytes", wavSize);

    // Create Java byte array for output
    jbyteArray jWavData = env->NewByteArray(static_cast<jsize>(wavSize));
    if (jWavData == nullptr) {
        LOGe("racAudioInt16ToWav: failed to create output byte array");
        rac_free(wavData);
        return nullptr;
    }

    env->SetByteArrayRegion(jWavData, 0, static_cast<jsize>(wavSize),
                            reinterpret_cast<const jbyte*>(wavData));

    // Free the C-allocated memory
    rac_free(wavData);

    return jWavData;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioWavHeaderSize(JNIEnv* env,
                                                                               jclass clazz) {
    return static_cast<jint>(rac_audio_wav_header_size());
}

// =============================================================================
// JNI FUNCTIONS - Device Manager (rac_device_manager.h)
// =============================================================================
// Mirrors Swift SDK's CppBridge+Device.swift

// Global state for device callbacks
static struct {
    jobject callback_obj;
    jmethodID get_device_info_method;
    jmethodID get_device_id_method;
    jmethodID is_registered_method;
    jmethodID set_registered_method;
    jmethodID http_post_method;
    std::mutex mtx;
} g_device_jni_state = {};

// Forward declarations for device C callbacks
static void jni_device_get_info(rac_device_registration_info_t* out_info, void* user_data);
static const char* jni_device_get_id(void* user_data);
static rac_bool_t jni_device_is_registered(void* user_data);
static void jni_device_set_registered(rac_bool_t registered, void* user_data);
static rac_result_t jni_device_http_post(const char* endpoint, const char* json_body,
                                         rac_bool_t requires_auth,
                                         rac_device_http_response_t* out_response, void* user_data);

// Static storage for device ID string (needs to persist across calls)
// Protected by g_device_jni_state.mtx for thread safety
static std::string g_cached_device_id;

// Static storage for device info strings (need to persist for C callbacks)
static struct {
    std::string device_id;
    std::string device_model;
    std::string device_name;
    std::string platform;
    std::string os_version;
    std::string form_factor;
    std::string architecture;
    std::string chip_name;
    std::string gpu_family;
    std::string battery_state;
    std::string device_fingerprint;
    std::string manufacturer;
    std::mutex mtx;
} g_device_info_strings = {};

// Device callback implementations
static void jni_device_get_info(rac_device_registration_info_t* out_info, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.get_device_info_method) {
        LOGe("jni_device_get_info: JNI not ready");
        return;
    }

    // Call Java getDeviceInfo() which returns a JSON string
    jstring jResult = (jstring)env->CallObjectMethod(g_device_jni_state.callback_obj,
                                                     g_device_jni_state.get_device_info_method);

    // Check for Java exception after CallObjectMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_get_info: Java exception occurred in getDeviceInfo()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return;
    }

    if (jResult && out_info) {
        const char* json_str = env->GetStringUTFChars(jResult, nullptr);
        LOGd("jni_device_get_info: parsing JSON: %.200s...", json_str);

        // Parse JSON and extract all fields
        std::lock_guard<std::mutex> lock(g_device_info_strings.mtx);

        try {
            auto j = nlohmann::json::parse(json_str);

            // Extract all string fields from Kotlin's getDeviceInfoCallback() JSON
            g_device_info_strings.device_id = j.value("device_id", std::string(""));
            g_device_info_strings.device_model = j.value("device_model", std::string(""));
            g_device_info_strings.device_name = j.value("device_name", std::string(""));
            g_device_info_strings.platform = j.value("platform", std::string(""));
            g_device_info_strings.os_version = j.value("os_version", std::string(""));
            g_device_info_strings.form_factor = j.value("form_factor", std::string(""));
            g_device_info_strings.architecture = j.value("architecture", std::string(""));
            g_device_info_strings.chip_name = j.value("chip_name", std::string(""));
            g_device_info_strings.gpu_family = j.value("gpu_family", std::string(""));
            g_device_info_strings.battery_state = j.value("battery_state", std::string(""));
            g_device_info_strings.device_fingerprint = j.value("device_fingerprint", std::string(""));
            g_device_info_strings.manufacturer = j.value("manufacturer", std::string(""));

            // Extract integer fields
            out_info->total_memory = j.value("total_memory", (int64_t)0);
            out_info->available_memory = j.value("available_memory", (int64_t)0);
            out_info->neural_engine_cores = j.value("neural_engine_cores", (int32_t)0);
            out_info->core_count = j.value("core_count", (int32_t)0);
            out_info->performance_cores = j.value("performance_cores", (int32_t)0);
            out_info->efficiency_cores = j.value("efficiency_cores", (int32_t)0);

            // Extract boolean fields
            out_info->has_neural_engine = j.value("has_neural_engine", false) ? RAC_TRUE : RAC_FALSE;
            out_info->is_low_power_mode = j.value("is_low_power_mode", false) ? RAC_TRUE : RAC_FALSE;

            // Extract float field for battery
            out_info->battery_level = j.value("battery_level", 0.0f);
        } catch (const nlohmann::json::exception& e) {
            LOGe("Failed to parse device info JSON: %s", e.what());
        }

        // Assign pointers to out_info (C struct uses const char*)
        out_info->device_id = g_device_info_strings.device_id.empty()
                                  ? nullptr
                                  : g_device_info_strings.device_id.c_str();
        out_info->device_model = g_device_info_strings.device_model.empty()
                                     ? nullptr
                                     : g_device_info_strings.device_model.c_str();
        out_info->device_name = g_device_info_strings.device_name.empty()
                                    ? nullptr
                                    : g_device_info_strings.device_name.c_str();
        out_info->platform = g_device_info_strings.platform.empty()
                                 ? "android"
                                 : g_device_info_strings.platform.c_str();
        out_info->os_version = g_device_info_strings.os_version.empty()
                                   ? nullptr
                                   : g_device_info_strings.os_version.c_str();
        out_info->form_factor = g_device_info_strings.form_factor.empty()
                                    ? nullptr
                                    : g_device_info_strings.form_factor.c_str();
        out_info->architecture = g_device_info_strings.architecture.empty()
                                     ? nullptr
                                     : g_device_info_strings.architecture.c_str();
        out_info->chip_name = g_device_info_strings.chip_name.empty()
                                  ? nullptr
                                  : g_device_info_strings.chip_name.c_str();
        out_info->gpu_family = g_device_info_strings.gpu_family.empty()
                                   ? nullptr
                                   : g_device_info_strings.gpu_family.c_str();
        out_info->battery_state = g_device_info_strings.battery_state.empty()
                                      ? nullptr
                                      : g_device_info_strings.battery_state.c_str();
        out_info->device_fingerprint = g_device_info_strings.device_fingerprint.empty()
                                           ? nullptr
                                           : g_device_info_strings.device_fingerprint.c_str();

        LOGi("jni_device_get_info: parsed device_model=%s, os_version=%s, architecture=%s",
             out_info->device_model ? out_info->device_model : "(null)",
             out_info->os_version ? out_info->os_version : "(null)",
             out_info->architecture ? out_info->architecture : "(null)");

        env->ReleaseStringUTFChars(jResult, json_str);
        env->DeleteLocalRef(jResult);
    }
}

static const char* jni_device_get_id(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.get_device_id_method) {
        LOGe("jni_device_get_id: JNI not ready");
        return "";
    }

    jstring jResult = (jstring)env->CallObjectMethod(g_device_jni_state.callback_obj,
                                                     g_device_jni_state.get_device_id_method);

    // Check for Java exception after CallObjectMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_get_id: Java exception occurred in getDeviceId()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return "";
    }

    if (jResult) {
        const char* str = env->GetStringUTFChars(jResult, nullptr);

        // Lock mutex to protect g_cached_device_id from concurrent access
        std::lock_guard<std::mutex> lock(g_device_jni_state.mtx);
        g_cached_device_id = str;
        env->ReleaseStringUTFChars(jResult, str);
        env->DeleteLocalRef(jResult);
        return g_cached_device_id.c_str();
    }
    return "";
}

static rac_bool_t jni_device_is_registered(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.is_registered_method) {
        return RAC_FALSE;
    }

    jboolean result = env->CallBooleanMethod(g_device_jni_state.callback_obj,
                                             g_device_jni_state.is_registered_method);

    // Check for Java exception after CallBooleanMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_is_registered: Java exception occurred in isRegistered()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return RAC_FALSE;
    }

    return result ? RAC_TRUE : RAC_FALSE;
}

static void jni_device_set_registered(rac_bool_t registered, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.set_registered_method) {
        return;
    }

    env->CallVoidMethod(g_device_jni_state.callback_obj, g_device_jni_state.set_registered_method,
                        registered == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallVoidMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_set_registered: Java exception occurred in setRegistered()");
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}

static rac_result_t jni_device_http_post(const char* endpoint, const char* json_body,
                                         rac_bool_t requires_auth,
                                         rac_device_http_response_t* out_response,
                                         void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.http_post_method) {
        LOGe("jni_device_http_post: JNI not ready");
        if (out_response) {
            out_response->result = RAC_ERROR_ADAPTER_NOT_SET;
            out_response->status_code = -1;
        }
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jEndpoint = env->NewStringUTF(endpoint ? endpoint : "");
    jstring jBody = env->NewStringUTF(json_body ? json_body : "");

    // Check for allocation failures (can throw OutOfMemoryError)
    if (env->ExceptionCheck() || !jEndpoint || !jBody) {
        LOGe("jni_device_http_post: Failed to create JNI strings");
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        if (jEndpoint)
            env->DeleteLocalRef(jEndpoint);
        if (jBody)
            env->DeleteLocalRef(jBody);
        if (out_response) {
            out_response->result = RAC_ERROR_OUT_OF_MEMORY;
            out_response->status_code = -1;
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    jint statusCode =
        env->CallIntMethod(g_device_jni_state.callback_obj, g_device_jni_state.http_post_method,
                           jEndpoint, jBody, requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallIntMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_http_post: Java exception occurred in httpPost()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        env->DeleteLocalRef(jEndpoint);
        env->DeleteLocalRef(jBody);
        if (out_response) {
            out_response->result = RAC_ERROR_NETWORK_ERROR;
            out_response->status_code = -1;
        }
        return RAC_ERROR_NETWORK_ERROR;
    }

    env->DeleteLocalRef(jEndpoint);
    env->DeleteLocalRef(jBody);

    if (out_response) {
        out_response->status_code = statusCode;
        out_response->result =
            (statusCode >= 200 && statusCode < 300) ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
    }

    return (statusCode >= 200 && statusCode < 300) ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerSetCallbacks(
    JNIEnv* env, jclass clazz, jobject callbacks) {
    LOGi("racDeviceManagerSetCallbacks called");

    std::lock_guard<std::mutex> lock(g_device_jni_state.mtx);

    // Clean up previous callback
    if (g_device_jni_state.callback_obj != nullptr) {
        env->DeleteGlobalRef(g_device_jni_state.callback_obj);
        g_device_jni_state.callback_obj = nullptr;
    }

    if (callbacks == nullptr) {
        LOGw("racDeviceManagerSetCallbacks: null callbacks");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Create global reference
    g_device_jni_state.callback_obj = env->NewGlobalRef(callbacks);

    // Cache method IDs
    jclass cls = env->GetObjectClass(callbacks);
    g_device_jni_state.get_device_info_method =
        env->GetMethodID(cls, "getDeviceInfo", "()Ljava/lang/String;");
    g_device_jni_state.get_device_id_method =
        env->GetMethodID(cls, "getDeviceId", "()Ljava/lang/String;");
    g_device_jni_state.is_registered_method = env->GetMethodID(cls, "isRegistered", "()Z");
    g_device_jni_state.set_registered_method = env->GetMethodID(cls, "setRegistered", "(Z)V");
    g_device_jni_state.http_post_method =
        env->GetMethodID(cls, "httpPost", "(Ljava/lang/String;Ljava/lang/String;Z)I");
    env->DeleteLocalRef(cls);

    // Verify methods found
    if (!g_device_jni_state.get_device_id_method || !g_device_jni_state.is_registered_method) {
        LOGe("racDeviceManagerSetCallbacks: required methods not found");
        env->DeleteGlobalRef(g_device_jni_state.callback_obj);
        g_device_jni_state.callback_obj = nullptr;
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Set up C callbacks
    rac_device_callbacks_t c_callbacks = {};
    c_callbacks.get_device_info = jni_device_get_info;
    c_callbacks.get_device_id = jni_device_get_id;
    c_callbacks.is_registered = jni_device_is_registered;
    c_callbacks.set_registered = jni_device_set_registered;
    c_callbacks.http_post = jni_device_http_post;
    c_callbacks.user_data = nullptr;

    rac_result_t result = rac_device_manager_set_callbacks(&c_callbacks);

    LOGi("racDeviceManagerSetCallbacks result: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerRegisterIfNeeded(
    JNIEnv* env, jclass clazz, jint environment, jstring buildToken) {
    LOGi("racDeviceManagerRegisterIfNeeded called (env=%d)", environment);

    std::string tokenStorage;
    const char* token = getNullableCString(env, buildToken, tokenStorage);

    rac_result_t result =
        rac_device_manager_register_if_needed(static_cast<rac_environment_t>(environment), token);

    LOGi("racDeviceManagerRegisterIfNeeded result: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerIsRegistered(
    JNIEnv* env, jclass clazz) {
    return rac_device_manager_is_registered() == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerClearRegistration(
    JNIEnv* env, jclass clazz) {
    LOGi("racDeviceManagerClearRegistration called");
    rac_device_manager_clear_registration();
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerGetDeviceId(JNIEnv* env,
                                                                                     jclass clazz) {
    const char* deviceId = rac_device_manager_get_device_id();
    if (deviceId) {
        return env->NewStringUTF(deviceId);
    }
    return nullptr;
}

// =============================================================================
// JNI FUNCTIONS - Telemetry Manager (rac_telemetry_manager.h)
// =============================================================================
// Mirrors Swift SDK's CppBridge+Telemetry.swift

// Global state for telemetry
static struct {
    rac_telemetry_manager_t* manager;
    jobject http_callback_obj;
    jmethodID http_callback_method;
    std::mutex mtx;
} g_telemetry_jni_state = {};

// Telemetry HTTP callback from C++ to Java
static void jni_telemetry_http_callback(void* user_data, const char* endpoint,
                                        const char* json_body, size_t json_length,
                                        rac_bool_t requires_auth) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_telemetry_jni_state.http_callback_obj ||
        !g_telemetry_jni_state.http_callback_method) {
        LOGw("jni_telemetry_http_callback: JNI not ready");
        return;
    }

    jstring jEndpoint = env->NewStringUTF(endpoint ? endpoint : "");
    jstring jBody = env->NewStringUTF(json_body ? json_body : "");

    // Check for NewStringUTF allocation failures
    if (!jEndpoint || !jBody) {
        LOGe("jni_telemetry_http_callback: failed to allocate JNI strings");
        if (jEndpoint)
            env->DeleteLocalRef(jEndpoint);
        if (jBody)
            env->DeleteLocalRef(jBody);
        return;
    }

    env->CallVoidMethod(g_telemetry_jni_state.http_callback_obj,
                        g_telemetry_jni_state.http_callback_method, jEndpoint, jBody,
                        static_cast<jint>(json_length),
                        requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallVoidMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_telemetry_http_callback: Java exception occurred in HTTP callback");
        env->ExceptionDescribe();
        env->ExceptionClear();
    }

    // Always clean up local references
    env->DeleteLocalRef(jEndpoint);
    env->DeleteLocalRef(jBody);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerCreate(
    JNIEnv* env, jclass clazz, jint environment, jstring deviceId, jstring platform,
    jstring sdkVersion) {
    LOGi("racTelemetryManagerCreate called (env=%d)", environment);

    std::string deviceIdStr = getCString(env, deviceId);
    std::string platformStr = getCString(env, platform);
    std::string versionStr = getCString(env, sdkVersion);

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    // Destroy existing manager if any
    if (g_telemetry_jni_state.manager) {
        rac_telemetry_manager_destroy(g_telemetry_jni_state.manager);
    }

    g_telemetry_jni_state.manager =
        rac_telemetry_manager_create(static_cast<rac_environment_t>(environment),
                                     deviceIdStr.c_str(), platformStr.c_str(), versionStr.c_str());

    LOGi("racTelemetryManagerCreate: manager=%p", (void*)g_telemetry_jni_state.manager);
    return reinterpret_cast<jlong>(g_telemetry_jni_state.manager);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerDestroy(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jlong handle) {
    LOGi("racTelemetryManagerDestroy called");

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    if (handle != 0 &&
        reinterpret_cast<rac_telemetry_manager_t*>(handle) == g_telemetry_jni_state.manager) {
        // Flush before destroying
        rac_telemetry_manager_flush(g_telemetry_jni_state.manager);
        rac_telemetry_manager_destroy(g_telemetry_jni_state.manager);
        g_telemetry_jni_state.manager = nullptr;

        // Clean up callback
        if (g_telemetry_jni_state.http_callback_obj) {
            env->DeleteGlobalRef(g_telemetry_jni_state.http_callback_obj);
            g_telemetry_jni_state.http_callback_obj = nullptr;
        }
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerSetDeviceInfo(
    JNIEnv* env, jclass clazz, jlong handle, jstring deviceModel, jstring osVersion) {
    if (handle == 0)
        return;

    std::string modelStr = getCString(env, deviceModel);
    std::string osStr = getCString(env, osVersion);

    rac_telemetry_manager_set_device_info(reinterpret_cast<rac_telemetry_manager_t*>(handle),
                                          modelStr.c_str(), osStr.c_str());

    LOGi("racTelemetryManagerSetDeviceInfo: model=%s, os=%s", modelStr.c_str(), osStr.c_str());
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerSetHttpCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject callback) {
    LOGi("racTelemetryManagerSetHttpCallback called");

    if (handle == 0)
        return;

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    // Clean up previous callback
    if (g_telemetry_jni_state.http_callback_obj) {
        env->DeleteGlobalRef(g_telemetry_jni_state.http_callback_obj);
        g_telemetry_jni_state.http_callback_obj = nullptr;
    }

    if (callback) {
        g_telemetry_jni_state.http_callback_obj = env->NewGlobalRef(callback);

        // Cache method ID
        jclass cls = env->GetObjectClass(callback);
        g_telemetry_jni_state.http_callback_method =
            env->GetMethodID(cls, "onHttpRequest", "(Ljava/lang/String;Ljava/lang/String;IZ)V");
        env->DeleteLocalRef(cls);

        // Register C callback with telemetry manager
        rac_telemetry_manager_set_http_callback(reinterpret_cast<rac_telemetry_manager_t*>(handle),
                                                jni_telemetry_http_callback, nullptr);
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerFlush(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle) {
    LOGi("racTelemetryManagerFlush called");

    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    return static_cast<jint>(
        rac_telemetry_manager_flush(reinterpret_cast<rac_telemetry_manager_t*>(handle)));
}

// =============================================================================
// JNI FUNCTIONS - Analytics Events (rac_analytics_events.h)
// =============================================================================

// Global telemetry manager pointer for analytics callback routing
// The C callback routes events directly to the telemetry manager (same as Swift)
static rac_telemetry_manager_t* g_analytics_telemetry_manager = nullptr;
static std::mutex g_analytics_telemetry_mutex;

// C callback that routes analytics events to telemetry manager
// This mirrors Swift's analyticsEventCallback -> Telemetry.trackAnalyticsEvent()
static void jni_analytics_event_callback(rac_event_type_t type,
                                         const rac_analytics_event_data_t* data, void* user_data) {
    LOGi("jni_analytics_event_callback called: event_type=%d", type);

    std::lock_guard<std::mutex> lock(g_analytics_telemetry_mutex);
    if (g_analytics_telemetry_manager && data) {
        LOGi("jni_analytics_event_callback: routing to telemetry manager");
        rac_telemetry_manager_track_analytics(g_analytics_telemetry_manager, type, data);
    } else {
        LOGw("jni_analytics_event_callback: manager=%p, data=%p",
             (void*)g_analytics_telemetry_manager, (void*)data);
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventsSetCallback(
    JNIEnv* env, jclass clazz, jlong telemetryHandle) {
    LOGi("racAnalyticsEventsSetCallback called (telemetryHandle=%lld)", (long long)telemetryHandle);

    std::lock_guard<std::mutex> lock(g_analytics_telemetry_mutex);

    if (telemetryHandle != 0) {
        // Store telemetry manager and register C callback
        g_analytics_telemetry_manager = reinterpret_cast<rac_telemetry_manager_t*>(telemetryHandle);
        rac_result_t result =
            rac_analytics_events_set_callback(jni_analytics_event_callback, nullptr);
        LOGi("Analytics callback registered, result=%d", result);
        return static_cast<jint>(result);
    } else {
        // Unregister callback
        g_analytics_telemetry_manager = nullptr;
        rac_result_t result = rac_analytics_events_set_callback(nullptr, nullptr);
        LOGi("Analytics callback unregistered, result=%d", result);
        return static_cast<jint>(result);
    }
}

// =============================================================================
// JNI FUNCTIONS - Analytics Event Emission
// =============================================================================
// These functions allow Kotlin to emit analytics events (e.g., SDK lifecycle events
// that originate from Kotlin code). They call rac_analytics_event_emit() which
// routes events through the registered callback to the telemetry manager.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitDownload(
    JNIEnv* env, jclass clazz, jint eventType, jstring modelId, jdouble progress,
    jlong bytesDownloaded, jlong totalBytes, jdouble durationMs, jlong sizeBytes,
    jstring archiveType, jint errorCode, jstring errorMessage) {
    std::string modelIdStr = getCString(env, modelId);
    std::string archiveTypeStorage;
    std::string errorMsgStorage;
    const char* archiveTypePtr = getNullableCString(env, archiveType, archiveTypeStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.model_download.model_id = modelIdStr.c_str();
    event_data.data.model_download.progress = progress;
    event_data.data.model_download.bytes_downloaded = bytesDownloaded;
    event_data.data.model_download.total_bytes = totalBytes;
    event_data.data.model_download.duration_ms = durationMs;
    event_data.data.model_download.size_bytes = sizeBytes;
    event_data.data.model_download.archive_type = archiveTypePtr;
    event_data.data.model_download.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.model_download.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSdkLifecycle(
    JNIEnv* env, jclass clazz, jint eventType, jdouble durationMs, jint count, jint errorCode,
    jstring errorMessage) {
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.sdk_lifecycle.duration_ms = durationMs;
    event_data.data.sdk_lifecycle.count = count;
    event_data.data.sdk_lifecycle.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.sdk_lifecycle.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitStorage(
    JNIEnv* env, jclass clazz, jint eventType, jlong freedBytes, jint errorCode,
    jstring errorMessage) {
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.storage.freed_bytes = freedBytes;
    event_data.data.storage.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.storage.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitDevice(
    JNIEnv* env, jclass clazz, jint eventType, jstring deviceId, jint errorCode,
    jstring errorMessage) {
    std::string deviceIdStr = getCString(env, deviceId);
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.device.device_id = deviceIdStr.c_str();
    event_data.data.device.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.device.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSdkError(
    JNIEnv* env, jclass clazz, jint eventType, jint errorCode, jstring errorMessage,
    jstring operation, jstring context) {
    std::string errorMsgStorage, opStorage, ctxStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);
    const char* opPtr = getNullableCString(env, operation, opStorage);
    const char* ctxPtr = getNullableCString(env, context, ctxStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.sdk_error.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.sdk_error.error_message = errorMsgPtr;
    event_data.data.sdk_error.operation = opPtr;
    event_data.data.sdk_error.context = ctxPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitNetwork(
    JNIEnv* env, jclass clazz, jint eventType, jboolean isOnline) {
    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.network.is_online = isOnline ? RAC_TRUE : RAC_FALSE;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitLlmGeneration(
    JNIEnv* env, jclass clazz, jint eventType, jstring generationId, jstring modelId,
    jstring modelName, jint inputTokens, jint outputTokens, jdouble durationMs,
    jdouble tokensPerSecond, jboolean isStreaming, jdouble timeToFirstTokenMs, jint framework,
    jfloat temperature, jint maxTokens, jint contextLength, jint errorCode, jstring errorMessage) {
    std::string genIdStr = getCString(env, generationId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage;
    std::string errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.llm_generation.generation_id = genIdStr.c_str();
    event_data.data.llm_generation.model_id = modelIdStr.c_str();
    event_data.data.llm_generation.model_name = modelNamePtr;
    event_data.data.llm_generation.input_tokens = inputTokens;
    event_data.data.llm_generation.output_tokens = outputTokens;
    event_data.data.llm_generation.duration_ms = durationMs;
    event_data.data.llm_generation.tokens_per_second = tokensPerSecond;
    event_data.data.llm_generation.is_streaming = isStreaming ? RAC_TRUE : RAC_FALSE;
    event_data.data.llm_generation.time_to_first_token_ms = timeToFirstTokenMs;
    event_data.data.llm_generation.framework = static_cast<rac_inference_framework_t>(framework);
    event_data.data.llm_generation.temperature = temperature;
    event_data.data.llm_generation.max_tokens = maxTokens;
    event_data.data.llm_generation.context_length = contextLength;
    event_data.data.llm_generation.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.llm_generation.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitLlmModel(
    JNIEnv* env, jclass clazz, jint eventType, jstring modelId, jstring modelName,
    jlong modelSizeBytes, jdouble durationMs, jint framework, jint errorCode,
    jstring errorMessage) {
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage;
    std::string errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.llm_model.model_id = modelIdStr.c_str();
    event_data.data.llm_model.model_name = modelNamePtr;
    event_data.data.llm_model.model_size_bytes = modelSizeBytes;
    event_data.data.llm_model.duration_ms = durationMs;
    event_data.data.llm_model.framework = static_cast<rac_inference_framework_t>(framework);
    event_data.data.llm_model.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.llm_model.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSttTranscription(
    JNIEnv* env, jclass clazz, jint eventType, jstring transcriptionId, jstring modelId,
    jstring modelName, jstring text, jfloat confidence, jdouble durationMs, jdouble audioLengthMs,
    jint audioSizeBytes, jint wordCount, jdouble realTimeFactor, jstring language, jint sampleRate,
    jboolean isStreaming, jint framework, jint errorCode, jstring errorMessage) {
    std::string transIdStr = getCString(env, transcriptionId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage, textStorage, langStorage, errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* textPtr = getNullableCString(env, text, textStorage);
    const char* langPtr = getNullableCString(env, language, langStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.stt_transcription.transcription_id = transIdStr.c_str();
    event_data.data.stt_transcription.model_id = modelIdStr.c_str();
    event_data.data.stt_transcription.model_name = modelNamePtr;
    event_data.data.stt_transcription.text = textPtr;
    event_data.data.stt_transcription.confidence = confidence;
    event_data.data.stt_transcription.duration_ms = durationMs;
    event_data.data.stt_transcription.audio_length_ms = audioLengthMs;
    event_data.data.stt_transcription.audio_size_bytes = audioSizeBytes;
    event_data.data.stt_transcription.word_count = wordCount;
    event_data.data.stt_transcription.real_time_factor = realTimeFactor;
    event_data.data.stt_transcription.language = langPtr;
    event_data.data.stt_transcription.sample_rate = sampleRate;
    event_data.data.stt_transcription.is_streaming = isStreaming ? RAC_TRUE : RAC_FALSE;
    event_data.data.stt_transcription.framework = static_cast<rac_inference_framework_t>(framework);
    event_data.data.stt_transcription.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.stt_transcription.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitTtsSynthesis(
    JNIEnv* env, jclass clazz, jint eventType, jstring synthesisId, jstring modelId,
    jstring modelName, jint characterCount, jdouble audioDurationMs, jint audioSizeBytes,
    jdouble processingDurationMs, jdouble charactersPerSecond, jint sampleRate, jint framework,
    jint errorCode, jstring errorMessage) {
    std::string synthIdStr = getCString(env, synthesisId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage, errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.tts_synthesis.synthesis_id = synthIdStr.c_str();
    event_data.data.tts_synthesis.model_id = modelIdStr.c_str();
    event_data.data.tts_synthesis.model_name = modelNamePtr;
    event_data.data.tts_synthesis.character_count = characterCount;
    event_data.data.tts_synthesis.audio_duration_ms = audioDurationMs;
    event_data.data.tts_synthesis.audio_size_bytes = audioSizeBytes;
    event_data.data.tts_synthesis.processing_duration_ms = processingDurationMs;
    event_data.data.tts_synthesis.characters_per_second = charactersPerSecond;
    event_data.data.tts_synthesis.sample_rate = sampleRate;
    event_data.data.tts_synthesis.framework = static_cast<rac_inference_framework_t>(framework);
    event_data.data.tts_synthesis.error_code = static_cast<rac_result_t>(errorCode);
    event_data.data.tts_synthesis.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitVad(
    JNIEnv* env, jclass clazz, jint eventType, jdouble speechDurationMs, jfloat energyLevel) {
    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.vad.speech_duration_ms = speechDurationMs;
    event_data.data.vad.energy_level = energyLevel;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitVoiceAgentState(
    JNIEnv* env, jclass clazz, jint eventType, jstring component, jint state, jstring modelId,
    jstring errorMessage) {
    std::string componentStr = getCString(env, component);
    std::string modelIdStorage, errorMsgStorage;
    const char* modelIdPtr = getNullableCString(env, modelId, modelIdStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    rac_analytics_event_data_t event_data = {};
    event_data.type = static_cast<rac_event_type_t>(eventType);
    event_data.data.voice_agent_state.component = componentStr.c_str();
    event_data.data.voice_agent_state.state = static_cast<rac_voice_agent_component_state_t>(state);
    event_data.data.voice_agent_state.model_id = modelIdPtr;
    event_data.data.voice_agent_state.error_message = errorMsgPtr;

    rac_analytics_event_emit(event_data.type, &event_data);
    return RAC_SUCCESS;
}

// =============================================================================
// DEV CONFIG API (rac_dev_config.h)
// Mirrors Swift SDK's CppBridge+Environment.swift DevConfig
// =============================================================================

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigIsAvailable(JNIEnv* env,
                                                                                 jclass clazz) {
    return rac_dev_config_is_available() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetSupabaseUrl(JNIEnv* env,
                                                                                    jclass clazz) {
    const char* url = rac_dev_config_get_supabase_url();
    if (url == nullptr || strlen(url) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(url);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetSupabaseKey(JNIEnv* env,
                                                                                    jclass clazz) {
    const char* key = rac_dev_config_get_supabase_key();
    if (key == nullptr || strlen(key) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(key);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetBuildToken(JNIEnv* env,
                                                                                   jclass clazz) {
    const char* token = rac_dev_config_get_build_token();
    if (token == nullptr || strlen(token) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(token);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetSentryDsn(JNIEnv* env,
                                                                                  jclass clazz) {
    const char* dsn = rac_dev_config_get_sentry_dsn();
    if (dsn == nullptr || strlen(dsn) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(dsn);
}

// =============================================================================
// SDK Configuration Initialization
// =============================================================================

/**
 * Initialize SDK configuration with version and platform info.
 * This must be called during SDK initialization for device registration
 * to include the correct sdk_version (instead of "unknown").
 *
 * @param environment Environment (0=development, 1=staging, 2=production)
 * @param deviceId Device ID string
 * @param platform Platform string (e.g., "android")
 * @param sdkVersion SDK version string (e.g., "0.1.0")
 * @param apiKey API key (can be empty for development)
 * @param baseUrl Base URL (can be empty for development)
 * @return 0 on success, error code on failure
 */
JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkInit(
    JNIEnv* env, jclass clazz, jint environment, jstring deviceId, jstring platform,
    jstring sdkVersion, jstring apiKey, jstring baseUrl) {
    rac_sdk_config_t config = {};
    config.environment = static_cast<rac_environment_t>(environment);

    std::string deviceIdStr = getCString(env, deviceId);
    std::string platformStr = getCString(env, platform);
    std::string sdkVersionStr = getCString(env, sdkVersion);
    std::string apiKeyStr = getCString(env, apiKey);
    std::string baseUrlStr = getCString(env, baseUrl);

    config.device_id = deviceIdStr.empty() ? nullptr : deviceIdStr.c_str();
    config.platform = platformStr.empty() ? "android" : platformStr.c_str();
    config.sdk_version = sdkVersionStr.empty() ? nullptr : sdkVersionStr.c_str();
    config.api_key = apiKeyStr.empty() ? nullptr : apiKeyStr.c_str();
    config.base_url = baseUrlStr.empty() ? nullptr : baseUrlStr.c_str();

    LOGi("racSdkInit: env=%d, platform=%s, sdk_version=%s", environment,
         config.platform ? config.platform : "(null)",
         config.sdk_version ? config.sdk_version : "(null)");

    rac_validation_result_t result = rac_sdk_init(&config);

    if (result == RAC_VALIDATION_OK) {
        LOGi("racSdkInit: SDK config initialized successfully");
    } else {
        LOGe("racSdkInit: Failed with result %d", result);
    }

    return static_cast<jint>(result);
}

// =============================================================================
// TOOL CALLING API (rac_tool_calling.h)
// Mirrors Swift SDK's CppBridge+ToolCalling.swift
// =============================================================================

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallParse(JNIEnv* env, jclass clazz,
                                                                          jstring llmOutput) {
    std::string outputStr = getCString(env, llmOutput);
    rac_tool_call_t result;

    rac_result_t rc = rac_tool_call_parse(outputStr.c_str(), &result);

    // Build JSON response
    std::string json = "{";
    json += "\"hasToolCall\":";
    json += (result.has_tool_call == RAC_TRUE) ? "true" : "false";
    json += ",\"cleanText\":\"";

    // Escape clean text
    if (result.clean_text) {
        for (const char* p = result.clean_text; *p; p++) {
            switch (*p) {
                case '"': json += "\\\""; break;
                case '\\': json += "\\\\"; break;
                case '\n': json += "\\n"; break;
                case '\r': json += "\\r"; break;
                case '\t': json += "\\t"; break;
                default: json += *p; break;
            }
        }
    }
    json += "\"";

    if (result.has_tool_call == RAC_TRUE) {
        json += ",\"toolName\":\"";
        if (result.tool_name) json += result.tool_name;
        json += "\",\"argumentsJson\":";
        if (result.arguments_json) {
            // Validate that arguments_json is valid JSON object/array before inserting
            // This prevents malformed JSON from breaking the response
            std::string args(result.arguments_json);
            // Trim leading whitespace
            size_t start = args.find_first_not_of(" \t\n\r");
            if (start != std::string::npos && (args[start] == '{' || args[start] == '[')) {
                // Appears to be valid JSON object/array - insert directly
                json += args;
            } else {
                // Fallback: not a valid JSON object/array, use empty object
                LOGe("racToolCallParse: arguments_json is not valid JSON object/array, using empty object");
                json += "{}";
            }
        } else {
            json += "{}";
        }
        json += ",\"callId\":";
        json += std::to_string(result.call_id);
    }

    json += "}";

    rac_tool_call_free(&result);
    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallFormatPromptJson(
    JNIEnv* env, jclass clazz, jstring toolsJson) {
    std::string toolsStr = getCString(env, toolsJson);
    char* prompt = nullptr;

    rac_result_t rc = rac_tool_call_format_prompt_json(toolsStr.c_str(), &prompt);

    if (rc != RAC_SUCCESS || prompt == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(prompt);
    rac_free(prompt);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallFormatPromptJsonWithFormat(
    JNIEnv* env, jclass clazz, jstring toolsJson, jint format) {
    std::string toolsStr = getCString(env, toolsJson);
    char* prompt = nullptr;

    rac_result_t rc = rac_tool_call_format_prompt_json_with_format(
        toolsStr.c_str(),
        static_cast<rac_tool_call_format_t>(format),
        &prompt
    );

    if (rc != RAC_SUCCESS || prompt == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(prompt);
    rac_free(prompt);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallFormatPromptJsonWithFormatName(
    JNIEnv* env, jclass clazz, jstring toolsJson, jstring formatName) {
    std::string toolsStr = getCString(env, toolsJson);
    std::string formatStr = getCString(env, formatName);
    char* prompt = nullptr;

    // Use string-based API (C++ is single source of truth for format names)
    rac_result_t rc = rac_tool_call_format_prompt_json_with_format_name(
        toolsStr.c_str(),
        formatStr.c_str(),
        &prompt
    );

    if (rc != RAC_SUCCESS || prompt == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(prompt);
    rac_free(prompt);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallBuildInitialPrompt(
    JNIEnv* env, jclass clazz, jstring userPrompt, jstring toolsJson, jstring optionsJson) {
    std::string userStr = getCString(env, userPrompt);
    std::string toolsStr = getCString(env, toolsJson);

    // Parse options if provided (simplified - use defaults for now)
    rac_tool_calling_options_t options = {5, RAC_TRUE, 0.7f, 1024, nullptr, RAC_FALSE, RAC_FALSE};

    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_initial_prompt(userStr.c_str(), toolsStr.c_str(), &options, &prompt);

    if (rc != RAC_SUCCESS || prompt == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(prompt);
    rac_free(prompt);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallBuildFollowupPrompt(
    JNIEnv* env, jclass clazz, jstring originalPrompt, jstring toolsPrompt, jstring toolName,
    jstring toolResultJson, jboolean keepToolsAvailable) {
    std::string originalStr = getCString(env, originalPrompt);
    std::string toolsPromptStr = getCString(env, toolsPrompt);
    std::string toolNameStr = getCString(env, toolName);
    std::string resultJsonStr = getCString(env, toolResultJson);

    char* prompt = nullptr;
    rac_result_t rc = rac_tool_call_build_followup_prompt(
        originalStr.c_str(),
        toolsPromptStr.empty() ? nullptr : toolsPromptStr.c_str(),
        toolNameStr.c_str(),
        resultJsonStr.c_str(),
        keepToolsAvailable ? RAC_TRUE : RAC_FALSE,
        &prompt);

    if (rc != RAC_SUCCESS || prompt == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(prompt);
    rac_free(prompt);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallNormalizeJson(JNIEnv* env,
                                                                                   jclass clazz,
                                                                                   jstring jsonStr) {
    std::string inputStr = getCString(env, jsonStr);
    char* normalized = nullptr;

    rac_result_t rc = rac_tool_call_normalize_json(inputStr.c_str(), &normalized);

    if (rc != RAC_SUCCESS || normalized == nullptr) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(normalized);
    rac_free(normalized);
    return result;
}

// =============================================================================
// JNI FUNCTIONS - VLM Component
// =============================================================================

// Helper: Build a VLM result JSON string matching what Kotlin expects
static std::string buildVlmResultJson(const std::string& text, const rac_vlm_result_t& result) {
    nlohmann::json j;
    j["text"] = text;
    j["prompt_tokens"] = result.prompt_tokens;
    j["image_tokens"] = result.image_tokens;
    j["completion_tokens"] = result.completion_tokens;
    j["total_tokens"] = result.total_tokens;
    j["time_to_first_token_ms"] = result.time_to_first_token_ms;
    j["image_encode_time_ms"] = result.image_encode_time_ms;
    j["total_time_ms"] = result.total_time_ms;
    j["tokens_per_second"] = result.tokens_per_second;
    return j.dump();
}

// Helper: Populate rac_vlm_image_t from JNI parameters
static void fillVlmImage(rac_vlm_image_t& image,
                          jint imageFormat,
                          const std::string& imagePath,
                          JNIEnv* env, jbyteArray imageData,
                          const std::string& imageBase64,
                          jint imageWidth, jint imageHeight,
                          const uint8_t*& pixelDataOut) {
    memset(&image, 0, sizeof(image));
    image.format = static_cast<rac_vlm_image_format_t>(imageFormat);
    image.width = static_cast<uint32_t>(imageWidth);
    image.height = static_cast<uint32_t>(imageHeight);

    switch (image.format) {
        case RAC_VLM_IMAGE_FORMAT_FILE_PATH:
            image.file_path = imagePath.empty() ? nullptr : imagePath.c_str();
            break;
        case RAC_VLM_IMAGE_FORMAT_RGB_PIXELS:
            if (imageData != nullptr) {
                jsize len = env->GetArrayLength(imageData);
                auto* buf = new uint8_t[len];
                env->GetByteArrayRegion(imageData, 0, len, reinterpret_cast<jbyte*>(buf));
                image.pixel_data = buf;
                image.data_size = static_cast<size_t>(len);
                pixelDataOut = buf;
            }
            break;
        case RAC_VLM_IMAGE_FORMAT_BASE64:
            image.base64_data = imageBase64.empty() ? nullptr : imageBase64.c_str();
            if (image.base64_data) {
                image.data_size = imageBase64.length();
            }
            break;
    }
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_vlm_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create VLM component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_vlm_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring mmprojPath,
    jstring modelId, jstring modelName) {
    LOGi("racVlmComponentLoadModel called with handle=%lld", (long long)handle);
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    std::string path = getCString(env, modelPath);
    std::string mmprojStorage;
    const char* mmproj = getNullableCString(env, mmprojPath, mmprojStorage);
    std::string id = getCString(env, modelId);
    std::string nameStorage;
    const char* name = getNullableCString(env, modelName, nameStorage);

    LOGi("racVlmComponentLoadModel path=%s, mmproj=%s, id=%s, name=%s",
         path.c_str(), mmproj ? mmproj : "NULL", id.c_str(), name ? name : "NULL");

    rac_result_t result = rac_vlm_component_load_model(
        reinterpret_cast<rac_handle_t>(handle),
        path.c_str(),
        mmproj,
        id.c_str(),
        name);

    LOGi("rac_vlm_component_load_model returned: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    return static_cast<jint>(rac_vlm_component_unload(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    return static_cast<jint>(rac_vlm_component_cancel(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentLoadModelById(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelId) {
    LOGi("racVlmComponentLoadModelById called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racVlmComponentLoadModelById: invalid handle");
        return static_cast<jint>(RAC_ERROR_INVALID_HANDLE);
    }

    std::string modelIdStr = getCString(env, modelId);
    if (modelIdStr.empty()) {
        LOGe("racVlmComponentLoadModelById: empty model ID");
        return static_cast<jint>(RAC_ERROR_INVALID_ARGUMENT);
    }

    LOGi("racVlmComponentLoadModelById modelId=%s", modelIdStr.c_str());
    rac_result_t result =
        rac_vlm_component_load_model_by_id(reinterpret_cast<rac_handle_t>(handle), modelIdStr.c_str());
    LOGi("rac_vlm_component_load_model_by_id returned: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentIsLoaded(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_vlm_component_is_loaded(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                               : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentGetModelId(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jlong handle) {
    if (handle == 0)
        return nullptr;
    const char* modelId = rac_vlm_component_get_model_id(reinterpret_cast<rac_handle_t>(handle));
    if (modelId == nullptr)
        return nullptr;
    return env->NewStringUTF(modelId);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentProcess(
    JNIEnv* env, jclass clazz, jlong handle, jint imageFormat, jstring imagePath,
    jbyteArray imageData, jstring imageBase64, jint imageWidth, jint imageHeight,
    jstring prompt, jstring optionsJson) {
    LOGi("racVlmComponentProcess called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racVlmComponentProcess: invalid handle");
        return nullptr;
    }

    std::string promptStr = getCString(env, prompt);
    std::string imagePathStr = getCString(env, imagePath);
    std::string imageBase64Str = getCString(env, imageBase64);

    LOGi("racVlmComponentProcess prompt length=%zu, imageFormat=%d",
         promptStr.length(), imageFormat);

    // Build image struct
    rac_vlm_image_t image;
    const uint8_t* pixelBuf = nullptr;
    fillVlmImage(image, imageFormat, imagePathStr, env, imageData,
                 imageBase64Str, imageWidth, imageHeight, pixelBuf);

    // Default options (optionsJson is intentionally unused for now — VLM options
    // are configured at the native layer; Kotlin-side overrides will be added later)
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    options.streaming_enabled = RAC_FALSE;

    rac_vlm_result_t result = {};
    rac_result_t status = rac_vlm_component_process(
        reinterpret_cast<rac_handle_t>(handle), &image, promptStr.c_str(), &options, &result);

    // Clean up pixel buffer if allocated
    delete[] pixelBuf;

    if (status != RAC_SUCCESS) {
        LOGe("racVlmComponentProcess failed with status=%d", status);
        return nullptr;
    }

    std::string text = result.text ? result.text : "";
    std::string json = buildVlmResultJson(text, result);

    LOGi("racVlmComponentProcess returning JSON: %zu bytes", json.length());

    jstring jResult = env->NewStringUTF(json.c_str());
    rac_vlm_result_free(&result);
    return jResult;
}

// ========================================================================
// VLM STREAMING CONTEXT
// ========================================================================

struct VLMStreamCallbackContext {
    JavaVM* jvm = nullptr;
    jobject callback = nullptr;
    jmethodID onTokenMethod = nullptr;
    std::string accumulated_text;
    int token_count = 0;
    bool is_complete = false;
    bool has_error = false;
    rac_result_t error_code = RAC_SUCCESS;
    std::string error_message;
    rac_vlm_result_t final_result = {};
};

static rac_bool_t vlm_stream_callback_token(const char* token, void* user_data) {
    if (!user_data || !token)
        return RAC_TRUE;

    auto* ctx = static_cast<VLMStreamCallbackContext*>(user_data);

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
                LOGe("VLM: Failed to attach thread for streaming callback");
                return RAC_TRUE;
            }
        }

        if (env) {
            jsize len = static_cast<jsize>(strlen(token));
            jbyteArray jToken = env->NewByteArray(len);
            env->SetByteArrayRegion(
                jToken, 0, len,
                reinterpret_cast<const jbyte*>(token));

            jboolean continueGen =
                env->CallBooleanMethod(ctx->callback, ctx->onTokenMethod, jToken);
            env->DeleteLocalRef(jToken);

            if (env->ExceptionCheck()) {
                env->ExceptionDescribe();
                env->ExceptionClear();
                if (needsDetach) {
                    ctx->jvm->DetachCurrentThread();
                }
                return RAC_FALSE;  // Stop generation on exception
            }

            if (needsDetach) {
                ctx->jvm->DetachCurrentThread();
            }

            if (!continueGen) {
                LOGi("VLM: Streaming cancelled by callback");
                return RAC_FALSE;
            }
        }
    }

    return RAC_TRUE;
}

static void vlm_stream_callback_complete(const rac_vlm_result_t* result, void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<VLMStreamCallbackContext*>(user_data);

    LOGi("VLM streaming complete: %d tokens", ctx->token_count);

    if (result) {
        ctx->final_result.prompt_tokens = result->prompt_tokens;
        ctx->final_result.image_tokens = result->image_tokens;
        ctx->final_result.completion_tokens =
            result->completion_tokens > 0 ? result->completion_tokens : ctx->token_count;
        ctx->final_result.total_tokens = result->total_tokens;
        ctx->final_result.time_to_first_token_ms = result->time_to_first_token_ms;
        ctx->final_result.image_encode_time_ms = result->image_encode_time_ms;
        ctx->final_result.total_time_ms = result->total_time_ms;
        ctx->final_result.tokens_per_second = result->tokens_per_second;
    } else {
        ctx->final_result.completion_tokens = ctx->token_count;
    }

    ctx->is_complete = true;
}

static void vlm_stream_callback_error(rac_result_t error_code, const char* error_message,
                                       void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<VLMStreamCallbackContext*>(user_data);

    LOGe("VLM streaming error: %d - %s", error_code, error_message ? error_message : "Unknown");

    ctx->has_error = true;
    ctx->error_code = error_code;
    ctx->error_message = error_message ? error_message : "Unknown error";
    ctx->is_complete = true;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentProcessStream(
    JNIEnv* env, jclass clazz, jlong handle, jint imageFormat, jstring imagePath,
    jbyteArray imageData, jstring imageBase64, jint imageWidth, jint imageHeight,
    jstring prompt, jstring optionsJson, jobject tokenCallback) {
    LOGi("racVlmComponentProcessStream called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("racVlmComponentProcessStream: invalid handle");
        return nullptr;
    }

    if (!tokenCallback) {
        LOGe("racVlmComponentProcessStream: null callback");
        return nullptr;
    }

    std::string promptStr = getCString(env, prompt);
    std::string imagePathStr = getCString(env, imagePath);
    std::string imageBase64Str = getCString(env, imageBase64);

    LOGi("racVlmComponentProcessStream prompt length=%zu, imageFormat=%d",
         promptStr.length(), imageFormat);

    // Build image struct
    rac_vlm_image_t image;
    const uint8_t* pixelBuf = nullptr;
    fillVlmImage(image, imageFormat, imagePathStr, env, imageData,
                 imageBase64Str, imageWidth, imageHeight, pixelBuf);

    // Get JVM and callback method
    JavaVM* jvm = nullptr;
    env->GetJavaVM(&jvm);

    jclass callbackClass = env->GetObjectClass(tokenCallback);
    jmethodID onTokenMethod = env->GetMethodID(callbackClass, "onToken", "([B)Z");
    env->DeleteLocalRef(callbackClass);

    if (!onTokenMethod) {
        LOGe("racVlmComponentProcessStream: could not find onToken method");
        delete[] pixelBuf;
        return nullptr;
    }

    jobject globalCallback = env->NewGlobalRef(tokenCallback);

    // Default options (optionsJson is intentionally unused for now — VLM options
    // are configured at the native layer; Kotlin-side overrides will be added later)
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    options.streaming_enabled = RAC_TRUE;

    // Create streaming callback context
    VLMStreamCallbackContext ctx;
    ctx.jvm = jvm;
    ctx.callback = globalCallback;
    ctx.onTokenMethod = onTokenMethod;

    LOGi("racVlmComponentProcessStream calling rac_vlm_component_process_stream...");

    rac_result_t status = rac_vlm_component_process_stream(
        reinterpret_cast<rac_handle_t>(handle), &image, promptStr.c_str(), &options,
        vlm_stream_callback_token, vlm_stream_callback_complete, vlm_stream_callback_error, &ctx);

    // Clean up
    env->DeleteGlobalRef(globalCallback);
    delete[] pixelBuf;

    if (status != RAC_SUCCESS) {
        LOGe("rac_vlm_component_process_stream failed with status=%d", status);
        return nullptr;
    }

    if (ctx.has_error) {
        LOGe("VLM streaming failed: %s", ctx.error_message.c_str());
        return nullptr;
    }

    std::string json = buildVlmResultJson(ctx.accumulated_text, ctx.final_result);

    LOGi("racVlmComponentProcessStream returning JSON: %zu bytes", json.length());

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentSupportsStreaming(
    JNIEnv* env, jclass clazz, jlong handle) {
    if (handle == 0)
        return JNI_FALSE;
    return rac_vlm_component_supports_streaming(reinterpret_cast<rac_handle_t>(handle)) ? JNI_TRUE
                                                                                        : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentGetState(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle) {
    if (handle == 0)
        return 0;
    return static_cast<jint>(rac_vlm_component_get_state(reinterpret_cast<rac_handle_t>(handle)));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmComponentGetMetrics(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jlong handle) {
    if (handle == 0)
        return nullptr;

    rac_lifecycle_metrics_t metrics = {};
    rac_result_t status =
        rac_vlm_component_get_metrics(reinterpret_cast<rac_handle_t>(handle), &metrics);

    if (status != RAC_SUCCESS) {
        LOGe("racVlmComponentGetMetrics failed with status=%d", status);
        return nullptr;
    }

    nlohmann::json j;
    j["total_events"] = metrics.total_events;
    j["start_time_ms"] = metrics.start_time_ms;
    j["last_event_time_ms"] = metrics.last_event_time_ms;
    j["total_loads"] = metrics.total_loads;
    j["successful_loads"] = metrics.successful_loads;
    j["failed_loads"] = metrics.failed_loads;
    j["average_load_time_ms"] = metrics.average_load_time_ms;
    j["total_unloads"] = metrics.total_unloads;
    std::string json = j.dump();

    return env->NewStringUTF(json.c_str());
}

}  // extern "C"

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
