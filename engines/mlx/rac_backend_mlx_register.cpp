/**
 * @file rac_backend_mlx_register.cpp
 * @brief Explicit registration entry for the MLX engine plugin.
 */

#include <mutex>

#include "mlx_bundle_policy.h"

#include "rac/backends/rac_mlx.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_mlx.h"

#define LOG_CAT "MLX"

namespace {

std::mutex g_mutex;
bool g_registered = false;

}  // namespace

extern "C" {

rac_result_t rac_backend_mlx_register(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_registered) {
        return RAC_SUCCESS;
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_mlx();
    if (vt == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "rac_plugin_entry_mlx() returned NULL");
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    rac_result_t rc = rac_plugin_register(vt);
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_PLUGIN_DUPLICATE) {
        RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register(mlx) failed: %d", rc);
        return rc;
    }
    rac_bundle_policy_register(mlx_bundle_policy());
    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "MLX backend registered");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_mlx_unregister(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_registered) {
        return RAC_SUCCESS;
    }
    rac_plugin_unregister("mlx");
    rac_bundle_policy_unregister(RAC_FRAMEWORK_MLX);
    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
