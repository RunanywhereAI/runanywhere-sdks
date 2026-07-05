/**
 * QHexRT Backend JNI Bridge
 *
 * JNI layer for the QHexRT (Qualcomm Hexagon NPU) backend. Links against
 * rac_commons for the plugin registry + the NPU capability probe.
 *
 * Linked by: runanywhere-kotlin/modules/runanywhere-core-qhexrt
 * Package: com.runanywhere.sdk.npu.qhexrt   Class: QHexRTBridge
 *
 * The register/unregister/isRegistered/getVersion quartet + JNI_OnLoad come from
 * the shared RAC_DEFINE_ENGINE_JNI_BRIDGE macro. nativeProbeNpuProto is
 * hand-written: it surfaces the pre-flight Hexagon-arch detection
 * (rac_npu_probe_proto) so the app can warn before loading QNN. The probe lives
 * in commons and works on any device, including non-v75/v79/v81 parts.
 */

#include <jni.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/device/rac_npu_capability.h"

#include "../../common/rac_engine_jni_bridge.h"

RAC_DEFINE_ENGINE_JNI_LOG_TAG("JNI.QHexRT");

#ifndef RAC_QHEXRT_VERSION
#define RAC_QHEXRT_VERSION "0.1.0"
#endif

extern "C" rac_result_t rac_backend_qhexrt_register(void);
extern "C" rac_result_t rac_backend_qhexrt_unregister(void);

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
    const rac_result_t rc = rac_npu_probe_proto(&buf);
    if (rc != RAC_SUCCESS || RAC_FAILED(buf.status) || (buf.size > 0 && buf.data == nullptr)) {
        LOGe("nativeProbeNpuProto: rac_npu_probe_proto failed (rc=%d, status=%d, %s)", rc,
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

}  // extern "C"
