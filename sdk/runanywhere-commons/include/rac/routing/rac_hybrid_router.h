/**
 * @file rac_hybrid_router.h
 * @brief Capability-agnostic hybrid router (handle-based).
 *
 * One handle per (capability, use-case). A handle owns its registry, its
 * cascade config, and its custom-policy fn pointer. Multiple handles for the
 * same capability can coexist — e.g. one "fast LLM" router and one "accurate
 * LLM" router with different backends.
 *
 * Backend registration is single-fn: the caller passes a capability-typed
 * service handle (rac_stt_service_t* / rac_vad_service_t* / ...) as a void*.
 * Per-capability rac_hybrid_router_run_<cap>() does the cast at the boundary
 * and dispatches through that service's vtable.
 *
 * Threading: all functions are thread-safe.
 * Lifetime: the router holds non-owning refs to registered services. The
 *   caller must unregister before destroying a service.
 */

#ifndef RAC_HYBRID_ROUTER_H
#define RAC_HYBRID_ROUTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/routing/rac_routing_types.h"
#include "rac/routing/rac_vad_routing.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_hybrid_router rac_hybrid_router_t;

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * Create a router for one capability. The capability is locked in at creation
 * — register_backend() rejects descriptors with mismatching capability, and
 * only the matching run_<cap>() can be called against this handle.
 */
RAC_API rac_hybrid_router_t* rac_hybrid_router_create(rac_routed_capability_t capability);
RAC_API void                 rac_hybrid_router_destroy(rac_hybrid_router_t* router);

RAC_API rac_routed_capability_t rac_hybrid_router_capability(const rac_hybrid_router_t* router);

// =============================================================================
// PER-INSTANCE CONFIG
// =============================================================================

/**
 * Cascade config — defaults: enabled=true, threshold=RAC_ROUTING_CONFIDENCE_THRESHOLD.
 * Set enabled=false to disable low-confidence fallback entirely (router returns
 * the highest-scored candidate's result regardless of confidence).
 */
RAC_API rac_result_t rac_hybrid_router_set_cascade(rac_hybrid_router_t* router,
                                                    bool                 enabled,
                                                    float                threshold);

/**
 * Install a custom scoring fn used when context.policy == RAC_ROUTING_POLICY_CUSTOM.
 * Pass fn=nullptr to clear. The router stores the fn ptr + user_data; the
 * caller must keep user_data live for the router's lifetime (or until clear).
 */
RAC_API rac_result_t rac_hybrid_router_set_custom_policy(rac_hybrid_router_t* router,
                                                          rac_custom_policy_fn fn,
                                                          void*                user_data);

// =============================================================================
// REGISTRATION (capability-agnostic — one fn for all capabilities)
// =============================================================================

/**
 * Register a backend with the router.
 *
 * @param router         Router instance.
 * @param descriptor     Backend descriptor; descriptor->capability must match
 *                       the router's capability.
 * @param service_handle Pointer to the capability-typed service struct
 *                       (rac_stt_service_t* for STT, etc.). The router stores
 *                       this as void* and the per-capability run_*() casts.
 *                       Non-owning — caller retains lifecycle responsibility.
 */
RAC_API rac_result_t rac_hybrid_router_register_backend(rac_hybrid_router_t* router,
                                                         const rac_backend_descriptor_t* descriptor,
                                                         void* service_handle);

RAC_API rac_result_t rac_hybrid_router_unregister(rac_hybrid_router_t* router,
                                                  const char*          module_id);

RAC_API int32_t rac_hybrid_router_count(const rac_hybrid_router_t* router);

// =============================================================================
// DISPATCH (per-capability)
// =============================================================================

/**
 * STT dispatch. Selects one candidate, invokes its transcribe vtable, applies
 * the confidence cascade. The caller owns out_result allocations exactly as
 * for rac_stt_transcribe (free with rac_stt_result_free).
 */
RAC_API rac_result_t rac_hybrid_router_run_stt(rac_hybrid_router_t*         router,
                                                const rac_routing_context_t* context,
                                                const void*                  audio_data,
                                                size_t                       audio_size,
                                                const rac_stt_options_t*     options,
                                                rac_stt_result_t*            out_result,
                                                rac_routed_metadata_t*       out_meta);

/**
 * VAD dispatch. Picks one VAD backend per the descriptors' priority + policy,
 * runs `ops->process` once. No cascade — VAD decisions are per-frame and
 * cheap; if a backend fails, the router falls through to the next candidate.
 */
RAC_API rac_result_t rac_hybrid_router_run_vad(rac_hybrid_router_t*         router,
                                                const rac_routing_context_t* context,
                                                const float*                 samples,
                                                size_t                       num_samples,
                                                rac_vad_routed_result_t*     out_result,
                                                rac_routed_metadata_t*       out_meta);

// (run_llm / run_tts / run_vlm land in their own commits — same shape.)

#ifdef __cplusplus
}
#endif

#endif  // RAC_HYBRID_ROUTER_H
