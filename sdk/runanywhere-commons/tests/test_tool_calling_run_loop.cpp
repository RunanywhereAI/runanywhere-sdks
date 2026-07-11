/**
 * @file test_tool_calling_run_loop.cpp
 * @brief Tests for rac_tool_calling_run_loop_proto.
 *
 * Mirrors test_tool_calling_session_proto.cpp's setup (mock LLM plugin,
 * fixture-driven responses) and exercises the synchronous single-call API:
 *  1. No tool call -> immediate completion with text-only result.
 *  2. One tool call -> executor invoked once, follow-up generates final text.
 *  3. Iteration cap enforced (executor called max_iterations times).
 *  4. Validation failure short-circuits with a failed ToolResult.
 */

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
    std::vector<std::string> stop_sequences;
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
            for (size_t i = 0; i < options->num_stop_sequences; ++i) {
                const char* stop = options->stop_sequences ? options->stop_sequences[i] : nullptr;
                if (stop && stop[0] != '\0') {
                    capture.stop_sequences.emplace_back(stop);
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

runanywhere::v1::ModelInfo build_llm_model() {
    runanywhere::v1::ModelInfo model;
    model.set_id("toolloop.llm");
    model.set_name("ToolLoop LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
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

bool load_mock_llm() {
    cleanup_environment();
    if (rac_plugin_register(&g_mock_vtable) != RAC_SUCCESS)
        return false;

    if (!g_registry && (rac_model_registry_create(&g_registry) != RAC_SUCCESS || !g_registry)) {
        return false;
    }

    std::vector<uint8_t> model_bytes;
    auto model = build_llm_model();
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
                                                              uint32_t max_iterations = 0) {
    runanywhere::v1::ToolCallingSessionCreateRequest request;
    request.set_prompt(prompt);
    request.set_max_tokens(64);
    request.set_temperature(0.5f);
    *request.add_tools() = make_weather_tool();
    request.set_format_hint("default");
    if (max_iterations > 0)
        request.set_max_iterations(max_iterations);
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
    tr.set_call_id(received.id());
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
    rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
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
    rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
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

int test_explicit_tool_decision_is_narrowed_and_independently_budgeted() {
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
    const rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "explicit-tool run_loop returns RAC_SUCCESS");
    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.tool_calls_size() == 1, "completed decision records one tool call");
    CHECK(result.tool_results_size() == 1, "completed decision records one tool result");
    CHECK(result.text().find("540") != std::string::npos,
          "follow-up produces a visible final answer");

    const auto captures = generation_captures();
    CHECK(captures.size() == 2, "explicit request generated decision plus synthesis");
    if (captures.size() == 2) {
        CHECK(captures[0].max_tokens == 192, "explicit decision safety-capped at 192 tokens");
        CHECK(captures[0].temperature == 0.0f, "explicit decision uses greedy temperature");
        CHECK(captures[0].top_p == 1.0f, "explicit decision disables nucleus truncation");
        CHECK(captures[0].disable_thinking, "explicit decision disables thinking");
        CHECK(captures[0].stop_sequences == std::vector<std::string>{"</tool_call>"},
              "explicit decision stops at completed default tool call");
        CHECK(captures[0].prompt.rfind("/no_think\n", 0) == 0,
              "explicit decision carries no-think directive");
        CHECK(captures[0].prompt.find("calculate") != std::string::npos,
              "explicit decision advertises selected tool");
        CHECK(captures[0].prompt.find("expression") != std::string::npos,
              "explicit decision carries exact required argument");
        CHECK(captures[0].prompt.find("get_weather") == std::string::npos,
              "explicit decision omits unrelated generic weather example");
        CHECK(captures[0].prompt.find("unrelated_tool") == std::string::npos,
              "explicit decision omits unrelated schema");
        CHECK(captures[0].prompt.find("## EXAMPLES") == std::string::npos,
              "explicit decision omits generic examples");
        CHECK(captures[0].prompt.find("Math/calculation question") == std::string::npos,
              "explicit decision omits unrelated generic rules");
        CHECK(captures[0].prompt.size() < 800, "explicit decision prompt stays compact");

        CHECK(captures[1].max_tokens == 96, "synthesis retains final-answer token budget");
        CHECK(captures[1].temperature == 0.7f, "synthesis retains caller sampling temperature");
        CHECK(captures[1].top_p == 0.9f, "synthesis retains caller top-p");
        CHECK(!captures[1].disable_thinking, "synthesis retains caller thinking policy");
        CHECK(captures[1].stop_sequences.empty(), "synthesis does not inherit decision stop");
        CHECK(captures[1].prompt.rfind("/no_think\n", 0) != 0,
              "synthesis does not inherit decision-only directive");
    }
    CHECK(exec.invocation_count == 1, "explicit executor invoked exactly once");
    if (!exec.received_calls.empty()) {
        CHECK(exec.received_calls[0].name() == "calculate", "executor receives calculate call");
        CHECK(exec.received_calls[0].arguments_json().find("45 * 12") != std::string::npos,
              "executor receives complete expression argument");
    }

    rac_proto_buffer_free(&out);
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
    const rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
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
        CHECK(captures[1].prompt.find("policy effective on the current date") !=
                  std::string::npos,
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

int test_max_iterations_capped() {
    if (!load_mock_llm())
        return 1;
    // Three loop iterations would consume three responses, but max_iterations=2
    // forces the loop to stop after two parses (executor invoked twice when
    // both responses are tool calls).
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"B"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"C"}}</tool_call>)",
    });

    auto request = make_request("weather everywhere", /*max_iterations=*/2);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.iterations_used() == 2, "iterations_used == max_iterations");
    CHECK(result.tool_calls_size() == 2, "two tool_calls recorded");
    CHECK(result.tool_results_size() == 2, "two tool_results recorded");
    CHECK(exec.invocation_count == 2, "executor invoked twice");
    CHECK(generate_calls() == 2, "generate called twice");

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
    rac_result_t rc =
        rac_tool_calling_run_loop_proto(bytes.data(), bytes.size(), executor_callback, &exec, &out);
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

int test_null_arguments_return_null_pointer() {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_calling_run_loop_proto(nullptr, 0, nullptr, nullptr, &out);
    CHECK(rc == RAC_ERROR_NULL_POINTER, "null callback rejected");
    rac_proto_buffer_free(&out);

    rc = rac_tool_calling_run_loop_proto(nullptr, 0, executor_callback, nullptr, nullptr);
    CHECK(rc == RAC_ERROR_NULL_POINTER, "null out_result rejected");
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
        test_explicit_tool_decision_is_narrowed_and_independently_budgeted();
        test_search_web_synthesis_is_current_compact_and_attributed();
        test_max_iterations_capped();
        test_validation_failure_short_circuits();
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
