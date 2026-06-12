/**
 * @file rac_vlm_service.h
 * @brief RunAnywhere Commons - VLM Service Interface
 *
 * Defines the generic VLM service API and vtable for multi-backend dispatch.
 * Backends (LlamaCpp VLM, MLX VLM) implement the vtable and register
 * with the service registry.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - rac_vlm_service_ops_t and rac_vlm_service_t: `internal`.
 *   - Proto-byte APIs (rac_vlm_process_proto, rac_vlm_process_stream_proto,
 *     rac_vlm_generate_proto, rac_vlm_stream_proto,
 *     rac_vlm_cancel_proto, rac_vlm_cancel_lifecycle_proto):
 *     `SDK-facing default` over runanywhere.v1.VLMImage /
 *     VLMGenerationOptions / VLMResult / VLMStreamEvent / SDKEvent bytes.
 *   - Struct APIs (rac_vlm_create, initialize, process, process_stream,
 *     get_info, cancel, cleanup, destroy, result_free): `delete after
 *     SDK migration` for SDK callers; keep only as backend smoke-test
 *     entry points.
 */

#ifndef RAC_VLM_SERVICE_H
#define RAC_VLM_SERVICE_H

#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * VLM Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_vlm_service_ops {
    /**
     * Initialize the service with model path(s).
     * @param impl Backend implementation handle
     * @param model_path Path to the main model file (LLM weights)
     * @param mmproj_path Path to vision projector (required for llama.cpp, NULL for MLX)
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*initialize)(void* impl, const char* model_path, const char* mmproj_path);

    /**
     * Process an image with a text prompt (blocking).
     * @param impl Backend implementation handle
     * @param image Image input
     * @param prompt Text prompt
     * @param options Generation options (can be NULL for defaults)
     * @param out_result Output result (caller must free with rac_vlm_result_free)
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*process)(void* impl, const rac_vlm_image_t* image, const char* prompt,
                            const rac_vlm_options_t* options, rac_vlm_result_t* out_result);

    /**
     * Process an image with streaming callback.
     * @param impl Backend implementation handle
     * @param image Image input
     * @param prompt Text prompt
     * @param options Generation options (can be NULL for defaults)
     * @param callback Token callback
     * @param user_data User context for callback
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*process_stream)(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                   const rac_vlm_options_t* options,
                                   rac_vlm_stream_callback_fn callback, void* user_data);

    /**
     * Get service information.
     * @param impl Backend implementation handle
     * @param out_info Output info structure
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*get_info)(void* impl, rac_vlm_info_t* out_info);

    /**
     * Cancel ongoing generation.
     * @param impl Backend implementation handle
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*cancel)(void* impl);

    /**
     * Cleanup/unload model (keeps service alive).
     * @param impl Backend implementation handle
     * @return RAC_SUCCESS or error code
     */
    rac_result_t (*cleanup)(void* impl);

    /**
     * Destroy the service.
     * @param impl Backend implementation handle
     */
    void (*destroy)(void* impl);

    /**
     * Allocate a backend-specific impl for a new VLM service instance.
     * v3 replacement for the legacy rac_service_provider_t::create callback.
     * See rac_llm_service_ops_t::create for the full semantics.
     *
     * For VLM, `config_json` MAY include an "mmproj_path" key that the
     * adapter passes to the backend's 2-path create function (e.g.
     * rac_vlm_llamacpp_create(model_path, mmproj_path, config, out_handle)).
     */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_vlm_service_ops_t;

/**
 * VLM Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_vlm_service {
    /** Vtable with backend operations */
    const rac_vlm_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_vlm_service_t;

/**
 * @brief Callback for proto-byte VLM streaming events.
 *
 * The callback receives serialized runanywhere.v1.SDKEvent bytes. Token deltas
 * are emitted as GenerationEvent TOKEN_GENERATED events, while operation
 * lifecycle is also published on the canonical SDKEvent stream.
 */
