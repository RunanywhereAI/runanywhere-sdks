// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// OpenAI-compatible HTTP solution. Registers routes with a small
// POSIX-socket HTTP server and connects them to ra_server_* + the
// host's registered request callback.

#include "http_server.h"

#include "../../core/abi/ra_server.h"
#include "../../core/abi/ra_primitives.h"

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <sstream>

namespace {

using ra::solutions::openai::HttpServer;
using ra::solutions::openai::HttpRequest;
using ra::solutions::openai::HttpResponse;

std::mutex                    g_mu;
std::unique_ptr<HttpServer>   g_server;
std::string                   g_api_key;

ra_server_request_callback_t  g_req_cb   = nullptr;
void*                         g_req_user = nullptr;

std::atomic<int64_t>          g_total_requests{0};
std::atomic<int64_t>          g_started_at_ms{0};

bool authorised(const HttpRequest& req) {
    if (g_api_key.empty()) return true;
    auto it = req.headers.find("authorization");
    if (it == req.headers.end()) return false;
    const std::string& h = it->second;
    const std::string prefix = "Bearer ";
    if (h.size() <= prefix.size()) return false;
    return h.compare(0, prefix.size(), prefix) == 0 &&
            h.substr(prefix.size()) == g_api_key;
}

HttpResponse healthcheck_handler(const HttpRequest&) {
    return HttpResponse{200, "application/json", R"({"ok":true})"};
}

HttpResponse models_handler(const HttpRequest& req) {
    if (!authorised(req)) {
        return HttpResponse{401, "application/json",
            R"({"error":{"message":"missing api key"}})"};
    }
    ++g_total_requests;
    return HttpResponse{200, "application/json",
        R"({"object":"list","data":[{"id":"runanywhere-local","object":"model","owned_by":"runanywhere"}]})"};
}

HttpResponse chat_completions_handler(const HttpRequest& req) {
    if (!authorised(req)) {
        return HttpResponse{401, "application/json",
            R"({"error":{"message":"missing api key"}})"};
    }
    ++g_total_requests;

    ra_server_request_callback_t cb;
    void*                        ud;
    {
        std::lock_guard lk(g_mu);
        cb = g_req_cb;
        ud = g_req_user;
    }
    if (cb) {
        cb(req.method.c_str(), req.path.c_str(), req.body.c_str(), ud);
    }

    // Minimal placeholder response body — the real router lives in the
    // host process via the request callback and fills a JSON reply by
    // invoking ra_llm_generate. Returning a well-formed (empty) OpenAI
    // response keeps clients happy when no callback is registered.
    const char* body = R"({
        "id":"chatcmpl-local",
        "object":"chat.completion",
        "model":"runanywhere-local",
        "choices":[{"index":0,"message":{"role":"assistant","content":""},
                    "finish_reason":"stop"}],
        "usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}
    })";
    return HttpResponse{200, "application/json", body};
}

}  // namespace

// C ABI used by solutions/openai-server/ to hook into ra_server_*.
// The ra_server.cpp stub calls these via weak symbol lookup (or direct
// static link) when the solution library is linked into the final binary.
extern "C" {

int32_t ra_solution_openai_server_start(const char* host, int32_t port,
                                           const char* api_key) {
    std::lock_guard lk(g_mu);
    if (g_server && g_server->running()) return g_server->port();
    g_api_key = api_key ? api_key : "";
    g_server  = std::make_unique<HttpServer>();
    if (g_server->start(host ? host : "127.0.0.1", port) != 0) {
        g_server.reset();
        return -1;
    }
    g_server->on("GET",  "/healthz",                &healthcheck_handler);
    g_server->on("GET",  "/v1/models",              &models_handler);
    g_server->on("POST", "/v1/chat/completions",    &chat_completions_handler);
    g_server->on("POST", "/v1/completions",         &chat_completions_handler);
    g_started_at_ms.store(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
    return g_server->port();
}

void ra_solution_openai_server_stop(void) {
    std::lock_guard lk(g_mu);
    if (g_server) { g_server->stop(); g_server.reset(); }
}

void ra_solution_openai_server_set_callback(
    ra_server_request_callback_t cb, void* user_data) {
    std::lock_guard lk(g_mu);
    g_req_cb   = cb;
    g_req_user = user_data;
}

int64_t ra_solution_openai_server_total_requests(void) {
    return g_total_requests.load();
}

int64_t ra_solution_openai_server_started_at_ms(void) {
    return g_started_at_ms.load();
}

}  // extern "C"
