/**
 * @file test_tool_calling_run_loop.cpp
 * @brief Tests for rac_tool_calling_run_loop_proto.
 *
 * Mirrors test_tool_calling_session_proto.cpp's setup (mock LLM plugin,
 * fixture-driven responses) and exercises the synchronous single-call API:
 *  1. No tool call -> immediate completion with text-only result.
 *  2. One tool call -> executor invoked once, follow-up generates final text.
 *  3. Tool-call cap enforced.
 *  4. Validation failure short-circuits with a failed ToolResult.
 */

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#include "tool_calling.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                           \
    do {                                                                             \
        ++test_count;                                                                \
        if (!(cond)) {                                                               \
            ++fail_count;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        } else {                                                                     \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        }                                                                            \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

// ---------------------------------------------------------------------------
// Mock LLM plugin (identical pattern to the session proto tests).
// ---------------------------------------------------------------------------

struct MockLlm {
    std::string model_path;
};

std::mutex g_responses_mutex;
std::vector<std::string> g_responses;
int g_generate_calls = 0;

struct GenerationCapture {
    std::string prompt;
    int32_t max_tokens = 0;
    float temperature = 0.0f;
    float top_p = 0.0f;
    bool disable_thinking = false;
    // rac_llm_options_t.grammar as the backend saw it (RUN-80). Empty unless the
    // loaded model's framework advertises grammar support (QHexRT).
    std::string grammar;
    std::vector<std::string> stop_sequences;
    // Prior conversation turns the run loop threaded onto rac_llm_options_t
    // (ToolCallingSessionCreateRequest.history, field 19). Captured verbatim so
    // tests can assert history flows through every generate in the loop and that
    // the odd-length trailing-turn drop happened before generation.
    std::vector<std::string> history;
    int32_t n_history = 0;
};

std::vector<GenerationCapture> g_generation_captures;

char* dup_cstr(const char* value) {
    const size_t len = std::strlen(value);
    char* out = static_cast<char*>(std::malloc(len + 1));
    if (!out)
        return nullptr;
    std::memcpy(out, value, len + 1);
    return out;
}

rac_result_t mock_create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = new MockLlm();
    impl->model_path = model_id;
    *out_impl = impl;
    return RAC_SUCCESS;
}

rac_result_t mock_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t mock_generate(void*, const char* prompt, const rac_llm_options_t* options,
                           rac_llm_result_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
    std::string response;
    {
        std::lock_guard<std::mutex> lg(g_responses_mutex);
        g_generate_calls++;
        GenerationCapture capture;
        capture.prompt = prompt ? prompt : "";
        if (options) {
            capture.max_tokens = options->max_tokens;
            capture.temperature = options->temperature;
            capture.top_p = options->top_p;
            capture.disable_thinking = options->disable_thinking != RAC_FALSE;
            capture.grammar = options->grammar ? options->grammar : "";
            for (size_t i = 0; i < options->num_stop_sequences; ++i) {
                const char* stop = options->stop_sequences ? options->stop_sequences[i] : nullptr;
                if (stop && stop[0] != '\0') {
                    capture.stop_sequences.emplace_back(stop);
                }
            }
            // rac_llm_options_t.history / n_history (rac_llm_types.h): the run
            // loop flattens generation.history into this positional C-ABI slot.
            capture.n_history = options->n_history;
            if (options->history != nullptr && options->n_history > 0) {
                for (int32_t i = 0; i < options->n_history; ++i) {
                    const char* turn = options->history[i];
                    capture.history.emplace_back(turn ? turn : "");
                }
            }
        }
        if (g_responses.empty()) {
            response = "empty-response";
        } else {
            response = g_responses.front();
            g_responses.erase(g_responses.begin());
        }
        // Model the backend contract: a matched caller stop is not returned in
        // raw.text. The tool parser must still accept the complete payload.
        for (const auto& stop : capture.stop_sequences) {
            const size_t pos = response.find(stop);
            if (pos != std::string::npos) {
                response.resize(pos);
                break;
            }
        }
        g_generation_captures.push_back(std::move(capture));
    }
    out_result->text = dup_cstr(response.c_str());
    if (!out_result->text)
        return RAC_ERROR_OUT_OF_MEMORY;
    out_result->prompt_tokens = 3;
    out_result->completion_tokens = 5;
    out_result->total_tokens = 8;
    out_result->time_to_first_token_ms = 1;
    out_result->total_time_ms = 10;
    out_result->tokens_per_second = 50.0f;
    return RAC_SUCCESS;
}

rac_result_t mock_cancel(void*) {
    return RAC_SUCCESS;
}
rac_result_t mock_cleanup(void*) {
    return RAC_SUCCESS;
}
void mock_destroy(void* impl) {
    delete static_cast<MockLlm*>(impl);
}

rac_llm_service_ops_t g_mock_ops = [] {
    rac_llm_service_ops_t ops{};
    ops.create = mock_create;
    ops.initialize = mock_initialize;
    ops.generate = mock_generate;
    ops.cancel = mock_cancel;
    ops.cleanup = mock_cleanup;
    ops.destroy = mock_destroy;
    return ops;
}();

const uint32_t g_formats[] = {static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF)};

rac_engine_vtable_t g_mock_vtable = [] {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = "llamacpp";
    v.metadata.display_name = "mock llama.cpp";
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 100;
    v.metadata.formats = g_formats;
    v.metadata.formats_count = 1;
    v.llm_ops = &g_mock_ops;
    return v;
}();

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    if (out->empty())
        return true;
    return message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

void set_responses(std::vector<std::string> responses) {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    g_responses = std::move(responses);
    g_generate_calls = 0;
    g_generation_captures.clear();
}

int generate_calls() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_generate_calls;
}

std::vector<GenerationCapture> generation_captures() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_generation_captures;
}