typedef rac_bool_t (*rac_vlm_stream_proto_callback_fn)(const uint8_t* event_proto_bytes,
                                                       size_t event_proto_size, void* user_data);

/**
 * @brief Callback for generated VLM stream events.
 *
 * The callback receives serialized runanywhere.v1.VLMStreamEvent bytes emitted
 * by lifecycle-owned generated VLM stream processing.
 */
typedef rac_bool_t (*rac_vlm_stream_event_proto_callback_fn)(const uint8_t* event_proto_bytes,
                                                             size_t event_proto_size,
                                                             void* user_data);

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create a VLM service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_id Model identifier (registry ID or path to model file)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_create(const char* model_id, rac_handle_t* out_handle);

/**
 * @brief Initialize a VLM service with model paths
 *
 * @param handle Service handle
 * @param model_path Path to the main model file
 * @param mmproj_path Path to vision projector (can be NULL for some backends)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_initialize(rac_handle_t handle, const char* model_path,
                                        const char* mmproj_path);

/**
 * @brief Process an image with a text prompt
 *
 * @param handle Service handle
 * @param image Image input
 * @param prompt Text prompt describing what to analyze
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free with rac_vlm_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                     const char* prompt, const rac_vlm_options_t* options,
                                     rac_vlm_result_t* out_result);

/**
 * @brief Process an image with serialized generated proto inputs.
 *
 * image_proto_bytes must encode runanywhere.v1.VLMImage and
 * options_proto_bytes must encode runanywhere.v1.VLMGenerationOptions. The
 * result buffer receives serialized runanywhere.v1.VLMResult bytes.
 */
RAC_API rac_result_t rac_vlm_process_proto(rac_handle_t handle, const uint8_t* image_proto_bytes,
                                           size_t image_proto_size,
                                           const uint8_t* options_proto_bytes,
                                           size_t options_proto_size,
                                           rac_proto_buffer_t* out_result);

/**
 * @brief Process an image with streaming response
 *
 * @param handle Service handle
 * @param image Image input
 * @param prompt Text prompt
 * @param options Generation options (can be NULL for defaults)
 * @param callback Callback for each generated token
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                            const char* prompt, const rac_vlm_options_t* options,
                                            rac_vlm_stream_callback_fn callback, void* user_data);

/**
 * @brief Stream VLM output with serialized generated proto inputs.
 *
 * Token events are delivered to callback as serialized runanywhere.v1.SDKEvent
 * bytes. The optional out_result receives the aggregate runanywhere.v1.VLMResult
 * when generation completes.
 *
 * @warning user_data ownership and lifetime (cross-SDK
 *          contract — see rac_llm_stream.h for the canonical recipe). The C
 *          runtime may invoke `callback(bytes, size, user_data)` on a
 *          background thread AFTER this entry point has returned, because
 *          the dispatcher copies the callback slot under its internal mutex
 *          and releases the mutex BEFORE invoking the user callback (see
 *          rac_vlm_proto_abi.cpp lock-release-before-callback comment). The
 *          caller MUST ensure no in-flight invocation is executing on a
 *          background thread before freeing @p user_data.
 *
 *          Recommended teardown sequence:
 *            (a) drive the stream to its terminal event or call
 *                rac_vlm_cancel_proto(handle) / rac_vlm_cancel_lifecycle_proto()
 *                — no NEW dispatches will fire once cancellation has been
 *                observed by the generator loop;
 *            (b) call rac_vlm_proto_quiesce() — spin-waits until every
 *                in-flight callback invocation has returned;
 *            (c) free @p user_data.
 *
 *          Modalities that currently expose proto_quiesce: LLM
 *          (rac_llm_stream.h), STT (rac_stt_stream.h), TTS
 *          (rac_tts_stream.h), VAD (rac_vad_stream.h), Diffusion
 *          (rac_diffusion_stream.h), VLM (this header). voice_agent
 *          quiesces in-flight callbacks as part of rac_voice_agent_destroy()
 *          rather than exposing a standalone quiesce entry point. SDK
 *          fan-out helpers (Swift HandleStreamAdapter, Kotlin/Flutter/RN
 *          equivalents) centralize this dance for their host language;
 *          refer to the canonical adapter implementation when porting a new
 *          SDK.
 */
