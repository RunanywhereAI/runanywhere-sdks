/** Focused concurrency tests for same-session QHexRT STT operations. */

#include "qhexrt_session.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

extern "C" const rac_stt_service_ops_t g_qhexrt_stt_ops;

struct qhx_model {};
struct qhx_session {};

namespace {

using namespace std::chrono_literals;

struct NativeProbe {
    std::atomic<int> active_calls{0};
    std::atomic<int> max_active_calls{0};
    std::atomic<int> generate_calls{0};
    std::atomic<int> generate_active{0};
    std::atomic<int> reset_during_generate{0};
    std::mutex gate_mutex;
    std::condition_variable gate_cv;
    bool block_generate = false;
    bool release_generate = false;

    void reset() {
        active_calls.store(0, std::memory_order_relaxed);
        max_active_calls.store(0, std::memory_order_relaxed);
        generate_calls.store(0, std::memory_order_relaxed);
        generate_active.store(0, std::memory_order_relaxed);
        reset_during_generate.store(0, std::memory_order_relaxed);
        std::lock_guard<std::mutex> lock(gate_mutex);
        block_generate = false;
        release_generate = false;
    }

    void enter_native_call() {
        const int active = active_calls.fetch_add(1, std::memory_order_acq_rel) + 1;
        int observed = max_active_calls.load(std::memory_order_relaxed);
        while (active > observed && !max_active_calls.compare_exchange_weak(
                                        observed, active, std::memory_order_relaxed)) {}
    }

    void leave_native_call() { active_calls.fetch_sub(1, std::memory_order_acq_rel); }

    bool wait_for_generate_calls(int expected, std::chrono::milliseconds timeout) {
        std::unique_lock<std::mutex> lock(gate_mutex);
        return gate_cv.wait_for(lock, timeout, [&] {
            return generate_calls.load(std::memory_order_acquire) >= expected;
        });
    }

    void release_all_generations() {
        {
            std::lock_guard<std::mutex> lock(gate_mutex);
            release_generate = true;
        }
        gate_cv.notify_all();
    }
};

NativeProbe g_probe;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

void ignore_stream_event(const char*, rac_bool_t, void*) {}

bool test_batch_and_stream_calls_are_serialized() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.gate_mutex);
        g_probe.block_generate = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    constexpr int kThreadCount = 8;
    std::atomic<int> ready{0};
    std::atomic<bool> start{false};
    std::atomic<int> failures{0};
    std::vector<std::thread> workers;
    workers.reserve(kThreadCount);

    const int16_t pcm[] = {0, 200, -200, 400, -400, 0};
    const rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    for (int i = 0; i < kThreadCount; ++i) {
        workers.emplace_back([&, i] {
            ready.fetch_add(1, std::memory_order_release);
            while (!start.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }
            rac_result_t rc = RAC_SUCCESS;
            if ((i % 2) == 0) {
                rac_stt_result_t result{};
                rc = g_qhexrt_stt_ops.transcribe(&session, pcm, sizeof(pcm), &options, &result);
                rac_stt_result_free(&result);
            } else {
                rc = g_qhexrt_stt_ops.transcribe_stream(&session, pcm, sizeof(pcm), &options,
                                                        ignore_stream_event, nullptr);
            }
            if (rc != RAC_SUCCESS) {
                failures.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }
    while (ready.load(std::memory_order_acquire) != kThreadCount) {
        std::this_thread::yield();
    }
    start.store(true, std::memory_order_release);

    const bool first_generation_entered = g_probe.wait_for_generate_calls(1, 2s);
    // The first native generation is held open. A second entry would prove
    // that the exported STT operations failed to serialize the shared handle.
    const bool second_generation_entered =
        first_generation_entered && g_probe.wait_for_generate_calls(2, 100ms);
    g_probe.release_all_generations();
    for (auto& worker : workers) {
        worker.join();
    }

    EXPECT_TRUE(first_generation_entered);
    EXPECT_TRUE(!second_generation_entered);
    EXPECT_TRUE(failures.load(std::memory_order_relaxed) == 0);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_relaxed) == kThreadCount);
    EXPECT_TRUE(g_probe.max_active_calls.load(std::memory_order_relaxed) == 1);
    EXPECT_TRUE(g_probe.reset_during_generate.load(std::memory_order_relaxed) == 0);
    return true;
}

