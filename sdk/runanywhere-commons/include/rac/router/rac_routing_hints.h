/**
 * @file rac_routing_hints.h
 * @brief Caller-supplied hints that bias engine routing decisions.
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

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Routing hints. Pass `NULL` for "no hints".
 *
 * Scalar field sizes are fixed (`uint64_t`, `int32_t`) so the layout is the
 * same on 32-bit and 64-bit hosts. The leading `const char*` still matches
 * host pointer width — plugins are loaded into the host process, so pointer
 * width matches by construction. New fields land in the `_reserved[]` tail
 * and require an `RAC_PLUGIN_API_VERSION` bump per the compatibility
 * policy.
 */
typedef struct rac_routing_hints {
    /**
     * Hard pin to a specific plugin by `metadata.name` (e.g. "whisperkit_coreml").
     * When set, the router only considers this plugin. NULL = no pin.
     */
    const char* preferred_engine_name;

    /**
     * Soft preference for a runtime. Carries a `rac_runtime_id_t` value (e.g.
     * `RAC_RUNTIME_ANE`) typed as `int32_t` so the field width does not depend
     * on the C compiler's choice of enum underlying type. Plugins that declare
     * this runtime in their metadata get a +30 scoring bonus, but non-matching
     * plugins are still considered.
     */
    int32_t preferred_runtime;

    /**
     * If non-zero AND `preferred_engine_name` is set, the router returns
     * `RAC_ERROR_NOT_FOUND` instead of falling back to the next-best plugin
     * when the pinned name is unavailable. Useful for tests + reproducible
     * deployments.
     */
    uint8_t no_fallback;

    /** Reserved — must be zero. Round to 8-byte alignment. */
    uint8_t _reserved[3];

    /**
     * Estimated working-set memory the caller expects to need (bytes). Used
     * by the router to decline plugins whose engine has insufficient
     * resources on the current host. Typed as `uint64_t` so the field is
     * the same width on 32-bit and 64-bit hosts. 0 = no hint.
     */
    uint64_t estimated_memory_bytes;
} rac_routing_hints_t;

/* Wire-layout guard. Catches enum-underlying-type changes and accidental
 * field-width drift on 64-bit hosts (the only ABI the SDK ships against).
 * Pointer width is intentionally allowed to track the host — plugins are
 * loaded into the host process and share its word size by construction. */
#if defined(__SIZEOF_POINTER__) && __SIZEOF_POINTER__ == 8
#ifdef __cplusplus
static_assert(sizeof(rac_routing_hints_t) == 24, "rac_routing_hints_t layout drift (64-bit)");
#else
_Static_assert(sizeof(rac_routing_hints_t) == 24, "rac_routing_hints_t layout drift (64-bit)");
#endif
#endif

#ifdef __cplusplus
}
#endif

#endif /* RAC_ROUTER_ROUTING_HINTS_H */
