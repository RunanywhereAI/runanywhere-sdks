/**
 * @file rac_audio_convert.h
 * @brief Shared inline audio-conversion helpers for engine backends.
 *
 * STT backends previously hand-rolled identical Int16 -> Float32 PCM
 * conversion routines inside their `vtable_transcribe` trampolines. This
 * header centralizes that conversion so every STT backend can normalize Int16
 * PCM to Float32 in [-1.0, 1.0] without duplication.
 *
 * Scope:
 *   - sherpa and metalrt-STT consume this header today.
 *     Any STT engine that resamples Int16 mic PCM to Float32 for its
 *     transcription entry point should call this helper rather than
 *     repeating the 1.0f/32768.0f scaling loop.
 */

#ifndef RAC_AUDIO_CONVERT_H
#define RAC_AUDIO_CONVERT_H

#include <cstddef>
#include <cstdint>

namespace rac {
namespace audio {

/**
 * @brief Convert a block of Int16 PCM samples to Float32 in [-1.0, 1.0].
 *
 * Dividing by 32768.0f matches the historical behavior used across every
 * in-tree backend. The caller owns both buffers; `out` MUST hold at least
 * `n_samples` floats.
 *
 * If `in` is NULL or `n_samples` is zero the call is a no-op.
 */
inline void rac_audio_pcm16_to_float32(const int16_t* in, size_t n_samples, float* out) {
    if (in == nullptr || out == nullptr || n_samples == 0)
        return;
    for (size_t i = 0; i < n_samples; ++i) {
        out[i] = static_cast<float>(in[i]) / 32768.0f;
    }
}

}  // namespace audio
}  // namespace rac

#endif /* RAC_AUDIO_CONVERT_H */
