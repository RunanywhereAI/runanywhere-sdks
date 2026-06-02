/**
 * @file tool_calling_run_loop.cpp
 * @brief Synchronous, single-call tool-calling loop.
 *
 * Collapses Swift's RunAnywhere+ToolCalling.swift::generateWithTools (~100 LOC)
 * to ~10 LOC. Same logic that the session API uses, but exposed as a
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
 * Mirrors tool_calling_session.cpp — share the same design but as
 * a synchronous single-call ABI instead of an outer-driven event stream.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
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

// per-loop cancellation state. Allocated on the heap, owned by
// a per-process registry keyed by an opaque handle published to the host via
// rac_tool_calling_run_loop_with_handle_proto. The cancel function is
// thread-safe relative to the run loop (uses a separate active_ref_mu).
struct LoopCancelState {
    std::mutex active_ref_mu;
    rac::llm::LifecycleLlmRef* active_ref = nullptr;
    std::atomic<bool> cancel_requested{false};
};

struct LoopRegistry {
    std::mutex mu;
    std::atomic<uint64_t> next_handle{1};
    std::unordered_map<uint64_t, std::shared_ptr<LoopCancelState>> states;
};

LoopRegistry& loop_registry() {
    static LoopRegistry inst;
    return inst;
}

uint64_t register_loop_state(std::shared_ptr<LoopCancelState> state) {
    auto& reg = loop_registry();
    uint64_t handle = reg.next_handle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lg(reg.mu);
    reg.states[handle] = std::move(state);
    return handle;
}

void unregister_loop_state(uint64_t handle) {
    if (handle == 0)
        return;
    auto& reg = loop_registry();
    std::lock_guard<std::mutex> lg(reg.mu);
    reg.states.erase(handle);
}

std::shared_ptr<LoopCancelState> lookup_loop_state(uint64_t handle) {
    if (handle == 0)
        return nullptr;
    auto& reg = loop_registry();
    std::lock_guard<std::mutex> lg(reg.mu);
    auto it = reg.states.find(handle);
    return it == reg.states.end() ? nullptr : it->second;
}

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

    // request-level tool_choice / forced_tool_name overrides.
    // When present, build_options_snapshot copies them onto the synthesized
    // ToolCallingOptions before every format/validate proto helper call.
    bool has_tool_choice = false;
    runanywhere::v1::ToolChoiceMode tool_choice = runanywhere::v1::TOOL_CHOICE_MODE_UNSPECIFIED;
    std::string forced_tool_name;

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
    // Honor ToolCallingSessionCreateRequest.tool_choice / forced_tool_name
    // The request-level fields take precedence over any
    // tool_options the caller might have pre-populated, so the high-level
    // run-loop / session APIs surface the OpenAI-style tool_choice knob
    // that the format/validate primitives already read.
    if (ctx.has_tool_choice) {
        options.set_tool_choice(ctx.tool_choice);
    }
    if (!ctx.forced_tool_name.empty()) {
        options.set_forced_tool_name(ctx.forced_tool_name);
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
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
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
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    } else {
        result.set_is_valid(false);
        result.set_error_message(out.error_message ? out.error_message
                                                   : "validation proto call failed");
    }
    rac_proto_buffer_free(&out);
    return result;
}

bool run_generate_once(const LoopContext& ctx, LoopCancelState* cancel_state,
                       const std::string& prompt, std::string* out_response, rac_result_t* out_rc) {
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

    // publish the in-flight ref so a cancel from another
    // thread can interrupt. Latch a pre-arrived cancel onto the ref now.
    if (cancel_state) {
        std::lock_guard<std::mutex> guard(cancel_state->active_ref_mu);
        cancel_state->active_ref = &ref;
        if (cancel_state->cancel_requested.load(std::memory_order_acquire)) {
            rac::llm::request_lifecycle_llm_cancel(&ref);
        }
    }

    rac_llm_result_t raw{};
    rc = ref.ops->generate(ref.impl, prompt.c_str(), &options, &raw);

    if (cancel_state) {
        std::lock_guard<std::mutex> guard(cancel_state->active_ref_mu);
        cancel_state->active_ref = nullptr;
    }

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

// internal helper that owns the full run-loop body. Both the
// pointer-shape (rac_tool_calling_run_loop_with_handle_proto) and the
// callback-shape (rac_tool_calling_run_loop_with_handle_and_cb_proto) entry
// points funnel through this helper. The handle is allocated FIRST — before
// any LLM work — and published two ways:
//   1. *out_run_loop_handle (when non-null) — for hosts that observe the
//      handle from the SAME thread that called the run-loop.
//   2. on_handle_published(handle, on_handle_user_data) (when non-null) —
//      fired synchronously the moment the handle is minted so hosts can fan
//      the value into a thread-safe sink (Swift HandleBox, Kotlin
//      CompletableDeferred, RN JS-thread callback, Flutter Completer, Web
//      synchronous capture) BEFORE the first generate iteration runs.
static rac_result_t
run_loop_impl(const uint8_t* in_request_bytes, size_t in_size,
              rac_tool_execute_callback_fn on_execute, void* on_execute_user_data,
              rac_tool_calling_run_loop_on_handle_published_cb_t on_handle_published,
              void* on_handle_user_data, uint64_t* out_run_loop_handle,
              rac_proto_buffer_t* out_result) {
    if (!on_execute || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_run_loop_handle) {
        *out_run_loop_handle = 0;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_size;
    (void)on_execute_user_data;
    (void)on_handle_published;
    (void)on_handle_user_data;
    rac_proto_buffer_init(out_result);
    rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "protobuf runtime unavailable");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (in_size > 0 && !in_request_bytes) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_result);

    // mint the cancel state and handle FIRST — before any
    // proto parsing or LLM work — so the host can race the handle into its
    // own thread-safe sink synchronously from on_handle_published. RAII
    // guard unregisters on every return path.
    auto cancel_state = std::make_shared<LoopCancelState>();
    uint64_t handle = register_loop_state(cancel_state);
    if (out_run_loop_handle) {
        *out_run_loop_handle = handle;
    }
    struct HandleScope {
        uint64_t handle;
        ~HandleScope() { unregister_loop_state(handle); }
    } scope{handle};

    // Fire the publication callback SYNCHRONOUSLY before any other work.
    // The callback runs on this thread, with the handle already registered
    // in the loop_registry, so a concurrent cancel from another thread
    // (e.g. Swift withTaskCancellationHandler) will land on the live state.
    if (on_handle_published) {
        on_handle_published(handle, on_handle_user_data);
    }

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
    // Honor ToolCallingSessionCreateRequest.validate_calls (idl/tool_calling.proto).
    // The field is `optional bool` so we can preserve the historical default
    // (validate=true) when the caller did not set it, while still letting hosts
    // that delegate validation/authorization to their executor opt out by
    // explicitly setting validate_calls=false.
    ctx.validate_calls = request.has_validate_calls() ? request.validate_calls() : true;
    // pick up the request-level OpenAI-style tool_choice and
    // forced_tool_name knobs (idl/tool_calling.proto fields 7/8) — these are
    // copied onto every ToolCallingOptions snapshot the loop synthesizes for
    // format/validate proto calls.
    if (request.has_tool_choice()) {
        ctx.has_tool_choice = true;
        ctx.tool_choice = request.tool_choice();
    }
    if (request.has_forced_tool_name()) {
        ctx.forced_tool_name = request.forced_tool_name();
    }
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
        if (!run_generate_once(ctx, cancel_state.get(), current_prompt, &response, &rc)) {
            // distinguish cancel from other generate
            // failures, mirroring run_generate_loop in tool_calling_session.cpp.
            // A cancel that latched before/during generate surfaces as
            // RAC_ERROR_CANCELLED with "LLM generation cancelled" so hosts can
            // branch on error_code instead of message string matching.
            const bool cancelled = cancel_state->cancel_requested.load(std::memory_order_acquire);
            const rac_result_t report_rc = cancelled ? RAC_ERROR_CANCELLED : rc;
            const char* msg = cancelled ? "LLM generation cancelled" : "LLM generation failed";
            final_result.set_text(final_text);
            final_result.set_is_complete(false);
            final_result.set_iterations_used(static_cast<int32_t>(iteration));
            final_result.set_error_code(static_cast<int32_t>(report_rc));
            final_result.set_error_message(msg);
            std::vector<uint8_t> bytes;
            serialize(final_result, &bytes);
            rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
            return report_rc;
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
                                          call_bytes.size(), &exec_out, on_execute_user_data);

        runanywhere::v1::ToolResult tool_result;
        if (exec_rc == RAC_SUCCESS && exec_out.data && exec_out.size > 0) {
            (void)tool_result.ParseFromArray(exec_out.data, static_cast<int>(exec_out.size));
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

// Public entry: pointer-shape (handle written into out_run_loop_handle).
// Hosts that observe the handle from the same thread that called the loop
// use this. SDKs that need cross-thread publication should prefer
// rac_tool_calling_run_loop_with_handle_and_cb_proto below.
extern "C" rac_result_t rac_tool_calling_run_loop_with_handle_proto(
    const uint8_t* in_request_bytes, size_t in_size, rac_tool_execute_callback_fn on_execute,
    void* user_data, uint64_t* out_run_loop_handle, rac_proto_buffer_t* out_result) {
    return run_loop_impl(in_request_bytes, in_size, on_execute, user_data,
                         /*on_handle_published=*/nullptr,
                         /*on_handle_user_data=*/nullptr, out_run_loop_handle, out_result);
}

