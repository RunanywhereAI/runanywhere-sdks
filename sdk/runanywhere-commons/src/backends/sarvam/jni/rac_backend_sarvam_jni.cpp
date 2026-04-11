/**
 * @file rac_backend_sarvam_jni.cpp
 * @brief Sarvam AI Backend JNI Bridge
 *
 * Package: com.runanywhere.sdk.cloud.sarvam
 * Class: SarvamBridge
 */

#include <jni.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_TAG = "JNI.Sarvam";
#define LOGi(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

extern "C" rac_result_t rac_backend_sarvam_register(void);
extern "C" rac_result_t rac_backend_sarvam_unregister(void);
extern "C" rac_result_t rac_stt_sarvam_set_api_key(const char* api_key);
extern "C" const char* rac_stt_sarvam_get_api_key(void);

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_cloud_sarvam_SarvamBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("Sarvam nativeRegister called");

    rac_result_t result = rac_backend_sarvam_register();
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register Sarvam backend: %d", result);
        return static_cast<jint>(result);
    }

    LOGi("Sarvam backend registered (STT)");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_cloud_sarvam_SarvamBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    rac_result_t result = rac_backend_sarvam_unregister();
    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister Sarvam backend: %d", result);
    }
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_cloud_sarvam_SarvamBridge_nativeSetApiKey(JNIEnv* env, jclass clazz,
                                                                   jstring apiKey) {
    (void)clazz;
    if (!apiKey) {
        LOGe("nativeSetApiKey: null API key");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* key = env->GetStringUTFChars(apiKey, nullptr);
    if (!key) return RAC_ERROR_OUT_OF_MEMORY;

    rac_result_t result = rac_stt_sarvam_set_api_key(key);
    env->ReleaseStringUTFChars(apiKey, key);

    if (result == RAC_SUCCESS) {
        LOGi("Sarvam API key configured");
    }
    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_cloud_sarvam_SarvamBridge_nativeHasApiKey(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    return rac_stt_sarvam_get_api_key() != nullptr ? JNI_TRUE : JNI_FALSE;
}

}  // extern "C"
