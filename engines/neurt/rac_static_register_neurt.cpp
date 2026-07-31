/**
 * @file rac_static_register_neurt.cpp
 * @brief One-line shim: opt-in static registration of the `neurt` engine
 *        plugin at process start.
 *
 * Mirrors `rac_static_register_llamacpp.cpp`. The neurt engine has no custom
 * `rac_backend_neurt_register()` fn, so this uses RAC_STATIC_PLUGIN_REGISTER
 * (which calls the entry directly) rather than RAC_STATIC_REGISTER_BACKEND.
 * Hosts that cannot use the static ctor register the entry themselves —
 * `rac_plugin_register(rac_plugin_entry_neurt())` — which is what rcli,
 * the Electron addon and the Python module all do.
 * Two compile paths:
 *   - RAC_PLUGIN_MODE_STATIC (iOS / WASM hosts or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`): expands
 *     `RAC_STATIC_PLUGIN_REGISTER(neurt)`, scheduling a file-scope ctor that
 *     calls `rac_plugin_register(rac_plugin_entry_neurt())` before main(). The
 *     host must keep this TU alive via the `rac_force_load` helper from
 *     `cmake/plugins.cmake`.
 *   - RAC_PLUGIN_MODE_SHARED (default desktop): this TU is the carrier
 *     library's entry-symbol re-export. The host loads
 *     `librunanywhere_neurt.{dylib,so}` at runtime via
 *     `rac_registry_load_plugin()`, which dlsyms `rac_plugin_entry_neurt` from
 *     the engine impl library linked into the carrier.
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(neurt);
#endif
