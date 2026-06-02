/**
 * @file rac_static_register_llamacpp.cpp
 * @brief One-line shim: opt-in static registration of the llama.cpp engine
 *        plugin at process start.
 *
 * Routes through `rac_backend_llamacpp_register()` (not the bare
 * `RAC_STATIC_PLUGIN_REGISTER(llamacpp)` macro) so the static-linkage path runs
 * the full backend bring-up — CPU-runtime provider hookup + unified plugin
 * registration via `rac_plugin_register` — and stays symmetric with the
 * dynamic-link path where the SDK bridge calls `rac_backend_llamacpp_register()`
 * directly. The register fn is idempotent on repeat calls.
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
RAC_STATIC_REGISTER_BACKEND(llamacpp);
#endif
