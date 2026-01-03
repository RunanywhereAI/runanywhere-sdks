/**
 * LlamaCPP Backend JNI Bridge
 *
 * Self-contained JNI layer for the LlamaCPP backend.
 * This mirrors the Swift LlamaCPPBackend XCFramework architecture.
 *
 * This JNI library is linked by:
 *   Kotlin: runanywhere-kotlin/modules/runanywhere-core-llamacpp
 *
 * Package: com.runanywhere.sdk.native.bridge
 * Class: LlamaCPPBridge
 */

#include <jni.h>
#include <string>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RACLlamaCPPJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGi(...) fprintf(stdout, "[INFO] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGe(...) fprintf(stderr, "[ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGw(...) fprintf(stdout, "[WARN] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

// Include LlamaCPP backend header
#include "rac_llm_llamacpp.h"

// Include commons for API (debugging provider list)
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"

extern "C" {

// =============================================================================
// JNI_OnLoad - Called when native library is loaded
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnLoad: rac_backend_llamacpp_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

/**
 * Register the LlamaCPP backend with the C++ service registry.
 *
 * This calls rac_backend_llamacpp_register() which registers the LlamaCPP
 * LLM service provider with the C++ commons service registry.
 *
 * @return RAC_SUCCESS (0) on success, error code on failure
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    LOGi("LlamaCPP nativeRegister called");

    rac_result_t result = rac_backend_llamacpp_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register LlamaCPP backend: %d", result);
        return static_cast<jint>(result);
    }

    // Debug: List registered providers
    const char** provider_names = nullptr;
    size_t provider_count = 0;
    rac_result_t list_result = rac_service_list_providers(RAC_CAPABILITY_TEXT_GENERATION, &provider_names, &provider_count);
    LOGi("After LlamaCPP registration - TEXT_GENERATION providers: count=%zu, result=%d", provider_count, list_result);
    if (provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            LOGi("  Provider[%zu]: %s", i, provider_names[i] ? provider_names[i] : "NULL");
        }
    }

    LOGi("LlamaCPP backend registered successfully");
    return RAC_SUCCESS;
}

/**
 * Unregister the LlamaCPP backend from the C++ service registry.
 *
 * @return RAC_SUCCESS (0) on success, error code on failure
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    LOGi("LlamaCPP nativeUnregister called");

    rac_result_t result = rac_backend_llamacpp_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister LlamaCPP backend: %d", result);
    } else {
        LOGi("LlamaCPP backend unregistered");
    }

    return static_cast<jint>(result);
}

/**
 * Check if the LlamaCPP backend is registered.
 *
 * @return true if registered, false otherwise
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    // Check if LlamaCPP provider is registered by listing providers
    const char** provider_names = nullptr;
    size_t provider_count = 0;

    rac_result_t result = rac_service_list_providers(RAC_CAPABILITY_TEXT_GENERATION, &provider_names, &provider_count);

    if (result == RAC_SUCCESS && provider_names && provider_count > 0) {
        for (size_t i = 0; i < provider_count; i++) {
            if (provider_names[i] && strstr(provider_names[i], "llamacpp") != nullptr) {
                return JNI_TRUE;
            }
        }
    }

    return JNI_FALSE;
}

/**
 * Get the LlamaCPP library version.
 *
 * @return Version string
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    // Return the version from the backend if available
    // For now, return a placeholder
    return env->NewStringUTF("b7199");
}

} // extern "C"
