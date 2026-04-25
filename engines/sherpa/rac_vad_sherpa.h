#ifndef RAC_VAD_SHERPA_H
#define RAC_VAD_SHERPA_H

#include "rac/backends/rac_vad_onnx.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(RAC_SHERPA_BUILDING)
#if defined(_WIN32)
#define RAC_SHERPA_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_SHERPA_API __attribute__((visibility("default")))
#else
#define RAC_SHERPA_API
#endif
#else
#define RAC_SHERPA_API
#endif

typedef rac_vad_onnx_config_t rac_vad_sherpa_config_t;

RAC_SHERPA_API rac_result_t rac_vad_sherpa_create(const char* model_path,
                                                  const rac_vad_sherpa_config_t* config,
                                                  rac_handle_t* out_handle);
RAC_SHERPA_API rac_result_t rac_vad_sherpa_process(rac_handle_t handle, const float* samples,
                                                   size_t num_samples, rac_bool_t* out_is_speech);
RAC_SHERPA_API rac_result_t rac_vad_sherpa_start(rac_handle_t handle);
RAC_SHERPA_API rac_result_t rac_vad_sherpa_stop(rac_handle_t handle);
RAC_SHERPA_API rac_result_t rac_vad_sherpa_reset(rac_handle_t handle);
RAC_SHERPA_API rac_result_t rac_vad_sherpa_set_threshold(rac_handle_t handle, float threshold);
RAC_SHERPA_API rac_bool_t rac_vad_sherpa_is_speech_active(rac_handle_t handle);
RAC_SHERPA_API void rac_vad_sherpa_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_SHERPA_H */
