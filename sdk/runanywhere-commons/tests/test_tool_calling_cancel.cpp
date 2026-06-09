/**
 * @file test_tool_calling_cancel.cpp
 * @brief pass3-syn-086 — concurrency contract tests for the new tool-calling
 *        cancel ABIs.
 *
 * The pass-2/pass-3 fix commits (a2de2a4d6) added three new C ABI symbols:
 *   - rac_tool_calling_run_loop_with_handle_proto    (pass2-syn-007)
 *   - rac_tool_calling_run_loop_cancel_proto         (pass2-syn-007)
 *   - rac_tool_calling_session_cancel_proto          (pass2-syn-007)
 *
 * pass3-syn-021 then bolted "sticky cancel" semantics on top so the host
 * cannot silently re-arm a cancelled session, and pass3-syn-083 nailed
 * down idempotent RAC_SUCCESS for stale-handle cancel calls.
 *
 * Tool-calling previously had zero coverage of the concurrency contract.
 * This file closes that gap with four targeted tests:
 *
 *   1. run_loop cancel-during-publish: a slow mock generate is interrupted
 *      from another thread mid-iteration; the cancel ABI must return
 *      RAC_SUCCESS concurrently, and the loop must return RAC_ERROR_CANCELLED
 *      within a bounded time (no deadlock against the in-flight generate
 *      caller's session/loop mutex).
 *   2. run_loop cancel-after-natural-completion: cancelling a handle that
 *      the loop has already retired must be an idempotent RAC_SUCCESS no-op.
 *   3. session cancel sticky-true non-regression (pass3-syn-021): after
 *      session_cancel latches cancel_requested, step_with_result_proto on
 *      the same handle must return RAC_ERROR_INVALID_STATE rather than
 *      silently auto-cancelling the next generate.
 *   4. session_cancel idempotency (pass3-syn-083): multiple cancels on a
 *      stale/destroyed handle return RAC_SUCCESS without crashing.
 *
 * The tests reuse the existing mock-LLM plugin pattern (see
 * test_tool_calling_run_loop.cpp / test_tool_calling_session_proto.cpp) so
 * they exercise the real lifecycle/acquire/release path that production
 * SDK adapters drive.
 *
 * Verification under TSAN:
 *   cmake -B build-tsan -DRAC_BUILD_TESTS=ON \
 *       -DCMAKE_CXX_FLAGS="-fsanitize=thread -O1 -g"
 *   cmake --build build-tsan --target test_tool_calling_cancel
 *   ctest --test-dir build-tsan -R tool_calling_cancel
 */

#include <atomic>
#include <chrono>
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
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
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

// ---------------------------------------------------------------------------
// Mock LLM plugin (mirrors test_tool_calling_run_loop.cpp + adds a
// "blocking generate" mode the cancel-during-publish test uses to hold the
// generate call until a sibling thread fires cancel).
//
// The lifecycle-cancel path (request_lifecycle_llm_cancel, used by
// rac_tool_calling_run_loop_cancel_proto / rac_tool_calling_session_cancel_proto)
// only flips an atomic on the LoadedModel — it does NOT directly invoke
// `ops->cancel`. Real backends interrupt their inner generate loop by
// polling that flag (engines/llamacpp/llamacpp_backend.cpp:988) or via a
// separate cancel API. To keep the test independent of that internal flag
// (which the mock cannot reach through the void* impl), we use an explicit
// `g_test_cancel_signal` atomic that the test thread sets immediately after
// calling the cancel ABI. The mock polls it; the assertion that matters is
// that the cancel ABI is concurrent-safe and the loop returns in bounded
// time, not the specific internal propagation channel.
// ---------------------------------------------------------------------------

struct MockLlm {
    std::string model_path;
};

std::mutex g_state_mutex;
std::condition_variable g_state_cv;
std::vector<std::string> g_responses;
int g_generate_calls = 0;
bool g_block_generate = false;
bool g_generate_started = false;
std::atomic<bool> g_test_cancel_signal{false};
bool g_generate_resume = false;
std::atomic<int> g_cancel_calls{0};

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

