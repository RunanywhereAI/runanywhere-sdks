/**
 * @file test_llm_proto_service.cpp
 * @brief Generated-proto LLM ABI tests over lifecycle-owned backend state.
 */

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "sdk_events.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                    \
    do {                                                                                      \
        ++test_count;                                                                         \
        if (!(cond)) {                                                                        \
            ++fail_count;                                                                     \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__,      \
                         #cond);                                                             \
        } else {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                     \
        }                                                                                     \
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
    if (!model_id || !out_impl) return RAC_ERROR_NULL_POINTER;
    auto* impl = new MockLlm();
    impl->model_path = model_id;
    *out_impl = impl;
    return RAC_SUCCESS;
}

rac_result_t mock_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) return RAC_ERROR_NULL_POINTER;
    auto* mock = static_cast<MockLlm*>(impl);
    mock->model_path = model_path;
    mock->initialized = true;
    return RAC_SUCCESS;
}

rac_result_t mock_generate(void* impl,
                           const char* prompt,
                           const rac_llm_options_t* options,
                           rac_llm_result_t* out_result) {
    if (!impl || !prompt || !out_result) return RAC_ERROR_NULL_POINTER;
    const char* text = "<think>plan</think>final {\"ok\":true}";
    out_result->text = dup_cstr(text);
    if (!out_result->text) return RAC_ERROR_OUT_OF_MEMORY;
    out_result->prompt_tokens = 3;
    out_result->completion_tokens = options && options->max_tokens > 0 ? 12 : 10;
    out_result->total_tokens = out_result->prompt_tokens + out_result->completion_tokens;
    out_result->time_to_first_token_ms = 7;
    out_result->total_time_ms = 21;
    out_result->tokens_per_second = 42.0f;
    return RAC_SUCCESS;
}

rac_result_t mock_generate_stream(void* impl,
                                  const char* prompt,
                                  const rac_llm_options_t*,
                                  rac_llm_stream_callback_fn callback,
                                  void* user_data) {
    if (!impl || !prompt || !callback) return RAC_ERROR_NULL_POINTER;
    auto* mock = static_cast<MockLlm*>(impl);
    if (callback("alpha", user_data) != RAC_TRUE) {
        return RAC_ERROR_STREAM_CANCELLED;
    }

    {
        std::lock_guard<std::mutex> lock(g_stream_mutex);
        g_first_token_seen = true;
    }
    g_stream_cv.notify_all();

    if (g_wait_for_cancel) {
        std::unique_lock<std::mutex> lock(g_stream_mutex);
        g_stream_cv.wait_for(lock, std::chrono::seconds(2), [mock] {
            return mock->cancelled;
        });
        return RAC_ERROR_CANCELLED;
    }

    if (callback("beta", user_data) != RAC_TRUE) {
        return RAC_ERROR_STREAM_CANCELLED;
    }
    return RAC_SUCCESS;
}

rac_result_t mock_cancel(void* impl) {
    if (!impl) return RAC_ERROR_NULL_POINTER;
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

const uint32_t g_formats[] = {
    static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF)};

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
    if (out->empty()) return true;
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
    model.set_is_downloaded(true);
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
    const bool ok = rc == RAC_SUCCESS && parse_buffer(out, &result) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

std::vector<uint8_t> generate_request_bytes(const char* prompt) {
    runanywhere::v1::LLMGenerateRequest request;
    request.set_prompt(prompt);
    request.set_max_tokens(12);
    request.set_temperature(0.2f);
    request.set_top_p(0.9f);
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

int terminal_count(const CapturedStream& capture, std::string* finish_reason) {
    int count = 0;
    for (const auto& bytes : capture.events) {
        runanywhere::v1::LLMStreamEvent event;
        if (!event.ParseFromArray(bytes.data(), static_cast<int>(bytes.size()))) {
            continue;
        }
        if (event.is_final()) {
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
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "generate returns parsable LLMGenerationResult");
    CHECK(result.text() == "final {\"ok\":true}", "generate strips thinking from text");
    CHECK(result.thinking_content() == "plan", "generate extracts thinking content");
    CHECK(result.model_used() == "lifecycle.llm", "generate reports lifecycle model id");
    CHECK(result.tokens_generated() == 12, "generate reports completion tokens");
    CHECK(result.thinking_tokens() > 0, "generate splits thinking tokens");
    CHECK(result.response_tokens() > 0, "generate splits response tokens");
    CHECK(result.has_json_output() && result.json_output() == "{\"ok\":true}",
          "generate extracts structured JSON");
    CHECK(result.finish_reason() == "stop", "generate reports stop finish reason");
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
    std::string finish;
    CHECK(terminal_count(capture, &finish) == 1, "stream emits exactly one terminal event");
    CHECK(finish == "stop", "stream terminal finish reason is stop");
    cleanup_environment();
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
        g_stream_cv.wait_for(lock, std::chrono::seconds(2), [] {
            return g_first_token_seen;
        });
    }

    rac_proto_buffer_t cancel_event;
    rac_proto_buffer_init(&cancel_event);
    const rac_result_t cancel_rc = rac_llm_cancel_proto(&cancel_event);
    runanywhere::v1::SDKEvent event;
    CHECK(cancel_rc == RAC_SUCCESS && parse_buffer(cancel_event, &event),
          "cancel returns parsable SDKEvent");
    CHECK(event.has_cancellation(), "cancel event carries CancellationEvent");
    CHECK(event.cancellation().kind() ==
              runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED,
          "cancel event reports completion");
    rac_proto_buffer_free(&cancel_event);

    worker.join();

    std::string finish;
    CHECK(stream_rc == RAC_SUCCESS, "cancelled stream returns success transport status");
    CHECK(terminal_count(capture, &finish) == 1,
          "cancelled stream emits exactly one terminal event");
    CHECK(finish == "cancelled", "cancelled stream terminal finish reason");
    cleanup_environment();
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_llm_proto_service\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: LLM proto service tests (no protobuf)\n");
    return 0;
#else
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "model registry creates");

    test_request_parse_error();
    test_missing_lifecycle_model();
    test_mocked_generation(registry);
    test_stream_terminal_once(registry);
    test_cancel_stream(registry);

    cleanup_environment();
    rac_model_registry_destroy(registry);
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
