/**
 * @file rac_stt_hybrid_router_jni.cpp
 * @brief JNI thunks for the STT hybrid router + a unified registry-backed STT
 *        service factory used by BOTH router sides.
 *
 * Stays byte-only at the proto .so boundary. All proto parsing / building
 * lives inside rac_commons (rac_stt_hybrid_router_proto.cpp); the transcribe /
 * set-policy / set-service thunks just marshal jbyteArray → (const uint8_t*,
 * size_t) and back.
 *
 * Service handles (offline / online) cross the JNI as raw `jlong`
 * (reinterpret_cast'd `rac_stt_service_t*`). BOTH sides are created through the
 * SAME registry path — rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE,
 * <"sherpa"|"cloud">) → vt->stt_ops->create — via
 * create_stt_service_via_registry(): the offline side enters it from
 * racSttServiceCreate (model-registry path resolution for in-tree backends
 * like sherpa-onnx), the online side from racSttHybridRouterCreateService
 * (explicit engine hint + config JSON; the cloud provider, default
 * "sarvam", travels in that config JSON). The router path no longer depends on
 * any bespoke per-engine factory; racSttHybridRouterDestroyService releases
 * either handle through rac_stt_destroy.
 */

#include <jni.h>

#include <nlohmann/json.hpp>
#include <string>
#include <sys/stat.h>
#include <vector>

// Errors always log. The verbose INFO trace is gated to debug builds (NDEBUG is
// defined in release) so production stays quiet.
#ifdef __ANDROID__
#include <android/log.h>
#define STTJNI_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "stt_router_jni", __VA_ARGS__)
#if !defined(NDEBUG) || defined(RAC_JNI_VERBOSE)
#define STTJNI_LOG(...) __android_log_print(ANDROID_LOG_INFO, "stt_router_jni", __VA_ARGS__)
#else
#define STTJNI_LOG(...) ((void)0)
#endif
#else
#define STTJNI_LOG(...) ((void)0)
#define STTJNI_LOG_E(...) ((void)0)
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/router/hybrid/rac_stt_hybrid_router.h"
#include "rac/router/hybrid/rac_stt_hybrid_router_proto.h"

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

std::vector<uint8_t> jbyte_array_to_vec(JNIEnv* env, jbyteArray arr) {
    if (arr == nullptr) {
        return {};
    }
    const jsize len = env->GetArrayLength(arr);
    if (len <= 0) {
        return {};
    }
    std::vector<uint8_t> out(static_cast<size_t>(len));
    env->GetByteArrayRegion(arr, 0, len, reinterpret_cast<jbyte*>(out.data()));
    return out;
}

jbyteArray bytes_to_jbyte_array(JNIEnv* env, uint8_t* src, size_t size) {
    if (src == nullptr) {
        return env->NewByteArray(0);
    }
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(size));
    if (arr != nullptr && size > 0) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(src));
    }
    rac_stt_hybrid_router_proto_buffer_free(src);
    return arr;
}

bool path_is_directory(const std::string& path) {
    struct stat st{};
    return (::stat(path.c_str(), &st) == 0) && S_ISDIR(st.st_mode);
}

const char* framework_to_plugin_hint(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_SHERPA:
            return "sherpa";
        case RAC_FRAMEWORK_ONNX:
            return "onnx";
        // RAC_FRAMEWORK_WHISPERKIT_COREML (retired enum value 9) intentionally
        // dropped: the whisperkit_coreml engine was removed, so no plugin hint
        // can resolve to it. Unmapped frameworks fall through to the default
        // (nullptr), letting rac_plugin_find pick by primitive/format.
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "platform";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "platform";
        case RAC_FRAMEWORK_COREML:
            return "platform";
        default:
            return nullptr;
    }
}

// Engine hint for the generic cloud backend (engines/cloud), a modality-agnostic
// engine that today serves STT. The concrete HTTP provider is chosen per-service
// from config_json["provider"] (default "sarvam"), NOT from the hint.
constexpr char kCloudSttEngineHint[] = "cloud";
constexpr char kDefaultCloudProvider[] = "sarvam";

