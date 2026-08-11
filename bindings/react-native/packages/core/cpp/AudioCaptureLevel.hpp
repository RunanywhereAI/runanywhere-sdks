/**
 * AudioCaptureLevel.hpp
 *
 * Thin C ABI around commons `rac_audio_pcm16_to_float32` /
 * `rac_audio_compute_level_normalized` for RN HybridAudioCapture (iOS/Android).
 * Keeps RMS→dB→[0,1] out of the handwritten capture managers.
 */
#pragma once

#include <cstddef>
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

/** Normalized [0,1] meter from float32 PCM. Empty / failure → 0. */
double ra_audio_capture_level_normalized_f32(const float *samples, size_t count);

/** Normalized [0,1] meter from int16 PCM. Empty / failure → 0. */
double ra_audio_capture_level_normalized_pcm16(const int16_t *pcm, size_t n_samples);

#ifdef __cplusplus
}
#endif
