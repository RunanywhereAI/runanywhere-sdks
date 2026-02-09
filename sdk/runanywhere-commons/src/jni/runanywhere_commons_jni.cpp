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
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

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
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

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

// Forward declarations for helpers used by adapters
static JNIEnv* getJNIEnv();
static bool clearPendingException(JNIEnv* env, const char* context);
static int64_t nowEpochMs();

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
// Global State for Component Callback Registration
// =============================================================================

struct VadCallbackState {
    std::mutex mutex;
    JavaVM* jvm = nullptr;
    jobject frame_callback = nullptr;
    jobject speech_start_callback = nullptr;
    jobject speech_end_callback = nullptr;
    jobject progress_callback = nullptr;
    jmethodID frame_method = nullptr;         // streamFrameCallback(ZFI)Z
    jmethodID speech_start_method = nullptr;  // speechStartCallback(J)V
    jmethodID speech_end_method = nullptr;    // speechEndCallback(JJF)V
    jmethodID progress_method = nullptr;      // progressCallback(F)V
    int64_t last_speech_start_ms = 0;
};

struct TtsCallbackState {
    std::mutex mutex;
    JavaVM* jvm = nullptr;
    jobject audio_callback = nullptr;
    jobject progress_callback = nullptr;
    jmethodID audio_method = nullptr;     // streamAudioCallback([BZ)Z
    jmethodID progress_method = nullptr;  // progressCallback(F)V
};

struct VoiceAgentCallbackState {
    std::mutex mutex;
    JavaVM* jvm = nullptr;
    jobject state_callback = nullptr;
    jobject turn_phase_callback = nullptr;
    jobject partial_transcription_callback = nullptr;
    jobject response_token_callback = nullptr;
    jobject audio_chunk_callback = nullptr;
    jobject user_interrupt_callback = nullptr;
    jobject progress_callback = nullptr;
    jmethodID state_method = nullptr;                 // stateChangeCallback(I)V
    jmethodID turn_phase_method = nullptr;            // turnPhaseCallback(I)V
    jmethodID partial_transcription_method = nullptr; // partialTranscriptionCallback(Ljava/lang/String;)V
    jmethodID response_token_method = nullptr;        // responseTokenCallback(Ljava/lang/String;Z)Z
    jmethodID audio_chunk_method = nullptr;           // audioChunkCallback([BZ)Z
    jmethodID user_interrupt_method = nullptr;        // userInterruptCallback()V
    jmethodID progress_method = nullptr;              // progressCallback(F)V
};

static VadCallbackState g_vad_callbacks;
static TtsCallbackState g_tts_callbacks;
static VoiceAgentCallbackState g_voice_agent_callbacks;

struct TtsStreamContext {
    std::vector<uint8_t> audio_buffer;
};

static void tts_stream_adapter(const void* audio_data, size_t audio_size, void* user_data) {
    if (!audio_data || audio_size == 0 || !user_data) {
        return;
    }

    auto* ctx = static_cast<TtsStreamContext*>(user_data);
    const auto* bytes = static_cast<const uint8_t*>(audio_data);
    ctx->audio_buffer.insert(ctx->audio_buffer.end(), bytes, bytes + audio_size);

    JNIEnv* env = getJNIEnv();
    if (!env) {
        return;
    }

    jobject callback = nullptr;
    jmethodID method = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_tts_callbacks.mutex);
        if (g_tts_callbacks.audio_callback && g_tts_callbacks.audio_method) {
            callback = env->NewLocalRef(g_tts_callbacks.audio_callback);
            method = g_tts_callbacks.audio_method;
        }
    }

    if (!callback || !method) {
        return;
    }

    jbyteArray jAudio = env->NewByteArray(static_cast<jsize>(audio_size));
    env->SetByteArrayRegion(jAudio, 0, static_cast<jsize>(audio_size),
                            reinterpret_cast<const jbyte*>(audio_data));
    env->CallBooleanMethod(callback, method, jAudio, JNI_FALSE);
    env->DeleteLocalRef(jAudio);
    env->DeleteLocalRef(callback);
    clearPendingException(env, "tts_stream_adapter CallBooleanMethod");
}