runanywhere::v1::ModelInfo build_llm_model(runanywhere::v1::InferenceFramework framework =
                                               runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP) {
    runanywhere::v1::ModelInfo model;
    model.set_id("toolloop.llm");
    model.set_name("ToolLoop LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    // Framework drives the lifecycle's supports_grammar gate. A QHexRT framework
    // with no registered qhexrt plugin still loads via the primitive fallback to
    // the mock GENERATE_TEXT vtable, so tests can exercise the grammar path with
    // the mock ops while loaded->framework reports QHEXRT.
    model.set_framework(framework);
    model.set_local_path("/tmp/toolloop-test.gguf");
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

rac_model_registry_handle_t g_registry = nullptr;

void cleanup_environment() {
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();
    (void)rac_plugin_unregister("llamacpp");
    set_responses({});
}

bool load_mock_llm(runanywhere::v1::InferenceFramework framework =
                       runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP) {
    cleanup_environment();
    if (rac_plugin_register(&g_mock_vtable) != RAC_SUCCESS)
        return false;

    if (!g_registry && (rac_model_registry_create(&g_registry) != RAC_SUCCESS || !g_registry)) {
        return false;
    }

    std::vector<uint8_t> model_bytes;
    auto model = build_llm_model(framework);
    if (!serialize(model, &model_bytes) ||
        rac_model_registry_register_proto(g_registry, model_bytes.data(), model_bytes.size()) !=
            RAC_SUCCESS) {
        return false;
    }

    runanywhere::v1::ModelLoadRequest load;
    load.set_model_id("toolloop.llm");
    std::vector<uint8_t> load_bytes;
    if (!serialize(load, &load_bytes))
        return false;

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_lifecycle_load_proto(g_registry, load_bytes.data(), load_bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    bool ok = rc == RAC_SUCCESS && out.data != nullptr && out.size > 0 &&
              result.ParseFromArray(out.data, static_cast<int>(out.size)) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

// ---------------------------------------------------------------------------
// Tool definition + helpers.
// ---------------------------------------------------------------------------

runanywhere::v1::ToolDefinition make_weather_tool() {
    runanywhere::v1::ToolDefinition tool;
    tool.set_name("get_weather");
    tool.set_description("Get weather for a city");
    auto* param = tool.add_parameters();
    param->set_name("location");
    param->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
    param->set_description("City name");
    param->set_required(true);
    return tool;
}

runanywhere::v1::ToolDefinition make_calculate_tool() {
    runanywhere::v1::ToolDefinition tool;
    tool.set_name("calculate");
    tool.set_description("Evaluates a math expression");
    auto* param = tool.add_parameters();
    param->set_name("expression");
    param->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
    param->set_description("Expression such as 45 * 12");
    param->set_required(true);
    return tool;
}

runanywhere::v1::ToolDefinition make_search_web_tool() {
    runanywhere::v1::ToolDefinition tool;
    tool.set_name("search_web");
    tool.set_description("Searches the web for current information and source links");
    auto* param = tool.add_parameters();
    param->set_name("query");
    param->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
    param->set_description("A concise web search query");
    param->set_required(true);
    return tool;
}

runanywhere::v1::ToolCallingSessionCreateRequest make_request(const std::string& prompt,
                                                              uint32_t max_tool_calls = 0) {
    runanywhere::v1::ToolCallingSessionCreateRequest request;
    request.set_prompt(prompt);
    request.set_max_tokens(64);
    request.set_temperature(0.5f);
    *request.add_tools() = make_weather_tool();
    request.set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    if (max_tool_calls > 0)
        request.set_max_tool_calls(max_tool_calls);
    return request;
}

// ---------------------------------------------------------------------------
// Executor harness — captures every tool call the loop emits and returns
// canned tool results in FIFO order.
// ---------------------------------------------------------------------------

struct ExecutorState {
    std::mutex mu;
    std::vector<runanywhere::v1::ToolCall> received_calls;
    std::vector<std::string> result_jsons;  // FIFO canned results
    int invocation_count = 0;
    bool simulate_failure = false;
};

rac_result_t executor_callback(const uint8_t* in_bytes, size_t in_size,
                               rac_proto_buffer_t* out_result, void* user_data) {
    auto* state = static_cast<ExecutorState*>(user_data);
    runanywhere::v1::ToolCall received;
    if (in_size > 0)
        (void)received.ParseFromArray(in_bytes, static_cast<int>(in_size));

    {
        std::lock_guard<std::mutex> lg(state->mu);
        state->invocation_count++;
        state->received_calls.push_back(received);
    }

    if (state->simulate_failure) {
        rac_proto_buffer_init(out_result);
        rac_proto_buffer_set_error(out_result, RAC_ERROR_INTERNAL, "executor failed");
        return RAC_ERROR_INTERNAL;
    }

    runanywhere::v1::ToolResult tr;
    tr.set_tool_call_id(received.id());
    tr.set_name(received.name());
    tr.set_success(true);
    {
        std::lock_guard<std::mutex> lg(state->mu);
        if (!state->result_jsons.empty()) {
            tr.set_result_json(state->result_jsons.front());
            state->result_jsons.erase(state->result_jsons.begin());
        } else {
            tr.set_result_json("{\"ok\":true}");
        }
    }

    std::vector<uint8_t> bytes;
    serialize(tr, &bytes);
    rac_proto_buffer_init(out_result);
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
}

rac_result_t empty_executor_callback(const uint8_t*, size_t, rac_proto_buffer_t* out_result,
                                     void*) {
    rac_proto_buffer_init(out_result);
    return RAC_SUCCESS;
}

rac_result_t malformed_executor_callback(const uint8_t*, size_t, rac_proto_buffer_t* out_result,
                                         void*) {
    constexpr uint8_t malformed[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_init(out_result);
    return rac_proto_buffer_copy(malformed, sizeof(malformed), out_result);
}

rac_result_t status_error_executor_callback(const uint8_t*, size_t,
                                            rac_proto_buffer_t* out_result, void*) {
    rac_proto_buffer_init(out_result);
    (void)rac_proto_buffer_set_error(out_result, RAC_ERROR_INTERNAL,
                                     "executor buffer status failure");
    return RAC_SUCCESS;
}

rac_result_t mismatched_executor_callback(const uint8_t* in_bytes, size_t in_size,
                                          rac_proto_buffer_t* out_result, void*) {
    runanywhere::v1::ToolCall received;
    (void)received.ParseFromArray(in_bytes, static_cast<int>(in_size));
    runanywhere::v1::ToolResult result;
    result.set_tool_call_id(received.id() + "_wrong");
    result.set_name(received.name());
    result.set_success(true);
    result.set_result_json("{}");
    std::vector<uint8_t> bytes;
    serialize(result, &bytes);
    rac_proto_buffer_init(out_result);
    return rac_proto_buffer_copy(bytes.data(), bytes.size(), out_result);
}

void ignore_published_handle(uint64_t, void*) {}

rac_result_t run_loop(const uint8_t* request_bytes, size_t request_size,
                      rac_tool_execute_callback_fn on_execute, void* user_data,
                      rac_proto_buffer_t* out_result) {
    return rac_tool_calling_run_loop_proto(request_bytes, request_size, on_execute, user_data,
                                           ignore_published_handle, nullptr, out_result);
}

// ---------------------------------------------------------------------------
// Tests.
// ---------------------------------------------------------------------------

int test_no_tool_call_completes_immediately() {
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    set_responses({"Sure, here's the answer."});

    auto request = make_request("hi there");
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "serialize request");

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS");
    const bool has_bytes = out.data != nullptr && out.size > 0;
    CHECK(has_bytes, "out has bytes");

    runanywhere::v1::ToolCallingResult result;
    if (out.data != nullptr && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete() == true, "is_complete true");
    CHECK(result.tool_calls_size() == 0, "no tool_calls");
    CHECK(result.tool_results_size() == 0, "no tool_results");
    CHECK(result.iterations_used() == 1, "single iteration");
    CHECK(result.text() == "Sure, here's the answer.", "text echoed back");
    CHECK(exec.invocation_count == 0, "executor not invoked");
    CHECK(generate_calls() == 1, "generate called once");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_one_tool_call_then_final_text() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny, 25C.",
    });

    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    {
        std::lock_guard<std::mutex> lg(exec.mu);
        exec.result_jsons.emplace_back(R"({"temp":25,"condition":"sunny"})");
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete() == true, "is_complete true");
    CHECK(result.tool_calls_size() == 1, "one tool_call recorded");
    CHECK(result.tool_results_size() == 1, "one tool_result recorded");
    CHECK(result.iterations_used() == 2, "iterations_used == 2");
    CHECK(result.text().find("sunny") != std::string::npos, "final text contains sunny");
    CHECK(exec.invocation_count == 1, "executor invoked once");
    if (!exec.received_calls.empty()) {
        CHECK(exec.received_calls[0].name() == "get_weather", "executor saw correct name");
        CHECK(exec.received_calls[0].arguments_json().find("Tokyo") != std::string::npos,
              "executor saw Tokyo arg");
    }
    CHECK(generate_calls() == 2, "generate called twice");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_forced_tool_name_only_is_narrowed_and_independently_budgeted() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<think>route only; do not expose this</think><tool_call>{"tool":"calculate","arguments":{"expression":"45 * 12"}}</tool_call>ignored trailing text)",
        "The result is 540.",
    });

    auto request = make_request("Use calculate to multiply 45 by 12.");
    request.clear_tools();
    *request.add_tools() = make_calculate_tool();
    request.set_max_tokens(96);
    request.set_temperature(0.7f);
    request.set_top_p(0.9f);
    request.set_disable_thinking(false);
    request.set_forced_tool_name("calculate");
    auto* unrelated = request.add_tools();
    unrelated->set_name("unrelated_tool");
    unrelated->set_description("Must not be advertised");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    {
        std::lock_guard<std::mutex> lg(exec.mu);
        exec.result_jsons.emplace_back(R"({"result":"540"})");
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "forced-name-only run_loop returns RAC_SUCCESS");
    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.tool_calls_size() == 1, "completed decision records one tool call");
    CHECK(result.tool_results_size() == 1, "completed decision records one tool result");
    CHECK(result.text().find("540") != std::string::npos,
          "follow-up produces a visible final answer");

    const auto captures = generation_captures();
    CHECK(captures.size() == 2, "forced name generated decision plus synthesis");
    if (captures.size() == 2) {
        CHECK(captures[0].max_tokens == 192, "forced decision safety-capped at 192 tokens");
        CHECK(captures[0].temperature == 0.0f, "forced decision uses greedy temperature");
        CHECK(captures[0].top_p == 1.0f, "forced decision disables nucleus truncation");
        CHECK(captures[0].disable_thinking, "forced decision disables thinking");
        CHECK(captures[0].stop_sequences == std::vector<std::string>{"</tool_call>"},
              "forced decision stops at completed default tool call");
        CHECK(captures[0].prompt.rfind("/no_think\n", 0) == 0,
              "forced decision carries no-think directive");
        CHECK(captures[0].prompt.find("calculate") != std::string::npos,
              "forced decision advertises selected tool");
        CHECK(captures[0].prompt.find("expression") != std::string::npos,
              "forced decision carries exact required argument");
        CHECK(captures[0].prompt.find("get_weather") == std::string::npos,
              "forced decision omits unrelated generic weather example");
        CHECK(captures[0].prompt.find("unrelated_tool") == std::string::npos,
              "forced decision omits unrelated schema");
        CHECK(captures[0].prompt.find("## EXAMPLES") == std::string::npos,
              "forced decision omits generic examples");
        CHECK(captures[0].prompt.find("Math/calculation question") == std::string::npos,
              "forced decision omits unrelated generic rules");
        CHECK(captures[0].prompt.size() < 800, "forced decision prompt stays compact");

        CHECK(captures[1].max_tokens == 96, "synthesis retains final-answer token budget");
        CHECK(captures[1].temperature == 0.7f, "synthesis retains caller sampling temperature");
        CHECK(captures[1].top_p == 0.9f, "synthesis retains caller top-p");
        CHECK(!captures[1].disable_thinking, "synthesis retains caller thinking policy");
        CHECK(captures[1].stop_sequences.empty(), "synthesis does not inherit decision stop");
        CHECK(captures[1].prompt.rfind("/no_think\n", 0) != 0,
              "synthesis does not inherit decision-only directive");
    }
    CHECK(exec.invocation_count == 1, "forced executor invoked exactly once");
    if (!exec.received_calls.empty()) {
        CHECK(exec.received_calls[0].name() == "calculate", "executor receives calculate call");
        CHECK(exec.received_calls[0].arguments_json().find("45 * 12") != std::string::npos,
              "executor receives complete expression argument");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_none_vetoes_forced_tool_name() {
    if (!load_mock_llm())
        return 1;
    set_responses({"No tool call is needed."});

    auto request = make_request("Answer directly without tools.");
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    request.set_forced_tool_name("get_weather");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "NONE plus forced name returns a normal text result");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete(), "NONE plus forced name completes");
    CHECK(result.error_code() == 0, "NONE plus forced name has no policy error for plain text");
    CHECK(exec.invocation_count == 0, "NONE veto prevents executor invocation");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "NONE plus forced name generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].prompt == request.prompt(), "NONE veto suppresses every tool schema");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_none_blocks_hallucinated_call_when_validation_disabled() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    auto request = make_request("Answer directly without tools.");
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    request.set_validate_calls(false);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "NONE policy failure is returned in ToolCallingResult");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(!result.is_complete(), "hallucinated NONE call is not successful");
    CHECK(result.error_code() == RAC_ERROR_VALIDATION_FAILED,
          "hallucinated NONE call surfaces validation failure");
    CHECK(result.error_message() == "Tool calls are disabled by tool_choice=NONE",
          "hallucinated NONE call surfaces deterministic policy message");
    CHECK(exec.invocation_count == 0, "NONE blocks executor when validate_calls=false");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_forced_target_blocks_wrong_call_when_validation_disabled() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    auto request = make_request("Use calculate only.");
    *request.add_tools() = make_calculate_tool();
    request.set_forced_tool_name("calculate");
    request.set_validate_calls(false);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "forced-target policy failure is returned in ToolCallingResult");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(!result.is_complete(), "wrong forced-target call is not successful");
    CHECK(result.error_code() == RAC_ERROR_VALIDATION_FAILED,
          "wrong forced-target call surfaces validation failure");
    CHECK(result.error_message() == "Tool call must use tool_choice=SPECIFIC target: calculate",
          "wrong forced-target call surfaces deterministic policy message");
    CHECK(exec.invocation_count == 0,
          "forced target blocks wrong executor when validate_calls=false");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_specific_target_must_be_nonempty_and_present() {
    if (!load_mock_llm())
        return 1;

    const auto run_invalid_request = [](runanywhere::v1::ToolCallingSessionCreateRequest request,
                                        const std::string& expected_message, const char* label) {
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc =
            run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        CHECK(rc == RAC_ERROR_INVALID_ARGUMENT, label);

        CHECK(out.status == RAC_ERROR_INVALID_ARGUMENT,
              "invalid SPECIFIC request buffer carries INVALID_ARGUMENT");
        CHECK(out.error_message && expected_message == out.error_message,
              "invalid SPECIFIC request buffer carries deterministic message");
        CHECK(exec.invocation_count == 0, "invalid SPECIFIC request never invokes executor");
        rac_proto_buffer_free(&out);
    };

    auto empty_target = make_request("Use a specific tool.");
    empty_target.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    run_invalid_request(empty_target, "tool_choice=SPECIFIC requires a non-empty forced_tool_name",
                        "SPECIFIC without target is rejected");

    auto missing_target = make_request("Use the missing tool.");
    missing_target.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    missing_target.set_forced_tool_name("missing_tool");
    run_invalid_request(missing_target,
                        "tool_choice=SPECIFIC target is not present in request.tools: missing_tool",
                        "SPECIFIC target absent from tools is rejected");
    CHECK(generate_calls() == 0, "invalid SPECIFIC requests fail before generation");

    cleanup_environment();
    return 0;
}

