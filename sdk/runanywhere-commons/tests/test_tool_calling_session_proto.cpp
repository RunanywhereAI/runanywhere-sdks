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
#include "errors.pb.h"
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
std::vector<std::string> g_prompts;
// rac_llm_options_t.grammar as each generate saw it (RUN-80 grammar path).
std::vector<std::string> g_grammars;
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

rac_result_t mock_generate(void*, const char* prompt, const rac_llm_options_t* options,
                           rac_llm_result_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
    std::string response;
    {
        std::lock_guard<std::mutex> lg(g_responses_mutex);
        g_generate_calls++;
        g_prompts.emplace_back(prompt ? prompt : "");
        g_grammars.emplace_back(options && options->grammar ? options->grammar : "");
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
    g_prompts.clear();
    g_grammars.clear();
}

std::vector<std::string> generated_grammars() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_grammars;
}

int generate_calls() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_generate_calls;
}

std::vector<std::string> generated_prompts() {
    std::lock_guard<std::mutex> lg(g_responses_mutex);
    return g_prompts;
}

runanywhere::v1::ModelInfo build_llm_model(runanywhere::v1::InferenceFramework framework =
                                               runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP) {
    runanywhere::v1::ModelInfo model;
    model.set_id("toolsession.llm");
    model.set_name("ToolSession LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    // A QHexRT framework with no registered qhexrt plugin still loads via the
    // primitive fallback to the mock GENERATE_TEXT vtable, so the session grammar
    // path can be exercised with the mock ops (supports_grammar=true).
    model.set_framework(framework);
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
    const uint64_t* published_handle = nullptr;
    bool callback_saw_published_handle = false;

    bool saw_published_handle() {
        std::lock_guard<std::mutex> lg(mu);
        return callback_saw_published_handle;
    }

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
    const bool parsed = size > 0 && event.ParseFromArray(bytes, static_cast<int>(size));
    std::lock_guard<std::mutex> lg(sink->mu);
    sink->callback_saw_published_handle =
        sink->callback_saw_published_handle ||
        (sink->published_handle != nullptr && *sink->published_handle != 0);
    if (parsed) {
        sink->events.push_back(event);
    }
}

void capture_session_handle(uint64_t handle, void* user_data) {
    if (user_data) {
        *static_cast<uint64_t*>(user_data) = handle;
    }
}

struct DestroyOnFirstEventSink {
    const uint64_t* handle = nullptr;
    int callback_count = 0;
    int tool_call_count = 0;
    bool destroy_called = false;
    rac_result_t destroy_result = RAC_ERROR_INVALID_STATE;
};

void destroy_on_first_event_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* sink = static_cast<DestroyOnFirstEventSink*>(user_data);
    runanywhere::v1::ToolCallingSessionEvent event;
    if (size > 0 && event.ParseFromArray(bytes, static_cast<int>(size)) &&
        event.kind_case() == runanywhere::v1::ToolCallingSessionEvent::kToolCall) {
        ++sink->tool_call_count;
    }
    ++sink->callback_count;
    if (!sink->destroy_called && sink->handle && *sink->handle != 0) {
        sink->destroy_called = true;
        sink->destroy_result = rac_tool_calling_session_destroy_proto(*sink->handle);
    }
}

struct NestedStepDestroySink {
    const uint64_t* handle = nullptr;
    int callback_count = 0;
    int tool_call_count = 0;
    int final_result_count = 0;
    bool step_started = false;
    bool step_serialized = false;
    bool in_step = false;
    bool destroy_called = false;
    rac_result_t step_result = RAC_ERROR_INVALID_STATE;
    rac_result_t destroy_result = RAC_ERROR_INVALID_STATE;
};

