/**
 * @file rac_llm_hybrid_router.h
 * @brief RunAnywhere Commons - LLM Hybrid Router public C API.
 *
 * Handle-based router that owns at most one offline and one online
 * rac_llm_service_t. On generate() it applies hard filters, ranks the
 * surviving candidates, invokes the primary, optionally cascades to the
 * secondary on confidence/error, and returns the LLM result together with
 * a rac_hybrid_routed_metadata_t describing the decision.
 *
 * The router does NOT own the underlying services — callers create them
 * via rac_llm_create() (or the backend-specific factory) and pass them in.
 * Caller must call set_*_service(handle, NULL) BEFORE destroying either
 * underlying service to avoid use-after-free on the next route.
 */

#ifndef RAC_LLM_HYBRID_ROUTER_H
#define RAC_LLM_HYBRID_ROUTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/routing/rac_hybrid_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Allocate a new LLM hybrid router. Returns an opaque handle.
 *
 * @param out_handle Receives the handle. NULL on failure.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_llm_hybrid_router_create(rac_handle_t* out_handle);

/**
 * @brief Destroy a router and free its resources. The wrapped services are
 *        NOT destroyed — the caller owns those.
 */
RAC_API void rac_llm_hybrid_router_destroy(rac_handle_t handle);

/**
 * @brief Attach the offline (on-device) LLM service + its descriptor.
 *        Passing service == NULL clears the slot.
 */
RAC_API rac_result_t rac_llm_hybrid_router_set_offline_service(
    rac_handle_t                         handle,
    rac_llm_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Attach the online (cloud) LLM service + its descriptor.
 *        Passing service == NULL clears the slot.
 */
RAC_API rac_result_t rac_llm_hybrid_router_set_online_service(
    rac_handle_t                         handle,
    rac_llm_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Install the routing policy. The policy struct (including the
 *        hard_filters array) is copied into router-owned memory; callers
 *        may free the source after this returns.
 */
RAC_API rac_result_t rac_llm_hybrid_router_set_policy(
    rac_handle_t                       handle,
    const rac_hybrid_routing_policy_t* policy);

/**
 * @brief Generate text via the router. Applies filters → rank → invoke →
 *        cascade, then writes the chosen backend's result into out_result
 *        and routing decision into out_metadata.
 *
 * @param handle      Router handle.
 * @param ctx         Per-request routing context (online?, sensitive?, ...).
 * @param prompt      Input prompt.
 * @param options     Generation options (may be NULL for defaults).
 * @param out_result  Caller-owned struct populated on success. Free with
 *                    rac_llm_result_free().
 * @param out_metadata Always populated, even on failure.
 * @return RAC_SUCCESS on success; error code on failure. When the primary
 *         succeeded but cascade was attempted-and-failed, returns
 *         RAC_SUCCESS with out_metadata->cascade_error_code != 0 and the
 *         primary's result restored into out_result.
 */
RAC_API rac_result_t rac_llm_hybrid_router_generate(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const char*                         prompt,
    const rac_llm_options_t*            options,
    rac_llm_result_t*                   out_result,
    rac_hybrid_routed_metadata_t*       out_metadata);

/**
 * @brief Streaming variant. Tokens from the chosen backend flow through
 *        @p callback. When cascade is configured, the router buffers the
 *        primary's tokens, evaluates the cascade trigger at end-of-stream
 *        (or at min_tokens_before_check if confidence is available
 *        mid-stream), and only forwards tokens once the decision is
 *        committed. out_metadata is populated when the stream terminates.
 *
 * @note  POC scope: confidence cascade is evaluated only at end-of-stream
 *        because the existing rac_llm_stream_callback_fn does not carry
 *        a per-token logprob. Mid-stream early cascade requires extending
 *        the callback signature (planned future work, documented in
 *        idl/hybrid_router.proto).
 */
RAC_API rac_result_t rac_llm_hybrid_router_generate_stream(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const char*                         prompt,
    const rac_llm_options_t*            options,
    rac_llm_stream_callback_fn          callback,
    void*                               user_data,
    rac_hybrid_routed_metadata_t*       out_metadata);

/**
 * @brief Cancel the in-flight generate / generate_stream call on @p handle,
 *        if any. Forwards to the active service's ops->cancel.
 *
 * Safe to call from any thread; uses an atomic to track the currently
 * invoked service. No-op when no call is in flight or when the active
 * service exposes no cancel op.
 *
 * @return RAC_SUCCESS when forwarded (or no-op); the service's cancel rc
 *         otherwise.
 */
RAC_API rac_result_t rac_llm_hybrid_router_cancel(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif  // RAC_LLM_HYBRID_ROUTER_H
