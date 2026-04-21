/**
 * @file plugin_registry_internal.h
 * @brief Internal coupling between the unified plugin registry and the
 *        dynamic loader (GAP 03).
 *
 * The PUBLIC ABI lives in `rac/plugin/rac_plugin_loader.h`. This header is
 * intentionally not installed; only the two internal TUs
 * (`rac_plugin_registry.cpp`, `plugin_loader.cpp`) include it. Keeps the
 * `dlopen` handle map private to commons while letting both files agree on
 * the bookkeeping signatures.
 */

#ifndef RAC_PLUGIN_REGISTRY_INTERNAL_H
#define RAC_PLUGIN_REGISTRY_INTERNAL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Associate a `dlopen` handle with a registered plugin name. Called by the
 * loader immediately after `rac_plugin_register` succeeds. Replaces any
 * previously-stored handle for the same name (the previous one's `dlclose`
 * is the caller's responsibility).
 *
 * Pass `handle = NULL` to clear the association without unregistering.
 */
void rac_plugin_registry_set_dl_handle(const char* name, void* handle);

/**
 * Pop the dlopen handle associated with `name` (returns `NULL` if there is
 * none, e.g. for statically-registered plugins). Called by `rac_plugin_unregister`
 * so the loader can `dlclose` the right handle exactly once. After this call
 * the registry no longer tracks the handle.
 */
void* rac_plugin_registry_take_dl_handle(const char* name);

/**
 * Snapshot the names of every currently-registered plugin into `out_names`
 * (heap-allocated `strdup`s, caller frees with `free()` per entry + `free()`
 * on the array). Returns the count via `out_count`. Caller passes the desired
 * count cap; the registry truncates if it has more.
 */
size_t rac_plugin_registry_snapshot_names(const char*** out_names);

#ifdef __cplusplus
}
#endif

#endif  /* RAC_PLUGIN_REGISTRY_INTERNAL_H */
