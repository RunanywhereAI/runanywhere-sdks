/**
 * @file tool_calling_run_loop.cpp
 * @brief P2-T8: Synchronous, single-call tool-calling loop.
 *
 * Collapses Swift's RunAnywhere+ToolCalling.swift::generateWithTools (~100 LOC)
 * to ~10 LOC. Same logic that the Wave D-4 session API uses, but exposed as a
 * single C ABI call: the host SDK passes in the full request plus a
 * synchronous tool-execute callback, and commons owns the entire
 *   build_prompt -> generate -> parse -> validate -> execute -> follow_up
 * loop. The host only owns the executor side-effects (HTTP calls, device APIs,
 * etc.) — exactly what cannot live in C++ portably.
 *
 * Reuses public proto APIs (no internal duplication):
 *   - rac_tool_call_format_prompt_proto  -> initial + follow-up prompts
 *   - rac_tool_call_parse_proto          -> parse LLM output for tool calls
 *   - rac_tool_call_validate_proto       -> validate against request.tools
 *
 * LLM generation goes through the lifecycle-owned LLM (same path that the
 * session API uses), so this honors the same plugin routing, cancel, and
 * refcount semantics.
 *
 * Mirrors tool_calling_session.cpp (Wave D-4) — share the same design but as
 * a synchronous single-call ABI instead of an outer-driven event stream.
 */

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace {

constexpr const char* kTag = "ToolCallingRunLoop";
constexpr uint32_t kDefaultMaxIterations = 5;

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

// Snapshot of immutable per-loop inputs. Mirrors the per-session struct in
// tool_calling_session.cpp but without the state-machine plumbing.
struct LoopContext {
    std::string user_prompt;
    std::string format_hint;
    std::string system_prompt;
    int32_t max_tokens = 0;
    float temperature = 0.0f;
    float top_p = 0.0f;
    uint32_t max_iterations = kDefaultMaxIterations;
    bool keep_tools_available = false;
    bool validate_calls = true;

    // Tools (and any other portable options) live inside this snapshot for
    // the parse/validate/format_prompt helpers.
    runanywhere::v1::ToolCallingOptions tool_options;
};

runanywhere::v1::ToolCallingOptions build_options_snapshot(const LoopContext& ctx) {
    runanywhere::v1::ToolCallingOptions options = ctx.tool_options;
    options.set_format_hint(ctx.format_hint);
    options.set_max_iterations(static_cast<int32_t>(ctx.max_iterations));
    options.set_keep_tools_available(ctx.keep_tools_available);
    if (ctx.max_tokens > 0) {
        options.set_max_tokens(ctx.max_tokens);
    }
    if (ctx.temperature > 0.0f) {
        options.set_temperature(ctx.temperature);
    }
    if (!ctx.system_prompt.empty()) {
        options.set_system_prompt(ctx.system_prompt);
    }
    options.set_auto_execute(true);
    return options;
}

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    if (out->empty()) {
        return true;
    }
    return message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

std::string format_prompt_proto(const LoopContext& ctx,
                                const std::vector<runanywhere::v1::ToolResult>& tool_results) {
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(ctx.user_prompt);
    *request.mutable_options() = build_options_snapshot(ctx);
    for (const auto& tr : tool_results) {
        *request.add_tool_results() = tr;
    }

    std::vector<uint8_t> req_bytes;
    if (!serialize(request, &req_bytes)) {
        return {};
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_format_prompt_proto(
        req_bytes.empty() ? nullptr : req_bytes.data(), req_bytes.size(), &out);
    std::string formatted;
    if (rc == RAC_SUCCESS && out.data && out.size > 0) {
        runanywhere::v1::ToolPromptFormatResult result;
        if (result.ParseFromArray(out.data, static_cast<int>(out.size))) {
            formatted = result.formatted_prompt();
        }
    }
    rac_proto_buffer_free(&out);
    return formatted;
}

bool parse_tool_call_from_output(const LoopContext& ctx, const std::string& llm_output,
                                 std::string* out_clean_text,
                                 runanywhere::v1::ToolCall* out_tool_call) {
    runanywhere::v1::ToolParseRequest request;
    request.set_text(llm_output);
    *request.mutable_options() = build_options_snapshot(ctx);

    std::vector<uint8_t> req_bytes;
    if (!serialize(request, &req_bytes)) {
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
        result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    rac_proto_buffer_free(&out);

    if (out_clean_text) {
        *out_clean_text = result.remaining_text();
    }
    if (result.has_tool_call() && result.tool_calls_size() > 0) {
        if (out_tool_call) {
            *out_tool_call = result.tool_calls(0);
        }
        return true;
    }
    return false;
}

runanywhere::v1::ToolCallValidationResult
validate_tool_call(const LoopContext& ctx, const runanywhere::v1::ToolCall& tool_call) {
    runanywhere::v1::ToolCallValidationRequest request;
    *request.mutable_tool_call() = tool_call;
    *request.mutable_options() = build_options_snapshot(ctx);

    runanywhere::v1::ToolCallValidationResult result;
    std::vector<uint8_t> req_bytes;
    if (!serialize(request, &req_bytes)) {
        result.set_is_valid(false);
        result.set_error_message("failed to serialize validation request");
        return result;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_validate_proto(req_bytes.empty() ? nullptr : req_bytes.data(),
                                                   req_bytes.size(), &out);
    if (rc == RAC_SUCCESS && out.data && out.size > 0) {
        result.ParseFromArray(out.data, static_cast<int>(out.size));
    } else {
        result.set_is_valid(false);
        result.set_error_message(out.error_message ? out.error_message
                                                   : "validation proto call failed");
    }
    rac_proto_buffer_free(&out);
    return result;
}

bool run_generate_once(const LoopContext& ctx, const std::string& prompt, std::string* out_response,
                       rac_result_t* out_rc) {
    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        if (out_rc)
            *out_rc = rc;
        return false;
    }

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    if (ctx.max_tokens > 0) {
        options.max_tokens = ctx.max_tokens;
    }
    if (ctx.temperature > 0.0f) {
        options.temperature = ctx.temperature;
    }
    if (ctx.top_p > 0.0f) {
        options.top_p = ctx.top_p;
    }
    options.streaming_enabled = RAC_FALSE;
    options.system_prompt = ctx.system_prompt.empty() ? nullptr : ctx.system_prompt.c_str();

    rac::llm::clear_lifecycle_llm_cancel(&ref);

    if (!ref.ops || !ref.ops->generate) {
        rac::llm::release_lifecycle_llm(&ref);
        if (out_rc)
            *out_rc = RAC_ERROR_NOT_SUPPORTED;
        return false;
    }

    rac_llm_result_t raw{};
    rc = ref.ops->generate(ref.impl, prompt.c_str(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac_llm_result_free(&raw);
        rac::llm::release_lifecycle_llm(&ref);
        if (out_rc)
            *out_rc = rc;
        return false;
    }

    if (out_response) {
        *out_response = raw.text ? raw.text : "";
    }
    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    if (out_rc)
        *out_rc = RAC_SUCCESS;
    return true;
}

void emit_failure(rac_proto_buffer_t* out_result, rac_result_t status, const std::string& message) {
    if (!out_result)
        return;
    runanywhere::v1::ToolCallingResult err;
    err.set_error_code(static_cast<int32_t>(status));
    err.set_error_message(message);
    err.set_is_complete(false);
    std::vector<uint8_t> bytes;
    serialize(err, &bytes);
    rac_proto_buffer_init(out_result);
    rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
    rac_proto_buffer_set_error(out_result, status, message.c_str());
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_tool_calling_run_loop_proto(const uint8_t* in_request_bytes,
                                                        size_t in_size,
                                                        rac_tool_execute_callback_fn on_execute,
                                                        void* user_data,
                                                        rac_proto_buffer_t* out_result) {
    if (!on_execute || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_size;
    (void)user_data;
    rac_proto_buffer_init(out_result);
    rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "protobuf runtime unavailable");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (in_size > 0 && !in_request_bytes) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_result);

    // Reuse the existing ToolCallingSessionCreateRequest as the input shape
    // (identical fields: prompt, tools, max_iterations, format_hint, etc.).
    runanywhere::v1::ToolCallingSessionCreateRequest request;
    if (in_size > 0 && !request.ParseFromArray(in_request_bytes, static_cast<int>(in_size))) {
        emit_failure(out_result, RAC_ERROR_DECODING_ERROR,
                     "failed to parse ToolCallingSessionCreateRequest");
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.prompt().empty()) {
        emit_failure(out_result, RAC_ERROR_INVALID_ARGUMENT, "prompt is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    LoopContext ctx;
    ctx.user_prompt = request.prompt();
    ctx.max_tokens = request.max_tokens();
    ctx.temperature = request.temperature();
    ctx.top_p = request.top_p();
    ctx.system_prompt = request.system_prompt();
    ctx.format_hint =
        request.format_hint().empty() ? std::string("default") : request.format_hint();
    ctx.max_iterations =
        request.max_iterations() == 0 ? kDefaultMaxIterations : request.max_iterations();
    ctx.keep_tools_available = request.keep_tools_available();
    ctx.validate_calls = true;
    for (const auto& tool : request.tools()) {
        *ctx.tool_options.add_tools() = tool;
    }

    runanywhere::v1::ToolCallingResult final_result;
    std::string current_prompt = format_prompt_proto(ctx, /*tool_results=*/{});
    if (current_prompt.empty()) {
        current_prompt = ctx.user_prompt;
    }

    uint32_t iteration = 0;
    bool is_complete = false;
    std::string final_text;

    while (iteration < ctx.max_iterations) {
        iteration++;
        RAC_LOG_DEBUG(kTag, "iteration %u/%u", iteration, ctx.max_iterations);

        std::string response;
        rac_result_t rc = RAC_SUCCESS;
        if (!run_generate_once(ctx, current_prompt, &response, &rc)) {
            final_result.set_text(final_text);
            final_result.set_is_complete(false);
            final_result.set_iterations_used(static_cast<int32_t>(iteration));
            final_result.set_error_code(static_cast<int32_t>(rc));
            final_result.set_error_message("LLM generation failed");
            std::vector<uint8_t> bytes;
            serialize(final_result, &bytes);
            rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
            return rc;
        }

        std::string clean_text;
        runanywhere::v1::ToolCall parsed_call;
        const bool has_call = parse_tool_call_from_output(ctx, response, &clean_text, &parsed_call);
        final_text = clean_text;

        if (!has_call) {
            RAC_LOG_DEBUG(kTag, "no tool call; loop complete after iter %u", iteration);
            is_complete = true;
            break;
        }

        if (ctx.validate_calls) {
            auto validation = validate_tool_call(ctx, parsed_call);
            if (!validation.is_valid()) {
                std::string msg = validation.error_message();
                if (msg.empty() && validation.validation_errors_size() > 0) {
                    msg = validation.validation_errors(0);
                }
                if (msg.empty()) {
                    msg = "tool call validation failed";
                }
                runanywhere::v1::ToolResult failed;
                failed.set_tool_call_id(parsed_call.id());
                failed.set_call_id(parsed_call.id());
                failed.set_name(parsed_call.name());
                failed.set_error(msg);
                failed.set_success(false);
                failed.set_started_at_ms(now_ms());
                failed.set_completed_at_ms(now_ms());
                *final_result.add_tool_calls() = parsed_call;
                *final_result.add_tool_results() = failed;
                is_complete = false;
                final_result.set_error_code(RAC_ERROR_VALIDATION_FAILED);
                final_result.set_error_message(msg);
                break;
            }
            if (!validation.normalized_arguments_json().empty()) {
                parsed_call.set_arguments_json(validation.normalized_arguments_json());
            }
        }

        // Synchronous tool execution via host callback.
        std::vector<uint8_t> call_bytes;
        if (!serialize(parsed_call, &call_bytes)) {
            emit_failure(out_result, RAC_ERROR_INTERNAL,
                         "failed to serialize ToolCall for callback");
            return RAC_ERROR_INTERNAL;
        }

        rac_proto_buffer_t exec_out;
        rac_proto_buffer_init(&exec_out);
        rac_result_t exec_rc = on_execute(call_bytes.empty() ? nullptr : call_bytes.data(),
                                          call_bytes.size(), &exec_out, user_data);

        runanywhere::v1::ToolResult tool_result;
        if (exec_rc == RAC_SUCCESS && exec_out.data && exec_out.size > 0) {
            tool_result.ParseFromArray(exec_out.data, static_cast<int>(exec_out.size));
        }
        // Always populate identifiers / fallback success state on the
        // returned result so the follow-up prompt formatter has stable input.
        if (tool_result.tool_call_id().empty()) {
            tool_result.set_tool_call_id(parsed_call.id());
        }
        if (tool_result.call_id().empty()) {
            tool_result.set_call_id(parsed_call.id());
        }
        if (tool_result.name().empty()) {
            tool_result.set_name(parsed_call.name());
        }
        if (exec_rc != RAC_SUCCESS) {
            tool_result.set_success(false);
            std::string err_msg = "tool executor returned error";
            if (exec_out.error_message) {
                err_msg = exec_out.error_message;
            }
            tool_result.set_error(err_msg);
        }
        if (tool_result.started_at_ms() == 0)
            tool_result.set_started_at_ms(now_ms());
        if (tool_result.completed_at_ms() == 0)
            tool_result.set_completed_at_ms(now_ms());

        rac_proto_buffer_free(&exec_out);

        *final_result.add_tool_calls() = parsed_call;
        *final_result.add_tool_results() = tool_result;

        if (exec_rc != RAC_SUCCESS) {
            final_result.set_error_code(static_cast<int32_t>(exec_rc));
            final_result.set_error_message(tool_result.error());
            is_complete = false;
            break;
        }

        // Build follow-up prompt from the executed tool result.
        std::vector<runanywhere::v1::ToolResult> trs{tool_result};
        std::string follow = format_prompt_proto(ctx, trs);
        current_prompt = follow.empty() ? ctx.user_prompt : follow;
    }

    if (iteration >= ctx.max_iterations && !is_complete) {
        // Mirror the session API: max_iterations is a hard cap and we report
        // is_complete=true (the conversation is done as far as the loop is
        // concerned), matching tool_calling_session.cpp's run_generate_loop.
        is_complete = true;
    }

    final_result.set_text(final_text);
    final_result.set_is_complete(is_complete);
    final_result.set_iterations_used(static_cast<int32_t>(iteration));

    std::vector<uint8_t> bytes;
    if (!serialize(final_result, &bytes)) {
        emit_failure(out_result, RAC_ERROR_INTERNAL, "failed to serialize ToolCallingResult");
        return RAC_ERROR_INTERNAL;
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
#endif
}
