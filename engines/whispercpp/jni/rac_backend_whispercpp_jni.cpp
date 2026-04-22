/**
 * @file rac_backend_whispercpp_jni.cpp
 * @brief RunAnywhere Core - WhisperCPP Backend JNI Bridge
 *
 * Self-contained JNI layer for the WhisperCPP backend.
 *
 * Package: com.runanywhere.sdk.core.whispercpp
 * Class: WhisperCPPBridge
 */

#include "rac_stt_whispercpp.h"

#include <jni.h>

#include <cstring>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

// Route JNI logging through unified RAC_LOG_* system
static const char* LOG_TAG = "JNI.WhisperCpp";
#define LOGi(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)

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

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeRegister(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("WhisperCPP nativeRegister called");

    rac_result_t result = rac_backend_whispercpp_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register WhisperCPP backend: %d", result);
        return static_cast<jint>(result);
    }

    // v3 Phase B9: list TRANSCRIBE plugins for debug visibility.
    {
        const rac_engine_vtable_t* plugins[16] = {};
        size_t plugin_count = 0;
        rac_result_t list_result =
            rac_plugin_list(RAC_PRIMITIVE_TRANSCRIBE, plugins, 16, &plugin_count);
        LOGi("After WhisperCPP registration - TRANSCRIBE plugins: count=%zu, result=%d",
             plugin_count, list_result);
    }

    LOGi("WhisperCPP backend registered successfully (STT)");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeUnregister(
    JNIEnv* env, jclass clazz) {
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
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeIsRegistered(JNIEnv* env,
                                                                             jclass clazz) {
    (void)env;
    (void)clazz;

    // v3 Phase B9: check plugin registry for a plugin named "whispercpp".
    const rac_engine_vtable_t* plugins[16] = {};
    size_t plugin_count = 0;
    rac_result_t result =
        rac_plugin_list(RAC_PRIMITIVE_TRANSCRIBE, plugins, 16, &plugin_count);
    if (result == RAC_SUCCESS) {
        for (size_t i = 0; i < plugin_count; ++i) {
            if (plugins[i] && plugins[i]->metadata.name &&
                strcmp(plugins[i]->metadata.name, "whispercpp") == 0) {
                return JNI_TRUE;
            }
        }
    }
    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_core_whispercpp_WhisperCPPBridge_nativeGetVersion(JNIEnv* env,
                                                                           jclass clazz) {
    (void)clazz;
    return env->NewStringUTF("1.0.0");
}

}  // extern "C"
