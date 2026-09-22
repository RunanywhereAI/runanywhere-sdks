/** Hermetic HTTP contract tests. A deterministic backend exercises real SDK
 * dispatch, tool parsing, HTTP serialization, cancellation and concurrent clients. */
#include "openai_handler.h"
#include "openai_translation.h"

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
    std::vector<std::string> stops;
    std::atomic<int> running{0}, peak{0}, cancelledCalls{0};
    std::atomic<bool> cancelled{false};
    int delayMs = 0;
    rac_result_t result = RAC_SUCCESS;
};
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
    ops.get_stream_token_counts = [](void*, rac_llm_token_counts_t* out) {
        out->prompt_tokens = 17;
        out->completion_tokens = 9;
        return RAC_SUCCESS;
    };
    ops.generate_stream = [](void* state, const char* prompt, const rac_llm_options_t* options,
                             rac_llm_stream_callback_fn callback, void* user) {
        auto& backend = *static_cast<Backend*>(state);
        const int running = ++backend.running;
        if (running > backend.peak)
            backend.peak = running;
        backend.cancelled = false;
        backend.prompt = prompt;
        backend.threads = options->n_threads;
        backend.maxTokens = options->max_tokens;
        backend.stops.clear();
        for (size_t i = 0; i < options->num_stop_sequences; ++i)
            backend.stops.emplace_back(options->stop_sequences[i]);
        for (int elapsed = 0; elapsed < backend.delayMs && !backend.cancelled; elapsed += 10)
            std::this_thread::sleep_for(10ms);
        if (backend.cancelled) {
            --backend.running;
            return RAC_ERROR_CANCELLED;
        }
        // One byte at a time deliberately splits every reasoning/tool delimiter.
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
    };
    return ops;
}();

struct Fixture {
    Backend backend;
    rac_llm_service_t service{&operations, &backend, "fixture"};
    rac::server::OpenAIHandler handler{&service, "fixture", 7, 1};
    httplib::Server server;
    std::thread thread;
    int port;
    Fixture() {
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
        check(fixture.backend.prompt.find("PROJECT_RULES") != std::string::npos,
              "system prompt preserved");
        check(fixture.backend.prompt.find("FIRST_TURN") != std::string::npos,
              "text array preserved");
        check(fixture.backend.prompt.find("call_old") != std::string::npos,
              "tool call ID preserved");
        check(fixture.backend.prompt.find("first.txt") != std::string::npos,
              "previous arguments preserved");
        check(fixture.backend.prompt.find("FIRST_FILE_RESULT") != std::string::npos,
              "tool result preserved");
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
            check(body["usage"]["prompt_tokens"] == 17, "tokenizer prompt usage");
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
    Fixture fixture;
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
    check(fixture.backend.prompt.find("FIRST_FILE_RESULT") != std::string::npos,
          "none preserves tool results");
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
}  // namespace
int main() {
    try {
        test_conversation_and_tools();
        test_text_options_and_errors();
        test_validation_and_choices();
        test_serialization_and_timeout();
        std::printf("OpenAI server: %d assertions passed\n", assertions);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL after %d assertions: %s\n", assertions, error.what());
        return 1;
    }
}
