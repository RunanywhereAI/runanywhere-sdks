#ifndef RAC_VAD_SHERPA_H
#define RAC_VAD_SHERPA_H

#include "rac/backends/rac_vad_onnx.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef rac_vad_onnx_config_t rac_vad_sherpa_config_t;

rac_result_t rac_vad_sherpa_create(const char* model_path, const rac_vad_sherpa_config_t* config,
                                   rac_handle_t* out_handle);
rac_result_t rac_vad_sherpa_process(rac_handle_t handle, const float* samples, size_t num_samples,
                                    rac_bool_t* out_is_speech);
rac_result_t rac_vad_sherpa_start(rac_handle_t handle);
rac_result_t rac_vad_sherpa_stop(rac_handle_t handle);
rac_result_t rac_vad_sherpa_reset(rac_handle_t handle);
rac_result_t rac_vad_sherpa_set_threshold(rac_handle_t handle, float threshold);
rac_bool_t rac_vad_sherpa_is_speech_active(rac_handle_t handle);
void rac_vad_sherpa_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_SHERPA_H */
