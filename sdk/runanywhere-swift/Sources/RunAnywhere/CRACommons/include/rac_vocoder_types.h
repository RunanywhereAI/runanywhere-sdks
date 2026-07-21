/** @file rac_vocoder_types.h @brief Backend-facing mel vocoder types. */

#ifndef RAC_FEATURES_VOCODER_RAC_VOCODER_TYPES_H
#define RAC_FEATURES_VOCODER_RAC_VOCODER_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_vocoder_input {
  const float *mel_spectrogram;
  size_t value_count;
  uint32_t batch_size;
  uint32_t mel_bin_count;
  uint32_t frame_count;
} rac_vocoder_input_t;

typedef struct rac_vocoder_result {
  float *samples;
  size_t sample_value_count;
  uint32_t batch_size;
  uint32_t channel_count;
  uint32_t sample_count;
  uint32_t sample_rate_hz;
  uint32_t hop_length;
  int64_t processing_time_ms;
  char *model_id;
} rac_vocoder_result_t;

RAC_API void rac_vocoder_result_free(rac_vocoder_result_t *result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_VOCODER_RAC_VOCODER_TYPES_H */
