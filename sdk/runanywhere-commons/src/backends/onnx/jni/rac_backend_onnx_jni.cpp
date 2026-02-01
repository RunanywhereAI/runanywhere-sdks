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

// Forward declaration
extern "C" rac_result_t rac_backend_onnx_register(void);
extern "C" rac_result_t rac_backend_onnx_unregister(void);

extern "C" {

// =============================================================================
// JNI_OnLoad
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    LOGi("JNI_OnLoad: rac_backend_onnx_jni loaded - AUTO-REGISTERING NOW!");
    
    // Auto-register the ONNX backend immediately when library is loaded
    rac_result_t result = rac_backend_onnx_register();
    LOGi("JNI_OnLoad: rac_backend_onnx_register() returned: %d", result);
    
    if (result == RAC_SUCCESS || result == RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGi("JNI_OnLoad: ONNX backend auto-registered successfully!");
    } else {
        LOGe("JNI_OnLoad: ONNX backend auto-registration FAILED: %d", result);
    }
    
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("=== ONNX nativeRegister START ===");

    rac_result_t result = rac_backend_onnx_register();
    LOGi("rac_backend_onnx_register() returned: %d", result);

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register ONNX backend: %d", result);
        return static_cast<jint>(result);
    }

    // List STT providers
    const char** stt_provider_names = nullptr;
    size_t stt_provider_count = 0;
    rac_result_t stt_list_result = rac_service_list_providers(RAC_CAPABILITY_STT, &stt_provider_names, &stt_provider_count);
    LOGi("STT providers after registration: count=%zu, result=%d", stt_provider_count, stt_list_result);
    for (size_t i = 0; i < stt_provider_count; i++) {
        LOGi("  STT provider[%zu]: %s", i, stt_provider_names[i]);
    }

    // List TTS providers
    const char** tts_provider_names = nullptr;
    size_t tts_provider_count = 0;
    rac_result_t tts_list_result = rac_service_list_providers(RAC_CAPABILITY_TTS, &tts_provider_names, &tts_provider_count);
    LOGi("TTS providers after registration: count=%zu, result=%d", tts_provider_count, tts_list_result);
    for (size_t i = 0; i < tts_provider_count; i++) {
        LOGi("  TTS provider[%zu]: %s", i, tts_provider_names[i]);
    }

    LOGi("=== ONNX nativeRegister END (success) ===");
    return RAC_SUCCESS;
}

// Get TTS provider count - for debugging
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetTTSProviderCount(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    const char** tts_provider_names = nullptr;
    size_t tts_provider_count = 0;
    rac_service_list_providers(RAC_CAPABILITY_TTS, &tts_provider_names, &tts_provider_count);
    LOGi("nativeGetTTSProviderCount: %zu", tts_provider_count);
    return static_cast<jint>(tts_provider_count);
}

// Get the last TTS creation error code
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetLastTTSError(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_backend_onnx_get_last_tts_error());
}

// Get the last TTS creation error details
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetLastTTSErrorDetails(JNIEnv* env, jclass clazz) {
    (void)clazz;
    const char* details = rac_backend_onnx_get_last_tts_error_details();
    return env->NewStringUTF(details ? details : "");
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

}  // extern "C"
