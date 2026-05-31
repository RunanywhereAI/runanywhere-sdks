/**
 * @file rac_llm_openrouter.cpp
 * @brief OpenRouter LLM backend implementation.
 *
 * The impl struct stores the api key, model id, base URL, and the cancel
 * flag toggled by rac_llm_service_ops::cancel. Each generate / generate_stream
 * call constructs a fresh HTTP request, issues it through the commons
 * rac_http_client_* ABI, and decodes the OpenAI-compatible response.
 */

#include "rac/backends/rac_llm_openrouter.h"

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
#define ORENG_LOG(...) __android_log_print(ANDROID_LOG_INFO,  "openrouter", __VA_ARGS__)
#define ORENG_LOG_E(...) __android_log_print(ANDROID_LOG_ERROR, "openrouter", __VA_ARGS__)
#else
#define ORENG_LOG(...) ((void)0)
#define ORENG_LOG_E(...) ((void)0)
#endif

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

constexpr const char* kDefaultBaseUrl = "https://openrouter.ai/api/v1";
constexpr int32_t     kDefaultTimeoutMs = 30000;

struct OpenRouterImpl {
    std::string api_key;
    std::string model;
    std::string base_url;
    int32_t     timeout_ms = kDefaultTimeoutMs;
    std::string http_referer;
    std::string x_title;
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

nlohmann::json build_payload(const OpenRouterImpl&    impl,
                             const char*              prompt,
                             const rac_llm_options_t* options,
                             bool                     stream) {
    nlohmann::json messages = nlohmann::json::array();
    if (options != nullptr && options->system_prompt != nullptr &&
        options->system_prompt[0] != '\0') {
        messages.push_back({{"role", "system"}, {"content", options->system_prompt}});
    }
    messages.push_back({{"role", "user"}, {"content", prompt != nullptr ? prompt : ""}});

    nlohmann::json payload = {
        {"model", impl.model},
        {"messages", std::move(messages)},
        {"stream", stream},
    };
    if (options != nullptr) {
        if (options->max_tokens > 0) {
            payload["max_tokens"] = options->max_tokens;
        }
        payload["temperature"] = options->temperature;
        payload["top_p"]       = options->top_p;
        if (options->stop_sequences != nullptr && options->num_stop_sequences > 0) {
            nlohmann::json stop = nlohmann::json::array();
            for (size_t i = 0; i < options->num_stop_sequences; ++i) {
                if (options->stop_sequences[i] != nullptr) {
                    stop.push_back(options->stop_sequences[i]);
                }
            }
            payload["stop"] = std::move(stop);
        }
    }
    return payload;
}

std::vector<rac_http_header_kv_t> build_headers(const OpenRouterImpl& impl,
                                                std::string&          auth_storage,
                                                std::string&          referer_storage,
                                                std::string&          title_storage) {
    auth_storage = "Bearer " + impl.api_key;
    referer_storage = impl.http_referer.empty() ? std::string("https://runanywhere.ai")
                                                : impl.http_referer;
    title_storage = impl.x_title.empty() ? std::string("RunAnywhere SDK") : impl.x_title;
    return {
        {"Authorization", auth_storage.c_str()},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"},
        {"HTTP-Referer", referer_storage.c_str()},
        {"X-Title", title_storage.c_str()},
    };
}

rac_result_t issue_blocking(OpenRouterImpl&      impl,
                            const std::string&   body,
                            rac_http_response_t& resp) {
    std::string auth_storage, referer_storage, title_storage;
    const auto  headers = build_headers(impl, auth_storage, referer_storage, title_storage);
    const std::string url = impl.base_url + "/chat/completions";

    rac_http_request_t req{};
    req.method = "POST";
    req.url = url.c_str();
    req.headers = headers.data();
    req.header_count = headers.size();
    req.body_bytes = reinterpret_cast<const uint8_t*>(body.data());
    req.body_len = body.size();
    req.timeout_ms = impl.timeout_ms;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || client == nullptr) {
        ORENG_LOG_E("issue_blocking: http_client_create rc=%d", rc);
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL;
    }
    ORENG_LOG("issue_blocking: POST %s body_len=%zu", url.c_str(), body.size());
    std::lock_guard<std::mutex> lock(impl.http_mutex);
    rc = rac_http_request_send(client, &req, &resp);
    rac_http_client_destroy(client);
    ORENG_LOG("issue_blocking: send rc=%d status=%d body_len=%zu", rc, resp.status, resp.body_len);
    return rc;
}

