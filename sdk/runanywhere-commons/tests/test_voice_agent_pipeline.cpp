// SPDX-License-Identifier: Apache-2.0
//
// test_voice_agent_pipeline.cpp — GAP 05 Phase 2 unit tests for the
// VoiceAgent's GraphScheduler-driven pipeline (voice_agent_pipeline.cpp).
//
// These tests do NOT require backends or model files — they exercise the
// pipeline class with null component handles and verify:
//   * the C ABI surface still rejects bad input,
//   * cancel() before run_once() is a safe no-op,
//   * cancel() is idempotent,
//   * cancel() while no pipeline is active does not crash,
//   * an in-flight pipeline tears down deterministically when cancelled.
//
// Backend-dependent end-to-end coverage lives in test_voice_agent.cpp.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <thread>
#include <vector>

#include "rac/features/voice_agent/rac_voice_agent.h"

#include "../src/features/voice_agent/voice_agent_internal.h"
#include "../src/features/voice_agent/voice_agent_pipeline.hpp"

static int g_failed = 0;
static int g_passed = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__,      \
                         #cond);                                               \
            g_failed++;                                                        \
            return;                                                            \
        }                                                                      \
    } while (0)

#define TEST(name)                                                             \
    static void test_##name();                                                 \
    static void run_test_##name() {                                            \
        std::fprintf(stderr, "[RUN ] %s\n", #name);                            \
        const int before = g_failed;                                           \
        test_##name();                                                         \
        if (g_failed == before) {                                              \
            std::fprintf(stderr, "[  OK] %s\n", #name);                        \
            g_passed++;                                                        \
        }                                                                      \
    }                                                                          \
    static void test_##name()

// ---------------------------------------------------------------------------
// Helpers — a stub agent with null component handles so we can exercise the
// pipeline error path without spinning up STT/LLM/TTS backends.
// ---------------------------------------------------------------------------

namespace {

struct EventCounter {
    std::atomic<int> total{0};
    std::atomic<int> errors{0};
    std::atomic<int> processed{0};
};

void counting_callback(const rac_voice_agent_event_t* ev, void* ud) {
    auto* c = static_cast<EventCounter*>(ud);
    c->total.fetch_add(1, std::memory_order_relaxed);
    if (ev->type == RAC_VOICE_AGENT_EVENT_ERROR) {
        c->errors.fetch_add(1, std::memory_order_relaxed);
    }
    if (ev->type == RAC_VOICE_AGENT_EVENT_PROCESSED) {
        c->processed.fetch_add(1, std::memory_order_relaxed);
    }
}

}  // namespace

// ---------------------------------------------------------------------------
// Constructor + null-input rejection — pipeline rejects empty buffers and
// missing handles before spawning any worker threads.
// ---------------------------------------------------------------------------

TEST(rejects_invalid_input) {
    rac_voice_agent agent;  // null component handles, not configured.
    rac::voice_agent::VoiceAgentPipeline pipeline(&agent, nullptr, nullptr);

    CHECK(pipeline.run_once(nullptr, 0)        == RAC_ERROR_INVALID_ARGUMENT);
    CHECK(pipeline.run_once(nullptr, 16)       == RAC_ERROR_INVALID_ARGUMENT);
    const std::vector<int16_t> buf(8000, 0);
    CHECK(pipeline.run_once(buf.data(), 0)     == RAC_ERROR_INVALID_ARGUMENT);
}

TEST(rejects_null_agent) {
    rac::voice_agent::VoiceAgentPipeline pipeline(nullptr, nullptr, nullptr);
    const std::vector<int16_t> buf(8000, 0);
    CHECK(pipeline.run_once(buf.data(), buf.size() * sizeof(int16_t))
          == RAC_ERROR_INVALID_HANDLE);
}

// ---------------------------------------------------------------------------
// cancel() is safe before any run starts and is idempotent. This guarantees
// the destroy/cleanup → cancel hook in voice_agent.cpp can fire at any time
// without observing a torn-down scheduler.
// ---------------------------------------------------------------------------

TEST(cancel_is_idempotent_when_idle) {
    rac_voice_agent agent;
    rac::voice_agent::VoiceAgentPipeline pipeline(&agent, nullptr, nullptr);

    pipeline.cancel();
    pipeline.cancel();
    pipeline.cancel();
    // No assertion — surviving without crash / hang is the contract.
}

// ---------------------------------------------------------------------------
// Error propagation — with null component handles the STT primitive returns
// RAC_ERROR_INVALID_HANDLE; the dispatcher records the first failure and
// surfaces it via the run_once() return code. The graph drains cleanly
// without hanging — this exercises the GraphScheduler::wait() path.
// ---------------------------------------------------------------------------

TEST(error_propagates_through_pipeline) {
    rac_voice_agent agent;  // all handles null.
    EventCounter counts;
    rac::voice_agent::VoiceAgentPipeline pipeline(&agent, counting_callback,
                                                   &counts);

    const std::vector<int16_t> buf(160, 0);  // 10ms of silence at 16kHz.
    rac_result_t rc = pipeline.run_once(buf.data(), buf.size() * sizeof(int16_t));

    // First failure is the STT call's invalid-handle return; downstream
    // stages observe input close-on-cancel and drain.
    CHECK(rc != RAC_SUCCESS);
    CHECK(counts.errors.load() >= 1);
    // VAD ran (and emitted its event) before STT failed.
    CHECK(counts.total.load() >= 1);
}

// ---------------------------------------------------------------------------
// External cancel mid-flight — kick off run_once on a worker thread and
// then call cancel() from the main thread. Verify the worker returns
// promptly (within 2s budget — well above the ~50ms cancel granularity).
// With null handles the run is fast anyway, so this primarily proves the
// cancel() path does not deadlock when the scheduler is alive.
// ---------------------------------------------------------------------------

TEST(external_cancel_unblocks_run) {
    rac_voice_agent agent;
    EventCounter counts;
    rac::voice_agent::VoiceAgentPipeline pipeline(&agent, counting_callback,
                                                   &counts);

    std::atomic<bool> done{false};
    std::thread worker([&] {
        const std::vector<int16_t> buf(160, 0);
        (void)pipeline.run_once(buf.data(), buf.size() * sizeof(int16_t));
        done.store(true, std::memory_order_release);
    });

    // Give the worker a moment to spin up the graph, then cancel.
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    pipeline.cancel();

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(2);
    while (!done.load(std::memory_order_acquire)) {
        if (std::chrono::steady_clock::now() > deadline) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    CHECK(done.load(std::memory_order_acquire));

    worker.join();
    pipeline.cancel();
}

int main() {
    run_test_rejects_invalid_input();
    run_test_rejects_null_agent();
    run_test_cancel_is_idempotent_when_idle();
    run_test_error_propagates_through_pipeline();
    run_test_external_cancel_unblocks_run();

    std::fprintf(stderr, "\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
