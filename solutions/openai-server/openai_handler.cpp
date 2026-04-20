// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// OpenAI endpoint handlers — port of runanywhere-commons/src/server/
// onto the `ra_*` C ABI. Uses `ra_llm_generate` on sessions resolved via
// `ServerSessionRegistry`.

#include "openai_handler.h"

#include "ra_primitives.h"
#include "ra_tool.h"
#include "server_session_registry.h"

#include <chrono>
#include <cstdio>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace ra::solutions::openai {

using json = nlohmann::json;

namespace {

std::string new_id(const char* prefix) {
    thread_local std::random_device rd;
    thread_local std::mt19937_64 gen(rd());
    thread_local std::uniform_int_distribution<uint64_t> dis;
    std::ostringstream os;
    os << prefix << std::hex << dis(gen);
    return os.str();
}

int64_t now_s() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

// Build a flat prompt from OpenAI `messages` array. Mirrors the shape from
// main's translation layer: system/user/assistant/tool blocks joined with
// newlines and terminated by an `assistant:` cue.
std::string build_prompt(const json& messages, const json& tools) {
    std::ostringstream os;

    if (tools.is_array() && !tools.empty()) {
        os << "[TOOLS]\n" << tools.dump() << "\n[/TOOLS]\n";
    }

    for (const auto& m : messages) {
        const std::string role = m.value("role", "user");
        const std::string content = m.value("content", "");
        if (role == "system") {
            os << "[SYSTEM]\n" << content << "\n";
        } else if (role == "user") {
            os << "[USER]\n" << content << "\n";
        } else if (role == "assistant") {
            os << "[ASSISTANT]\n" << content << "\n";
        } else if (role == "tool") {
            os << "[TOOL]\n" << content << "\n";
        }
    }
    os << "[ASSISTANT]\n";
    return os.str();
}

std::string resolve_model_id(const json& body) {
    if (body.contains("model") && body["model"].is_string()) {
        return body["model"].get<std::string>();
    }
    return ServerSessionRegistry::instance().default_model();
}

struct SyncCollector {
    std::string text;
    bool done = false;
    bool cancelled = false;
    int32_t tokens = 0;
    ra_status_t err = RA_OK;
};

void collect_token(const ra_token_output_t* t, void* ud) {
    auto* c = static_cast<SyncCollector*>(ud);
    if (!t) return;
    if (t->text && t->text[0]) c->text.append(t->text);
    if (t->is_final) c->done = true;
    else ++c->tokens;
}

void collect_error(ra_status_t code, const char* /*msg*/, void* ud) {
    auto* c = static_cast<SyncCollector*>(ud);
    c->err = code;
    c->done = true;
}

struct StreamCtx {
    httplib::DataSink* sink;
    std::string request_id;
    std::string model_id;
    int64_t created;
    int32_t tokens;
    bool done;
};

std::string format_sse(const json& payload) {
    std::string s = "data: ";
    s += payload.dump();
    s += "\n\n";
    return s;
}

void stream_token(const ra_token_output_t* t, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    if (!ctx || !t || !ctx->sink) return;

    json chunk = {
        {"id", ctx->request_id},
        {"object", "chat.completion.chunk"},
        {"created", ctx->created},
        {"model", ctx->model_id},
    };

    json choice = {{"index", 0}};
    if (t->is_final) {
        choice["delta"] = json::object();
        choice["finish_reason"] = "stop";
        ctx->done = true;
    } else {
        choice["delta"] = {{"content", t->text ? std::string(t->text) : ""}};
        choice["finish_reason"] = nullptr;
        ++ctx->tokens;
    }
    chunk["choices"] = json::array({choice});

    std::string sse = format_sse(chunk);
    ctx->sink->write(sse.c_str(), sse.size());
}

void stream_error(ra_status_t /*code*/, const char* /*msg*/, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    if (ctx) ctx->done = true;
}

}  // namespace