RAC_API rac_result_t rac_vlm_process_stream_proto(
    rac_handle_t handle, const uint8_t* image_proto_bytes, size_t image_proto_size,
    const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_vlm_stream_proto_callback_fn callback, void* user_data, rac_proto_buffer_t* out_result);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_get_info(rac_handle_t handle, rac_vlm_info_t* out_info);

/**
 * @brief Cancel ongoing generation
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_cancel(rac_handle_t handle);

/**
 * @brief Cancel VLM generation and emit canonical cancellation events.
 */
RAC_API rac_result_t rac_vlm_cancel_proto(rac_handle_t handle);

// =============================================================================
// GENERATED-PROTO VLM ABI - lifecycle-owned model state
// =============================================================================

/**
 * @brief Generate text from serialized runanywhere.v1.VLMGenerationRequest bytes.
 *
 * Uses the VLM model loaded through rac_model_lifecycle_load_proto() and
 * returns serialized runanywhere.v1.VLMResult bytes in out_result.
 */
RAC_API rac_result_t rac_vlm_generate_proto(const uint8_t* request_proto_bytes,
                                            size_t request_proto_size,
                                            rac_proto_buffer_t* out_result);

/**
 * @brief Stream VLM output from serialized runanywhere.v1.VLMGenerationRequest bytes.
 *
 * Uses the lifecycle-owned VLM model. The callback receives serialized
 * runanywhere.v1.VLMStreamEvent bytes including token deltas and exactly one
 * terminal event.
 *
 * @warning user_data ownership and lifetime (cross-SDK
 *          contract — see rac_llm_stream.h for the canonical recipe). The C
 *          runtime may invoke `callback(bytes, size, user_data)` on a
 *          background thread AFTER this entry point has returned, because
 *          the dispatcher copies the callback slot under its internal mutex
 *          and releases the mutex BEFORE invoking the user callback. The
 *          caller MUST ensure no in-flight invocation is executing on a
 *          background thread before freeing @p user_data.
 *
 *          Recommended teardown sequence:
 *            (a) drive the stream to its terminal event or call
 *                rac_vlm_cancel_lifecycle_proto() — no NEW dispatches will
 *                fire once cancellation has been observed;
 *            (b) call rac_vlm_proto_quiesce() — spin-waits until every
 *                in-flight callback invocation has returned;
 *            (c) free @p user_data.
 */
RAC_API rac_result_t rac_vlm_stream_proto(const uint8_t* request_proto_bytes,
                                          size_t request_proto_size,
                                          rac_vlm_stream_event_proto_callback_fn callback,
                                          void* user_data);

/**
 * @brief Cancel lifecycle-owned VLM generation and return a cancellation event.
 */
RAC_API rac_result_t rac_vlm_cancel_lifecycle_proto(rac_proto_buffer_t* out_event);

/**
 * @brief Spin-wait until all in-flight VLM proto-byte stream/process entry
 *        points have returned. Mirrors the voice_agent in_flight pattern
 *        (voice_agent.cpp:594). Callers freeing user_data passed into
 *        rac_vlm_process_stream_proto / rac_vlm_stream_proto, or tearing
 *        down the lifecycle VLM, should call this before freeing the
 *        user_data. Safe to call from any thread.
 */
RAC_API void rac_vlm_proto_quiesce(void);

/**
 * @brief Cleanup and release model resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vlm_cleanup(rac_handle_t handle);

/**
 * @brief Destroy a VLM service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_vlm_destroy(rac_handle_t handle);

/**
 * @brief Free a VLM result
 *
 * @param result Result to free
 */
RAC_API void rac_vlm_result_free(rac_vlm_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VLM_SERVICE_H */
