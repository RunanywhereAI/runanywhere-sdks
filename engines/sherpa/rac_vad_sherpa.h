#ifndef RAC_VAD_SHERPA_H
#define RAC_VAD_SHERPA_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/vad/rac_vad.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_vad_sherpa_config {
    int32_t sample_rate;
    float energy_threshold;
    float frame_length;
    int32_t num_threads;
} rac_vad_sherpa_config_t;

static const rac_vad_sherpa_config_t RAC_VAD_SHERPA_CONFIG_DEFAULT = {
    .sample_rate = 16000, .energy_threshold = 0.5f, .frame_length = 0.032f, .num_threads = 0};

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
