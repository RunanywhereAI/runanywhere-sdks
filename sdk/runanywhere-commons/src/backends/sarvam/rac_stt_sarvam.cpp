/**
 * @file rac_stt_sarvam.cpp
 * @brief Sarvam AI STT backend implementation.
 */

#include "rac_stt_sarvam.h"

#include <chrono>
#include <condition_variable>
#include <cstring>

#include <nlohmann/json.hpp>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_http_client.h"

static const char* LOG_CAT = "Sarvam";

namespace rac::sarvam {

// Global API key
std::string& global_api_key() {
    static std::string key;
    return key;
}

std::mutex& global_api_key_mutex() {
    static std::mutex mtx;
    return mtx;
}

const char* model_string(rac_stt_sarvam_model_t model) {
    switch (model) {
        case RAC_STT_SARVAM_MODEL_SAARIKA_V1: return "saarika:v1";
        case RAC_STT_SARVAM_MODEL_SAARIKA_V2: return "saarika:v2";
        case RAC_STT_SARVAM_MODEL_SAARIKA_V2_5: return "saarika:v2.5";
        default: return "saarika:v2.5";
    }
}

// WAV header encoding
std::vector<uint8_t> encode_wav(const void* pcm_data, size_t pcm_size, int32_t sample_rate,
                                int16_t channels, int16_t bits_per_sample) {
    const uint32_t data_size = static_cast<uint32_t>(pcm_size);
    const uint32_t file_size = 36 + data_size;
    const uint16_t block_align = channels * (bits_per_sample / 8);
    const uint32_t byte_rate = sample_rate * block_align;

    std::vector<uint8_t> wav(44 + pcm_size);
    auto* w = wav.data();

    // RIFF header
    std::memcpy(w, "RIFF", 4);
    std::memcpy(w + 4, &file_size, 4);
    std::memcpy(w + 8, "WAVE", 4);

    // fmt chunk
    std::memcpy(w + 12, "fmt ", 4);
    uint32_t fmt_size = 16;
    std::memcpy(w + 16, &fmt_size, 4);
    uint16_t audio_fmt = 1; // PCM
    std::memcpy(w + 20, &audio_fmt, 2);
    uint16_t ch = static_cast<uint16_t>(channels);
    std::memcpy(w + 22, &ch, 2);
    std::memcpy(w + 24, &sample_rate, 4);
    std::memcpy(w + 28, &byte_rate, 4);
    std::memcpy(w + 32, &block_align, 2);
    std::memcpy(w + 34, &bits_per_sample, 2);

    // data chunk
    std::memcpy(w + 36, "data", 4);
    std::memcpy(w + 40, &data_size, 4);
    std::memcpy(w + 44, pcm_data, pcm_size);

    return wav;
}

// Multipart form-data encoding
multipart_result encode_multipart(const std::vector<multipart_field>& fields) {
    const std::string boundary = "----RACBoundary" + std::to_string(
        std::chrono::steady_clock::now().time_since_epoch().count());

    std::vector<uint8_t> body;

    for (const auto& field : fields) {
        std::string part = "--" + boundary + "\r\n";

        if (!field.filename.empty()) {
            // File field
            part += "Content-Disposition: form-data; name=\"" + field.name +
                    "\"; filename=\"" + field.filename + "\"\r\n";
            part += "Content-Type: " + field.content_type + "\r\n\r\n";
            body.insert(body.end(), part.begin(), part.end());
            body.insert(body.end(), field.binary_data.begin(), field.binary_data.end());
            body.push_back('\r');
            body.push_back('\n');
        } else {
            // Text field
            part += "Content-Disposition: form-data; name=\"" + field.name + "\"\r\n\r\n";
            part += field.value + "\r\n";
            body.insert(body.end(), part.begin(), part.end());
        }
    }

    std::string closing = "--" + boundary + "--\r\n";
    body.insert(body.end(), closing.begin(), closing.end());

    multipart_result result;
    result.body = std::move(body);
    result.content_type = "multipart/form-data; boundary=" + boundary;
    return result;
}

}  // namespace rac::sarvam

