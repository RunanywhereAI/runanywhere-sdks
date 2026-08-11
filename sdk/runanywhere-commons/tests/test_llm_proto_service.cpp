/**
 * @file test_llm_proto_service.cpp
 * @brief Generated-proto LLM ABI tests over lifecycle-owned backend state.
 */

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "sdk_events.pb.h"
#include "structured_output.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct MockLlm {
    std::string model_path;
    bool initialized{false};
    bool cancelled{false};
};

std::mutex g_stream_mutex;
std::condition_variable g_stream_cv;
bool g_wait_for_cancel = false;
bool g_first_token_seen = false;

char* dup_cstr(const char* value) {
    const size_t len = std::strlen(value);
    char* out = static_cast<char*>(std::malloc(len + 1));
    if (!out) {
        return nullptr;
    }
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

rac_result_t mock_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path)
        return RAC_ERROR_NULL_POINTER;
    auto* mock = static_cast<MockLlm*>(impl);
    mock->model_path = model_path;
    mock->initialized = true;
    return RAC_SUCCESS;
}

// The prompt exactly as the engine received it, plus the disable_thinking flag
// that rode alongside it. Both are needed to tell "the request was honored" from
// "commons edited the prompt": the flag must always reach the backend, while the
// "/no_think" prefix must appear only for a model that speaks it.
std::mutex g_prompt_mutex;
std::string g_last_prompt;
bool g_last_disable_thinking = false;

void record_prompt(const char* prompt, const rac_llm_options_t* options) {
    std::lock_guard<std::mutex> lock(g_prompt_mutex);
    g_last_prompt = prompt != nullptr ? prompt : "";
    g_last_disable_thinking = options != nullptr && options->disable_thinking == RAC_TRUE;
}

rac_result_t mock_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                           rac_llm_result_t* out_result) {
    if (!impl || !prompt || !out_result)
        return RAC_ERROR_NULL_POINTER;
    record_prompt(prompt, options);
    const char* text = std::strstr(prompt, "empty response") != nullptr
                           ? " \n\t "
                           : "<think>plan</think>final {\"ok\":true}";
    out_result->text = dup_cstr(text);
    if (!out_result->text)
        return RAC_ERROR_OUT_OF_MEMORY;
    out_result->prompt_tokens = 3;
    out_result->completion_tokens = options && options->max_tokens > 0 ? 12 : 10;
    out_result->total_tokens = out_result->prompt_tokens + out_result->completion_tokens;
    out_result->time_to_first_token_ms = 7;
    out_result->total_time_ms = 21;
    out_result->tokens_per_second = 42.0f;
    return RAC_SUCCESS;
}