int test_specific_and_required_reject_initial_no_call() {
    if (!load_mock_llm())
        return 1;

    const auto run_required_choice = [](runanywhere::v1::ToolChoiceMode mode,
                                        const std::string& expected_message, const char* label) {
        set_responses({"I decided not to call a tool."});
        auto request = make_request("A tool call is mandatory.", /*max_tool_calls=*/1);
        request.set_tool_choice(mode);
        if (mode == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC) {
            request.set_forced_tool_name("get_weather");
        }
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc =
            run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        CHECK(rc == RAC_SUCCESS, label);

        runanywhere::v1::ToolCallingResult result;
        if (out.data && out.size > 0) {
            (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
        }
        CHECK(!result.is_complete(), "required no-call response is not successful");
        CHECK(result.error_code() == RAC_ERROR_VALIDATION_FAILED,
              "required no-call response carries validation failure");
        CHECK(result.error_message() == expected_message,
              "required no-call response carries deterministic policy message");
        CHECK(exec.invocation_count == 0, "required no-call response never invokes executor");
        rac_proto_buffer_free(&out);
    };

    run_required_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC,
                        "tool_choice=SPECIFIC requires a tool call",
                        "SPECIFIC no-call returns a result-level policy failure");
    run_required_choice(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED,
                        "tool_choice=REQUIRED requires a tool call",
                        "REQUIRED no-call returns a result-level policy failure");

    cleanup_environment();
    return 0;
}