void nested_step_destroy_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* sink = static_cast<NestedStepDestroySink*>(user_data);
    runanywhere::v1::ToolCallingSessionEvent event;
    if (size == 0 || !event.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }

    ++sink->callback_count;
    if (event.kind_case() == runanywhere::v1::ToolCallingSessionEvent::kFinalResult) {
        ++sink->final_result_count;
    }

    if (sink->in_step && !sink->destroy_called && sink->handle && *sink->handle != 0) {
        sink->destroy_called = true;
        sink->destroy_result = rac_tool_calling_session_destroy_proto(*sink->handle);
        return;
    }

    if (event.kind_case() != runanywhere::v1::ToolCallingSessionEvent::kToolCall ||
        sink->step_started || !sink->handle || *sink->handle == 0) {
        return;
    }

    ++sink->tool_call_count;
    sink->step_started = true;
    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(*sink->handle);
    step.set_tool_call_id(event.tool_call().id());
    step.set_result_json(R"({"temperature":25})");
    std::vector<uint8_t> step_bytes;
    sink->step_serialized = serialize(step, &step_bytes);
    if (!sink->step_serialized) {
        return;
    }

    sink->in_step = true;
    sink->step_result =
        rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    sink->in_step = false;
}

struct CancelBeforeToolDispatchSink {
    const uint64_t* handle = nullptr;
    int callback_count = 0;
    int tool_side_effect_count = 0;
    bool cancel_called = false;
    rac_result_t cancel_result = RAC_ERROR_INVALID_STATE;
};

void cancel_before_tool_dispatch_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* sink = static_cast<CancelBeforeToolDispatchSink*>(user_data);
    runanywhere::v1::ToolCallingSessionEvent event;
    if (size == 0 || !event.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }

    ++sink->callback_count;
    if (event.kind_case() == runanywhere::v1::ToolCallingSessionEvent::kToolCall) {
        ++sink->tool_side_effect_count;
    }
    if (event.kind_case() == runanywhere::v1::ToolCallingSessionEvent::kLlmStreamEventBytes &&
        !sink->cancel_called && sink->handle && *sink->handle != 0) {
        sink->cancel_called = true;
        sink->cancel_result = rac_tool_calling_session_cancel_proto(*sink->handle);
    }
}

