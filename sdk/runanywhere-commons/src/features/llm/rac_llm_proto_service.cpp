/**
 * @file rac_llm_proto_service.cpp
 * @brief Lifecycle-owned LLM generated-proto C ABI.
 */

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/llm/rac_llm_stream_internal.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_options.pb.h"
#include "llm_service.pb.h"
#include "sdk_events.pb.h"
#include "tool_calling.pb.h"
#endif

namespace {

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

using runanywhere::v1::CancellationEventKind;
using runanywhere::v1::ErrorSeverity;
using runanywhere::v1::EventCategory;
using runanywhere::v1::GenerationEventKind;
using runanywhere::v1::LLMGenerateRequest;
using runanywhere::v1::LLMGenerationResult;
using runanywhere::v1::LLMStreamFinalResult;
using runanywhere::v1::SDKEvent;
using runanywhere::v1::TokenKind;

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string make_event_id() {
    static std::atomic<uint64_t> counter{0};
    const uint64_t c = counter.fetch_add(1);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(c));
    return buffer;
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_event_envelope(SDKEvent* event, EventCategory category, ErrorSeverity severity) {
    event->set_id(make_event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

rac_result_t publish_sdk_event(const SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    return rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
}

void publish_generation_event(GenerationEventKind kind, const char* prompt, const char* token,
                              const char* response, const char* error, const char* model_id,
                              int32_t token_count, int64_t latency_ms, int32_t input_tokens = 0) {
    SDKEvent event;
    const bool failed = kind == runanywhere::v1::GENERATION_EVENT_KIND_FAILED;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_LLM,
                            failed ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                   : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_operation_id("llm.generate");
    auto* generation = event.mutable_generation();
    generation->set_kind(kind);
    if ((prompt != nullptr) && prompt[0] != '\0') {
        generation->set_prompt(prompt);
    }
    if ((token != nullptr) && token[0] != '\0') {
        generation->set_token(token);
    }
    if ((response != nullptr) && response[0] != '\0') {
        generation->set_response(response);
    }
    if ((error != nullptr) && error[0] != '\0') {
        generation->set_error(error);
    }
    if ((model_id != nullptr) && model_id[0] != '\0') {
        generation->set_model_id(model_id);
    }
    if (token_count > 0) {
        generation->set_tokens_count(token_count);
        generation->set_tokens_used(token_count);
    }
    if (latency_ms > 0) {
        generation->set_latency_ms(latency_ms);
    }
    if (input_tokens > 0) {
        generation->set_input_tokens(input_tokens);
    }
    (void)publish_sdk_event(event);
}

SDKEvent make_cancellation_event(CancellationEventKind kind, const char* reason,
                                 rac_bool_t user_initiated, ErrorSeverity severity) {
    SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_CANCELLATION, severity);
    event.set_operation_id("llm.generate");
    auto* cancellation = event.mutable_cancellation();
    cancellation->set_kind(kind);
    cancellation->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    cancellation->set_operation_id("llm.generate");
    cancellation->set_reason((reason != nullptr) && reason[0] != '\0' ? reason : "user_requested");
    cancellation->set_user_initiated(user_initiated == RAC_TRUE);
    return event;
}

// idl-005: pick the canonical system_prompt from the embedded
// LLMGenerationOptions when set, falling back to the legacy inline field.
std::string system_prompt_from_request(const LLMGenerateRequest& request) {
    if (request.has_options() && request.options().has_system_prompt() &&
        !request.options().system_prompt().empty()) {
        return request.options().system_prompt();
    }
    return request.system_prompt();
}

// Fills `options` from `request`. The caller-owned `stop_storage`/`stop_ptrs`
// must outlive every generate/generate_stream dispatch that observes
// `options.stop_sequences` — they hold the backing memory the C ABI points
// into. Mirrors RALLMTypes+CppBridge.swift toRALLMGenerateRequest which
// copies stopSequences into the canonical proto request.
//
// idl-005: prefer values from the canonical `request.options()` embedded
// LLMGenerationOptions message when set; fall back to the legacy inline
// scalar fields for backwards compatibility with callers that have not
// yet migrated.
rac_llm_options_t options_from_request(const LLMGenerateRequest& request,
                                       const std::string& system_prompt,
                                       std::vector<std::string>& stop_storage,
                                       std::vector<const char*>& stop_ptrs) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;

    const bool has_options = request.has_options();
    const auto& opts = request.options();

    const int max_tokens =
        (has_options && opts.max_tokens() > 0) ? opts.max_tokens() : request.max_tokens();
    if (max_tokens > 0) {
        options.max_tokens = max_tokens;
    }

    const float temperature =
        (has_options && opts.temperature() > 0.0f) ? opts.temperature() : request.temperature();
    if (temperature > 0.0f) {
        options.temperature = temperature;
    }

    const float top_p = (has_options && opts.top_p() > 0.0f) ? opts.top_p() : request.top_p();
    if (top_p > 0.0f) {
        options.top_p = top_p;
    }

    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    stop_storage.clear();
    stop_ptrs.clear();

    const auto& canonical_stop_sequences = (has_options && opts.stop_sequences_size() > 0)
                                               ? opts.stop_sequences()
                                               : request.stop_sequences();
    const int stop_count = canonical_stop_sequences.size();
    if (stop_count > 0) {
        stop_storage.reserve(static_cast<size_t>(stop_count));
        for (const auto& seq : canonical_stop_sequences) {
            if (!seq.empty()) {
                stop_storage.push_back(seq);
            }
        }
        stop_ptrs.reserve(stop_storage.size());
        for (const auto& seq : stop_storage) {
            stop_ptrs.push_back(seq.c_str());
        }
    }
    options.stop_sequences = stop_ptrs.empty() ? nullptr : stop_ptrs.data();
    options.num_stop_sequences = stop_ptrs.size();
    return options;
}

void set_result_from_raw(const rac::llm::LifecycleLlmRef& ref, const rac_llm_result_t& raw,
                         const char* response, size_t response_len, const char* thinking,
                         size_t thinking_len, int32_t thinking_tokens, int32_t response_tokens,
                         int32_t requested_max_tokens, LLMGenerationResult* out) {
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
    if ((ref.framework_name != nullptr) && ref.framework_name[0] != '\0') {
        out->set_framework(ref.framework_name);
    }
    // BUG-STREAMING-003: emit finish_reason="length" when max_tokens was exhausted
    // (matches OpenAI chat.completions contract — proto is modeled after it).
    out->set_finish_reason(
        (requested_max_tokens > 0 && raw.completion_tokens >= requested_max_tokens) ? "length"
                                                                                    : "stop");
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
    bool inside_thinking = false;
    bool emit_thoughts = false;
    int64_t started_ms = 0;
    int32_t token_count = 0;
    std::string request_id;
    std::string conversation_id;
    std::string raw_text;
    std::string pending_text;
    std::string response_text;
    std::string thinking_text;
};

size_t matching_tag_suffix_len(const std::string& text, const char* const* tags,
                               size_t tags_count) {
    size_t best = 0;
    for (size_t i = 0; i < tags_count; ++i) {
        const char* tag = tags[i];
        const size_t tag_len = std::strlen(tag);
        const size_t max_len = std::min(tag_len - 1, text.size());
        for (size_t len = 1; len <= max_len; ++len) {
            if (std::memcmp(text.data() + text.size() - len, tag, len) == 0) {
                best = std::max(best, len);
            }
        }
    }
    return best;
}

size_t find_earliest_tag(const std::string& text, const char* const* tags, size_t tags_count,
                         const char** out_tag) {
    size_t best = std::string::npos;
    const char* best_tag = nullptr;
    for (size_t i = 0; i < tags_count; ++i) {
        const size_t pos = text.find(tags[i]);
        if (pos != std::string::npos && pos < best) {
            best = pos;
            best_tag = tags[i];
        }
    }
    if (out_tag) {
        *out_tag = best_tag;
    }
    return best;
}

// BUG-STREAMING-001 unification: `dispatch_stream_event` now delegates
// to `rac::llm::serialize_llm_stream_event` — the single canonical
// 13-field emitter shared with `rac_llm_stream.cpp`. All callers
// populate the same LLMStreamEvent shape so Swift iOS, Web, and Kotlin
// Android consumers see identical wire bytes for identical inputs.
//
// pass3-syn-039: optional `tool_call` populates proto field 18 on
// LLMStreamEvent (idl/llm_service.proto:179). Producers pass it on the
// synthesized TOOL_CALL boundary event when the streaming output contains
// a parseable tool call; non-tool-call events leave it nullptr so legacy
// streams are byte-for-byte identical.
void dispatch_stream_event(ProtoStreamContext* ctx, const char* token, bool is_final,
                           TokenKind kind, const char* finish_reason, const char* error_message,
                           const LLMStreamFinalResult* result = nullptr,
                           const runanywhere::v1::ToolCall* tool_call = nullptr) {
    if (!ctx || !ctx->callback) {
        return;
    }

    rac::llm::LLMStreamEventParams params;
    params.token = token ? token : "";
    params.is_final = is_final;
    params.kind = static_cast<int>(kind);
    params.finish_reason = finish_reason;
    params.error_message = error_message;
    params.request_id = ctx->request_id.empty() ? nullptr : ctx->request_id.c_str();
    params.conversation_id = ctx->conversation_id.empty() ? nullptr : ctx->conversation_id.c_str();
    params.completion_tokens_generated = ctx->token_count;
    params.elapsed_ms = now_ms() - ctx->started_ms;
    params.final_result = result;
    params.tool_call = tool_call;

    thread_local std::vector<uint8_t> scratch;
    if (!rac::llm::serialize_llm_stream_event(++ctx->seq, params, scratch)) {
        return;
    }
    ctx->callback(scratch.empty() ? nullptr : scratch.data(), scratch.size(), ctx->user_data);
}

// pass3-syn-039: parse the accumulated streaming response_text for a tool
// call boundary using the canonical commons parser (rac_tool_call_parse_proto
// over runanywhere.v1.ToolParseRequest/Result). Returns true and populates
// out_tool_call when a structured tool call is recognized; false when the
// output contains no tool-call markers. The parser is format-aware
// (DEFAULT <tool_call>JSON</tool_call> and LFM2 <|tool_call_start|>...) and
// requires no ToolCallingOptions on the request because LLMGenerateRequest
// does not carry tool definitions (idl/llm_service.proto:42-51) — auto-format
// detection is sufficient to surface the structured payload on the
// LLMStreamEvent.tool_call slot when the model emitted one.
bool parse_response_tool_call(const std::string& response_text,
                              runanywhere::v1::ToolCall* out_tool_call) {
    if (response_text.empty() || !out_tool_call) {
        return false;
    }
    runanywhere::v1::ToolParseRequest request;
    request.set_text(response_text);

    const size_t req_size = request.ByteSizeLong();
    std::vector<uint8_t> req_bytes(req_size);
    if (req_size > 0 &&
        !request.SerializeToArray(req_bytes.data(), static_cast<int>(req_bytes.size()))) {
        return false;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_parse_proto(req_bytes.empty() ? nullptr : req_bytes.data(),
                                                req_bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return false;
    }

    runanywhere::v1::ToolParseResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    rac_proto_buffer_free(&out);

    if (result.has_tool_call() && result.tool_calls_size() > 0) {
        *out_tool_call = result.tool_calls(0);
        return true;
    }
    return false;
}

void emit_stream_segment(ProtoStreamContext* ctx, const std::string& token, TokenKind kind) {
    if (!ctx || token.empty()) {
        return;
    }

    if (kind == runanywhere::v1::TOKEN_KIND_THOUGHT) {
        ctx->thinking_text += token;
        if (!ctx->emit_thoughts) {
            return;
        }
    } else {
        ctx->response_text += token;
    }

    ctx->token_count += 1;
    if (!ctx->first_token_sent) {
        ctx->first_token_sent = true;
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED,
                                 nullptr, token.c_str(), nullptr, nullptr, ctx->ref->model_id, 1,
                                 now_ms() - ctx->started_ms);
    }
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED, nullptr,
                             token.c_str(), nullptr, nullptr, ctx->ref->model_id, ctx->token_count,
                             0);
    dispatch_stream_event(ctx, token.c_str(), false, kind, nullptr, nullptr);
}

