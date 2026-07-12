/**
 * @file rac_stt_component.h
 * @brief RunAnywhere Commons - STT Capability Component
 *
 * C port of Swift's STTCapability.swift from:
 * Sources/RunAnywhere/Features/STT/STTCapability.swift
 *
 * Actor-based STT capability that owns model lifecycle and transcription.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - Proto-byte APIs (rac_stt_component_transcribe_proto,
 *     rac_stt_component_transcribe_stream_proto): `SDK-facing default`
 *     over runanywhere.v1.STTOptions / STTOutput / STTStreamEvent bytes.
 *   - Struct APIs (rac_stt_component_create, configure, load_model,
 *     unload, cleanup, transcribe, transcribe_stream, get_*,
 *     get_supported_languages, detect_language, destroy):
 *     `delete after SDK migration` for SDK callers — use proto-byte
 *     APIs and the model lifecycle proto contract.
 */

#ifndef RAC_STT_COMPONENT_H
#define RAC_STT_COMPONENT_H

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// NOTE: rac_stt_config_t is defined in rac_stt_types.h (included above)

// =============================================================================
// STT COMPONENT API - Mirrors Swift's STTCapability
// =============================================================================

/**
 * @brief Create an STT capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the STT component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_configure(rac_handle_t handle,
                                                 const rac_stt_config_t* config);

/**
 * @brief Check if model is loaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_stt_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * @param handle Component handle
 * @return Current model ID (NULL if not loaded)
 */
RAC_API const char* rac_stt_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load a model
 *
 * Any active proto stream sessions owned by this component are cancelled and
 * drained before the current model is replaced. A re-entrant call from the
 * component's own stream callback returns RAC_ERROR_SERVICE_BUSY rather than
 * waiting for itself.
 *
 * @param handle Component handle
 * @param model_path File path to the model (used for loading) - REQUIRED
 * @param model_id Model identifier for telemetry (e.g., "sherpa-onnx-whisper-tiny.en")
 *                 Optional: if NULL, defaults to model_path
 * @param model_name Human-readable model name (e.g., "Sherpa Whisper Tiny (ONNX)")
 *                   Optional: if NULL, defaults to model_id
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_load_model(rac_handle_t handle, const char* model_path,
                                                  const char* model_id, const char* model_name);

/**
 * @brief Unload the current model
 *
 * Cancels and drains all active proto stream sessions before unloading the
 * provider service. A re-entrant call from the component's own stream callback
 * returns RAC_ERROR_SERVICE_BUSY rather than waiting for itself.
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * Cancels and drains all active proto stream sessions before resetting the
 * provider service. A re-entrant call from the component's own stream callback
 * returns RAC_ERROR_SERVICE_BUSY rather than waiting for itself.
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_cleanup(rac_handle_t handle);

/**
 * @brief Transcribe audio data (batch mode)
 *
 * @param handle Component handle
 * @param audio_data Audio data buffer
 * @param audio_size Size of audio data in bytes
 * @param options Transcription options (can be NULL for defaults)
 * @param out_result Output: Transcription result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_transcribe(rac_handle_t handle, const void* audio_data,
                                                  size_t audio_size,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result);

/**
 * @brief Check if streaming is supported
 *
 * @param handle Component handle
 * @return RAC_TRUE if streaming supported, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_stt_component_supports_streaming(rac_handle_t handle);

/**
 * @brief Transcribe audio with the low-level raw partial/final callback.
 *
 * This remains the backend-facing C callback path. SDK-facing generated-proto
 * callers should use rac_stt_component_transcribe_stream_proto so commons emits
 * runanywhere.v1.STTStreamEvent envelopes.
 *
 * @param handle Component handle
 * @param audio_data Audio chunk data
 * @param audio_size Size of audio chunk
 * @param options Transcription options
 * @param callback Callback for partial results
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_transcribe_stream(rac_handle_t handle,
                                                         const void* audio_data, size_t audio_size,
                                                         const rac_stt_options_t* options,
                                                         rac_stt_stream_callback_t callback,
                                                         void* user_data);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_stt_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the STT component
 *
 * Cancels and drains all active proto stream sessions, closes admission to
 * every public STT component operation, and waits for already-admitted calls
 * before destroying the provider service and component. A re-entrant call
 * from any operation or callback currently using this component is rejected
 * internally and leaves the component alive because this legacy void API
 * cannot report RAC_ERROR_SERVICE_BUSY; destroy it after that call returns.
 *
 * @param handle Component handle
 */
RAC_API void rac_stt_component_destroy(rac_handle_t handle);

