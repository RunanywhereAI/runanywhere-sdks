/**
 * @file rac_stt_service.h
 * @brief RunAnywhere Commons - STT Service Interface
 *
 * Defines the generic STT service API and vtable for multi-backend dispatch.
 * Backends (ONNX, Whisper, etc.) implement the vtable and register
 * with the service registry.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - rac_stt_service_ops_t and rac_stt_service_t: `internal`.
 *   - rac_stt_transcribe_lifecycle_proto: `SDK-facing default` over
 *     runanywhere.v1.STTTranscriptionRequest / STTOutput bytes.
 *   - Struct APIs (rac_stt_create, initialize, transcribe,
 *     transcribe_stream, get_info, cleanup, destroy, result_free,
 *     get_languages, detect_language): `delete after SDK migration`
 *     for SDK callers; keep only as backend smoke-test entry points.
 */

#ifndef RAC_STT_SERVICE_H
#define RAC_STT_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * STT Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_stt_service_ops {
    /** Initialize the service with a model path */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /** Transcribe audio (batch mode) */
    rac_result_t (*transcribe)(void* impl, const void* audio_data, size_t audio_size,
                               const rac_stt_options_t* options, rac_stt_result_t* out_result);

    /** Stream transcription for real-time processing */
    rac_result_t (*transcribe_stream)(void* impl, const void* audio_data, size_t audio_size,
                                      const rac_stt_options_t* options,
                                      rac_stt_stream_callback_t callback, void* user_data);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_stt_info_t* out_info);

    /** Cleanup/unload model (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);

    /**
     * Allocate a backend-specific impl for a new STT service instance.
     * v3 replacement for the legacy rac_service_provider_t::create callback.
     * See rac_llm_service_ops_t::create for the full semantics.
     */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);

    /**
     * Enumerate language codes the backend can transcribe as a JSON array of
     * BCP-47-ish strings, e.g. "[\"en\",\"es\",\"fr\"]". Callee allocates with
     * malloc; caller MUST free via free(). Returns RAC_ERROR_NOT_SUPPORTED if
     * the backend cannot enumerate (leave this slot NULL to get that behavior
     * for free via the generic dispatcher).
     */
    rac_result_t (*get_languages)(void* impl, char** out_json);

    /**
     * Detect the spoken language of a short PCM audio clip. audio_data layout
     * follows the same format backends use for transcribe() (Int16 mono).
     * Writes a NUL-terminated language code (e.g. "en") to *out_language;
     * callee allocates with malloc, caller MUST free via free(). Returns
     * RAC_ERROR_NOT_SUPPORTED when the slot is NULL.
     */
    rac_result_t (*detect_language)(void* impl, const void* audio_data, size_t audio_size,
                                    const rac_stt_options_t* options, char** out_language);

    // -------------------------------------------------------------------------
    // Persistent per-session streaming handles.
    //
    // These three slots let the commons streaming dispatcher keep a stable
    // backend recognizer handle alive across chunks. Sherpa-ONNX in
    // particular MUST NOT re-initialize its online recognizer every frame —
    // doing so discards the decoder state and inflates first-token latency.
    //
    // Backends that leave these slots NULL continue to receive per-chunk
    // `transcribe_stream` calls (legacy path). Backends that fill them in
    // get a stream_create on first chunk, N x stream_feed_audio_chunk, and
    // a final stream_destroy on stop/cancel.
    // -------------------------------------------------------------------------

    /**
     * Allocate a backend-specific streaming session tied to @p impl. The
     * returned @p out_stream_handle is opaque from commons' perspective and
     * is plumbed back into stream_feed_audio_chunk / stream_destroy. @p
     * options carries the resolved language / sample rate / timestamps /
     * etc. captured at session start and may be NULL for backend defaults.
     */
    rac_result_t (*stream_create)(void* impl, const rac_stt_options_t* options,
                                  rac_handle_t* out_stream_handle);

    /**
     * Feed one chunk of Int16 mono PCM samples into an active stream. @p
     * samples is non-null when @p count > 0. Backends decode the chunk
     * using their online recognizer and push partials / finals back to
     * commons by invoking @p callback — exactly the same bridge signature
     * the legacy transcribe_stream uses.
     */
    rac_result_t (*stream_feed_audio_chunk)(void* impl, rac_handle_t stream_handle,
                                            const int16_t* samples, size_t count,
                                            rac_stt_stream_callback_t callback, void* user_data);

    /**
     * Tear down a streaming session allocated by stream_create. Must be
     * idempotent with respect to NULL @p stream_handle.
     */
    rac_result_t (*stream_destroy)(void* impl, rac_handle_t stream_handle);
} rac_stt_service_ops_t;

/**
 * STT Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_stt_service {
    /** Vtable with backend operations */
    const rac_stt_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_stt_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create an STT service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_path Path to the model file (can be NULL for some providers)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle);