void consume_thinking_aware_text(ProtoStreamContext* ctx, const char* token) {
    static const char* const kOpenTags[] = {"<think>", "<thinking>"};
    static const char* const kCloseTags[] = {"</think>", "</thinking>"};
    if (!ctx || !token || token[0] == '\0') {
        return;
    }

    ctx->raw_text += token;
    ctx->pending_text += token;
    while (!ctx->pending_text.empty()) {
        if (ctx->inside_thinking) {
            const char* close_tag = nullptr;
            const size_t close_pos =
                find_earliest_tag(ctx->pending_text, kCloseTags,
                                  sizeof(kCloseTags) / sizeof(kCloseTags[0]), &close_tag);
            if (close_pos != std::string::npos) {
                emit_stream_segment(ctx, ctx->pending_text.substr(0, close_pos),
                                    runanywhere::v1::TOKEN_KIND_THOUGHT);
                ctx->pending_text.erase(0, close_pos + std::strlen(close_tag));
                ctx->inside_thinking = false;
                continue;
            }

            const size_t keep = matching_tag_suffix_len(ctx->pending_text, kCloseTags,
                                                        sizeof(kCloseTags) / sizeof(kCloseTags[0]));
            const size_t emit_len = ctx->pending_text.size() - keep;
            if (emit_len == 0) {
                break;
            }
            emit_stream_segment(ctx, ctx->pending_text.substr(0, emit_len),
                                runanywhere::v1::TOKEN_KIND_THOUGHT);
            ctx->pending_text.erase(0, emit_len);
            continue;
        }

        const char* open_tag = nullptr;
        const size_t open_pos = find_earliest_tag(
            ctx->pending_text, kOpenTags, sizeof(kOpenTags) / sizeof(kOpenTags[0]), &open_tag);
        if (open_pos != std::string::npos) {
            emit_stream_segment(ctx, ctx->pending_text.substr(0, open_pos),
                                runanywhere::v1::TOKEN_KIND_ANSWER);
            ctx->pending_text.erase(0, open_pos + std::strlen(open_tag));
            ctx->inside_thinking = true;
            continue;
        }

        const size_t keep = matching_tag_suffix_len(ctx->pending_text, kOpenTags,
                                                    sizeof(kOpenTags) / sizeof(kOpenTags[0]));
        const size_t emit_len = ctx->pending_text.size() - keep;
        if (emit_len == 0) {
            break;
        }
        emit_stream_segment(ctx, ctx->pending_text.substr(0, emit_len),
                            runanywhere::v1::TOKEN_KIND_ANSWER);
        ctx->pending_text.erase(0, emit_len);
    }
}

