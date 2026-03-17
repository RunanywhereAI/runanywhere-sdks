/**
 * @file rac_audio_utils.cpp
 * @brief RunAnywhere Commons - Audio Utility Functions Implementation
 *
 * Provides audio format conversion utilities used across the SDK.
 */

#include "rac/core/rac_audio_utils.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

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
    uint8_t* wav_data = static_cast<uint8_t*>(malloc(wav_size));
    if (!wav_data) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Build WAV header
    build_wav_header(wav_data, sample_rate, int16_data_size);

    // Convert Float32 to Int16
    // Use __restrict to guarantee no aliasing, enabling auto-vectorization.
    // The loop body is kept simple (multiply + clamp) so compilers can emit
    // NEON (ARM) or SSE/AVX (x86) vector instructions with -O2.
    const float* __restrict float_samples = static_cast<const float*>(pcm_data);
    int16_t* __restrict int16_samples = reinterpret_cast<int16_t*>(wav_data + WAV_HEADER_SIZE);

    for (size_t i = 0; i < num_samples; ++i) {
        // Multiply first, then clamp to Int16 range in one step.
        // Avoids two separate clamp operations and is auto-vectorizable.
        // std::clamp produces branchless vmin/vmax on ARM NEON, minps/maxps on SSE.
        const float scaled = std::clamp(float_samples[i] * 32767.0f, -32768.0f, 32767.0f);
        int16_samples[i] = static_cast<int16_t>(scaled);
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
    uint8_t* wav_data = static_cast<uint8_t*>(malloc(wav_size));
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
