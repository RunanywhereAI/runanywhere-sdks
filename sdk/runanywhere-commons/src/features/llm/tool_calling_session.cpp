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

#include "features/llm/llm_thinking_directive_internal.h"
#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "llm_service.pb.h"
#include "tool_calling.pb.h"
#endif

namespace {

constexpr const char* kTag = "ToolCallingSession";
constexpr uint32_t kDefaultMaxIterations = 5;

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

void split_display_text_and_thinking(const std::string& raw_text, std::string* out_text,
                                     std::string* out_thinking) {
    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    if (rac_llm_extract_thinking(raw_text.c_str(), &response, &response_len, &thinking,
                                 &thinking_len) != RAC_SUCCESS) {
        if (out_text) {
            *out_text = raw_text;
        }
        if (out_thinking) {
            out_thinking->clear();
        }
        return;
    }

    if (out_text) {
        *out_text = response ? std::string(response, response_len) : std::string();
    }
    if (out_thinking) {
        *out_thinking =
            (thinking && thinking_len > 0) ? std::string(thinking, thinking_len) : std::string();
    }
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
    std::atomic<bool> cancel_requested{false};

    rac_tool_calling_session_event_callback_fn callback = nullptr;
    void* user_data = nullptr;

    SessionState state = SessionState::kIdle;

    std::string user_prompt;
    std::string format_hint;
    uint32_t max_iterations = kDefaultMaxIterations;
    bool keep_tools_available = false;
    bool validate_calls = true;

    int32_t max_tokens = 0;
    float temperature = 0.0f;
    float top_p = 0.0f;
    std::string system_prompt;
    // Suppress the model thinking phase on every generate in the session
    // (ToolCallingSessionCreateRequest.disable_thinking).
    bool disable_thinking = false;

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
};

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

// Process-global in-flight counter for the
// tool-calling-session event dispatcher. Mirrors the rac_llm_proto_quiesce /
// rac_vlm_proto_quiesce / rac_stt_proto_quiesce pattern. drain_and_dispatch
// snapshots (callback, user_data) under session->mu, releases the lock, then
// fires the host callback. A concurrent rac_tool_calling_session_destroy_proto
// can race the dispatcher between the unlock and the callback fire, freeing
// user_data before cb(payload, size, ud) executes. The InFlightGuard wraps the
// entire drain_and_dispatch so rac_tool_calling_session_proto_quiesce() can
// spin-wait until every pending callback has returned before destroy returns
// to the host.
std::atomic<int>& tool_calling_session_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

struct ToolCallingSessionInFlightGuard {
    ToolCallingSessionInFlightGuard() {
        tool_calling_session_in_flight().fetch_add(1, std::memory_order_acq_rel);
    }
    ~ToolCallingSessionInFlightGuard() {
        tool_calling_session_in_flight().fetch_sub(1, std::memory_order_acq_rel);
    }
    ToolCallingSessionInFlightGuard(const ToolCallingSessionInFlightGuard&) = delete;
    ToolCallingSessionInFlightGuard& operator=(const ToolCallingSessionInFlightGuard&) = delete;
};

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
// Hold a ToolCallingSessionInFlightGuard for
// the entire body so rac_tool_calling_session_proto_quiesce() can spin-wait
// until every pending callback has returned. Without the guard,
// rac_tool_calling_session_destroy_proto can return while this function is
// between releasing session->mu (after snapshotting cb/ud) and firing
// cb(payload, size, ud), letting the host free user_data before the
// callback executes — yielding a use-after-free on ud.
void drain_and_dispatch(const std::shared_ptr<ToolCallingSession>& session) {
    if (!session)
        return;
    ToolCallingSessionInFlightGuard in_flight_guard;
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
    for (auto& payload : drained) {
        cb(payload.empty() ? nullptr : payload.data(), payload.size(), ud);
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
    options.set_format_hint(session.format_hint);
    options.set_max_iterations(static_cast<int32_t>(session.max_iterations));
    options.set_keep_tools_available(session.keep_tools_available);
    if (session.max_tokens > 0) {
        options.set_max_tokens(session.max_tokens);
    }
    if (session.temperature > 0.0f) {
        options.set_temperature(session.temperature);
    }
    if (!session.system_prompt.empty()) {
        options.set_system_prompt(session.system_prompt);
    }
    // Honor request-level tool_choice / forced_tool_name on the
    // snapshot consumed by the format/validate proto helpers.
    if (session.has_tool_choice) {
        options.set_tool_choice(session.tool_choice);
    }
    if (!session.forced_tool_name.empty()) {
        options.set_forced_tool_name(session.forced_tool_name);
    }
    options.set_auto_execute(true);
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

std::string build_followup_prompt(const ToolCallingSession& session,
                                  const runanywhere::v1::ToolResult& tool_result) {
    runanywhere::v1::ToolPromptFormatRequest request;
    request.set_user_prompt(session.user_prompt);
    *request.mutable_options() = build_options_snapshot(session);
    *request.add_tool_results() = tool_result;

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

bool run_generate_once(ToolCallingSession& session, const std::string& prompt,
                       std::string* out_response, rac_result_t* out_rc) {
    rac::llm::LifecycleLlmRef ref;
    rac_result_t rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        if (out_rc)
            *out_rc = rc;
        return false;
    }

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    if (session.max_tokens > 0) {
        options.max_tokens = session.max_tokens;
    }
    if (session.temperature > 0.0f) {
        options.temperature = session.temperature;
    }
    if (session.top_p > 0.0f) {
        options.top_p = session.top_p;
    }
    options.streaming_enabled = RAC_FALSE;
    options.system_prompt = session.system_prompt.empty() ? nullptr : session.system_prompt.c_str();
    options.disable_thinking = session.disable_thinking ? RAC_TRUE : RAC_FALSE;

    rac::llm::clear_lifecycle_llm_cancel(&ref);

    rac_llm_result_t raw{};
    if (!ref.ops || !ref.ops->generate) {
        rac::llm::release_lifecycle_llm(&ref);
        if (out_rc)
            *out_rc = RAC_ERROR_NOT_SUPPORTED;
        return false;
    }

    // Publish the in-flight ref so cancel calls from other
    // threads can interrupt this generate. If a cancel arrived before we
    // got here, latch it onto the ref now.
    {
        std::lock_guard<std::mutex> guard(session.active_ref_mu);
        session.active_ref = &ref;
        if (session.cancel_requested.load(std::memory_order_acquire)) {
            rac::llm::request_lifecycle_llm_cancel(&ref);
        }
    }

    // Apply the no-think directive at the prompt level when requested (same
    // contract as the rac_llm_generate / proto generate sites).
    const std::string effective_prompt =
        rac::llm::apply_no_think_directive(prompt, options.disable_thinking);
    rc = ref.ops->generate(ref.impl, effective_prompt.c_str(), &options, &raw);

    // Unpublish before the ref goes out of scope.
    {
        std::lock_guard<std::mutex> guard(session.active_ref_mu);
        session.active_ref = nullptr;
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

void run_generate_loop(ToolCallingSession& session) {
    while (session.iteration < session.max_iterations) {
        session.iteration++;
        RAC_LOG_DEBUG(kTag, "iteration %u/%u", session.iteration, session.max_iterations);

        std::string response;
        rac_result_t rc = RAC_SUCCESS;
        if (!run_generate_once(session, session.current_prompt, &response, &rc)) {
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

        std::string clean_text;
        runanywhere::v1::ToolCall parsed_call;
        const bool has_call =
            parse_tool_call_from_output(session, response, &clean_text, &parsed_call);

        split_display_text_and_thinking(clean_text, &session.final_text,
                                        &session.final_thinking_content);
        emit_llm_chunk(session, session.final_text, true, "stop");

        if (!has_call) {
            RAC_LOG_DEBUG(kTag, "no tool call found; loop complete");
            emit_final_event(session, true);
            session.state = SessionState::kCompleted;
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

        session.all_tool_calls.push_back(parsed_call);
        session.pending_tool_call_id =
            parsed_call.call_id().empty() ? parsed_call.id() : parsed_call.call_id();
        session.pending_tool_name = parsed_call.name();

        emit_tool_call_event(session, parsed_call);

        session.state = SessionState::kWaitingForTool;
        return;
    }

    RAC_LOG_DEBUG(kTag, "max_iterations %u reached", session.max_iterations);
    emit_final_event(session, true);
    session.state = SessionState::kCompleted;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t
rac_tool_calling_session_create_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                      rac_tool_calling_session_event_callback_fn callback,
                                      void* user_data, uint64_t* out_session_handle) {
    if (!callback || !out_session_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_session_handle = 0;

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)user_data;
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
    session->max_tokens = request.max_tokens();
    session->temperature = request.temperature();
    session->top_p = request.top_p();
    session->system_prompt = request.system_prompt();
    session->disable_thinking = request.disable_thinking();

    session->format_hint =
        request.format_hint().empty() ? std::string("default") : request.format_hint();
    session->max_iterations =
        request.max_iterations() == 0 ? kDefaultMaxIterations : request.max_iterations();
    session->keep_tools_available = request.keep_tools_available();
    // Honor ToolCallingSessionCreateRequest.validate_calls (idl/tool_calling.proto).
    // The field is `optional bool` so we can preserve the historical default
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
    }

    auto& reg = registry();
    uint64_t handle = reg.next_handle.fetch_add(1, std::memory_order_relaxed);
    session->handle = handle;
    {
        std::lock_guard<std::mutex> lg(reg.mu);
        reg.sessions[handle] = session;
    }

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

    *out_session_handle = handle;
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
        tr.set_call_id(tr.tool_call_id());
        tr.set_started_at_ms(now_ms());
        tr.set_completed_at_ms(now_ms());
        session->all_tool_results.push_back(tr);

        session->current_prompt = build_followup_prompt(*session, tr);
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
    //   (b) drain_and_dispatch is between releasing session->mu (after
    //       snapshotting cb/ud) and firing cb(payload, size, ud) — the
    //       acquire/release of session->mu does NOT cover this gap, so we
    //       additionally clear the callback under the lock and then call
    //       rac_tool_calling_session_proto_quiesce() to spin-wait for any
    //       in-progress dispatch to drain. Mirrors rac_vlm_proto_quiesce /
    //       rac_llm_proto_quiesce / voice_agent destroy (voice_agent.cpp:598).
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
    // boundary instead of dragging out the destroy by max_iterations.
    session->cancel_requested.store(true, std::memory_order_release);
    {
        std::lock_guard<std::mutex> guard(session->active_ref_mu);
        if (session->active_ref) {
            rac::llm::request_lifecycle_llm_cancel(session->active_ref);
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
        session->callback = nullptr;
        session->user_data = nullptr;
    }
    // Spin-wait for any drain_and_dispatch that snapshotted cb/ud BEFORE we
    // cleared them above to finish firing the host callback. This is the
    // load-bearing barrier for race (b) in the comment above — without it,
    // destroy_proto can return while cb(payload, size, ud) is mid-flight on
    // another thread and the host then frees user_data.
    rac_tool_calling_session_proto_quiesce();
    // session shared_ptr goes out of scope here; if no other thread holds it,
    // the ToolCallingSession is freed and any leftover pending_dispatches
    // bytes are released along with it. The host can now safely free user_data.
    return RAC_SUCCESS;
#endif  // RAC_HAVE_PROTOBUF
}

// Public quiesce helper. Spin-waits until every
// in-flight drain_and_dispatch invocation has returned. Mirrors
// rac_llm_proto_quiesce / rac_vlm_proto_quiesce / rac_stt_proto_quiesce.
// Called from rac_tool_calling_session_destroy_proto and exposed to SDK
// bridges that need to coordinate user_data lifetime with a concurrent
// tool-calling event dispatcher. Safe to call from any thread.
extern "C" void rac_tool_calling_session_proto_quiesce(void) {
#if defined(RAC_HAVE_PROTOBUF)
    while (tool_calling_session_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
#endif
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
    session->cancel_requested.store(true, std::memory_order_release);
    std::lock_guard<std::mutex> guard(session->active_ref_mu);
    if (session->active_ref) {
        rac::llm::request_lifecycle_llm_cancel(session->active_ref);
    }
    return RAC_SUCCESS;
#endif
}
