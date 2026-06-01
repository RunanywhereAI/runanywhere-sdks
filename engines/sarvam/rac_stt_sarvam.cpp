/**
 * @file rac_stt_sarvam.cpp
 * @brief Sarvam STT backend implementation.
 *
 * The impl struct stores the api key, model id, language code, base URL, and
 * a cancel flag. Each transcribe() call builds a multipart/form-data body,
 * issues it through the commons rac_http_client_* ABI, and decodes Sarvam's
 * JSON response into a rac_stt_result_t.
 */

#include "rac/backends/rac_stt_sarvam.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define SARVAM_LOG(...)   __android_log_print(ANDROID_LOG_INFO,  "sarvam", __VA_ARGS__)
#define SARVAM_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "sarvam", __VA_ARGS__)
#else
#define SARVAM_LOG(...)   ((void)0)
#define SARVAM_LOG_E(...) ((void)0)
#endif

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

constexpr const char* kDefaultBaseUrl   = "https://api.sarvam.ai";
// Sarvam requires language_code on saaras:v3 (saarika:v2.5 treats it as
// optional but accepts the same set). "unknown" is the documented
// auto-detect sentinel and is the first valid value listed in the API's
// own error message.
constexpr const char* kDefaultLanguage  = "unknown";
constexpr int32_t     kDefaultTimeoutMs = 30000;

struct SarvamImpl {
    std::string api_key;
    std::string model;
    std::string language_code;
    std::string base_url;
    int32_t     timeout_ms = kDefaultTimeoutMs;
    std::atomic<bool> cancelled{false};
    std::mutex  http_mutex;
};

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (out == nullptr) {
        return nullptr;
    }
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

void mime_for_format(rac_audio_format_enum_t fmt, const char*& content_type, const char*& ext) {
    switch (fmt) {
        case RAC_AUDIO_FORMAT_MP3:  content_type = "audio/mpeg"; ext = "mp3";  break;
        case RAC_AUDIO_FORMAT_OPUS: content_type = "audio/opus"; ext = "opus"; break;
        case RAC_AUDIO_FORMAT_AAC:  content_type = "audio/aac";  ext = "m4a";  break;
        case RAC_AUDIO_FORMAT_FLAC: content_type = "audio/flac"; ext = "flac"; break;
        case RAC_AUDIO_FORMAT_WAV:
        case RAC_AUDIO_FORMAT_PCM:
        default:                    content_type = "audio/wav";  ext = "wav";  break;
    }
}

std::string make_boundary() {
    using namespace std::chrono;
    const auto ns = duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count();
    std::string b = "----rac-sarvam-boundary-";
    b += std::to_string(ns);
    return b;
}

void append_str(std::vector<uint8_t>& buf, const std::string& s) {
    buf.insert(buf.end(), s.begin(), s.end());
}

void append_bytes(std::vector<uint8_t>& buf, const void* data, size_t len) {
    const auto* p = static_cast<const uint8_t*>(data);
    buf.insert(buf.end(), p, p + len);
}

void multipart_text_part(std::vector<uint8_t>& buf, const std::string& boundary,
                         const std::string& name, const std::string& value) {
    append_str(buf, "--" + boundary + "\r\n");
    append_str(buf, "Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n");
    append_str(buf, value);
    append_str(buf, "\r\n");
}

void multipart_file_part(std::vector<uint8_t>& buf, const std::string& boundary,
                         const std::string& name, const std::string& filename,
                         const std::string& content_type,
                         const void* data, size_t len) {
    append_str(buf, "--" + boundary + "\r\n");
    append_str(buf, "Content-Disposition: form-data; name=\"" + name +
                        "\"; filename=\"" + filename + "\"\r\n");
    append_str(buf, "Content-Type: " + content_type + "\r\n\r\n");
    append_bytes(buf, data, len);
    append_str(buf, "\r\n");
}

void multipart_close(std::vector<uint8_t>& buf, const std::string& boundary) {
    append_str(buf, "--" + boundary + "--\r\n");
}