int test_search_web_synthesis_is_current_compact_and_attributed() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"search_web","arguments":{"query":"current Google Play target API requirement for new mobile apps"}}</tool_call>)",
        "For new mobile apps and updates, the currently effective requirement is API 35.",
    });

    auto request = make_request(
        "Use search_web to find the current Google Play target API requirement for a new mobile "
        "app. Include a source URL.");
    request.clear_tools();
    *request.add_tools() = make_search_web_tool();
    request.set_max_tokens(96);
    request.set_disable_thinking(true);
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    request.set_forced_tool_name("search_web");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    {
        std::lock_guard<std::mutex> lg(exec.mu);
        exec.result_jsons.emplace_back(R"({
          "query":"current Google Play target API requirement for new mobile apps",
          "source_url":"https://developer.android.com/google/play/requirements/target-sdk",
          "summary":"From August 31, 2024, existing mobile apps need API 34 for availability.",
          "related_results":[
            {"title":"2025 requirement","text":"From August 31, 2025, new mobile apps and updates must target API 35.","url":"https://developer.android.com/google/play/requirements/target-sdk#mobile-2025"},
            {"title":"2026 announcement","text":"From August 31, 2026, new mobile apps and updates must target API 36.","url":"https://developer.android.com/google/play/requirements/target-sdk#mobile-2026"},
            {"title":"discard me","text":"Must not crowd synthesis.","url":"https://example.com/discard"}
          ]
        })");
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "search_web run_loop returns RAC_SUCCESS");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.text().find("API 35") != std::string::npos,
          "search synthesis keeps the currently effective answer");
    CHECK(result.text().find("API 34") == std::string::npos,
          "search synthesis does not surface the old-scope requirement");
    CHECK(result.text().find(
              "Source: https://developer.android.com/google/play/requirements/target-sdk") !=
              std::string::npos,
          "native result boundary appends the primary source URL verbatim");
    CHECK(generate_calls() == 2, "search request keeps decision and synthesis separate");

    const auto captures = generation_captures();
    CHECK(captures.size() == 2, "search request captured decision plus synthesis");
    if (captures.size() == 2) {
        CHECK(captures[0].max_tokens == 192,
              "search decision keeps independent 192-token safety ceiling");
        CHECK(captures[1].max_tokens == 96,
              "search synthesis keeps independent concise answer budget");
        CHECK(captures[1].disable_thinking, "search synthesis disables thinking");
        CHECK(captures[1].prompt.find("Current UTC date:") != std::string::npos,
              "search synthesis receives the current UTC date");
        CHECK(captures[1].prompt.find("policy effective on the current date") != std::string::npos,
              "search synthesis resolves dated evidence against the current policy");
        CHECK(captures[1].prompt.find("source_url verbatim") != std::string::npos,
              "search synthesis requires verbatim source attribution");
        CHECK(captures[1].prompt.find("API 34") != std::string::npos &&
                  captures[1].prompt.find("API 35") != std::string::npos &&
                  captures[1].prompt.find("API 36") != std::string::npos,
              "search synthesis retains conflicting dated evidence needed for resolution");
        CHECK(captures[1].prompt.find("discard me") == std::string::npos,
              "search synthesis drops excess related evidence");
        CHECK(captures[1].prompt.size() < 2600,
              "search synthesis prompt stays bounded for a 1K model context");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_tool_name_mentions_do_not_force_execution() {
    if (!load_mock_llm())
        return 1;
    set_responses({"I will explain calculate without calling it."});

    auto request = make_request("Do not call calculate. Explain what calculate does.");
    *request.add_tools() = make_calculate_tool();
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "negated tool-name mention returns success");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.tool_calls_size() == 0, "negated mention records no tool call");
    CHECK(result.tool_results_size() == 0, "negated mention records no tool result");
    CHECK(exec.invocation_count == 0, "negated mention never invokes executor");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "negated mention uses one AUTO generation");
    if (captures.size() == 1) {
        CHECK(captures[0].max_tokens == 64, "AUTO generation keeps caller token budget");
        CHECK(captures[0].temperature == 0.5f, "AUTO generation keeps caller temperature");
        CHECK(captures[0].prompt.find("get_weather") != std::string::npos,
              "AUTO prompt keeps all registered tools");
        CHECK(captures[0].prompt.find("calculate") != std::string::npos,
              "AUTO prompt keeps mentioned tool without forcing it");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_max_tool_calls_capped() {
    if (!load_mock_llm())
        return 1;
    // max_tool_calls limits host side effects, not generation turns. Commons
    // executes two calls, removes tools from the final follow-up prompt, and
    // still performs the synthesis turn.
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"B"}}</tool_call>)",
        "Final answer after two tool calls.",
    });

    auto request = make_request("weather everywhere", /*max_tool_calls=*/2);
    request.set_keep_tools_available(true);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    exec.result_jsons = {R"({"city":"A"})", R"({"city":"B"})"};
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.iterations_used() == 3,
          "two tool calls plus final synthesis use three generations");
    CHECK(result.tool_calls_size() == 2, "two tool_calls recorded");
    CHECK(result.tool_results_size() == 2, "two tool_results recorded");
    CHECK(exec.invocation_count == 2, "executor invoked twice");
    CHECK(generate_calls() == 3, "generate runs final synthesis after second tool");
    CHECK(result.text() == "Final answer after two tool calls.",
          "final synthesis text is preserved");
    const auto prompts = generation_captures();
    CHECK(prompts.size() == 3, "three prompts captured");
    if (prompts.size() == 3) {
        CHECK(prompts[2].prompt.find("\"city\":\"A\"") != std::string::npos,
              "final prompt includes first tool result");
        CHECK(prompts[2].prompt.find("\"city\":\"B\"") != std::string::npos,
              "final prompt includes second tool result");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_max_tool_calls_blocks_extra_side_effect() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"B"}}</tool_call>)",
    });

    auto request = make_request("weather twice", /*max_tool_calls=*/1);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "limit violation is returned in the result envelope");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.error_code() == RAC_ERROR_VALIDATION_FAILED,
          "extra tool request is rejected at the policy boundary");
    CHECK(result.tool_calls_size() == 1, "only the authorized tool call is recorded");
    CHECK(exec.invocation_count == 1, "extra tool request never reaches the executor");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_auto_execute_false_returns_call_without_side_effect() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
    });
    auto request = make_request("weather");
    request.set_auto_execute(false);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);
    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "manual execution request succeeds");
    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(!result.is_complete(), "manual execution result remains incomplete");
    CHECK(result.tool_calls_size() == 1, "manual execution returns parsed tool call");
    CHECK(result.tool_results_size() == 0, "manual execution returns no tool result");
    CHECK(exec.invocation_count == 0, "manual execution never invokes host executor");
    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_validation_failure_short_circuits() {
    if (!load_mock_llm())
        return 1;
    // Tool name that is NOT in the request's tool list should fail validation
    // before the executor is invoked.
    set_responses({
        R"(<tool_call>{"tool":"unknown_tool","arguments":{}}</tool_call>)",
    });

    auto request = make_request("call missing tool");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS (failed result inside)");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.tool_calls_size() == 1, "one tool_call recorded");
    CHECK(result.tool_results_size() == 1, "one failed tool_result recorded");
    CHECK(exec.invocation_count == 0, "executor NOT invoked");
    if (result.tool_results_size() > 0) {
        CHECK(result.tool_results(0).success() == false, "tool_result.success == false");
        CHECK(!result.tool_results(0).error().empty(), "tool_result has error message");
    }
    CHECK(result.error_code() == RAC_ERROR_VALIDATION_FAILED, "error_code = VALIDATION_FAILED");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_executor_result_contract_is_fail_closed() {
    if (!load_mock_llm())
        return 1;

    struct Case {
        rac_tool_execute_callback_fn callback;
        int32_t expected_code;
        const char* label;
    };
    const Case cases[] = {
        {empty_executor_callback, RAC_ERROR_DECODING_ERROR, "empty ToolResult rejected"},
        {malformed_executor_callback, RAC_ERROR_DECODING_ERROR, "malformed ToolResult rejected"},
        {status_error_executor_callback, RAC_ERROR_INTERNAL, "error buffer status honored"},
        {mismatched_executor_callback, RAC_ERROR_VALIDATION_FAILED,
         "mismatched ToolResult identity rejected"},
    };

    for (const auto& test_case : cases) {
        set_responses({
            R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        });
        auto request = make_request("weather");
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc = run_loop(bytes.data(), bytes.size(), test_case.callback, nullptr,
                                         &out);
        CHECK(rc == RAC_SUCCESS, "executor contract failure uses result envelope");
        runanywhere::v1::ToolCallingResult result;
        if (out.data && out.size > 0) {
            (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
        }
        CHECK(result.error_code() == test_case.expected_code, test_case.label);
        CHECK(result.tool_results_size() == 1, "failed executor result is recorded once");
        if (result.tool_results_size() == 1) {
            CHECK(!result.tool_results(0).success(), "failed executor result is unsuccessful");
            CHECK(!result.tool_results(0).error().empty(),
                  "failed executor result has a deterministic error");
        }
        rac_proto_buffer_free(&out);
    }

    cleanup_environment();
    return 0;
}

// ---------------------------------------------------------------------------
// A11: prior conversation history threading
// (ToolCallingSessionCreateRequest.history, tool_calling.proto field 19).
// run_loop_impl copies request.history() into ctx.generation.history and
// run_generate_once flattens it into rac_llm_options_t.history / n_history for
// EVERY generate in the loop.
// ---------------------------------------------------------------------------

int test_history_flows_to_options_history() {
    if (!load_mock_llm())
        return 1;
    set_responses({"Direct answer, no tool needed."});

    auto request = make_request("What about tomorrow?");
    // Even-length, pre-alternated [user0, asst0, user1, asst1]. The current turn
    // travels as `prompt` and must NOT appear in history.
    request.add_history("What's the weather in Tokyo?");
    request.add_history("It is sunny, 25C.");
    request.add_history("And in Osaka?");
    request.add_history("Cloudy, 22C.");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "history run_loop returns RAC_SUCCESS");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "no-tool history request generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].n_history == 4, "options.n_history matches request.history size");
        const std::vector<std::string> expected = {"What's the weather in Tokyo?",
                                                    "It is sunny, 25C.", "And in Osaka?",
                                                    "Cloudy, 22C."};
        CHECK(captures[0].history == expected, "history forwarded verbatim, in order");
        CHECK(captures[0].prompt.find("What about tomorrow?") != std::string::npos,
              "current turn still travels as the prompt");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_history_threads_into_decision_and_followup_generates() {
    if (!load_mock_llm())
        return 1;
    // One tool call then a synthesis turn: history must reach BOTH generates
    // (the tool-decision generate copies ctx.generation; the follow-up generate
    // copies ctx which carries ctx.generation).
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny, 25C.",
    });

    auto request = make_request("What's the weather in Tokyo?");
    request.add_history("Hi");
    request.add_history("Hello! How can I help?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    {
        std::lock_guard<std::mutex> lg(exec.mu);
        exec.result_jsons.emplace_back(R"({"temp":25,"condition":"sunny"})");
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "history+tool run_loop returns RAC_SUCCESS");

    const auto captures = generation_captures();
    CHECK(captures.size() == 2, "tool call plus synthesis generate twice");
    const std::vector<std::string> expected = {"Hi", "Hello! How can I help?"};
    if (captures.size() == 2) {
        CHECK(captures[0].n_history == 2, "decision generate inherits history count");
        CHECK(captures[0].history == expected, "decision generate inherits history verbatim");
        CHECK(captures[1].n_history == 2, "follow-up synthesis generate inherits history count");
        CHECK(captures[1].history == expected, "follow-up synthesis generate inherits history");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_odd_length_history_drops_trailing_turn() {
    if (!load_mock_llm())
        return 1;
    set_responses({"Answer."});

    auto request = make_request("Follow-up question.");
    // Odd count: a trailing user turn with no assistant reply. The loop drops the
    // last entry so the positional [user,asst,...] alignment stays intact.
    request.add_history("First user turn");
    request.add_history("First assistant reply");
    request.add_history("Dangling user turn with no reply");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "odd-history run_loop returns RAC_SUCCESS");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "odd-history request generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].n_history == 2, "odd history is trimmed to an even count");
        const std::vector<std::string> expected = {"First user turn", "First assistant reply"};
        CHECK(captures[0].history == expected, "trailing unpaired user turn is dropped");
        CHECK(std::find(captures[0].history.begin(), captures[0].history.end(),
                        "Dangling user turn with no reply") == captures[0].history.end(),
              "dropped turn never reaches the backend");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_empty_history_yields_no_options_history() {
    if (!load_mock_llm())
        return 1;
    set_responses({"Single-turn answer."});

    // make_request adds no history; single-turn callers must not accidentally
    // send a non-null history pointer or a positive n_history.
    auto request = make_request("Just a single-turn question.");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "empty-history run_loop returns RAC_SUCCESS");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "empty-history request generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].n_history == 0, "no history => n_history == 0");
        CHECK(captures[0].history.empty(), "no history => empty options.history");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_null_arguments_return_null_pointer() {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = run_loop(nullptr, 0, nullptr, nullptr, &out);
    CHECK(rc == RAC_ERROR_NULL_POINTER, "null callback rejected");
    rac_proto_buffer_free(&out);

    rc = run_loop(nullptr, 0, executor_callback, nullptr, nullptr);
    CHECK(rc == RAC_ERROR_NULL_POINTER, "null out_result rejected");

    rac_proto_buffer_init(&out);
    rc = rac_tool_calling_run_loop_proto(nullptr, 0, executor_callback, nullptr, nullptr, nullptr,
                                         &out);
    CHECK(rc == RAC_ERROR_NULL_POINTER, "null handle publication callback rejected");
    return 0;
}

// RUN-80: tools may be OFFERED without being NEEDED. With the neutralized prompt
// (no "ALWAYS use the tool" bias, no hardcoded weather/math few-shot), an
// unrelated question must NOT trigger a call — but the offered tools are still
// advertised, and a non-grammar backend attaches no grammar.
int test_tools_present_but_unused_makes_no_call() {
    if (!load_mock_llm())
        return 1;
    set_responses({"The capital of France is Paris."});

    auto request = make_request("What is the capital of France?");
    *request.add_tools() = make_calculate_tool();  // weather + calculate offered
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "unused-tools turn returns success");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete(), "unused-tools turn completes");
    CHECK(result.tool_calls_size() == 0, "no tool call when none is needed");
    CHECK(result.tool_results_size() == 0, "no tool result when none is needed");
    CHECK(result.text() == "The capital of France is Paris.", "plain answer echoed");
    CHECK(exec.invocation_count == 0, "executor not invoked");
    CHECK(generate_calls() == 1, "single generation");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "one AUTO generation");
    if (captures.size() == 1) {
        CHECK(captures[0].prompt.find("get_weather") != std::string::npos,
              "offered tools are still advertised (get_weather)");
        CHECK(captures[0].prompt.find("calculate") != std::string::npos,
              "offered tools are still advertised (calculate)");
        CHECK(captures[0].prompt.find("ALWAYS use the tool") == std::string::npos,
              "the aggressive ALWAYS-use-the-tool bias is gone");
        CHECK(captures[0].temperature == 0.5f, "AUTO keeps caller temperature");
        CHECK(!captures[0].disable_thinking, "AUTO leaves thinking enabled");
        CHECK(captures[0].grammar.empty(), "non-grammar backend attaches no grammar");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

// RUN-80: tool_choice=NONE strips every tool schema from the prompt and never
// calls, even with multiple tools offered and a benign answer.
int test_none_suppresses_tools_and_never_calls() {
    if (!load_mock_llm())
        return 1;
    set_responses({"Here is a direct answer."});

    auto request = make_request("Answer directly.");
    *request.add_tools() = make_calculate_tool();
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "NONE with tools returns success");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete(), "NONE completes");
    CHECK(result.error_code() == 0, "NONE plain answer has no policy error");
    CHECK(result.tool_calls_size() == 0, "NONE makes no tool call");
    CHECK(exec.invocation_count == 0, "NONE never invokes executor");

    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "NONE generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].prompt == request.prompt(),
              "NONE suppresses every tool schema even with two tools");
        CHECK(captures[0].grammar.empty(), "NONE attaches no grammar");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