/**
 * @brief Get supported languages for the loaded STT model as a JSON array string.
 *
 * Forwards to the underlying service/backend. Returns RAC_ERROR_BACKEND_NOT_READY
 * if no model is loaded, or RAC_ERROR_NOT_SUPPORTED if the backend cannot enumerate.
 *
 * @param handle    Component handle
 * @param out_json  Output: malloc'd JSON string (e.g. "[\"en\",\"es\"]"). Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_get_supported_languages(rac_handle_t handle,
                                                               char** out_json);

/**
 * @brief Detect spoken language for a short audio clip.
 *
 * Forwards to the underlying service/backend. Returns RAC_ERROR_BACKEND_NOT_READY
 * if no model is loaded, or RAC_ERROR_NOT_SUPPORTED if the backend does not
 * expose language detection.
 *
 * @param handle        Component handle
 * @param audio_data    PCM audio buffer (Int16 mono, sample rate per component config)
 * @param audio_size    Size of audio_data in bytes
 * @param out_language  Output: malloc'd NUL-terminated language code. Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_detect_language(rac_handle_t handle, const void* audio_data,
                                                       size_t audio_size, char** out_language);

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

/**
 * @brief Callback fired for serialized runanywhere.v1.STTStreamEvent bytes.
 *
 * The byte buffer is valid only for the duration of the callback.
 */
typedef void (*rac_stt_proto_stream_event_callback_fn)(const uint8_t* event_proto_bytes,
                                                       size_t event_proto_size, void* user_data);

/**
 * @brief Transcribe audio using serialized runanywhere.v1.STTOptions bytes.
 *
 * Returns serialized runanywhere.v1.STTOutput bytes in out_result.
 */
RAC_API rac_result_t rac_stt_component_transcribe_proto(rac_handle_t handle, const void* audio_data,
                                                        size_t audio_size,
                                                        const uint8_t* options_proto_bytes,
                                                        size_t options_proto_size,
                                                        rac_proto_buffer_t* out_result);

/**
 * @brief Stream transcription as generated runanywhere.v1.STTStreamEvent bytes.
 */
RAC_API rac_result_t rac_stt_component_transcribe_stream_proto(
    rac_handle_t handle, const void* audio_data, size_t audio_size,
    const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_stt_proto_stream_event_callback_fn callback, void* user_data);

// =============================================================================
// Persistent per-session streaming handles.
//
// Commons exposes these thin wrappers so `rac_stt_stream.cpp` can reach the
// backend vtable without hard-coding knowledge of the service struct layout.
// Each returns RAC_ERROR_NOT_SUPPORTED if the loaded backend does not
// implement the matching vtable slot; the commons stream dispatcher then
// falls back to the per-chunk transcribe_stream path.
// =============================================================================

/**
 * @brief Allocate a backend-specific streaming session bound to the loaded STT model.
 *
 * @param handle            STT component handle.
 * @param options           Transcription options (may be NULL for backend defaults).
 * @param out_stream_handle Output: opaque backend stream handle; NULL on failure.
 *
 * @retval RAC_SUCCESS               Session created.
 * @retval RAC_ERROR_NOT_INITIALIZED No model is loaded.
 * @retval RAC_ERROR_NOT_SUPPORTED   Backend does not advertise per-session streams.
 */
RAC_API rac_result_t rac_stt_component_stream_create(rac_handle_t handle,
                                                     const rac_stt_options_t* options,
                                                     rac_handle_t* out_stream_handle);

/**
 * @brief Feed one chunk of Int16 mono PCM samples into an active backend stream.
 *
 * Partials / finals produced by the backend are pushed to @p callback
 * synchronously during the call. @p callback uses the same
 * rac_stt_stream_callback_t backend emission contract as one-shot
 * transcribe_stream calls so commons can route both through the same bridge.
 *
 * @param handle        STT component handle.
 * @param stream_handle Stream handle returned by rac_stt_component_stream_create.
 * @param samples       Int16 mono PCM samples (non-null when count > 0).
 * @param count         Number of samples at @p samples.
 * @param callback      Partial / final emission callback.
 * @param user_data     Opaque pointer forwarded to @p callback.
 *
 * @retval RAC_SUCCESS             Chunk accepted.
 * @retval RAC_ERROR_NOT_SUPPORTED Backend does not advertise per-session streams.
 */
RAC_API rac_result_t rac_stt_component_stream_feed_audio_chunk(rac_handle_t handle,
                                                               rac_handle_t stream_handle,
                                                               const int16_t* samples, size_t count,
                                                               rac_stt_stream_callback_t callback,
                                                               void* user_data);

/**
 * @brief Destroy a backend-specific streaming session.
 *
 * Safe to call with @p stream_handle == NULL (no-op). Backends that don't
 * implement the stream_destroy slot return RAC_ERROR_NOT_SUPPORTED.
 */
RAC_API rac_result_t rac_stt_component_stream_destroy(rac_handle_t handle,
                                                      rac_handle_t stream_handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_COMPONENT_H */