static void vad_activity_adapter(rac_speech_activity_t activity, void* user_data) {
    (void)user_data;

    JNIEnv* env = getJNIEnv();
    if (!env) {
        return;
    }

    jobject frame_cb = nullptr;
    jobject start_cb = nullptr;
    jobject end_cb = nullptr;
    jmethodID frame_method = nullptr;
    jmethodID start_method = nullptr;
    jmethodID end_method = nullptr;
    int64_t start_ms = 0;

    int64_t now_ms = nowEpochMs();
    int event_type = 0;
    bool is_speech = false;
    float probability = 0.0f;

    {
        std::lock_guard<std::mutex> lock(g_vad_callbacks.mutex);
        if (activity == RAC_SPEECH_STARTED) {
            g_vad_callbacks.last_speech_start_ms = now_ms;
        }
        start_ms = g_vad_callbacks.last_speech_start_ms;

        if (g_vad_callbacks.frame_callback && g_vad_callbacks.frame_method) {
            frame_cb = env->NewLocalRef(g_vad_callbacks.frame_callback);
            frame_method = g_vad_callbacks.frame_method;
        }
        if (g_vad_callbacks.speech_start_callback && g_vad_callbacks.speech_start_method) {
            start_cb = env->NewLocalRef(g_vad_callbacks.speech_start_callback);
            start_method = g_vad_callbacks.speech_start_method;
        }
        if (g_vad_callbacks.speech_end_callback && g_vad_callbacks.speech_end_method) {
            end_cb = env->NewLocalRef(g_vad_callbacks.speech_end_callback);
            end_method = g_vad_callbacks.speech_end_method;
        }
    }

    if (activity == RAC_SPEECH_STARTED) {
        event_type = 1;  // SPEECH_START
        is_speech = true;
        probability = 1.0f;
        if (start_cb && start_method) {
            env->CallVoidMethod(start_cb, start_method, static_cast<jlong>(now_ms));
            clearPendingException(env, "vad_activity_adapter speechStartCallback");
        }
    } else if (activity == RAC_SPEECH_ENDED) {
        event_type = 3;  // SPEECH_END
        is_speech = false;
        probability = 0.0f;
        if (end_cb && end_method) {
            env->CallVoidMethod(end_cb, end_method, static_cast<jlong>(start_ms),
                                static_cast<jlong>(now_ms), static_cast<jfloat>(1.0f));
            clearPendingException(env, "vad_activity_adapter speechEndCallback");
        }
    } else {
        event_type = 2;  // SPEECH_ONGOING
        is_speech = true;
        probability = 1.0f;
    }

    if (frame_cb && frame_method) {
        env->CallBooleanMethod(frame_cb, frame_method, static_cast<jboolean>(is_speech),
                               static_cast<jfloat>(probability), static_cast<jint>(event_type));
        clearPendingException(env, "vad_activity_adapter streamFrameCallback");
    }

    if (frame_cb)
        env->DeleteLocalRef(frame_cb);
    if (start_cb)
        env->DeleteLocalRef(start_cb);
    if (end_cb)
        env->DeleteLocalRef(end_cb);
}

static void voice_agent_event_adapter(const rac_voice_agent_event_t* event, void* user_data) {
    (void)user_data;
    if (!event) {
        return;
    }

    JNIEnv* env = getJNIEnv();
    if (!env) {
        return;
    }

    jobject partial_cb = nullptr;
    jobject response_cb = nullptr;
    jobject audio_cb = nullptr;
    jmethodID partial_method = nullptr;
    jmethodID response_method = nullptr;
    jmethodID audio_method = nullptr;

    {
        std::lock_guard<std::mutex> lock(g_voice_agent_callbacks.mutex);
        if (g_voice_agent_callbacks.partial_transcription_callback &&
            g_voice_agent_callbacks.partial_transcription_method) {
            partial_cb = env->NewLocalRef(g_voice_agent_callbacks.partial_transcription_callback);
            partial_method = g_voice_agent_callbacks.partial_transcription_method;
        }
        if (g_voice_agent_callbacks.response_token_callback &&
            g_voice_agent_callbacks.response_token_method) {
            response_cb = env->NewLocalRef(g_voice_agent_callbacks.response_token_callback);
            response_method = g_voice_agent_callbacks.response_token_method;
        }
        if (g_voice_agent_callbacks.audio_chunk_callback &&
            g_voice_agent_callbacks.audio_chunk_method) {
            audio_cb = env->NewLocalRef(g_voice_agent_callbacks.audio_chunk_callback);
            audio_method = g_voice_agent_callbacks.audio_chunk_method;
        }
    }

    switch (event->type) {
        case RAC_VOICE_AGENT_EVENT_TRANSCRIPTION: {
            if (partial_cb && partial_method && event->data.transcription) {
                jstring jText = env->NewStringUTF(event->data.transcription);
                env->CallVoidMethod(partial_cb, partial_method, jText);
                env->DeleteLocalRef(jText);
                clearPendingException(env, "voice_agent_event_adapter partialTranscriptionCallback");
            }
            break;
        }
        case RAC_VOICE_AGENT_EVENT_RESPONSE: {
            if (response_cb && response_method && event->data.response) {
                jstring jToken = env->NewStringUTF(event->data.response);
                env->CallBooleanMethod(response_cb, response_method, jToken, JNI_TRUE);
                env->DeleteLocalRef(jToken);
                clearPendingException(env, "voice_agent_event_adapter responseTokenCallback");
            }
            break;
        }
        case RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED: {
            if (audio_cb && audio_method && event->data.audio.audio_data &&
                event->data.audio.audio_size > 0) {
                jbyteArray jAudio = env->NewByteArray(static_cast<jsize>(event->data.audio.audio_size));
                env->SetByteArrayRegion(jAudio, 0, static_cast<jsize>(event->data.audio.audio_size),
                                        reinterpret_cast<const jbyte*>(event->data.audio.audio_data));
                env->CallBooleanMethod(audio_cb, audio_method, jAudio, JNI_TRUE);
                env->DeleteLocalRef(jAudio);
                clearPendingException(env, "voice_agent_event_adapter audioChunkCallback");
            }
            break;
        }
        default:
            break;
    }

    if (partial_cb)
        env->DeleteLocalRef(partial_cb);
    if (response_cb)
        env->DeleteLocalRef(response_cb);
    if (audio_cb)
        env->DeleteLocalRef(audio_cb);
}

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

    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
        {
            std::lock_guard<std::mutex> tts_lock(g_tts_callbacks.mutex);
            if (g_tts_callbacks.audio_callback) {
                env->DeleteGlobalRef(g_tts_callbacks.audio_callback);
                g_tts_callbacks.audio_callback = nullptr;
            }
            if (g_tts_callbacks.progress_callback) {
                env->DeleteGlobalRef(g_tts_callbacks.progress_callback);
                g_tts_callbacks.progress_callback = nullptr;
            }
        }
        {
            std::lock_guard<std::mutex> vad_lock(g_vad_callbacks.mutex);
            if (g_vad_callbacks.frame_callback) {
                env->DeleteGlobalRef(g_vad_callbacks.frame_callback);
                g_vad_callbacks.frame_callback = nullptr;
            }
            if (g_vad_callbacks.speech_start_callback) {
                env->DeleteGlobalRef(g_vad_callbacks.speech_start_callback);
                g_vad_callbacks.speech_start_callback = nullptr;
            }
            if (g_vad_callbacks.speech_end_callback) {
                env->DeleteGlobalRef(g_vad_callbacks.speech_end_callback);
                g_vad_callbacks.speech_end_callback = nullptr;
            }
            if (g_vad_callbacks.progress_callback) {
                env->DeleteGlobalRef(g_vad_callbacks.progress_callback);
                g_vad_callbacks.progress_callback = nullptr;
            }
        }
        {
            std::lock_guard<std::mutex> voice_lock(g_voice_agent_callbacks.mutex);
            if (g_voice_agent_callbacks.state_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.state_callback);
                g_voice_agent_callbacks.state_callback = nullptr;
            }
            if (g_voice_agent_callbacks.turn_phase_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.turn_phase_callback);
                g_voice_agent_callbacks.turn_phase_callback = nullptr;
            }
            if (g_voice_agent_callbacks.partial_transcription_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.partial_transcription_callback);
                g_voice_agent_callbacks.partial_transcription_callback = nullptr;
            }
            if (g_voice_agent_callbacks.response_token_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.response_token_callback);
                g_voice_agent_callbacks.response_token_callback = nullptr;
            }
            if (g_voice_agent_callbacks.audio_chunk_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.audio_chunk_callback);
                g_voice_agent_callbacks.audio_chunk_callback = nullptr;
            }
            if (g_voice_agent_callbacks.user_interrupt_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.user_interrupt_callback);
                g_voice_agent_callbacks.user_interrupt_callback = nullptr;
            }
            if (g_voice_agent_callbacks.progress_callback) {
                env->DeleteGlobalRef(g_voice_agent_callbacks.progress_callback);
                g_voice_agent_callbacks.progress_callback = nullptr;
            }
        }
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

