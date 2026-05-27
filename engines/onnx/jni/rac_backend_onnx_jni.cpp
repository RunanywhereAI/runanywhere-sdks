/**
 * @file rac_backend_onnx_jni.cpp
 * @brief RunAnywhere Core - ONNX Backend JNI Bridge
 *
 * Self-contained JNI layer for the ONNX backend.
 *
 * Package: com.runanywhere.sdk.core.onnx
 * Class: ONNXBridge
 */

#include <dlfcn.h>
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

    // ENG-SHERPA-03: opportunistically call rac_backend_sherpa_register() when
    // librac_backend_sherpa.so is present in-process. On Android, libraries
    // loaded by System.loadLibrary from a non-bootclassloader live in a
    // per-class-loader linker namespace, so `dlsym(RTLD_DEFAULT, …)` cannot
    // see symbols in `librac_backend_sherpa.so` even though Kotlin's
    // ONNXBridge already System.loadLibrary'd it. Fix: dlopen the .so by
    // name explicitly, which returns a handle into the current namespace,
    // then dlsym from that handle. Static hosts (RAC_STATIC_PLUGINS=ON) still
    // go through RAC_STATIC_PLUGIN_REGISTER from rac_static_register_sherpa.cpp.
    using rac_backend_sherpa_register_fn = rac_result_t (*)(void);
    void* sherpa_handle = dlopen("librac_backend_sherpa.so", RTLD_NOW | RTLD_GLOBAL);
    if (sherpa_handle == nullptr) {
        // Fall back to RTLD_DEFAULT in case the .so is already global (iOS / WASM).
        // Cache dlerror() once: POSIX semantics clear the per-thread error after
        // the first read, so calling it twice (once for the test, once for the
        // value) would always log "no error" on a real failure.
        const char* err = dlerror();
        LOGw(
            "dlopen(librac_backend_sherpa.so) failed (%s); falling back to "
            "RTLD_DEFAULT",
            err ? err : "no error");
    }
    auto* sherpa_register = reinterpret_cast<rac_backend_sherpa_register_fn>(
        sherpa_handle != nullptr ? dlsym(sherpa_handle, "rac_backend_sherpa_register")
                                 : dlsym(RTLD_DEFAULT, "rac_backend_sherpa_register"));
    if (sherpa_register != nullptr) {
        rac_result_t sherpa_rc = sherpa_register();
        if (sherpa_rc != RAC_SUCCESS && sherpa_rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            LOGw("rac_backend_sherpa_register returned %d", sherpa_rc);
        } else {
            LOGi("Sherpa backend registered via explicit dlsym call");
        }
    } else {
        LOGi(
            "rac_backend_sherpa_register symbol not present; Sherpa backend "
            "unavailable");
    }

    // v3 Phase B9: list EMBED plugins for debug visibility.
    {
        const rac_engine_vtable_t* plugins[16] = {};
        size_t plugin_count = 0;
        rac_result_t list_result = rac_plugin_list(RAC_PRIMITIVE_EMBED, plugins, 16, &plugin_count);
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
    rac_result_t result = rac_plugin_list(RAC_PRIMITIVE_EMBED, plugins, 16, &plugin_count);
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
#ifdef RAC_ONNXRUNTIME_VERSION
    return env->NewStringUTF(RAC_ONNXRUNTIME_VERSION);
#else
    return env->NewStringUTF("unknown");
#endif
}

}  // extern "C"
