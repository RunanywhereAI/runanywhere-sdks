/**
 * ONNX Backend JNI Bridge
 *
 * Self-contained JNI layer for the ONNX backend.
 * This mirrors the Swift ONNXBackend XCFramework architecture.
 *
 * This JNI library is linked by:
 *   Kotlin: runanywhere-kotlin/modules/runanywhere-core-onnx
 *
 * Package: com.runanywhere.sdk.native.bridge
 * Class: ONNXBridge
 */

#include <jni.h>
#include <string>

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

// Include ONNX backend headers
#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

// Include commons for API (debugging provider list)
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

extern "C" {

// =============================================================================
// JNI_OnLoad - Called when native library is loaded
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnLoad: rac_backend_onnx_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

/**
 * Register the ONNX backend with the C++ service registry.
 *
 * This calls rac_backend_onnx_register() which registers all ONNX
 * service providers (STT, TTS, VAD) with the C++ commons service registry.
 *
 * @return RAC_SUCCESS (0) on success, error code on failure
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    LOGi("ONNX nativeRegister called");

    rac_result_t result = rac_backend_onnx_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register ONNX backend: %d", result);
        return static_cast<jint>(result);
    }

    // Debug: List registered providers for STT capability
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);
    LOGi("After ONNX registration - SPEECH_TO_TEXT providers: count=%zu, result=%d", provider_count, list_result);

    LOGi("ONNX backend registered successfully (STT + TTS + VAD)");
    return RAC_SUCCESS;
}

/**
 * Unregister the ONNX backend from the C++ service registry.
 *
 * @return RAC_SUCCESS (0) on success, error code on failure
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    LOGi("ONNX nativeUnregister called");

    rac_result_t result = rac_backend_onnx_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister ONNX backend: %d", result);
    } else {
        LOGi("ONNX backend unregistered");
    }

    return static_cast<jint>(result);
}

/**
 * Check if the ONNX backend is registered.
 *
 * @return true if registered, false otherwise
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    // Check if ONNX provider is registered by listing providers
    const char** provider_names = nullptr;
    size_t provider_count = 0;

    rac_result_t result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);

    if (result == RAC_SUCCESS && provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            if (provider_names[i] && strstr(provider_names[i], "onnx") != nullptr) {
                return JNI_TRUE;
            }
        }
    }

    return JNI_FALSE;
}

/**
 * Get the ONNX Runtime library version.
 *
 * @return Version string
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    // Return the version from ONNX Runtime if available
    // For now, return a placeholder
    return env->NewStringUTF("1.23.2");
}

} // extern "C"