void OpenAIHandler::send_error(httplib::Response& res, int status,
                                const std::string& message,
                                const std::string& type) {
    json j = {{"error", {{"message", message}, {"type", type}, {"code", status}}}};
    res.status = status;
    res.set_content(j.dump(), "application/json");
}

void OpenAIHandler::handle_models(const httplib::Request&, httplib::Response& res) {
    auto ids = ServerSessionRegistry::instance().list();
    json data = json::array();
    int64_t created = now_s();
    if (ids.empty()) {
        data.push_back({{"id", "runanywhere-local"},
                        {"object", "model"},
                        {"created", created},
                        {"owned_by", "runanywhere"}});
    } else {
        for (const auto& id : ids) {
            data.push_back({{"id", id},
                            {"object", "model"},
                            {"created", created},
                            {"owned_by", "runanywhere"}});
        }
    }
    json out = {{"object", "list"}, {"data", data}};
    res.status = 200;
    res.set_content(out.dump(), "application/json");
}

void OpenAIHandler::handle_health(const httplib::Request&, httplib::Response& res) {
    auto& reg = ServerSessionRegistry::instance();
    bool loaded = reg.get("") != nullptr;
    json j = {{"status", "ok"},
              {"ok", true},
              {"model_loaded", loaded},
              {"model_id", reg.default_model()}};
    res.status = 200;
    res.set_content(j.dump(), "application/json");
}

void OpenAIHandler::handle_info(const httplib::Request&, httplib::Response& res) {
    json j = {{"name", "RunAnywhere Server"},
              {"version", "2.0.0"},
              {"endpoints", json::array({"GET /health", "GET /v1/models",
                                          "POST /v1/chat/completions",
                                          "POST /v1/completions"})}};
    res.status = 200;
    res.set_content(j.dump(2), "application/json");
}

void OpenAIHandler::handle_chat_completions(const httplib::Request& req,
                                             httplib::Response& res) {
    json body;
    try {
        body = json::parse(req.body);
    } catch (const std::exception& e) {
        send_error(res, 400, std::string("invalid json: ") + e.what(),
                   "invalid_request_error");
        return;
    }
    if (!body.contains("messages") || !body["messages"].is_array() ||
        body["messages"].empty()) {
        send_error(res, 400, "messages array is required", "invalid_request_error");
        return;
    }
    const bool stream = body.value("stream", false);
    if (stream) process_streaming(res, body);
    else        process_non_streaming(res, body);
}

void OpenAIHandler::handle_completions(const httplib::Request& req,
                                        httplib::Response& res) {
    // Legacy `prompt` style — translate into a single-user-message chat.
    json body;
    try {
        body = json::parse(req.body);
    } catch (const std::exception& e) {
        send_error(res, 400, std::string("invalid json: ") + e.what(),
                   "invalid_request_error");
        return;
    }
    const std::string prompt = body.value("prompt", "");
    if (prompt.empty()) {
        send_error(res, 400, "prompt is required", "invalid_request_error");
        return;
    }
    json translated = body;
    translated["messages"] = json::array({json{{"role", "user"}, {"content", prompt}}});
    translated.erase("prompt");
    const bool stream = body.value("stream", false);
    if (stream) process_streaming(res, translated);
    else        process_non_streaming(res, translated);
}

