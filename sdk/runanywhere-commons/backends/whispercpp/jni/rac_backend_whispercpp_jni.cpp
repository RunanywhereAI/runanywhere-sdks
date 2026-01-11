/**
 * @file rac_backend_whispercpp_jni.cpp
 * @brief RunAnywhere Core - WhisperCPP Backend JNI Bridge
 *
 * Self-contained JNI layer for the WhisperCPP backend.
 *
 * Package: com.runanywhere.sdk.core.whispercpp
 * Class: WhisperCPPBridge
 */

#include <jni.h>
#include <string>
#include <cstring>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RACWhisperCPPJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGi(...) fprintf(stdout, "[INFO] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGe(...) fprintf(stderr, "[ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGw(...) fprintf(stdout, "[WARN] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

#include "rac_stt_whispercpp.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

extern "C" {

// =============================================================================
// JNI_OnLoad
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    LOGi("JNI_OnLoad: rac_backend_whispercpp_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("WhisperCPP nativeRegister called");

    rac_result_t result = rac_backend_whispercpp_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register WhisperCPP backend: %d", result);
        return static_cast<jint>(result);
    }

    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);
    LOGi("After WhisperCPP registration - STT providers: count=%zu, result=%d", provider_count, list_result);

    LOGi("WhisperCPP backend registered successfully (STT)");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("WhisperCPP nativeUnregister called");

    rac_result_t result = rac_backend_whispercpp_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister WhisperCPP backend: %d", result);
    } else {
        LOGi("WhisperCPP backend unregistered");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    const char** provider_names = nullptr;
    size_t provider_count = 0;

    rac_result_t result = rac_service_list_providers(RAC_CAPABILITY_STT, &provider_names, &provider_count);

    if (result == RAC_SUCCESS && provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            if (provider_names[i] && strstr(provider_names[i], "WhisperCPP") != nullptr) {
                return JNI_TRUE;
            }
        }
    }

    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    (void)clazz;
    return env->NewStringUTF("1.0.0");
}

}  // extern "C"