bool parse_first_error(EventSink& sink, runanywhere::v1::SDKError* out_error) {
    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    const auto* event = sink.find_first(EvCase::kErrorBytes);
    return event && out_error && out_error->ParseFromString(event->error_bytes());
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

runanywhere::v1::ToolDefinition make_calculate_tool() {
    runanywhere::v1::ToolDefinition tool;
    tool.set_name("calculate");
    tool.set_description("Evaluate a math expression");
    auto* param = tool.add_parameters();
    param->set_name("expression");
    param->set_type(runanywhere::v1::TOOL_PARAMETER_TYPE_STRING);
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
    sink.published_handle = &handle;
    rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");
    CHECK(handle != 0, "handle non-zero");
    CHECK(sink.saw_published_handle(), "handle published before event callback");

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
    rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
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

int test_max_tool_calls_allows_final_synthesis() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"A"}}</tool_call>)",
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"B"}}</tool_call>)",
        "Final answer after two tool calls.",
    });

    EventSink sink;
    auto request = make_request("weather everywhere", 2);
    request.set_keep_tools_available(true);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
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

    CHECK(sink.count_kind(EvCase::kFinalResult) == 1,
          "final synthesis emitted after max_tool_calls");
    const auto* final_ev = sink.find_first(EvCase::kFinalResult);
    if (final_ev) {
        CHECK(final_ev->final_result().iterations_used() == 3,
              "two tool calls plus final synthesis use three generations");
        CHECK(final_ev->final_result().tool_calls_size() == 2,
              "max_tool_calls limits invocations, not generation turns");
        CHECK(final_ev->final_result().text() == "Final answer after two tool calls.",
              "final synthesis text is preserved");
    }
    CHECK(generate_calls() == 3, "final synthesis runs after second tool result");

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_forced_tool_name_only_promotes_session_to_specific() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    EventSink sink;
    auto request = make_request("Use the selected tool.");
    request.set_forced_tool_name("get_weather");
    *request.add_tools() = make_calculate_tool();
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "forced-name-only session create succeeds");
    CHECK(handle != 0, "forced-name-only session publishes handle");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 1,
          "forced-name-only session emits selected tool call");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 0,
          "forced-name-only session has no policy error");
    const auto prompts = generated_prompts();
    CHECK(prompts.size() == 1, "forced-name-only session generates once");
    if (prompts.size() == 1) {
        CHECK(prompts[0].find("get_weather") != std::string::npos,
              "forced-name-only session advertises selected tool");
        CHECK(prompts[0].find("calculate") == std::string::npos,
              "forced-name-only session narrows away unrelated tools");
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_none_vetoes_forced_name_in_session() {
    if (!load_mock_llm())
        return 1;
    set_responses({"No tool is needed."});

    EventSink sink;
    auto request = make_request("Answer directly without tools.");
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    request.set_forced_tool_name("get_weather");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "NONE plus forced name session create succeeds");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kFinalResult) == 1,
          "NONE plus forced name permits a plain final response");
    CHECK(sink.count_kind(EvCase::kToolCall) == 0, "NONE plus forced name emits no tool call");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 0, "NONE plus forced name emits no error");
    const auto prompts = generated_prompts();
    CHECK(prompts.size() == 1, "NONE plus forced name session generates once");
    if (prompts.size() == 1) {
        CHECK(prompts[0] == request.prompt(), "NONE veto suppresses session tool schemas");
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_none_blocks_session_call_when_validation_disabled() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    EventSink sink;
    auto request = make_request("Answer directly without tools.");
    request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
    request.set_validate_calls(false);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "NONE session policy failure is emitted asynchronously");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 0,
          "NONE session never publishes a call for host execution");
    CHECK(sink.count_kind(EvCase::kLlmStreamEventBytes) == 0,
          "NONE hallucinated call emits no completed LLM event");
    CHECK(sink.count_kind(EvCase::kFinalResult) == 0,
          "NONE hallucinated call is not reported as successful");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 1,
          "NONE hallucinated call emits one policy error");
    runanywhere::v1::SDKError error;
    CHECK(parse_first_error(sink, &error), "NONE session error decodes");
    CHECK(error.c_abi_code() == RAC_ERROR_VALIDATION_FAILED,
          "NONE session error carries validation failure");
    CHECK(error.message() == "Tool calls are disabled by tool_choice=NONE",
          "NONE session error carries deterministic policy message");

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_forced_target_blocks_wrong_session_call_when_validation_disabled() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    EventSink sink;
    auto request = make_request("Use calculate only.");
    *request.add_tools() = make_calculate_tool();
    request.set_forced_tool_name("calculate");
    request.set_validate_calls(false);
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "wrong forced-target session call emits asynchronously");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    CHECK(sink.count_kind(EvCase::kToolCall) == 0,
          "wrong forced-target session call is never published to host");
    CHECK(sink.count_kind(EvCase::kLlmStreamEventBytes) == 0,
          "wrong forced-target session call emits no completed LLM event");
    CHECK(sink.count_kind(EvCase::kFinalResult) == 0,
          "wrong forced-target session call is not reported as successful");
    CHECK(sink.count_kind(EvCase::kErrorBytes) == 1,
          "wrong forced-target session call emits one policy error");
    runanywhere::v1::SDKError error;
    CHECK(parse_first_error(sink, &error), "forced-target session error decodes");
    CHECK(error.c_abi_code() == RAC_ERROR_VALIDATION_FAILED,
          "forced-target session error carries validation failure");
    CHECK(error.message() == "Tool call must use tool_choice=SPECIFIC target: calculate",
          "forced-target session error carries deterministic policy message");

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_specific_session_target_must_be_nonempty_and_present() {
    if (!load_mock_llm())
        return 1;

    const auto run_invalid_request = [](runanywhere::v1::ToolCallingSessionCreateRequest request,
                                        const char* label) {
        EventSink sink;
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        const rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_ERROR_INVALID_ARGUMENT, label);
        CHECK(handle == 0, "invalid SPECIFIC session does not publish handle");
        using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
        CHECK(sink.count_kind(EvCase::kToolCall) == 0,
              "invalid SPECIFIC session emits no tool call");
    };

    auto empty_target = make_request("Use a specific tool.");
    empty_target.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    run_invalid_request(empty_target, "SPECIFIC session without target is rejected");

    auto missing_target = make_request("Use the missing tool.");
    missing_target.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
    missing_target.set_forced_tool_name("missing_tool");
    run_invalid_request(missing_target, "SPECIFIC session target absent from tools is rejected");
    CHECK(generate_calls() == 0, "invalid SPECIFIC sessions fail before generation");

    cleanup_environment();
    return 0;
}