void OpenAIHandler::process_non_streaming(httplib::Response& res, const json& body) {
    const std::string model_id = resolve_model_id(body);
    ra_llm_session_t* session = ServerSessionRegistry::instance().get(model_id);
    if (!session) {
        send_error(res, 503, "no llm session registered", "server_error");
        return;
    }

    const json tools = body.value("tools", json::array());
    const std::string prompt_text = build_prompt(body["messages"], tools);

    SyncCollector col;
    ra_prompt_t p{};
    p.text = prompt_text.c_str();
    p.conversation_id = -1;

    ra_status_t rc = ra_llm_generate(session, &p, &collect_token, &collect_error, &col);
    if (rc != RA_OK && col.err == RA_OK) col.err = rc;
    if (col.err != RA_OK) {
        send_error(res, 500, "generation failed", "server_error");
        return;
    }
    total_tokens_ += col.tokens;

    // Try to extract a tool call — when tools are defined.
    std::string assistant_content = col.text;
    bool has_tool_call = false;
    ra_tool_call_t parsed{};
    std::string tool_name, tool_args;
    if (!tools.empty() && !col.text.empty()) {
        ra_status_t tc = ra_tool_call_parse(col.text.c_str(), &parsed);
        has_tool_call = (tc == RA_OK && parsed.has_call);
        if (has_tool_call) {
            if (parsed.tool_name)      tool_name = parsed.tool_name;
            if (parsed.arguments_json) tool_args = parsed.arguments_json;
            if (parsed.clean_text)     assistant_content = parsed.clean_text;
        }
    }

    json message = {{"role", "assistant"}};
    if (has_tool_call) {
        message["content"] = assistant_content;
        message["tool_calls"] = json::array({
            {{"id", new_id("call-")}, {"type", "function"},
             {"function", {{"name", tool_name}, {"arguments", tool_args}}}}
        });
    } else {
        message["content"] = assistant_content;
    }

    if (parsed.has_call) ra_tool_call_free(&parsed);

    json out = {
        {"id", new_id("chatcmpl-")},
        {"object", "chat.completion"},
        {"created", now_s()},
        {"model", model_id.empty() ? "runanywhere-local" : model_id},
        {"choices", json::array({
            {{"index", 0},
             {"message", message},
             {"finish_reason", has_tool_call ? "tool_calls" : "stop"}}
        })},
        {"usage", {{"prompt_tokens", static_cast<int>(prompt_text.size() / 4)},
                    {"completion_tokens", col.tokens},
                    {"total_tokens",
                     static_cast<int>(prompt_text.size() / 4) + col.tokens}}},
    };
    res.status = 200;
    res.set_content(out.dump(), "application/json");
}

void OpenAIHandler::process_streaming(httplib::Response& res, const json& body) {
    const std::string model_id = resolve_model_id(body);
    ra_llm_session_t* session = ServerSessionRegistry::instance().get(model_id);
    if (!session) {
        send_error(res, 503, "no llm session registered", "server_error");
        return;
    }

    const json tools = body.value("tools", json::array());
    const std::string prompt_text = build_prompt(body["messages"], tools);

    const std::string request_id = new_id("chatcmpl-");
    const int64_t created = now_s();

    res.set_header("Cache-Control", "no-cache");
    res.set_header("Connection", "keep-alive");
    res.set_chunked_content_provider(
        "text/event-stream",
        [this, session, prompt_text, request_id, created, model_id](
            size_t /*offset*/, httplib::DataSink& sink) mutable {
            // Role-first chunk.
            {
                json roll = {
                    {"id", request_id},
                    {"object", "chat.completion.chunk"},
                    {"created", created},
                    {"model", model_id.empty() ? "runanywhere-local" : model_id},
                    {"choices",
                     json::array({json{{"index", 0},
                                       {"delta", {{"role", "assistant"}}},
                                       {"finish_reason", nullptr}}})}};
                std::string sse = format_sse(roll);
                sink.write(sse.c_str(), sse.size());
            }

            StreamCtx ctx{&sink, request_id,
                          model_id.empty() ? std::string("runanywhere-local") : model_id,
                          created, 0, false};

            ra_prompt_t p{};
            p.text = prompt_text.c_str();
            p.conversation_id = -1;

            ra_status_t rc = ra_llm_generate(session, &p, &stream_token,
                                              &stream_error, &ctx);
            (void)rc;
            total_tokens_ += ctx.tokens;

            static const std::string DONE = "data: [DONE]\n\n";
            sink.write(DONE.c_str(), DONE.size());
            sink.done();
            return true;
        });
    res.status = 200;
}

}  // namespace ra::solutions::openai
