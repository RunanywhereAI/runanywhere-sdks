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
#include <utility>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/llm/tool_calling_generation_internal.h"
#include "features/llm/tool_calling_result_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace {

constexpr const char* kTag = "ToolCallingRunLoop";
constexpr uint32_t kDefaultMaxToolCalls = 5;

// per-loop cancellation state. Allocated on the heap, owned by
// a per-process registry keyed by an opaque handle published to the host via
// rac_tool_calling_run_loop_proto. The cancel function is
// thread-safe relative to the run loop (uses a separate active_ref_mu).
struct LoopCancelState {
    std::mutex active_ref_mu;
    rac::llm::LifecycleLlmRef* active_ref = nullptr;
    bool generation_started = false;  // guarded by active_ref_mu
    std::recursive_mutex side_effect_admission_mu;
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
    runanywhere::v1::ToolCallFormatName format = runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON;
    uint32_t max_tool_calls = kDefaultMaxToolCalls;
    bool auto_execute = true;
    bool replace_system_prompt = false;
    bool require_json_arguments = false;
    bool keep_tools_available = false;
    bool validate_calls = true;
    rac::llm::tool_calling::GenerationState generation;

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

// A caller-provided forced_tool_name is an explicit routing instruction. Raw
// user text is never promoted to SPECIFIC here: merely mentioning a tool name
// (including in a negation, quotation, or documentation question) must retain
// AUTO semantics and must not authorize a side effect.
bool apply_explicit_tool_choice(LoopContext* ctx, std::string* out_error) {
    if (!ctx) {
        return false;
    }

    // NONE is an authorization veto. Discard a contradictory forced name so
    // every downstream prompt/parse/validation snapshot sees one unambiguous
    // policy.
    if (ctx->has_tool_choice && ctx->tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) {
        ctx->forced_tool_name.clear();
        return true;
    }

    // A non-empty forced name is itself an explicit SPECIFIC choice, even
    // when callers omit tool_choice (or accidentally leave it AUTO/REQUIRED).
    if (!ctx->forced_tool_name.empty()) {
        ctx->has_tool_choice = true;
        ctx->tool_choice = runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC;
    }

    if (!ctx->has_tool_choice || ctx->tool_choice != runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC) {
        return true;
    }
    if (ctx->forced_tool_name.empty()) {
        if (out_error) {
            *out_error = "tool_choice=SPECIFIC requires a non-empty forced_tool_name";
        }
        return false;
    }
    for (const auto& tool : ctx->tool_options.tools()) {
        if (tool.name() == ctx->forced_tool_name) {
            return true;
        }
    }
    if (out_error) {
        *out_error =
            "tool_choice=SPECIFIC target is not present in request.tools: " + ctx->forced_tool_name;
    }
    return false;
}

bool tool_choice_requires_call(const LoopContext& ctx) {
    return ctx.has_tool_choice && (ctx.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED ||
                                   ctx.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
}

std::string missing_required_tool_call_error(const LoopContext& ctx) {
    return ctx.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC
               ? "tool_choice=SPECIFIC requires a tool call"
               : "tool_choice=REQUIRED requires a tool call";
}

std::string tool_choice_policy_error(const LoopContext& ctx,
                                     const runanywhere::v1::ToolCall& tool_call) {
    if (ctx.has_tool_choice && ctx.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) {
        return "Tool calls are disabled by tool_choice=NONE";
    }
    if (ctx.has_tool_choice && ctx.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC &&
        tool_call.name() != ctx.forced_tool_name) {
        return "Tool call must use tool_choice=SPECIFIC target: " + ctx.forced_tool_name;
    }
    return {};
}

runanywhere::v1::ToolCallingOptions build_options_snapshot(const LoopContext& ctx) {
    runanywhere::v1::ToolCallingOptions options = ctx.tool_options;
    options.set_format(ctx.format);
    options.set_max_tool_calls(static_cast<int32_t>(ctx.max_tool_calls));
    options.set_keep_tools_available(ctx.keep_tools_available);
    if (ctx.generation.max_tokens > 0) {
        options.set_max_tokens(ctx.generation.max_tokens);
    }
    if (ctx.generation.temperature > 0.0f) {
        options.set_temperature(ctx.generation.temperature);
    }
    if (!ctx.generation.system_prompt.empty()) {
        options.set_system_prompt(ctx.generation.system_prompt);
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
    options.set_auto_execute(ctx.auto_execute);
    options.set_replace_system_prompt(ctx.replace_system_prompt);
    options.set_require_json_arguments(ctx.require_json_arguments);
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

// The handle is allocated before any LLM work and published synchronously so
// hosts can fan it into a thread-safe cancellation sink before generation.
static rac_result_t run_loop_impl(const uint8_t* in_request_bytes, size_t in_size,
                                  rac_tool_execute_callback_fn on_execute,
                                  void* on_execute_user_data,
                                  rac_tool_calling_handle_published_callback_fn on_handle_published,
                                  void* on_handle_user_data, rac_proto_buffer_t* out_result) {
    if (!on_execute || !on_handle_published || !out_result) {
        return RAC_ERROR_NULL_POINTER;
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
    struct HandleScope {
        uint64_t handle;
        ~HandleScope() { unregister_loop_state(handle); }
    } scope{handle};

    // Fire the publication callback SYNCHRONOUSLY before any other work.
    // The callback runs on this thread, with the handle already registered
    // in the loop_registry, so a concurrent cancel from another thread
    // (e.g. Swift withTaskCancellationHandler) will land on the live state.
    on_handle_published(handle, on_handle_user_data);

    // Reuse ToolCallingSessionCreateRequest as the input shape.
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
    ctx.generation.max_tokens = request.max_tokens();
    ctx.generation.temperature = request.temperature();
    ctx.generation.top_p = request.top_p();
    ctx.generation.system_prompt = request.system_prompt();
    ctx.format = request.format() == runanywhere::v1::TOOL_CALL_FORMAT_NAME_UNSPECIFIED
                     ? runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON
                     : request.format();
    ctx.max_tool_calls =
        request.max_tool_calls() == 0 ? kDefaultMaxToolCalls : request.max_tool_calls();
    ctx.auto_execute = request.has_auto_execute() ? request.auto_execute() : true;
    ctx.replace_system_prompt = request.replace_system_prompt();
    ctx.require_json_arguments = request.require_json_arguments();
    ctx.keep_tools_available = request.keep_tools_available();
    ctx.generation.disable_thinking = request.disable_thinking();
    // Prior conversation turns (tool_calling.proto field 19). Threaded onto the
    // generation snapshot so EVERY generate in the loop inherits it — the initial
    // tool-decision generate (generation_for_tool_step copies base) and the
    // follow-up generate (followup_ctx = ctx copies it). request.history already
    // EXCLUDES the current turn (which travels as prompt) and is pre-alternated
    // [user,asst,...], so we forward it as-is and do NOT pop a trailing turn —
    // unlike llm_module's normalizer, whose history includes the current turn.
    ctx.generation.history.assign(request.history().begin(), request.history().end());
    // Defensive: the C ABI history slot is positional [user0, asst0, user1, ...];
    // an odd count means a trailing user turn with no assistant reply (e.g. the
    // prior turn's response was blank/filtered upstream). Drop it so the positional
    // role assignment stays aligned — the same net effect as the standard path's
    // trailing-user pop (llm_module.cpp), without needing role tags we don't carry.
    if (ctx.generation.history.size() % 2 != 0) {
        ctx.generation.history.pop_back();
    }
    // Honor ToolCallingSessionCreateRequest.validate_calls (idl/tool_calling.proto).
    // The field is `optional bool` so we can preserve the documented default
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
    std::string tool_choice_error;
    if (!apply_explicit_tool_choice(&ctx, &tool_choice_error)) {
        emit_failure(out_result, RAC_ERROR_INVALID_ARGUMENT, tool_choice_error);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::v1::ToolCallingResult final_result;
    std::string current_prompt = format_prompt_proto(ctx, /*tool_results=*/{});
    if (current_prompt.empty()) {
        current_prompt = ctx.user_prompt;
    }

    uint32_t iteration = 0;
    bool is_complete = false;
    std::string final_text;

    const auto finish_cancelled = [&]() -> rac_result_t {
        rac::llm::tool_calling::set_display_text_and_thinking(&final_result, final_text,
                                                              ctx.generation);
        final_result.set_is_complete(false);
        final_result.set_iterations_used(static_cast<int32_t>(iteration));
        final_result.set_error_code(RAC_ERROR_CANCELLED);
        final_result.set_error_message("LLM generation cancelled");
        std::vector<uint8_t> bytes;
        serialize(final_result, &bytes);
        rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
        return RAC_ERROR_CANCELLED;
    };

    // One telemetry row per tool-calling request; inner iterations are PUBLIC-only.
    rac::llm::tool_calling::ToolLoopTelemetryScope loop_telemetry;

    while (true) {
        iteration++;
        RAC_LOG_DEBUG(kTag, "generation iteration %u; tool calls %d/%u", iteration,
                      final_result.tool_calls_size(), ctx.max_tool_calls);

        std::string response;
        rac_result_t rc = RAC_SUCCESS;
        auto step_generation = rac::llm::tool_calling::generation_for_tool_step(
            ctx.generation, iteration, ctx.has_tool_choice, ctx.tool_choice, ctx.format);
        rac::llm::tool_calling::GenerationCancelBinding cancel_binding{
            &cancel_state->active_ref_mu, &cancel_state->active_ref,
            &cancel_state->cancel_requested, &cancel_state->generation_started};
        if (!rac::llm::tool_calling::run_generate_once(step_generation, cancel_binding,
                                                       current_prompt, &response, &rc,
                                                       &loop_telemetry.agg)) {
            // distinguish cancel from other generate
            // failures, mirroring run_generate_loop in tool_calling_session.cpp.
            // A cancel that latched before/during generate surfaces as
            // RAC_ERROR_CANCELLED with "LLM generation cancelled" so hosts can
            // branch on error_code instead of message string matching.
            const bool cancelled = cancel_state->cancel_requested.load(std::memory_order_acquire);
            const rac_result_t report_rc = cancelled ? RAC_ERROR_CANCELLED : rc;
            const char* msg = cancelled ? "LLM generation cancelled" : "LLM generation failed";
            rac::llm::tool_calling::set_display_text_and_thinking(&final_result, final_text,
                                                                  ctx.generation);
            final_result.set_is_complete(false);
            final_result.set_iterations_used(static_cast<int32_t>(iteration));
            final_result.set_error_code(static_cast<int32_t>(report_rc));
            final_result.set_error_message(msg);
            std::vector<uint8_t> bytes;
            serialize(final_result, &bytes);
            rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
            return report_rc;
        }
        // Preserve the thinking-tag lookup cached by run_generate_once without
        // leaking the decision-only sampling/token overrides into synthesis.
        ctx.generation.thinking_tags_resolved = step_generation.thinking_tags_resolved;
        ctx.generation.thinking_open_tag = std::move(step_generation.thinking_open_tag);
        ctx.generation.thinking_close_tag = std::move(step_generation.thinking_close_tag);

        if (cancel_state->cancel_requested.load(std::memory_order_acquire)) {
            return finish_cancelled();
        }

        std::string clean_text;
        runanywhere::v1::ToolCall parsed_call;
        const bool has_call = parse_tool_call_from_output(ctx, response, &clean_text, &parsed_call);
        final_text = clean_text;

        if (!has_call) {
            if (final_result.tool_calls_size() == 0 && tool_choice_requires_call(ctx)) {
                const std::string msg = missing_required_tool_call_error(ctx);
                final_result.set_error_code(RAC_ERROR_VALIDATION_FAILED);
                final_result.set_error_message(msg);
                is_complete = false;
                break;
            }
            RAC_LOG_DEBUG(kTag, "no tool call; loop complete after iter %u", iteration);
            is_complete = true;
            break;
        }

        if (static_cast<uint32_t>(final_result.tool_calls_size()) >= ctx.max_tool_calls) {
            constexpr const char* kLimitMessage =
                "model requested another tool after max_tool_calls was reached";
            final_result.set_error_code(RAC_ERROR_VALIDATION_FAILED);
            final_result.set_error_message(kLimitMessage);
            is_complete = false;
            break;
        }
        if (final_result.tool_calls_size() > 0 && !ctx.keep_tools_available) {
            constexpr const char* kToolsUnavailableMessage =
                "model requested another tool after tools were removed";
            final_result.set_error_code(RAC_ERROR_VALIDATION_FAILED);
            final_result.set_error_message(kToolsUnavailableMessage);
            is_complete = false;
            break;
        }

        // Tool-choice policy is an authorization constraint, not optional
        // schema validation. It must run even when validate_calls=false.
        const std::string policy_error = tool_choice_policy_error(ctx, parsed_call);
        if (!policy_error.empty()) {
            runanywhere::v1::ToolResult failed;
            failed.set_tool_call_id(parsed_call.id());
            failed.set_name(parsed_call.name());
            failed.set_error(policy_error);
            failed.set_success(false);
            failed.set_started_at_ms(now_ms());
            failed.set_completed_at_ms(now_ms());
            *final_result.add_tool_calls() = parsed_call;
            *final_result.add_tool_results() = failed;
            is_complete = false;
            final_result.set_error_code(RAC_ERROR_VALIDATION_FAILED);
            final_result.set_error_message(policy_error);
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

        if (!ctx.auto_execute) {
            *final_result.add_tool_calls() = parsed_call;
            is_complete = false;
            break;
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
        rac_result_t exec_rc = RAC_SUCCESS;
        {
            std::lock_guard<std::recursive_mutex> admission_guard(
                cancel_state->side_effect_admission_mu);
            if (cancel_state->cancel_requested.load(std::memory_order_acquire)) {
                return finish_cancelled();
            }
            exec_rc = on_execute(call_bytes.empty() ? nullptr : call_bytes.data(),
                                 call_bytes.size(), &exec_out, on_execute_user_data);
        }

        runanywhere::v1::ToolResult tool_result;
        std::string executor_error;
        if (exec_rc == RAC_SUCCESS && exec_out.status != RAC_SUCCESS) {
            exec_rc = exec_out.status;
            executor_error = exec_out.error_message ? exec_out.error_message
                                                    : "tool executor returned an error buffer";
        } else if (exec_rc == RAC_SUCCESS && (!exec_out.data || exec_out.size == 0)) {
            exec_rc = RAC_ERROR_DECODING_ERROR;
            executor_error = "tool executor returned an empty ToolResult";
        } else if (exec_rc == RAC_SUCCESS &&
                   !tool_result.ParseFromArray(exec_out.data, static_cast<int>(exec_out.size))) {
            exec_rc = RAC_ERROR_DECODING_ERROR;
            executor_error = "tool executor returned malformed ToolResult bytes";
        } else if (exec_rc == RAC_SUCCESS && !tool_result.tool_call_id().empty() &&
                   tool_result.tool_call_id() != parsed_call.id()) {
            exec_rc = RAC_ERROR_VALIDATION_FAILED;
            executor_error = "tool executor returned a mismatched tool_call_id";
        } else if (exec_rc == RAC_SUCCESS && !tool_result.name().empty() &&
                   tool_result.name() != parsed_call.name()) {
            exec_rc = RAC_ERROR_VALIDATION_FAILED;
            executor_error = "tool executor returned a mismatched tool name";
        }

        if (exec_rc != RAC_SUCCESS) {
            if (executor_error.empty()) {
                executor_error = exec_out.error_message ? exec_out.error_message
                                                        : "tool executor returned an error";
            }
            tool_result.Clear();
            tool_result.set_success(false);
            tool_result.set_error(executor_error);
        }
        tool_result.set_tool_call_id(parsed_call.id());
        tool_result.set_name(parsed_call.name());
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
        std::vector<runanywhere::v1::ToolResult> trs;
        trs.reserve(static_cast<size_t>(final_result.tool_results_size()));
        for (const auto& recorded_result : final_result.tool_results()) {
            trs.push_back(recorded_result);
        }
        LoopContext followup_ctx = ctx;
        if (static_cast<uint32_t>(final_result.tool_calls_size()) >= ctx.max_tool_calls) {
            followup_ctx.keep_tools_available = false;
        }
        std::string follow = format_prompt_proto(followup_ctx, trs);
        current_prompt = follow.empty() ? ctx.user_prompt : follow;
    }

    rac::llm::tool_calling::set_display_text_and_thinking(&final_result, final_text,
                                                          ctx.generation);
    rac::llm::tool_calling::ensure_web_search_attribution(&final_result);
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

extern "C" rac_result_t
rac_tool_calling_run_loop_proto(const uint8_t* in_request_bytes, size_t in_size,
                                rac_tool_execute_callback_fn on_execute, void* on_execute_user_data,
                                rac_tool_calling_handle_published_callback_fn on_handle_published,
                                void* on_handle_user_data, rac_proto_buffer_t* out_result) {
    return run_loop_impl(in_request_bytes, in_size, on_execute, on_execute_user_data,
                         on_handle_published, on_handle_user_data, out_result);
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
    {
        std::lock_guard<std::recursive_mutex> admission_guard(state->side_effect_admission_mu);
        state->cancel_requested.store(true, std::memory_order_release);
    }
    std::lock_guard<std::mutex> guard(state->active_ref_mu);
    if (state->active_ref) {
        rac::llm::request_lifecycle_llm_cancel(state->active_ref);
        if (state->generation_started && state->active_ref->ops && state->active_ref->ops->cancel) {
            (void)state->active_ref->ops->cancel(state->active_ref->impl);
        }
    }
    return RAC_SUCCESS;
#endif
}