std::vector<uint8_t> build_multipart_body(const SarvamImpl&       impl,
                                          const std::string&      language_code,
                                          const void*             audio_data,
                                          size_t                  audio_size,
                                          rac_audio_format_enum_t fmt,
                                          std::string&            out_boundary) {
    out_boundary = make_boundary();
    const char* content_type = nullptr;
    const char* ext          = nullptr;
    mime_for_format(fmt, content_type, ext);

    std::vector<uint8_t> body;
    body.reserve(audio_size + 512);

    multipart_file_part(body, out_boundary, "file", std::string("audio.") + ext,
                        content_type, audio_data, audio_size);
    multipart_text_part(body, out_boundary, "model", impl.model);
    if (!language_code.empty()) {
        multipart_text_part(body, out_boundary, "language_code", language_code);
    }
    multipart_close(body, out_boundary);
    return body;
}

rac_result_t issue_blocking(SarvamImpl&                 impl,
                            const std::vector<uint8_t>& body,
                            const std::string&          boundary,
                            rac_http_response_t&        resp) {
    const std::string ctype = "multipart/form-data; boundary=" + boundary;
    const std::string url   = impl.base_url + "/speech-to-text";

    const rac_http_header_kv_t headers[] = {
        {"api-subscription-key", impl.api_key.c_str()},
        {"Content-Type", ctype.c_str()},
        {"Accept", "application/json"},
    };

    rac_http_request_t req{};
    req.method = "POST";
    req.url = url.c_str();
    req.headers = headers;
    req.header_count = sizeof(headers) / sizeof(headers[0]);
    req.body_bytes = body.data();
    req.body_len   = body.size();
    req.timeout_ms = impl.timeout_ms;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || client == nullptr) {
        SARVAM_LOG_E("issue_blocking: http_client_create rc=%d", rc);
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL;
    }
    SARVAM_LOG("issue_blocking: POST %s body_len=%zu", url.c_str(), body.size());
    std::lock_guard<std::mutex> lock(impl.http_mutex);
    rc = rac_http_request_send(client, &req, &resp);
    rac_http_client_destroy(client);
    SARVAM_LOG("issue_blocking: send rc=%d status=%d body_len=%zu",
               rc, resp.status, resp.body_len);
    return rc;
}