// RUN-80: the QHexRT grammar enhancement is capability-gated. A grammar-capable
// backend (framework == QHEXRT) gets options.grammar="toolcall_opt:<names>" on
// the decision turn; every other engine (llama.cpp/onnx/cloud) gets NONE, so the
// change is a strict no-op for them.
int test_grammar_attached_only_for_grammar_backend() {
    // Grammar-capable backend: expect the ToolCallOptional spec over the live tools.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({"Paris is the capital of France."});
    {
        auto request = make_request("What is the capital of France?");
        *request.add_tools() = make_calculate_tool();  // tools: get_weather, calculate
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        CHECK(rc == RAC_SUCCESS, "grammar backend turn succeeds");
        const auto captures = generation_captures();
        CHECK(captures.size() == 1, "grammar backend generates once");
        if (captures.size() == 1) {
            CHECK(captures[0].grammar == "toolcall_opt:get_weather,calculate",
                  "QHexRT gets ToolCallOptional grammar over the live tool set");
        }
        rac_proto_buffer_free(&out);
    }

    // Non-grammar backend (llama.cpp): identical request, zero grammar attached.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP))
        return 1;
    set_responses({"Paris is the capital of France."});
    {
        auto request = make_request("What is the capital of France?");
        *request.add_tools() = make_calculate_tool();
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        CHECK(rc == RAC_SUCCESS, "non-grammar backend turn succeeds");
        const auto captures = generation_captures();
        CHECK(captures.size() == 1, "non-grammar backend generates once");
        if (captures.size() == 1) {
            CHECK(captures[0].grammar.empty(),
                  "non-grammar engine gets no grammar (strict no-op)");
        }
        rac_proto_buffer_free(&out);
    }

    cleanup_environment();
    return 0;
}

