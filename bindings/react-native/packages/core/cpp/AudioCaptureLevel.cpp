/**
 * AudioCaptureLevel.cpp
 *
 * Commons-owned mic-meter math for HybridAudioCapture.
 */
#include "AudioCaptureLevel.hpp"

#include "rac/core/rac_audio_utils.h"

#include <vector>

extern "C" double ra_audio_capture_level_normalized_f32(const float *samples,
                                                         size_t count) {
  if (samples == nullptr || count == 0) {
    return 0.0;
  }
  float out = 0.0f;
  const rac_result_t rc = rac_audio_compute_level_normalized(
      samples, count, RAC_AUDIO_LEVEL_FLOOR_DB, &out);
  if (rc != RAC_SUCCESS) {
    return 0.0;
  }
  return static_cast<double>(out);
}

extern "C" double ra_audio_capture_level_normalized_pcm16(const int16_t *pcm,
                                                          size_t n_samples) {
  if (pcm == nullptr || n_samples == 0) {
    return 0.0;
  }
  std::vector<float> floats(n_samples);
  const rac_result_t convertRc =
      rac_audio_pcm16_to_float32(pcm, n_samples, floats.data());
  if (convertRc != RAC_SUCCESS) {
    return 0.0;
  }
  return ra_audio_capture_level_normalized_f32(floats.data(), n_samples);
}
