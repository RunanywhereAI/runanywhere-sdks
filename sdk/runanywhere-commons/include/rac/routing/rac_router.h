/**
 * @file rac_router.h
 * @brief Hybrid router public C API.
 *
 * The router sits on top of the existing service registry. Callers create
 * backend services the usual way (via rac_service_create / rac_stt_create),
 * then register them with the router along with a descriptor that declares
 * eligibility conditions and priority. rac_router_run_<cap> picks one
 * candidate per request, applies policy + cascade, and invokes the chosen
 * backend through its existing service vtable.
 *
 * Only the STT capability is wired in this build. When a new capability is
 * implemented it adds its own register/unregister/run trio here without
 * disturbing the existing surface.
 *
 * Threading: all functions are safe to call from multiple threads.
 * Lifetime: the caller owns the registered service and must unregister
 *   before destroying it.
 */

#ifndef RAC_ROUTER_H
#define RAC_ROUTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/routing/rac_routing_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_router rac_router_t;

// =============================================================================
// LIFECYCLE
// =============================================================================

RAC_API rac_router_t* rac_router_create(void);
RAC_API void          rac_router_destroy(rac_router_t* router);

// Process-global router (lazy-initialized on first call). Backends self-
// register against this instance. Destroyed on SDK shutdown.
RAC_API rac_router_t* rac_router_global(void);
RAC_API void          rac_router_global_shutdown(void);

// =============================================================================
// STT REGISTRATION + DISPATCH
// =============================================================================

/**
 * Register an STT service with the router.
 *
 * The router keeps a non-owning reference to @p service. The caller must
 * call rac_router_unregister_stt() before destroying the service.
 *
 * @param router     Router instance.
 * @param descriptor Backend descriptor (module id, conditions, priority).
 * @param service    Service instance created via rac_stt_create or the
 *                   service registry (vtable + impl). Non-owning.
 */
RAC_API rac_result_t rac_router_register_stt(rac_router_t*                   router,
                                             const rac_backend_descriptor_t* descriptor,
                                             rac_stt_service_t*              service);

RAC_API rac_result_t rac_router_unregister_stt(rac_router_t* router, const char* module_id);

RAC_API int32_t rac_router_stt_count(rac_router_t* router);

/**
 * Transcribe through the router.
 *
 * Selects one candidate based on eligibility + policy + score, invokes its
 * transcribe vtable, and applies the confidence cascade when a local-only
 * primary scores below RAC_ROUTING_CONFIDENCE_THRESHOLD.
 *
 * The caller owns out_result's allocations exactly as for rac_stt_transcribe
 * (free with rac_stt_result_free).
 */
RAC_API rac_result_t rac_router_run_stt(rac_router_t*                router,
                                        const rac_routing_context_t* context,
                                        const void*                  audio_data,
                                        size_t                       audio_size,
                                        const rac_stt_options_t*     options,
                                        rac_stt_result_t*            out_result,
                                        rac_routed_metadata_t*       out_meta);

#ifdef __cplusplus
}
#endif

#endif  // RAC_ROUTER_H
