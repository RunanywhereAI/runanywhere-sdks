/**
 * @file wav_io.h
 * @brief CLI-owned WAV file I/O and RIFF format parsing.
 *
 * PCM conversion, linear resampling, and RIFF/WAV container synthesis live in
 * commons (`rac_audio_*`). This header only exposes path-based read/write and
 * thin wrappers that forward to those primitives.
 */

#ifndef RCLI_IO_WAV_IO_H
#define RCLI_IO_WAV_IO_H

#include <cstdint>
#include <string>
#include <vector>

namespace rcli::wav {

struct WavData {
    std::vector<int16_t> samples;  // mono (channels collapsed by averaging)
    int sample_rate = 0;
};

/** Read a RIFF/WAVE file (16-bit PCM only). Returns false + error message. */
bool read_wav(const std::string& path, WavData* out, std::string* error);

/** Write mono 16-bit PCM samples as a WAV file via rac_audio_int16_to_wav. */
bool write_wav(const std::string& path, const int16_t* samples, size_t count, int sample_rate,
               std::string* error);

/** Write mono float32 PCM samples as a WAV file via rac_audio_float32_to_wav. */
bool write_wav_f32(const std::string& path, const float* samples, size_t count, int sample_rate,
                   std::string* error);

/** Linear resample via rac_audio_resample_f32 (PCM16 ↔ float around the call). */
std::vector<int16_t> resample(const std::vector<int16_t>& samples, int from_rate, int to_rate);

/** int16 → float [-1, 1] via rac_audio_pcm16_to_float32. */
std::vector<float> to_float(const std::vector<int16_t>& samples);

}  // namespace rcli::wav

#endif  // RCLI_IO_WAV_IO_H
