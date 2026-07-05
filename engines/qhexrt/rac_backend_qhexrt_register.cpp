/**
 * @file rac_backend_qhexrt_register.cpp
 * @brief Explicit registration entry for the QHexRT engine plugin.
 *
 * `rac_backend_qhexrt_register()` is the single symbol the platform SDKs invoke
 * to make QHexRT routable: Kotlin via its JNI bridge, Flutter via dart:ffi
 * lookup, React Native via the Nitro HybridObject. It registers the unified
 * vtable returned by `rac_plugin_entry_qhexrt()` and is idempotent, so the
 * static-init path (RAC_STATIC_REGISTER_BACKEND) and the dynamic path agree.
 *
 * On stub builds (engine archive absent) the entry's capability_check rejects
 * registration with RAC_ERROR_BACKEND_UNAVAILABLE, which is surfaced here so the
 * caller can fall back to CPU inference.
 */

#include <mutex>

#include "qhexrt_bundle_policy.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/device/rac_npu_capability.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" RAC_PLUGIN_ENTRY_DECL(qhexrt);

namespace {
const char* LOG_CAT = "QHexRT";
std::mutex g_mutex;
bool g_registered = false;
}  // namespace

extern "C" {

rac_result_t rac_backend_qhexrt_register(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_registered) {
        return RAC_SUCCESS;
    }
    // Bundle policy: how commons resolves HNPU folder bundles (manifest
    // selection, QNN_CONTEXT format) for one-line HF registrations. Inert
    // metadata, so it registers BEFORE the arch gate — deterministic on
    // stub builds and unsupported devices alike.
    rac_bundle_policy_register(qhexrt_bundle_policy());
    // Arch gate: only register on a Hexagon v75+ part. On unsupported
    // devices QHexRT cannot run, and registering its providers would make the
    // router select QHexRT for *all* LLM/VLM/STT/TTS loads (intercepting
    // llamacpp / onnx / genie models and failing them). Refuse here so the
    // platform SDKs fall back to the CPU engines. (qhexrt_supported is false on
    // non-Snapdragon / non-Android and on older Hexagon parts.)
    rac_npu_info_t npu;
    const rac_result_t probe_rc = rac_npu_probe(&npu);
    if (probe_rc != RAC_SUCCESS) {
        RAC_LOG_WARNING(LOG_CAT, "QHexRT not registered: NPU probe failed (%d)", probe_rc);
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    if (npu.qhexrt_supported != RAC_TRUE) {
        RAC_LOG_WARNING(LOG_CAT,
                        "QHexRT not registered: Hexagon %s is unsupported (requires v75+)",
                        rac_hexagon_arch_name(npu.hexagon_arch));
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    const rac_engine_vtable_t* vt = rac_plugin_entry_qhexrt();
    if (vt == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "rac_plugin_entry_qhexrt() returned NULL");
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_PLUGIN_DUPLICATE) {
        RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register(qhexrt) failed: %d", rc);
        return rc;
    }
    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "QHexRT backend registered");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_qhexrt_unregister(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_registered) {
        return RAC_SUCCESS;
    }
    rac_plugin_unregister("qhexrt");
    rac_bundle_policy_unregister(RAC_FRAMEWORK_QHEXRT);
    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
