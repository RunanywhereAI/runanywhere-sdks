/**
 * @file test_tool_calling_session_proto.cpp
 * @brief Tests for rac_tool_calling_session_*_proto.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <ranges>
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
#include "llm_service.pb.h"
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

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
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
    model.set_id("toolsession.llm");
    model.set_name("ToolSession LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/toolsession-test.gguf");
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
    load.set_model_id("toolsession.llm");
    std::vector<uint8_t> load_bytes;
    if (!serialize(load, &load_bytes))
        return false;

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_lifecycle_load_proto(g_registry, load_bytes.data(), load_bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    const bool ok = rc == RAC_SUCCESS && parse_buffer(out, &result) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

struct EventSink {
    std::mutex mu;
    std::vector<runanywhere::v1::ToolCallingSessionEvent> events;

    int count_kind(runanywhere::v1::ToolCallingSessionEvent::KindCase kind) {
        std::lock_guard<std::mutex> lg(mu);
        int count = 0;
        for (const auto& ev : events) {
            if (ev.kind_case() == kind)
                ++count;
        }
        return count;
    }

    const runanywhere::v1::ToolCallingSessionEvent*
    find_first(runanywhere::v1::ToolCallingSessionEvent::KindCase kind) {
        std::lock_guard<std::mutex> lg(mu);
        for (const auto& ev : events) {
            if (ev.kind_case() == kind)
                return &ev;
        }
        return nullptr;
    }

    const runanywhere::v1::ToolCallingSessionEvent*
    find_last(runanywhere::v1::ToolCallingSessionEvent::KindCase kind) {
        std::lock_guard<std::mutex> lg(mu);
        for (auto& event : std::ranges::reverse_view(events)) {
            if (event.kind_case() == kind)
                return &event;
        }
        return nullptr;
    }
};

void sink_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* sink = static_cast<EventSink*>(user_data);
    runanywhere::v1::ToolCallingSessionEvent event;
    if (size > 0 && event.ParseFromArray(bytes, static_cast<int>(size))) {
        std::lock_guard<std::mutex> lg(sink->mu);
        sink->events.push_back(event);
    }
}

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

int test_session_emits_tool_call() {
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    EventSink sink;
    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "serialize create request");

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");
    CHECK(handle != 0, "handle non-zero");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 1, "one tool_call event");
    CHECK(sink.count_kind(EvCase::kFinalResult) == 0, "no final while paused");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 0, "no error");

    const auto* tool_call_ev = sink.find_first(EvCase::kToolCall);
    CHECK(tool_call_ev != nullptr, "tool_call captured");
    if (tool_call_ev) {
        CHECK(tool_call_ev->tool_call().name() == "get_weather", "tool name");
        CHECK(tool_call_ev->tool_call().arguments_json().find("Tokyo") != std::string::npos,
              "args contain Tokyo");
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_step_with_result_emits_final() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny, 25C.",
    });

    EventSink sink;
    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 1, "paused on tool_call");

    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(handle);
    const auto* tool_ev = sink.find_first(EvCase::kToolCall);
    if (tool_ev)
        step.set_tool_call_id(tool_ev->tool_call().id());
    step.set_result_json(R"({"temp":25,"condition":"sunny"})");
    std::vector<uint8_t> step_bytes;
    serialize(step, &step_bytes);

    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_SUCCESS, "step_with_result RAC_SUCCESS");

    CHECK(sink.count_kind(EvCase::kFinalResult) == 1, "one final_result");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 0, "no error");

    const auto* final_ev = sink.find_first(EvCase::kFinalResult);
    CHECK(final_ev != nullptr, "final captured");
    if (final_ev) {
        const auto& result = final_ev->final_result();
        CHECK(result.is_complete() == true, "is_complete true");
        CHECK(result.tool_calls_size() == 1, "has tool_call");
        CHECK(result.tool_results_size() == 1, "has tool_result");
        CHECK(result.iterations_used() == 2, "iterations_used == 2");
        CHECK(result.text().find("sunny") != std::string::npos, "text has sunny");
    }

    CHECK(generate_calls() == 2, "generate called twice");

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_iteration_cap_respected() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"B"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"C"}}</tool_call>)",
    });

    EventSink sink;
    auto request = make_request("weather everywhere", 2);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 1, "paused on first tool_call");

    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(handle);
    step.set_tool_call_id(sink.find_last(EvCase::kToolCall)->tool_call().id());
    step.set_result_json("{\"ok\":true}");
    std::vector<uint8_t> step_bytes;
    serialize(step, &step_bytes);
    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_SUCCESS, "first step resumed");

    step.Clear();
    step.set_session_handle(handle);
    step.set_tool_call_id(sink.find_last(EvCase::kToolCall)->tool_call().id());
    step.set_result_json("{\"ok\":true}");
    serialize(step, &step_bytes);
    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_SUCCESS, "second step resumed");

    CHECK(sink.count_kind(EvCase::kFinalResult) == 1, "final emitted after max_iterations");
    const auto* final_ev = sink.find_first(EvCase::kFinalResult);
    if (final_ev) {
        CHECK(final_ev->final_result().iterations_used() == 2, "iterations_used == max_iterations");
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_destroy_clears_state() {
    if (!load_mock_llm())
        return 1;
    set_responses({"plain text no tool call"});
    EventSink sink;
    auto request = make_request("hello");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create succeeds");
    CHECK(handle != 0, "handle non-zero");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kFinalResult) == 1, "final for plain text");

    rc = rac_tool_calling_session_destroy_proto(handle);
    CHECK(rc == RAC_SUCCESS, "destroy RAC_SUCCESS");
    rc = rac_tool_calling_session_destroy_proto(handle);
    CHECK(rc == RAC_SUCCESS, "destroy idempotent");
    rc = rac_tool_calling_session_destroy_proto(0);
    CHECK(rc == RAC_SUCCESS, "destroy(0) no-op");

    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(handle);
    step.set_result_json("{}");
    std::vector<uint8_t> step_bytes;
    serialize(step, &step_bytes);
    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_ERROR_INVALID_HANDLE, "step after destroy INVALID_HANDLE");

    cleanup_environment();
    return 0;
}

#endif

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_tool_calling_session_proto\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: no protobuf\n");
        return 0;
#else
        test_session_emits_tool_call();
        test_step_with_result_emits_final();
        test_iteration_cap_respected();
        test_destroy_clears_state();
        if (g_registry) {
            rac_model_registry_destroy(g_registry);
            g_registry = nullptr;
        }
        std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
        return fail_count == 0 ? 0 : 1;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
