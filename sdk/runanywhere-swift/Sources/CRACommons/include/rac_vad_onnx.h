/**
 * @file rac_vad_onnx.h
 * @brief RunAnywhere Core - ONNX Backend RAC API for VAD
 *
 * Direct RAC API export from runanywhere-core's ONNX VAD backend.
 */

#ifndef RAC_VAD_ONNX_H
#define RAC_VAD_ONNX_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_vad.h"

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

typedef struct rac_vad_onnx_config {
    int32_t sample_rate;
    float energy_threshold;
    float frame_length;
    int32_t num_threads;
} rac_vad_onnx_config_t;

static const rac_vad_onnx_config_t RAC_VAD_ONNX_CONFIG_DEFAULT = {
    .sample_rate = 16000, .energy_threshold = 0.5f, .frame_length = 0.032f, .num_threads = 0};

// =============================================================================
// ONNX VAD API
// =============================================================================

RAC_ONNX_API rac_result_t rac_vad_onnx_create(const char* model_path,
                                              const rac_vad_onnx_config_t* config,
                                              rac_handle_t* out_handle);

RAC_ONNX_API rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples,
                                               size_t num_samples, rac_bool_t* out_is_speech);

RAC_ONNX_API rac_result_t rac_vad_onnx_start(rac_handle_t handle);

RAC_ONNX_API rac_result_t rac_vad_onnx_stop(rac_handle_t handle);

RAC_ONNX_API rac_result_t rac_vad_onnx_reset(rac_handle_t handle);

RAC_ONNX_API rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold);

RAC_ONNX_API rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle);

RAC_ONNX_API void rac_vad_onnx_destroy(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

RAC_ONNX_API rac_result_t rac_backend_onnx_register(void);

RAC_ONNX_API rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ONNX_H */
