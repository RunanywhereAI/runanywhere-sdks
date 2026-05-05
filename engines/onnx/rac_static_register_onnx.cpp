/**
 * @file rac_static_register_onnx.cpp
 * @brief One-line shim: opt-in static registration of the ONNX engine plugin
 *        at process start.
 *
 * ENG-SHERPA-03 — parallel to engines/llamacpp/rac_static_register_llamacpp.cpp
 * and engines/sherpa/rac_static_register_sherpa.cpp. Standardizes backend
 * registration so all three active backends use the same explicit-register
 * + static-shim pattern.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU expands the
 *     `RAC_STATIC_PLUGIN_REGISTER(onnx)` macro, which schedules a
 *     file-scope ctor to call `rac_plugin_register(rac_plugin_entry_onnx())`
 *     before main(). The host MUST also tell the linker not to drop this TU
 *     from the static archive (see rac_plugin_entry.h header doc on
 *     `-force_load` / `--whole-archive`).
 *   - When `RAC_PLUGIN_MODE_SHARED` is set (default desktop / Android), this
 *     TU is the shared library's entry-symbol carrier. The host loads the
 *     library at runtime via `rac_registry_load_plugin()`, which calls
 *     `rac_plugin_entry_onnx()` directly via dlsym; no static-init
 *     registration is needed (and would in fact be wasteful because dedup
 *     would reject the second registration).
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(onnx);
#endif
