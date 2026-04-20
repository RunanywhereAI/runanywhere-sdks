// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// OpenAI-compatible HTTP server solution on top of httplib. Exposes the
// weak-linked entry points consumed by core/Public/ra_server.cpp so the
// `ra_server_*` C ABI starts/stops this server transparently when the
// solution library is linked into a host binary.

#include "openai_handler.h"
#include "server_session_registry.h"

#include "ra_primitives.h"
#include "ra_server.h"

#include <httplib.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace {

using ra::solutions::openai::OpenAIHandler;
using ra::solutions::openai::ServerSessionRegistry;

std::mutex                                  g_mu;
std::unique_ptr<httplib::Server>            g_http;
std::thread                                 g_thread;
std::shared_ptr<OpenAIHandler>              g_handler;
std::string                                 g_api_key;
std::string                                 g_host;
std::atomic<int32_t>                        g_bound_port{-1};
std::atomic<bool>                           g_running{false};
std::atomic<int64_t>                        g_total_requests{0};
std::atomic<int64_t>                        g_started_at_ms{0};

ra_server_request_callback_t                g_req_cb = nullptr;
void*                                       g_req_user = nullptr;

bool authorised(const httplib::Request& req) {
    if (g_api_key.empty()) return true;
    auto it = req.headers.find("Authorization");
    if (it == req.headers.end()) it = req.headers.find("authorization");
    if (it == req.headers.end()) return false;
    const std::string& h = it->second;
    static const std::string prefix = "Bearer ";
    if (h.size() <= prefix.size()) return false;
    return h.compare(0, prefix.size(), prefix) == 0 &&
           h.substr(prefix.size()) == g_api_key;
}

void notify_host(const httplib::Request& req) {
    ++g_total_requests;
    ra_server_request_callback_t cb;
    void* ud;
    {
        std::lock_guard lk(g_mu);
        cb = g_req_cb;
        ud = g_req_user;
    }
    if (cb) cb(req.method.c_str(), req.path.c_str(), req.body.c_str(), ud);
}

void wire_routes(httplib::Server& srv, OpenAIHandler& h) {
    srv.Get("/",         [&h](const httplib::Request& rq, httplib::Response& rs) {
        notify_host(rq); h.handle_info(rq, rs);
    });
    srv.Get("/health",   [&h](const httplib::Request& rq, httplib::Response& rs) {
        notify_host(rq); h.handle_health(rq, rs);
    });
    srv.Get("/healthz",  [&h](const httplib::Request& rq, httplib::Response& rs) {
        notify_host(rq); h.handle_health(rq, rs);
    });
    srv.Get("/v1/models", [&h](const httplib::Request& rq, httplib::Response& rs) {
        if (!authorised(rq)) {
            rs.status = 401;
            rs.set_content(R"({"error":{"message":"missing api key"}})",
                           "application/json");
            return;
        }
        notify_host(rq); h.handle_models(rq, rs);
    });
    srv.Post("/v1/chat/completions",
             [&h](const httplib::Request& rq, httplib::Response& rs) {
        if (!authorised(rq)) {
            rs.status = 401;
            rs.set_content(R"({"error":{"message":"missing api key"}})",
                           "application/json");
            return;
        }
        notify_host(rq); h.handle_chat_completions(rq, rs);
    });
    srv.Post("/v1/completions",
             [&h](const httplib::Request& rq, httplib::Response& rs) {
        if (!authorised(rq)) {
            rs.status = 401;
            rs.set_content(R"({"error":{"message":"missing api key"}})",
                           "application/json");
            return;
        }
        notify_host(rq); h.handle_completions(rq, rs);
    });

    srv.set_pre_routing_handler(
        [](const httplib::Request& rq, httplib::Response& rs) {
            rs.set_header("Access-Control-Allow-Origin", "*");
            rs.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            rs.set_header("Access-Control-Allow-Headers",
                          "Content-Type, Authorization");
            if (rq.method == "OPTIONS") {
                rs.status = 204;
                return httplib::Server::HandlerResponse::Handled;
            }
            return httplib::Server::HandlerResponse::Unhandled;
        });
}

}  // namespace

// C ABI consumed by core/Public/ra_server.cpp through weak-symbol lookup.
extern "C" {

int32_t ra_solution_openai_server_start(const char* host, int32_t port,
                                         const char* api_key) {
    std::lock_guard lk(g_mu);
    if (g_running.load()) return g_bound_port.load();

    g_host    = host ? host : "127.0.0.1";
    g_api_key = api_key ? api_key : "";
    g_handler = std::make_shared<OpenAIHandler>();
    g_http    = std::make_unique<httplib::Server>();

    wire_routes(*g_http, *g_handler);

    // Bind first so we know the port before announcing running. Use
    // bind_to_any_port when the caller asks for an ephemeral port so we
    // learn the actual bound port without requiring a second syscall.
    int bound;
    if (port <= 0) {
        bound = g_http->bind_to_any_port(g_host);
        if (bound < 0) {
            g_http.reset();
            g_handler.reset();
            return -1;
        }
    } else {
        if (!g_http->bind_to_port(g_host, port)) {
            g_http.reset();
            g_handler.reset();
            return -1;
        }
        bound = port;
    }
    g_bound_port.store(bound);

    g_running.store(true);
    g_started_at_ms.store(std::chrono::duration_cast<std::chrono::milliseconds>(
                              std::chrono::system_clock::now().time_since_epoch())
                              .count());

    g_thread = std::thread([] {
        if (g_http) g_http->listen_after_bind();
        g_running.store(false);
    });

    // Block until httplib's acceptor is actually ready — otherwise the
    // first test request races with thread startup and the client sees
    // a connection-refused.
    if (g_http) g_http->wait_until_ready();

    return bound;
}

void ra_solution_openai_server_stop(void) {
    std::unique_lock lk(g_mu);
    if (!g_running.load() && !g_http) return;
    if (g_http) g_http->stop();
    lk.unlock();
    if (g_thread.joinable()) g_thread.join();
    lk.lock();
    g_http.reset();
    g_handler.reset();
    g_running.store(false);
    g_bound_port.store(-1);
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

// Session registry bridge so frontends / standalone binaries can attach an
// `ra_llm_session_t*` created via `ra_llm_create` to a model id.
ra_status_t ra_solution_openai_server_register_session(const char*       model_id,
                                                        ra_llm_session_t* session) {
    if (!model_id) return RA_ERR_INVALID_ARGUMENT;
    ServerSessionRegistry::instance().set(model_id, session);
    return RA_OK;
}

void ra_solution_openai_server_set_default_model(const char* model_id) {
    ServerSessionRegistry::instance().set_default(model_id ? model_id : "");
}

void ra_solution_openai_server_clear_sessions(void) {
    ServerSessionRegistry::instance().clear();
}

}  // extern "C"
