/**
 * QHexRT Backend JNI Bridge
 *
 * JNI layer for the QHexRT (Qualcomm Hexagon NPU) backend. Links against
 * rac_commons for shared registry/download services and against the QHexRT
 * engine for capability, chip selection, and device-aware catalog policy.
 *
 * Linked by: runanywhere-kotlin/modules/runanywhere-core-qhexrt
 * Package: com.runanywhere.sdk.npu.qhexrt   Class: QHexRTBridge
 *
 * The register/unregister/isRegistered/getVersion quartet + JNI_OnLoad come from
 * the shared RAC_DEFINE_ENGINE_JNI_BRIDGE macro. nativeProbeNpuProto is
 * hand-written: it surfaces the QHexRT-owned pre-flight Hexagon probe and
 * catalog calls without reimplementing their policy in Kotlin.
 */

#include <jni.h>

#include <limits>
#include <string>
#include <vector>

#include "../../common/rac_engine_jni_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/qhexrt/rac_qhexrt.h"

RAC_DEFINE_ENGINE_JNI_LOG_TAG("JNI.QHexRT");

#ifndef RAC_QHEXRT_VERSION
#define RAC_QHEXRT_VERSION "unknown"
#endif

extern "C" rac_result_t rac_backend_qhexrt_register(void);
extern "C" rac_result_t rac_backend_qhexrt_unregister(void);
#if defined(__ANDROID__)
extern "C" void rac_qhexrt_set_skel_directory(const char* path);
#endif

namespace {

void throw_java_exception(JNIEnv* env, const char* class_name, const std::string& message) {
    jclass exception_class = env->FindClass(class_name);
    if (exception_class != nullptr) {
        env->ThrowNew(exception_class, message.c_str());
        env->DeleteLocalRef(exception_class);
    }
}

bool is_input_error(rac_result_t result) {
    return result == RAC_ERROR_INVALID_PARAMETER || result == RAC_ERROR_VALIDATION_FAILED ||
           result == RAC_ERROR_INVALID_INPUT || result == RAC_ERROR_INVALID_ARGUMENT ||
           result == RAC_ERROR_NULL_POINTER;
}

}  // namespace

extern "C" {

// JNI_OnLoad + nativeRegister/nativeUnregister/nativeIsRegistered/nativeGetVersion.
// QHexRT cross-registers no sibling backend (no-op after-register); the plugin
// registers under "qhexrt" and is discoverable via the GENERATE_TEXT primitive.
RAC_DEFINE_ENGINE_JNI_BRIDGE(com_runanywhere_sdk_npu_qhexrt_QHexRTBridge,
                             rac_backend_qhexrt_register, rac_backend_qhexrt_unregister, "QHexRT",
                             "", RAC_ENGINE_JNI_NO_AFTER_REGISTER, RAC_PRIMITIVE_GENERATE_TEXT,
                             "qhexrt", RAC_QHEXRT_VERSION)

// Pre-flight Hexagon NPU probe. Thin proto thunk: returns serialized
// runanywhere.v1.NpuCapability bytes the Kotlin layer decodes with its
// generated Wire types. On failure returns an EMPTY array (never NULL), which
// decodes to the all-default (unknown/unsupported) capability.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeProbeNpuProto(JNIEnv* env, jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t buf;
    rac_proto_buffer_init(&buf);
    const rac_result_t rc = rac_qhexrt_probe_proto(&buf);
    if (rc != RAC_SUCCESS || RAC_FAILED(buf.status) || (buf.size > 0 && buf.data == nullptr)) {
        LOGe("nativeProbeNpuProto: rac_qhexrt_probe_proto failed (rc=%d, status=%d, %s)", rc,
             buf.status, buf.error_message ? buf.error_message : "");
        rac_proto_buffer_free(&buf);
        return env->NewByteArray(0);
    }
    jbyteArray out = env->NewByteArray(static_cast<jsize>(buf.size));
    if (out == nullptr) {
        // OOM: an exception is pending; free and let the JVM raise it.
        rac_proto_buffer_free(&buf);
        return nullptr;
    }
    if (buf.size > 0) {
        env->SetByteArrayRegion(out, 0, static_cast<jsize>(buf.size),
                                reinterpret_cast<const jbyte*>(buf.data));
    }
    rac_proto_buffer_free(&buf);
    return out;
}

JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeArchIsSupported(
    JNIEnv* env, jclass clazz, jint arch) {
    (void)env;
    (void)clazz;
    return rac_qhexrt_arch_is_supported(static_cast<rac_qhexrt_hexagon_arch_t>(arch)) == RAC_TRUE
               ? JNI_TRUE
               : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeCatalogModelSupportsArch(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jstring model_id,
                                                                                jint arch) {
    (void)clazz;
    if (model_id == nullptr) {
        return JNI_FALSE;
    }
    const char* id = env->GetStringUTFChars(model_id, nullptr);
    if (id == nullptr) {
        return JNI_FALSE;
    }
    const rac_bool_t supported =
        rac_qhexrt_catalog_model_supports_arch(id, static_cast<rac_qhexrt_hexagon_arch_t>(arch));
    env->ReleaseStringUTFChars(model_id, id);
    return supported == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeCatalogModelRequiresHfAuth(
    JNIEnv* env, jclass clazz, jstring model_id) {
    (void)clazz;
    if (model_id == nullptr) {
        return JNI_FALSE;
    }
    const char* id = env->GetStringUTFChars(model_id, nullptr);
    if (id == nullptr) {
        return JNI_FALSE;
    }
    const rac_bool_t requires_auth = rac_qhexrt_catalog_model_requires_hf_auth(id);
    env->ReleaseStringUTFChars(model_id, id);
    return requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeCatalogRegisterModelProto(
    JNIEnv* env, jclass clazz, jbyteArray request_bytes) {
    (void)clazz;
    if (request_bytes == nullptr) {
        throw_java_exception(env, "java/lang/IllegalArgumentException",
                             "requestBytes must not be null");
        return nullptr;
    }

    const jsize request_size = env->GetArrayLength(request_bytes);
    std::vector<uint8_t> request(static_cast<size_t>(request_size));
    if (request_size > 0) {
        env->GetByteArrayRegion(request_bytes, 0, request_size,
                                reinterpret_cast<jbyte*>(request.data()));
    }
    rac_bool_t registered = RAC_FALSE;
    rac_proto_buffer_t model;
    rac_proto_buffer_init(&model);
    const rac_result_t rc = rac_qhexrt_catalog_register_model_proto(request.data(), request.size(),
                                                                    &registered, &model);
    const rac_result_t status = rc != RAC_SUCCESS ? rc : model.status;
    if (status != RAC_SUCCESS) {
        const std::string detail = model.error_message != nullptr ? model.error_message : "";
        const std::string message =
            "QHexRT device-aware model registration failed (code=" + std::to_string(status) + ")" +
            (detail.empty() ? "" : ": " + detail);
        LOGe("nativeCatalogRegisterModelProto: %s", message.c_str());
        rac_proto_buffer_free(&model);
        throw_java_exception(env,
                             is_input_error(status) ? "java/lang/IllegalArgumentException"
                                                    : "java/lang/IllegalStateException",
                             message);
        return nullptr;
    }

    if (registered != RAC_TRUE) {
        rac_proto_buffer_free(&model);
        return nullptr;
    }
    if (model.data == nullptr || model.size == 0 ||
        model.size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        rac_proto_buffer_free(&model);
        throw_java_exception(env, "java/lang/IllegalStateException",
                             "QHexRT registration returned an invalid ModelInfo payload");
        return nullptr;
    }

    jbyteArray out = env->NewByteArray(static_cast<jsize>(model.size));
    if (out != nullptr) {
        env->SetByteArrayRegion(out, 0, static_cast<jsize>(model.size),
                                reinterpret_cast<const jbyte*>(model.data));
    }
    rac_proto_buffer_free(&model);
    return out;
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeSetSkelDirectory(
    JNIEnv* env, jclass clazz, jstring path) {
    (void)clazz;
#if defined(__ANDROID__)
    if (path == nullptr) {
        rac_qhexrt_set_skel_directory(nullptr);
        return;
    }
    const char* chars = env->GetStringUTFChars(path, nullptr);
    if (chars == nullptr) {
        return;
    }
    rac_qhexrt_set_skel_directory(chars);
    env->ReleaseStringUTFChars(path, chars);
#else
    (void)env;
    (void)path;
#endif
}

}  // extern "C"