rac_result_t parse_response(const rac_http_response_t& resp,
                            rac_stt_result_t*          out_result,
                            int64_t                    elapsed_ms) {
    if (resp.status < 200 || resp.status >= 300) {
        SARVAM_LOG_E("HTTP %d: %.*s",
                     resp.status,
                     (int)std::min<size_t>(resp.body_len, 512),
                     reinterpret_cast<const char*>(resp.body_bytes));
        RAC_LOG_ERROR("sarvam",
                      "HTTP %d: %.*s",
                      resp.status,
                      (int)std::min<size_t>(resp.body_len, 512),
                      reinterpret_cast<const char*>(resp.body_bytes));
        return RAC_ERROR_HTTP_ERROR;
    }
    if (resp.body_bytes == nullptr || resp.body_len == 0) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
    try {
        auto json = nlohmann::json::parse(resp.body_bytes, resp.body_bytes + resp.body_len);
        const auto transcript = json.value("transcript", std::string{});
        const auto language   = json.value("language_code", std::string{});

        out_result->text = dup_cstr(transcript);
        if (out_result->text == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        if (!language.empty()) {
            out_result->detected_language = dup_cstr(language);
        }
        out_result->confidence         = RAC_STT_DEFAULT_CONFIDENCE;
        out_result->processing_time_ms = elapsed_ms;
        return RAC_SUCCESS;
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
}

rac_result_t parse_config(const std::string& config_json, SarvamImpl& out) {
    try {
        const auto json = nlohmann::json::parse(config_json);
        out.api_key       = json.value("api_key", std::string{});
        out.model         = json.value("model", std::string{});
        out.language_code = json.value("language_code", std::string{kDefaultLanguage});
        out.base_url      = json.value("base_url", std::string{kDefaultBaseUrl});
        out.timeout_ms    = json.value("timeout_ms", kDefaultTimeoutMs);
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (out.api_key.empty() || out.model.empty()) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    return RAC_SUCCESS;
}

// =============================================================================
// Vtable implementations
// =============================================================================

rac_result_t ops_create(const char* model_id, const char* config_json, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_impl = nullptr;
    auto impl = std::make_unique<SarvamImpl>();
    impl->base_url      = kDefaultBaseUrl;
    impl->language_code = kDefaultLanguage;
    impl->timeout_ms    = kDefaultTimeoutMs;
    if (config_json != nullptr && config_json[0] != '\0') {
        rac_result_t rc = parse_config(config_json, *impl);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
    }
    if (model_id != nullptr && model_id[0] != '\0') {
        impl->model = model_id;
    }
    if (impl->api_key.empty() || impl->model.empty()) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    *out_impl = impl.release();
    return RAC_SUCCESS;
}

rac_result_t ops_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}

rac_result_t ops_transcribe(void* impl_v, const void* audio_data, size_t audio_size,
                            const rac_stt_options_t* options, rac_stt_result_t* out_result) {
    SARVAM_LOG("ops_transcribe called impl=%p audio_size=%zu", impl_v, audio_size);
    auto* impl = static_cast<SarvamImpl*>(impl_v);
    if (impl == nullptr || audio_data == nullptr || audio_size == 0 || out_result == nullptr) {
        SARVAM_LOG_E("ops_transcribe INVALID_PARAMETER impl=%p data=%p size=%zu out=%p",
                     impl_v, audio_data, audio_size, (void*)out_result);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    impl->cancelled.store(false);
    std::memset(out_result, 0, sizeof(*out_result));

    const std::string language_code =
        (options != nullptr && options->language != nullptr && options->language[0] != '\0')
            ? std::string(options->language)
            : impl->language_code;
    const rac_audio_format_enum_t fmt =
        (options != nullptr) ? options->audio_format : RAC_AUDIO_FORMAT_WAV;

    std::string boundary;
    auto body = build_multipart_body(*impl, language_code, audio_data, audio_size, fmt, boundary);

    const auto start = std::chrono::steady_clock::now();
    rac_http_response_t resp{};
    rac_result_t rc = issue_blocking(*impl, body, boundary, resp);
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&resp);
        return rc;
    }
    rc = parse_response(resp, out_result, static_cast<int64_t>(elapsed_ms));
    rac_http_response_free(&resp);
    return rc;
}

rac_result_t ops_get_info(void* impl_v, rac_stt_info_t* out_info) {
    auto* impl = static_cast<SarvamImpl*>(impl_v);
    if (impl == nullptr || out_info == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    out_info->is_ready           = RAC_TRUE;
    out_info->current_model      = impl->model.c_str();
    out_info->supports_streaming = RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t ops_cleanup(void* /*impl*/) {
    return RAC_SUCCESS;
}

void ops_destroy(void* impl_v) {
    delete static_cast<SarvamImpl*>(impl_v);
}

}  // namespace

const rac_stt_service_ops_t g_sarvam_stt_ops = {
    /* initialize              */ ops_initialize,
    /* transcribe              */ ops_transcribe,
    /* transcribe_stream       */ nullptr,
    /* get_info                */ ops_get_info,
    /* cleanup                 */ ops_cleanup,
    /* destroy                 */ ops_destroy,
    /* create                  */ ops_create,
    /* get_languages           */ nullptr,
    /* detect_language         */ nullptr,
    /* stream_create           */ nullptr,
    /* stream_feed_audio_chunk */ nullptr,
    /* stream_destroy          */ nullptr,
};

extern "C" {

rac_result_t rac_stt_sarvam_create(const char* api_key, const char* model,
                                   rac_stt_service_t** out_service) {
    if (api_key == nullptr || model == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;
    nlohmann::json cfg = {{"api_key", api_key}, {"model", model}};
    const std::string cfg_str = cfg.dump();
    return rac_stt_sarvam_create_from_json(cfg_str.c_str(), out_service);
}

rac_result_t rac_stt_sarvam_create_from_json(const char*         config_json,
                                             rac_stt_service_t** out_service) {
    if (config_json == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;

    void* impl = nullptr;
    rac_result_t rc = g_sarvam_stt_ops.create(/*model_id=*/nullptr, config_json, &impl);
    if (rc != RAC_SUCCESS || impl == nullptr) {
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INITIALIZATION_FAILED;
    }
    auto* svc = new (std::nothrow) rac_stt_service_t{};
    if (svc == nullptr) {
        g_sarvam_stt_ops.destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    svc->ops  = &g_sarvam_stt_ops;
    svc->impl = impl;
    auto* impl_typed = static_cast<SarvamImpl*>(impl);
    svc->model_id = impl_typed->model.c_str();
    *out_service = svc;
    return RAC_SUCCESS;
}

void rac_stt_sarvam_destroy(rac_stt_service_t* service) {
    if (service == nullptr) {
        return;
    }
    if (service->ops != nullptr && service->ops->destroy != nullptr && service->impl != nullptr) {
        service->ops->destroy(service->impl);
    }
    delete service;
}

}  // extern "C"