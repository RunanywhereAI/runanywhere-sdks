/**
 * @file rac_stt_cloud.cpp
 * @brief Generic cloud STT backend — shared HTTP/multipart core.
 *
 * cloud_stt is ONE engine; the PROVIDER (Sarvam, and future HTTP STT providers)
 * is selected at create() via config_json["provider"]. This TU owns the
 * provider-agnostic plumbing — ~85% of the original Sarvam code:
 *   - the CloudSttImpl state + its vtable (create/transcribe/get_info/destroy)
 *   - the shared HTTP issue path (URL assembly, auth + content-type + accept
 *     headers, timeout, the rac_http_client_* round-trip, mutex)
 *   - the shared multipart writer + MIME map (cloud_stt_build_multipart_default)
 *   - the shared flat-JSON decoder (cloud_stt_parse_flat_json)
 *   - the NaN "no-signal" confidence helper
 *
 * The genuinely provider-specific bits (endpoint path, auth header, body shape,
 * response keys) live behind the CloudSttProvider adapter; Sarvam's adapter is
 * in providers/sarvam.cpp.
 */

#include "rac/backends/rac_stt_cloud.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <utility>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define CLOUD_STT_LOG(...)   __android_log_print(ANDROID_LOG_INFO,  "cloud_stt", __VA_ARGS__)
#define CLOUD_STT_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "cloud_stt", __VA_ARGS__)
#else
#define CLOUD_STT_LOG(...)   ((void)0)
#define CLOUD_STT_LOG_E(...) ((void)0)
#endif

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/cloud/rac_cloud_stt_provider.h"

#include "cloud_stt_provider.h"

