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
// engines-sherpa-005: route through rac_backend_sherpa_register() instead of
// the plain RAC_STATIC_PLUGIN_REGISTER(sherpa) macro so the static-linkage
// path populates both the module record (rac_module_register, which backs
// rac_module_get_info("sherpa", ...)) and the unified plugin registry
// (rac_plugin_register). The macro alone only performed the plugin half, so
// iOS/WASM hosts reported the sherpa module as not-found via the module
// registry surface even though primitives routed correctly. The explicit
// register fn is idempotent (returns MODULE_ALREADY_REGISTERED on repeat),
// matches the header doc that promises "static-link hosts also route
// through this function", and keeps the dynamic-link path (SDK bridge
// calls rac_backend_sherpa_register() directly) symmetric.
namespace rac_static_sherpa {
struct Registrar {
    Registrar() noexcept { (void)::rac_backend_sherpa_register(); }
};
#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
static Registrar g_registrar;
}

// Keep the per-plugin externally visible marker symbol the linker uses to
// retain the TU when the host invokes `-force_load` by file rather than
// `--whole-archive`. Mirrors the marker that RAC_STATIC_PLUGIN_REGISTER
// would have emitted (`rac_plugin_static_marker_sherpa`).
extern "C"
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((used))
#endif
        const char *const rac_plugin_static_marker_sherpa = "sherpa";
#endif
