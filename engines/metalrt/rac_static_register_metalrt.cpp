/**
 * @file rac_static_register_metalrt.cpp
 * @brief One-line shim: opt-in static registration of the MetalRT engine
 *        plugin at process start.
 *
 * Mirrors `rac_static_register_diffusion_coreml.cpp` / `rac_static_register_llamacpp.cpp`
 * but invokes `rac_backend_metalrt_register()` from the ctor rather than
 * using the `RAC_STATIC_PLUGIN_REGISTER` macro directly. Reason: the MetalRT
 * register function performs additional bookkeeping beyond `rac_plugin_register`:
 *   1. Emits a single startup warning when the closed-source engine binary
 *      (`libmetalrt_engine.a`) is NOT linked — i.e. when
 *      `RAC_METALRT_ENGINE_AVAILABLE` is OFF — so operators understand why
 *      `loadModel(framework: .metalrt)` will surface BACKEND_UNAVAILABLE.
 *   2. Registers a legacy `rac_module_info_t` entry via `rac_module_register`
 *      (only when the real engine is linked).
 *   3. Calls `rac_plugin_register(rac_plugin_entry_metalrt())` (only when
 *      the real engine is linked).
 *
 * Using `RAC_STATIC_PLUGIN_REGISTER(metalrt)` directly would only perform
 * step (3), drop the stub-mode warning, and skip the legacy module-registry
 * entry — leaving the registries inconsistent.
 *
 * Build-layout note: MetalRT is an OBJECT library whose .o files are folded
 * into `rac_commons` (see `engines/metalrt/CMakeLists.txt`). Adding this TU
 * to `rac_commons` via `target_sources(rac_commons PRIVATE ...)` ensures
 * the file-scope ctor lands in the same translation unit set and runs
 * before main() on iOS / WASM hosts where dlopen is not available.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU schedules a file-scope ctor
 *     that calls `rac_backend_metalrt_register()` before main().
 *   - Otherwise the TU expands to nothing.
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_metalrt.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC

extern "C" rac_result_t rac_backend_metalrt_register(void);

namespace rac_plugin_autoreg_metalrt {

struct Registrar {
    Registrar() noexcept {
        // Fire-and-forget. In stub-mode (RAC_METALRT_ENGINE_AVAILABLE=0) the
        // register function emits a single warning and marks the backend as
        // registered without installing a route, so subsequent
        // `loadModel(framework: .metalrt)` surfaces BACKEND_UNAVAILABLE
        // cleanly. In authorized builds it installs the full vtable.
        (void)::rac_backend_metalrt_register();
    }
};

#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
static Registrar g_registrar;

}  // namespace rac_plugin_autoreg_metalrt

// Force at least one externally-visible symbol per plugin so the linker
// can be asked to keep the TU by name without `-force_load`. Mirrors the
// marker emitted by RAC_STATIC_PLUGIN_REGISTER.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
extern "C" const char* const rac_plugin_static_marker_metalrt = "metalrt";

#endif  // RAC_PLUGIN_MODE_STATIC