void flush_pending_stream_text(ProtoStreamContext* ctx) {
    if (!ctx || ctx->pending_text.empty()) {
        return;
    }
    emit_stream_segment(ctx, ctx->pending_text,
                        ctx->inside_thinking ? runanywhere::v1::TOKEN_KIND_THOUGHT
                                             : runanywhere::v1::TOKEN_KIND_ANSWER);
    ctx->pending_text.clear();
}

void dispatch_terminal_once(ProtoStreamContext* ctx, const char* finish_reason,
                            const char* error_message) {
    if (!ctx || ctx->terminal_sent) {
        return;
    }
    flush_pending_stream_text(ctx);
    ctx->terminal_sent = true;

    // pass3-syn-039: surface a structured tool call on LLMStreamEvent.tool_call
    // (proto field 18) when the streaming output contains one. The terminal
    // event still carries the same finish_reason / result; this emission is
    // an additional in-stream event with event_kind=LLM_STREAM_EVENT_KIND_TOOL_CALL
    // and tool_call=<parsed ToolCall>, mirroring the
    // TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED semantics from
    // tool_calling_session.cpp but on the canonical LLM stream so direct
    // consumers (Swift LLMStreamEvent.toolCall, Kotlin event.tool_call, etc.)
    // observe the structured payload without parsing the raw token text.
    if (error_message == nullptr || error_message[0] == '\0') {
        runanywhere::v1::ToolCall parsed_tool_call;
        if (parse_response_tool_call(ctx->response_text, &parsed_tool_call)) {
            dispatch_stream_event(ctx, /*token=*/"", /*is_final=*/false,
                                  runanywhere::v1::TOKEN_KIND_TOOL_CALL,
                                  /*finish_reason=*/nullptr, /*error_message=*/nullptr,
                                  /*result=*/nullptr, &parsed_tool_call);
        }
    }

    LLMStreamFinalResult final_result;
    final_result.set_text(ctx->response_text);
    if (!ctx->thinking_text.empty()) {
        final_result.set_thinking_content(ctx->thinking_text);
    }
    final_result.set_completion_tokens(ctx->token_count);
    final_result.set_total_tokens(ctx->token_count);
    final_result.set_total_time_ms(now_ms() - ctx->started_ms);
    final_result.set_finish_reason(
        (finish_reason != nullptr) && finish_reason[0] != '\0' ? finish_reason : "stop");
    if ((error_message != nullptr) && error_message[0] != '\0') {
        final_result.set_error_message(error_message);
    }

    dispatch_stream_event(ctx, "", true, runanywhere::v1::TOKEN_KIND_ANSWER, finish_reason,
                          error_message, &final_result);
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
    consume_thinking_aware_text(ctx, safe_token);
    return RAC_TRUE;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

rac_result_t rac_llm_generate_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
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
                             request.prompt().c_str(), nullptr, nullptr, nullptr, ref.model_id, 0,
                             0);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    rac_llm_options_t options =
        options_from_request(request, system_prompt, stop_storage, stop_ptrs);
    options.streaming_enabled = RAC_FALSE;

    rac_llm_result_t raw{};
    const int64_t started = now_ms();
    rc = (ref.ops && ref.ops->generate)
             ? ref.ops->generate(ref.impl, request.prompt().c_str(), &options, &raw)
             : RAC_ERROR_NOT_SUPPORTED;
    const int64_t elapsed = now_ms() - started;

    if (rc != RAC_SUCCESS) {
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, nullptr, rac_error_message(rc),
                                 ref.model_id, 0, elapsed);
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
    (void)rac_llm_split_thinking_tokens(raw.completion_tokens, response, thinking, &thinking_tokens,
                                        &response_tokens);

    LLMGenerationResult result;
    set_result_from_raw(ref, raw, response, response_len, thinking, thinking_len, thinking_tokens,
                        response_tokens, options.max_tokens, &result);
    set_structured_output_if_present(response, &result);

    publish_generation_event(
        runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED, request.prompt().c_str(), nullptr,
        response, nullptr, ref.model_id, raw.completion_tokens,
        raw.total_time_ms > 0 ? raw.total_time_ms : elapsed, raw.prompt_tokens);

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
                             request.prompt().c_str(), nullptr, nullptr, nullptr, ref.model_id, 0,
                             0);

    const std::string system_prompt = system_prompt_from_request(request);
    std::vector<std::string> stop_storage;
    std::vector<const char*> stop_ptrs;
    rac_llm_options_t options =
        options_from_request(request, system_prompt, stop_storage, stop_ptrs);
    options.streaming_enabled = RAC_TRUE;

    ProtoStreamContext ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.started_ms = now_ms();
    ctx.emit_thoughts = request.emit_thoughts();
    ctx.request_id = request.request_id();
    ctx.conversation_id = request.conversation_id();

    // Defensive: catch any C++ exception that escapes the engine vtable.
    // Each backend (llamacpp, onnx, etc.) already wraps its inference call in
    // try/catch, but we wrap here too so a misbehaving engine (or a future
    // backend that forgets) can never propagate `__cxa_throw` across the
    // extern "C" boundary into the platform SDK. On WASM this would surface
    // as an opaque `WebAssembly.Exception` (no `.message`) in JS; on native
    // SDKs it would be undefined behaviour through a C ABI return.
    try {
        rc = ref.ops->generate_stream(ref.impl, request.prompt().c_str(), &options,
                                      stream_token_callback, &ctx);
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        rc = RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception escaped LLM engine generate_stream");
        rc = RAC_ERROR_INFERENCE_FAILED;
    }

    const bool cancelled = rac::llm::lifecycle_llm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        dispatch_terminal_once(&ctx, "cancelled", nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCELLED,
                                 request.prompt().c_str(), nullptr, ctx.response_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count, now_ms() - ctx.started_ms);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_terminal_once(&ctx, "error", rac_error_message(rc));
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_FAILED,
                                 request.prompt().c_str(), nullptr, ctx.response_text.c_str(),
                                 rac_error_message(rc), ref.model_id, ctx.token_count,
                                 now_ms() - ctx.started_ms);
    } else {
        // commons-features-llm-rag-002: mirror the OpenAI-style finish_reason
        // contract from llm_component.cpp:867-884 and rac_llm_generate_proto's
        // set_result_from_raw — when the backend stopped because it generated
        // the requested max_tokens, the terminal proto event must report
        // "length" rather than "stop". Without this gate every successful
        // streaming proto generation looks like a natural stop, which breaks
        // OpenAI parity for direct streaming proto callers (JNI, Web, etc.)
        // and diverges from the non-streaming proto path.
        const char* finish_reason =
            (options.max_tokens > 0 && ctx.token_count >= options.max_tokens) ? "length" : "stop";
        dispatch_terminal_once(&ctx, finish_reason, nullptr);
        publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_STREAM_COMPLETED,
                                 request.prompt().c_str(), nullptr, ctx.response_text.c_str(),
                                 nullptr, ref.model_id, ctx.token_count, now_ms() - ctx.started_ms);
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
        SDKEvent failed = make_cancellation_event(runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
                                                  "no lifecycle LLM model loaded", RAC_TRUE,
                                                  runanywhere::v1::ERROR_SEVERITY_ERROR);
        (void)publish_sdk_event(failed);
        return rac_proto_buffer_set_error(out_event, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::request_lifecycle_llm_cancel(&ref);
    publish_generation_event(runanywhere::v1::GENERATION_EVENT_KIND_CANCEL_REQUESTED, nullptr,
                             nullptr, nullptr, nullptr, ref.model_id, 0, 0);
    if (ref.ops && ref.ops->cancel) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }

    SDKEvent event = make_cancellation_event(
        rc == RAC_SUCCESS ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                          : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED,
        rc == RAC_SUCCESS ? "user_requested" : rac_error_message(rc), RAC_TRUE,
        rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                          : runanywhere::v1::ERROR_SEVERITY_ERROR);
    (void)publish_sdk_event(event);
    rac_result_t copy_rc = copy_proto(event, out_event);
    rac::llm::release_lifecycle_llm(&ref);
    return rc == RAC_SUCCESS ? copy_rc : rc;
#endif
}

}  // extern "C"
