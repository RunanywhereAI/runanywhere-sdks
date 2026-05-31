/**
 * @file rac_stt_hybrid_router.h
 * @brief RunAnywhere Commons - STT Hybrid Router public C API.
 *
 * Handle-based router that owns at most one offline and one online
 * rac_stt_service_t. On transcribe() it applies hard filters, ranks the
 * surviving candidates, invokes the primary, falls back to the secondary
 * on failure, and returns the STT result together with a
 * rac_hybrid_routed_metadata_t describing the decision.
 *
 * The router does NOT own the underlying services — callers create them
 * via the backend-specific factory (rac_stt_create() for sherpa,
 * rac_stt_sarvam_create() for the cloud) and pass them in. Caller must
 * call set_*_service(handle, NULL) BEFORE destroying either underlying
 * service to avoid use-after-free on the next route.
 *
 * Confidence cascade is intentionally NOT exposed in this header — it is
 * evaluated inside the router on the per-token confidence the offline
 * (sherpa) engine reports; the cloud side does not surface
 * transcript-quality confidence.
 */

#ifndef RAC_STT_HYBRID_ROUTER_H
#define RAC_STT_HYBRID_ROUTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/routing/rac_hybrid_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Allocate a new STT hybrid router. Returns an opaque handle.
 *
 * @param out_handle Receives the handle. NULL on failure.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_stt_hybrid_router_create(rac_handle_t* out_handle);

/**
 * @brief Destroy a router and free its resources. The wrapped services are
 *        NOT destroyed — the caller owns those.
 */
RAC_API void rac_stt_hybrid_router_destroy(rac_handle_t handle);

/**
 * @brief Attach the offline (on-device) STT service + its descriptor.
 *        Passing service == NULL clears the slot.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_offline_service(
    rac_handle_t                         handle,
    rac_stt_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Attach the online (cloud) STT service + its descriptor.
 *        Passing service == NULL clears the slot.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_online_service(
    rac_handle_t                         handle,
    rac_stt_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Install the routing policy. The policy struct (including the
 *        hard_filters array) is copied into router-owned memory; callers
 *        may free the source after this returns.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_policy(
    rac_handle_t                       handle,
    const rac_hybrid_routing_policy_t* policy);

/**
 * @brief Transcribe audio via the router. Applies filters → rank → invoke
 *        → failure-fallback, then writes the chosen backend's result into
 *        out_result and the routing decision into out_metadata.
 *
 * @param handle       Router handle.
 * @param ctx          Per-request routing context (is_online, battery, …).
 * @param audio_data   File-encoded audio bytes (wav/mp3/flac/...) OR raw PCM.
 * @param audio_size   Length of @p audio_data in bytes.
 * @param options      Transcription options (may be NULL for defaults).
 * @param out_result   Caller-owned struct populated on success. Free with
 *                     rac_stt_result_free().
 * @param out_metadata Always populated, even on failure.
 * @return RAC_SUCCESS on success; error code on failure.
 */
RAC_API rac_result_t rac_stt_hybrid_router_transcribe(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const void*                         audio_data,
    size_t                              audio_size,
    const rac_stt_options_t*            options,
    rac_stt_result_t*                   out_result,
    rac_hybrid_routed_metadata_t*       out_metadata);

/**
 * @brief Cancel the in-flight transcribe call on @p handle, if any.
 *
 * Safe to call from any thread; uses an atomic to track the currently
 * invoked service. rac_stt_service_ops_t exposes no cancel op today, so this
 * is effectively a no-op — it exists so callers can wire cancellation now and
 * have it take effect automatically once an engine adds a cancel op.
 *
 * @return RAC_SUCCESS.
 */
RAC_API rac_result_t rac_stt_hybrid_router_cancel(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif  // RAC_STT_HYBRID_ROUTER_H
