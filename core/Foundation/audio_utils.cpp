// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "audio_utils.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace ra::core::util {

namespace {

// Little-endian writer — portable across host endianness. The macOS + Linux
// CI runners are both little-endian but we don't want to rely on that.
void write_le_u16(std::vector<std::uint8_t>& out, std::uint16_t v) {
    out.push_back(static_cast<std::uint8_t>(v & 0xff));
    out.push_back(static_cast<std::uint8_t>((v >> 8) & 0xff));
}
void write_le_u32(std::vector<std::uint8_t>& out, std::uint32_t v) {
    out.push_back(static_cast<std::uint8_t>(v & 0xff));
    out.push_back(static_cast<std::uint8_t>((v >> 8) & 0xff));
    out.push_back(static_cast<std::uint8_t>((v >> 16) & 0xff));
    out.push_back(static_cast<std::uint8_t>((v >> 24) & 0xff));
}
std::uint16_t read_le_u16(const std::uint8_t* p) {
    return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
}
std::uint32_t read_le_u32(const std::uint8_t* p) {
    return static_cast<std::uint32_t>(p[0]) |
           (static_cast<std::uint32_t>(p[1]) << 8) |
           (static_cast<std::uint32_t>(p[2]) << 16) |
           (static_cast<std::uint32_t>(p[3]) << 24);
}

void write_wav_header(std::vector<std::uint8_t>& out,
                       int sample_rate, int channels, int bits_per_sample,
                       std::uint32_t data_bytes) {
    const std::uint32_t byte_rate   = static_cast<std::uint32_t>(sample_rate) *
                                       static_cast<std::uint32_t>(channels) *
                                       static_cast<std::uint32_t>(bits_per_sample / 8);
    const std::uint16_t block_align = static_cast<std::uint16_t>(channels *
                                                                   (bits_per_sample / 8));

    // RIFF header.
    out.insert(out.end(), {'R','I','F','F'});
    write_le_u32(out, 36 + data_bytes);
    out.insert(out.end(), {'W','A','V','E'});

    // fmt chunk.
    out.insert(out.end(), {'f','m','t',' '});
    write_le_u32(out, 16);                                 // chunk size
    write_le_u16(out, 1);                                  // PCM format
    write_le_u16(out, static_cast<std::uint16_t>(channels));
    write_le_u32(out, static_cast<std::uint32_t>(sample_rate));
    write_le_u32(out, byte_rate);
    write_le_u16(out, block_align);
    write_le_u16(out, static_cast<std::uint16_t>(bits_per_sample));

    // data chunk header.
    out.insert(out.end(), {'d','a','t','a'});
    write_le_u32(out, data_bytes);
}

}  // namespace

std::vector<std::uint8_t> encode_wav_f32(const float* samples,
                                          std::size_t  num_samples,
                                          int          sample_rate,
                                          int          channels) {
    std::vector<std::uint8_t> out;
    if (!samples || num_samples == 0 || sample_rate <= 0 || channels <= 0) return out;
    const std::uint32_t data_bytes =
        static_cast<std::uint32_t>(num_samples) * 2u;
    out.reserve(44 + data_bytes);
    write_wav_header(out, sample_rate, channels, 16, data_bytes);

    // Clamp to [-1, 1] and convert.
    for (std::size_t i = 0; i < num_samples; ++i) {
        float s = samples[i];
        s = std::clamp(s, -1.f, 1.f);
        const std::int16_t v = static_cast<std::int16_t>(
            std::lrintf(s * 32767.f));
        const auto u = static_cast<std::uint16_t>(v);
        out.push_back(static_cast<std::uint8_t>(u & 0xff));
        out.push_back(static_cast<std::uint8_t>((u >> 8) & 0xff));
    }
    return out;
}

std::vector<std::uint8_t> encode_wav_s16(const std::int16_t* samples,
                                          std::size_t         num_samples,
                                          int                 sample_rate,
                                          int                 channels) {
    std::vector<std::uint8_t> out;
    if (!samples || num_samples == 0 || sample_rate <= 0 || channels <= 0) return out;
    const std::uint32_t data_bytes =
        static_cast<std::uint32_t>(num_samples) * 2u;
    out.reserve(44 + data_bytes);
    write_wav_header(out, sample_rate, channels, 16, data_bytes);
    for (std::size_t i = 0; i < num_samples; ++i) {
        const auto u = static_cast<std::uint16_t>(samples[i]);
        out.push_back(static_cast<std::uint8_t>(u & 0xff));
        out.push_back(static_cast<std::uint8_t>((u >> 8) & 0xff));
    }
    return out;
}

std::vector<float> decode_wav_f32(const std::uint8_t* data, std::size_t n,
                                    int* out_sr, int* out_ch) {
    std::vector<float> out;
    if (!data || n < 44) return out;
    if (std::memcmp(data,  "RIFF", 4) != 0) return out;
    if (std::memcmp(data + 8,  "WAVE", 4) != 0) return out;
    if (std::memcmp(data + 12, "fmt ", 4) != 0) return out;

    const auto fmt        = read_le_u16(data + 20);
    const auto channels   = read_le_u16(data + 22);
    const auto sample_rate = read_le_u32(data + 24);
    const auto bits       = read_le_u16(data + 34);
    if (fmt != 1 || bits != 16 || channels == 0) return out;

    // Walk chunks to find "data".
    std::size_t p = 36;
    while (p + 8 <= n) {
        if (std::memcmp(data + p, "data", 4) == 0) {
            const auto data_bytes = read_le_u32(data + p + 4);
            const std::size_t offset = p + 8;
            if (offset + data_bytes > n) return out;
            const auto* samples = reinterpret_cast<const std::int16_t*>(data + offset);
            const std::size_t count = data_bytes / 2;
            out.resize(count);
            for (std::size_t i = 0; i < count; ++i) {
                out[i] = static_cast<float>(samples[i]) / 32768.f;
            }
            if (out_sr) *out_sr = static_cast<int>(sample_rate);
            if (out_ch) *out_ch = static_cast<int>(channels);
            return out;
        }
        const auto chunk_bytes = read_le_u32(data + p + 4);
        p += 8 + chunk_bytes + (chunk_bytes & 1u);  // pad to even
    }
    return out;
}

}  // namespace ra::core::util