// RUN-81: disable_thinking is enforced at generation. Engines that do NOT
// self-suppress (llama.cpp/onnx/cloud) get the "/no_think" directive prepended;
// QHexRT (which suppresses natively + strips the token) does NOT. The flag itself
// always reaches the backend, and the post-hoc <think> strip stays universal.
int test_disable_thinking_directive_is_engine_gated() {
    const std::string kNoThink = "/no_think\n";

    // A) Non-native engine (llama.cpp) + disable → flag set AND directive prepended.
    if (!load_mock_llm())
        return 1;
    set_responses({"Plain answer."});
    {
        auto request = make_request("Hi");
        request.set_disable_thinking(true);
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        const auto captures = generation_captures();
        CHECK(captures.size() == 1, "disable+llamacpp generates once");
        if (captures.size() == 1) {
            CHECK(captures[0].disable_thinking, "disable_thinking flag reaches the backend");
            CHECK(captures[0].prompt.rfind(kNoThink, 0) == 0,
                  "llama.cpp gets the /no_think directive prepended");
        }
        rac_proto_buffer_free(&out);
    }

    // B) Default (thinking on) → no flag, no directive.
    if (!load_mock_llm())
        return 1;
    set_responses({"Plain answer."});
    {
        auto request = make_request("Hi");
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        const auto captures = generation_captures();
        CHECK(captures.size() == 1, "default generates once");
        if (captures.size() == 1) {
            CHECK(!captures[0].disable_thinking, "default leaves thinking enabled");
            CHECK(captures[0].prompt.rfind(kNoThink, 0) != 0, "default injects no directive");
        }
        rac_proto_buffer_free(&out);
    }

    // C) QHexRT + disable → flag set but directive SKIPPED (native suppression).
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({"Plain answer."});
    {
        auto request = make_request("Hi");
        request.set_disable_thinking(true);
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        const auto captures = generation_captures();
        CHECK(captures.size() == 1, "disable+qhexrt generates once");
        if (captures.size() == 1) {
            CHECK(captures[0].disable_thinking, "disable_thinking flag still reaches QHexRT");
            CHECK(captures[0].prompt.rfind(kNoThink, 0) != 0,
                  "QHexRT skips the /no_think directive (native suppression)");
        }
        rac_proto_buffer_free(&out);
    }

    cleanup_environment();
    return 0;
}

