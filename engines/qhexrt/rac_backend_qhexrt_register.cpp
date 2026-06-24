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

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
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
    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
