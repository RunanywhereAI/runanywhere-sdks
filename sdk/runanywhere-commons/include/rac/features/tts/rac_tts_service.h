/**
 * @file rac_tts_service.h
 * @brief RunAnywhere Commons - TTS Service Interface
 *
 * Defines the generic TTS service API and vtable for multi-backend dispatch.
 * Backends (ONNX, Platform/System TTS, etc.) implement the vtable and register
 * with the service registry.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - rac_tts_service_ops_t and rac_tts_service_t: `internal`.
 *   - rac_tts_synthesize_lifecycle_proto: `SDK-facing default` over
 *     runanywhere.v1.TTSSynthesisRequest / TTSOutput bytes.
 *   - Struct APIs (rac_tts_create, initialize, synthesize,
 *     synthesize_stream, stop, get_info, cleanup, destroy, result_free,
 *     get_languages): `delete after SDK migration` for SDK callers;
 *     keep only as backend smoke-test entry points.
 */

#ifndef RAC_TTS_SERVICE_H
#define RAC_TTS_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * TTS Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_tts_service_ops {
    /** Initialize the service */
    rac_result_t (*initialize)(void* impl);

    /** Synthesize text to audio (blocking) */
    rac_result_t (*synthesize)(void* impl, const char* text, const rac_tts_options_t* options,
                               rac_tts_result_t* out_result);

    /** Stream synthesis for long text */
    rac_result_t (*synthesize_stream)(void* impl, const char* text,
                                      const rac_tts_options_t* options,
                                      rac_tts_stream_callback_t callback, void* user_data);

    /** Stop current synthesis */
    rac_result_t (*stop)(void* impl);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_tts_info_t* out_info);

    /** Cleanup/release resources (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);

    /**
     * Allocate a backend-specific impl for a new TTS service instance.
     * v3 replacement for the legacy rac_service_provider_t::create callback.
     * See rac_llm_service_ops_t::create for the full semantics.
     *
     * For TTS, `model_id` is a voice ID or voice-model path.
     */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);

    /**
     * Enumerate synthesis languages the backend currently supports (derived
     * from the loaded voice(s)) as a JSON array, e.g. "[\"en\",\"de\"]".
     * Callee allocates with malloc; caller MUST free via free(). Leave this
     * slot NULL to return RAC_ERROR_NOT_SUPPORTED from the generic dispatcher.
     */
    rac_result_t (*get_languages)(void* impl, char** out_json);
} rac_tts_service_ops_t;

/**
 * TTS Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_tts_service {
    /** Vtable with backend operations */
    const rac_tts_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model/voice ID for reference */
    const char* model_id;
} rac_tts_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create a TTS service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param voice_id Voice/model identifier (registry ID or path)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_create(const char* voice_id, rac_handle_t* out_handle);

/**
 * @brief Initialize a TTS service
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_initialize(rac_handle_t handle);

/**
 * @brief Synthesize text to audio
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options Synthesis options (can be NULL for defaults)
 * @param out_result Output: Synthesis result (caller must free with rac_tts_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_synthesize(rac_handle_t handle, const char* text,
                                        const rac_tts_options_t* options,
                                        rac_tts_result_t* out_result);

/**
 * @brief Stream synthesis for long text
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param callback Callback for each audio chunk
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_synthesize_stream(rac_handle_t handle, const char* text,
                                               const rac_tts_options_t* options,
                                               rac_tts_stream_callback_t callback, void* user_data);

/**
 * @brief Stop current synthesis
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_stop(rac_handle_t handle);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_get_info(rac_handle_t handle, rac_tts_info_t* out_info);

/**
 * @brief Cleanup and release resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_cleanup(rac_handle_t handle);

/**
 * @brief Destroy a TTS service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_tts_destroy(rac_handle_t handle);

/**
 * @brief Free a TTS result
 *
 * @param result Result to free
 */
RAC_API void rac_tts_result_free(rac_tts_result_t* result);

/**
 * @brief Get supported languages for the loaded TTS model as a JSON array string.
 *
 * Dispatches through the backend vtable. Returns RAC_ERROR_NOT_SUPPORTED if the
 * backend does not enumerate languages.
 *
 * @param handle      Service handle
 * @param out_json    Output: malloc'd JSON string (e.g. "[\"en\",\"de\"]"). Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_get_languages(rac_handle_t handle, char** out_json);

/**
 * @brief Synthesize using the lifecycle-loaded TTS voice/model.
 *
 * request_proto_bytes encodes runanywhere.v1.TTSSynthesisRequest.
 * Commons resolves the current TTS lifecycle component and out_result receives
 * serialized runanywhere.v1.TTSOutput bytes.
 */