// RUN-80 (review follow-up): tool_choice=NONE must attach NO grammar even on a
// grammar backend — a "chat OR one call" grammar would invite a call the NONE
// policy then rejects. Proves the NONE gate on the grammar path (not just the
// prompt body).
int test_none_attaches_no_grammar_on_grammar_backend() {
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({"Here is a direct answer."});

    auto request = make_request("Answer directly.");
    *request.add_tools() = make_calculate_tool();
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "NONE on grammar backend succeeds");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete(), "NONE on grammar backend completes");
    CHECK(result.tool_calls_size() == 0, "NONE makes no call");
    const auto captures = generation_captures();
    CHECK(captures.size() == 1, "NONE grammar-backend generates once");
    if (captures.size() == 1) {
        CHECK(captures[0].grammar.empty(),
              "NONE attaches NO grammar on a grammar backend (no invite-then-reject)");
    }

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

// RUN-80 (review follow-up): grammar constrains the DECISION turn but must be
// dropped on a pure SYNTHESIS turn (a call ran + tools not kept) so the final
// answer is free text; and RETAINED when tools stay available.
int test_grammar_dropped_on_synthesis_turn() {
    // keep_tools_available=false → grammar on turn 0, gone on synthesis turn 1.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny.",
    });
    {
        auto request = make_request("Weather in Tokyo?");  // one tool: get_weather
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        {
            std::lock_guard<std::mutex> lg(exec.mu);
            exec.result_jsons.emplace_back(R"({"temp":25})");
        }
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        const auto captures = generation_captures();
        CHECK(captures.size() == 2, "decision + synthesis = two generations");
        if (captures.size() == 2) {
            CHECK(captures[0].grammar == "toolcall_opt:get_weather",
                  "decision turn is grammar-constrained");
            CHECK(captures[1].grammar.empty(), "synthesis turn is unconstrained");
        }
        rac_proto_buffer_free(&out);
    }

    // keep_tools_available=true → grammar persists on the follow-up turn.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny.",
    });
    {
        auto request = make_request("Weather in Tokyo?");
        request.set_keep_tools_available(true);
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        {
            std::lock_guard<std::mutex> lg(exec.mu);
            exec.result_jsons.emplace_back(R"({"temp":25})");
        }
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        const auto captures = generation_captures();
        CHECK(captures.size() == 2, "keep-tools decision + follow-up = two generations");
        if (captures.size() == 2) {
            CHECK(captures[1].grammar == "toolcall_opt:get_weather",
                  "grammar persists on the follow-up when tools stay available");
        }
        rac_proto_buffer_free(&out);
    }

    cleanup_environment();
    return 0;
}

