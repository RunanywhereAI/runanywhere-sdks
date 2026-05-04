/**
 * @file rac_llm_proto_service.cpp
 * @brief Lifecycle-owned LLM generated-proto C ABI.
 */

#include "rac/features/llm/rac_llm_service.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "sdk_events.pb.h"
#endif

namespace {

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

using runanywhere::v1::CancellationEventKind;
using runanywhere::v1::EventCategory;
using runanywhere::v1::EventSeverity;
using runanywhere::v1::GenerationEventKind;
using runanywhere::v1::LLMGenerateRequest;
using runanywhere::v1::LLMGenerationResult;
using runanywhere::v1::LLMStreamEvent;
using runanywhere::v1::LLMTokenKind;
using runanywhere::v1::SDKComponent;
using runanywhere::v1::SDKEvent;

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

std::string make_event_id() {
    static std::atomic<uint64_t> counter{0};
    const uint64_t c = counter.fetch_add(1);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu",
                  static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(c));
    return buffer;
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message,
                        rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_event_envelope(SDKEvent* event,
                             EventCategory category,
                             EventSeverity severity) {
    event->set_id(make_event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
}

rac_result_t publish_sdk_event(const SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    return rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
}

void publish_generation_event(GenerationEventKind kind,
                              const char* prompt,
                              const char* token,
                              const char* response,
                              const char* error,
                              const char* model_id,
                              int32_t token_count,
                              int64_t latency_ms) {
    SDKEvent event;
    const bool failed = kind == runanywhere::v1::GENERATION_EVENT_KIND_FAILED;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_LLM,
                            failed ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                   : runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* generation = event.mutable_generation();
    generation->set_kind(kind);
    if (prompt && prompt[0]) {
        generation->set_prompt(prompt);
    }
    if (token && token[0]) {
        generation->set_token(token);
    }
    if (response && response[0]) {
        generation->set_response(response);
    }
    if (error && error[0]) {
        generation->set_error(error);
    }
    if (model_id && model_id[0]) {
        generation->set_model_id(model_id);
    }
    if (token_count > 0) {
        generation->set_tokens_count(token_count);
        generation->set_tokens_used(token_count);
    }
    if (latency_ms > 0) {
        generation->set_latency_ms(latency_ms);
    }
    (void)publish_sdk_event(event);
}

SDKEvent make_cancellation_event(CancellationEventKind kind,
                                 const char* reason,
                                 rac_bool_t user_initiated,
                                 EventSeverity severity) {
    SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_CANCELLATION, severity);
    auto* cancellation = event.mutable_cancellation();
    cancellation->set_kind(kind);
    cancellation->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    cancellation->set_operation_id("llm.generate");
    cancellation->set_reason(reason && reason[0] ? reason : "user_requested");
    cancellation->set_user_initiated(user_initiated == RAC_TRUE);
    return event;
}

rac_llm_options_t options_from_request(const LLMGenerateRequest& request,
                                       const std::string& system_prompt) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    if (request.max_tokens() > 0) {
        options.max_tokens = request.max_tokens();
    }
    if (request.temperature() > 0.0f) {
        options.temperature = request.temperature();
    }
    if (request.top_p() > 0.0f) {
        options.top_p = request.top_p();
    }
    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();
    return options;
}

void set_result_from_raw(const rac::llm::LifecycleLlmRef& ref,
                         const rac_llm_result_t& raw,
                         const char* response,
                         size_t response_len,
                         const char* thinking,
                         size_t thinking_len,
                         int32_t thinking_tokens,
                         int32_t response_tokens,
                         LLMGenerationResult* out) {
    out->set_text(response ? std::string(response, response_len) : std::string());
    if (thinking && thinking_len > 0) {
        out->set_thinking_content(std::string(thinking, thinking_len));
    }
    out->set_input_tokens(raw.prompt_tokens);
    out->set_tokens_generated(raw.completion_tokens);
    out->set_total_tokens(raw.total_tokens);
    out->set_model_used(ref.model_id ? ref.model_id : "");
    out->set_generation_time_ms(static_cast<double>(raw.total_time_ms));
    if (raw.time_to_first_token_ms > 0) {
        out->set_ttft_ms(static_cast<double>(raw.time_to_first_token_ms));
    }
    out->set_tokens_per_second(static_cast<double>(raw.tokens_per_second));
    if (ref.framework_name && ref.framework_name[0]) {
        out->set_framework(ref.framework_name);
    }
    out->set_finish_reason("stop");
    out->set_thinking_tokens(thinking_tokens);
    out->set_response_tokens(response_tokens);
    out->set_executed_on(runanywhere::v1::EXECUTION_TARGET_ON_DEVICE);

    auto* perf = out->mutable_performance();
    perf->set_latency_ms(raw.total_time_ms);
    perf->set_throughput_tokens_per_sec(raw.tokens_per_second);
    perf->set_prompt_tokens(raw.prompt_tokens);
    perf->set_completion_tokens(raw.completion_tokens);
}

