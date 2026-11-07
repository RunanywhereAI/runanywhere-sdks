/**
 * @file rac_backend_litertlm_register.cpp
 * @brief Explicit registration of the LiteRT-LM engine plugin.
 *
 * Idempotent, so the static-init path and the SDK bridges agree. On a build
 * without the prebuilt library the entry's capability_check rejects
 * registration with RAC_ERROR_BACKEND_UNAVAILABLE, which is returned to the
 * caller.
 */

#include "rac_litertlm.h"

#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_registration.h"

extern "C" RAC_PLUGIN_ENTRY_DECL(litertlm);

namespace {
const char* LOG_CAT = "LiteRTLM";
std::mutex g_mutex;
bool g_registered = false;
}  // namespace

extern "C" {

rac_result_t rac_backend_litertlm_register(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_registered) {
        return RAC_SUCCESS;
    }
    const rac_engine_vtable_t* vtable = rac_plugin_entry_litertlm();
    if (vtable == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    const rac_result_t rc = rac_plugin_register(vtable);
    if (!rac_plugin_registration_succeeded(rc)) {
        RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register(litertlm) failed: %d", rc);
        return rc;
    }
    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "LiteRT-LM backend registered");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_litertlm_unregister(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_registered) {
        const rac_result_t rc = rac_plugin_unregister("litertlm");
        RAC_PLUGIN_UNREGISTER_BUSY_CHECK("litertlm", rc);
        g_registered = false;
    }
    return RAC_SUCCESS;
}

rac_bool_t rac_backend_litertlm_is_registered(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_registered ? RAC_TRUE : RAC_FALSE;
}

}  // extern "C"