int test_specific_and_required_sessions_reject_initial_no_call() {
    if (!load_mock_llm())
        return 1;

    const auto run_required_choice = [](runanywhere::v1::ToolChoiceMode mode,
                                        const std::string& expected_message, const char* label) {
        set_responses({"I decided not to call a tool."});
        EventSink sink;
        auto request = make_request("A tool call is mandatory.");
        request.set_tool_choice(mode);
        if (mode == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC) {
            request.set_forced_tool_name("get_weather");
        }
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        const rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_SUCCESS, label);

        using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
        CHECK(sink.count_kind(EvCase::kToolCall) == 0,
              "required session no-call emits no host-executable call");
        CHECK(sink.count_kind(EvCase::kLlmStreamEventBytes) == 0,
              "required session no-call emits no completed LLM event");
        CHECK(sink.count_kind(EvCase::kFinalResult) == 0,
              "required session no-call is not reported as successful");
        CHECK(sink.count_kind(EvCase::kErrorBytes) == 1,
              "required session no-call emits one policy error");
        runanywhere::v1::SDKError error;
        CHECK(parse_first_error(sink, &error), "required session error decodes");
        CHECK(error.c_abi_code() == RAC_ERROR_VALIDATION_FAILED,
              "required session error carries validation failure");
        CHECK(error.message() == expected_message,
              "required session error carries deterministic policy message");

        rac_tool_calling_session_destroy_proto(handle);
    };

    run_required_choice(runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC,
                        "tool_choice=SPECIFIC requires a tool call",
                        "SPECIFIC session no-call emits a policy failure");
    run_required_choice(runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED,
                        "tool_choice=REQUIRED requires a tool call",
                        "REQUIRED session no-call emits a policy failure");

    cleanup_environment();
    return 0;
}

