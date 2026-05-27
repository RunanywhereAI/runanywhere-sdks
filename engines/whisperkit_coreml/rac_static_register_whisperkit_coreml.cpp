/**
 * @file rac_static_register_whisperkit_coreml.cpp
 * @brief One-line shim: opt-in static registration of the WhisperKit CoreML
 *        engine plugin at process start.
 *
 * Mirrors `rac_static_register_diffusion_coreml.cpp` / `rac_static_register_llamacpp.cpp`
 * but with one difference: WhisperKit CoreML has a hand-written
 * `rac_backend_whisperkit_coreml_register()` function that performs
 * additional bookkeeping beyond `rac_plugin_register`:
 *   1. Verifies Swift-side callbacks are installed via
 *      `rac_whisperkit_coreml_stt_is_available()` and short-circuits with
 *      RAC_ERROR_BACKEND_UNAVAILABLE when they are not.
 *   2. Registers a legacy `rac_module_info_t` entry via `rac_module_register`.
 *   3. Calls `rac_plugin_register(rac_plugin_entry_whisperkit_coreml())`.
 *
 * Using `RAC_STATIC_PLUGIN_REGISTER(whisperkit_coreml)` directly would only
 * perform step (3) and silently skip the availability gate + module-registry
 * entry, leaving callers like the legacy module registry inconsistent with
 * the plugin registry.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU schedules a file-scope ctor
 *     that calls `rac_backend_whisperkit_coreml_register()` before main().
 *     The host MUST also tell the linker not to drop this TU from the
 *     static archive (see `rac_plugin_entry.h` header doc on `-force_load`
 *     / `--whole-archive`); this is handled because the TU is added to
 *     `rac_commons` via `target_sources(rac_commons PRIVATE ...)`.
 *   - Otherwise the TU expands to nothing.
 *
 * NOTE: WhisperKit CoreML's Swift-side callbacks are typically installed
 * after `rac_init` runs (during the Swift SDK's WhisperKit bootstrap). The
 * register function tolerates this — it returns RAC_ERROR_BACKEND_UNAVAILABLE
 * if callbacks are not yet installed at static-init time, and downstream
 * code paths re-attempt registration once Swift wires up the callbacks.
 */

#include "rac/backends/rac_stt_whisperkit_coreml.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_whisperkit_coreml.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC

extern "C" rac_result_t rac_backend_whisperkit_coreml_register(void);

namespace rac_plugin_autoreg_whisperkit_coreml {

struct Registrar {
    Registrar() noexcept {
        // Fire and forget — the register function returns
        // RAC_ERROR_BACKEND_UNAVAILABLE when Swift-side callbacks have not
        // been installed yet, which is expected at static-init time. The
        // Swift WhisperKit bootstrap re-invokes registration later via its
        // own bridge path; this static ctor is the iOS Release fallback for
        // builds where the Swift bootstrap has been short-circuited.
        (void)::rac_backend_whisperkit_coreml_register();
    }
};

#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
static Registrar g_registrar;

}  // namespace rac_plugin_autoreg_whisperkit_coreml

// Force at least one externally-visible symbol per plugin so the linker
// can be asked to keep the TU by name without `-force_load`. Mirrors the
// marker emitted by RAC_STATIC_PLUGIN_REGISTER.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((used))
#endif
extern "C" const char* const rac_plugin_static_marker_whisperkit_coreml = "whisperkit_coreml";

#endif  // RAC_PLUGIN_MODE_STATIC