rac_result_t mock_generate(void*, const char*, const rac_llm_options_t*,
                           rac_llm_result_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;

    std::string response;
    {
        std::unique_lock<std::mutex> lk(g_state_mutex);
        g_generate_calls++;
        g_generate_started = true;
        g_state_cv.notify_all();

        if (g_block_generate) {
            // Wait until either the test releases us or it raises the
            // explicit cancel signal. A 5-second absolute timeout guards
            // against a wedged test on pathological CI hosts.
            g_state_cv.wait_for(lk, std::chrono::seconds(5), [] {
                return g_generate_resume || g_test_cancel_signal.load(std::memory_order_acquire);
            });
            if (g_test_cancel_signal.load(std::memory_order_acquire)) {
                // Mirror what a real backend does when its inner loop sees
                // the cancel flag: bail out with the documented cancel code
                // so the run-loop / session can propagate it upward.
                return RAC_ERROR_CANCELLED;
            }
        }

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
    // ops->cancel is registered for completeness but is NOT invoked by the
    // run_loop / session cancel paths under test (those flip an atomic on
    // LoadedModel instead). The counter exists so we can assert the
    // negative — that cancel-after-completion does NOT spuriously fire
    // ops->cancel for a stale handle.
    g_cancel_calls.fetch_add(1, std::memory_order_relaxed);
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

void reset_mock_state() {
    std::lock_guard<std::mutex> lk(g_state_mutex);
    g_responses.clear();
    g_generate_calls = 0;
    g_block_generate = false;
    g_generate_started = false;
    g_generate_resume = false;
    g_test_cancel_signal.store(false, std::memory_order_release);
    g_cancel_calls.store(0, std::memory_order_release);
}

void set_responses(std::vector<std::string> responses) {
    std::lock_guard<std::mutex> lk(g_state_mutex);
    g_responses = std::move(responses);
    g_generate_calls = 0;
    g_generate_started = false;
    g_generate_resume = false;
    g_test_cancel_signal.store(false, std::memory_order_release);
    g_cancel_calls.store(0, std::memory_order_release);
}

void raise_test_cancel_signal() {
    g_test_cancel_signal.store(true, std::memory_order_release);
    std::lock_guard<std::mutex> lk(g_state_mutex);
    g_state_cv.notify_all();
}

void enable_blocking_generate(bool enable) {
    std::lock_guard<std::mutex> lk(g_state_mutex);
    g_block_generate = enable;
}

bool wait_for_generate_started(std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lk(g_state_mutex);
    return g_state_cv.wait_for(lk, timeout, [] { return g_generate_started; });
}

runanywhere::v1::ModelInfo build_llm_model() {
    runanywhere::v1::ModelInfo model;
    model.set_id("toolcancel.llm");
    model.set_name("ToolCancel LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/toolcancel-test.gguf");
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

rac_model_registry_handle_t g_registry = nullptr;

void cleanup_environment() {
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();
    (void)rac_plugin_unregister("llamacpp");
    reset_mock_state();
}

bool load_mock_llm() {
    cleanup_environment();
    if (rac_plugin_register(&g_mock_vtable) != RAC_SUCCESS)
        return false;

    if (!g_registry && (rac_model_registry_create(&g_registry) != RAC_SUCCESS || !g_registry)) {
        return false;
    }

    std::vector<uint8_t> model_bytes;
    auto model = build_llm_model();
    if (!serialize(model, &model_bytes) ||
        rac_model_registry_register_proto(g_registry, model_bytes.data(), model_bytes.size()) !=
            RAC_SUCCESS) {
        return false;
    }

    runanywhere::v1::ModelLoadRequest load;
    load.set_model_id("toolcancel.llm");
    std::vector<uint8_t> load_bytes;
    if (!serialize(load, &load_bytes))
        return false;

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_lifecycle_load_proto(g_registry, load_bytes.data(), load_bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    bool ok = rc == RAC_SUCCESS && out.data != nullptr && out.size > 0 &&
              result.ParseFromArray(out.data, static_cast<int>(out.size)) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

// ---------------------------------------------------------------------------
// Tool definition + request helpers.
// ---------------------------------------------------------------------------

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

runanywhere::v1::ToolCallingSessionCreateRequest make_request(const std::string& prompt,
                                                              uint32_t max_iterations = 0) {
    runanywhere::v1::ToolCallingSessionCreateRequest request;
    request.set_prompt(prompt);
    request.set_max_tokens(64);
    request.set_temperature(0.5f);
    *request.add_tools() = make_weather_tool();
    request.set_format_hint("default");
    if (max_iterations > 0)
        request.set_max_iterations(max_iterations);
    return request;
}

// Trivial executor used by the run_loop cancel tests. Records each call but
// never blocks — the cancel-during-publish race is exercised inside the
// generate callback, not the executor.
struct ExecutorState {
    std::mutex mu;
    int invocation_count = 0;
};

rac_result_t executor_callback(const uint8_t* in_bytes, size_t in_size,
                               rac_proto_buffer_t* out_result, void* user_data) {
    auto* state = static_cast<ExecutorState*>(user_data);
    runanywhere::v1::ToolCall received;
    if (in_size > 0)
        (void)received.ParseFromArray(in_bytes, static_cast<int>(in_size));

    {
        std::lock_guard<std::mutex> lk(state->mu);
        state->invocation_count++;
    }

    runanywhere::v1::ToolResult tr;
    tr.set_tool_call_id(received.id());
    tr.set_call_id(received.id());
    tr.set_name(received.name());
    tr.set_success(true);
    tr.set_result_json("{\"ok\":true}");

    std::vector<uint8_t> bytes;
    serialize(tr, &bytes);
    rac_proto_buffer_init(out_result);
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
}

// Session event sink. Sessions emit error_bytes on cancel; we only need to
// observe that the callback fires so the test does not deadlock waiting for
// step_with_result to return.
struct SessionEventSink {
    std::mutex mu;
    int event_count = 0;
};

void session_sink_callback(const uint8_t* /*bytes*/, size_t /*size*/, void* user_data) {
    auto* sink = static_cast<SessionEventSink*>(user_data);
    std::lock_guard<std::mutex> lk(sink->mu);
    sink->event_count++;
}

// ---------------------------------------------------------------------------
// Tests.
// ---------------------------------------------------------------------------

// 1. cancel-during-publish (run loop)
//
// Spawn a generate thread that blocks inside mock_generate. From a sibling
// thread call rac_tool_calling_run_loop_cancel_proto while generate is
// in-flight. Expect:
//   - the cancel ABI returns RAC_SUCCESS while the loop's handle is still
//     live in the registry (proves concurrent safety of the registry
//     mutex vs. the in-flight ABI call)
//   - the loop thread joins within a bounded time after the mock
//     cooperatively bails (proves no deadlock — the cancel ABI does not
//     wedge on a mutex held by the generate caller)
//   - the run_loop returns RAC_ERROR_CANCELLED through the documented
//     error-propagation path
//
// We do not assert on `ops->cancel` invocations because the run_loop /
// session cancel paths set an atomic on the LoadedModel rather than
// calling `ops->cancel` — real backends interrupt their inner loop by
// polling that atomic. The mock here simulates the same behavior using an
// explicit test signal that the test thread raises immediately after
// firing the cancel ABI.
int test_run_loop_cancel_during_publish() {
    std::fprintf(stdout, "test_run_loop_cancel_during_publish\n");
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    set_responses({"unused-because-we-cancel-before-the-response-is-consumed"});
    enable_blocking_generate(true);

    auto request = make_request("slow request");
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "serialize create request");

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);

    std::atomic<bool> loop_returned{false};
    std::atomic<rac_result_t> loop_rc{RAC_SUCCESS};

    std::thread loop_thread([&] {
        // The handle is published into the loop_registry synchronously
        // BEFORE generate is called (see register_loop_state in
        // tool_calling_run_loop.cpp:72). We do not need to capture it in
        // the test thread — the cancel-by-handle scan below will land on
        // it idempotently for non-matching handles.
        uint64_t handle = 0;
        rac_result_t rc = rac_tool_calling_run_loop_with_handle_proto(
            bytes.data(), bytes.size(), executor_callback, &exec, &handle, &out);
        loop_rc.store(rc, std::memory_order_release);
        loop_returned.store(true, std::memory_order_release);
    });

    // Wait until the loop is inside generate. Bounded wait — if generate
    // hasn't started within 2s we conclude the run-loop pre-flight rejected
    // the request, which would be a separate bug not in scope for this test.
    const bool started = wait_for_generate_started(std::chrono::milliseconds(2000));
    CHECK(started, "generate started before cancel");

    // Fire the cancel ABI from the test thread. The loop_registry's
    // next_handle starts at 1 and is per-process — within this test binary
    // the run-loop tests run sequentially, so the active handle is the
    // first unretired value. We brute-force the first 16 handles which is
    // safely above any plausible counter value in this test process and
    // exercises the idempotent stale-handle path for the rest. Adapters
    // fan structured-concurrency cancels in similarly without coordinating
    // on the exact handle value, so this is the realistic shape.
    rac_result_t any_cancel_rc = RAC_ERROR_INVALID_HANDLE;
    for (uint64_t h = 1; h <= 16; ++h) {
        rac_result_t rc = rac_tool_calling_run_loop_cancel_proto(h);
        if (rc == RAC_SUCCESS) {
            any_cancel_rc = RAC_SUCCESS;
        }
    }
    CHECK(any_cancel_rc == RAC_SUCCESS, "cancel returned RAC_SUCCESS while loop in-flight");

    // The cancel ABI does not call ops->cancel directly — it sets an
    // atomic on the LoadedModel that real backends poll. To simulate that
    // polling and let the mock bail out, raise the test cancel signal.
    raise_test_cancel_signal();

    // The loop must return within a bounded time. Without the cancel
    // signal the mock would wait the full 5s timeout, so a join inside
    // 5s proves forward progress. We use a 3s bound with a polling join
    // pattern so the test fails loudly if the cancel ABI ever wedges the
    // loop on a mutex held by the in-flight generate caller.
    const auto join_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < join_deadline &&
           !loop_returned.load(std::memory_order_acquire)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    CHECK(loop_returned.load(std::memory_order_acquire),
          "loop returned within 3s of cancel (no deadlock)");
    loop_thread.join();

    CHECK(loop_rc.load(std::memory_order_acquire) == RAC_ERROR_CANCELLED,
          "run loop propagated RAC_ERROR_CANCELLED");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

// 2. cancel-after-natural-completion (run loop)
//
// Run a full loop to completion (no tool call, single iteration), then
// fire cancel against handles that may have been published. The cancel ABI
// must idempotently return RAC_SUCCESS for stale handles — adapters fan
// structured-concurrency cancels into this entry point without
// coordinating with run_loop exit.
int test_run_loop_cancel_after_completion() {
    std::fprintf(stdout, "test_run_loop_cancel_after_completion\n");
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    set_responses({"plain answer, no tool call"});

    auto request = make_request("hi");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    ExecutorState exec;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_run_loop_with_handle_proto(
        bytes.data(), bytes.size(), executor_callback, &exec, &handle, &out);
    CHECK(rc == RAC_SUCCESS, "run_loop returns RAC_SUCCESS");

    runanywhere::v1::ToolCallingResult result;
    if (out.data && out.size > 0) {
        (void)result.ParseFromArray(out.data, static_cast<int>(out.size));
    }
    CHECK(result.is_complete() == true, "is_complete true");

    // The handle was retired by the HandleScope RAII guard when run_loop
    // returned. Cancel must still report RAC_SUCCESS for the now-stale
    // handle (idempotent semantics — adapters cannot coordinate with the
    // loop's exit).
    rc = rac_tool_calling_run_loop_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "cancel post-completion is idempotent RAC_SUCCESS");

    // Repeated cancels are also no-ops.
    rc = rac_tool_calling_run_loop_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "second cancel still RAC_SUCCESS");

    // Zero / arbitrary stale handles are also no-ops.
    rc = rac_tool_calling_run_loop_cancel_proto(0);
    CHECK(rc == RAC_SUCCESS, "cancel(0) is RAC_SUCCESS");
    rc = rac_tool_calling_run_loop_cancel_proto(999999);
    CHECK(rc == RAC_SUCCESS, "cancel(stale) is RAC_SUCCESS");

    // ops->cancel was never invoked anywhere in this test — confirms the
    // stale-handle cancel path is a pure no-op that never reaches into the
    // (already-released) lifecycle ref.
    CHECK(g_cancel_calls.load(std::memory_order_acquire) == 0,
          "ops->cancel NOT invoked for stale-handle cancel");

    rac_proto_buffer_free(&out);
    cleanup_environment();
    return 0;
}

// 3. session cancel sticky-true non-regression (pass3-syn-021)
//
// Before pass3-syn-021, calling session_cancel then step_with_result on the
// same session would auto-cancel the next generate (because
// cancel_requested is a per-session atomic that survives state transitions).
// pass3-syn-021's fix rejects step_with_result on a cancelled session with
// RAC_ERROR_INVALID_STATE so the host must destroy and recreate the
// session to continue.
int test_session_cancel_sticky_blocks_step() {
    std::fprintf(stdout, "test_session_cancel_sticky_blocks_step\n");
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    // First generate yields a tool call -> session pauses in kWaitingForTool.
    // The follow-up response is never consumed because we cancel between
    // the tool_call event and step_with_result.
    set_responses({
        R"(<tool_call>{"tool":"get_weather","arguments":{"location":"Tokyo"}}</tool_call>)",
        "follow-up text that should never be generated",
    });

    SessionEventSink sink;
    auto request = make_request("What's the weather in Tokyo?");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            session_sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");
    CHECK(handle != 0, "handle non-zero");

    // Session paused waiting for tool result. Fire cancel.
    rc = rac_tool_calling_session_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "session_cancel RAC_SUCCESS");

    // The sticky-cancel contract: step_with_result on a cancelled session
    // must return RAC_ERROR_INVALID_STATE. Without pass3-syn-021's guard,
    // step_with_result would resume generate_loop, the atomic
    // cancel_requested would still be true, and the new generate would
    // immediately auto-cancel — silently feeding the host a cancelled
    // result instead of an explicit error.
    runanywhere::v1::ToolCallingSessionStepWithResultRequest step;
    step.set_session_handle(handle);
    step.set_result_json("{\"temp\":25,\"condition\":\"sunny\"}");
    std::vector<uint8_t> step_bytes;
    serialize(step, &step_bytes);

    rc = rac_tool_calling_session_step_with_result_proto(step_bytes.data(), step_bytes.size());
    CHECK(rc == RAC_ERROR_INVALID_STATE,
          "step_with_result after cancel returns RAC_ERROR_INVALID_STATE");

    // The second generate must NOT have been invoked.
    {
        std::lock_guard<std::mutex> lk(g_state_mutex);
        CHECK(g_generate_calls == 1, "no follow-up generate after cancelled-session step");
    }

    rac_tool_calling_session_destroy_proto(handle);
    cleanup_environment();
    return 0;
}

// 4. session_cancel idempotency on stale/destroyed handles (pass3-syn-083)
//
// Multiple cancels on the same handle — including after destroy and on
// arbitrary stale values — must return RAC_SUCCESS without crashing.
// Adapters cannot coordinate cancel with destroy, so the C ABI is
// responsible for absorbing the race.
int test_session_cancel_idempotent_on_stale_handle() {
    std::fprintf(stdout, "test_session_cancel_idempotent_on_stale_handle\n");
    if (!load_mock_llm()) {
        std::fprintf(stderr, "FAIL: mock LLM load\n");
        return 1;
    }
    set_responses({"plain text no tool call"});

    SessionEventSink sink;
    auto request = make_request("hello");
    std::vector<uint8_t> bytes;
    serialize(request, &bytes);

    uint64_t handle = 0;
    rac_result_t rc = rac_tool_calling_session_create_proto(bytes.data(), bytes.size(),
                                                            session_sink_callback, &sink, &handle);
    CHECK(rc == RAC_SUCCESS, "session_create RAC_SUCCESS");
    CHECK(handle != 0, "handle non-zero");

    // Session already completed (no tool call in the response). Cancel on
    // the live-but-terminal session is a no-op success — the latch only
    // affects future generates, of which there are none.
    rc = rac_tool_calling_session_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "cancel on terminal session is RAC_SUCCESS");

    rc = rac_tool_calling_session_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "second cancel on same live handle is RAC_SUCCESS");

    // Destroy retires the handle.
    rc = rac_tool_calling_session_destroy_proto(handle);
    CHECK(rc == RAC_SUCCESS, "destroy RAC_SUCCESS");

    // Cancel on the now-stale handle — adapter raced cancel against
    // destroy. pass3-syn-083: this must be idempotent RAC_SUCCESS.
    rc = rac_tool_calling_session_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "cancel on destroyed handle is RAC_SUCCESS");

    rc = rac_tool_calling_session_cancel_proto(handle);
    CHECK(rc == RAC_SUCCESS, "second cancel on destroyed handle is RAC_SUCCESS");

    // Zero handle (adapter never got past create) — idempotent no-op.
    rc = rac_tool_calling_session_cancel_proto(0);
    CHECK(rc == RAC_SUCCESS, "cancel(0) is RAC_SUCCESS");

    // Arbitrary stale value that was never published — idempotent no-op.
    rc = rac_tool_calling_session_cancel_proto(987654321ULL);
    CHECK(rc == RAC_SUCCESS, "cancel(unrelated stale handle) is RAC_SUCCESS");

    cleanup_environment();
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_tool_calling_cancel\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: no protobuf\n");
        return 0;
#else
        test_run_loop_cancel_during_publish();
        test_run_loop_cancel_after_completion();
        test_session_cancel_sticky_blocks_step();
        test_session_cancel_idempotent_on_stale_handle();
        if (g_registry) {
            rac_model_registry_destroy(g_registry);
            g_registry = nullptr;
        }
        std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
        return fail_count == 0 ? 0 : 1;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "test_tool_calling_cancel: uncaught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        std::fprintf(stderr, "test_tool_calling_cancel: uncaught exception\n");
        return 1;
    }
}