int test_step_rejects_mismatched_tool_call_id_without_mutation() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny.",
    });

    EventSink sink;
    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
    CHECK(rc == RAC_SUCCESS, "identity test session create succeeds");

    using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
    const auto* tool_event = sink.find_first(EvCase::kToolCall);
    CHECK(tool_event != nullptr, "identity test captures pending tool call");
    const std::string pending_tool_call_id = tool_event ? tool_event->tool_call().id() : "";

    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(handle);
    step.set_tool_call_id("different-call-id");
    step.set_result_json(R"({"temperature":25})");
    std::vector<uint8_t> step_bytes;
    serialize(step, &step_bytes);
    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_ERROR_VALIDATION_FAILED, "mismatched tool_call_id is rejected");
    CHECK(generate_calls() == 1, "mismatched result does not start another generation");
    CHECK(sink.count_kind(EvCase::kFinalResult) == 0,
          "mismatched result does not complete the session");

    if (tool_event) {
        step.set_tool_call_id(pending_tool_call_id);
        serialize(step, &step_bytes);
        rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
        CHECK(rc == RAC_SUCCESS, "correct pending tool_call_id remains accepted");
        CHECK(generate_calls() == 2, "correct result resumes generation exactly once");
        const auto* final_event = sink.find_first(EvCase::kFinalResult);
        CHECK(final_event != nullptr, "correct result completes the session");
        if (final_event) {
            CHECK(final_event->final_result().tool_results_size() == 1,
                  "rejected result did not mutate accumulated tool results");
            if (final_event->final_result().tool_results_size() == 1) {
                CHECK(final_event->final_result().tool_results(0).tool_call_id() ==
                          pending_tool_call_id,
                      "accepted result retains pending call identity");
            }
        }
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

int test_reentrant_destroy_stops_remaining_queued_events() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    DestroyOnFirstEventSink sink;
    sink.handle = &handle;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), destroy_on_first_event_callback, &sink, capture_session_handle,
        &handle);

    CHECK(rc == RAC_SUCCESS, "create returns after reentrant destroy");
    CHECK(sink.destroy_called, "first queued callback destroys its own session");
    CHECK(sink.destroy_result == RAC_SUCCESS, "reentrant destroy succeeds");
    CHECK(sink.callback_count == 1, "reentrant destroy stops the remaining payload batch");
    CHECK(sink.tool_call_count == 0, "destroyed session publishes no queued tool call");

    cleanup_environment();
    return 0;
}

int test_nested_reentrant_step_and_destroy_does_not_deadlock() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny.",
    });

    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    NestedStepDestroySink sink;
    sink.handle = &handle;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), nested_step_destroy_callback, &sink, capture_session_handle,
        &handle);

    CHECK(rc == RAC_SUCCESS, "create returns after nested reentrant step/destroy");
    CHECK(sink.step_started, "tool callback starts a nested step");
    CHECK(sink.step_serialized, "nested step request serializes");
    CHECK(sink.step_result == RAC_SUCCESS, "nested step returns after nested destroy");
    CHECK(sink.destroy_called, "nested step callback destroys its session");
    CHECK(sink.destroy_result == RAC_SUCCESS, "nested reentrant destroy succeeds");
    CHECK(sink.tool_call_count == 1, "only the admitted outer tool call is published");
    CHECK(sink.final_result_count == 0, "destroy suppresses the nested queued final result");

    cleanup_environment();
    return 0;
}

