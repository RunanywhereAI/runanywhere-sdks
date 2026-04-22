/**
 * @file rac_static_register_llamacpp.cpp
 * @brief One-line shim: opt-in static registration of the llama.cpp engine
 *        plugin at process start.
 *
 * GAP 03 Phase 5 — see v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU expands the
 *     `RAC_STATIC_PLUGIN_REGISTER(llamacpp)` macro, which schedules a
 *     file-scope ctor to call `rac_plugin_register(rac_plugin_entry_llamacpp())`
 *     before main(). The host MUST also tell the linker not to drop this TU
 *     from the static archive (see rac_plugin_entry.h header doc on
 *     `-force_load` / `--whole-archive`).
 *   - When `RAC_PLUGIN_MODE_SHARED` is set (default desktop / Android), this
 *     TU is the shared library's entry-symbol carrier. The host loads the
 *     library at runtime via `rac_registry_load_plugin()`, which calls
 *     `rac_plugin_entry_llamacpp()` directly via dlsym; no static-init
 *     registration is needed (and would in fact be wasteful because dedup
 *     would reject the second registration).
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(llamacpp);
#endif
