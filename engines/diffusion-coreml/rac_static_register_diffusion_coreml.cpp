/**
 * @file rac_static_register_diffusion_coreml.cpp
 * @brief One-line shim: opt-in static registration of the diffusion-coreml
 *        engine plugin at process start.
 *
 * Mirrors `rac_static_register_llamacpp.cpp`. Two compile paths:
 *   - RAC_PLUGIN_MODE_STATIC (iOS / WASM hosts or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`): expands
 *     `RAC_STATIC_PLUGIN_REGISTER(diffusion_coreml)`, scheduling a
 *     file-scope ctor that calls
 *     `rac_plugin_register(rac_plugin_entry_diffusion_coreml())` before
 *     main(). The host must keep this TU alive via the `rac_force_load`
 *     helper from `cmake/plugins.cmake`.
 *   - RAC_PLUGIN_MODE_SHARED (default desktop): this TU is the carrier
 *     library's entry-symbol re-export. The host loads
 *     `librunanywhere_diffusion_coreml.{dylib,so}` at runtime via
 *     `rac_registry_load_plugin()`, which dlsyms
 *     `rac_plugin_entry_diffusion_coreml` from the engine impl library
 *     linked into the carrier.
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_diffusion_coreml.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(diffusion_coreml);
#endif
