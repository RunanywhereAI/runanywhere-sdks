/**
 * @file tool_calling_session.cpp
 * @brief Tool-calling session state machine.
 *
 * Collapses the per-SDK 200-400 LOC tool-calling orchestration loop
 * (generate -> parse -> validate -> host-executes -> format follow-up
 * prompt -> generate) into one native session. SDK receives a stream
 * of ToolCallingSessionEvent (LLMStreamEvent / tool_call / final_result
 * / error) through a single callback.
 *
 * Reuses the existing proto primitives from tool_calling.cpp:
 *   - rac_tool_call_parse_proto       -> parse LLM output for tool calls
 *   - rac_tool_call_validate_proto    -> validate against registered tools
 *   - rac_tool_call_format_prompt_proto -> build initial + follow-up prompts
 *
 * And the existing LLM lifecycle-owned generation path:
 *   - acquire_lifecycle_llm + ops->generate
 *
 * SINGLE SOURCE OF TRUTH: the loop lives here. No per-SDK duplication.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/llm/tool_calling_generation_internal.h"
#include "features/llm/tool_calling_result_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "llm_service.pb.h"
#include "tool_calling.pb.h"
#endif

namespace {

constexpr const char* kTag = "ToolCallingSession";
constexpr uint32_t kDefaultMaxToolCalls = 5;

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

enum class SessionState {
    kIdle,
    kGenerating,
    kWaitingForTool,
    kCompleted,
    kFailed,
    kCancelled,
};

struct ToolCallingSession {
    uint64_t handle = 0;
    std::mutex mu;

    // In-flight LifecycleLlmRef tracking for cancel. The
    // generate caller holds `mu` while ops->generate runs; cancel calls must
    // come from another thread and CANNOT take `mu` (would deadlock). Instead
    // we publish a pointer to the in-flight ref under `active_ref_mu` (a
    // distinct mutex) and a `cancel_requested` atomic that latches a
    // pre-generate cancel so a cancel that arrives before active_ref is
    // published is still honored when generate eventually starts.
    std::mutex active_ref_mu;
    rac::llm::LifecycleLlmRef* active_ref = nullptr;
    bool generation_started = false;  // guarded by active_ref_mu
    std::recursive_mutex side_effect_admission_mu;
    std::atomic<bool> cancel_requested{false};
    std::atomic<bool> destroy_requested{false};

    rac_tool_calling_session_event_callback_fn callback = nullptr;
    void* user_data = nullptr;

    SessionState state = SessionState::kIdle;

    std::string user_prompt;
    runanywhere::v1::ToolCallFormatName format = runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON;
    uint32_t max_tool_calls = kDefaultMaxToolCalls;
    bool auto_execute = true;
    bool replace_system_prompt = false;
    bool require_json_arguments = false;
    bool keep_tools_available = false;
    bool validate_calls = true;

    rac::llm::tool_calling::GenerationState generation;
    rac::llm::tool_calling::GenerationTelemetryAgg telemetry;
    bool telemetry_published = false;  // guarded by mu

    // Request-level tool_choice / forced_tool_name overrides.
    bool has_tool_choice = false;
    runanywhere::v1::ToolChoiceMode tool_choice = runanywhere::v1::TOOL_CHOICE_MODE_UNSPECIFIED;
    std::string forced_tool_name;

    runanywhere::v1::ToolCallingOptions tool_options;

    uint32_t iteration = 0;
    uint64_t seq = 0;
    std::string current_prompt;
    std::vector<runanywhere::v1::ToolCall> all_tool_calls;
    std::vector<runanywhere::v1::ToolResult> all_tool_results;
    std::string final_text;
    std::string final_thinking_content;

    std::string pending_tool_call_id;
    std::string pending_tool_name;

    // Deferred-dispatch queue. emit_event runs
    // under session->mu (held by create_proto / step_with_result_proto while
    // run_generate_loop runs); invoking session.callback directly would
    // deadlock if the host callback re-entered rac_tool_calling_session_*
    // on the same handle. Instead we serialize the event under the lock,
    // append the bytes here, and dispatch after the lock is released by the
    // outer scope (see drain_and_dispatch).
    std::vector<std::vector<uint8_t>> pending_dispatches;
    std::atomic<int> callbacks_in_flight{0};
};

bool is_terminal(SessionState state) {
    return state == SessionState::kCompleted || state == SessionState::kFailed ||
           state == SessionState::kCancelled;
}

void publish_session_telemetry_once(ToolCallingSession& session) {
    if (session.telemetry_published) {
        return;
    }
    session.telemetry_published = true;
    rac::llm::tool_calling::publish_tool_loop_telemetry(session.telemetry);
}

struct SessionTelemetryTerminalScope {
    ToolCallingSession& session;
    ~SessionTelemetryTerminalScope() {
        if (is_terminal(session.state)) {
            publish_session_telemetry_once(session);
        }
    }
};

bool apply_explicit_tool_choice(ToolCallingSession* session, std::string* out_error) {
    if (!session) {
        return false;
    }

    // NONE is an authorization veto and must win over forced_tool_name.
    if (session->has_tool_choice &&
        session->tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) {
        session->forced_tool_name.clear();
        return true;
    }

    if (!session->forced_tool_name.empty()) {
        session->has_tool_choice = true;
        session->tool_choice = runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC;
    }

    if (!session->has_tool_choice ||
        session->tool_choice != runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC) {
        return true;
    }
    if (session->forced_tool_name.empty()) {
        if (out_error) {
            *out_error = "tool_choice=SPECIFIC requires a non-empty forced_tool_name";
        }
        return false;
    }
    for (const auto& tool : session->tool_options.tools()) {
        if (tool.name() == session->forced_tool_name) {
            return true;
        }
    }
    if (out_error) {
        *out_error = "tool_choice=SPECIFIC target is not present in request.tools: " +
                     session->forced_tool_name;
    }
    return false;
}

bool tool_choice_requires_call(const ToolCallingSession& session) {
    return session.has_tool_choice &&
           (session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED ||
            session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC);
}

std::string missing_required_tool_call_error(const ToolCallingSession& session) {
    return session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC
               ? "tool_choice=SPECIFIC requires a tool call"
               : "tool_choice=REQUIRED requires a tool call";
}

std::string tool_choice_policy_error(const ToolCallingSession& session,
                                     const runanywhere::v1::ToolCall& tool_call) {
    if (session.has_tool_choice && session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) {
        return "Tool calls are disabled by tool_choice=NONE";
    }
    if (session.has_tool_choice &&
        session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC &&
        tool_call.name() != session.forced_tool_name) {
        return "Tool call must use tool_choice=SPECIFIC target: " + session.forced_tool_name;
    }
    return {};
}

struct SessionRegistry {
    std::mutex mu;
    std::atomic<uint64_t> next_handle{1};
    std::unordered_map<uint64_t, std::shared_ptr<ToolCallingSession>> sessions;
};

SessionRegistry& registry() {
    static SessionRegistry inst;
    return inst;
}

std::shared_ptr<ToolCallingSession> lookup_session(uint64_t handle) {
    auto& reg = registry();
    std::lock_guard<std::mutex> lg(reg.mu);
    auto it = reg.sessions.find(handle);
    return it == reg.sessions.end() ? nullptr : it->second;
}

thread_local std::vector<ToolCallingSession*> g_dispatch_stack;

int current_thread_dispatch_depth(const ToolCallingSession* session) {
    int depth = 0;
    for (const auto* active_session : g_dispatch_stack) {
        if (active_session == session) {
            ++depth;
        }
    }
    return depth;
}

void emit_event(ToolCallingSession& session, runanywhere::v1::ToolCallingSessionEvent event) {
    event.set_seq(++session.seq);
    // Serialize under the lock the caller holds,
    // queue bytes for deferred dispatch. drain_and_dispatch (invoked after the
    // outer session_lock is released) fires session.callback for each entry.
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0) {
        (void)event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()));
    }
    session.pending_dispatches.push_back(std::move(bytes));
}

// Dispatch queued events after the caller has
// released session->mu. Snapshots the callback/user_data and pending bytes
// under the registry mutex via session.mu, then releases before invoking the
// host callback so a re-entrant call into rac_tool_calling_session_* on the
// same handle does not self-deadlock.
//
// The per-session in-flight count lets destroy wait only for callbacks that
// belong to this handle. The thread-local stack tracks nested dispatches for
// this session so a re-entrant destroy never waits for callback frames on its
// own thread.
void drain_and_dispatch(const std::shared_ptr<ToolCallingSession>& session) {
    if (!session)
        return;
    session->callbacks_in_flight.fetch_add(1, std::memory_order_acq_rel);
    struct DispatchGuard {
        ToolCallingSession& session;
        ~DispatchGuard() { session.callbacks_in_flight.fetch_sub(1, std::memory_order_acq_rel); }
    } dispatch_guard{*session};
    std::vector<std::vector<uint8_t>> drained;
    rac_tool_calling_session_event_callback_fn cb = nullptr;
    void* ud = nullptr;
    {
        std::lock_guard<std::mutex> lock(session->mu);
        if (session->pending_dispatches.empty()) {
            return;
        }
        drained.swap(session->pending_dispatches);
        cb = session->callback;
        ud = session->user_data;
    }
    if (!cb)
        return;
    struct DispatchMarker {
        explicit DispatchMarker(ToolCallingSession* current) {
            g_dispatch_stack.push_back(current);
        }
        ~DispatchMarker() { g_dispatch_stack.pop_back(); }
    } dispatch_marker{session.get()};
    for (auto& payload : drained) {
        if (session->destroy_requested.load(std::memory_order_acquire)) {
            break;
        }

        runanywhere::v1::ToolCallingSessionEvent event;
        const bool is_tool_call =
            !payload.empty() &&
            event.ParseFromArray(payload.data(), static_cast<int>(payload.size())) &&
            event.kind_case() == runanywhere::v1::ToolCallingSessionEvent::kToolCall;
        if (is_tool_call) {
            // The callback is the host-execution admission boundary. Holding
            // this recursive mutex through publication gives cancel/destroy a
            // deterministic winner while allowing either operation to be
            // called re-entrantly by the callback itself.
            std::lock_guard<std::recursive_mutex> admission_guard(
                session->side_effect_admission_mu);
            if (session->cancel_requested.load(std::memory_order_acquire) ||
                session->destroy_requested.load(std::memory_order_acquire)) {
                continue;
            }
            cb(payload.data(), payload.size(), ud);
        } else {
            cb(payload.empty() ? nullptr : payload.data(), payload.size(), ud);
        }

        // A callback may destroy its own session and free user_data as soon as
        // destroy returns. Never publish a later payload from this snapshot.
        if (session->destroy_requested.load(std::memory_order_acquire)) {
            break;
        }
    }
}

void emit_error_event(ToolCallingSession& session, int32_t c_abi_code, const std::string& message) {
    runanywhere::v1::SDKError sdk_error;
    sdk_error.set_message(message);
    sdk_error.set_c_abi_code(c_abi_code);
    sdk_error.set_component("llm");
    sdk_error.set_timestamp_ms(now_ms());
    std::string error_bytes;
    (void)sdk_error.SerializeToString(&error_bytes);

    runanywhere::v1::ToolCallingSessionEvent event;
    event.set_error_bytes(error_bytes);
    emit_event(session, std::move(event));
}

void emit_final_event(ToolCallingSession& session, bool is_complete) {
    runanywhere::v1::ToolCallingSessionEvent event;
    auto* final_result = event.mutable_final_result();
    final_result->set_text(session.final_text);
    if (!session.final_thinking_content.empty()) {
        final_result->set_thinking_content(session.final_thinking_content);
    }
    for (const auto& tc : session.all_tool_calls) {
        *final_result->add_tool_calls() = tc;
    }
    for (const auto& tr : session.all_tool_results) {
        *final_result->add_tool_results() = tr;
    }
    final_result->set_is_complete(is_complete);
    final_result->set_iterations_used(static_cast<int32_t>(session.iteration));
    rac::llm::tool_calling::ensure_web_search_attribution(final_result);
    emit_event(session, std::move(event));
}

void emit_llm_chunk(ToolCallingSession& session, const std::string& text, bool is_final,
                    const std::string& finish_reason) {
    runanywhere::v1::LLMStreamEvent stream;
    stream.set_seq(session.seq + 1);
    stream.set_timestamp_us(now_us());
    stream.set_token(text);
    stream.set_is_final(is_final);
    stream.set_kind(runanywhere::v1::TOKEN_KIND_ANSWER);
    if (is_final) {
        stream.set_event_kind(runanywhere::v1::LLM_STREAM_EVENT_KIND_COMPLETED);
        stream.set_finish_reason(finish_reason);
    } else {
        stream.set_event_kind(runanywhere::v1::LLM_STREAM_EVENT_KIND_TOKEN);
    }
    std::string stream_bytes;
    (void)stream.SerializeToString(&stream_bytes);

    runanywhere::v1::ToolCallingSessionEvent event;
    event.set_llm_stream_event_bytes(stream_bytes);
    emit_event(session, std::move(event));
}

void emit_tool_call_event(ToolCallingSession& session, const runanywhere::v1::ToolCall& call) {
    runanywhere::v1::ToolCallingSessionEvent event;
    *event.mutable_tool_call() = call;
    emit_event(session, std::move(event));
}

runanywhere::v1::ToolCallingOptions build_options_snapshot(const ToolCallingSession& session) {
    runanywhere::v1::ToolCallingOptions options = session.tool_options;
    options.set_format(session.format);
    options.set_max_tool_calls(static_cast<int32_t>(session.max_tool_calls));
    options.set_keep_tools_available(session.keep_tools_available);
    if (session.generation.max_tokens > 0) {
        options.set_max_tokens(session.generation.max_tokens);
    }
    if (session.generation.temperature > 0.0f) {
        options.set_temperature(session.generation.temperature);
    }
    if (!session.generation.system_prompt.empty()) {
        options.set_system_prompt(session.generation.system_prompt);
    }
    // Honor request-level tool_choice / forced_tool_name on the
    // snapshot consumed by the format/validate proto helpers.
    if (session.has_tool_choice) {
        options.set_tool_choice(session.tool_choice);
    }
    if (!session.forced_tool_name.empty()) {
        options.set_forced_tool_name(session.forced_tool_name);
    }
    options.set_auto_execute(session.auto_execute);
    options.set_replace_system_prompt(session.replace_system_prompt);
    options.set_require_json_arguments(session.require_json_arguments);
    return options;
}

std::string build_initial_prompt(const ToolCallingSession& session) {
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(session.user_prompt);
    *request.mutable_options() = build_options_snapshot(session);

    const size_t req_size = request.ByteSizeLong();
    std::vector<uint8_t> req_bytes(req_size);
    if (req_size > 0 &&
        !request.SerializeToArray(req_bytes.data(), static_cast<int>(req_bytes.size()))) {
        return {};
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_format_prompt_proto(
        req_bytes.empty() ? nullptr : req_bytes.data(), req_bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return {};
    }

    runanywhere::v1::ToolPromptFormatResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    rac_proto_buffer_free(&out);
    return result.formatted_prompt();
}

std::string build_followup_prompt(const ToolCallingSession& session, bool keep_tools_available) {
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(session.user_prompt);
    *request.mutable_options() = build_options_snapshot(session);
    request.mutable_options()->set_keep_tools_available(keep_tools_available);
    for (const auto& tool_result : session.all_tool_results) {
        *request.add_tool_results() = tool_result;
    }

    const size_t req_size = request.ByteSizeLong();
    std::vector<uint8_t> req_bytes(req_size);
    if (req_size > 0 &&
        !request.SerializeToArray(req_bytes.data(), static_cast<int>(req_bytes.size()))) {
        return {};
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_format_prompt_proto(
        req_bytes.empty() ? nullptr : req_bytes.data(), req_bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return {};
    }

    runanywhere::v1::ToolPromptFormatResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    rac_proto_buffer_free(&out);
    return result.formatted_prompt();
}

bool parse_tool_call_from_output(const ToolCallingSession& session, const std::string& llm_output,
                                 std::string* out_clean_text,
                                 runanywhere::v1::ToolCall* out_tool_call) {
    runanywhere::v1::ToolParseRequest request;
    request.set_text(llm_output);
    auto* options = request.mutable_options();
    *options = build_options_snapshot(session);

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
validate_tool_call(const ToolCallingSession& session, const runanywhere::v1::ToolCall& tool_call) {
    runanywhere::v1::ToolCallValidationRequest request;
    *request.mutable_tool_call() = tool_call;
    *request.mutable_options() = build_options_snapshot(session);

    runanywhere::v1::ToolCallValidationResult empty_result;
    const size_t req_size = request.ByteSizeLong();
    std::vector<uint8_t> req_bytes(req_size);
    if (req_size > 0 &&
        !request.SerializeToArray(req_bytes.data(), static_cast<int>(req_bytes.size()))) {
        empty_result.set_is_valid(false);
        empty_result.set_error_message("failed to serialize validation request");
        return empty_result;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_call_validate_proto(req_bytes.empty() ? nullptr : req_bytes.data(),
                                                   req_bytes.size(), &out);

    runanywhere::v1::ToolCallValidationResult result;
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

void run_generate_loop(ToolCallingSession& session) {
    // A session may suspend for host tool execution between generations. Keep
    // one aggregate across every step and publish only when the logical
    // request becomes terminal (or is explicitly destroyed while suspended).
    SessionTelemetryTerminalScope telemetry_scope{session};

    session.iteration++;
    RAC_LOG_DEBUG(kTag, "generation iteration %u; tool calls %zu/%u", session.iteration,
                  session.all_tool_calls.size(), session.max_tool_calls);

    std::string response;
    rac_result_t rc = RAC_SUCCESS;
    auto step_generation = rac::llm::tool_calling::generation_for_tool_step(
        session.generation, session.iteration, session.has_tool_choice, session.tool_choice,
        session.format);
    // Grammar-constrain (QHexRT) only while a tool call is still possible this turn.
    // Drop the grammar (unconstrained decoding) when: (a) tool_choice=NONE — calls
    // are forbidden, so a "chat OR one call" grammar must not invite one (it would
    // be emitted then rejected); or (b) a call already ran and tools are not kept
    // available — a synthesis turn producing free-form text.
    if ((session.has_tool_choice && session.tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) ||
        (!session.all_tool_calls.empty() && !session.keep_tools_available)) {
        step_generation.tool_names.clear();
    }
    rac::llm::tool_calling::GenerationCancelBinding cancel_binding{
        &session.active_ref_mu, &session.active_ref, &session.cancel_requested,
        &session.generation_started};
    if (!rac::llm::tool_calling::run_generate_once(step_generation, cancel_binding,
                                                   session.current_prompt, &response, &rc,
                                                   &session.telemetry)) {
        // Distinguish cancel from other generate failures.
        // A cancel that landed before or during generate makes the session
        // terminal — emit a cancel error and mark state kCancelled so the
        // public step_with_result_proto guard rejects further steps.
        const bool cancelled = session.cancel_requested.load(std::memory_order_acquire);
        const char* msg = cancelled ? "LLM generation cancelled" : "LLM generation failed";
        emit_error_event(session, static_cast<int32_t>(rc), msg);
        session.state = cancelled ? SessionState::kCancelled : SessionState::kFailed;
        return;
    }

    session.generation.thinking_tags_resolved = step_generation.thinking_tags_resolved;
    session.generation.thinking_open_tag = std::move(step_generation.thinking_open_tag);
    session.generation.thinking_close_tag = std::move(step_generation.thinking_close_tag);

    if (session.cancel_requested.load(std::memory_order_acquire)) {
        emit_error_event(session, RAC_ERROR_CANCELLED, "LLM generation cancelled");
        session.state = SessionState::kCancelled;
        return;
    }

    std::string clean_text;
    runanywhere::v1::ToolCall parsed_call;
    const bool has_call = parse_tool_call_from_output(session, response, &clean_text, &parsed_call);

    rac::llm::tool_calling::split_display_text_and_thinking(
        clean_text, &session.final_text, &session.final_thinking_content, session.generation);

    if (!has_call) {
        if (session.all_tool_calls.empty() && tool_choice_requires_call(session)) {
            emit_error_event(session, RAC_ERROR_VALIDATION_FAILED,
                             missing_required_tool_call_error(session));
            session.state = SessionState::kFailed;
            return;
        }
        emit_llm_chunk(session, session.final_text, true, "stop");
        RAC_LOG_DEBUG(kTag, "no tool call found; loop complete");
        emit_final_event(session, true);
        session.state = SessionState::kCompleted;
        return;
    }

    if (session.all_tool_calls.size() >= session.max_tool_calls) {
        emit_error_event(session, RAC_ERROR_VALIDATION_FAILED,
                         "model requested another tool after max_tool_calls was reached");
        session.state = SessionState::kFailed;
        return;
    }

    // Tool-choice policy is an authorization constraint, not optional
    // schema validation. It must run even when validate_calls=false.
    const std::string policy_error = tool_choice_policy_error(session, parsed_call);
    if (!policy_error.empty()) {
        runanywhere::v1::ToolResult failed;
        failed.set_tool_call_id(parsed_call.id());
        failed.set_name(parsed_call.name());
        failed.set_error(policy_error);
        failed.set_success(false);
        failed.set_started_at_ms(now_ms());
        failed.set_completed_at_ms(now_ms());
        session.all_tool_calls.push_back(parsed_call);
        session.all_tool_results.push_back(failed);

        emit_error_event(session, RAC_ERROR_VALIDATION_FAILED, policy_error);
        session.state = SessionState::kFailed;
        return;
    }

    emit_llm_chunk(session, session.final_text, true, "stop");

    if (!session.all_tool_calls.empty() && !session.keep_tools_available) {
        emit_error_event(session, RAC_ERROR_VALIDATION_FAILED,
                         "model requested another tool after tools were removed");
        session.state = SessionState::kFailed;
        return;
    }

    if (session.validate_calls) {
        auto validation = validate_tool_call(session, parsed_call);
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
            session.all_tool_calls.push_back(parsed_call);
            session.all_tool_results.push_back(failed);

            emit_error_event(session, RAC_ERROR_VALIDATION_FAILED, msg);
            session.state = SessionState::kFailed;
            return;
        }

        if (!validation.normalized_arguments_json().empty()) {
            parsed_call.set_arguments_json(validation.normalized_arguments_json());
        }
    }

    if (!session.auto_execute) {
        std::lock_guard<std::recursive_mutex> admission_guard(session.side_effect_admission_mu);
        if (session.cancel_requested.load(std::memory_order_acquire)) {
            emit_error_event(session, RAC_ERROR_CANCELLED, "LLM generation cancelled");
            session.state = SessionState::kCancelled;
            return;
        }
        session.all_tool_calls.push_back(parsed_call);
        emit_final_event(session, false);
        session.state = SessionState::kCompleted;
        return;
    }

    {
        std::lock_guard<std::recursive_mutex> admission_guard(session.side_effect_admission_mu);
        if (session.cancel_requested.load(std::memory_order_acquire)) {
            emit_error_event(session, RAC_ERROR_CANCELLED, "LLM generation cancelled");
            session.state = SessionState::kCancelled;
            return;
        }
        session.all_tool_calls.push_back(parsed_call);
        session.pending_tool_call_id = parsed_call.id();
        session.pending_tool_name = parsed_call.name();
        emit_tool_call_event(session, parsed_call);
        session.state = SessionState::kWaitingForTool;
    }
    return;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_tool_calling_session_create_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_tool_calling_session_event_callback_fn callback, void* user_data,
    rac_tool_calling_handle_published_callback_fn on_handle_published, void* on_handle_user_data) {
    if (!callback || !on_handle_published) {
        return RAC_ERROR_NULL_POINTER;
    }

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)user_data;
    (void)on_handle_user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (request_proto_size > 0 && !request_proto_bytes) {
        return RAC_ERROR_NULL_POINTER;
    }

    runanywhere::v1::ToolCallingSessionCreateRequest request;
    if (request_proto_size > 0 &&
        !request.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.prompt().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto session = std::make_shared<ToolCallingSession>();
    session->callback = callback;
    session->user_data = user_data;

    session->user_prompt = request.prompt();
    session->generation.max_tokens = request.max_tokens();
    session->generation.temperature = request.temperature();
    session->generation.top_p = request.top_p();
    session->generation.system_prompt = request.system_prompt();
    session->generation.disable_thinking = request.disable_thinking();
    // Prior conversation turns (tool_calling.proto field 19). The session path
    // shares run_generate_once (via generation_for_tool_step), which flattens
    // generation.history into options.history for EVERY generate — so setting it
    // here gives Web/Flutter (session ABI) the same multi-turn context the
    // run-loop ABI already threads. request.history already EXCLUDES the current
    // turn and is pre-alternated [user,asst,...]; drop a dangling trailing turn
    // on an odd count so the positional role assignment stays aligned (mirrors
    // tool_calling_run_loop.cpp and the standard path's trailing-user pop).
    session->generation.history.assign(request.history().begin(), request.history().end());
    if (session->generation.history.size() % 2 != 0) {
        session->generation.history.pop_back();
    }

    session->format = request.format() == runanywhere::v1::TOOL_CALL_FORMAT_NAME_UNSPECIFIED
                          ? runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON
                          : request.format();
    session->max_tool_calls =
        request.max_tool_calls() == 0 ? kDefaultMaxToolCalls : request.max_tool_calls();
    session->auto_execute = request.has_auto_execute() ? request.auto_execute() : true;
    session->replace_system_prompt = request.replace_system_prompt();
    session->require_json_arguments = request.require_json_arguments();
    session->keep_tools_available = request.keep_tools_available();
    // Honor ToolCallingSessionCreateRequest.validate_calls (idl/tool_calling.proto).
    // The field is `optional bool` so we can preserve the documented default
    // (validate=true) when the caller did not set it, while still letting hosts
    // that delegate validation/authorization to their executor opt out by
    // explicitly setting validate_calls=false.
    session->validate_calls = request.has_validate_calls() ? request.validate_calls() : true;
    // Pick up the OpenAI-style request-level tool_choice and
    // forced_tool_name knobs (idl/tool_calling.proto fields 7/8).
    if (request.has_tool_choice()) {
        session->has_tool_choice = true;
        session->tool_choice = request.tool_choice();
    }
    if (request.has_forced_tool_name()) {
        session->forced_tool_name = request.forced_tool_name();
    }

    for (const auto& tool : request.tools()) {
        *session->tool_options.add_tools() = tool;
        // Names drive the QHexRT grammar spec (RUN-80); ignored by non-grammar engines.
        session->generation.tool_names.push_back(tool.name());
    }

    std::string tool_choice_error;
    if (!apply_explicit_tool_choice(session.get(), &tool_choice_error)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto& reg = registry();
    uint64_t handle = reg.next_handle.fetch_add(1, std::memory_order_relaxed);
    session->handle = handle;
    {
        std::lock_guard<std::mutex> lg(reg.mu);
        reg.sessions[handle] = session;
    }
    // Publish the handle before generation can suspend through Asyncify/JSPI
    // or block a worker isolate. Every SDK can therefore cancel the initial
    // generation while this function is still in flight.
    on_handle_published(handle, on_handle_user_data);

    // Hold session->mu while run_generate_loop
    // queues events into session.pending_dispatches, then release the lock
    // BEFORE drain_and_dispatch fires the host callback so a re-entrant
    // step_with_result_proto / cancel / destroy from inside the callback
    // does not deadlock on session->mu.
    {
        std::lock_guard<std::mutex> session_lock(session->mu);

        session->current_prompt = build_initial_prompt(*session);
        if (session->current_prompt.empty()) {
            session->current_prompt = session->user_prompt;
        }

        session->state = SessionState::kGenerating;
        run_generate_loop(*session);
    }
    drain_and_dispatch(session);

    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t
rac_tool_calling_session_step_with_result_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (request_proto_size > 0 && !request_proto_bytes) {
        return RAC_ERROR_NULL_POINTER;
    }

    runanywhere::v1::ToolCallingSessionStepWithResultRequest request;
    if (request_proto_size > 0 &&
        !request.ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    auto session = lookup_session(request.session_handle());
    if (!session) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    // Hold session->mu only while we mutate
    // session state and let run_generate_loop queue events. Drop the lock
    // BEFORE dispatching queued events so a host callback that re-enters
    // step_with_result_proto / cancel / destroy on the same handle does not
    // deadlock on session->mu.
    {
        std::lock_guard<std::mutex> session_lock(session->mu);
        // A cancelled session is terminal. Once
        // rac_tool_calling_session_cancel_proto has latched cancel_requested, any
        // follow-up step_with_result_proto must be rejected so the host cannot
        // silently feed the cancelled session more iterations (which would then
        // auto-cancel at the first generate boundary because the per-session
        // atomic survives every state transition). The host must destroy and
        // recreate the session to continue.
        if (session->cancel_requested.load(std::memory_order_acquire) ||
            session->state == SessionState::kCancelled) {
            RAC_LOG_WARNING(kTag, "step_with_result called on cancelled session");
            return RAC_ERROR_INVALID_STATE;
        }
        if (session->state != SessionState::kWaitingForTool) {
            RAC_LOG_WARNING(kTag, "step_with_result called in state %d (expected kWaitingForTool)",
                            static_cast<int>(session->state));
            return RAC_ERROR_INVALID_STATE;
        }
        if (!request.tool_call_id().empty() &&
            request.tool_call_id() != session->pending_tool_call_id) {
            RAC_LOG_WARNING(kTag, "step_with_result tool_call_id does not match pending call");
            return RAC_ERROR_VALIDATION_FAILED;
        }

        runanywhere::v1::ToolResult tr;
        tr.set_tool_call_id(request.tool_call_id().empty() ? session->pending_tool_call_id
                                                           : request.tool_call_id());
        tr.set_name(session->pending_tool_name);
        const bool has_error = request.has_error() && !request.error().empty();
        if (has_error) {
            tr.set_error(request.error());
            tr.set_success(false);
        } else {
            tr.set_result_json(request.result_json().empty() ? std::string("{}")
                                                             : request.result_json());
            tr.set_success(true);
        }
        tr.set_started_at_ms(now_ms());
        tr.set_completed_at_ms(now_ms());
        session->all_tool_results.push_back(tr);

        const bool can_call_more_tools = session->keep_tools_available &&
                                         session->all_tool_calls.size() < session->max_tool_calls;
        session->current_prompt = build_followup_prompt(*session, can_call_more_tools);
        if (session->current_prompt.empty()) {
            session->current_prompt = session->user_prompt;
        }

        session->pending_tool_call_id.clear();
        session->pending_tool_name.clear();
        session->state = SessionState::kGenerating;
        run_generate_loop(*session);
    }
    drain_and_dispatch(session);

    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_tool_calling_session_destroy_proto(uint64_t session_handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_handle;
    return RAC_SUCCESS;  // idempotent — protobuf-less builds never create a session
#else
    if (session_handle == 0) {
        return RAC_SUCCESS;
    }
    // Quiesce before returning. Two races to
    // close:
    //   (a) a concurrent rac_tool_calling_session_step_with_result_proto /
    //       create_proto is still inside run_generate_loop holding
    //       session->mu — the inner session_lock acquire/release below
    //       serializes against that path; AND
    //   (b) drain_and_dispatch is between releasing session->mu and firing
    //       cb(payload, size, ud). A per-session in-flight counter closes that
    //       gap without coupling teardown to unrelated sessions.
    std::shared_ptr<ToolCallingSession> session;
    auto& reg = registry();
    {
        std::lock_guard<std::mutex> lg(reg.mu);
        auto it = reg.sessions.find(session_handle);
        if (it == reg.sessions.end()) {
            return RAC_SUCCESS;  // idempotent
        }
        session = it->second;
        reg.sessions.erase(it);
    }
    if (!session) {
        return RAC_SUCCESS;
    }
    // Latch cancel so any in-flight generate exits at the next cancel
    // boundary instead of dragging out the destroy by max_tool_calls.
    {
        std::lock_guard<std::recursive_mutex> admission_guard(session->side_effect_admission_mu);
        session->destroy_requested.store(true, std::memory_order_release);
        session->cancel_requested.store(true, std::memory_order_release);
    }
    {
        std::lock_guard<std::mutex> guard(session->active_ref_mu);
        if (session->active_ref) {
            rac::llm::request_lifecycle_llm_cancel(session->active_ref);
            if (session->generation_started && session->active_ref->ops &&
                session->active_ref->ops->cancel) {
                (void)session->active_ref->ops->cancel(session->active_ref->impl);
            }
        }
    }
    // Block until the in-flight create/step releases session->mu, then null
    // out the host callback/user_data so any NEW drain_and_dispatch cycle
    // that races us (e.g. a dispatch the in-flight generate had not yet
    // queued when we acquired the lock) snapshots cb=nullptr and exits
    // without invoking the host. The shared_ptr we hold keeps
    // pending_dispatches bytes alive long enough for that snapshot.
    {
        std::lock_guard<std::mutex> session_lock(session->mu);
        publish_session_telemetry_once(*session);
        session->callback = nullptr;
        session->user_data = nullptr;
    }
    // Wait only for this session's callbacks. When destroy is called through
    // nested callbacks, every frame for this session on the current thread is
    // allowed to unwind naturally; waiting for any of them would deadlock.
    // Other threads' callbacks must still drain.
    const int own_callback_depth = current_thread_dispatch_depth(session.get());
    while (session->callbacks_in_flight.load(std::memory_order_acquire) > own_callback_depth) {
        std::this_thread::yield();
    }
    // session shared_ptr goes out of scope here; if no other thread holds it,
    // the ToolCallingSession is freed and any leftover pending_dispatches
    // bytes are released along with it. The host can now safely free user_data.
    return RAC_SUCCESS;
#endif  // RAC_HAVE_PROTOBUF
}

extern "C" rac_result_t rac_tool_calling_session_cancel_proto(uint64_t session_handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_handle;
    return RAC_SUCCESS;  // idempotent — protobuf-less builds never start a session
#else
    if (session_handle == 0) {
        // Idempotent — zero handle means the SDK adapter raced cancel
        // against create/destroy. Treat as a successful no-op so adapters
        // can fan structured-concurrency cancels in without coordinating
        // with session lifetime (matches run_loop_cancel_proto semantics).
        return RAC_SUCCESS;
    }
    auto session = lookup_session(session_handle);
    if (!session) {
        // Idempotent — handle already retired or never published. The SDK
        // adapters fan structured-concurrency cancels into this entry point
        // without coordinating with session destroy, so a stale handle is
        // the normal race-loser path. Return success (matches
        // run_loop_cancel_proto semantics).
        return RAC_SUCCESS;
    }
    // Latch the cancel request first so a generate that
    // hasn't yet published active_ref will pick it up when it starts, then
    // forward to the in-flight ref if one is currently published. We hold
    // active_ref_mu (NOT session.mu, which the generate caller holds).
    //
    // Setting cancel_requested makes the session terminal —
    // subsequent rac_tool_calling_session_step_with_result_proto calls will
    // be rejected with RAC_ERROR_INVALID_STATE (see the guard at the top of
    // that function). Hosts must destroy the session and create a new one
    // to continue tool-calling after a cancel. We cannot also write
    // session->state here because the generate caller holds session.mu;
    // run_generate_loop maps the cancelled-generate exit to
    // SessionState::kCancelled when it observes cancel_requested.
    {
        std::lock_guard<std::recursive_mutex> admission_guard(session->side_effect_admission_mu);
        session->cancel_requested.store(true, std::memory_order_release);
    }
    std::lock_guard<std::mutex> guard(session->active_ref_mu);
    if (session->active_ref) {
        rac::llm::request_lifecycle_llm_cancel(session->active_ref);
        if (session->generation_started && session->active_ref->ops &&
            session->active_ref->ops->cancel) {
            (void)session->active_ref->ops->cancel(session->active_ref->impl);
        }
    }
    return RAC_SUCCESS;
#endif
}
