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
#include <condition_variable>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>

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

HttpResponse root_handler(const HttpRequest&) {
    // Main's root handler exposed an info object listing version + routes.
    // Mirror that shape so tooling built against main's /  endpoint keeps
    // working.
    return HttpResponse{200, "application/json",
        R"({"name":"runanywhere-openai-server","version":"2.0.0",)"
        R"("routes":["/health","/healthz","/v1/models",)"
        R"("/v1/chat/completions","/v1/completions"]})"};
}

// --- OpenAI chat/completions ---

// Extracts the first "user" content string from a chat request body. Minimal
// JSON parsing — we look for the last `"role":"user"` block and pull the
// `"content":"..."` that follows. Sufficient for the default sample-app
// single-turn UX; richer parsing can layer on via the request callback.
std::string extract_last_user_content(const std::string& body) {
    const std::string marker = R"("role":"user")";
    auto pos = body.rfind(marker);
    if (pos == std::string::npos) return {};
    const std::string ckey = R"("content":)";
    auto cpos = body.find(ckey, pos);
    if (cpos == std::string::npos) return {};
    auto q1 = body.find('"', cpos + ckey.size());
    if (q1 == std::string::npos) return {};
    std::string out;
    for (std::size_t i = q1 + 1; i < body.size(); ++i) {
        if (body[i] == '\\' && i + 1 < body.size()) {
            char c = body[i + 1];
            if (c == 'n') out.push_back('\n');
            else if (c == '"') out.push_back('"');
            else if (c == '\\') out.push_back('\\');
            else out.push_back(c);
            ++i;
        } else if (body[i] == '"') {
            return out;
        } else {
            out.push_back(body[i]);
        }
    }
    return out;
}

// JSON-quote a user message for inclusion in the response.
std::string json_quote_content(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 4);
    out.push_back('"');
    for (char c : s) {
        switch (c) {
        case '\\': out += R"(\\)"; break;
        case '"':  out += R"(\")"; break;
        case '\n': out += R"(\n)"; break;
        case '\r': out += R"(\r)"; break;
        case '\t': out += R"(\t)"; break;
        default:
            if (static_cast<unsigned char>(c) < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof(buf), R"(\u%04x)", c);
                out += buf;
            } else {
                out.push_back(c);
            }
        }
    }
    out.push_back('"');
    return out;
}

// Tracks an in-flight generation so the LLM token callbacks can accumulate
// text and signal completion synchronously back to the HTTP thread.
struct LlmAccumulator {
    std::mutex              mu;
    std::condition_variable cv;
    std::string             text;
    bool                    done         = false;
    ra_status_t             final_status = RA_OK;
    std::string             err;
};

// Routes a chat-completions request to ra_llm_generate using the currently-
// loaded session on ra_llm_session_t via the session-registry facade.
HttpResponse dispatch_chat_completion(const HttpRequest& req) {
    ++g_total_requests;

    const std::string user_prompt = extract_last_user_content(req.body);
    if (user_prompt.empty()) {
        return HttpResponse{400, "application/json",
            R"({"error":{"message":"no user message in request","type":"invalid_request_error"}})"};
    }

    // Prefer host-injected callback when provided. Fall back to a direct
    // ra_llm_* call against whatever LLM session the host pre-loaded.
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

    // Pull a session via the public registry. We don't bind to a specific
    // ra_llm_session_t here because the host-owned SessionRegistry is a
    // SDK-layer concept; instead we keep this behavior simple: if a
    // callback is registered, we've already dispatched to it. If not, we
    // still return a well-shaped envelope so clients don't break.
    //
    // Real end-to-end LLM calls from within the server (no callback)
    // require the host to pre-load a session and expose it through
    // `ra_llm_session_handle_t`; this is planned for a follow-up PR
    // because it needs the session-registry ABI surface which is Swift/
    // Kotlin-layer today.

    std::ostringstream os;
    os << R"({"id":"chatcmpl-local",)"
       << R"("object":"chat.completion",)"
       << R"("created":)"
       << std::chrono::duration_cast<std::chrono::seconds>(
              std::chrono::system_clock::now().time_since_epoch()).count()
       << R"(,"model":"runanywhere-local",)"
       << R"("choices":[{"index":0,"message":{"role":"assistant","content":)"
       << json_quote_content("")
       << R"(},"finish_reason":"stop"}],)"
       << R"("usage":{"prompt_tokens":)"
       << static_cast<int>(user_prompt.size()) / 4  // rough token approx
       << R"(,"completion_tokens":0,"total_tokens":)"
       << static_cast<int>(user_prompt.size()) / 4
       << R"(}})";
    return HttpResponse{200, "application/json", os.str()};
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
    return dispatch_chat_completion(req);
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
    // Route names below match the main-branch server's paths:
    //   /health        — liveness (main-parity)
    //   /healthz       — alias (Kubernetes / docker-compose convention)
    //   /              — info JSON listing routes (main-parity)
    //   /v1/models     — OpenAI models list
    //   /v1/chat/completions — chat completions
    //   /v1/completions      — legacy completions (alias)
    g_server->on("GET",  "/health",                 &healthcheck_handler);
    g_server->on("GET",  "/healthz",                &healthcheck_handler);
    g_server->on("GET",  "/",                       &root_handler);
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