void set_structured_output_if_present(const char* response, LLMGenerationResult* out) {
    if (!response || !out) {
        return;
    }
    rac_structured_output_validation_t validation{};
    if (rac_structured_output_validate(response, nullptr, &validation) == RAC_SUCCESS) {
        if (validation.is_valid == RAC_TRUE && validation.extracted_json) {
            out->set_json_output(validation.extracted_json);
            auto* structured = out->mutable_structured_output_validation();
            structured->set_is_valid(true);
            structured->set_contains_json(true);
            structured->set_raw_output(response);
            structured->set_extracted_json(validation.extracted_json);
        } else if (validation.error_message) {
            auto* structured = out->mutable_structured_output_validation();
            structured->set_is_valid(false);
            structured->set_contains_json(false);
            structured->set_raw_output(response);
            structured->set_error_message(validation.error_message);
        }
    }
    rac_structured_output_validation_free(&validation);
}

struct ProtoStreamContext {
    rac_llm_stream_proto_callback_fn callback = nullptr;
    void* user_data = nullptr;
    rac::llm::LifecycleLlmRef* ref = nullptr;
    uint64_t seq = 0;
    bool terminal_sent = false;
    bool first_token_sent = false;
    int64_t started_ms = 0;
    int32_t token_count = 0;
    std::string full_text;
};

void dispatch_stream_event(ProtoStreamContext* ctx,
                           const char* token,
                           bool is_final,
                           LLMTokenKind kind,
                           const char* finish_reason,
                           const char* error_message) {
    if (!ctx || !ctx->callback) {
        return;
    }

    LLMStreamEvent event;
    event.set_seq(++ctx->seq);
    event.set_timestamp_us(now_us());
    if (token) {
        event.set_token(token);
    }
    event.set_is_final(is_final);
    event.set_kind(kind);
    if (finish_reason && finish_reason[0]) {
        event.set_finish_reason(finish_reason);
    }
    if (error_message && error_message[0]) {
        event.set_error_message(error_message);
    }

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return;
    }
    ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
}

void dispatch_terminal_once(ProtoStreamContext* ctx,
                            const char* finish_reason,
                            const char* error_message) {
    if (!ctx || ctx->terminal_sent) {
        return;
    }
    ctx->terminal_sent = true;
    dispatch_stream_event(ctx, "", true, runanywhere::v1::LLM_TOKEN_KIND_ANSWER,
                          finish_reason, error_message);
}

rac_bool_t stream_token_callback(const char* token, void* user_data) {
    auto* ctx = static_cast<ProtoStreamContext*>(user_data);
    if (!ctx || !ctx->ref) {
        return RAC_FALSE;
    }
    if (rac::llm::lifecycle_llm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    const char* safe_token = token ? token : "";
    ctx->full_text += safe_token;
    ctx->token_count += safe_token[0] ? 1 : 0;

    if (!ctx->first_token_sent && safe_token[0]) {
        ctx->first_token_sent = true;
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED,
                                 nullptr, safe_token, nullptr, nullptr,
                                 ctx->ref->model_id, 1, now_ms() - ctx->started_ms);
    }
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED,
                             nullptr, safe_token, nullptr, nullptr,
                             ctx->ref->model_id, ctx->token_count, 0);
    dispatch_stream_event(ctx, safe_token, false, runanywhere::v1::LLM_TOKEN_KIND_ANSWER,
                          nullptr, nullptr);
    return RAC_TRUE;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

