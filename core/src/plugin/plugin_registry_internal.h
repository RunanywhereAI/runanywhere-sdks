/**
 * @file plugin_registry_internal.h
 * @brief Internal coupling between the unified plugin registry and the
 *        dynamic loader.
 *
 * The PUBLIC ABI lives in `rac/plugin/rac_plugin_loader.h`. This header is
 * intentionally not installed. The registry, loader and segmentation service
 * use it to keep library bookkeeping and model leases private to commons.
 */

#ifndef RAC_PLUGIN_REGISTRY_INTERNAL_H
#define RAC_PLUGIN_REGISTRY_INTERNAL_H

#include <stddef.h>

#include "rac/plugin/rac_engine_manifest.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Internal C ABI surface — same noexcept rationale as the public surface in
 * rac/plugin/rac_plugin_entry.h. RAC_PLUGIN_REGISTRY_NOEXCEPT expands to
 * `noexcept` under C++ and nothing under plain C. The macro may already be
 * defined by rac_plugin_entry.h; guarded so both inclusions work. */
#ifndef RAC_PLUGIN_REGISTRY_NOEXCEPT
#ifdef __cplusplus
#define RAC_PLUGIN_REGISTRY_NOEXCEPT noexcept
#else
#define RAC_PLUGIN_REGISTRY_NOEXCEPT
#endif
#endif

/**
 * Register a dynamic plugin and transfer its OS handle under the registry lock.
 * On success, the registry owns `handle` and returns the replaced handle (if any)
 * through `out_previous_handle`; the loader closes it after the unload callback.
 * On failure, the caller retains `handle` and no handle ownership is transferred.
 */
rac_result_t
rac_plugin_registry_register_dynamic(const rac_engine_vtable_t* vtable, void* handle,
                                     void** out_previous_handle) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/** Atomically remove an idle plugin and return its OS handle to the loader.
 * A model lease returns RAC_ERROR_PLUGIN_BUSY without removing any state.
 */
rac_result_t rac_plugin_registry_unregister(const char* name,
                                            void** out_dl_handle) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/** Pin an accepted vtable by pointer identity without dereferencing stale data.
 * The returned manifest remains valid until the matching release. */
rac_result_t rac_plugin_registry_acquire(const rac_engine_vtable_t* vtable,
                                         const rac_engine_manifest_t** out_manifest)
    RAC_PLUGIN_REGISTRY_NOEXCEPT;
void rac_plugin_registry_release(const rac_engine_vtable_t* vtable) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * Snapshot the names of every currently-registered plugin into `out_names`
 * (heap-allocated copies via the portable `rac_strdup` helper; caller frees
 * each entry with `free()` then the array with `free()`). Returns the count
 * via the function's return value. On allocator failure the function rolls
 * back every entry already duplicated, leaves `*out_names == NULL` and
 * returns 0 — the caller never sees a partial array with NULL slots.
 */
size_t rac_plugin_registry_snapshot_names(const char*** out_names) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * Drop `name` from the unavailability ledger (`plugin_availability.cpp`).
 * Called by the registry the moment a plugin registers successfully, so a
 * backend that failed once and then loaded is not still reported as missing.
 *
 * The recording half of this pair is public
 * (`rac_registry_record_plugin_unavailable` in `rac/plugin/rac_plugin_loader.h`)
 * because SDKs that call `rac_backend_<x>_register()` directly need it; only
 * the clearing half is internal, since nothing outside commons can know that a
 * registration just succeeded.
 */
void rac_plugin_availability_forget(const char* name) RAC_PLUGIN_REGISTRY_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_REGISTRY_INTERNAL_H */
