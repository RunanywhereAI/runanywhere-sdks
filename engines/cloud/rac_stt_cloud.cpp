/**
 * @file rac_stt_cloud.cpp
 * @brief Generic cloud STT backend — shared HTTP/multipart core.
 *
 * cloud_stt is ONE engine; the PROVIDER (the RunAnywhere backend proxy)
 * is selected at create() via config_json["provider"]. This TU owns the
 * provider-agnostic plumbing:
 *   - the CloudSttImpl state + its vtable (create/transcribe/get_info/destroy)
 *   - the shared HTTP issue path (URL assembly, auth + content-type + accept
 *     headers, timeout, the rac_http_client_* round-trip, mutex)
 *   - the shared multipart writer + MIME map (cloud_stt_build_multipart_default)
 *   - the shared flat-JSON decoder (cloud_stt_parse_flat_json)
 *   - the NaN "no-signal" confidence helper
 *
 * The genuinely provider-specific bits (endpoint path, auth header, body shape,
 * response keys) live behind the CloudSttProvider adapter; the RunAnywhere
 * backend-proxy adapter is in providers/runanywhere.cpp.
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
#include "rac/core/rac_sdk_state.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/network/rac_auth_manager.h"

#include "cloud_stt_provider.h"

namespace rac::cloud_stt {

// =============================================================================
// Shared helpers (declared in cloud_stt_provider.h, reused by every adapter)
// =============================================================================

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

// ---- multipart writer + MIME map (shared) -----------------------------------

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

// ---- auth header value template ---------------------------------------------

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

// ---- shared HTTP issue path -------------------------------------------------

// Assembles the auth + content-type + accept headers, POSTs the adapter-built
// body to {base_url}{path}, and returns the raw send result. Behavior is
// provider-agnostic: the only provider inputs are the impl's resolved url/auth
// and the parts the adapter filled.
rac_result_t issue_blocking(CloudSttImpl&            impl,
                            const HttpRequestParts&  parts,
                            rac_http_response_t&     resp) {
    const std::string url = impl.base_url + impl.path;

    // Session-auth providers read the device access token at request time so
    // rotation (5h expiry + refresh) is picked up without recreating the
    // service. A missing session fails here, before any audio leaves the
    // device.
    std::string credential = impl.api_key;
    if (impl.provider->auth_from_sdk_session && credential.empty()) {
        const char* token = rac_auth_get_access_token();
        if (token == nullptr || token[0] == '\0') {
            RAC_LOG_ERROR("cloud_stt", "no SDK access token; authenticate first");
            return RAC_ERROR_UNAUTHORIZED;
        }
        credential = token;
    }
    const std::string auth_value =
        expand_auth_value(impl.provider->auth_value_template, credential);

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

// ---- config parsing ---------------------------------------------------------

// Fills the impl from config_json. The provider table is LOCKED to the static
// adapters in providers/ (runanywhere only): audio captured by this engine is
// never routable to an arbitrary host, so there is no developer-registered
// provider branch and no way to point the engine at a third-party endpoint
// beyond the test-only base_url override.
rac_result_t cloud_stt_finalize_impl(CloudSttImpl& out);

rac_result_t parse_config(const std::string& config_json, CloudSttImpl& out) {
    std::string provider_name = "runanywhere";
    try {
        const auto json = nlohmann::json::parse(config_json);
        provider_name     = json.value("provider", std::string{"runanywhere"});
        out.api_key       = json.value("api_key", std::string{});
        out.model         = json.value("model", std::string{});
        out.language_code = json.value("language_code", std::string{kDefaultLanguage});
        out.timeout_ms    = json.value("timeout_ms", kDefaultTimeoutMs);
        out.provider_name = provider_name;

        const CloudSttProvider* provider = find_cloud_stt_provider(provider_name);
        if (provider == nullptr) {
            CLOUD_STT_LOG_E("parse_config: unsupported provider '%s'", provider_name.c_str());
            RAC_LOG_ERROR("cloud_stt", "unsupported provider '%s'", provider_name.c_str());
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        out.provider = provider;
        // Provider defaults first, then optional per-request overrides.
        out.base_url = json.value("base_url", std::string{provider->default_base_url});
        out.path     = json.value("path", std::string{provider->default_path});
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    return cloud_stt_finalize_impl(out);
}

// Shared tail of both create paths: resolve an empty base_url from the SDK's
// configured backend, then validate what this provider actually requires.
// Session-auth providers need neither api_key (the device token is read per
// request) nor model (the backend chooses the served model).
rac_result_t cloud_stt_finalize_impl(CloudSttImpl& out) {
    if (out.provider == nullptr) {
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (out.base_url.empty()) {
        const char* backend = rac_state_get_base_url();
        if (backend != nullptr) {
            out.base_url = backend;
        }
    }
    if (out.base_url.empty()) {
        RAC_LOG_ERROR("cloud_stt", "no base_url: SDK not initialized with a backend URL");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (!out.provider->auth_from_sdk_session &&
        (out.api_key.empty() || out.model.empty())) {
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
    auto impl = std::make_unique<CloudSttImpl>();
    impl->language_code = kDefaultLanguage;
    impl->timeout_ms    = kDefaultTimeoutMs;
    if (config_json != nullptr && config_json[0] != '\0') {
        rac_result_t rc = parse_config(config_json, *impl);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
    } else {
        // No config at all: default to the runanywhere backend proxy, which
        // needs no per-caller configuration (base_url and auth come from the
        // SDK session).
        impl->provider = find_cloud_stt_provider("runanywhere");
        if (impl->provider == nullptr) {
            return RAC_ERROR_INVALID_CONFIGURATION;
        }
        impl->provider_name = impl->provider->name;
        impl->base_url      = impl->provider->default_base_url;
        impl->path          = impl->provider->default_path;
        const rac_result_t rc = cloud_stt_finalize_impl(*impl);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
    }
    if (model_id != nullptr && model_id[0] != '\0') {
        impl->model = model_id;
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

// =============================================================================
// Shared default helpers (definitions; declared in cloud_stt_provider.h)
// =============================================================================

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
        // Backend error envelope ({"error":{"code": ...}}) beats the bare HTTP
        // status: it distinguishes "key not entitled" from a generic 403 so
        // apps can point at the Console toggle instead of a mystery failure.
        if (resp->body_bytes != nullptr && resp->body_len > 0) {
            try {
                const auto json =
                    nlohmann::json::parse(resp->body_bytes, resp->body_bytes + resp->body_len);
                const auto code =
                    json.value("error", nlohmann::json::object()).value("code", std::string{});
                if (code == "feature_not_enabled") {
                    return RAC_ERROR_FEATURE_NOT_ENABLED;
                }
                if (code == "quota_exceeded") {
                    return RAC_ERROR_QUOTA_EXCEEDED;
                }
            } catch (const std::exception&) {
                // Not our envelope; fall through to the status mapping.
            }
        }
        switch (resp->status) {
            case 401: return RAC_ERROR_UNAUTHORIZED;
            case 403: return RAC_ERROR_FORBIDDEN;
            case 429: return RAC_ERROR_QUOTA_EXCEEDED;
            default:  return RAC_ERROR_HTTP_ERROR;
        }
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

// =============================================================================
// Engine ops vtable + C ABI factory
// =============================================================================

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
    // No "provider" key -> defaults to runanywhere inside ops_create, preserving the
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
