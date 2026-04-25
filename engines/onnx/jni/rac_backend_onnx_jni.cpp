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

#include <cstring>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

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

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_core_onnx_ONNXBridge_nativeRegister(JNIEnv* env,
                                                                                    jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("ONNX nativeRegister called");

    rac_result_t result = rac_backend_onnx_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register ONNX backend: %d", result);
        return static_cast<jint>(result);
    }

    // v3 Phase B9: list EMBED plugins for debug visibility.
    {
        const rac_engine_vtable_t* plugins[16] = {};
        size_t plugin_count = 0;
        rac_result_t list_result =
            rac_plugin_list(RAC_PRIMITIVE_EMBED, plugins, 16, &plugin_count);
        LOGi("After ONNX registration - EMBED plugins: count=%zu, result=%d", plugin_count,
             list_result);
    }

    LOGi("ONNX backend registered successfully (generic ONNX services)");
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

    // v3 Phase B9: check plugin registry for a plugin named "onnx".
    const rac_engine_vtable_t* plugins[16] = {};
    size_t plugin_count = 0;
    rac_result_t result =
        rac_plugin_list(RAC_PRIMITIVE_EMBED, plugins, 16, &plugin_count);
    if (result == RAC_SUCCESS) {
        for (size_t i = 0; i < plugin_count; ++i) {
            if (plugins[i] && plugins[i]->metadata.name &&
                strcmp(plugins[i]->metadata.name, "onnx") == 0) {
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
