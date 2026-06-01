/**
 * @file rac_stt_sarvam_jni.cpp
 * @brief JNI thunks for the Sarvam STT backend factory.
 *
 * Kotlin obtains an opaque `rac_stt_service_t*` (passed across JNI as a
 * `jlong`) which it then hands to whatever STT facade consumes the engine.
 */

#include <jni.h>
#include <string>

// Errors always log. The verbose INFO trace is gated to debug builds (NDEBUG is
// defined in release) so production stays quiet.
#ifdef __ANDROID__
#include <android/log.h>
#define SARVAM_JNI_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "sarvam", __VA_ARGS__)
#if !defined(NDEBUG) || defined(RAC_JNI_VERBOSE)
#define SARVAM_JNI_LOG(...)   __android_log_print(ANDROID_LOG_INFO,  "sarvam", __VA_ARGS__)
#else
#define SARVAM_JNI_LOG(...)   ((void)0)
#endif
#else
#define SARVAM_JNI_LOG(...)   ((void)0)
#define SARVAM_JNI_LOG_E(...) ((void)0)
#endif

#include "rac/backends/rac_stt_sarvam.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

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

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_SarvamBridge_racSttSarvamCreate(
    JNIEnv* env, jclass /*clazz*/, jstring api_key, jstring model) {
    const std::string  key = jstring_to_std(env, api_key);
    const std::string  mdl = jstring_to_std(env, model);
    rac_stt_service_t* svc = nullptr;
    if (rac_stt_sarvam_create(key.c_str(), mdl.c_str(), &svc) != RAC_SUCCESS || svc == nullptr) {
        return 0;
    }
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_SarvamBridge_racSttSarvamCreateFromJson(
    JNIEnv* env, jclass /*clazz*/, jstring config_json) {
    const std::string  cfg = jstring_to_std(env, config_json);
    SARVAM_JNI_LOG("createFromJson: cfg_len=%zu", cfg.size());
    rac_stt_service_t* svc = nullptr;
    rac_result_t       rc  = rac_stt_sarvam_create_from_json(cfg.c_str(), &svc);
    if (rc != RAC_SUCCESS || svc == nullptr) {
        SARVAM_JNI_LOG_E("createFromJson FAILED rc=%d svc=%p", rc, (void*)svc);
        return 0;
    }
    SARVAM_JNI_LOG("createFromJson OK svc=%p", (void*)svc);
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_SarvamBridge_racSttSarvamDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle != 0) {
        rac_stt_sarvam_destroy(reinterpret_cast<rac_stt_service_t*>(handle));
    }
}

}  // extern "C"