// =============================================================================
// C API Implementation
// =============================================================================

extern "C" {

rac_result_t rac_stt_sarvam_set_api_key(const char* api_key) {
    if (!api_key || api_key[0] == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
    rac::sarvam::global_api_key() = api_key;
    RAC_LOG_INFO(LOG_CAT, "API key configured");
    return RAC_SUCCESS;
}

const char* rac_stt_sarvam_get_api_key(void) {
    std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
    const auto& key = rac::sarvam::global_api_key();
    return key.empty() ? nullptr : key.c_str();
}

rac_result_t rac_stt_sarvam_create(const rac_stt_sarvam_config_t* config,
                                   rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Verify API key is set
    {
        std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
        if (rac::sarvam::global_api_key().empty()) {
            RAC_LOG_ERROR(LOG_CAT, "API key not configured. Call rac_stt_sarvam_set_api_key first.");
            return RAC_ERROR_INVALID_STATE;
        }
    }

    // Verify HTTP executor is available
    if (!rac_http_has_executor()) {
        RAC_LOG_ERROR(LOG_CAT, "No HTTP executor registered");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    auto* ctx = new (std::nothrow) rac::sarvam::sarvam_context();
    if (!ctx) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    ctx->config = config ? *config : RAC_STT_SARVAM_CONFIG_DEFAULT;
    {
        std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
        ctx->api_key = rac::sarvam::global_api_key();
    }

    *out_handle = ctx;
    RAC_LOG_INFO(LOG_CAT, "Service created (model=%s)",
                 rac::sarvam::model_string(ctx->config.model));
    return RAC_SUCCESS;
}

rac_result_t rac_stt_sarvam_transcribe(rac_handle_t handle, const void* audio_data,
                                       size_t audio_size, const rac_stt_options_t* options,
                                       rac_stt_result_t* out_result) {
    if (!handle || !audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (audio_size > rac::sarvam::kMaxAudioBytes) {
        RAC_LOG_ERROR(LOG_CAT, "Audio exceeds 2 minute limit (%zu bytes)", audio_size);
        return RAC_ERROR_AUDIO_TOO_LONG;
    }

    auto* ctx = static_cast<rac::sarvam::sarvam_context*>(handle);

    auto start_time = std::chrono::steady_clock::now();

    // Determine language from options or config
    // "auto" is used by the SDK for auto-detection — map to config default
    const char* language = ctx->config.language_code;
    if (options && options->language && options->language[0] != '\0' &&
        strcmp(options->language, "auto") != 0) {
        language = options->language;
    }

    RAC_LOG_INFO(LOG_CAT, "Language resolved: '%s' (options->language='%s', config='%s')",
                 language,
                 (options && options->language) ? options->language : "(null)",
                 ctx->config.language_code);

    // Encode PCM to WAV
    auto wav = rac::sarvam::encode_wav(audio_data, audio_size, RAC_STT_DEFAULT_SAMPLE_RATE, 1, 16);

    // Build multipart request
    std::vector<rac::sarvam::multipart_field> fields;

    // Audio file
    rac::sarvam::multipart_field file_field;
    file_field.name = "file";
    file_field.filename = "audio.wav";
    file_field.content_type = "audio/wav";
    file_field.binary_data = std::move(wav);
    fields.push_back(std::move(file_field));

    // Model
    rac::sarvam::multipart_field model_field;
    model_field.name = "model";
    model_field.value = rac::sarvam::model_string(ctx->config.model);
    fields.push_back(std::move(model_field));

    // Language
    rac::sarvam::multipart_field lang_field;
    lang_field.name = "language_code";
    lang_field.value = language ? language : "en-IN";
    fields.push_back(std::move(lang_field));

    // Optional: timestamps
    if (ctx->config.with_timestamps || (options && options->enable_timestamps)) {
        rac::sarvam::multipart_field ts_field;
        ts_field.name = "with_timestamps";
        ts_field.value = "true";
        fields.push_back(std::move(ts_field));
    }

    // Optional: diarization
    if (ctx->config.with_diarization || (options && options->enable_diarization)) {
        rac::sarvam::multipart_field diar_field;
        diar_field.name = "with_diarization";
        diar_field.value = "true";
        fields.push_back(std::move(diar_field));
    }

    auto multipart = rac::sarvam::encode_multipart(fields);

    // Build HTTP request
    rac_http_request_t* request = rac_http_request_create(RAC_HTTP_POST, rac::sarvam::kApiUrl);
    if (!request) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_http_request_add_header(request, "Content-Type", multipart.content_type.c_str());
    rac_http_request_add_header(request, "api-subscription-key", ctx->api_key.c_str());
    rac_http_request_set_timeout(request, ctx->config.timeout_ms);

    // Set binary body
    request->body = reinterpret_cast<const char*>(multipart.body.data());
    request->body_length = multipart.body.size();

    // Synchronous HTTP via condition variable
    struct callback_state {
        std::mutex mtx;
        std::condition_variable cv;
        bool done = false;
        int32_t status_code = 0;
        std::string response_body;
        std::string error;
    };

    callback_state state;

    rac_http_context_t http_ctx = {};
    http_ctx.user_data = &state;
    http_ctx.on_success = [](const char* body, void* ud) {
        auto* s = static_cast<callback_state*>(ud);
        std::lock_guard<std::mutex> lock(s->mtx);
        s->status_code = 200;
        if (body) s->response_body = body;
        s->done = true;
        s->cv.notify_one();
    };
    http_ctx.on_error = [](int status_code, const char* error, void* ud) {
        auto* s = static_cast<callback_state*>(ud);
        std::lock_guard<std::mutex> lock(s->mtx);
        s->status_code = status_code;
        if (error) s->error = error;
        s->done = true;
        s->cv.notify_one();
    };

    rac_http_execute(request, &http_ctx);

    // Wait for response
    {
        std::unique_lock<std::mutex> lock(state.mtx);
        state.cv.wait_for(lock, std::chrono::milliseconds(ctx->config.timeout_ms + 1000),
                          [&] { return state.done; });
    }

    // Don't free body pointer — it points into multipart.body
    request->body = nullptr;
    request->body_length = 0;
    rac_http_request_free(request);

    if (!state.done) {
        RAC_LOG_ERROR(LOG_CAT, "Request timed out");
        return RAC_ERROR_TIMEOUT;
    }

    if (state.status_code != 200) {
        RAC_LOG_ERROR(LOG_CAT, "API error: status=%d, error=%s",
                      state.status_code, state.error.c_str());
        return RAC_ERROR_REQUEST_FAILED;
    }

    // Parse JSON response
    try {
        auto json = nlohmann::json::parse(state.response_body);

        std::string transcript = json.value("transcript", "");

        auto end_time = std::chrono::steady_clock::now();
        auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            end_time - start_time).count();

        out_result->text = rac_strdup(transcript.c_str());
        out_result->confidence = RAC_STT_DEFAULT_CONFIDENCE;
        out_result->processing_time_ms = static_cast<int64_t>(elapsed_ms);
        out_result->words = nullptr;
        out_result->num_words = 0;

        if (json.contains("language_code")) {
            out_result->detected_language = rac_strdup(
                json["language_code"].get<std::string>().c_str());
        } else {
            out_result->detected_language = nullptr;
        }

        RAC_LOG_INFO(LOG_CAT, "Transcription complete (%lldms): \"%s\"",
                     elapsed_ms, transcript.substr(0, 50).c_str());

    } catch (const nlohmann::json::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to parse response: %s", e.what());
        return RAC_ERROR_INVALID_RESPONSE;
    }

    return RAC_SUCCESS;
}

void rac_stt_sarvam_destroy(rac_handle_t handle) {
    if (handle) {
        delete static_cast<rac::sarvam::sarvam_context*>(handle);
        RAC_LOG_DEBUG(LOG_CAT, "Service destroyed");
    }
}

}  // extern "C"
