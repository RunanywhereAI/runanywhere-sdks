/**
 * @file rac_tts_onnx.h
 * @brief RunAnywhere Core - ONNX Backend RAC API for TTS
 *
 * Direct RAC API export from runanywhere-core's ONNX TTS backend.
 */

#ifndef RAC_TTS_ONNX_H
#define RAC_TTS_ONNX_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts.h"

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

typedef struct rac_tts_onnx_config {
    int32_t num_threads;
    rac_bool_t use_coreml;
    int32_t sample_rate;
} rac_tts_onnx_config_t;

static const rac_tts_onnx_config_t RAC_TTS_ONNX_CONFIG_DEFAULT = {
    .num_threads = 0, .use_coreml = RAC_TRUE, .sample_rate = 22050};

// =============================================================================
// ONNX TTS API
// =============================================================================

RAC_ONNX_API rac_result_t rac_tts_onnx_create(const char* model_path,
                                              const rac_tts_onnx_config_t* config,
                                              rac_handle_t* out_handle);

RAC_ONNX_API rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text,
                                                  const rac_tts_options_t* options,
                                                  rac_tts_result_t* out_result);

RAC_ONNX_API rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices,
                                                  size_t* out_count);

RAC_ONNX_API void rac_tts_onnx_stop(rac_handle_t handle);

RAC_ONNX_API void rac_tts_onnx_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_ONNX_H */