// RUN-81: the post-hoc <think> strip is universal — thinking content never leaks
// into the final answer regardless of engine or the disable flag.
int test_thinking_content_stripped_from_answer() {
    if (!load_mock_llm())
        return 1;
    set_responses({"<think>secret plan</think>Visible answer."});
    {
        auto request = make_request("Hi");
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        ExecutorState exec;
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        (void)run_loop(bytes.data(), bytes.size(), executor_callback, &exec, &out);
        runanywhere::v1::ToolCallingResult result;
        if (out.data && out.size > 0) {
            (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
        }
        CHECK(result.text().find("secret") == std::string::npos, "thinking content stripped");
        CHECK(result.text().find("Visible") != std::string::npos, "visible answer preserved");
        rac_proto_buffer_free(&out);
    }

    cleanup_environment();
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_tool_calling_run_loop\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: no protobuf\n");
        return 0;
#else
        test_null_arguments_return_null_pointer();
        test_no_tool_call_completes_immediately();
        test_one_tool_call_then_final_text();
        test_forced_tool_name_only_is_narrowed_and_independently_budgeted();
        test_none_vetoes_forced_tool_name();
        test_none_blocks_hallucinated_call_when_validation_disabled();
        test_forced_target_blocks_wrong_call_when_validation_disabled();
        test_specific_target_must_be_nonempty_and_present();
        test_specific_and_required_reject_initial_no_call();
        test_search_web_synthesis_is_current_compact_and_attributed();
        test_tool_name_mentions_do_not_force_execution();
        test_tools_present_but_unused_makes_no_call();
        test_none_suppresses_tools_and_never_calls();
        test_grammar_attached_only_for_grammar_backend();
        test_none_attaches_no_grammar_on_grammar_backend();
        test_grammar_dropped_on_synthesis_turn();
        test_disable_thinking_directive_is_engine_gated();
        test_thinking_content_stripped_from_answer();
        test_max_tool_calls_capped();
        test_max_tool_calls_blocks_extra_side_effect();
        test_auto_execute_false_returns_call_without_side_effect();
        test_validation_failure_short_circuits();
        test_executor_result_contract_is_fail_closed();
        test_history_flows_to_options_history();
        test_history_threads_into_decision_and_followup_generates();
        test_odd_length_history_drops_trailing_turn();
        test_empty_history_yields_no_options_history();
        if (g_registry) {
            rac_model_registry_destroy(g_registry);
            g_registry = nullptr;
        }
        std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
        return fail_count == 0 ? 0 : 1;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "test_tool_calling_run_loop: uncaught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        std::fprintf(stderr, "test_tool_calling_run_loop: uncaught exception\n");
        return 1;
    }
}
