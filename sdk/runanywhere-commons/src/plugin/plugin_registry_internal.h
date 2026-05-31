/**
 * @file plugin_registry_internal.h
 * @brief Internal coupling between the unified plugin registry and the
 *        dynamic loader.
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
 * Associate a `dlopen` handle with a registered plugin name. Called by the
 * loader immediately after `rac_plugin_register` succeeds. Replaces any
 * previously-stored handle for the same name (the previous one's `dlclose`
 * is the caller's responsibility).
 *
 * Pass `handle = NULL` to clear the association without unregistering.
 */
void rac_plugin_registry_set_dl_handle(const char* name, void* handle) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * Pop the dlopen handle associated with `name` (returns `NULL` if there is
 * none, e.g. for statically-registered plugins). Called by `rac_plugin_unregister`
 * so the loader can `dlclose` the right handle exactly once. After this call
 * the registry no longer tracks the handle.
 */
void* rac_plugin_registry_take_dl_handle(const char* name) RAC_PLUGIN_REGISTRY_NOEXCEPT;

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
 * Pin/unpin the vtables snapshotted from the registry against concurrent
 * dynamic unload.
 *
 * `EngineRouter::route` returns a list of raw vtable pointers
 * from `rac_plugin_list` and then dereferences `vt->metadata` AFTER releasing
 * the registry lock. On hosts that allow `rac_registry_unload_plugin`
 * (Android / Linux / macOS dynamic builds) the underlying `.rodata` for those
 * vtables can be `dlclose`d while a router is still reading them, producing a
 * use-after-free.
 *
 * Routers MUST bracket the snapshot/score/sort window with
 * `router_enter()` / `router_exit()`. `rac_registry_unload_plugin` then
 * spin-waits until the in-flight router count drops to zero AFTER the plugin
 * is unregistered but BEFORE the OS library mapping is `dlclose`d, draining
 * any router that already observed the vtable. Statically-linked builds
 * (iOS / WASM) never `dlclose`, so the counter is effectively a no-op there.
 *
 * The counter is process-wide rather than per-plugin: routers don't know
 * which plugins they're going to score until after the snapshot completes,
 * and a single uint32_t spin counter is dramatically simpler than per-vtable
 * refcounts. Per-plugin refcounting is the alternative if a future workload
 * exposes contention on this counter (it scales as plugin-load frequency,
 * which is bounded by app startup).
 */
void rac_plugin_registry_router_enter(void) RAC_PLUGIN_REGISTRY_NOEXCEPT;
void rac_plugin_registry_router_exit(void) RAC_PLUGIN_REGISTRY_NOEXCEPT;
size_t rac_plugin_registry_router_inflight(void) RAC_PLUGIN_REGISTRY_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_REGISTRY_INTERNAL_H */
