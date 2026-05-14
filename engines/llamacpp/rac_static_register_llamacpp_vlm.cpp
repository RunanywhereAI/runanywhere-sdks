/**
 * @file rac_static_register_llamacpp_vlm.cpp
 * @brief One-line shim: opt-in static registration of the llama.cpp VLM
 *        engine plugin at process start.
 *
 * Mirrors rac_static_register_llamacpp.cpp for the VLM plugin. The LLM plugin
 * already had a static-register shim; without this equivalent for VLM,
 * rac_plugin_route(framework=llamacpp, primitive=vlm) fails with
 * "no backend route for llamacpp_vlm" even after LlamaCPP.register() has
 * called rac_backend_llamacpp_vlm_register() — because that registers the
 * *module*, not the *plugin vtable*. The plugin-registry route happens via
 * the static ctor below.
 *
 * Swift-only E2E Phase 6e: previously masked by the Phase 6b multi-file
 * download bug + Phase 6a xcframework rebuild; surfaced in the Phase 6c re-run
 * when VLM download started succeeding.
 */

#include "rac/plugin/rac_plugin_entry.h"

extern "C" const rac_engine_vtable_t *rac_plugin_entry_llamacpp_vlm(void);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(llamacpp_vlm);
#endif
