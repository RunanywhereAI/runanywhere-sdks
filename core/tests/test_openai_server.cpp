/** Hermetic HTTP contract tests. A deterministic backend exercises real SDK
 * dispatch, tool parsing, HTTP serialization, cancellation and concurrent clients. */
#define google runanywhere_internal
#include "../src/generated/proto/llm_service.pb.h"
#undef google
#include "openai_handler.h"
#include "openai_translation.h"
#include "rac/server/rac_server.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <future>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using Json = nlohmann::json;
using namespace std::chrono_literals;

namespace {
int assertions = 0;
void check(bool value, const char* label) {
    ++assertions;
    if (!value)
        throw std::runtime_error(label);
}
struct Backend {
    std::string output = "hello";
    std::string finish = "stop";
    std::string prompt;
    int threads = 0;
    int maxTokens = 0;
    int promptTokens = 31;
    int cachedPromptTokens = 13;
    int structuredCalls = 0;
    runanywhere::v1::LLMGenerateRequest request;
    std::vector<std::string> stops;
    std::atomic<int> running{0}, peak{0}, cancelledCalls{0};
    std::atomic<bool> cancelled{false};
    int delayMs = 0;
    rac_result_t result = RAC_SUCCESS;
};

rac_result_t runGeneration(Backend& backend, const rac_llm_options_t* options,
                           rac_llm_stream_callback_fn callback, void* user) {
    const int running = ++backend.running;
    if (running > backend.peak)
        backend.peak = running;
    backend.cancelled = false;
    if (options) {
        backend.threads = options->n_threads;
        backend.maxTokens = options->max_tokens;
        backend.stops.clear();
        for (size_t i = 0; i < options->num_stop_sequences; ++i)
            backend.stops.emplace_back(options->stop_sequences[i]);
    }
    for (int elapsed = 0; elapsed < backend.delayMs && !backend.cancelled; elapsed += 10)
        std::this_thread::sleep_for(10ms);
    if (backend.cancelled) {
        --backend.running;
        return RAC_ERROR_CANCELLED;
    }
    for (char byte : backend.output) {
        const std::string token(1, byte);
        if (!callback(token.c_str(), RAC_FALSE, nullptr, 1, user)) {
            --backend.running;
            return RAC_ERROR_CANCELLED;
        }
    }
    callback("", RAC_TRUE, backend.finish.c_str(), 0, user);
    --backend.running;
    return backend.result;
}

rac_llm_service_ops_t operations = [] {
    rac_llm_service_ops_t ops{};
    ops.get_info = [](void*, rac_llm_info_t* info) {
        info->is_ready = RAC_TRUE;
        info->supports_streaming = RAC_TRUE;
        return RAC_SUCCESS;
    };
    ops.cancel = [](void* state) {
        auto& backend = *static_cast<Backend*>(state);
        backend.cancelled = true;
        ++backend.cancelledCalls;
        return RAC_SUCCESS;
    };
    ops.get_stream_token_counts = [](void* state, rac_llm_token_counts_t* out) {
        auto& backend = *static_cast<Backend*>(state);
        out->prompt_tokens = backend.promptTokens;
        out->completion_tokens = 9;
        out->cached_prompt_tokens = backend.cachedPromptTokens;
        return RAC_SUCCESS;
    };
    ops.generate_stream = [](void* state, const char* prompt, const rac_llm_options_t* options,
                             rac_llm_stream_callback_fn callback, void* user) {
        auto& backend = *static_cast<Backend*>(state);
        backend.prompt = prompt;
        return runGeneration(backend, options, callback, user);
    };
    ops.generate_chat_stream = [](void* state, const uint8_t* bytes, size_t size,
                                  rac_llm_stream_callback_fn callback, void* user) {
        auto& backend = *static_cast<Backend*>(state);
        if (!backend.request.ParseFromArray(bytes, static_cast<int>(size)))
            return RAC_ERROR_INVALID_ARGUMENT;
        ++backend.structuredCalls;
        return runGeneration(backend, nullptr, callback, user);
    };
    return ops;
}();

struct Fixture {
    Backend backend;
    rac_llm_service_ops_t ops = operations;
    rac_llm_service_t service{&ops, &backend, "fixture"};
    rac::server::OpenAIHandler handler{&service, "fixture", 7, 1};
    httplib::Server server;
    std::thread thread;
    int port;
    explicit Fixture(bool structured = true) {
        if (!structured)
            ops.generate_chat_stream = nullptr;
        server.Post("/v1/chat/completions",
                    [&](const auto& req, auto& res) { handler.handleChatCompletions(req, res); });
        server.Get("/health", [&](const auto& req, auto& res) { handler.handleHealth(req, res); });
        port = server.bind_to_any_port("127.0.0.1");
        check(port > 0, "bind loopback ephemeral port");
        thread = std::thread([&] { server.listen_after_bind(); });
    }
    ~Fixture() {
        server.stop();
        thread.join();
    }
    httplib::Result post(Json request) {
        httplib::Client client("127.0.0.1", port);
        client.set_read_timeout(5, 0);
        return client.Post("/v1/chat/completions", request.dump(), "application/json");
    }
};
Json base(bool stream = false) {
    return {{"model", "fixture"},
            {"stream", stream},
            {"messages", Json::array({{{"role", "user"}, {"content", "Say hello"}}})}};
}
Json toolRequest(bool stream = false) {
    auto request = base(stream);
    request["tools"] = Json::array({{{"type", "function"},
                                     {"function",
                                      {{"name", "read_file"},
                                       {"description", "Read a file"},
                                       {"parameters",
                                        {{"type", "object"},
                                         {"properties", {{"path", {{"type", "string"}}}}},
                                         {"required", {"path"}}}}}}}});
    request["messages"] = Json::array(
        {{{"role", "system"}, {"content", "Remember PROJECT_RULES"}},
         {{"role", "user"},
          {"content", Json::array({{{"type", "text"}, {"text", "FIRST"}},
                                   {{"type", "text"}, {"text", "_TURN"}}})}},
         {{"role", "assistant"},
          {"content", nullptr},
          {"tool_calls",
           Json::array({{{"id", "call_old"},
                         {"type", "function"},
                         {"function",
                          {{"name", "read_file"}, {"arguments", "{\"path\":\"first.txt\"}"}}}}})}},
         {{"role", "tool"}, {"tool_call_id", "call_old"}, {"content", "FIRST_FILE_RESULT"}},
         {{"role", "user"}, {"content", "Continue from that file"}}});
    return request;
}
std::vector<Json> events(const std::string& body) {
    std::vector<Json> parsed;
    size_t start = 0;
    while ((start = body.find("data: ", start)) != std::string::npos) {
        start += 6;
        const auto end = body.find('\n', start);
        const auto data = body.substr(start, end - start);
        if (data != "[DONE]")
            parsed.push_back(Json::parse(data));
        start = end;
    }
    return parsed;
}

void test_conversation_and_tools() {
    Fixture fixture;
    fixture.backend.output =
        "<think>private "
        "reasoning</"
        "think><tool_call>{\"tool\":\"read_file\",\"arguments\":{\"path\":\"second.txt\"}}</"
        "tool_call>";
    for (bool stream : {false, true}) {
        auto request = toolRequest(stream);
        auto response = fixture.post(request);
        check(response && response->status == 200, "tool HTTP response succeeds");
        const auto& structured = fixture.backend.request;
        check(structured.options().system_prompt() == "Remember PROJECT_RULES",
              "system prompt typed");
        check(structured.messages(0).content() == "FIRST_TURN", "text array typed");
        check(structured.messages(1).tool_calls(0).id() == "call_old", "tool call ID typed");
        check(structured.messages(1).tool_calls(0).arguments_json() == "{\"path\":\"first.txt\"}",
              "previous arguments typed");
        check(structured.messages(2).tool_result().result_json() == "\"FIRST_FILE_RESULT\"",
              "tool result typed");
        check(structured.options().tool_calling().tools(0).name() == "read_file",
              "tool definition typed");
        Json message;
        if (stream) {
            const auto chunks = events(response->body);
            check(chunks.front()["choices"][0]["delta"]["role"] == "assistant",
                  "SSE assistant role");
            message = chunks[1]["choices"][0]["delta"];
            check(message["tool_calls"][0]["index"] == 0, "SSE tool call index");
            check(chunks.back()["choices"][0]["finish_reason"] == "tool_calls",
                  "SSE tool terminal");
            check(response->body.find("data: [DONE]") != std::string::npos, "SSE DONE");
        } else {
            const auto body = Json::parse(response->body);
            message = body["choices"][0]["message"];
            check(body["choices"][0]["finish_reason"] == "tool_calls", "unary tool terminal");
            check(body["usage"]["prompt_tokens"] == 31, "tokenizer prompt usage");
            check(body["usage"]["prompt_tokens_details"]["cached_tokens"] == 13,
                  "unary cached prompt usage");
        }
        check(message["reasoning_content"] == "private reasoning", "reasoning separated");
        check(!message.contains("content") || message["content"].is_null() ||
                  message["content"] == "",
              "raw tool JSON not content");
        check(message["tool_calls"][0]["function"]["name"] == "read_file", "tool name parsed");
        check(Json::parse(
                  message["tool_calls"][0]["function"]["arguments"].get<std::string>())["path"] ==
                  "second.txt",
              "tool arguments parsed");
        check(message["tool_calls"][0]["id"].get<std::string>().starts_with("call_"),
              "tool call has ID");
    }
}

void test_text_options_and_errors() {
    Fixture fixture(false);
    auto request = base(true);
    request["max_completion_tokens"] = 123;
    request["stop"] = {"END", "STOP"};
    request["stream_options"] = {{"include_usage", true}};
    fixture.backend.output = "<think>secret</think>visible";
    fixture.backend.finish = "length";
    auto response = fixture.post(request);
    check(response && response->status == 200, "text stream succeeds");
    std::string content, reasoning;
    auto chunks = events(response->body);
    for (const auto& event : chunks) {
        if (event["choices"].empty())
            continue;
        auto delta = event["choices"][0]["delta"];
        content += delta.value("content", "");
        reasoning += delta.value("reasoning_content", "");
    }
    check(content == "visible" && reasoning == "secret", "split streaming reasoning delimiters");
    check(chunks[chunks.size() - 2]["choices"][0]["finish_reason"] == "length",
          "length terminal preserved");
    check(chunks.back()["usage"]["completion_tokens"] == 9, "stream usage uses tokenizer counts");
    check(chunks.back()["usage"]["prompt_tokens"] == 31 &&
              chunks.back()["usage"]["total_tokens"] == 40,
          "stream usage reports full logical prompt total");
    check(chunks.back()["usage"]["prompt_tokens_details"]["cached_tokens"] == 13,
          "stream usage reports exact cached count");
    check(fixture.backend.threads == 7 && fixture.backend.maxTokens == 123,
          "thread and token controls forwarded");
    check(fixture.backend.stops == std::vector<std::string>({"END", "STOP"}),
          "stop strings live during provider");
    fixture.backend.result = RAC_ERROR_INTERNAL;
    auto error = fixture.post(base(true));
    auto errorEvents = events(error->body);
    check(errorEvents.back().contains("error"), "stream generation failure is an error event");
    check(error->body.find("\"finish_reason\":\"stop\"") == std::string::npos,
          "failure does not claim success");
    check(fixture.post(base())->status == 500, "unary failure is HTTP 500");
}

void test_validation_and_choices() {
    Fixture fixture;
    for (const auto& invalid :
         std::vector<Json>{Json::array(),
                           {{"messages", "text"}},
                           {{"messages", Json::array()}},
                           {{"messages", {{{"role", "user"}, {"content", nullptr}}}}}}) {
        check(fixture.post(invalid)->status == 400, "malformed messages rejected");
    }
    auto request = base();
    request["messages"][0]["content"] = {{{"type", "image_url"}, {"image_url", "url"}}};
    check(fixture.post(request)->status == 400, "unsupported image fails explicitly");
    request = base();
    request["max_tokens"] = 1.5;
    check(fixture.post(request)->status == 400, "fractional token limit rejected");
    request = base();
    request["model"] = "missing";
    check(fixture.post(request)->status == 404, "unknown model rejected");
    request = toolRequest();
    request["tool_choice"] = "required";
    check(fixture.post(request)->status == 500, "required tool missing fails");
    request["tool_choice"] = "none";
    check(fixture.post(request)->status == 200, "tool_choice none allows final synthesis");
    check(fixture.backend.request.messages(2).tool_result().result_json() ==
              "\"FIRST_FILE_RESULT\"",
          "none preserves typed tool results");
    fixture.backend.output = "<tool_call>{\"tool\":\"unknown\",\"arguments\":{}}</tool_call>";
    check(fixture.post(toolRequest())->status == 500, "unknown generated tool is rejected");
    fixture.backend.output =
        "<tool_call>{\"tool\":\"read_file\",\"arguments\":{\"path\":\"a\"}}</tool_call>"
        "<tool_call>{\"tool\":\"read_file\",\"arguments\":{\"path\":\"b\"}}</tool_call>";
    auto parallel = fixture.post(toolRequest());
    check(parallel->status == 200, "multiple generated calls accepted");
    check(Json::parse(parallel->body)["choices"][0]["message"]["tool_calls"].size() == 2,
          "all parallel calls retained");
    request = toolRequest();
    request["parallel_tool_calls"] = false;
    check(fixture.post(request)->status == 500, "disabled parallel tool calls rejected");
    fixture.backend.output = "{\"tool\":\"read_file\",\"arguments\":{\"path\":\"a\"}}";
    check(Json::parse(fixture.post(toolRequest())->body)["choices"][0]["finish_reason"] ==
              "tool_calls",
          "bare tool JSON normalized through SDK parser");
    fixture.backend.output = "<tool_call>{\"tool\":\"read_file\"";
    check(fixture.post(toolRequest())->status == 500, "incomplete tool call fails explicitly");
}

void test_structured_history_and_fallback() {
    Fixture fixture;
    auto exact = base();
    check(fixture.post(exact)->status == 200, "exact history request succeeds");
    check(fixture.backend.request.messages_size() == 1 &&
              fixture.backend.request.messages(0).content() == "Say hello",
          "exact history reaches engine");

    auto partial = exact;
    partial["messages"].push_back({{"role", "assistant"}, {"content", "hello"}});
    partial["messages"].push_back({{"role", "user"}, {"content", "again"}});
    check(fixture.post(partial)->status == 200, "partial-prefix history succeeds");
    check(fixture.backend.request.messages_size() == 3 &&
              fixture.backend.request.messages(2).content() == "again",
          "partial-prefix history reaches engine intact");

    auto divergent = partial;
    divergent["messages"][0]["content"] = "Different root";
    check(fixture.post(divergent)->status == 200, "divergent history succeeds");
    check(fixture.backend.request.messages(0).content() == "Different root",
          "divergent history is not flattened or reused");

    Fixture fallback(false);
    check(fallback.post(toolRequest())->status == 200, "legacy engine fallback succeeds");
    check(fallback.backend.prompt.find("FIRST_FILE_RESULT") != std::string::npos,
          "legacy fallback receives complete flattened history");
    check(fallback.backend.structuredCalls == 0, "legacy fallback avoids structured op");
}

void test_serialization_and_timeout() {
    Fixture fixture;
    fixture.backend.delayMs = 100;
    auto first = std::async(std::launch::async, [&] { return fixture.post(base(true)); });
    auto second = std::async(std::launch::async, [&] { return fixture.post(base()); });
    check(first.get()->status == 200 && second.get()->status == 200,
          "parallel HTTP clients complete");
    check(fixture.backend.peak == 1, "backend calls serialized through SSE lifetime");
    check(fixture.handler.getActiveRequests() == 0, "active count drains after streaming");
    check(fixture.handler.getTotalTokensGenerated() == 18, "statistics count real stream tokens");
    fixture.backend.delayMs = 3000;
    const auto start = std::chrono::steady_clock::now();
    check(fixture.post(base())->status == 504, "prefill timeout returns HTTP 504");
    check(fixture.backend.cancelledCalls > 0, "timeout cancels backend before first token");
    check(std::chrono::steady_clock::now() - start < 2500ms, "timeout is bounded");
    fixture.handler.requestStop();
    check(fixture.post(base())->status == 503, "shutdown rejects new inference");
}

void test_server_context_query_requires_running_model() {
    check(rac_server_get_context_length(nullptr) == RAC_ERROR_INVALID_ARGUMENT,
          "context query rejects null output");
    int32_t contextLength = -1;
    check(rac_server_get_context_length(&contextLength) == RAC_ERROR_SERVER_NOT_RUNNING,
          "context query rejects stopped server");
    check(contextLength == 0, "failed context query clears output");
}
}  // namespace
int main() {
    try {
        test_conversation_and_tools();
        test_text_options_and_errors();
        test_validation_and_choices();
        test_structured_history_and_fallback();
        test_serialization_and_timeout();
        test_server_context_query_requires_running_model();
        std::printf("OpenAI server: %d assertions passed\n", assertions);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL after %d assertions: %s\n", assertions, error.what());
        return 1;
    }
}
