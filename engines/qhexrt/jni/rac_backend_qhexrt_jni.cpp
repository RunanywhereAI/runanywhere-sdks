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
 * the shared RAC_DEFINE_ENGINE_JNI_BRIDGE macro. nativeProbeNpu is hand-written:
 * it surfaces the pre-flight Hexagon-arch detection (rac_npu_probe) so the app
 * can warn before loading QNN. The probe lives in commons and works on any
 * device, including non-v79/81 parts.
 */

#include <jni.h>

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
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

// Pre-flight Hexagon NPU probe. Returns a small JSON object the Kotlin layer
// parses: {"soc_model","soc_id","arch","supported"}. soc_model is a vendor
// identifier (alphanumeric), so no JSON escaping is required.
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_npu_qhexrt_QHexRTBridge_nativeProbeNpu(JNIEnv* env, jclass clazz) {
    (void)clazz;
    rac_npu_info_t info;
    if (rac_npu_probe(&info) != RAC_SUCCESS) {
        return env->NewStringUTF("{\"soc_model\":\"\",\"soc_id\":-1,\"arch\":\"unknown\","
                                 "\"supported\":false}");
    }
    char buf[256];
    std::snprintf(buf, sizeof(buf),
                  "{\"soc_model\":\"%s\",\"soc_id\":%d,\"arch\":\"%s\",\"supported\":%s}",
                  info.soc_model, info.soc_id, rac_hexagon_arch_name(info.hexagon_arch),
                  info.qhexrt_supported ? "true" : "false");
    return env->NewStringUTF(buf);
}

}  // extern "C"
