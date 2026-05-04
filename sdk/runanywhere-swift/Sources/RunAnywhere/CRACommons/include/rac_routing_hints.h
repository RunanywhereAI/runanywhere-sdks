/**
 * @file rac_routing_hints.h
 * @brief Caller-supplied hints that bias engine routing decisions.
 *
 * GAP 04 Phase 8 — see v2_gap_specs/GAP_04_ENGINE_ROUTER.md.
 *
 * Hints are SUGGESTIONS, not requirements. The router gives matching plugins
 * a scoring bonus but still picks the next-best plugin if the hinted one is
 * unavailable on the host. The exception is `preferred_engine_name`, which
 * is treated as a HARD pin: when set, the router will only return that
 * specific plugin (or NOT_FOUND when `no_fallback` is also set).
 *
 * Frontends pass `NULL` for "no hints" (equivalent to a zero-initialized
 * struct).
 */

#ifndef RAC_ROUTER_ROUTING_HINTS_H
#define RAC_ROUTER_ROUTING_HINTS_H

#include <stddef.h>
#include <stdint.h>

#include "rac_primitive.h"   /* rac_runtime_id_t */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Routing hints. Pass `NULL` for "no hints".
 *
 * Layout is wire-stable. New fields land in the `_reserved[]` tail and
 * require an `RAC_PLUGIN_API_VERSION` bump per the GAP 02 compatibility
 * policy.
 */
typedef struct rac_routing_hints {
    /**
     * Hard pin to a specific plugin by `metadata.name` (e.g. "whisperkit_coreml").
     * When set, the router only considers this plugin. NULL = no pin.
     */
    const char* preferred_engine_name;

    /**
     * Soft preference for a runtime (e.g. RAC_RUNTIME_ANE). Plugins that
     * declare this runtime in their metadata get a +30 scoring bonus, but
     * non-matching plugins are still considered.
     */
    rac_runtime_id_t preferred_runtime;

    /**
     * Estimated working-set memory the caller expects to need (bytes). Used
     * by the router to decline plugins whose engine has insufficient
     * resources on the current host. 0 = no hint.
     */
    size_t estimated_memory_bytes;

    /**
     * If non-zero AND `preferred_engine_name` is set, the router returns
     * `RAC_ERROR_NOT_FOUND` instead of falling back to the next-best plugin
     * when the pinned name is unavailable. Useful for tests + reproducible
     * deployments.
     */
    uint8_t no_fallback;

    /** Reserved — must be zero. Round to 8-byte alignment. */
    uint8_t _reserved[7];
} rac_routing_hints_t;

#ifdef __cplusplus
}
#endif

#endif  /* RAC_ROUTER_ROUTING_HINTS_H */
