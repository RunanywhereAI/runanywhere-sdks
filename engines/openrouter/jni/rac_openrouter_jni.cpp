/**
 * @file rac_openrouter_jni.cpp
 * @brief JNI thunks for the OpenRouter LLM backend factory.
 *
 * Kotlin obtains an opaque `rac_llm_service_t*` (passed across the JNI
 * as a `jlong`) which it then hands to the hybrid router via
 * `RunAnywhereBridge.racLlmHybridRouterSetOnlineService`.
 */

#include <jni.h>

#include <string>

#ifdef __ANDROID__
#include <android/log.h>
#define ORJNI_LOG(...) __android_log_print(ANDROID_LOG_INFO, "openrouter", __VA_ARGS__)
#define ORJNI_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "openrouter", __VA_ARGS__)
#else
#define ORJNI_LOG(...) ((void)0)
#define ORJNI_LOG_E(...) ((void)0)
#endif

#include "rac/backends/rac_llm_openrouter.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

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
Java_com_runanywhere_sdk_native_bridge_OpenRouterBridge_racLlmOpenRouterCreate(
    JNIEnv* env, jclass /*clazz*/, jstring api_key, jstring model) {
    const std::string  key = jstring_to_std(env, api_key);
    const std::string  mdl = jstring_to_std(env, model);
    rac_llm_service_t* svc = nullptr;
    if (rac_llm_openrouter_create(key.c_str(), mdl.c_str(), &svc) != RAC_SUCCESS || svc == nullptr) {
        return 0;
    }
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_OpenRouterBridge_racLlmOpenRouterCreateFromJson(
    JNIEnv* env, jclass /*clazz*/, jstring config_json) {
    const std::string  cfg = jstring_to_std(env, config_json);
    ORJNI_LOG("createFromJson: cfg_len=%zu", cfg.size());
    rac_llm_service_t* svc = nullptr;
    rac_result_t       rc = rac_llm_openrouter_create_from_json(cfg.c_str(), &svc);
    if (rc != RAC_SUCCESS || svc == nullptr) {
        ORJNI_LOG_E("createFromJson FAILED rc=%d svc=%p", rc, (void*)svc);
        return 0;
    }
    ORJNI_LOG("createFromJson OK svc=%p", (void*)svc);
    return reinterpret_cast<jlong>(svc);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_OpenRouterBridge_racLlmOpenRouterDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle != 0) {
        rac_llm_openrouter_destroy(reinterpret_cast<rac_llm_service_t*>(handle));
    }
}

}  // extern "C"
