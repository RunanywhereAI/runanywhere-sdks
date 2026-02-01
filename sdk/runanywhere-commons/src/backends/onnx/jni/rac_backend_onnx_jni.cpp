/**
 * @file rac_backend_onnx_jni.cpp
 * @brief RunAnywhere Core - ONNX Backend JNI Bridge
 *
 * Self-contained JNI layer for the ONNX backend.
 *
 * Package: com.runanywhere.sdk.core.onnx
 * Class: ONNXBridge
 */

#include <jni.h>
#include <string>
#include <cstring>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RACOnnxJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGi(...) fprintf(stdout, "[INFO] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGe(...) fprintf(stderr, "[ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGw(...) fprintf(stdout, "[WARN] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

// NPU/QNN support - DISABLED FOR NNAPI TESTING
// QNN headers cause linker errors when QNN is not compiled
// #include "rac/backends/rac_qnn_config.h"
// #include "rac/backends/rac_onnx_npu.h"

// Forward declaration
extern "C" rac_result_t rac_backend_onnx_register(void);
extern "C" rac_result_t rac_backend_onnx_unregister(void);

// Kokoro benchmark API
extern "C" rac_result_t rac_tts_kokoro_run_benchmark(void* handle, const char* test_text,
                                                     char* out_json, size_t json_size);
extern "C" rac_bool_t rac_tts_is_kokoro(void* handle);
extern "C" rac_bool_t rac_tts_kokoro_is_npu_active(void* handle);
extern "C" rac_result_t rac_tts_kokoro_run_standalone_benchmark(const char* model_path,
                                                                 const char* test_text,
                                                                 char* out_json, size_t json_size);

extern "C" {

// =============================================================================
// JNI_OnLoad
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    LOGi("JNI_OnLoad: rac_backend_onnx_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("ONNX nativeRegister called");

    rac_result_t result = rac_backend_onnx_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register ONNX backend: %d", result);
        return static_cast<jint>(result);
    }

    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);
    LOGi("After ONNX registration - STT providers: count=%zu, result=%d", provider_count, list_result);

    // Also check TTS providers
    const char** tts_provider_names = nullptr;
    size_t tts_provider_count = 0;
    rac_result_t tts_list_result = rac_service_list_providers(RAC_CAPABILITY_TTS, &tts_provider_names, &tts_provider_count);
    LOGi("After ONNX registration - TTS providers: count=%zu, result=%d", tts_provider_count, tts_list_result);

    LOGi("ONNX backend registered successfully (STT + TTS + VAD)");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("ONNX nativeUnregister called");

    rac_result_t result = rac_backend_onnx_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister ONNX backend: %d", result);
    } else {
        LOGi("ONNX backend unregistered");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    const char** provider_names = nullptr;
    size_t provider_count = 0;

    rac_result_t result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);

    if (result == RAC_SUCCESS && provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            if (provider_names[i] && strstr(provider_names[i], "ONNX") != nullptr) {
                return JNI_TRUE;
            }
        }
    }

    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    (void)clazz;
    return env->NewStringUTF("1.0.0");
}

