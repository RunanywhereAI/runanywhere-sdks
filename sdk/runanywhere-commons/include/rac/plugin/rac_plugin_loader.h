/**
 * @file rac_plugin_loader.h
 * @brief Dynamic plugin loader — `dlopen` path for desktop / Android / Linux /
 *        Windows hosts that are NOT statically linking plugins.
 *
 * GAP 03 Phase 1 — see v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md.
 *
 * Layered on top of the GAP 02 plugin registry (`rac_plugin_register`,
 * `rac_plugin_find`). The loader's job is purely to resolve a shared library
 * file into a `const rac_engine_vtable_t*` and hand it to the registry —
 * the registry still owns ABI validation, capability_check, and dedup.
 *
 * On iOS / WebAssembly, where `dlopen` is banned or unavailable, plugins are
 * compile-time linked via `RAC_STATIC_PLUGIN_REGISTER(name)` from
 * `rac_plugin_entry.h`. This header still compiles on those platforms; the
 * `rac_registry_load_plugin*` functions return
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE` rather than failing to link.
 *
 * Symbol-resolution convention:
 *   `librunanywhere_<name>.so`        → looks up `rac_plugin_entry_<name>`
 *   `runanywhere_<name>.dll`          → same
 *   `librunanywhere_<name>.dylib`     → same
 * The stem is parsed by stripping the platform-specific `lib*` prefix and
 * the file extension, so a plugin author only needs to (a) name their
 * `RAC_PLUGIN_ENTRY_DEF(<name>)` to match the library stem and (b) ensure
 * the entry symbol has C linkage and default visibility.
 */

#ifndef RAC_PLUGIN_LOADER_H
#define RAC_PLUGIN_LOADER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Compile-time plugin API version this build of `rac_commons` supports.
 *
 * Same value as `RAC_PLUGIN_API_VERSION` in `rac_plugin_entry.h`. Exposed as a
 * runtime function so loaders, frontends, and third-party tooling can ask the
 * commons binary for its version without `#include`-ing the C++ macro header.
 */
RAC_API uint32_t rac_plugin_api_version(void);

/**
 * @brief Load a shared library, resolve its `rac_plugin_entry_<stem>` symbol,
 *        and register the returned vtable with the plugin registry.
 *
 * @param path Absolute or relative path to the shared library
 *             (`*.so` / `*.dylib` / `*.dll`). Must NOT be NULL.
 *
 * @return RAC_SUCCESS on accept, or:
 *   - RAC_ERROR_NULL_POINTER             - `path` is NULL
 *   - RAC_ERROR_PLUGIN_LOAD_FAILED       - `dlopen` / `dlsym` failed
 *   - RAC_ERROR_ABI_VERSION_MISMATCH     - vtable abi_version != host's
 *   - RAC_ERROR_CAPABILITY_UNSUPPORTED   - plugin's `capability_check()` declined
 *   - RAC_ERROR_PLUGIN_DUPLICATE         - same `metadata.name` already registered with higher priority
 *   - RAC_ERROR_FEATURE_NOT_AVAILABLE    - host built with RAC_STATIC_PLUGINS=ON
 *
 * On any failure, the underlying handle is `dlclose`'d before return.
 *
 * Thread-safe.
 */
RAC_API rac_result_t rac_registry_load_plugin(const char* path);

/**
 * @brief Unregister a plugin by name. If the plugin was loaded via
 *        `rac_registry_load_plugin`, the underlying `dlopen` handle is
 *        `dlclose`'d. Statically registered plugins are accepted but the
 *        underlying TU stays linked.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, RAC_ERROR_NOT_FOUND, or
 *         RAC_ERROR_PLUGIN_BUSY (when reference-counted sessions still hold
 *         the plugin — wired in GAP 04+).
 *
 * Thread-safe.
 */
RAC_API rac_result_t rac_registry_unload_plugin(const char* name);

/**
 * @brief Total number of plugins currently registered (across all primitives,
 *        counting each plugin once).
 *
 * Equivalent to `rac_plugin_count()` in `rac_plugin_entry.h` — exposed here
 * for symmetry with the loader API surface.
 */
RAC_API size_t rac_registry_plugin_count(void);

/**
 * @brief Snapshot the names of currently-registered plugins.
 *
 * Allocates an array of `out_count` C-strings. Caller MUST free with
 * `rac_registry_free_plugin_list()`. Returns RAC_SUCCESS even when no plugins
 * are registered (`*out_count = 0`, `*out_names = NULL`).
 */
RAC_API rac_result_t rac_registry_list_plugins(const char*** out_names, size_t* out_count);

/**
 * @brief Free the array returned by `rac_registry_list_plugins`.
 */
RAC_API void rac_registry_free_plugin_list(const char** names, size_t count);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_LOADER_H */
