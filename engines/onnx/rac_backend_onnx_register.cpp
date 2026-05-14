/**
 * @file rac_backend_onnx_register.cpp
 * @brief ONNX Runtime backend registration for generic ONNX model services.
 */

#include "rac/backends/rac_embeddings_onnx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_entry.h"

namespace {

const char *LOG_CAT = "ONNX";
const char *const MODULE_ID = "onnx";

bool g_registered = false;

} // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_onnx_register(void) {
  if (g_registered) {
    return RAC_ERROR_MODULE_ALREADY_REGISTERED;
  }

  rac_module_info_t module_info = {};
  module_info.id = MODULE_ID;
  module_info.name = "ONNX Runtime";
  module_info.version = "1.0.0";
  module_info.description = "ONNX Runtime backend";
  module_info.capabilities = nullptr;
  module_info.num_capabilities = 0;

  rac_result_t result = rac_module_register(&module_info);
  if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
    return result;
  }

  rac_backend_onnx_embeddings_register();

  // Android-fix: same issue as B-AK-1-001 — on Android the JNI bridges call
  // this `rac_backend_*_register` function but the unified plugin registry
  // is never populated through dlopen+dlsym. Register the plugin entry here
  // so `rac_plugin_route` can find the ONNX-backed STT/TTS/VAD primitives.
  extern const rac_engine_vtable_t *rac_plugin_entry_onnx(void);
  const rac_engine_vtable_t *vt = rac_plugin_entry_onnx();
  if (vt != nullptr) {
    rac_result_t plugin_rc = rac_plugin_register(vt);
    if (plugin_rc != RAC_SUCCESS &&
        plugin_rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register failed: %d", plugin_rc);
    } else {
      RAC_LOG_INFO(LOG_CAT, "rac_plugin_register succeeded for 'onnx'");
    }
  }

  g_registered = true;
  RAC_LOG_INFO(LOG_CAT,
               "ONNX backend registered (module + embeddings + plugin)");
  return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_unregister(void) {
  if (!g_registered) {
    return RAC_ERROR_MODULE_NOT_FOUND;
  }

  rac_backend_onnx_embeddings_unregister();
  rac_module_unregister(MODULE_ID);

  g_registered = false;
  return RAC_SUCCESS;
}

} // extern "C"
