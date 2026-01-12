/**
 * @file rac_stt_onnx.h
 * @brief RunAnywhere Core - ONNX Backend RAC API for STT
 *
 * Direct RAC API export from runanywhere-core's ONNX STT backend.
 * Mirrors Swift's ONNXSTTService implementation pattern.
 */

#ifndef RAC_STT_ONNX_H
#define RAC_STT_ONNX_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt.h"

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
 */
typedef enum rac_stt_onnx_model_type {
    RAC_STT_ONNX_MODEL_WHISPER = 0,
    RAC_STT_ONNX_MODEL_ZIPFORMER = 1,
    RAC_STT_ONNX_MODEL_PARAFORMER = 2,
    RAC_STT_ONNX_MODEL_AUTO = 99
} rac_stt_onnx_model_type_t;

/**
 * ONNX STT configuration.
 */
typedef struct rac_stt_onnx_config {
    rac_stt_onnx_model_type_t model_type;
    int32_t num_threads;
    rac_bool_t use_coreml;
} rac_stt_onnx_config_t;

static const rac_stt_onnx_config_t RAC_STT_ONNX_CONFIG_DEFAULT = {
    .model_type = RAC_STT_ONNX_MODEL_AUTO, .num_threads = 0, .use_coreml = RAC_TRUE};

// =============================================================================
// ONNX STT API
// =============================================================================

RAC_ONNX_API rac_result_t rac_stt_onnx_create(const char* model_path,
                                              const rac_stt_onnx_config_t* config,
                                              rac_handle_t* out_handle);

RAC_ONNX_API rac_result_t rac_stt_onnx_transcribe(rac_handle_t handle, const float* audio_samples,
                                                  size_t num_samples,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result);

RAC_ONNX_API rac_bool_t rac_stt_onnx_supports_streaming(rac_handle_t handle);

RAC_ONNX_API rac_result_t rac_stt_onnx_create_stream(rac_handle_t handle, rac_handle_t* out_stream);

RAC_ONNX_API rac_result_t rac_stt_onnx_feed_audio(rac_handle_t handle, rac_handle_t stream,
                                                  const float* audio_samples, size_t num_samples);

RAC_ONNX_API rac_bool_t rac_stt_onnx_stream_is_ready(rac_handle_t handle, rac_handle_t stream);

RAC_ONNX_API rac_result_t rac_stt_onnx_decode_stream(rac_handle_t handle, rac_handle_t stream,
                                                     char** out_text);

RAC_ONNX_API void rac_stt_onnx_input_finished(rac_handle_t handle, rac_handle_t stream);

RAC_ONNX_API rac_bool_t rac_stt_onnx_is_endpoint(rac_handle_t handle, rac_handle_t stream);

RAC_ONNX_API void rac_stt_onnx_destroy_stream(rac_handle_t handle, rac_handle_t stream);

RAC_ONNX_API void rac_stt_onnx_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_ONNX_H */
