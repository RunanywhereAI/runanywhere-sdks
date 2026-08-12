/**
 * @file rac_plugin_loader.h
 * @brief Dynamic plugin loader — `dlopen` path for desktop / Android / Linux /
 *        Windows hosts that are NOT statically linking plugins.
 *
 * Layered on top of the plugin registry (`rac_plugin_register`,
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
 *   - RAC_ERROR_PLUGIN_DUPLICATE         - same `metadata.name` already registered with higher
 * priority
 *   - RAC_ERROR_FEATURE_NOT_AVAILABLE    - host built with RAC_STATIC_PLUGINS=ON
 *
 * On any failure, the underlying handle is `dlclose`'d before return.
 *
 * Thread-safe.
 */
RAC_API rac_result_t rac_registry_load_plugin(const char* path);

/**
 * @brief Load a batch of plugin paths, isolating each one's failure.
 *
 * The all-or-nothing alternative — a caller looping over
 * `rac_registry_load_plugin` and bailing on the first non-success — turns one
 * broken backend into a dead SDK: `rac_init` is never reached and every
 * feature, including the ones served by the backends that DID load, becomes
 * unreachable. That is a packaging accident (a mis-built plugin) escalated
 * into a total outage, and it is the reason this entry point exists.
 *
 * Every path is attempted. A path that fails is logged and recorded in the
 * unavailability ledger (see `rac_registry_list_unavailable_plugins`); the
 * loop continues to the next one. `RAC_ERROR_PLUGIN_DUPLICATE` counts as
 * loaded — the plugin is in the registry, which is what the caller asked for.
 *
 * @param paths      Array of `count` library paths. NULL/empty entries are skipped.
 * @param count      Number of entries in `paths`.
 * @param out_loaded Optional; receives how many plugins are now registered as
 *                   a result of this call.
 *
 * @return RAC_SUCCESS whenever the arguments are well-formed — INCLUDING the
 *         case where every plugin failed. "Which backends are missing" is a
 *         capability question the caller answers through the ledger, not an
 *         initialization error. Returns RAC_ERROR_NULL_POINTER only when
 *         `paths` is NULL with a non-zero `count`.
 *
 * Thread-safe.
 */
RAC_API rac_result_t rac_registry_load_plugins(const char* const* paths, size_t count,
                                               size_t* out_loaded);

/**
 * @brief One backend that asked to join the registry and was refused.
 *
 * Produced by the loader (`dlopen`/`dlsym` failure) and by the registry
 * (ABI mismatch, `capability_check` decline, manifest validation failure), so
 * a single query answers "what can this build NOT do, and why" regardless of
 * whether the plugin was dynamic or statically registered.
 */
typedef struct rac_plugin_unavailable {
    /** Engine name when known, else the library stem parsed from the path. Never NULL. */
    const char* name;
    /** Library path for loader-originated failures; NULL for static registrations. */
    const char* path;
    /** Why it was refused — the same code the failing call returned. */
    rac_result_t status;
} rac_plugin_unavailable_t;

/**
 * @brief Record a backend as unavailable.
 *
 * For SDKs that call a backend's `rac_backend_<x>_register()` directly rather
 * than going through the loader: pass the non-success result here so the
 * failure reaches the same capability surface as a dynamic load failure
 * instead of being dropped on the floor.
 *
 * A later successful registration of the same `name` clears the entry, so the
 * ledger never reports a backend that is actually serving. Passing
 * `RAC_SUCCESS` clears the entry too.
 *
 * Thread-safe. Never allocates on the caller's behalf; a NULL `name` is a
 * no-op.
 */
RAC_API void rac_registry_record_plugin_unavailable(const char* name, const char* path,
                                                    rac_result_t status);

/**
 * @brief Snapshot every backend currently recorded as unavailable.
 *
 * Allocates an array of `out_count` entries whose strings the entries own.
 * Caller MUST free with `rac_registry_free_unavailable_plugins()`. Returns
 * RAC_SUCCESS with `*out_count = 0` and `*out_items = NULL` when everything
 * that tried to register succeeded.
 */
RAC_API rac_result_t rac_registry_list_unavailable_plugins(rac_plugin_unavailable_t** out_items,
                                                           size_t* out_count);

/**
 * @brief Free the array returned by `rac_registry_list_unavailable_plugins`.
 */
RAC_API void rac_registry_free_unavailable_plugins(rac_plugin_unavailable_t* items, size_t count);

/**
 * @brief Unregister a plugin by name. If the plugin was loaded via
 *        `rac_registry_load_plugin`, the underlying `dlopen` handle is
 *        `dlclose`'d. Statically registered plugins are accepted but the
 *        underlying TU stays linked.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, RAC_ERROR_NOT_FOUND, or
 *         RAC_ERROR_PLUGIN_BUSY (when reference-counted sessions still hold
 *         the plugin).
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
