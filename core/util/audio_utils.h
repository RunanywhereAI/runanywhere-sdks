// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Audio utility functions — PCM to WAV conversion. Ports the capability
// surface from `sdk/runanywhere-commons/include/rac/core/rac_audio_utils.h`.

#ifndef RA_CORE_UTIL_AUDIO_UTILS_H
#define RA_CORE_UTIL_AUDIO_UTILS_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace ra::core::util {

// Encode f32 samples (normalized to [-1, 1]) to a 16-bit PCM WAV blob.
// Returns the WAV bytes including the 44-byte RIFF header.
std::vector<std::uint8_t> encode_wav_f32(const float*   samples,
                                          std::size_t    num_samples,
                                          int            sample_rate_hz,
                                          int            channels = 1);

// Encode int16 samples directly — no sample conversion.
std::vector<std::uint8_t> encode_wav_s16(const std::int16_t* samples,
                                          std::size_t         num_samples,
                                          int                 sample_rate_hz,
                                          int                 channels = 1);

// Decode a 16-bit PCM WAV blob into f32 samples. Returns empty vector on
// parse failure. *out_sample_rate_hz + *out_channels populated on success.
std::vector<float> decode_wav_f32(const std::uint8_t* data,
                                    std::size_t         n,
                                    int*                out_sample_rate_hz,
                                    int*                out_channels);

}  // namespace ra::core::util

#endif  // RA_CORE_UTIL_AUDIO_UTILS_H