namespace rac::cloud_stt {

// Shared helpers (declared in cloud_stt_provider.h, reused by every adapter)

float cloud_stt_no_confidence() {
    // NaN, NOT RAC_STT_DEFAULT_CONFIDENCE (0.9). Cloud STT has no per-result
    // confidence signal; the hybrid router treats NaN as "no signal" so a cloud
    // result never wrongly triggers or suppresses a cascade.
    return std::numeric_limits<float>::quiet_NaN();
}

char* cloud_stt_dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (out == nullptr) {
        return nullptr;
    }
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

namespace {

// multipart writer + MIME map (shared)

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
    std::string b = "----rac-cloud-stt-boundary-";
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

// auth header value template

// Expand an adapter's auth_value_template by replacing the literal token "{key}"
// with the API key. "{key}" alone yields the raw key (Sarvam); "Bearer {key}"
// and "Token {key}" yield the scheme-prefixed forms.
std::string expand_auth_value(const char* templ, const std::string& key) {
    std::string out = (templ != nullptr) ? templ : "{key}";
    const std::string token = "{key}";
    const auto pos = out.find(token);
    if (pos != std::string::npos) {
        out.replace(pos, token.size(), key);
    }
    return out;
}

// shared HTTP issue path

// Assembles the auth + content-type + accept headers, POSTs the adapter-built
// body to {base_url}{path}, and returns the raw send result. Behavior is
// provider-agnostic: the only provider inputs are the impl's resolved url/auth
// and the parts the adapter filled.
rac_result_t issue_blocking(CloudSttImpl&            impl,
                            const HttpRequestParts&  parts,
                            rac_http_response_t&     resp) {
    const std::string url        = impl.base_url + impl.path;
    const std::string auth_value =
        expand_auth_value(impl.provider->auth_value_template, impl.api_key);

    const rac_http_header_kv_t headers[] = {
        {impl.provider->auth_header_name, auth_value.c_str()},
        {"Content-Type", parts.content_type.c_str()},
        {"Accept", "application/json"},
    };

    rac_http_request_t req{};
    req.method = "POST";
    req.url = url.c_str();
    req.headers = headers;
    req.header_count = sizeof(headers) / sizeof(headers[0]);
    req.body_bytes = parts.body.data();
    req.body_len   = parts.body.size();
    req.timeout_ms = impl.timeout_ms;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || client == nullptr) {
        CLOUD_STT_LOG_E("issue_blocking: http_client_create rc=%d", rc);
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL;
    }
    CLOUD_STT_LOG("issue_blocking: POST %s body_len=%zu", url.c_str(), parts.body.size());
    std::lock_guard<std::mutex> lock(impl.http_mutex);
    rc = rac_http_request_send(client, &req, &resp);
    rac_http_client_destroy(client);
    CLOUD_STT_LOG("issue_blocking: send rc=%d status=%d body_len=%zu",
                  rc, resp.status, resp.body_len);
    return rc;
}

// config parsing

// Selects the provider, then fills the impl. Provider defaults seed base_url /
// path before config overrides. api_key + model stay required (as today).
rac_result_t parse_config(const std::string& config_json, CloudSttImpl& out) {
    std::string provider_name = "sarvam";  // default for current single-provider callers
    try {
        const auto json = nlohmann::json::parse(config_json);
        provider_name     = json.value("provider", std::string{"sarvam"});
        out.api_key       = json.value("api_key", std::string{});
        out.model         = json.value("model", std::string{});
        out.language_code = json.value("language_code", std::string{kDefaultLanguage});
        out.timeout_ms    = json.value("timeout_ms", kDefaultTimeoutMs);
        out.provider_name = provider_name;
        out.config_json   = config_json;

        const CloudSttProvider* provider = find_cloud_stt_provider(provider_name);
        if (provider != nullptr) {
            out.use_host_callback = false;
            out.provider = provider;
            // Provider defaults first, then optional per-request overrides.
            out.base_url = json.value("base_url", std::string{provider->default_base_url});
            out.path     = json.value("path", std::string{provider->default_path});
        } else if (rac_cloud_has_stt_provider(provider_name.c_str()) == RAC_TRUE) {
            // Developer-registered host-callback provider: the host owns the wire
            // format end to end, so there's no static adapter and no engine-side
            // base_url/path defaults — the host reads whatever it needs from the
            // forwarded config_json.
            out.use_host_callback = true;
            out.provider = nullptr;
            out.base_url = json.value("base_url", std::string{});
            out.path     = json.value("path", std::string{});
        } else {
            CLOUD_STT_LOG_E("parse_config: unknown provider '%s'", provider_name.c_str());
            RAC_LOG_ERROR("cloud_stt", "unknown provider '%s'", provider_name.c_str());
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (out.api_key.empty() || out.model.empty()) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    return RAC_SUCCESS;
}

// host-callback (developer-defined) provider path

// Decode the host callback's result JSON into out_result. Shape:
//   {"text": "...", "language_code": "...", "confidence": <number|omitted>,
//    "error_code": 0, "error_message": "..."}
// A non-zero error_code is surfaced as an HTTP error; confidence defaults to the
// cloud "no-signal" NaN when the host omits it.
rac_result_t parse_host_result_json(const char*       result_json,
                                    rac_stt_result_t* out_result,
                                    int64_t           elapsed_ms) {
    if (result_json == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
    try {
        const auto json = nlohmann::json::parse(result_json);
        const int error_code = json.value("error_code", 0);
        if (error_code != 0) {
            const auto msg = json.value("error_message", std::string{});
            CLOUD_STT_LOG_E("host provider error %d: %s", error_code, msg.c_str());
            RAC_LOG_ERROR("cloud_stt", "host provider error %d: %s", error_code, msg.c_str());
            return RAC_ERROR_HTTP_ERROR;
        }
        out_result->text = cloud_stt_dup_cstr(json.value("text", std::string{}));
        if (out_result->text == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        const auto language = json.value("language_code", std::string{});
        if (!language.empty()) {
            out_result->detected_language = cloud_stt_dup_cstr(language);
        }
        out_result->confidence =
            (json.contains("confidence") && json["confidence"].is_number())
                ? json["confidence"].get<float>()
                : cloud_stt_no_confidence();
        out_result->processing_time_ms = elapsed_ms;
        return RAC_SUCCESS;
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
}

// Delegate the whole transcribe to the host-registered provider callback. The
// host builds the request, performs the HTTP, and parses the response; we just
// hand over the audio + forwarded config and decode the result JSON it returns.
rac_result_t transcribe_via_host(CloudSttImpl&            impl,
                                 const void*              audio,
                                 size_t                   audio_size,
                                 const rac_stt_options_t* options,
                                 rac_stt_result_t*        out_result) {
    const int32_t fmt = (options != nullptr) ? static_cast<int32_t>(options->audio_format)
                                             : static_cast<int32_t>(RAC_AUDIO_FORMAT_WAV);
    char* result_json = nullptr;
    const auto start = std::chrono::steady_clock::now();
    rac_result_t rc = rac_cloud_invoke_stt_provider(
        impl.provider_name.c_str(), impl.config_json.c_str(),
        static_cast<const uint8_t*>(audio), audio_size, fmt, &result_json);
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
    if (rc != RAC_SUCCESS) {
        rac_cloud_stt_result_free(result_json);
        return rc;
    }
    rc = parse_host_result_json(result_json, out_result, static_cast<int64_t>(elapsed_ms));
    rac_cloud_stt_result_free(result_json);
    return rc;
}

// Vtable implementations

rac_result_t ops_create(const char* model_id, const char* config_json, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_impl = nullptr;
    auto impl = std::make_unique<CloudSttImpl>();
    impl->language_code = kDefaultLanguage;
    impl->timeout_ms    = kDefaultTimeoutMs;
    if (config_json != nullptr && config_json[0] != '\0') {
        rac_result_t rc = parse_config(config_json, *impl);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
    } else {
        // No config at all: still need a provider to be a usable service. Default
        // to sarvam so existing single-provider callers keep working; api_key /
        // model remain required and fail the check below.
        impl->provider = find_cloud_stt_provider("sarvam");
        if (impl->provider == nullptr) {
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        impl->base_url = impl->provider->default_base_url;
        impl->path     = impl->provider->default_path;
    }
    if (model_id != nullptr && model_id[0] != '\0') {
        impl->model = model_id;
    }
    // A usable service needs either a static provider adapter or a host-callback
    // provider; api_key + model stay required for both.
    if ((impl->provider == nullptr && !impl->use_host_callback) ||
        impl->api_key.empty() || impl->model.empty()) {
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
    CLOUD_STT_LOG("ops_transcribe called impl=%p audio_size=%zu", impl_v, audio_size);
    auto* impl = static_cast<CloudSttImpl*>(impl_v);
    if (impl == nullptr || audio_data == nullptr || audio_size == 0 || out_result == nullptr) {
        CLOUD_STT_LOG_E("ops_transcribe INVALID_PARAMETER impl=%p data=%p size=%zu out=%p",
                        impl_v, audio_data, audio_size, (void*)out_result);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    impl->cancelled.store(false);
    std::memset(out_result, 0, sizeof(*out_result));

    // Developer-defined provider: the host performs the whole request.
    if (impl->use_host_callback) {
        return transcribe_via_host(*impl, audio_data, audio_size, options, out_result);
    }

    if (impl->provider == nullptr || impl->provider->build_request == nullptr ||
        impl->provider->parse_response == nullptr) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    const std::string language_code =
        (options != nullptr && options->language != nullptr && options->language[0] != '\0')
            ? std::string(options->language)
            : impl->language_code;

    HttpRequestParts parts;
    rac_result_t rc =
        impl->provider->build_request(impl, audio_data, audio_size, language_code, options, &parts);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    const auto start = std::chrono::steady_clock::now();
    rac_http_response_t resp{};
    rc = issue_blocking(*impl, parts, resp);
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&resp);
        return rc;
    }
    rc = impl->provider->parse_response(&resp, out_result, static_cast<int64_t>(elapsed_ms));
    rac_http_response_free(&resp);
    return rc;
}

rac_result_t ops_get_info(void* impl_v, rac_stt_info_t* out_info) {
    auto* impl = static_cast<CloudSttImpl*>(impl_v);
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
    delete static_cast<CloudSttImpl*>(impl_v);
}

}  // namespace

// Shared default helpers (definitions; declared in cloud_stt_provider.h)

rac_result_t cloud_stt_build_multipart_default(
    const std::string&                                      file_field,
    const void*                                             audio,
    size_t                                                  audio_size,
    rac_audio_format_enum_t                                 fmt,
    const std::vector<std::pair<std::string, std::string>>& text_fields,
    HttpRequestParts*                                       out_parts) {
    if (out_parts == nullptr || audio == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const std::string boundary = make_boundary();
    const char* content_type = nullptr;
    const char* ext          = nullptr;
    mime_for_format(fmt, content_type, ext);

    std::vector<uint8_t> body;
    body.reserve(audio_size + 512);

    multipart_file_part(body, boundary, file_field, std::string("audio.") + ext,
                        content_type, audio, audio_size);
    for (const auto& kv : text_fields) {
        if (kv.second.empty()) {
            // Skip empty optional fields (matches Sarvam's optional-field rule).
            continue;
        }
        multipart_text_part(body, boundary, kv.first, kv.second);
    }
    multipart_close(body, boundary);

    out_parts->body         = std::move(body);
    out_parts->content_type = "multipart/form-data; boundary=" + boundary;
    return RAC_SUCCESS;
}

rac_result_t cloud_stt_parse_flat_json(const rac_http_response_t* resp,
                                       const char*                text_key,
                                       const char*                lang_key,
                                       rac_stt_result_t*          out_result,
                                       int64_t                    elapsed_ms) {
    if (resp == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (resp->status < 200 || resp->status >= 300) {
        CLOUD_STT_LOG_E("HTTP %d: %.*s",
                        resp->status,
                        (int)std::min<size_t>(resp->body_len, 512),
                        reinterpret_cast<const char*>(resp->body_bytes));
        RAC_LOG_ERROR("cloud_stt",
                      "HTTP %d: %.*s",
                      resp->status,
                      (int)std::min<size_t>(resp->body_len, 512),
                      reinterpret_cast<const char*>(resp->body_bytes));
        return RAC_ERROR_HTTP_ERROR;
    }
    if (resp->body_bytes == nullptr || resp->body_len == 0) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
    try {
        auto json = nlohmann::json::parse(resp->body_bytes, resp->body_bytes + resp->body_len);
        const auto transcript =
            (text_key != nullptr) ? json.value(text_key, std::string{}) : std::string{};

        out_result->text = cloud_stt_dup_cstr(transcript);
        if (out_result->text == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        if (lang_key != nullptr && lang_key[0] != '\0') {
            const auto language = json.value(lang_key, std::string{});
            if (!language.empty()) {
                out_result->detected_language = cloud_stt_dup_cstr(language);
            }
        }
        // Cloud "no-signal" confidence (NOT 0.9) — see cloud_stt_no_confidence().
        out_result->confidence         = cloud_stt_no_confidence();
        out_result->processing_time_ms = elapsed_ms;
        return RAC_SUCCESS;
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
}

}  // namespace rac::cloud_stt

// Engine ops vtable + C ABI factory

const rac_stt_service_ops_t g_cloud_stt_ops = {
    /* initialize              */ rac::cloud_stt::ops_initialize,
    /* transcribe              */ rac::cloud_stt::ops_transcribe,
    /* transcribe_stream       */ nullptr,
    /* get_info                */ rac::cloud_stt::ops_get_info,
    /* cleanup                 */ rac::cloud_stt::ops_cleanup,
    /* destroy                 */ rac::cloud_stt::ops_destroy,
    /* create                  */ rac::cloud_stt::ops_create,
    /* get_languages           */ nullptr,
    /* detect_language         */ nullptr,
    /* stream_create           */ nullptr,
    /* stream_feed_audio_chunk */ nullptr,
    /* stream_destroy          */ nullptr,
};

extern "C" {

rac_result_t rac_stt_cloud_create(const char* api_key, const char* model,
                                  rac_stt_service_t** out_service) {
    if (api_key == nullptr || model == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;
    // No "provider" key -> defaults to sarvam inside ops_create, preserving the
    // legacy single-provider create() contract byte-for-byte.
    nlohmann::json cfg = {{"api_key", api_key}, {"model", model}};
    const std::string cfg_str = cfg.dump();
    return rac_stt_cloud_create_from_json(cfg_str.c_str(), out_service);
}

rac_result_t rac_stt_cloud_create_from_json(const char*         config_json,
                                            rac_stt_service_t** out_service) {
    if (config_json == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;

    void* impl = nullptr;
    rac_result_t rc = g_cloud_stt_ops.create(/*model_id=*/nullptr, config_json, &impl);
    if (rc != RAC_SUCCESS || impl == nullptr) {
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INITIALIZATION_FAILED;
    }
    auto* svc = new (std::nothrow) rac_stt_service_t{};
    if (svc == nullptr) {
        g_cloud_stt_ops.destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    svc->ops  = &g_cloud_stt_ops;
    svc->impl = impl;
    auto* impl_typed = static_cast<rac::cloud_stt::CloudSttImpl*>(impl);
    svc->model_id = impl_typed->model.c_str();
    *out_service = svc;
    return RAC_SUCCESS;
}

void rac_stt_cloud_destroy(rac_stt_service_t* service) {
    if (service == nullptr) {
        return;
    }
    if (service->ops != nullptr && service->ops->destroy != nullptr && service->impl != nullptr) {
        service->ops->destroy(service->impl);
    }
    delete service;
}

}  // extern "C"