int test_cancel_before_tool_dispatch_prevents_host_side_effect() {
    if (!load_mock_llm())
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
    });

    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    CancelBeforeToolDispatchSink sink;
    sink.handle = &handle;
    const rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), cancel_before_tool_dispatch_callback, &sink,
        capture_session_handle, &handle);

    CHECK(rc == RAC_SUCCESS, "create returns after cancel from earlier queued event");
    CHECK(sink.cancel_called, "LLM event cancels before queued tool dispatch");
    CHECK(sink.cancel_result == RAC_SUCCESS, "cancel before tool dispatch succeeds");
    CHECK(sink.callback_count == 1, "cancelled queued tool event is not published");
    CHECK(sink.tool_side_effect_count == 0, "cancel prevents host tool side effects");

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
    rac_result_t rc = rac_tool_calling_session_create_proto(
        bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
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

// RUN-80 (review follow-up): the session path is a PARALLEL grammar wiring to the
// run loop. Prove the capability gate here too: a QHexRT-framework session's
// decision generate is constrained with "toolcall_opt:<names>", while a
// non-grammar engine gets none.
int test_session_grammar_gated_on_framework() {
    // Grammar backend (QHexRT): decision generate is grammar-constrained.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({"Paris is the capital of France."});
    {
        EventSink sink;
        auto request = make_request("What is the capital of France?");
        *request.add_tools() = make_calculate_tool();  // tools: get_weather, calculate
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        const rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_SUCCESS, "grammar-backend session create");
        const auto grammars = generated_grammars();
        CHECK(grammars.size() == 1, "one decision generate");
        if (grammars.size() == 1) {
            CHECK(grammars[0] == "toolcall_opt:get_weather,calculate",
                  "session decision turn is grammar-constrained on QHexRT");
        }
        rac_tool_calling_session_destroy_proto(handle);
    }

    // Non-grammar backend (llama.cpp): no grammar attached.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP))
        return 1;
    set_responses({"Paris is the capital of France."});
    {
        EventSink sink;
        auto request = make_request("What is the capital of France?");
        *request.add_tools() = make_calculate_tool();
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        const rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_SUCCESS, "non-grammar session create");
        const auto grammars = generated_grammars();
        CHECK(grammars.size() == 1, "one generate");
        if (grammars.size() == 1) {
            CHECK(grammars[0].empty(), "non-grammar session gets no grammar");
        }
        rac_tool_calling_session_destroy_proto(handle);
    }

    // QHexRT + tool_choice=NONE: no grammar attached (calls are forbidden).
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({"A direct answer."});
    {
        EventSink sink;
        auto request = make_request("Answer directly.");
        *request.add_tools() = make_calculate_tool();
        request.set_tool_choice(runanywhere::v1::TOOL_CHOICE_MODE_NONE);
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        const rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_SUCCESS, "NONE session create");
        const auto grammars = generated_grammars();
        CHECK(grammars.size() == 1, "NONE generates once");
        if (grammars.size() == 1) {
            CHECK(grammars[0].empty(), "session NONE attaches no grammar");
        }
        rac_tool_calling_session_destroy_proto(handle);
    }

    // QHexRT tool-call then synthesis: decision turn constrained, synthesis not.
    if (!load_mock_llm(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT))
        return 1;
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "The weather in Tokyo is sunny.",
    });
    {
        EventSink sink;
        auto request = make_request("Weather in Tokyo?");  // one tool: get_weather
        std::vector<uint8_t> bytes;
        serialize(request, &bytes);
        uint64_t handle = 0;
        rac_result_t rc = rac_tool_calling_session_create_proto(
            bytes.data(), bytes.size(), sink_callback, &sink, capture_session_handle, &handle);
        CHECK(rc == RAC_SUCCESS, "synthesis session create");
        using EvCase = runanywhere::v1::ToolCallingSessionEvent::KindCase;
        const auto* tool_ev = sink.find_first(EvCase::kToolCall);
        CHECK(tool_ev != nullptr, "paused on tool_call");
        runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
        step.set_session_handle(handle);
        if (tool_ev)
            step.set_tool_call_id(tool_ev->tool_call().id());
        step.set_result_json(R"({"temp":25})");
        std::vector<uint8_t> step_bytes;
        serialize(step, &step_bytes);
        rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
        CHECK(rc == RAC_SUCCESS, "step_with_result ok");
        const auto grammars = generated_grammars();
        CHECK(grammars.size() == 2, "decision + synthesis generations");
        if (grammars.size() == 2) {
            CHECK(grammars[0] == "toolcall_opt:get_weather", "session decision turn constrained");
            CHECK(grammars[1].empty(), "session synthesis turn unconstrained");
        }
        rac_tool_calling_session_destroy_proto(handle);
    }

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
        test_max_tool_calls_allows_final_synthesis();
        test_forced_tool_name_only_promotes_session_to_specific();
        test_none_vetoes_forced_name_in_session();
        test_none_blocks_session_call_when_validation_disabled();
        test_session_grammar_gated_on_framework();
        test_forced_target_blocks_wrong_session_call_when_validation_disabled();
        test_specific_session_target_must_be_nonempty_and_present();
        test_specific_and_required_sessions_reject_initial_no_call();
        test_step_rejects_mismatched_tool_call_id_without_mutation();
        test_reentrant_destroy_stops_remaining_queued_events();
        test_nested_reentrant_step_and_destroy_does_not_deadlock();
        test_cancel_before_tool_dispatch_prevents_host_side_effect();
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