rac_result_t mock_generate_stream(void* impl, const char* prompt, const rac_llm_options_t*,
                                  rac_llm_stream_callback_fn callback, void* user_data) {
    if (!impl || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;
    auto* mock = static_cast<MockLlm*>(impl);
    if (std::strstr(prompt, "hidden-thinking-stream") != nullptr) {
        for (const char* token : {"<think>alpha", "beta", "gamma"}) {
            if (callback(token, RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
                return RAC_ERROR_STREAM_CANCELLED;
            }
        }
        return RAC_SUCCESS;
    }
    if (std::strstr(prompt, "thinking-stream") != nullptr) {
        if (callback("<think>plan</think>done", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
            return RAC_ERROR_STREAM_CANCELLED;
        }
        return RAC_SUCCESS;
    }
    if (std::strstr(prompt, "structured-stream-json") != nullptr) {
        if (callback("{\"ok\"", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
            return RAC_ERROR_STREAM_CANCELLED;
        }
        if (callback(":true}", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
            return RAC_ERROR_STREAM_CANCELLED;
        }
        return RAC_SUCCESS;
    }
    // Optional branch that emits a native final+"stop" for tests that need a
    // genuine producer terminal signal. Default path intentionally does NOT
    // emit a final so finish_reason stays "unknown" with no native signal.
    if (std::strstr(prompt, "native-final-stop") != nullptr) {
        if (callback("alpha", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
            return RAC_ERROR_STREAM_CANCELLED;
        }
        if (callback("", RAC_TRUE, "stop", user_data) != RAC_TRUE) {
            return RAC_ERROR_STREAM_CANCELLED;
        }
        return RAC_SUCCESS;
    }
    if (callback("alpha", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
        return RAC_ERROR_STREAM_CANCELLED;
    }

    {
        std::lock_guard<std::mutex> lock(g_stream_mutex);
        g_first_token_seen = true;
    }
    g_stream_cv.notify_all();

    if (g_wait_for_cancel) {
        std::unique_lock<std::mutex> lock(g_stream_mutex);
        g_stream_cv.wait_for(lock, std::chrono::seconds(2), [mock] { return mock->cancelled; });
        return RAC_ERROR_CANCELLED;
    }

    if (callback("beta", RAC_FALSE, nullptr, user_data) != RAC_TRUE) {
        return RAC_ERROR_STREAM_CANCELLED;
    }
    return RAC_SUCCESS;
}

rac_result_t mock_cancel(void* impl) {
    if (!impl)
        return RAC_ERROR_NULL_POINTER;
    auto* mock = static_cast<MockLlm*>(impl);
    {
        std::lock_guard<std::mutex> lock(g_stream_mutex);
        mock->cancelled = true;
    }
    g_stream_cv.notify_all();
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
    ops.generate_stream = mock_generate_stream;
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

void reset_mock_stream_state() {
    std::lock_guard<std::mutex> lock(g_stream_mutex);
    g_wait_for_cancel = false;
    g_first_token_seen = false;
}

void cleanup_environment() {
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();
    (void)rac_plugin_unregister("llamacpp");
    reset_mock_stream_state();
}

runanywhere::v1::ModelInfo build_llm_model() {
    runanywhere::v1::ModelInfo model;
    model.set_id("lifecycle.llm");
    model.set_name("Lifecycle LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/lifecycle-test.gguf");
    // ModelInfo.is_downloaded (tag 32) was deleted outright: registry_status
    // is now the single downloaded-ness signal (idl/model_types.proto).
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    model.set_is_available(true);
    return model;
}

bool register_model(rac_model_registry_handle_t registry) {
    std::vector<uint8_t> bytes;
    runanywhere::v1::ModelInfo model = build_llm_model();
    return serialize(model, &bytes) &&
           rac_model_registry_register_proto(registry, bytes.data(), bytes.size()) == RAC_SUCCESS;
}

bool load_mock_model(rac_model_registry_handle_t registry) {
    cleanup_environment();
    if (rac_plugin_register(&g_mock_vtable) != RAC_SUCCESS) {
        return false;
    }
    if (!register_model(registry)) {
        return false;
    }

    runanywhere::v1::ModelLoadRequest load;
    load.set_model_id("lifecycle.llm");
    std::vector<uint8_t> bytes;
    if (!serialize(load, &bytes)) {
        return false;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    const bool ok = rc == RAC_SUCCESS && parse_buffer(out, &result) && result.has_error() == false;
    rac_proto_buffer_free(&out);
    return ok;
}

std::vector<uint8_t> generate_request_bytes(const char* prompt) {
    runanywhere::v1::LLMGenerateRequest request;
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the current turn is the last message.
    auto* message = request.add_messages();
    message->set_role(runanywhere::v1::MESSAGE_ROLE_USER);
    message->set_content(prompt);
    auto* options = request.mutable_options();
    options->set_max_output_tokens(12);
    options->set_temperature(0.2f);
    options->set_top_p(0.9f);
    std::vector<uint8_t> bytes;
    (void)serialize(request, &bytes);
    return bytes;
}

struct CapturedStream {
    std::vector<std::vector<uint8_t>> events;
};

void stream_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* capture = static_cast<CapturedStream*>(user_data);
    capture->events.emplace_back(bytes, bytes + size);
}

// is_final/kind were deleted from LLMStreamEvent (idl/llm_service.proto):
// event_kind is now the sole discriminator for a terminal event
// (COMPLETED or ERROR), and finish_reason widened from a bare string to the
// FinishReason enum.
bool is_terminal_event_kind(runanywhere::v1::LLMStreamEventKind kind) {
    return kind == runanywhere::v1::LLM_STREAM_EVENT_KIND_COMPLETED ||
           kind == runanywhere::v1::LLM_STREAM_EVENT_KIND_ERROR;
}

int terminal_count(const CapturedStream& capture, runanywhere::v1::FinishReason* finish_reason) {
    int count = 0;
    for (const auto& bytes : capture.events) {
        runanywhere::v1::LLMStreamEvent event;
        if (!event.ParseFromArray(bytes.data(), static_cast<int>(bytes.size()))) {
            continue;
        }
        if (is_terminal_event_kind(event.event_kind())) {
            ++count;
            if (finish_reason) {
                *finish_reason = event.finish_reason();
            }
        }
    }
    return count;
}

int test_request_parse_error() {
    cleanup_environment();
    const uint8_t invalid[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_llm_generate_proto(invalid, sizeof(invalid), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "invalid request returns decoding error");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR, "invalid request marks buffer error");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_missing_lifecycle_model() {
    cleanup_environment();
    std::vector<uint8_t> bytes = generate_request_bytes("hello");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_llm_generate_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NOT_INITIALIZED, "missing lifecycle LLM returns not initialized");
    CHECK(out.status == RAC_ERROR_NOT_INITIALIZED, "missing lifecycle marks buffer error");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_mocked_generation(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads");
    std::vector<uint8_t> bytes = generate_request_bytes("answer as json");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_llm_generate_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::LLMGenerationResult result;
    CHECK(rc == RAC_SUCCESS, "generate returns success");
    CHECK(parse_buffer(out, &result), "generate returns parsable LLMGenerationResult");
    CHECK(result.text() == "final {\"ok\":true}", "generate strips thinking from text");
    CHECK(result.thinking_content() == "plan", "generate extracts thinking content");
    CHECK(result.model_used() == "lifecycle.llm", "generate reports lifecycle model id");
    CHECK(result.usage().output_tokens() == 12, "generate reports completion tokens");
    CHECK(result.thinking_tokens() > 0, "generate splits thinking tokens");
    CHECK(result.response_tokens() > 0, "generate splits response tokens");
    CHECK(result.has_json_output() && result.json_output() == "{\"ok\":true}",
          "generate extracts structured JSON");
    CHECK(result.finish_reason() == runanywhere::v1::FINISH_REASON_LENGTH,
          "generate reports length finish reason when completion_tokens == max_tokens");
    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_empty_generation_skips_structured_validation(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for empty response");
    std::vector<uint8_t> bytes = generate_request_bytes("empty response");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_llm_generate_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::LLMGenerationResult result;
    CHECK(rc == RAC_SUCCESS, "empty generation returns success");
    CHECK(parse_buffer(out, &result), "empty generation returns parsable result");
    CHECK(!result.has_json_output(), "empty generation has no JSON output");
    CHECK(!result.has_structured_output_validation(),
          "empty generation skips structured-output validation");
    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

int test_stream_terminal_once(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for stream");
    std::vector<uint8_t> bytes = generate_request_bytes("stream please");
    CapturedStream capture;
    const rac_result_t rc =
        rac_llm_generate_stream_proto(bytes.data(), bytes.size(), stream_callback, &capture);
    CHECK(rc == RAC_SUCCESS, "stream generation succeeds");
    CHECK(capture.events.size() == 3, "stream emits two tokens plus terminal");
    runanywhere::v1::FinishReason finish = runanywhere::v1::FINISH_REASON_UNSPECIFIED;
    CHECK(terminal_count(capture, &finish) == 1, "stream emits exactly one terminal event");
    // The mock backend implements rac_llm_service_ops_t::generate_stream
    // directly (it isn't the real llamacpp/QHexRT adapter), so it never
    // reports the commons-internal "saw a native is_final" side channel
    // (rac_llm_stream_report_final_signal(), see rac_llm_service.h).
    // finish_reason is honestly unspecified rather than a fabricated "stop"
    // when there's zero evidence the backend actually finished cleanly
    // ("unknown" maps to FINISH_REASON_UNSPECIFIED via finish_reason_from_string).
    CHECK(finish == runanywhere::v1::FINISH_REASON_UNSPECIFIED,
          "stream terminal finish reason is unspecified with no native signal");
    cleanup_environment();
    return 0;
}

int test_stream_producer_finish_reason_stop(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for producer-final stream");
    std::vector<uint8_t> bytes = generate_request_bytes("native-final-stop please");
    CapturedStream capture;
    const rac_result_t rc =
        rac_llm_generate_stream_proto(bytes.data(), bytes.size(), stream_callback, &capture);
    CHECK(rc == RAC_SUCCESS, "producer-final stream generation succeeds");
    runanywhere::v1::FinishReason finish = runanywhere::v1::FINISH_REASON_UNSPECIFIED;
    CHECK(terminal_count(capture, &finish) == 1, "producer-final stream emits one terminal");
    CHECK(finish == runanywhere::v1::FINISH_REASON_STOP,
          "producer finish_reason from widened callback is stop");
    cleanup_environment();
    return 0;
}

int test_stream_thinking_envelope(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for thinking stream");

    runanywhere::v1::LLMGenerateRequest request;
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the current turn is the last message.
    auto* message = request.add_messages();
    message->set_role(runanywhere::v1::MESSAGE_ROLE_USER);
    message->set_content("thinking-stream");
    request.mutable_options()->mutable_reasoning()->set_include_in_output(true);
    request.set_request_id("think-req");
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "thinking stream request serializes");

    CapturedStream capture;
    const rac_result_t rc =
        rac_llm_generate_stream_proto(bytes.data(), bytes.size(), stream_callback, &capture);
    CHECK(rc == RAC_SUCCESS, "thinking stream generation succeeds");

    bool saw_thinking = false;
    bool saw_answer = false;
    bool saw_terminal_result = false;
    for (const auto& event_bytes : capture.events) {
        runanywhere::v1::LLMStreamEvent event;
        CHECK(event.ParseFromArray(event_bytes.data(), static_cast<int>(event_bytes.size())),
              "thinking stream event parses");
        // kind/is_final were deleted from LLMStreamEvent (idl/llm_service.proto):
        // event_kind is now the sole discriminator for every event category.
        if (event.event_kind() == runanywhere::v1::LLM_STREAM_EVENT_KIND_THINKING) {
            saw_thinking = true;
            CHECK(event.token() == "plan", "thinking token strips tags");
            CHECK(event.request_id() == "think-req", "thinking event carries request id");
        }
        if (event.event_kind() == runanywhere::v1::LLM_STREAM_EVENT_KIND_TOKEN) {
            saw_answer = true;
            CHECK(event.token() == "done", "answer token strips thinking block");
        }
        if (event.event_kind() == runanywhere::v1::LLM_STREAM_EVENT_KIND_COMPLETED) {
            saw_terminal_result = event.has_result();
            CHECK(event.result().text() == "done", "terminal result carries answer text");
            CHECK(event.result().thinking_content() == "plan",
                  "terminal result carries thinking content");
        }
    }

    CHECK(saw_thinking, "stream emits generated thinking envelope");
    CHECK(saw_answer, "stream emits answer envelope after thinking");
    CHECK(saw_terminal_result, "stream emits terminal result envelope");
    cleanup_environment();
    return 0;
}

int test_hidden_thinking_counts_toward_length(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for hidden thinking stream");

    runanywhere::v1::LLMGenerateRequest request;
    // LLMGenerateRequest.prompt was deleted in favor of `repeated ChatMessage
    // messages` (idl/llm_service.proto): the current turn is the last message.
    auto* message = request.add_messages();
    message->set_role(runanywhere::v1::MESSAGE_ROLE_USER);
    message->set_content("hidden-thinking-stream");
    request.mutable_options()->set_max_output_tokens(3);
    request.mutable_options()->mutable_reasoning()->set_include_in_output(false);
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "hidden thinking stream request serializes");

    CapturedStream capture;
    const rac_result_t rc =
        rac_llm_generate_stream_proto(bytes.data(), bytes.size(), stream_callback, &capture);
    CHECK(rc == RAC_SUCCESS, "hidden thinking stream generation succeeds");

    int non_terminal_events = 0;
    bool saw_terminal = false;
    for (const auto& event_bytes : capture.events) {
        runanywhere::v1::LLMStreamEvent event;
        CHECK(event.ParseFromArray(event_bytes.data(), static_cast<int>(event_bytes.size())),
              "hidden thinking stream event parses");
        // is_final was deleted from LLMStreamEvent (idl/llm_service.proto);
        // event_kind is now the sole discriminator for the terminal event.
        if (!is_terminal_event_kind(event.event_kind())) {
            ++non_terminal_events;
            continue;
        }
        saw_terminal = true;
        CHECK(event.finish_reason() == runanywhere::v1::FINISH_REASON_LENGTH,
              "hidden thinking exhaustion reports length finish reason");
        CHECK(event.has_result(), "hidden thinking terminal carries result");
        CHECK(event.result().text().empty(), "hidden thinking terminal has no answer text");
        CHECK(event.result().thinking_content() == "alphabetagamma",
              "hidden thinking terminal preserves reasoning content");
        CHECK(event.result().usage().output_tokens() == 3,
              "hidden thinking terminal counts suppressed completion segments");
    }
    CHECK(non_terminal_events == 0, "hidden thinking emits no thought events");
    CHECK(saw_terminal, "hidden thinking stream emits terminal result");
    cleanup_environment();
    return 0;
}

// idl/structured_output.proto (API-realignment so-p2) deleted
// StructuredOutputRequest, StructuredOutputStreamEventKind, and
// StructuredOutputStreamEvent outright. Structured GENERATION over an LLM
// prompt/stream is no longer a standalone verb — it flows through
// rac_llm_generate_proto / rac_llm_generate_stream_proto with
// LLMGenerationOptions.structured_output set (see llm_module.cpp). With no
// input message left to build a StructuredOutputRequest from,
// rac_structured_output_generate_proto and
// rac_structured_output_generate_stream_proto both always report the typed
// removal; that is the behavior this test now verifies, in place of the old
// (structurally impossible) round-trip.
int test_structured_generate_proto_reports_removed() {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_structured_output_generate_proto(nullptr, 0, &out);
    CHECK(rc == RAC_ERROR_FEATURE_NOT_AVAILABLE,
          "structured generate reports the removed StructuredOutputRequest verb");
    CHECK(out.status == RAC_ERROR_FEATURE_NOT_AVAILABLE,
          "structured generate buffer carries the typed removal error");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_structured_stream_proto_reports_removed() {
    CapturedStream capture;
    const rac_result_t rc =
        rac_structured_output_generate_stream_proto(nullptr, 0, stream_callback, &capture);
    CHECK(rc == RAC_ERROR_FEATURE_NOT_AVAILABLE,
          "structured stream reports the removed StructuredOutputRequest verb");
    CHECK(capture.events.empty(), "structured stream emits no events once removed");
    return 0;
}

int test_cancel_stream(rac_model_registry_handle_t registry) {
    CHECK(load_mock_model(registry), "mock lifecycle LLM loads for cancel");
    {
        std::lock_guard<std::mutex> lock(g_stream_mutex);
        g_wait_for_cancel = true;
        g_first_token_seen = false;
    }

    std::vector<uint8_t> bytes = generate_request_bytes("stream and cancel");
    CapturedStream capture;
    rac_result_t stream_rc = RAC_ERROR_UNKNOWN;
    std::thread worker([&] {
        stream_rc =
            rac_llm_generate_stream_proto(bytes.data(), bytes.size(), stream_callback, &capture);
    });

    {
        std::unique_lock<std::mutex> lock(g_stream_mutex);
        g_stream_cv.wait_for(lock, std::chrono::seconds(2), [] { return g_first_token_seen; });
    }

    rac_proto_buffer_t cancel_event;
    rac_proto_buffer_init(&cancel_event);
    const rac_result_t cancel_rc = rac_llm_cancel_proto(&cancel_event);
    runanywhere::v1::SDKEvent event;
    CHECK(cancel_rc == RAC_SUCCESS, "cancel returns success");
    CHECK(parse_buffer(cancel_event, &event), "cancel returns parsable SDKEvent");
    CHECK(event.has_cancellation(), "cancel event carries CancellationEvent");
    CHECK(event.cancellation().kind() == runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED,
          "cancel event reports completion");
    rac_proto_buffer_free(&cancel_event);

    worker.join();

    runanywhere::v1::FinishReason finish = runanywhere::v1::FINISH_REASON_UNSPECIFIED;
    CHECK(stream_rc == RAC_SUCCESS, "cancelled stream returns success transport status");
    CHECK(terminal_count(capture, &finish) == 1,
          "cancelled stream emits exactly one terminal event");
    CHECK(finish == runanywhere::v1::FINISH_REASON_CANCELLED,
          "cancelled stream terminal finish reason");
    cleanup_environment();
    return 0;
}

#endif

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_llm_proto_service\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: LLM proto service tests (no protobuf)\n");
        return 0;
#else
        rac_model_registry_handle_t registry = nullptr;
        CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS,
              "model registry create succeeds");
        CHECK(registry != nullptr, "model registry handle is non-null");

        test_request_parse_error();
        test_missing_lifecycle_model();
        test_mocked_generation(registry);
        test_empty_generation_skips_structured_validation(registry);
        test_stream_terminal_once(registry);
        test_stream_producer_finish_reason_stop(registry);
        test_stream_thinking_envelope(registry);
        test_hidden_thinking_counts_toward_length(registry);
        test_structured_generate_proto_reports_removed();
        test_structured_stream_proto_reports_removed();
        test_cancel_stream(registry);

        cleanup_environment();
        rac_model_registry_destroy(registry);
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