RAC_API rac_result_t rac_tts_synthesize_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                        size_t request_proto_size,
                                                        rac_proto_buffer_t* out_result);

/**
 * @brief Callback fired once per serialized runanywhere.v1.TTSStreamEvent.
 *
 * The buffer is valid only for the duration of the callback. Callers that
 * need to retain the bytes MUST copy them out.
 */
typedef void (*rac_tts_lifecycle_stream_event_callback_fn)(const uint8_t* event_bytes,
                                                           size_t event_size, void* user_data);

/**
 * @brief Stream synthesis using the lifecycle-loaded TTS voice/model.
 *
 * request_proto_bytes encodes runanywhere.v1.TTSSynthesisRequest. Commons
 * resolves the current TTS lifecycle component, dispatches the request to the
 * backend, and fires @p callback once per canonical
 * runanywhere.v1.TTSStreamEvent envelope (kind = STARTED / AUDIO_CHUNK /
 * COMPLETED / ERROR, each with monotonically-increasing `seq` and
 * `timestamp_us`).
 *
 * Mirrors rac_stt_transcribe_stream_lifecycle_proto for TTS — lets SDKs
 * collapse "load then stream" flows into a single native call.
 *
 * @retval RAC_SUCCESS                      Streaming completed successfully.
 * @retval RAC_ERROR_INVALID_ARGUMENT       Request bytes/callback invalid.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 * @retval RAC_ERROR_NOT_INITIALIZED        No TTS lifecycle voice is loaded.
 * @retval RAC_ERROR_NOT_SUPPORTED          Backend does not advertise streaming.
 */
RAC_API rac_result_t rac_tts_synthesize_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_tts_lifecycle_stream_event_callback_fn callback, void* user_data);

/**
 * @brief Stop the in-flight synthesis on the lifecycle-loaded TTS voice.
 *
 * out_result receives serialized runanywhere.v1.TTSServiceState bytes
 * reflecting the post-stop state (is_ready, current_voice, optional error).
 */
RAC_API rac_result_t rac_tts_stop_lifecycle_proto(rac_proto_buffer_t* out_result);

/**
 * @brief Enumerate voices available on the lifecycle-loaded TTS voice/model.
 *
 * Lifecycle-driven variant of rac_tts_component_list_voices_proto. Uses the
 * currently lifecycle-loaded TTS service directly — no handle threading
 * required. Returns serialized runanywhere.v1.TTSVoiceList bytes containing
 * zero or more runanywhere.v1.TTSVoiceInfo entries.
 *
 * @param out Owned proto buffer with serialized runanywhere.v1.TTSVoiceList.
 *            Caller MUST release with rac_proto_buffer_free().
 *
 * @retval RAC_SUCCESS                      Voices serialized successfully.
 * @retval RAC_ERROR_NULL_POINTER           out is NULL.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 * @retval RAC_ERROR_NOT_INITIALIZED        No TTS lifecycle voice is loaded.
 */
RAC_API rac_result_t rac_tts_list_voices_lifecycle_proto(rac_proto_buffer_t* out);

// =============================================================================
// CANONICAL DEFAULTS
// =============================================================================

/**
 * @brief Populate a default-initialised runanywhere.v1.TTSConfiguration.
 *
 * Commons-owned port of Swift's `RATTSConfiguration.defaults()` so every
 * platform SDK shares a single source of truth for the canonical defaults:
 *
 *   model_id              = ""
 *   voice                 = "default"
 *   language_code         = "en-US"
 *   speaking_rate         = 1.0
 *   pitch                 = 1.0
 *   volume                = 1.0
 *   audio_format          = AUDIO_FORMAT_PCM
 *   sample_rate           = 22050
 *   enable_neural_voice   = true
 *   enable_ssml           = false
 *
 * out_RATTSConfiguration receives serialized runanywhere.v1.TTSConfiguration
 * bytes. Caller MUST release with rac_proto_buffer_free().
 *
 * @retval RAC_SUCCESS                      Defaults serialized successfully.
 * @retval RAC_ERROR_NULL_POINTER           out_RATTSConfiguration is NULL.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 */
RAC_API rac_result_t
rac_tts_configuration_defaults_proto(rac_proto_buffer_t* out_RATTSConfiguration);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_SERVICE_H */
