/**
 * @file rac_backend_cloud_register.cpp
 * @brief Explicit registration of the generic cloud engine plugin.
 *
 * Mirrors the sherpa / onnx / llamacpp pattern: one idempotent
 * `rac_backend_cloud_register()` entry point that registers the unified plugin
 * vtable with the plugin registry via `rac_plugin_register`. There is NO module
 * registry (it was deleted in plugin API v3) — registration is the single
 * `rac_plugin_register(rac_plugin_entry_cloud())` call.
 *
 * Dynamic-linkage hosts (Android, Linux, macOS dev) call this from the SDK
 * bridge (CloudBridge.nativeRegister → RAC_DEFINE_ENGINE_JNI_BRIDGE).
 * Static-linkage hosts (iOS / WASM, RAC_STATIC_PLUGINS=ON) route through it via
 * RAC_STATIC_REGISTER_BACKEND(cloud); see rac_static_register_cloud.cpp.
 */

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_cloud.h"

namespace {

const char* LOG_CAT = "Cloud";

bool g_cloud_registered = false;

}  // namespace

extern "C" {

rac_result_t rac_backend_cloud_register(void) {
    if (g_cloud_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_cloud();
    if (vt != nullptr) {
        rac_result_t plugin_rc = rac_plugin_register(vt);
        if (plugin_rc != RAC_SUCCESS && plugin_rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register failed: %d", plugin_rc);
        } else {
            RAC_LOG_INFO(LOG_CAT, "rac_plugin_register succeeded for 'cloud'");
        }
    }

    g_cloud_registered = true;
    RAC_LOG_INFO(LOG_CAT, "Cloud backend registered (plugin)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_cloud_unregister(void) {
    if (!g_cloud_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_plugin_unregister("cloud");

    g_cloud_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