// callback-shape entry — fires on_handle_published(handle, ud)
// SYNCHRONOUSLY the moment a cancellable handle is minted, BEFORE the first
// generate iteration runs. This lets Swift/Kotlin/Flutter/RN/Web SDKs route
// the handle into a thread-safe sink (HandleBox, CompletableDeferred,
// Completer, JS callback, synchronous capture) without racing the worker
// thread that owns the run-loop. The pointer-shape out_run_loop_handle is
// still populated so legacy hosts that observe both have a stable contract.
extern "C" rac_result_t rac_tool_calling_run_loop_with_handle_and_cb_proto(
    const uint8_t* in_request_bytes, size_t in_size, rac_tool_execute_callback_fn on_execute,
    void* on_execute_user_data,
    rac_tool_calling_run_loop_on_handle_published_cb_t on_handle_published,
    void* on_handle_user_data, uint64_t* out_run_loop_handle, rac_proto_buffer_t* out_result) {
    return run_loop_impl(in_request_bytes, in_size, on_execute, on_execute_user_data,
                         on_handle_published, on_handle_user_data, out_run_loop_handle, out_result);
}

// Legacy ABI wrapper — preserves the original signature. Discards the handle
// out-parameter for hosts that don't need cancellation (the in-flight loop
// state is still registered / unregistered behind the scenes).
extern "C" rac_result_t rac_tool_calling_run_loop_proto(const uint8_t* in_request_bytes,
                                                        size_t in_size,
                                                        rac_tool_execute_callback_fn on_execute,
                                                        void* user_data,
                                                        rac_proto_buffer_t* out_result) {
    uint64_t discarded = 0;
    return run_loop_impl(in_request_bytes, in_size, on_execute, user_data,
                         /*on_handle_published=*/nullptr,
                         /*on_handle_user_data=*/nullptr, &discarded, out_result);
}

extern "C" rac_result_t rac_tool_calling_run_loop_cancel_proto(uint64_t run_loop_handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)run_loop_handle;
    return RAC_SUCCESS;  // idempotent — protobuf-less builds never start a loop
#else
    auto state = lookup_loop_state(run_loop_handle);
    if (!state) {
        // Idempotent — handle already retired or never published. The SDK
        // adapters fan structured-concurrency cancels into this entry point
        // without coordinating with the loop's exit, so a stale handle is
        // the normal race-loser path. Return success.
        return RAC_SUCCESS;
    }
    state->cancel_requested.store(true, std::memory_order_release);
    std::lock_guard<std::mutex> guard(state->active_ref_mu);
    if (state->active_ref) {
        rac::llm::request_lifecycle_llm_cancel(state->active_ref);
    }
    return RAC_SUCCESS;
#endif
}
