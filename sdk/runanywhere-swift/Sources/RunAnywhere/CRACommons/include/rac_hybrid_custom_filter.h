/**
 * @file rac_hybrid_custom_filter.h
 * @brief Cross-SDK named custom-filter callback table for the hybrid router.
 *
 * A HybridFilter::Custom carries a NAME on the wire. The predicate logic
 * stays host-supplied — each platform binding (Kotlin, Swift, Flutter, RN,
 * Web) registers a named predicate here at policy-install time. Commons then
 * RESOLVES the predicate by name and INVOKES it during candidate filtering,
 * so the custom-filter decision no longer leaks back into the host layer
 * (the host used to toggle router slots around the call — a layering
 * violation this table removes).
 *
 * This mirrors the rac_hybrid_device_state vtable pattern: an active table
 * lives behind a std::atomic; register/unregister publish a fresh immutable
 * snapshot and retire the previous one with a one-generation reprieve for
 * in-flight readers. Unlike device-state (a single vtable), this table holds
 * MANY named entries — register adds/replaces one entry by name, unregister
 * removes one, and lookup scans the published snapshot for a name match.
 *
 * Thread-safety: rac_hybrid_register_custom_filter / *_unregister_custom_filter
 * can be called from any thread; the active snapshot is swapped atomically.
 * The predicate itself may be invoked concurrently from request threads, so
 * implementations must be reentrant.
 *
 * Lifecycle: the predicate is invoked while the binding's user_data is alive.
 * Bindings MUST unregister (by name) before freeing the user_data backing
 * that predicate — there is no native-side reference counting on user_data,
 * and freeing it while a predicate call is in flight is undefined behavior.
 * As with device-state, unregister only retires the previous snapshot one
 * generation later, so bindings that need strict quiescence must add their
 * own synchronization before releasing user_data.
 */

#ifndef RAC_HYBRID_CUSTOM_FILTER_H
#define RAC_HYBRID_CUSTOM_FILTER_H

#include <stddef.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_hybrid_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Maximum length (including the NUL terminator) of a custom-filter
 *        name. Matches rac_hybrid_custom_filter_t::name in rac_hybrid_types.h
 *        so a registered name round-trips through the C filter struct without
 *        truncation surprises.
 */
#define RAC_HYBRID_CUSTOM_FILTER_NAME_MAX 64

/**
 * @brief Host-supplied eligibility predicate.
 *
 * Returns RAC_TRUE iff the candidate described by @p ctx is eligible. Must be
 * thread-safe / reentrant — the router may invoke it concurrently from
 * multiple request threads.
 *
 * @param ctx       Per-request routing context (the candidate model id plus
 *                  the device-state snapshot the router already resolved).
 *                  Never NULL when invoked by the router.
 * @param user_data Opaque binding-owned pointer supplied at registration.
 */
typedef rac_bool_t (*rac_hybrid_custom_filter_predicate_t)(
    const rac_hybrid_routing_context_t* ctx, void* user_data);

/**
 * @brief Register (or replace) a named custom-filter predicate.
 *
 * Re-registering an existing @p name atomically replaces that entry's
 * predicate + user_data. Registration copies @p name into table-owned
 * storage; the caller may free its copy on return.
 *
 * @param name      NUL-terminated identifier (≤ RAC_HYBRID_CUSTOM_FILTER_NAME_MAX
 *                  including the terminator). Must be non-NULL and non-empty.
 * @param predicate Predicate to invoke. Must be non-NULL.
 * @param user_data Opaque pointer passed back to @p predicate. MAY be NULL.
 * @return RAC_SUCCESS;
 *         RAC_ERROR_INVALID_PARAMETER if @p name is NULL/empty/too long or
 *         @p predicate is NULL;
 *         RAC_ERROR_OUT_OF_MEMORY if the new snapshot cannot be allocated.
 */
RAC_API rac_result_t rac_hybrid_register_custom_filter(
    const char*                          name,
    rac_hybrid_custom_filter_predicate_t predicate,
    void*                                user_data);

/**
 * @brief Remove a named custom-filter predicate.
 *
 * No-op (still RAC_SUCCESS) when @p name is not registered.
 *
 * @param name NUL-terminated identifier. Must be non-NULL and non-empty.
 * @return RAC_SUCCESS;
 *         RAC_ERROR_INVALID_PARAMETER if @p name is NULL/empty;
 *         RAC_ERROR_OUT_OF_MEMORY if the shrunk snapshot cannot be allocated.
 */
RAC_API rac_result_t rac_hybrid_unregister_custom_filter(const char* name);

/**
 * @brief Resolve and invoke a registered custom-filter predicate by name.
 *
 * Loads the active snapshot once, finds the entry whose name equals @p name,
 * and invokes its predicate against @p ctx. Thread-safe; cheap enough for the
 * request hot path.
 *
 * @param name     Predicate name parsed from the policy's HybridFilter.Custom.
 * @param ctx      Per-request routing context handed to the predicate.
 * @param out_pass Receives the predicate result (RAC_TRUE = eligible).
 * @return RAC_SUCCESS when a matching predicate ran and wrote @p out_pass;
 *         RAC_ERROR_NULL_POINTER if @p name, @p ctx, or @p out_pass is NULL;
 *         RAC_ERROR_NOT_FOUND when no predicate is registered under @p name
 *         (out_pass is left untouched — the router decides the fail-open /
 *         fail-closed policy for an unknown name).
 */
RAC_API rac_result_t rac_hybrid_invoke_custom_filter(
    const char*                         name,
    const rac_hybrid_routing_context_t* ctx,
    rac_bool_t*                         out_pass);

#ifdef __cplusplus
}
#endif

#endif  // RAC_HYBRID_CUSTOM_FILTER_H
