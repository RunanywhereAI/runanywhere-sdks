/**
 * @file rac_static_register_llamacpp.cpp
 * @brief One-line shim: opt-in static registration of the llama.cpp engine
 *        plugin at process start.
 *
 * GAP 03 Phase 5 — see v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU schedules a file-scope ctor to
 *     call `rac_backend_llamacpp_register()` before main(). The host MUST also
 *     tell the linker not to drop this TU from the static archive (see
 *     rac_plugin_entry.h header doc on `-force_load` / `--whole-archive`).
 *   - When `RAC_PLUGIN_MODE_SHARED` is set (default desktop / Android), this
 *     TU is the shared library's entry-symbol carrier. The host loads the
 *     library at runtime via `rac_registry_load_plugin()`, which calls
 *     `rac_plugin_entry_llamacpp()` directly via dlsym; no static-init
 *     registration is needed (and would in fact be wasteful because dedup
 *     would reject the second registration).
 */

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
// engines-009: route through rac_backend_llamacpp_register() instead of the
// plain RAC_STATIC_PLUGIN_REGISTER(llamacpp) macro so the static-linkage path
// populates both the module record (rac_module_register, which backs
// rac_module_get_info("llamacpp", ...)) and the unified plugin registry
// (rac_plugin_register). The macro alone only performed the plugin half, so
// iOS/WASM hosts reported the llamacpp module as not-found via the module
// registry surface even though primitives routed correctly. The explicit
// register fn is idempotent (returns MODULE_ALREADY_REGISTERED on repeat),
// matches the header doc that promises "static-link hosts also route through
// this function", and keeps the dynamic-link path (SDK bridge calls
// rac_backend_llamacpp_register() directly) symmetric. Mirrors the sherpa
// shim in engines/sherpa/rac_static_register_sherpa.cpp.
namespace rac_static_llamacpp {
struct Registrar {
    Registrar() noexcept { (void)::rac_backend_llamacpp_register(); }
};
#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
static Registrar g_registrar;
}  // namespace rac_static_llamacpp

// Keep the per-plugin externally visible marker symbol the linker uses to
// retain the TU when the host invokes `-force_load` by file rather than
// `--whole-archive`. Mirrors the marker that RAC_STATIC_PLUGIN_REGISTER
// would have emitted (`rac_plugin_static_marker_llamacpp`).
extern "C"
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((used))
#endif
    const char* const rac_plugin_static_marker_llamacpp = "llamacpp";
#endif