bool test_cleanup_waits_for_transcription() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.gate_mutex);
        g_probe.block_generate = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    const int16_t pcm[] = {0, 100, -100, 0};
    const rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    std::atomic<rac_result_t> transcribe_rc{RAC_ERROR_UNKNOWN};
    std::atomic<rac_result_t> cleanup_rc{RAC_ERROR_UNKNOWN};
    std::atomic<bool> cleanup_started{false};
    std::atomic<bool> cleanup_finished{false};

    std::thread transcriber([&] {
        rac_stt_result_t result{};
        transcribe_rc.store(
            g_qhexrt_stt_ops.transcribe(&session, pcm, sizeof(pcm), &options, &result),
            std::memory_order_release);
        rac_stt_result_free(&result);
    });
    const bool first_generation_entered = g_probe.wait_for_generate_calls(1, 2s);
    if (!first_generation_entered) {
        g_probe.release_all_generations();
        transcriber.join();
        EXPECT_TRUE(first_generation_entered);
    }

    std::thread cleaner([&] {
        cleanup_started.store(true, std::memory_order_release);
        cleanup_rc.store(g_qhexrt_stt_ops.cleanup(&session), std::memory_order_release);
        cleanup_finished.store(true, std::memory_order_release);
        g_probe.gate_cv.notify_all();
    });
    while (!cleanup_started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }

    // A cleanup without the session operation guard immediately resets the
    // live native session. With the guard it remains pending until generation
    // is released.
    {
        std::unique_lock<std::mutex> lock(g_probe.gate_mutex);
        (void)g_probe.gate_cv.wait_for(lock, 100ms, [&] {
            return cleanup_finished.load(std::memory_order_acquire) ||
                   g_probe.reset_during_generate.load(std::memory_order_acquire) != 0;
        });
    }
    const bool finished_while_generation_blocked = cleanup_finished.load(std::memory_order_acquire);
    const int reset_overlap = g_probe.reset_during_generate.load(std::memory_order_acquire);

    g_probe.release_all_generations();
    transcriber.join();
    cleaner.join();

    EXPECT_TRUE(!finished_while_generation_blocked);
    EXPECT_TRUE(reset_overlap == 0);
    EXPECT_TRUE(transcribe_rc.load(std::memory_order_acquire) == RAC_SUCCESS);
    EXPECT_TRUE(cleanup_rc.load(std::memory_order_acquire) == RAC_SUCCESS);
    EXPECT_TRUE(g_probe.max_active_calls.load(std::memory_order_relaxed) == 1);
    return true;
}

}  // namespace

namespace qhexrt_engine {

Session* session_open(const char*) {
    return nullptr;
}

void session_close(Session*) {}

}  // namespace qhexrt_engine

extern "C" {

void qhx_session_reset(qhx_session*) {
    g_probe.enter_native_call();
    if (g_probe.generate_active.load(std::memory_order_acquire) != 0) {
        g_probe.reset_during_generate.fetch_add(1, std::memory_order_relaxed);
        g_probe.gate_cv.notify_all();
    }
    g_probe.leave_native_call();
}

void qhx_gen_cfg_default(qhx_gen_cfg* cfg) {
    if (cfg != nullptr) {
        std::memset(cfg, 0, sizeof(*cfg));
    }
}

qhx_status qhx_generate(qhx_session*, const qhx_inputs*, const qhx_gen_cfg*, qhx_token_cb callback,
                        void* user, qhx_output* output) {
    g_probe.enter_native_call();
    g_probe.generate_active.fetch_add(1, std::memory_order_acq_rel);
    g_probe.generate_calls.fetch_add(1, std::memory_order_release);
    {
        std::unique_lock<std::mutex> lock(g_probe.gate_mutex);
        g_probe.gate_cv.notify_all();
        if (g_probe.block_generate) {
            g_probe.gate_cv.wait(lock, [] { return g_probe.release_generate; });
        }
    }
    static const char kTranscript[] = "serialized";
    if (callback != nullptr) {
        (void)callback(user, kTranscript, static_cast<int>(sizeof(kTranscript) - 1), 1, 0);
        (void)callback(user, nullptr, 0, -1, 1);
    }
    if (output != nullptr) {
        output->status = 0;
        output->text = kTranscript;
        output->n_generated = 1;
        output->n_prompt = 1;
        output->prefill_ms = 1.0;
        output->decode_ms = 1.0;
    }
    g_probe.generate_active.fetch_sub(1, std::memory_order_acq_rel);
    g_probe.leave_native_call();
    return 0;
}

const char* qhx_status_str(qhx_status) {
    return "fake";
}

}  // extern "C"

int main() {
    if (!test_batch_and_stream_calls_are_serialized()) {
        return 1;
    }
    if (!test_cleanup_waits_for_transcription()) {
        return 1;
    }
    std::puts("QHexRT session serialization tests passed");
    return 0;
}
