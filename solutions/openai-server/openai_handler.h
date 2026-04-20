// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// OpenAI-compatible endpoint handlers. Ports the main-branch layout onto
// the v2 `ra_*` ABI — every generation call goes through `ra_llm_generate`
// on sessions resolved via `ServerSessionRegistry`.

#ifndef RA_SERVER_OPENAI_HANDLER_H
#define RA_SERVER_OPENAI_HANDLER_H

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <atomic>
#include <string>

namespace ra::solutions::openai {

class OpenAIHandler {
public:
    OpenAIHandler() = default;

    // GET /v1/models
    void handle_models(const httplib::Request& req, httplib::Response& res);

    // POST /v1/chat/completions
    void handle_chat_completions(const httplib::Request& req, httplib::Response& res);

    // POST /v1/completions (legacy-style, accepts `prompt` string)
    void handle_completions(const httplib::Request& req, httplib::Response& res);

    // GET /health
    void handle_health(const httplib::Request& req, httplib::Response& res);

    // GET /
    void handle_info(const httplib::Request& req, httplib::Response& res);

    int64_t total_tokens() const { return total_tokens_.load(); }

private:
    void process_non_streaming(httplib::Response& res, const nlohmann::json& body);
    void process_streaming(httplib::Response& res, const nlohmann::json& body);
    void send_error(httplib::Response& res, int status, const std::string& message,
                    const std::string& type);

    std::atomic<int64_t> total_tokens_{0};
};

}  // namespace ra::solutions::openai

#endif  // RA_SERVER_OPENAI_HANDLER_H
