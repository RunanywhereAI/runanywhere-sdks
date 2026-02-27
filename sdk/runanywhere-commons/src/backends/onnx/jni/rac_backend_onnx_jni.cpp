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

#include "rac_stt_onnx.h"
#include "rac_tts_onnx.h"
#include "rac_vad_onnx.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// Route JNI logging through unified RAC_LOG_* system
static const char* LOG_TAG = "JNI.ONNX";
#define LOGi(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)

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

}  // extern "C"