rac_result_t rac_llm_generate_proto(const uint8_t* request_proto_bytes,
                                    size_t request_proto_size,
                                    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "LLMGenerateRequest bytes are empty or too large");
    }

    LLMGenerateRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse LLMGenerateRequest");
    }
    if (request.prompt().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "LLMGenerateRequest.prompt is required");
    }

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED,
                             request.prompt().c_str(), nullptr, nullptr, nullptr,
                             ref.model_id, 0, 0);

    const std::string system_prompt = request.system_prompt();
    rac_llm_options_t options = options_from_request(request, system_prompt);
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t raw{};
    const int64_t started = now_ms();
    rc = (ref.ops && ref.ops->generate)
             ? ref.ops->generate(ref.impl, request.prompt().c_str(), &options, &raw)
             : RAC_ERROR_NOT_SUPPORTED;
    const int64_t elapsed = now_ms() - started;

    if (rc != RAC_SUCCESS) {
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, nullptr,
                                 rac_error_message(rc), ref.model_id, 0, elapsed);
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    const char* raw_text = raw.text ? raw.text : "";
    (void)rac_llm_extract_thinking(raw_text, &response, &response_len, &thinking, &thinking_len);

    int32_t thinking_tokens = 0;
    int32_t response_tokens = raw.completion_tokens;
    (void)rac_llm_split_thinking_tokens(raw.completion_tokens, response, thinking,
                                        &thinking_tokens, &response_tokens);

    LLMGenerationResult result;
    set_result_from_raw(ref, raw, response, response_len, thinking, thinking_len,
                        thinking_tokens, response_tokens, &result);
    set_structured_output_if_present(response, &result);

    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED,
                             request.prompt().c_str(), nullptr, response, nullptr,
                             ref.model_id, raw.completion_tokens,
                             raw.total_time_ms > 0 ? raw.total_time_ms : elapsed);

    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_llm_generate_stream_proto(const uint8_t* request_proto_bytes,
                                           size_t request_proto_size,
                                           rac_llm_stream_proto_callback_fn callback,
                                           void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    LLMGenerateRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.prompt().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!ref.ops || !ref.ops->generate_stream) {
        rac::llm::release_lifecycle_llm(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STARTED,
                             request.prompt().c_str(), nullptr, nullptr, nullptr,
                             ref.model_id, 0, 0);

    const std::string system_prompt = request.system_prompt();
    rac_llm_options_t options = options_from_request(request, system_prompt);
    options.streaming_enabled = RAC_TRUE;

    ProtoStreamContext ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.started_ms = now_ms();

    rc = ref.ops->generate_stream(ref.impl, request.prompt().c_str(), &options,
                                  stream_token_callback, &ctx);

    const bool cancelled =
        rac::llm::lifecycle_llm_cancel_requested(&ref) ||
        rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        dispatch_terminal_once(&ctx, "cancelled", nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCELLED,
                                 request.prompt().c_str(), nullptr, ctx.full_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_terminal_once(&ctx, "error", rac_error_message(rc));
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, ctx.full_text.c_str(),
                                 rac_error_message(rc), ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms);
    } else {
        dispatch_terminal_once(&ctx, "stop", nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STREAM_COMPLETED,
                                 request.prompt().c_str(), nullptr, ctx.full_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms);
    }

    rac::llm::release_lifecycle_llm(&ref);
    return rc;
#endif
}

rac_result_t rac_llm_cancel_proto(rac_proto_buffer_t* out_event) {
    if (!out_event) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_event);
#else
    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        SDKEvent failed = make_cancellation_event(
            runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
            "no lifecycle LLM model loaded", RAC_TRUE,
            runanywhere::v1::EVENT_SEVERITY_ERROR);
        (void)publish_sdk_event(failed);
        return rac_proto_buffer_set_error(out_event, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::request_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCEL_REQUESTED,
                             nullptr, nullptr, nullptr, nullptr, ref.model_id, 0, 0);
    if (ref.ops && ref.ops->cancel) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }

    SDKEvent event = make_cancellation_event(
        rc == RAC_SUCCESS ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                          : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
        rc == RAC_SUCCESS ? "user_requested" : rac_error_message(rc),
        RAC_TRUE,
        rc == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                          : runanywhere::v1::EVENT_SEVERITY_ERROR);
    (void)publish_sdk_event(event);
    rac_result_t copy_rc = copy_proto(event, out_event);
    rac::llm::release_lifecycle_llm(&ref);
    return rc == RAC_SUCCESS ? copy_rc : rc;
#endif
}

}  // extern "C"
