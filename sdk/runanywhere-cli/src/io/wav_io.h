/**
 * @file wav_io.h
 * @brief Minimal 16-bit PCM WAV read/write + linear resampling.
 *
 * Mirrors the helpers the commons tests use (tests/test_common.h read_wav /
 * write_wav / resample_linear) so files are interchangeable with the test rig.
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

/** Write mono 16-bit PCM samples as a WAV file. */
bool write_wav(const std::string& path, const int16_t* samples, size_t count, int sample_rate,
               std::string* error);

/** Linear resample to target_rate (no-op when rates match). */
std::vector<int16_t> resample(const std::vector<int16_t>& samples, int from_rate, int to_rate);

/** int16 → float [-1, 1]. */
std::vector<float> to_float(const std::vector<int16_t>& samples);

/** float [-1, 1] → int16 (clamped). */
std::vector<int16_t> to_int16(const float* samples, size_t count);

}  // namespace rcli::wav

#endif  // RCLI_IO_WAV_IO_H