// Ensures config_json carries a "provider" so the cloud engine selects a
// concrete adapter. When the hint targets cloud and the incoming JSON has
// no "provider" key, inject the default ("sarvam"). Returns the (possibly
// rewritten) config string; passes non-cloud hints and already-tagged configs
// through unchanged. Malformed JSON is left untouched — the engine surfaces the
// parse error itself.
std::string ensure_cloud_provider(const std::string& engine_hint, const std::string& config_json) {
    if (engine_hint != kCloudSttEngineHint) {
        return config_json;
    }
    nlohmann::json j = config_json.empty() ? nlohmann::json::object()
                                           : nlohmann::json::parse(config_json, nullptr,
                                                                   /*allow_exceptions=*/false);
    if (!j.is_object()) {
        return config_json;  // not an object → leave verbatim for the engine.
    }
    if (!j.contains("provider")) {
        j["provider"] = kDefaultCloudProvider;
    }
    return j.dump();
}

// Unified "create an STT service by engine hint + config" path. BOTH the
// offline (sherpa) and online (cloud, provider=sarvam) sides of the hybrid
// router go through this single function so service creation always resolves the
// engine through the plugin registry (rac_plugin_find_for_engine → vt->stt_ops->create) —
// there is no bespoke per-engine factory on the router path.
//
//   - engine_hint    : "sherpa" | "cloud" | … pinned as preferred_engine_name.
//                      Empty/NULL lets the registry pick by primitive/format.
//   - model_or_config: passed verbatim as the create op's `model_id` argument
//                      (an on-device path for sherpa, or NULL for cloud
//                      engines that take everything via config_json).
//   - config_json    : passed verbatim as the create op's `config_json`
//                      argument (the cloud {provider,api_key,model,…} JSON, or
//                      NULL). The online entry point threads the provider in.
//
// Thin JNI adapter over the public commons factory
// rac_stt_hybrid_router_create_service (DRY: one implementation; the route /
// heap-wrap / ownership live in commons). Returns a heap rac_stt_service_t* (as
// jlong) the router owns by handle, or 0.
jlong create_stt_service_via_registry(const std::string& engine_hint, const char* model_or_config,
                                      const char* config_json) {
    rac_stt_service_t* service = rac_stt_hybrid_router_create_service(
        engine_hint.empty() ? nullptr : engine_hint.c_str(), model_or_config, config_json);
    if (service == nullptr) {
        STTJNI_LOG_E("create_stt_service_via_registry: create failed hint='%s'",
                     engine_hint.c_str());
        return 0;
    }
    STTJNI_LOG("create_stt_service_via_registry: OK service=%p hint='%s'", (void*)service,
               engine_hint.c_str());
    return reinterpret_cast<jlong>(service);
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttServiceCreate(JNIEnv* env,
                                                                             jclass /*clazz*/,
                                                                             jstring model_id) {
    const std::string id = jstring_to_std(env, model_id);
    STTJNI_LOG("racSttServiceCreate: model_id='%s'", id.c_str());
    if (id.empty()) {
        STTJNI_LOG_E("racSttServiceCreate: empty model_id");
        return 0;
    }

    // Look up framework + outer local_path. We can't call rac_stt_create()
    // because it always overrides our resolved path with the registry's
    // outer local_path via the id-extraction fallback — which is wrong for
    // ARCHIVE_STRUCTURE_NESTED_DIRECTORY models like sherpa-onnx-whisper
    // where the .onnx files live one level deeper than local_path.
    rac_model_info_t* model_info = nullptr;
    if (rac_get_model(id.c_str(), &model_info) != RAC_SUCCESS || model_info == nullptr) {
        STTJNI_LOG_E("racSttServiceCreate: rac_get_model failed for '%s'", id.c_str());
        return 0;
    }
    const rac_inference_framework_t framework = model_info->framework;
    const std::string outer_path = model_info->local_path ? model_info->local_path : "";
    rac_model_info_free(model_info);
    if (outer_path.empty()) {
        STTJNI_LOG_E("racSttServiceCreate: model '%s' has empty local_path", id.c_str());
        return 0;
    }

    // Probe for the nested-directory layout: <outer>/<id>/. If present, that's
    // where the actual model files live (the archive extracted into a nested
    // dir of the same name).
    std::string resolved_path = outer_path;
    const std::string nested = outer_path + "/" + id;
    if (path_is_directory(nested)) {
        resolved_path = nested;
        STTJNI_LOG("racSttServiceCreate: using nested path '%s'", resolved_path.c_str());
    } else {
        STTJNI_LOG("racSttServiceCreate: using flat path '%s'", resolved_path.c_str());
    }

    // Route to the matching STT plugin and call its create op with our
    // resolved path through the shared registry helper. Bypasses
    // rac_stt_create()'s path-override logic; the create itself goes through
    // rac_plugin_find exactly like every other commons consumer.
    const char* hint = framework_to_plugin_hint(framework);
    const jlong svc =
        create_stt_service_via_registry(hint != nullptr ? std::string(hint) : std::string(),
                                        resolved_path.c_str(), /*config_json=*/nullptr);
    if (svc == 0) {
        STTJNI_LOG_E("racSttServiceCreate: create_stt_service_via_registry failed path='%s'",
                     resolved_path.c_str());
    }
    return svc;
}

// Unified registry-based STT service factory used by the hybrid router for the
// ONLINE side (and any caller wanting an explicit engine hint + config). The
// online cloud service (provider=sarvam by default) is now resolved through
// the plugin registry exactly like the offline/sherpa service — `engineHint`
// (e.g. "cloud") is pinned as preferred_engine_name, `modelIdOrPath` and
// `configJson` are forwarded to the routed engine's stt_ops->create. For the
// cloud hint the provider is threaded into config_json (defaulting to
// "sarvam") so the engine selects the right adapter. This replaces the bespoke
// SarvamBridge.racSttSarvamCreate* factory on the router path; the returned
// jlong is the same opaque rac_stt_service_t* the router setters accept.
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterCreateService(
    JNIEnv* env, jclass /*clazz*/, jstring engine_hint, jstring model_id_or_path,
    jstring config_json) {
    const std::string hint = jstring_to_std(env, engine_hint);
    const std::string model = jstring_to_std(env, model_id_or_path);
    const std::string config = ensure_cloud_provider(hint, jstring_to_std(env, config_json));
    STTJNI_LOG("racSttHybridRouterCreateService: hint='%s' model_len=%zu config_len=%zu",
               hint.c_str(), model.size(), config.size());
    return create_stt_service_via_registry(hint, model.empty() ? nullptr : model.c_str(),
                                           config.empty() ? nullptr : config.c_str());
}

// Destroy a service created by racSttHybridRouterCreateService (or by
// racSttServiceCreate). Both wrap the routed engine's vtable in a
// rac_stt_service_t and route destroy through rac_stt_destroy, which calls the
// engine's stt_ops->destroy and frees the wrapper — no bespoke per-engine
// destroy thunk is involved on the router path.
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterDestroyService(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong service_handle) {
    if (service_handle != 0) {
        rac_stt_destroy(reinterpret_cast<rac_handle_t>(service_handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttServiceDestroy(JNIEnv* /*env*/,
                                                                              jclass /*clazz*/,
                                                                              jlong handle) {
    if (handle != 0) {
        rac_stt_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterCreate(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    if (rac_stt_hybrid_router_create(&handle) != RAC_SUCCESS) {
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterDestroy(JNIEnv* /*env*/,
                                                                                   jclass /*clazz*/,
                                                                                   jlong handle) {
    if (handle != 0) {
        rac_stt_hybrid_router_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterSetOfflineService(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jlong service_handle,
    jbyteArray descriptor_proto) {
    const auto bytes = jbyte_array_to_vec(env, descriptor_proto);
    return static_cast<jint>(rac_stt_hybrid_router_set_offline_service_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        reinterpret_cast<rac_stt_service_t*>(service_handle), bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterSetOnlineService(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jlong service_handle,
    jbyteArray descriptor_proto) {
    const auto bytes = jbyte_array_to_vec(env, descriptor_proto);
    return static_cast<jint>(rac_stt_hybrid_router_set_online_service_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        reinterpret_cast<rac_stt_service_t*>(service_handle), bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterSetPolicy(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray policy_proto) {
    const auto bytes = jbyte_array_to_vec(env, policy_proto);
    return static_cast<jint>(rac_stt_hybrid_router_set_policy_proto(
        reinterpret_cast<rac_handle_t>(router_handle), bytes.data(), bytes.size()));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterTranscribe(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray request_proto) {
    const auto bytes = jbyte_array_to_vec(env, request_proto);
    uint8_t* response_bytes = nullptr;
    size_t response_size = 0;
    const rac_result_t rc = rac_stt_hybrid_router_transcribe_proto(
        reinterpret_cast<rac_handle_t>(router_handle), bytes.data(), bytes.size(), &response_bytes,
        &response_size);
    if (rc != RAC_SUCCESS) {
        rac_stt_hybrid_router_proto_buffer_free(response_bytes);
        return nullptr;
    }
    return bytes_to_jbyte_array(env, response_bytes, response_size);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterCancel(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong router_handle) {
    if (router_handle == 0) {
        return static_cast<jint>(RAC_SUCCESS);
    }
    return static_cast<jint>(
        rac_stt_hybrid_router_cancel(reinterpret_cast<rac_handle_t>(router_handle)));
}

}  // extern "C"
