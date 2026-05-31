/**
 * @file rac_stt_hybrid_router_jni.cpp
 * @brief JNI thunks for the STT hybrid router + the offline STT service
 *        factory.
 *
 * Stays byte-only at the .so boundary. All proto parsing / building
 * lives inside rac_commons (rac_stt_hybrid_router_proto.cpp); these
 * thunks just marshal jbyteArray → (const uint8_t*, size_t) and back.
 *
 * Service handles (offline / online) cross the JNI as raw `jlong`
 * (reinterpret_cast'd `rac_stt_service_t*`). Kotlin obtains them from
 * either racSttServiceCreate (for in-tree STT backends like sherpa-onnx)
 * or from the engine-specific factory (e.g. SarvamBridge.racSttSarvamCreate).
 */

#include <jni.h>
#include <sys/stat.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define STTJNI_LOG(...)   __android_log_print(ANDROID_LOG_INFO,  "stt_router_jni", __VA_ARGS__)
#define STTJNI_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "stt_router_jni", __VA_ARGS__)
#else
#define STTJNI_LOG(...)   ((void)0)
#define STTJNI_LOG_E(...) ((void)0)
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"
#include "rac/routing/rac_stt_hybrid_router.h"
#include "rac/routing/rac_stt_hybrid_router_proto.h"

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
    struct stat st {};
    return (::stat(path.c_str(), &st) == 0) && S_ISDIR(st.st_mode);
}

const char* framework_to_plugin_hint(rac_inference_framework_t fw) {
    switch (fw) {
        case RAC_FRAMEWORK_SHERPA:            return "sherpa";
        case RAC_FRAMEWORK_ONNX:              return "onnx";
        case RAC_FRAMEWORK_WHISPERKIT_COREML: return "whisperkit_coreml";
        case RAC_FRAMEWORK_FOUNDATION_MODELS: return "platform";
        case RAC_FRAMEWORK_SYSTEM_TTS:        return "platform";
        case RAC_FRAMEWORK_COREML:            return "platform";
        default:                              return nullptr;
    }
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttServiceCreate(
    JNIEnv* env, jclass /*clazz*/, jstring model_id) {
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

    // Route to the matching STT plugin and call its create op directly with
    // our resolved path. Bypasses rac_stt_create()'s path-override logic.
    rac_routing_hints_t hints {};
    hints.preferred_engine_name = framework_to_plugin_hint(framework);

    const rac_engine_vtable_t* vt = nullptr;
    rac_result_t route_rc = rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, /*format=*/0, &hints, &vt);
    if (route_rc != RAC_SUCCESS || vt == nullptr || vt->stt_ops == nullptr ||
        vt->stt_ops->create == nullptr) {
        STTJNI_LOG_E("racSttServiceCreate: rac_plugin_route failed rc=%d vt=%p", route_rc, (const void*)vt);
        return 0;
    }

    void* impl = nullptr;
    rac_result_t create_rc =
        vt->stt_ops->create(resolved_path.c_str(), /*config_json=*/nullptr, &impl);
    if (create_rc != RAC_SUCCESS || impl == nullptr) {
        STTJNI_LOG_E("racSttServiceCreate: stt_ops->create FAILED rc=%d path='%s'",
                     create_rc, resolved_path.c_str());
        return 0;
    }

    auto* service = static_cast<rac_stt_service_t*>(std::malloc(sizeof(rac_stt_service_t)));
    if (service == nullptr) {
        if (vt->stt_ops->destroy != nullptr) {
            vt->stt_ops->destroy(impl);
        }
        return 0;
    }
    service->ops = vt->stt_ops;
    service->impl = impl;
    service->model_id = strdup(id.c_str());  // rac_stt_destroy free()s this

    STTJNI_LOG("racSttServiceCreate: OK service=%p path='%s'",
               (void*)service, resolved_path.c_str());
    return reinterpret_cast<jlong>(service);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttServiceDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
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
        reinterpret_cast<rac_stt_service_t*>(service_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterSetOnlineService(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jlong service_handle,
    jbyteArray descriptor_proto) {
    const auto bytes = jbyte_array_to_vec(env, descriptor_proto);
    return static_cast<jint>(rac_stt_hybrid_router_set_online_service_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        reinterpret_cast<rac_stt_service_t*>(service_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterSetPolicy(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray policy_proto) {
    const auto bytes = jbyte_array_to_vec(env, policy_proto);
    return static_cast<jint>(rac_stt_hybrid_router_set_policy_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttHybridRouterTranscribe(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray request_proto) {
    const auto bytes = jbyte_array_to_vec(env, request_proto);
    uint8_t* response_bytes = nullptr;
    size_t   response_size = 0;
    const rac_result_t rc = rac_stt_hybrid_router_transcribe_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        bytes.data(), bytes.size(),
        &response_bytes, &response_size);
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
