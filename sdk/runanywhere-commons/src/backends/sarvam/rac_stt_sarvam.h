/**
 * @file rac_stt_sarvam.h
 * @brief Internal header for Sarvam STT backend implementation.
 */

#ifndef RAC_STT_SARVAM_INTERNAL_H
#define RAC_STT_SARVAM_INTERNAL_H

#include "rac/backends/rac_stt_sarvam.h"

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace rac::sarvam {

// Sarvam API endpoint
constexpr const char* kApiUrl = "https://api.sarvam.ai/speech-to-text";

// Max audio duration: 2 minutes at 16kHz 16-bit mono
constexpr size_t kMaxAudioBytes = 16000 * 2 * 120;

// Returns the model string for the API request
const char* model_string(rac_stt_sarvam_model_t model);

// Normalize a user-provided language code into a Sarvam-accepted value.
// Accepts "auto"/null/"" -> "unknown"; "en" -> "en-IN"; passes through already
// qualified codes like "en-IN"; unknown inputs -> "unknown".
std::string normalize_language_code(const char* in);

// WAV encoding: wraps raw PCM Int16 data in a WAV header
std::vector<uint8_t> encode_wav(const void* pcm_data, size_t pcm_size, int32_t sample_rate,
                                int16_t channels, int16_t bits_per_sample);

// Multipart form-data encoding
struct multipart_field {
    std::string name;
    std::string value;
    std::string filename;    // empty for text fields
    std::string content_type; // empty for text fields
    std::vector<uint8_t> binary_data; // empty for text fields
};

struct multipart_result {
    std::vector<uint8_t> body;
    std::string content_type; // includes boundary
};

multipart_result encode_multipart(const std::vector<multipart_field>& fields);

// Sarvam service context
struct sarvam_context {
    rac_stt_sarvam_config_t config;
    std::string api_key;
};

// Global API key storage
std::string& global_api_key();
std::mutex& global_api_key_mutex();

}  // namespace rac::sarvam

#endif /* RAC_STT_SARVAM_INTERNAL_H */
