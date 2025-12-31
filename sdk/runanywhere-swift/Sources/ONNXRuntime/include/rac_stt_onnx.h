/**
 * @file rac_stt_onnx.h
 * @brief RunAnywhere Commons - ONNX Backend for STT
 *
 * C wrapper around runanywhere-core's ONNX STT backend.
 * Mirrors Swift's ONNXSTTService implementation.
 *
 * See: Sources/ONNXRuntime/ONNXSTTService.swift
 */

#ifndef RAC_STT_ONNX_H
#define RAC_STT_ONNX_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_stt.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_ONNX_BUILDING)
#if defined(_WIN32)
#define RAC_ONNX_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_ONNX_API __attribute__((visibility("default")))
#else
#define RAC_ONNX_API
#endif
#else
#define RAC_ONNX_API
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * ONNX STT model types.
 * Mirrors detection logic in ONNXSTTService.detectModelType().
 */
typedef enum rac_stt_onnx_model_type {
    RAC_STT_ONNX_MODEL_WHISPER = 0,
    RAC_STT_ONNX_MODEL_ZIPFORMER = 1,
    RAC_STT_ONNX_MODEL_PARAFORMER = 2,
    RAC_STT_ONNX_MODEL_AUTO = 99  // Auto-detect
} rac_stt_onnx_model_type_t;

/**
 * ONNX STT configuration.
 */
typedef struct rac_stt_onnx_config {
    /** Model type (or AUTO for detection) */
    rac_stt_onnx_model_type_t model_type;

    /** Number of threads (0 = auto) */
    int32_t num_threads;

    /** Enable CoreML on Apple platforms */
    rac_bool_t use_coreml;
} rac_stt_onnx_config_t;

/**
 * Default ONNX STT configuration.
 */
static const rac_stt_onnx_config_t RAC_STT_ONNX_CONFIG_DEFAULT = {
    .model_type = RAC_STT_ONNX_MODEL_AUTO, .num_threads = 0, .use_coreml = RAC_TRUE};

// =============================================================================
// ONNX STT API
// =============================================================================

/**
 * Creates an ONNX STT service.
 *
 * Mirrors Swift's ONNXSTTService.initialize(modelPath:)
 *
 * @param model_path Path to the model directory or file
 * @param config ONNX-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_stt_onnx_create(const char* model_path,
                                              const rac_stt_onnx_config_t* config,
                                              rac_handle_t* out_handle);

/**
 * Transcribes audio data.
 *
 * Mirrors Swift's ONNXSTTService.transcribe(audioData:options:)
 *
 * @param handle Service handle
 * @param audio_samples Float32 PCM samples (16kHz mono)
 * @param num_samples Number of samples
 * @param options STT options (can be NULL for defaults)
 * @param out_result Output: Transcription result
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                                  size_t num_samples,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result);

/**
 * Checks if streaming is supported.
 *
 * Mirrors Swift's ONNXSTTService.supportsStreaming
 *
 * @param handle Service handle
 * @return RAC_TRUE if streaming is supported
 */
RAC_ONNX_API rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle);

/**
 * Creates a streaming session.
 *
 * @param handle Service handle
 * @param out_stream Output: Stream handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream);

/**
 * Feeds audio to a streaming session.
 *
 * @param handle Service handle
 * @param stream Stream handle
 * @param audio_samples Float32 PCM samples
 * @param num_samples Number of samples
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                                  const float* audio_samples, size_t num_samples);

/**
 * Checks if stream is ready for decoding.
 *
 * @param handle Service handle
 * @param stream Stream handle
 * @return RAC_TRUE if ready
 */
RAC_ONNX_API rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream);

/**
 * Decodes current stream state.
 *
 * @param handle Service handle
 * @param stream Stream handle
 * @param out_text Output: Partial transcription (caller must free)
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream,
                                                     char** out_text);

/**
 * Signals end of audio input.
 *
 * @param handle Service handle
 * @param stream Stream handle
 */
RAC_ONNX_API void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream);

/**
 * Checks if endpoint (end of speech) detected.
 *
 * @param handle Service handle
 * @param stream Stream handle
 * @return RAC_TRUE if endpoint detected
 */
RAC_ONNX_API rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream);

/**
 * Destroys a streaming session.
 *
 * @param handle Service handle
 * @param stream Stream handle to destroy
 */
RAC_ONNX_API void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream);

/**
 * Destroys an ONNX STT service.
 *
 * @param handle Service handle to destroy
 */
RAC_ONNX_API void rac_stt_onnx_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_ONNX_H */
