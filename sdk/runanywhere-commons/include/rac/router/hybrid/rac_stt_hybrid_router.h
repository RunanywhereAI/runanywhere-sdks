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
 * through the plugin registry (engine_hint="sherpa" for the on-device side,
 * "cloud" with provider=sarvam for the cloud side) and pass them in. Caller must
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
#include "rac/router/hybrid/rac_hybrid_types.h"

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
RAC_API rac_result_t
rac_stt_hybrid_router_set_offline_service(rac_handle_t handle, rac_stt_service_t* service,
                                          const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Attach the online (cloud) STT service + its descriptor.
 *        Passing service == NULL clears the slot.
 */
RAC_API rac_result_t
rac_stt_hybrid_router_set_online_service(rac_handle_t handle, rac_stt_service_t* service,
                                         const rac_hybrid_model_descriptor_t* descriptor);

/**
 * @brief Install the routing policy. The policy struct (including the
 *        hard_filters array) is copied into router-owned memory; callers
 *        may free the source after this returns.
 */
RAC_API rac_result_t rac_stt_hybrid_router_set_policy(rac_handle_t handle,
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
RAC_API rac_result_t rac_stt_hybrid_router_transcribe(rac_handle_t handle,
                                                      const rac_hybrid_routing_context_t* ctx,
                                                      const void* audio_data, size_t audio_size,
                                                      const rac_stt_options_t* options,
                                                      rac_stt_result_t* out_result,
                                                      rac_hybrid_routed_metadata_t* out_metadata);

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

/**
 * @brief Create an STT service through the plugin registry, by engine hint.
 *
 * The single registry-backed factory for BOTH router sides: the offline
 * (on-device) service and the online (cloud) service are created the same way
 * — route RAC_PRIMITIVE_TRANSCRIBE with @p engine_hint pinned as
 * preferred_engine_name (and fallback disabled), then call the routed engine's
 * stt_ops->create. The returned vtable + impl are heap-wrapped into a
 * rac_stt_service_t the caller owns and passes to
 * rac_stt_hybrid_router_set_offline_service / _set_online_service.
 *
 * This is exposed so non-JNI bindings (Web/WASM, RN, Flutter) can construct a
 * rac_stt_service_t* without dereferencing a function pointer inside a routed
 * vtable across the proto-byte ABI boundary — the dereference and heap-wrap
 * happen here, inside commons, where the symbols are local. The Android JNI
 * service-create thunks delegate to this same function (one implementation).
 *
 * @param engine_hint       "sherpa" | "cloud" | … pinned as the preferred
 *                          engine. NULL/empty lets the registry pick by
 *                          primitive/format.
 * @param model_id_or_path  Passed verbatim as the create op's `model_id`
 *                          argument (an on-device path for sherpa, or NULL for
 *                          cloud engines that take everything via config_json).
 * @param config_json       Passed verbatim as the create op's `config_json`
 *                          argument (the cloud {provider,api_key,model,…} JSON,
 *                          or NULL). The caller is responsible for threading the
 *                          provider in (e.g. {"provider":"sarvam"}).
 * @return A heap-allocated rac_stt_service_t* the caller owns (release with
 *         rac_stt_hybrid_router_destroy_service), or NULL on routing/create
 *         failure or OOM.
 */
RAC_API rac_stt_service_t* rac_stt_hybrid_router_create_service(const char* engine_hint,
                                                                const char* model_id_or_path,
                                                                const char* config_json);

/**
 * @brief Destroy a service returned by rac_stt_hybrid_router_create_service.
 *
 * Routes through rac_stt_destroy: calls the engine's stt_ops->destroy, frees
 * the wrapper's strdup'd model_id, and frees the wrapper struct. NULL-safe.
 */
RAC_API void rac_stt_hybrid_router_destroy_service(rac_stt_service_t* service);

#ifdef __cplusplus
}
#endif

#endif  // RAC_STT_HYBRID_ROUTER_H
