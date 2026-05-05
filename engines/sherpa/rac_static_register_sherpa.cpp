/**
 * @file rac_static_register_sherpa.cpp
 * @brief One-line shim: opt-in static registration of the Sherpa-ONNX engine
 *        plugin at process start.
 *
 * ENG-SHERPA-03 — parallel to engines/llamacpp/rac_static_register_llamacpp.cpp
 * and engines/onnx/rac_static_register_onnx.cpp. Standardizes backend
 * registration so all three active backends use the same explicit-register
 * + static-shim pattern (the former ELF ctor at the bottom of
 * rac_plugin_entry_sherpa.cpp has been deleted).
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU expands the
 *     `RAC_STATIC_PLUGIN_REGISTER(sherpa)` macro, which schedules a
 *     file-scope ctor to call `rac_plugin_register(rac_plugin_entry_sherpa())`
 *     before main(). The host MUST also tell the linker not to drop this TU
 *     from the static archive (see rac_plugin_entry.h header doc on
 *     `-force_load` / `--whole-archive`).
 *   - When `RAC_PLUGIN_MODE_SHARED` is set (default desktop / Android), this
 *     TU is the shared library's entry-symbol carrier. The host loads the
 *     library at runtime via `rac_registry_load_plugin()`, which calls
 *     `rac_plugin_entry_sherpa()` directly via dlsym; no static-init
 *     registration is needed (and would in fact be wasteful because dedup
 *     would reject the second registration).
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(sherpa);
#endif