// =============================================================================
// NPU Detection APIs
// =============================================================================

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeIsNPUAvailable(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    // QNN DISABLED FOR NNAPI TESTING - always return false
    // #if RAC_QNN_AVAILABLE
    //     rac_bool_t available = rac_qnn_is_available();
    //     LOGi("NPU available: %s", available ? "true" : "false");
    //     return available ? JNI_TRUE : JNI_FALSE;
    // #else
    LOGi("NPU not available (QNN disabled for NNAPI testing)");
    return JNI_FALSE;
    // #endif
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetNPUInfo(JNIEnv* env, jclass clazz) {
    (void)clazz;
    // QNN DISABLED FOR NNAPI TESTING - always return disabled message
    // #if RAC_QNN_AVAILABLE
    //     char json_buffer[1024] = {0};
    //     rac_result_t result = rac_qnn_get_soc_info_json(json_buffer, sizeof(json_buffer));
    //     if (result == RAC_SUCCESS) {
    //         LOGi("NPU info: %s", json_buffer);
    //         return env->NewStringUTF(json_buffer);
    //     } else {
    //         LOGw("Failed to get NPU info: %d", result);
    //         return env->NewStringUTF("{\"error\":\"Failed to get NPU info\"}");
    //     }
    // #else
    return env->NewStringUTF("{\"htp_available\":false,\"name\":\"QNN disabled for NNAPI testing\"}");
    // #endif
}

// =============================================================================
// NPU TTS Hybrid Execution APIs
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeCreateTTSHybrid(
    JNIEnv* env, jclass clazz,
    jstring encoderPath, jstring vocoderPath,
    jint perfMode, jint vtcmMb, jboolean enableContextCache) {
    (void)clazz;
    // QNN DISABLED FOR NNAPI TESTING - entire hybrid TTS creation disabled
    // All parameters are unused
    (void)env;
    (void)encoderPath;
    (void)vocoderPath;
    (void)perfMode;
    (void)vtcmMb;
    (void)enableContextCache;
    LOGe("Hybrid TTS not available (QNN disabled for NNAPI testing)");
    return 0;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetNPUStats(JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    (void)handle;
    // QNN DISABLED FOR NNAPI TESTING - always return inactive stats
    return env->NewStringUTF("{\"is_npu_active\":false,\"reason\":\"QNN disabled for NNAPI testing\"}");
}

// =============================================================================
// Model Validation APIs
// =============================================================================

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeValidateModelForNPU(JNIEnv* env, jclass clazz, jstring modelPath) {
    (void)clazz;
    (void)modelPath;
    // QNN DISABLED FOR NNAPI TESTING - always return not ready
    return env->NewStringUTF("{\"is_npu_ready\":false,\"recommendation\":\"QNN disabled for NNAPI testing\"}");
}

// =============================================================================
// Kokoro NPU Benchmark APIs
// =============================================================================

/**
 * Run NPU vs CPU benchmark on Kokoro TTS model.
 *
 * @param handle TTS handle (must be Kokoro model)
 * @param testText Optional test text (null for default)
 * @return JSON string with benchmark results
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRunKokoroBenchmark(
    JNIEnv* env, jclass clazz, jlong handle, jstring testText) {
    (void)clazz;

    LOGi("nativeRunKokoroBenchmark called with handle=%lld", (long long)handle);

    if (handle == 0) {
        LOGe("Invalid handle (0)");
        return env->NewStringUTF("{\"success\":false,\"error\":\"Invalid handle\"}");
    }

    // Get test text if provided
    const char* text_cstr = nullptr;
    if (testText != nullptr) {
        text_cstr = env->GetStringUTFChars(testText, nullptr);
    }

    // Allocate buffer for JSON result
    char json_buffer[2048] = {0};

    // Run benchmark
    rac_result_t result = rac_tts_kokoro_run_benchmark(
        reinterpret_cast<void*>(handle),
        text_cstr,
        json_buffer,
        sizeof(json_buffer)
    );

    // Release text string
    if (text_cstr != nullptr) {
        env->ReleaseStringUTFChars(testText, text_cstr);
    }

    if (result != RAC_SUCCESS) {
        LOGw("Benchmark returned non-success: %d", result);
    } else {
        LOGi("Benchmark completed successfully");
    }

    return env->NewStringUTF(json_buffer);
}

/**
 * Check if a TTS handle is a Kokoro model.
 *
 * @param handle TTS handle
 * @return true if Kokoro model
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeIsKokoroTTS(JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;

    if (handle == 0) {
        return JNI_FALSE;
    }

    rac_bool_t is_kokoro = rac_tts_is_kokoro(reinterpret_cast<void*>(handle));
    return is_kokoro ? JNI_TRUE : JNI_FALSE;
}

/**
 * Check if NNAPI NPU is active for Kokoro TTS.
 *
 * @param handle TTS handle (must be Kokoro)
 * @return true if NPU is active
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeIsKokoroNPUActive(JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;

    if (handle == 0) {
        return JNI_FALSE;
    }

    rac_bool_t is_active = rac_tts_kokoro_is_npu_active(reinterpret_cast<void*>(handle));
    LOGi("Kokoro NPU active: %s", is_active ? "true" : "false");
    return is_active ? JNI_TRUE : JNI_FALSE;
}

/**
 * Run standalone Kokoro NPU vs CPU benchmark.
 *
 * This creates a temporary Kokoro TTS loader, runs the benchmark, and cleans up.
 * Does NOT require an existing TTS handle - useful for testing before model is loaded
 * in the main app.
 *
 * @param modelPath Path to Kokoro model directory
 * @param testText Optional test text (null for default)
 * @return JSON string with benchmark results
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRunStandaloneKokoroBenchmark(
    JNIEnv* env, jclass clazz, jstring modelPath, jstring testText) {
    (void)clazz;

    LOGi("╔═══════════════════════════════════════════════════════════════╗");
    LOGi("║  JNI: STANDALONE KOKORO NPU BENCHMARK                         ║");
    LOGi("╚═══════════════════════════════════════════════════════════════╝");

    if (modelPath == nullptr) {
        LOGe("Model path is null");
        return env->NewStringUTF("{\"success\":false,\"error\":\"Model path is null\"}");
    }

    // Get model path
    const char* model_path_cstr = env->GetStringUTFChars(modelPath, nullptr);
    if (model_path_cstr == nullptr) {
        LOGe("Failed to get model path string");
        return env->NewStringUTF("{\"success\":false,\"error\":\"Failed to get model path\"}");
    }

    LOGi("Model path: %s", model_path_cstr);

    // Get test text if provided
    const char* text_cstr = nullptr;
    if (testText != nullptr) {
        text_cstr = env->GetStringUTFChars(testText, nullptr);
        LOGi("Test text: %s", text_cstr ? text_cstr : "(null)");
    }

    // Allocate buffer for JSON result
    char json_buffer[4096] = {0};

    // Run standalone benchmark
    LOGi("Calling rac_tts_kokoro_run_standalone_benchmark...");
    rac_result_t result = rac_tts_kokoro_run_standalone_benchmark(
        model_path_cstr,
        text_cstr,
        json_buffer,
        sizeof(json_buffer)
    );

    // Release strings
    env->ReleaseStringUTFChars(modelPath, model_path_cstr);
    if (text_cstr != nullptr) {
        env->ReleaseStringUTFChars(testText, text_cstr);
    }

    if (result != RAC_SUCCESS) {
        LOGw("Benchmark returned non-success: %d", result);
    } else {
        LOGi("Benchmark completed successfully");
    }

    LOGi("Returning JSON: %.100s...", json_buffer);
    return env->NewStringUTF(json_buffer);
}

}  // extern "C"
