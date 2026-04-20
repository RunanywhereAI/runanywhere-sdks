// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tiny POSIX-socket HTTP server used by the OpenAI-compatible
// solutions/openai-server/. Not intended as a production-grade server:
// single-threaded accept loop with one worker thread per request, no
// TLS, minimal header parsing. Sufficient for local-dev OpenAI-API
// emulation while the SDK is running.
//
// Keeps this out of `core/` so the mobile XCFramework / AAR never pull
// in socket APIs.

#ifndef RA_SOLUTION_OPENAI_HTTP_SERVER_H
#define RA_SOLUTION_OPENAI_HTTP_SERVER_H

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace ra::solutions::openai {

struct HttpRequest {
    std::string method;
    std::string path;
    std::string query;
    std::unordered_map<std::string, std::string> headers;
    std::string body;
};

struct HttpResponse {
    int         status = 200;
    std::string content_type = "application/json";
    std::string body;
};

using RouteHandler = std::function<HttpResponse(const HttpRequest&)>;

class HttpServer {
public:
    HttpServer();
    ~HttpServer();

    // Bind + listen. Returns 0 on success, -1 on bind/listen error.
    int start(const std::string& host, int port);

    // Stop accepting + join accept thread. Idempotent.
    void stop();

    bool running() const { return running_.load(); }
    int  port()    const { return bound_port_; }

    // Register a handler for a specific method + path. Use "*" as path for
    // a fallback handler (last-resort 404 goes through this if present).
    void on(const std::string& method, const std::string& path, RouteHandler h);

private:
    void acceptLoop();
    void handleConnection(int client_fd);
    HttpResponse dispatch(const HttpRequest& req);

    std::atomic<bool>       running_{false};
    int                     listen_fd_   = -1;
    int                     bound_port_  = 0;
    std::thread             accept_thread_;
    mutable std::mutex      routes_mu_;
    std::unordered_map<std::string, RouteHandler> routes_;  // key = "METHOD <path>"
};

}  // namespace ra::solutions::openai

#endif  // RA_SOLUTION_OPENAI_HTTP_SERVER_H