static bool clearPendingException(JNIEnv* env, const char* context) {
    if (env != nullptr && env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        LOGe("%s: cleared pending JNI exception", context);
        return true;
    }
    return false;
}

static int64_t nowEpochMs() {
    auto now = std::chrono::system_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
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

    rac_llm_result_t result = {};
    LOGi("racLlmComponentGenerate calling rac_llm_component_generate...");

    rac_result_t status = rac_llm_component_generate(reinterpret_cast<rac_handle_t>(handle),
                                                     promptStr.c_str(), &options, &result);

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
                case '"':
                    json += "\\\"";
                    break;
                case '\\':
                    json += "\\\\";
                    break;
                case '\n':
                    json += "\\n";
                    break;
                case '\r':
                    json += "\\r";
                    break;
                case '\t':
                    json += "\\t";
                    break;
                default:
                    json += *p;
                    break;
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
            jboolean continueGen =
                env->CallBooleanMethod(ctx->callback, ctx->onTokenMethod, jToken);
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
}

static void llm_stream_callback_error(rac_result_t error_code, const char* error_message,
                                      void* user_data) {
    if (!user_data)
        return;

    auto* ctx = static_cast<LLMStreamCallbackContext*>(user_data);

    LOGe("Streaming with callback error: %d - %s", error_code,
         error_message ? error_message : "Unknown");

    ctx->has_error = true;
    ctx->error_code = error_code;
    ctx->error_message = error_message ? error_message : "Unknown error";
    ctx->is_complete = true;
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

    // Create streaming context
    LLMStreamContext ctx;

    LOGi("racLlmComponentGenerateStream calling rac_llm_component_generate_stream...");

    rac_result_t status = rac_llm_component_generate_stream(
        reinterpret_cast<rac_handle_t>(handle), promptStr.c_str(), &options,
        llm_stream_token_callback, llm_stream_complete_callback, llm_stream_error_callback, &ctx);

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
            case '"':
                json += "\\\"";
                break;
            case '\\':
                json += "\\\\";
                break;
            case '\n':
                json += "\\n";
                break;
            case '\r':
                json += "\\r";
                break;
            case '\t':
                json += "\\t";
                break;
            default:
                json += c;
                break;
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
        reinterpret_cast<rac_handle_t>(handle), promptStr.c_str(), &options,
        llm_stream_callback_token, llm_stream_callback_complete, llm_stream_callback_error, &ctx);

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
            case '"':
                json += "\\\"";
                break;
            case '\\':
                json += "\\\\";
                break;
            case '\n':
                json += "\\n";
                break;
            case '\r':
                json += "\\r";
                break;
            case '\t':
                json += "\\t";
                break;
            default:
                json += c;
                break;
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
        const char* json = env->GetStringUTFChars(configJson, nullptr);
        if (json != nullptr) {
            // Simple JSON parsing for sample_rate
            const char* sample_rate_key = "\"sample_rate\":";
            const char* pos = strstr(json, sample_rate_key);
            if (pos != nullptr) {
                pos += strlen(sample_rate_key);
                int sample_rate = atoi(pos);
                if (sample_rate > 0) {
                    options.sample_rate = sample_rate;
                    LOGd("Using sample_rate from config: %d", sample_rate);
                }
            }
            env->ReleaseStringUTFChars(configJson, json);
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
    std::string json_result = "{";
    json_result += "\"text\":\"";
    if (result.text != nullptr) {
        // Escape special characters in text
        for (const char* p = result.text; *p; ++p) {
            switch (*p) {
                case '"':
                    json_result += "\\\"";
                    break;
                case '\\':
                    json_result += "\\\\";
                    break;
                case '\n':
                    json_result += "\\n";
                    break;
                case '\r':
                    json_result += "\\r";
                    break;
                case '\t':
                    json_result += "\\t";
                    break;
                default:
                    json_result += *p;
                    break;
            }
        }
    }
    json_result += "\",";
    json_result += "\"language\":\"" +
                   std::string(result.detected_language ? result.detected_language : "en") + "\",";
    json_result += "\"duration_ms\":" + std::to_string(result.processing_time_ms) + ",";
    json_result += "\"completion_reason\":1,";  // END_OF_AUDIO
    json_result += "\"confidence\":" + std::to_string(result.confidence);
    json_result += "}";

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
    if (handle == 0)
        return nullptr;

    std::string textStr = getCString(env, text);
    rac_tts_options_t options = {};
    TtsStreamContext ctx;

    rac_result_t status = rac_tts_component_synthesize_stream(
        reinterpret_cast<rac_handle_t>(handle), textStr.c_str(), &options, tts_stream_adapter, &ctx);

    if (status != RAC_SUCCESS) {
        LOGe("TTS stream synthesize failed with status: %d", status);
        return nullptr;
    }

    // Send final callback marker if registered
    {
        jobject callback = nullptr;
        jmethodID method = nullptr;
        std::lock_guard<std::mutex> lock(g_tts_callbacks.mutex);
        if (g_tts_callbacks.audio_callback && g_tts_callbacks.audio_method) {
            callback = env->NewLocalRef(g_tts_callbacks.audio_callback);
            method = g_tts_callbacks.audio_method;
        }
        if (callback && method) {
            jbyteArray empty = env->NewByteArray(0);
            env->CallBooleanMethod(callback, method, empty, JNI_TRUE);
            env->DeleteLocalRef(empty);
            env->DeleteLocalRef(callback);
            clearPendingException(env, "racTtsComponentSynthesizeStream final callback");
        }
    }

    if (ctx.audio_buffer.empty()) {
        return nullptr;
    }

    jbyteArray jResult = env->NewByteArray(static_cast<jsize>(ctx.audio_buffer.size()));
    env->SetByteArrayRegion(jResult, 0, static_cast<jsize>(ctx.audio_buffer.size()),
                            reinterpret_cast<const jbyte*>(ctx.audio_buffer.data()));
    return jResult;
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
    LOGi("racTtsSetCallbacks called");

    std::lock_guard<std::mutex> lock(g_tts_callbacks.mutex);

    if (g_tts_callbacks.audio_callback != nullptr) {
        env->DeleteGlobalRef(g_tts_callbacks.audio_callback);
        g_tts_callbacks.audio_callback = nullptr;
    }
    if (g_tts_callbacks.progress_callback != nullptr) {
        env->DeleteGlobalRef(g_tts_callbacks.progress_callback);
        g_tts_callbacks.progress_callback = nullptr;
    }

    g_tts_callbacks.audio_method = nullptr;
    g_tts_callbacks.progress_method = nullptr;

    if (audioCallback == nullptr && progressCallback == nullptr) {
        LOGi("racTtsSetCallbacks: callbacks cleared");
        return;
    }

    env->GetJavaVM(&g_tts_callbacks.jvm);

    if (audioCallback != nullptr) {
        g_tts_callbacks.audio_callback = env->NewGlobalRef(audioCallback);
        jclass callbackClass = env->GetObjectClass(audioCallback);
        if (clearPendingException(env, "racTtsSetCallbacks GetObjectClass(audioCallback)") ||
            callbackClass == nullptr) {
            LOGe("racTtsSetCallbacks: failed to get audio callback class");
            env->DeleteGlobalRef(g_tts_callbacks.audio_callback);
            g_tts_callbacks.audio_callback = nullptr;
        } else {
        g_tts_callbacks.audio_method =
            env->GetMethodID(callbackClass, "streamAudioCallback", "([BZ)Z");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racTtsSetCallbacks GetMethodID(streamAudioCallback)") ||
            !g_tts_callbacks.audio_method) {
            LOGe("racTtsSetCallbacks: streamAudioCallback method not found");
            env->DeleteGlobalRef(g_tts_callbacks.audio_callback);
            g_tts_callbacks.audio_callback = nullptr;
        }
        }
    }

    if (progressCallback != nullptr) {
        g_tts_callbacks.progress_callback = env->NewGlobalRef(progressCallback);
        jclass callbackClass = env->GetObjectClass(progressCallback);
        if (clearPendingException(env, "racTtsSetCallbacks GetObjectClass(progressCallback)") ||
            callbackClass == nullptr) {
            LOGe("racTtsSetCallbacks: failed to get progress callback class");
            env->DeleteGlobalRef(g_tts_callbacks.progress_callback);
            g_tts_callbacks.progress_callback = nullptr;
        } else {
        g_tts_callbacks.progress_method =
            env->GetMethodID(callbackClass, "progressCallback", "(F)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racTtsSetCallbacks GetMethodID(progressCallback)") ||
            !g_tts_callbacks.progress_method) {
            LOGe("racTtsSetCallbacks: progressCallback method not found");
            env->DeleteGlobalRef(g_tts_callbacks.progress_callback);
            g_tts_callbacks.progress_callback = nullptr;
        }
        }
    }
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
    {
        std::lock_guard<std::mutex> lock(g_vad_callbacks.mutex);
        if (g_vad_callbacks.frame_callback || g_vad_callbacks.speech_start_callback ||
            g_vad_callbacks.speech_end_callback) {
            rac_vad_component_set_activity_callback(reinterpret_cast<rac_handle_t>(handle),
                                                   vad_activity_adapter, nullptr);
        }
    }
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
    LOGi("racVadSetCallbacks called");

    std::lock_guard<std::mutex> lock(g_vad_callbacks.mutex);

    if (g_vad_callbacks.frame_callback != nullptr) {
        env->DeleteGlobalRef(g_vad_callbacks.frame_callback);
        g_vad_callbacks.frame_callback = nullptr;
    }
    if (g_vad_callbacks.speech_start_callback != nullptr) {
        env->DeleteGlobalRef(g_vad_callbacks.speech_start_callback);
        g_vad_callbacks.speech_start_callback = nullptr;
    }
    if (g_vad_callbacks.speech_end_callback != nullptr) {
        env->DeleteGlobalRef(g_vad_callbacks.speech_end_callback);
        g_vad_callbacks.speech_end_callback = nullptr;
    }
    if (g_vad_callbacks.progress_callback != nullptr) {
        env->DeleteGlobalRef(g_vad_callbacks.progress_callback);
        g_vad_callbacks.progress_callback = nullptr;
    }

    g_vad_callbacks.frame_method = nullptr;
    g_vad_callbacks.speech_start_method = nullptr;
    g_vad_callbacks.speech_end_method = nullptr;
    g_vad_callbacks.progress_method = nullptr;

    if (frameCallback == nullptr && speechStartCallback == nullptr && speechEndCallback == nullptr &&
        progressCallback == nullptr) {
        LOGi("racVadSetCallbacks: callbacks cleared");
        return;
    }

    env->GetJavaVM(&g_vad_callbacks.jvm);

    if (frameCallback != nullptr) {
        g_vad_callbacks.frame_callback = env->NewGlobalRef(frameCallback);
        jclass callbackClass = env->GetObjectClass(frameCallback);
        if (clearPendingException(env, "racVadSetCallbacks GetObjectClass(frameCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVadSetCallbacks: failed to get frame callback class");
            env->DeleteGlobalRef(g_vad_callbacks.frame_callback);
            g_vad_callbacks.frame_callback = nullptr;
        } else {
        g_vad_callbacks.frame_method =
            env->GetMethodID(callbackClass, "streamFrameCallback", "(ZFI)Z");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVadSetCallbacks GetMethodID(streamFrameCallback)") ||
            !g_vad_callbacks.frame_method) {
            LOGe("racVadSetCallbacks: streamFrameCallback method not found");
            env->DeleteGlobalRef(g_vad_callbacks.frame_callback);
            g_vad_callbacks.frame_callback = nullptr;
        }
        }
    }

    if (speechStartCallback != nullptr) {
        g_vad_callbacks.speech_start_callback = env->NewGlobalRef(speechStartCallback);
        jclass callbackClass = env->GetObjectClass(speechStartCallback);
        if (clearPendingException(env, "racVadSetCallbacks GetObjectClass(speechStartCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVadSetCallbacks: failed to get speech start callback class");
            env->DeleteGlobalRef(g_vad_callbacks.speech_start_callback);
            g_vad_callbacks.speech_start_callback = nullptr;
        } else {
        g_vad_callbacks.speech_start_method =
            env->GetMethodID(callbackClass, "speechStartCallback", "(J)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVadSetCallbacks GetMethodID(speechStartCallback)") ||
            !g_vad_callbacks.speech_start_method) {
            LOGe("racVadSetCallbacks: speechStartCallback method not found");
            env->DeleteGlobalRef(g_vad_callbacks.speech_start_callback);
            g_vad_callbacks.speech_start_callback = nullptr;
        }
        }
    }

    if (speechEndCallback != nullptr) {
        g_vad_callbacks.speech_end_callback = env->NewGlobalRef(speechEndCallback);
        jclass callbackClass = env->GetObjectClass(speechEndCallback);
        if (clearPendingException(env, "racVadSetCallbacks GetObjectClass(speechEndCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVadSetCallbacks: failed to get speech end callback class");
            env->DeleteGlobalRef(g_vad_callbacks.speech_end_callback);
            g_vad_callbacks.speech_end_callback = nullptr;
        } else {
        g_vad_callbacks.speech_end_method =
            env->GetMethodID(callbackClass, "speechEndCallback", "(JJF)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVadSetCallbacks GetMethodID(speechEndCallback)") ||
            !g_vad_callbacks.speech_end_method) {
            LOGe("racVadSetCallbacks: speechEndCallback method not found");
            env->DeleteGlobalRef(g_vad_callbacks.speech_end_callback);
            g_vad_callbacks.speech_end_callback = nullptr;
        }
        }
    }

    if (progressCallback != nullptr) {
        g_vad_callbacks.progress_callback = env->NewGlobalRef(progressCallback);
        jclass callbackClass = env->GetObjectClass(progressCallback);
        if (clearPendingException(env, "racVadSetCallbacks GetObjectClass(progressCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVadSetCallbacks: failed to get progress callback class");
            env->DeleteGlobalRef(g_vad_callbacks.progress_callback);
            g_vad_callbacks.progress_callback = nullptr;
        } else {
        g_vad_callbacks.progress_method =
            env->GetMethodID(callbackClass, "progressCallback", "(F)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVadSetCallbacks GetMethodID(progressCallback)") ||
            !g_vad_callbacks.progress_method) {
            LOGe("racVadSetCallbacks: progressCallback method not found");
            env->DeleteGlobalRef(g_vad_callbacks.progress_callback);
            g_vad_callbacks.progress_callback = nullptr;
        }
        }
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentSetCallbacks(
    JNIEnv* env, jclass clazz, jobject stateCallback, jobject turnPhaseCallback,
    jobject partialTranscriptionCallback, jobject responseTokenCallback, jobject audioChunkCallback,
    jobject userInterruptCallback, jobject progressCallback) {
    LOGi("racVoiceAgentSetCallbacks called");

    std::lock_guard<std::mutex> lock(g_voice_agent_callbacks.mutex);

    if (g_voice_agent_callbacks.state_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.state_callback);
        g_voice_agent_callbacks.state_callback = nullptr;
    }
    if (g_voice_agent_callbacks.turn_phase_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.turn_phase_callback);
        g_voice_agent_callbacks.turn_phase_callback = nullptr;
    }
    if (g_voice_agent_callbacks.partial_transcription_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.partial_transcription_callback);
        g_voice_agent_callbacks.partial_transcription_callback = nullptr;
    }
    if (g_voice_agent_callbacks.response_token_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.response_token_callback);
        g_voice_agent_callbacks.response_token_callback = nullptr;
    }
    if (g_voice_agent_callbacks.audio_chunk_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.audio_chunk_callback);
        g_voice_agent_callbacks.audio_chunk_callback = nullptr;
    }
    if (g_voice_agent_callbacks.user_interrupt_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.user_interrupt_callback);
        g_voice_agent_callbacks.user_interrupt_callback = nullptr;
    }
    if (g_voice_agent_callbacks.progress_callback != nullptr) {
        env->DeleteGlobalRef(g_voice_agent_callbacks.progress_callback);
        g_voice_agent_callbacks.progress_callback = nullptr;
    }

    g_voice_agent_callbacks.state_method = nullptr;
    g_voice_agent_callbacks.turn_phase_method = nullptr;
    g_voice_agent_callbacks.partial_transcription_method = nullptr;
    g_voice_agent_callbacks.response_token_method = nullptr;
    g_voice_agent_callbacks.audio_chunk_method = nullptr;
    g_voice_agent_callbacks.user_interrupt_method = nullptr;
    g_voice_agent_callbacks.progress_method = nullptr;

    if (stateCallback == nullptr && turnPhaseCallback == nullptr &&
        partialTranscriptionCallback == nullptr && responseTokenCallback == nullptr &&
        audioChunkCallback == nullptr && userInterruptCallback == nullptr &&
        progressCallback == nullptr) {
        LOGi("racVoiceAgentSetCallbacks: callbacks cleared");
        return;
    }

    env->GetJavaVM(&g_voice_agent_callbacks.jvm);

    if (stateCallback != nullptr) {
        g_voice_agent_callbacks.state_callback = env->NewGlobalRef(stateCallback);
        jclass callbackClass = env->GetObjectClass(stateCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(stateCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get state callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.state_callback);
            g_voice_agent_callbacks.state_callback = nullptr;
        } else {
        g_voice_agent_callbacks.state_method =
            env->GetMethodID(callbackClass, "stateChangeCallback", "(I)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(stateChangeCallback)") ||
            !g_voice_agent_callbacks.state_method) {
            LOGe("racVoiceAgentSetCallbacks: stateChangeCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.state_callback);
            g_voice_agent_callbacks.state_callback = nullptr;
        }
        }
    }

    if (turnPhaseCallback != nullptr) {
        g_voice_agent_callbacks.turn_phase_callback = env->NewGlobalRef(turnPhaseCallback);
        jclass callbackClass = env->GetObjectClass(turnPhaseCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(turnPhaseCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get turn phase callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.turn_phase_callback);
            g_voice_agent_callbacks.turn_phase_callback = nullptr;
        } else {
        g_voice_agent_callbacks.turn_phase_method =
            env->GetMethodID(callbackClass, "turnPhaseCallback", "(I)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(turnPhaseCallback)") ||
            !g_voice_agent_callbacks.turn_phase_method) {
            LOGe("racVoiceAgentSetCallbacks: turnPhaseCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.turn_phase_callback);
            g_voice_agent_callbacks.turn_phase_callback = nullptr;
        }
        }
    }

    if (partialTranscriptionCallback != nullptr) {
        g_voice_agent_callbacks.partial_transcription_callback =
            env->NewGlobalRef(partialTranscriptionCallback);
        jclass callbackClass = env->GetObjectClass(partialTranscriptionCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(partialTranscriptionCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get partial transcription callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.partial_transcription_callback);
            g_voice_agent_callbacks.partial_transcription_callback = nullptr;
        } else {
        g_voice_agent_callbacks.partial_transcription_method =
            env->GetMethodID(callbackClass, "partialTranscriptionCallback",
                             "(Ljava/lang/String;)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(partialTranscriptionCallback)") ||
            !g_voice_agent_callbacks.partial_transcription_method) {
            LOGe("racVoiceAgentSetCallbacks: partialTranscriptionCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.partial_transcription_callback);
            g_voice_agent_callbacks.partial_transcription_callback = nullptr;
        }
        }
    }

    if (responseTokenCallback != nullptr) {
        g_voice_agent_callbacks.response_token_callback = env->NewGlobalRef(responseTokenCallback);
        jclass callbackClass = env->GetObjectClass(responseTokenCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(responseTokenCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get response token callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.response_token_callback);
            g_voice_agent_callbacks.response_token_callback = nullptr;
        } else {
        g_voice_agent_callbacks.response_token_method =
            env->GetMethodID(callbackClass, "responseTokenCallback", "(Ljava/lang/String;Z)Z");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(responseTokenCallback)") ||
            !g_voice_agent_callbacks.response_token_method) {
            LOGe("racVoiceAgentSetCallbacks: responseTokenCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.response_token_callback);
            g_voice_agent_callbacks.response_token_callback = nullptr;
        }
        }
    }

    if (audioChunkCallback != nullptr) {
        g_voice_agent_callbacks.audio_chunk_callback = env->NewGlobalRef(audioChunkCallback);
        jclass callbackClass = env->GetObjectClass(audioChunkCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(audioChunkCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get audio chunk callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.audio_chunk_callback);
            g_voice_agent_callbacks.audio_chunk_callback = nullptr;
        } else {
        g_voice_agent_callbacks.audio_chunk_method =
            env->GetMethodID(callbackClass, "audioChunkCallback", "([BZ)Z");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(audioChunkCallback)") ||
            !g_voice_agent_callbacks.audio_chunk_method) {
            LOGe("racVoiceAgentSetCallbacks: audioChunkCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.audio_chunk_callback);
            g_voice_agent_callbacks.audio_chunk_callback = nullptr;
        }
        }
    }

    if (userInterruptCallback != nullptr) {
        g_voice_agent_callbacks.user_interrupt_callback =
            env->NewGlobalRef(userInterruptCallback);
        jclass callbackClass = env->GetObjectClass(userInterruptCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(userInterruptCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get user interrupt callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.user_interrupt_callback);
            g_voice_agent_callbacks.user_interrupt_callback = nullptr;
        } else {
        g_voice_agent_callbacks.user_interrupt_method =
            env->GetMethodID(callbackClass, "userInterruptCallback", "()V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(userInterruptCallback)") ||
            !g_voice_agent_callbacks.user_interrupt_method) {
            LOGe("racVoiceAgentSetCallbacks: userInterruptCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.user_interrupt_callback);
            g_voice_agent_callbacks.user_interrupt_callback = nullptr;
        }
        }
    }

    if (progressCallback != nullptr) {
        g_voice_agent_callbacks.progress_callback = env->NewGlobalRef(progressCallback);
        jclass callbackClass = env->GetObjectClass(progressCallback);
        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetObjectClass(progressCallback)") ||
            callbackClass == nullptr) {
            LOGe("racVoiceAgentSetCallbacks: failed to get progress callback class");
            env->DeleteGlobalRef(g_voice_agent_callbacks.progress_callback);
            g_voice_agent_callbacks.progress_callback = nullptr;
        } else {
        g_voice_agent_callbacks.progress_method =
            env->GetMethodID(callbackClass, "progressCallback", "(F)V");
        env->DeleteLocalRef(callbackClass);

        if (clearPendingException(env, "racVoiceAgentSetCallbacks GetMethodID(progressCallback)") ||
            !g_voice_agent_callbacks.progress_method) {
            LOGe("racVoiceAgentSetCallbacks: progressCallback method not found");
            env->DeleteGlobalRef(g_voice_agent_callbacks.progress_callback);
            g_voice_agent_callbacks.progress_callback = nullptr;
        }
        }
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentProcessStream(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData) {
    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;
    if (audioData == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;

    jsize len = env->GetArrayLength(audioData);
    jbyte* data = env->GetByteArrayElements(audioData, nullptr);

    rac_result_t status = rac_voice_agent_process_stream(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), data, static_cast<size_t>(len),
        voice_agent_event_adapter, nullptr);

    env->ReleaseByteArrayElements(audioData, data, JNI_ABORT);

    return static_cast<jint>(status);
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

    std::string json = "{";
    json += "\"model_id\":\"" + std::string(model->id ? model->id : "") + "\",";
    json += "\"name\":\"" + std::string(model->name ? model->name : "") + "\",";
    json += "\"category\":" + std::to_string(static_cast<int>(model->category)) + ",";
    json += "\"format\":" + std::to_string(static_cast<int>(model->format)) + ",";
    json += "\"framework\":" + std::to_string(static_cast<int>(model->framework)) + ",";
    json += "\"download_url\":" +
            (model->download_url ? ("\"" + std::string(model->download_url) + "\"") : "null") + ",";
    json += "\"local_path\":" +
            (model->local_path ? ("\"" + std::string(model->local_path) + "\"") : "null") + ",";
    json += "\"download_size\":" + std::to_string(model->download_size) + ",";
    json += "\"context_length\":" + std::to_string(model->context_length) + ",";
    json +=
        "\"supports_thinking\":" + std::string(model->supports_thinking ? "true" : "false") + ",";
    json += "\"description\":" +
            (model->description ? ("\"" + std::string(model->description) + "\"") : "null");
    json += "}";

    return json;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistrySave(
    JNIEnv* env, jclass clazz, jstring modelId, jstring name, jint category, jint format,
    jint framework, jstring downloadUrl, jstring localPath, jlong downloadSize, jint contextLength,
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
    std::string json = "[";
    for (size_t i = 0; i < count; i++) {
        if (i > 0) json += ",";

        rac_model_info_t* m = models[i];
        json += "{";
        json += "\"id\":\"" + std::string(m->id ? m->id : "") + "\",";
        json += "\"name\":\"" + std::string(m->name ? m->name : "") + "\",";
        json += "\"category\":" + std::to_string(m->category) + ",";
        json += "\"format\":" + std::to_string(m->format) + ",";
        json += "\"framework\":" + std::to_string(m->framework) + ",";
        json += "\"downloadUrl\":\"" + std::string(m->download_url ? m->download_url : "") + "\",";
        json += "\"downloadSize\":" + std::to_string(m->download_size) + ",";
        json += "\"contextLength\":" + std::to_string(m->context_length) + ",";
        json +=
            "\"supportsThinking\":" + std::string(m->supports_thinking == RAC_TRUE ? "true" : "false");
        json += "}";
    }
    json += "]";

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

// Helper to extract a string value from JSON (simple parser for known keys)
// Returns allocated string that must be stored persistently, or nullptr
static std::string extract_json_string(const char* json, const char* key) {
    if (!json || !key)
        return "";

    std::string search_key = "\"" + std::string(key) + "\":";
    const char* pos = strstr(json, search_key.c_str());
    if (!pos)
        return "";

    pos += search_key.length();
    while (*pos == ' ')
        pos++;

    if (*pos == 'n' && strncmp(pos, "null", 4) == 0) {
        return "";
    }

    if (*pos != '"')
        return "";
    pos++;

    const char* end = strchr(pos, '"');
    if (!end)
        return "";

    return std::string(pos, end - pos);
}

// Helper to extract an integer value from JSON
static int64_t extract_json_int(const char* json, const char* key) {
    if (!json || !key)
        return 0;

    std::string search_key = "\"" + std::string(key) + "\":";
    const char* pos = strstr(json, search_key.c_str());
    if (!pos)
        return 0;

    pos += search_key.length();
    while (*pos == ' ')
        pos++;

    return strtoll(pos, nullptr, 10);
}

// Helper to extract a boolean value from JSON
static bool extract_json_bool(const char* json, const char* key) {
    if (!json || !key)
        return false;

    std::string search_key = "\"" + std::string(key) + "\":";
    const char* pos = strstr(json, search_key.c_str());
    if (!pos)
        return false;

    pos += search_key.length();
    while (*pos == ' ')
        pos++;

    return strncmp(pos, "true", 4) == 0;
}

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
        const char* json = env->GetStringUTFChars(jResult, nullptr);
        LOGd("jni_device_get_info: parsing JSON: %.200s...", json);

        // Parse JSON and extract all fields
        std::lock_guard<std::mutex> lock(g_device_info_strings.mtx);

        // Extract all string fields from Kotlin's getDeviceInfoCallback() JSON
        g_device_info_strings.device_id = extract_json_string(json, "device_id");
        g_device_info_strings.device_model = extract_json_string(json, "device_model");
        g_device_info_strings.device_name = extract_json_string(json, "device_name");
        g_device_info_strings.platform = extract_json_string(json, "platform");
        g_device_info_strings.os_version = extract_json_string(json, "os_version");
        g_device_info_strings.form_factor = extract_json_string(json, "form_factor");
        g_device_info_strings.architecture = extract_json_string(json, "architecture");
        g_device_info_strings.chip_name = extract_json_string(json, "chip_name");
        g_device_info_strings.gpu_family = extract_json_string(json, "gpu_family");
        g_device_info_strings.battery_state = extract_json_string(json, "battery_state");
        g_device_info_strings.device_fingerprint = extract_json_string(json, "device_fingerprint");
        g_device_info_strings.manufacturer = extract_json_string(json, "manufacturer");

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

        // Extract integer fields
        out_info->total_memory = extract_json_int(json, "total_memory");
        out_info->available_memory = extract_json_int(json, "available_memory");
        out_info->neural_engine_cores =
            static_cast<int32_t>(extract_json_int(json, "neural_engine_cores"));
        out_info->core_count = static_cast<int32_t>(extract_json_int(json, "core_count"));
        out_info->performance_cores =
            static_cast<int32_t>(extract_json_int(json, "performance_cores"));
        out_info->efficiency_cores =
            static_cast<int32_t>(extract_json_int(json, "efficiency_cores"));

        // Extract boolean fields
        out_info->has_neural_engine =
            extract_json_bool(json, "has_neural_engine") ? RAC_TRUE : RAC_FALSE;
        out_info->is_low_power_mode =
            extract_json_bool(json, "is_low_power_mode") ? RAC_TRUE : RAC_FALSE;

        // Extract float field for battery
        out_info->battery_level = static_cast<float>(extract_json_int(json, "battery_level"));

        LOGi("jni_device_get_info: parsed device_model=%s, os_version=%s, architecture=%s",
             out_info->device_model ? out_info->device_model : "(null)",
             out_info->os_version ? out_info->os_version : "(null)",
             out_info->architecture ? out_info->architecture : "(null)");

        env->ReleaseStringUTFChars(jResult, json);
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
