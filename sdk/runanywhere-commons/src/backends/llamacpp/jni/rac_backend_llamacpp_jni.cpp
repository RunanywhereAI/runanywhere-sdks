/**
 * LlamaCPP Backend JNI Bridge
 *
 * JNI layer for the LlamaCPP backend. Links against rac_commons for the
 * full service registry and infrastructure support.
 *
 * This JNI library is linked by:
 *   Kotlin: runanywhere-kotlin/modules/runanywhere-core-llamacpp
 *
 * Package: com.runanywhere.sdk.llm.llamacpp
 * Class: LlamaCPPBridge
 */

#include <jni.h>
#include <string>
#include <cstring>

// Include LlamaCPP backend header (direct API)
#include "rac_llm_llamacpp.h"

// Include commons for registration and service lookup
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// Route JNI logging through unified RAC_LOG_* system
static const char* LOG_TAG = "JNI.LlamaCpp";
#define LOGi(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)

// Forward declaration for registration functions
extern "C" rac_result_t rac_backend_llamacpp_register(void);
extern "C" rac_result_t rac_backend_llamacpp_unregister(void);
extern "C" rac_result_t rac_backend_llamacpp_vlm_register(void);
extern "C" rac_result_t rac_backend_llamacpp_vlm_unregister(void);

extern "C" {

// =============================================================================
// JNI_OnLoad - Called when native library is loaded
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    LOGi("JNI_OnLoad: rac_backend_llamacpp_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

/**
 * Register the LlamaCPP backend with the C++ service registry.
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("LlamaCPP nativeRegister called");

    rac_result_t result = rac_backend_llamacpp_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register LlamaCPP backend: %d", result);
        return static_cast<jint>(result);
    }

    LOGi("LlamaCPP backend registered successfully");
    return RAC_SUCCESS;
}

/**
 * Unregister the LlamaCPP backend from the C++ service registry.
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
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
 */
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    // Check by attempting to use the service
    // For now, return true if the native library is loaded
    return JNI_TRUE;
}

/**
 * Get the LlamaCPP library version.
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    (void)clazz;
    return env->NewStringUTF("b7199");
}

// =============================================================================
// VLM Backend Registration
// =============================================================================

/**
 * Register the LlamaCPP VLM backend with the C++ service registry.
 * Mirrors iOS LlamaCPP.registerVLM() pattern.
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeRegisterVlm(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("LlamaCPP nativeRegisterVlm called");

    rac_result_t result = rac_backend_llamacpp_vlm_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register LlamaCPP VLM backend: %d", result);
        return static_cast<jint>(result);
    }

    LOGi("LlamaCPP VLM backend registered successfully");
    return RAC_SUCCESS;
}

/**
 * Unregister the LlamaCPP VLM backend from the C++ service registry.
 */
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeUnregisterVlm(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("LlamaCPP nativeUnregisterVlm called");

    rac_result_t result = rac_backend_llamacpp_vlm_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister LlamaCPP VLM backend: %d", result);
    } else {
        LOGi("LlamaCPP VLM backend unregistered");
    }

    return static_cast<jint>(result);
}

// =============================================================================
// LLM Operations - Direct API calls
// =============================================================================

/**
 * Create a LlamaCPP instance and load a model
 */
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeCreate(
    JNIEnv* env, jclass clazz,
    jstring modelPath, jint contextSize, jint numThreads, jint gpuLayers) {
    (void)clazz;

    const char* path = env->GetStringUTFChars(modelPath, nullptr);
    if (!path) {
        LOGe("nativeCreate: Failed to get model path");
        return 0;
    }

    LOGi("nativeCreate: model=%s, ctx=%d, threads=%d, gpu=%d", path, contextSize, numThreads, gpuLayers);

    rac_llm_llamacpp_config_t config = RAC_LLM_LLAMACPP_CONFIG_DEFAULT;
    config.context_size = contextSize;
    config.num_threads = numThreads;
    config.gpu_layers = gpuLayers;

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_llm_llamacpp_create(path, &config, &handle);

    env->ReleaseStringUTFChars(modelPath, path);

    if (result != RAC_SUCCESS) {
        LOGe("nativeCreate: Failed with result %d", result);
        return 0;
    }

    LOGi("nativeCreate: Success, handle=%p", handle);
    return reinterpret_cast<jlong>(handle);
}

/**
 * Destroy a LlamaCPP instance
 */
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeDestroy(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;

    if (handle == 0) return;

    LOGi("nativeDestroy: handle=%p", reinterpret_cast<void*>(handle));
    rac_llm_llamacpp_destroy(reinterpret_cast<rac_handle_t>(handle));
}

/**
 * Generate text (blocking)
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeGenerate(
    JNIEnv* env, jclass clazz,
    jlong handle, jstring prompt, jint maxTokens, jfloat temperature) {
    (void)clazz;

    if (handle == 0) {
        LOGe("nativeGenerate: Invalid handle");
        return nullptr;
    }

    const char* promptStr = env->GetStringUTFChars(prompt, nullptr);
    if (!promptStr) {
        LOGe("nativeGenerate: Failed to get prompt");
        return nullptr;
    }

    LOGi("nativeGenerate: prompt_len=%zu, max_tokens=%d, temp=%.2f",
         strlen(promptStr), maxTokens, temperature);

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.max_tokens = maxTokens;
    options.temperature = temperature;

    rac_llm_result_t result = {};
    rac_result_t status = rac_llm_llamacpp_generate(
        reinterpret_cast<rac_handle_t>(handle),
        promptStr, &options, &result);

    env->ReleaseStringUTFChars(prompt, promptStr);

    if (status != RAC_SUCCESS) {
        LOGe("nativeGenerate: Failed with status %d", status);
        return nullptr;
    }

    jstring output = nullptr;
    if (result.text) {
        output = env->NewStringUTF(result.text);
        LOGi("nativeGenerate: Success, output_len=%zu", strlen(result.text));
        // Free the allocated text
        free((void*)result.text);
    }

    return output;
}

/**
 * Cancel ongoing generation
 */
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeCancel(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;

    if (handle == 0) return;

    LOGi("nativeCancel: handle=%p", reinterpret_cast<void*>(handle));
    rac_llm_llamacpp_cancel(reinterpret_cast<rac_handle_t>(handle));
}

/**
 * Get model info as JSON
 */
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCPPBridge_nativeGetModelInfo(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;

    if (handle == 0) return nullptr;

    char* json = nullptr;
    rac_result_t status = rac_llm_llamacpp_get_model_info(
        reinterpret_cast<rac_handle_t>(handle), &json);

    if (status != RAC_SUCCESS || !json) {
        return nullptr;
    }

    jstring result = env->NewStringUTF(json);
    free(json);

    return result;
}

} // extern "C"