/**
 * @brief Initialize an STT service
 *
 * @param handle Service handle
 * @param model_path Path to the model file (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_initialize(rac_handle_t handle, const char* model_path);

/**
 * @brief Transcribe audio data (batch mode)
 *
 * @param handle Service handle
 * @param audio_data Audio data buffer
 * @param audio_size Size of audio data in bytes
 * @param options Transcription options (can be NULL for defaults)
 * @param out_result Output: Transcription result (caller must free with rac_stt_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_transcribe(rac_handle_t handle, const void* audio_data,
                                        size_t audio_size, const rac_stt_options_t* options,
                                        rac_stt_result_t* out_result);

/**
 * @brief Stream transcription for real-time processing
 *
 * @param handle Service handle
 * @param audio_data Audio chunk data
 * @param audio_size Size of audio chunk
 * @param options Transcription options
 * @param callback Callback for partial results
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                               size_t audio_size, const rac_stt_options_t* options,
                                               rac_stt_stream_callback_t callback, void* user_data);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_get_info(rac_handle_t handle, rac_stt_info_t* out_info);

/**
 * @brief Cleanup and release resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_cleanup(rac_handle_t handle);

/**
 * @brief Destroy an STT service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_stt_destroy(rac_handle_t handle);

/**
 * @brief Free an STT result
 *
 * @param result Result to free
 */
RAC_API void rac_stt_result_free(rac_stt_result_t* result);

/**
 * @brief Get supported languages for the loaded STT model as a JSON array string.
 *
 * Dispatches through the backend vtable. Returns RAC_ERROR_NOT_SUPPORTED if the
 * backend does not enumerate languages.
 *
 * @param handle      Service handle
 * @param out_json    Output: malloc'd JSON string (e.g. "[\"en\",\"es\"]"). Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_get_languages(rac_handle_t handle, char** out_json);

/**
 * @brief Detect language of an audio clip via the loaded STT model.
 *
 * Dispatches through the backend vtable. Returns RAC_ERROR_NOT_SUPPORTED if the
 * backend does not expose language detection.
 *
 * @param handle        Service handle
 * @param audio_data    PCM audio buffer (backend-defined format, typically Int16 mono 16 kHz)
 * @param audio_size    Size of audio_data in bytes
 * @param options       Optional decoding hints (can be NULL)
 * @param out_language  Output: malloc'd NUL-terminated language code. Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_detect_language(rac_handle_t handle, const void* audio_data,
                                             size_t audio_size, const rac_stt_options_t* options,
                                             char** out_language);

/**
 * @brief Transcribe using the lifecycle-loaded STT model.
 *
 * request_proto_bytes encodes runanywhere.v1.STTTranscriptionRequest.
 * Commons resolves the current STT lifecycle component and out_result receives
 * serialized runanywhere.v1.STTOutput bytes. Native file/capture adapter
 * handles are intentionally not dereferenced by this portable ABI.
 */
RAC_API rac_result_t rac_stt_transcribe_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                        size_t request_proto_size,
                                                        rac_proto_buffer_t* out_result);

/**
 * @brief Callback fired once per serialized runanywhere.v1.STTStreamEvent.
 *
 * The buffer is valid only for the duration of the callback. Callers that
 * need to retain the bytes MUST copy them out.
 */
typedef void (*rac_stt_lifecycle_stream_event_callback_fn)(const uint8_t* event_bytes,
                                                           size_t event_size, void* user_data);

/**
 * @brief Stream transcription using the lifecycle-loaded STT model.
 *
 * request_proto_bytes encodes runanywhere.v1.STTTranscriptionRequest. Commons
 * resolves the current STT lifecycle component, dispatches the audio to the
 * backend, and fires @p callback once per canonical
 * runanywhere.v1.STTStreamEvent envelope (kind = STARTED / PARTIAL / FINAL /
 * ERROR, each with monotonically-increasing `seq` and `timestamp_us`).
 *
 * Designed to let SDKs collapse "load then stream" flows into a single
 * native call without having to first acquire an STT component handle.
 *
 * @retval RAC_SUCCESS                      Streaming completed successfully.
 * @retval RAC_ERROR_INVALID_ARGUMENT       Request bytes/audio/callback invalid.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 * @retval RAC_ERROR_NOT_INITIALIZED        No STT lifecycle model is loaded.
 * @retval RAC_ERROR_NOT_SUPPORTED          Backend does not advertise streaming.
 */
RAC_API rac_result_t rac_stt_transcribe_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_stt_lifecycle_stream_event_callback_fn callback, void* user_data);

// =============================================================================
// CANONICAL DEFAULTS
// =============================================================================

/**
 * @brief Populate a default-initialised runanywhere.v1.STTConfiguration.
 *
 * Commons-owned port of Swift's `RASTTConfiguration.defaults()` so every
 * platform SDK shares a single source of truth for the canonical defaults:
 *
 *   model_id            = ""
 *   language            = STT_LANGUAGE_EN
 *   sample_rate         = 16000
 *   enable_vad          = false
 *
 * out_RASTTConfiguration receives serialized runanywhere.v1.STTConfiguration
 * bytes. Caller MUST release with rac_proto_buffer_free().
 *
 * @retval RAC_SUCCESS                      Defaults serialized successfully.
 * @retval RAC_ERROR_NULL_POINTER           out_RASTTConfiguration is NULL.
 * @retval RAC_ERROR_FEATURE_NOT_AVAILABLE  Commons built without Protobuf.
 */
RAC_API rac_result_t
rac_stt_configuration_defaults_proto(rac_proto_buffer_t* out_RASTTConfiguration);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_SERVICE_H */
