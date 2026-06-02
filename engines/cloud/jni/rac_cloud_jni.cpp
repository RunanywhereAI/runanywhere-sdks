/**
 * @file rac_cloud_jni.cpp
 * @brief JNI bridge for the generic cloud backend.
 *
 * Two responsibilities:
 *   1. PLUGIN REGISTRATION (the standard engine bridge): the
 *      RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD macro emits
 *      nativeRegister/nativeUnregister/nativeIsRegistered/nativeGetVersion, so
 *      Kotlin's CloudBridge can register the "cloud" engine PLUGIN with the
 *      registry (routable via
 *      rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, …, hint="cloud")) — like
 *      onnx / llamacpp, except WITHOUT its own JNI_OnLoad: this TU folds into
 *      runanywhere_commons_jni, which already provides JNI_OnLoad (see the
 *      bridge invocation below for why).
 *   2. The bespoke STT-modality FACTORY thunks (racSttCloudCreate /
 *      *CreateFromJson / *Destroy): Kotlin obtains an opaque `rac_stt_service_t*`
 *      (passed across JNI as a `jlong`) which it hands to whatever STT facade
 *      consumes the engine. The provider is selected through the JSON config
 *      (`{"provider":"sarvam"}`); the bare create() defaults to sarvam. These
 *      `racSttCloud*` thunks keep their STT naming — they are the cloud engine's
 *      STT modality, not the engine identity.
 */

#include <jni.h>
#include <string>

// Errors always log. The verbose INFO trace is gated to debug builds (NDEBUG is
// defined in release) so production stays quiet.
#ifdef __ANDROID__
#include <android/log.h>
#define CLOUD_JNI_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "cloud", __VA_ARGS__)
#if !defined(NDEBUG) || defined(RAC_JNI_VERBOSE)
#define CLOUD_JNI_LOG(...)   __android_log_print(ANDROID_LOG_INFO,  "cloud", __VA_ARGS__)
#else
#define CLOUD_JNI_LOG(...)   ((void)0)
#endif
#else
#define CLOUD_JNI_LOG(...)   ((void)0)
#define CLOUD_JNI_LOG_E(...) ((void)0)
#endif

#include "rac/backends/rac_stt_cloud.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_plugin_entry_cloud.h"

// Shared engine JNI helpers (header-only). The ".." chain is relative to this
// source file's own directory (engines/cloud/jni/), so it resolves without
// any extra -I wiring on the JNI target: ../../common/ == engines/common/.
#include "../../common/rac_engine_jni_bridge.h"

// Stamp the LOG_TAG the shared LOGi/LOGe/LOGw macros (from rac_engine_jni_bridge.h)
// route through.
RAC_DEFINE_ENGINE_JNI_LOG_TAG("JNI.Cloud");

namespace {

std::string jstring_to_std(JNIEnv* env, jstring s) {
    if (s == nullptr) {
        return {};
    }
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out(c == nullptr ? "" : c);
    if (c != nullptr) {
        env->ReleaseStringUTFChars(s, c);
    }
    return out;
}

}  // namespace

// Forward declarations of the explicit backend register/unregister entry points
// (defined in engines/cloud/rac_backend_cloud_register.cpp). Pulled in via
// rac/plugin/rac_plugin_entry_cloud.h above, repeated here for locality with the
// bridge macro that references them.
extern "C" rac_result_t rac_backend_cloud_register(void);
extern "C" rac_result_t rac_backend_cloud_unregister(void);

// Version string for nativeGetVersion. The cloud engine has no upstream
// native-lib version; report the commons build version when CMake injects
// RAC_VERSION_STRING, else a stable fallback.
#ifdef RAC_VERSION_STRING
#define RAC_CLOUD_JNI_VERSION_STR RAC_VERSION_STRING
#else
#define RAC_CLOUD_JNI_VERSION_STR "1.0.0"
#endif

extern "C" {

// =============================================================================
// Backend Registration quartet (generated) — NO JNI_OnLoad
// =============================================================================
//
// Emits, with C linkage and EXACT JNI symbol parity:
//   Java_com_runanywhere_sdk_native_bridge_CloudBridge_nativeRegister
//   Java_com_runanywhere_sdk_native_bridge_CloudBridge_nativeUnregister
//   Java_com_runanywhere_sdk_native_bridge_CloudBridge_nativeIsRegistered
//   Java_com_runanywhere_sdk_native_bridge_CloudBridge_nativeGetVersion
// The cloud engine cross-registers no sibling backend, so it passes the no-op
// after-register statement. nativeIsRegistered scans the TRANSCRIBE plugin
// registry for the plugin named "cloud".
//
// NO-ONLOAD variant: this TU is folded into runanywhere_commons_jni
// (librunanywhere_jni.so) by engines/cloud/CMakeLists.txt, and that lib
// already defines JNI_OnLoad in runanywhere_commons_jni.cpp (it caches the
// JavaVM). Emitting a second JNI_OnLoad here would be a duplicate-symbol link
// error, so we use the _NO_ONLOAD macro and let commons own JNI_OnLoad. Plugin
// registration is unaffected: Kotlin's CloudBridge.nativeRegister() drives
// rac_backend_cloud_register() directly, independent of JNI_OnLoad.
RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD(com_runanywhere_sdk_native_bridge_CloudBridge,
                                       rac_backend_cloud_register,
                                       rac_backend_cloud_unregister, "Cloud", "",
                                       RAC_ENGINE_JNI_NO_AFTER_REGISTER, RAC_PRIMITIVE_TRANSCRIBE,
                                       "cloud", RAC_CLOUD_JNI_VERSION_STR)

// =============================================================================
// Bespoke STT-modality factory thunks (create / createFromJson / destroy)
// =============================================================================
// These keep their `racSttCloud*` STT naming — they front the cloud engine's
// STT modality (rac_stt_cloud_*). The JNI class token is the engine-level
// CloudBridge so the symbols stay parity-matched to the Kotlin bridge class.

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_CloudBridge_racSttCloudCreate(
    JNIEnv* env, jclass /*clazz*/, jstring api_key, jstring model) {
    const std::string  key = jstring_to_std(env, api_key);
    const std::string  mdl = jstring_to_std(env, model);
    rac_stt_service_t* svc = nullptr;
    if (rac_stt_cloud_create(key.c_str(), mdl.c_str(), &svc) != RAC_SUCCESS || svc == nullptr) {
        return 0;
    }
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_CloudBridge_racSttCloudCreateFromJson(
    JNIEnv* env, jclass /*clazz*/, jstring config_json) {
    const std::string  cfg = jstring_to_std(env, config_json);
    CLOUD_JNI_LOG("createFromJson: cfg_len=%zu", cfg.size());
    rac_stt_service_t* svc = nullptr;
    rac_result_t       rc  = rac_stt_cloud_create_from_json(cfg.c_str(), &svc);
    if (rc != RAC_SUCCESS || svc == nullptr) {
        CLOUD_JNI_LOG_E("createFromJson FAILED rc=%d svc=%p", rc, (void*)svc);
        return 0;
    }
    CLOUD_JNI_LOG("createFromJson OK svc=%p", (void*)svc);
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_CloudBridge_racSttCloudDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle != 0) {
        rac_stt_cloud_destroy(reinterpret_cast<rac_stt_service_t*>(handle));
    }
}

}  // extern "C"