rac_result_t parse_blocking_response(const rac_http_response_t& resp,
                                     rac_llm_result_t*          out_result,
                                     int64_t                    elapsed_ms) {
    if (resp.status < 200 || resp.status >= 300) {
        ORENG_LOG_E("HTTP %d: %.*s",
                    resp.status,
                    (int)std::min<size_t>(resp.body_len, 512),
                    reinterpret_cast<const char*>(resp.body_bytes));
        RAC_LOG_ERROR("openrouter",
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
        const auto& choices = json.at("choices");
        if (!choices.is_array() || choices.empty()) {
            return RAC_ERROR_INVALID_RESPONSE;
        }
        const auto& message = choices.at(0).at("message");
        const auto  content = message.value("content", std::string{});

        out_result->text = dup_cstr(content);
        if (out_result->text == nullptr) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        if (json.contains("usage")) {
            const auto& usage = json.at("usage");
            out_result->prompt_tokens     = usage.value("prompt_tokens", 0);
            out_result->completion_tokens = usage.value("completion_tokens", 0);
            out_result->total_tokens      = usage.value("total_tokens", 0);
        }
        out_result->total_time_ms = elapsed_ms;
        out_result->time_to_first_token_ms = elapsed_ms;
        if (out_result->completion_tokens > 0 && elapsed_ms > 0) {
            out_result->tokens_per_second =
                static_cast<float>(out_result->completion_tokens) * 1000.0f /
                static_cast<float>(elapsed_ms);
        }
        return RAC_SUCCESS;
    } catch (const std::exception&) {
        return RAC_ERROR_INVALID_RESPONSE;
    }
}

struct StreamCtx {
    OpenRouterImpl*            impl;
    rac_llm_stream_callback_fn cb;
    void*                      user_data;
    std::string                pending_line;
    bool                       saw_done = false;
};

void dispatch_sse_event(StreamCtx& ctx, const std::string& line) {
    constexpr const char* kDataPrefix = "data:";
    constexpr size_t      kDataPrefixLen = 5;
    if (line.size() <= kDataPrefixLen ||
        std::strncmp(line.c_str(), kDataPrefix, kDataPrefixLen) != 0) {
        return;
    }
    size_t start = kDataPrefixLen;
    while (start < line.size() && (line[start] == ' ' || line[start] == '\t')) {
        ++start;
    }
    const std::string payload = line.substr(start);
    if (payload == "[DONE]") {
        ctx.saw_done = true;
        return;
    }
    try {
        const auto  json = nlohmann::json::parse(payload);
        const auto& choices = json.at("choices");
        if (!choices.is_array() || choices.empty()) {
            return;
        }
        const auto& delta = choices.at(0).at("delta");
        const auto  token = delta.value("content", std::string{});
        if (!token.empty() && ctx.cb != nullptr) {
            if (ctx.cb(token.c_str(), ctx.user_data) == RAC_FALSE) {
                ctx.impl->cancelled.store(true);
            }
        }
    } catch (const std::exception&) {
        // Tolerate malformed deltas; OpenRouter occasionally interleaves
        // status comments that aren't JSON.
    }
}

rac_bool_t stream_chunk_cb(const uint8_t* chunk, size_t chunk_len, uint64_t /*total_written*/,
                           uint64_t /*content_length*/, void* user_data) {
    auto* ctx = static_cast<StreamCtx*>(user_data);
    if (ctx == nullptr) {
        return RAC_FALSE;
    }
    if (ctx->impl != nullptr && ctx->impl->cancelled.load()) {
        return RAC_FALSE;
    }
    ctx->pending_line.append(reinterpret_cast<const char*>(chunk), chunk_len);
    while (true) {
        const size_t nl = ctx->pending_line.find('\n');
        if (nl == std::string::npos) {
            break;
        }
        std::string line = ctx->pending_line.substr(0, nl);
        ctx->pending_line.erase(0, nl + 1);
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        if (line.empty()) {
            continue;
        }
        dispatch_sse_event(*ctx, line);
        if (ctx->saw_done) {
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

rac_result_t parse_config(const std::string& config_json, OpenRouterImpl& out) {
    try {
        const auto json = nlohmann::json::parse(config_json);
        out.api_key = json.value("api_key", std::string{});
        out.model   = json.value("model", std::string{});
        out.base_url = json.value("base_url", std::string{kDefaultBaseUrl});
        out.timeout_ms = json.value("timeout_ms", kDefaultTimeoutMs);
        out.http_referer = json.value("http_referer", std::string{});
        out.x_title = json.value("x_title", std::string{});
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
    auto impl = std::make_unique<OpenRouterImpl>();
    impl->base_url = kDefaultBaseUrl;
    impl->timeout_ms = kDefaultTimeoutMs;
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

rac_result_t ops_generate(void* impl_v, const char* prompt, const rac_llm_options_t* options,
                          rac_llm_result_t* out_result) {
    ORENG_LOG("ops_generate called impl=%p prompt_len=%zu", impl_v,
              prompt ? std::strlen(prompt) : 0);
    auto* impl = static_cast<OpenRouterImpl*>(impl_v);
    if (impl == nullptr || prompt == nullptr || out_result == nullptr) {
        ORENG_LOG_E("ops_generate INVALID_PARAMETER impl=%p prompt=%p out=%p",
                    impl_v, (void*)prompt, (void*)out_result);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    impl->cancelled.store(false);
    std::memset(out_result, 0, sizeof(*out_result));

    const auto payload = build_payload(*impl, prompt, options, /*stream=*/false);
    const std::string body = payload.dump();

    const auto start = std::chrono::steady_clock::now();
    rac_http_response_t resp{};
    rac_result_t rc = issue_blocking(*impl, body, resp);
    const auto elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() -
                                                              start)
            .count();
    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&resp);
        return rc;
    }
    rc = parse_blocking_response(resp, out_result, static_cast<int64_t>(elapsed_ms));
    rac_http_response_free(&resp);
    return rc;
}

rac_result_t ops_generate_stream(void* impl_v, const char* prompt,
                                 const rac_llm_options_t*   options,
                                 rac_llm_stream_callback_fn callback, void* user_data) {
    auto* impl = static_cast<OpenRouterImpl*>(impl_v);
    if (impl == nullptr || prompt == nullptr || callback == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    impl->cancelled.store(false);

    const auto payload = build_payload(*impl, prompt, options, /*stream=*/true);
    const std::string body = payload.dump();

    std::string auth_storage, referer_storage, title_storage;
    auto headers = build_headers(*impl, auth_storage, referer_storage, title_storage);
    headers.push_back({"Accept", "text/event-stream"});
    const std::string url = impl->base_url + "/chat/completions";

    rac_http_request_t req{};
    req.method = "POST";
    req.url = url.c_str();
    req.headers = headers.data();
    req.header_count = headers.size();
    req.body_bytes = reinterpret_cast<const uint8_t*>(body.data());
    req.body_len = body.size();
    req.timeout_ms = impl->timeout_ms;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    StreamCtx ctx{impl, callback, user_data, {}, false};

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || client == nullptr) {
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL;
    }
    rac_http_response_t resp_meta{};
    {
        std::lock_guard<std::mutex> lock(impl->http_mutex);
        rc = rac_http_request_stream(client, &req, stream_chunk_cb, &ctx, &resp_meta);
    }
    rac_http_client_destroy(client);
    rac_http_response_free(&resp_meta);

    if (rc == RAC_ERROR_CANCELLED && ctx.saw_done) {
        return RAC_SUCCESS;
    }
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (resp_meta.status >= 200 && resp_meta.status < 300) {
        return RAC_SUCCESS;
    }
    RAC_LOG_ERROR("openrouter",
                  "HTTP %d (stream): %.*s",
                  resp_meta.status,
                  (int)std::min<size_t>(resp_meta.body_len, 512),
                  reinterpret_cast<const char*>(resp_meta.body_bytes));
    return RAC_ERROR_HTTP_ERROR;
}

rac_result_t ops_get_info(void* impl_v, rac_llm_info_t* out_info) {
    auto* impl = static_cast<OpenRouterImpl*>(impl_v);
    if (impl == nullptr || out_info == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    out_info->is_ready = RAC_TRUE;
    out_info->current_model = impl->model.c_str();
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t ops_cancel(void* impl_v) {
    auto* impl = static_cast<OpenRouterImpl*>(impl_v);
    if (impl == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    impl->cancelled.store(true);
    return RAC_SUCCESS;
}

rac_result_t ops_cleanup(void* /*impl*/) {
    return RAC_SUCCESS;
}

void ops_destroy(void* impl_v) {
    delete static_cast<OpenRouterImpl*>(impl_v);
}

}  // namespace

const rac_llm_service_ops_t g_openrouter_llm_ops = {
    /* initialize                 */ ops_initialize,
    /* generate                   */ ops_generate,
    /* generate_stream            */ ops_generate_stream,
    /* generate_stream_with_timing*/ nullptr,
    /* get_info                   */ ops_get_info,
    /* cancel                     */ ops_cancel,
    /* cleanup                    */ ops_cleanup,
    /* destroy                    */ ops_destroy,
    /* load_lora                  */ nullptr,
    /* remove_lora                */ nullptr,
    /* clear_lora                 */ nullptr,
    /* get_lora_info              */ nullptr,
    /* inject_system_prompt       */ nullptr,
    /* append_context             */ nullptr,
    /* generate_from_context      */ nullptr,
    /* clear_context              */ nullptr,
    /* create                     */ ops_create,
};

extern "C" {

rac_result_t rac_llm_openrouter_create(const char* api_key, const char* model,
                                       rac_llm_service_t** out_service) {
    if (api_key == nullptr || model == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;
    nlohmann::json cfg = {{"api_key", api_key}, {"model", model}};
    const std::string cfg_str = cfg.dump();
    return rac_llm_openrouter_create_from_json(cfg_str.c_str(), out_service);
}

rac_result_t rac_llm_openrouter_create_from_json(const char*         config_json,
                                                 rac_llm_service_t** out_service) {
    if (config_json == nullptr || out_service == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_service = nullptr;

    void* impl = nullptr;
    rac_result_t rc = g_openrouter_llm_ops.create(/*model_id=*/nullptr, config_json, &impl);
    if (rc != RAC_SUCCESS || impl == nullptr) {
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INITIALIZATION_FAILED;
    }
    auto* svc = new (std::nothrow) rac_llm_service_t{};
    if (svc == nullptr) {
        g_openrouter_llm_ops.destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    svc->ops = &g_openrouter_llm_ops;
    svc->impl = impl;
    auto* impl_typed = static_cast<OpenRouterImpl*>(impl);
    svc->model_id = impl_typed->model.c_str();
    *out_service = svc;
    return RAC_SUCCESS;
}

void rac_llm_openrouter_destroy(rac_llm_service_t* service) {
    if (service == nullptr) {
        return;
    }
    if (service->ops != nullptr && service->ops->destroy != nullptr && service->impl != nullptr) {
        service->ops->destroy(service->impl);
    }
    delete service;
}

}  // extern "C"
