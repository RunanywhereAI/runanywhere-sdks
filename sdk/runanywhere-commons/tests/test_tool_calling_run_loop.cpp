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

rac_result_t mock_generate(void*, const char*, const rac_llm_options_t*,
                           rac_llm_result_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
    std::string response;
    {
        std::lock_guard<std::mutex> lg(g_responses_mutex);
        g_generate_calls++;
        if (g_responses.empty()) {
            response = "empty-response";
        } else {
            response = g_responses.front();
            g_responses.erase(g_responses.begin());
        }
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
}

int generate_calls() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_generate_calls;
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
