/**
 * @file rac_static_register_metalrt.cpp
 * @brief One-line shim: opt-in static registration of the MetalRT engine
 *        plugin at process start.
 *
 * Routes through `rac_backend_metalrt_register()` (not the bare
 * `RAC_STATIC_PLUGIN_REGISTER(metalrt)` macro) because the MetalRT register
 * function performs extra bookkeeping beyond `rac_plugin_register`:
 *   1. Emits a single startup warning when the closed-source engine binary
 *      (`libmetalrt_engine.a`) is NOT linked — i.e. when
 *      `RAC_METALRT_ENGINE_AVAILABLE` is OFF — so operators understand why
 *      `loadModel(framework: .metalrt)` will surface BACKEND_UNAVAILABLE.
 *   2. Calls `rac_plugin_register(rac_plugin_entry_metalrt())` (only when the
 *      real engine is linked).
 * Using the bare macro would drop the stub-mode warning in step (1).
 *
 * Build-layout note: MetalRT is an OBJECT library whose .o files are folded
 * into `rac_commons` (see `engines/metalrt/CMakeLists.txt`). Adding this TU
 * to `rac_commons` via `target_sources(rac_commons PRIVATE ...)` ensures the
 * file-scope ctor lands in the same translation unit set and runs before
 * main() on iOS / WASM hosts where dlopen is not available.
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
RAC_STATIC_REGISTER_BACKEND(metalrt);
#endif  // RAC_PLUGIN_MODE_STATIC
