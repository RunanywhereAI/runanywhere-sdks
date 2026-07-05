/**
 * @file rac_static_register_cloud.cpp
 * @brief One-line shim: opt-in static registration of the generic cloud engine
 *        plugin at process start.
 *
 * Routes through `rac_backend_cloud_register()` so the static-linkage path runs
 * the full backend register fn (unified plugin registration via
 * `rac_plugin_register` plus its idempotency bookkeeping), staying symmetric
 * with the dynamic-link path where the SDK bridge calls the register fn
 * directly. The register fn is idempotent on repeat calls.
 *
 * Compile-time behavior:
 *   - When `RAC_PLUGIN_MODE_STATIC` is set (iOS / WASM hosts, or
 *     `cmake -DRAC_STATIC_PLUGINS=ON`), this TU schedules a file-scope ctor to
 *     call `rac_backend_cloud_register()` before main(). The host MUST also
 *     tell the linker not to drop this TU from the static archive (see
 *     rac_plugin_entry.h header doc on `-force_load` / `--whole-archive`).
 *   - When `RAC_PLUGIN_MODE_SHARED` is set (default desktop / Android), this
 *     TU is the shared library's entry-symbol carrier. The host loads the
 *     library at runtime via `rac_registry_load_plugin()`, which calls
 *     `rac_plugin_entry_cloud()` directly via dlsym; no static-init
 *     registration is needed.
 */

#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_cloud.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_REGISTER_BACKEND(cloud);
#endif
