/**
 * @file rac_audio_utils.cpp
 * @brief RunAnywhere Commons - Audio Utility Functions Implementation
 *
 * Provides audio format conversion and level-meter utilities used across the SDK.
 */

#include "rac/core/rac_audio_utils.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

#include "rac/core/rac_error.h"

// WAV file constants
static constexpr size_t WAV_HEADER_SIZE = 44;
static constexpr uint16_t WAV_FORMAT_PCM = 1;
static constexpr uint16_t WAV_CHANNELS_MONO = 1;
static constexpr uint16_t WAV_BITS_PER_SAMPLE_16 = 16;

/**
 * @brief Write a little-endian uint16_t to a buffer
 */
static void write_uint16_le(uint8_t* buffer, uint16_t value) {
    buffer[0] = static_cast<uint8_t>(value & 0xFF);
    buffer[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
}

/**
 * @brief Write a little-endian uint32_t to a buffer
 */
static void write_uint32_le(uint8_t* buffer, uint32_t value) {
    buffer[0] = static_cast<uint8_t>(value & 0xFF);
    buffer[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    buffer[2] = static_cast<uint8_t>((value >> 16) & 0xFF);
    buffer[3] = static_cast<uint8_t>((value >> 24) & 0xFF);
}

/**
 * @brief Build a WAV header for PCM audio
 *
 * @param header Buffer to write header to (must be at least 44 bytes)
 * @param sample_rate Sample rate in Hz
 * @param data_size Size of audio data in bytes (Int16 samples)
 */
static void build_wav_header(uint8_t* header, int32_t sample_rate, uint32_t data_size) {
    // RIFF header
    // Bytes 0-3: "RIFF"
    header[0] = 'R';
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';

    // Bytes 4-7: File size minus 8 (RIFF header size)
    uint32_t file_size = data_size + WAV_HEADER_SIZE - 8;
    write_uint32_le(&header[4], file_size);

    // Bytes 8-11: "WAVE"
    header[8] = 'W';
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';

    // fmt chunk
    // Bytes 12-15: "fmt "
    header[12] = 'f';
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';

    // Bytes 16-19: fmt chunk size (16 for PCM)
    write_uint32_le(&header[16], 16);

    // Bytes 20-21: Audio format (1 = PCM)
    write_uint16_le(&header[20], WAV_FORMAT_PCM);

    // Bytes 22-23: Number of channels (1 = mono)
    write_uint16_le(&header[22], WAV_CHANNELS_MONO);

    // Bytes 24-27: Sample rate
    write_uint32_le(&header[24], static_cast<uint32_t>(sample_rate));

    // Bytes 28-31: Byte rate = sample_rate * channels * bytes_per_sample
    uint32_t byte_rate =
        static_cast<uint32_t>(sample_rate) * WAV_CHANNELS_MONO * (WAV_BITS_PER_SAMPLE_16 / 8);
    write_uint32_le(&header[28], byte_rate);

    // Bytes 32-33: Block align = channels * bytes_per_sample
    uint16_t block_align = WAV_CHANNELS_MONO * (WAV_BITS_PER_SAMPLE_16 / 8);
    write_uint16_le(&header[32], block_align);

    // Bytes 34-35: Bits per sample
    write_uint16_le(&header[34], WAV_BITS_PER_SAMPLE_16);

    // data chunk
    // Bytes 36-39: "data"
    header[36] = 'd';
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';

    // Bytes 40-43: Data size
    write_uint32_le(&header[40], data_size);
}

static int16_t quantize_float_to_pcm16(float sample) {
    if (!std::isfinite(sample)) {
        return 0;
    }
    const float clamped = std::clamp(sample, -1.0f, 1.0f);
    const float scaled = std::round(clamped * RAC_AUDIO_PCM16_SCALE);
    return static_cast<int16_t>(std::clamp(scaled, -32768.0f, 32767.0f));
}

rac_result_t rac_audio_pcm16_to_float32(const int16_t* in, size_t n_samples, float* out) {
    if (n_samples == 0) {
        return RAC_SUCCESS;
    }
    if (in == nullptr || out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    for (size_t i = 0; i < n_samples; ++i) {
        out[i] = static_cast<float>(in[i]) / RAC_AUDIO_PCM16_SCALE;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_audio_float32_to_pcm16(const float* in, size_t n_samples, int16_t* out) {
    if (n_samples == 0) {
        return RAC_SUCCESS;
    }
    if (in == nullptr || out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    for (size_t i = 0; i < n_samples; ++i) {
        out[i] = quantize_float_to_pcm16(in[i]);
    }
    return RAC_SUCCESS;
}

rac_result_t rac_audio_float32_to_wav(const void* pcm_data, size_t pcm_size, int32_t sample_rate,
                                      void** out_wav_data, size_t* out_wav_size) {
    // Validate arguments
    if (!pcm_data || pcm_size == 0 || !out_wav_data || !out_wav_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Float32 is 4 bytes per sample
    if (pcm_size % 4 != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (sample_rate <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const size_t num_samples = pcm_size / sizeof(float);

    // Guard against WAV header overflow: data_size field is uint32_t (max ~4GB)
    if (num_samples > UINT32_MAX / sizeof(int16_t)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Int16 data size (2 bytes per sample)
    const uint32_t int16_data_size = static_cast<uint32_t>(num_samples * sizeof(int16_t));

    // Total WAV file size
    const size_t wav_size = WAV_HEADER_SIZE + int16_data_size;

    // Allocate output buffer
    uint8_t* wav_data = static_cast<uint8_t*>(rac_alloc(wav_size));
    if (!wav_data) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Build WAV header
    build_wav_header(wav_data, sample_rate, int16_data_size);

    // Single quantization rule via the public PCM16 encoder.
    const float* float_samples = static_cast<const float*>(pcm_data);
    int16_t* int16_samples = reinterpret_cast<int16_t*>(wav_data + WAV_HEADER_SIZE);
    const rac_result_t qrc = rac_audio_float32_to_pcm16(float_samples, num_samples, int16_samples);
    if (qrc != RAC_SUCCESS) {
        rac_free(wav_data);
        return qrc;
    }

    *out_wav_data = wav_data;
    *out_wav_size = wav_size;

    return RAC_SUCCESS;
}

rac_result_t rac_audio_int16_to_wav(const void* pcm_data, size_t pcm_size, int32_t sample_rate,
                                    void** out_wav_data, size_t* out_wav_size) {
    // Validate arguments
    if (!pcm_data || pcm_size == 0 || !out_wav_data || !out_wav_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Int16 is 2 bytes per sample
    if (pcm_size % 2 != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (sample_rate <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Guard against WAV header overflow: the RIFF chunk-size field (data_size + 36)
    // is uint32_t, so data_size must leave room for the 36-byte header overhead.
    if (pcm_size > static_cast<size_t>(UINT32_MAX) - (WAV_HEADER_SIZE - 8)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const uint32_t data_size = static_cast<uint32_t>(pcm_size);

    // Total WAV file size
    const size_t wav_size = WAV_HEADER_SIZE + data_size;

    // Allocate output buffer
    uint8_t* wav_data = static_cast<uint8_t*>(rac_alloc(wav_size));
    if (!wav_data) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Build WAV header
    build_wav_header(wav_data, sample_rate, data_size);

    // Copy Int16 data directly
    memcpy(wav_data + WAV_HEADER_SIZE, pcm_data, pcm_size);

    *out_wav_data = wav_data;
    *out_wav_size = wav_size;

    return RAC_SUCCESS;
}

size_t rac_audio_wav_header_size(void) {
    return WAV_HEADER_SIZE;
}

rac_result_t rac_audio_compute_level_db(const float* samples, size_t count, float* out_db) {
    if (!samples || count == 0 || !out_db) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Accumulate squared samples in double precision to avoid loss-of-significance
    // on long buffers (e.g. 4096-sample taps at 16 kHz).
    double sum_sq = 0.0;
    for (size_t i = 0; i < count; ++i) {
        sum_sq += static_cast<double>(samples[i]) * static_cast<double>(samples[i]);
    }

    const double rms = std::sqrt(sum_sq / static_cast<double>(count));

    // Silence floor: clamp -inf to -100 dB (well below the -60 dB normalisation
    // bottom used by audio meters in the platform SDKs).
    *out_db = (rms <= 1e-10) ? -100.0f : static_cast<float>(20.0 * std::log10(rms));
    return RAC_SUCCESS;
}

rac_result_t rac_audio_compute_level_normalized(const float* samples, size_t count, float floor_db,
                                                float* out_0_1) {
    if (!out_0_1) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (!(floor_db < 0.0f) || !std::isfinite(floor_db)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    float db = 0.0f;
    const rac_result_t rc = rac_audio_compute_level_db(samples, count, &db);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    // Map [floor_db, 0] → [0, 1]. Example floor_db=-60: (db + 60) / 60.
    const float span = -floor_db;
    *out_0_1 = std::clamp((db - floor_db) / span, 0.0f, 1.0f);
    return RAC_SUCCESS;
}

rac_result_t rac_audio_resample_f32(const float* in, size_t in_frames, int32_t in_rate,
                                    int32_t out_rate, float** out, size_t* out_frames) {
    if (!out || !out_frames) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out = nullptr;
    *out_frames = 0;

    if (in_frames == 0) {
        return RAC_SUCCESS;
    }
    if (in == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (in_rate <= 0 || out_rate <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    size_t out_len = 0;
    if (in_rate == out_rate) {
        out_len = in_frames;
    } else {
        const double scaled = static_cast<double>(in_frames) * static_cast<double>(out_rate) /
                              static_cast<double>(in_rate);
        if (scaled <= 0.0) {
            return RAC_SUCCESS;
        }
        out_len = static_cast<size_t>(std::llround(scaled));
        if (out_len == 0) {
            return RAC_SUCCESS;
        }
    }

    float* buffer = static_cast<float*>(rac_alloc(out_len * sizeof(float)));
    if (!buffer) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (in_rate == out_rate) {
        std::memcpy(buffer, in, out_len * sizeof(float));
    } else {
        const double ratio =
            static_cast<double>(in_rate) / static_cast<double>(out_rate);
        for (size_t i = 0; i < out_len; ++i) {
            const double src_idx = static_cast<double>(i) * ratio;
            size_t idx0 = static_cast<size_t>(src_idx);
            size_t idx1 = idx0 + 1;
            if (idx0 >= in_frames) {
                idx0 = in_frames - 1;
            }
            if (idx1 >= in_frames) {
                idx1 = in_frames - 1;
            }
            const double frac = src_idx - static_cast<double>(idx0);
            buffer[i] = static_cast<float>(static_cast<double>(in[idx0]) * (1.0 - frac) +
                                           static_cast<double>(in[idx1]) * frac);
        }
    }

    *out = buffer;
    *out_frames = out_len;
    return RAC_SUCCESS;
}

rac_result_t rac_audio_pcm_bytes_to_ms(size_t byte_count, const rac_audio_format_t* format,
                                       int64_t* out_ms) {
    if (!format || !out_ms) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (format->sample_rate <= 0 || format->channels < 1) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (format->bits_per_sample != 16 && format->bits_per_sample != 32) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const size_t bytes_per_sample = static_cast<size_t>(format->bits_per_sample) / 8u;
    const size_t bytes_per_frame = bytes_per_sample * static_cast<size_t>(format->channels);
    if (bytes_per_frame == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_ms = static_cast<int64_t>(
        (static_cast<double>(byte_count) / static_cast<double>(bytes_per_frame) /
         static_cast<double>(format->sample_rate)) *
        1000.0);
    return RAC_SUCCESS;
}
