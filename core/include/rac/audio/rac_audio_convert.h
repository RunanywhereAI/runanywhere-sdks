/**
 * @file rac_audio_convert.h
 * @brief Compatibility wrapper for engine backends that convert Int16 ↔ Float32.
 *
 * Prefer the C ABI in rac/core/rac_audio_utils.h
 * (`rac_audio_pcm16_to_float32` / `rac_audio_float32_to_pcm16`).
 * This header keeps the historical `rac::audio::` inline name so sherpa and
 * other in-tree backends compile unchanged while sharing one implementation.
 *
 * Canonical scale: RAC_AUDIO_PCM16_SCALE (32768.0f) — see rac_audio_utils.h.
 */

#ifndef RAC_AUDIO_CONVERT_H
#define RAC_AUDIO_CONVERT_H

#include <cstddef>
#include <cstdint>

#include "rac/core/rac_audio_utils.h"

namespace rac {
namespace audio {

/**
 * @brief Convert a block of Int16 PCM samples to Float32 in [-1.0, 1.0].
 *
 * Forwards to the C ABI. The caller owns both buffers; `out` MUST hold at least
 * `n_samples` floats. NULL inputs or a zero sample count are a no-op.
 */
inline void rac_audio_pcm16_to_float32(const int16_t* in, size_t n_samples, float* out) {
    (void)::rac_audio_pcm16_to_float32(in, n_samples, out);
}

/**
 * @brief Quantize Float32 samples in [-1.0, 1.0] to Int16 PCM.
 *
 * Forwards to the C ABI (`RAC_AUDIO_PCM16_SCALE` round + saturate).
 */
inline void rac_audio_float32_to_pcm16(const float* in, size_t n_samples, int16_t* out) {
    (void)::rac_audio_float32_to_pcm16(in, n_samples, out);
}

}  // namespace audio
}  // namespace rac

#endif /* RAC_AUDIO_CONVERT_H */
