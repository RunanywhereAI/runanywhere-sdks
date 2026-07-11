/** Focused host-only cancellation tests for the QHexRT LLM adapter. */

#include "qhexrt_session.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

extern "C" const rac_llm_service_ops_t g_qhexrt_llm_ops;

struct qhx_model {};
struct qhx_session {
    std::atomic<uint64_t> cancellation_epoch{0};
    std::atomic<bool> active{false};
};

namespace {

using namespace std::chrono_literals;

struct Probe {
    std::mutex mutex;
    std::condition_variable cv;
    bool block_reset{false};
    bool reset_entered{false};
    bool release_reset{false};
    bool block_before_publication{false};
    bool before_publication_entered{false};
    bool release_publication{false};
    bool block_generate{false};
    bool generate_entered{false};
    bool release_generate{false};
    bool emit_fragment{false};
    std::atomic<int> generate_calls{0};
    std::atomic<int> native_work_calls{0};
    std::atomic<int> cancel_calls{0};
    std::atomic<int> should_cancel_calls{0};

    void reset() {
        std::lock_guard<std::mutex> lock(mutex);
        block_reset = false;
        reset_entered = false;
        release_reset = false;
        block_before_publication = false;
        before_publication_entered = false;
        release_publication = false;
        block_generate = false;
        generate_entered = false;
        release_generate = false;
        emit_fragment = false;
        generate_calls.store(0, std::memory_order_release);
        native_work_calls.store(0, std::memory_order_release);
        cancel_calls.store(0, std::memory_order_release);
        should_cancel_calls.store(0, std::memory_order_release);
    }
} g_probe;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

rac_bool_t keep_streaming(const char*, void*) { return RAC_TRUE; }
rac_bool_t cancel_on_first_fragment(const char*, void*) { return RAC_FALSE; }

rac_result_t generate_stream(qhexrt_engine::Session* session,
                             rac_llm_stream_callback_fn callback = keep_streaming) {
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    return g_qhexrt_llm_ops.generate_stream(session, "prompt", &options, callback, nullptr);
}

bool test_cancel_during_reset_is_not_lost() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_reset = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    std::atomic<rac_result_t> result{RAC_SUCCESS};
    std::thread worker([&] { result.store(generate_stream(&session), std::memory_order_release); });

    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        EXPECT_TRUE(g_probe.cv.wait_for(lock, 2s, [] { return g_probe.reset_entered; }));
    }
    EXPECT_TRUE(g_qhexrt_llm_ops.cancel(&session) == RAC_SUCCESS);
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.release_reset = true;
    }
    g_probe.cv.notify_all();
    worker.join();

    EXPECT_TRUE(result.load(std::memory_order_acquire) == RAC_ERROR_CANCELLED);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_acquire) == 0);
    EXPECT_TRUE(g_probe.cancel_calls.load(std::memory_order_acquire) == 0);
    return true;
}

bool test_cancel_interrupts_prefill_without_waiting_for_a_token_callback() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_generate = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    std::atomic<rac_result_t> result{RAC_SUCCESS};
    std::thread worker([&] { result.store(generate_stream(&session), std::memory_order_release); });

    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        EXPECT_TRUE(g_probe.cv.wait_for(lock, 2s, [] { return g_probe.generate_entered; }));
    }
    EXPECT_TRUE(g_qhexrt_llm_ops.cancel(&session) == RAC_SUCCESS);
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.release_generate = true;
    }
    g_probe.cv.notify_all();
    worker.join();

    EXPECT_TRUE(result.load(std::memory_order_acquire) == RAC_ERROR_CANCELLED);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_acquire) == 1);
    EXPECT_TRUE(g_probe.cancel_calls.load(std::memory_order_acquire) == 0);

    // The idle native epoch left by cancellation is snapshotted by the next
    // generation and therefore cannot poison an independent request.
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_generate = false;
        g_probe.generate_entered = false;
    }
    EXPECT_TRUE(generate_stream(&session) == RAC_SUCCESS);
    return true;
}

bool test_cancel_in_generate_publication_gap_is_transferred_to_native_request() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_before_publication = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    std::atomic<rac_result_t> result{RAC_SUCCESS};
    std::thread worker([&] { result.store(generate_stream(&session), std::memory_order_release); });

    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        EXPECT_TRUE(g_probe.cv.wait_for(lock, 2s, [] { return g_probe.before_publication_entered; }));
    }
    EXPECT_TRUE(!fake_session.active.load(std::memory_order_acquire));
    EXPECT_TRUE(g_qhexrt_llm_ops.cancel(&session) == RAC_SUCCESS);
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.release_publication = true;
    }
    g_probe.cv.notify_all();
    worker.join();

    EXPECT_TRUE(result.load(std::memory_order_acquire) == RAC_ERROR_CANCELLED);
    EXPECT_TRUE(g_probe.cancel_calls.load(std::memory_order_acquire) == 0);
    EXPECT_TRUE(g_probe.should_cancel_calls.load(std::memory_order_acquire) >= 1);
    EXPECT_TRUE(g_probe.native_work_calls.load(std::memory_order_acquire) == 0);

    // The binding latch is keyed to the finished SDK request id. The next
    // independent request publishes a new id and must run normally.
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_before_publication = false;
        g_probe.before_publication_entered = false;
        g_probe.release_publication = false;
    }
    EXPECT_TRUE(generate_stream(&session) == RAC_SUCCESS);
    EXPECT_TRUE(g_probe.native_work_calls.load(std::memory_order_acquire) == 1);
    return true;
}

bool test_clean_qhexrt_return_after_callback_stop_maps_to_cancelled() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.emit_fragment = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;

    EXPECT_TRUE(generate_stream(&session, cancel_on_first_fragment) == RAC_ERROR_CANCELLED);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_acquire) == 1);
    return true;
}

}  // namespace

namespace qhexrt_engine {
Session* session_open(const char*) { return nullptr; }
void session_close(Session*) {}
}  // namespace qhexrt_engine

extern "C" {

void qhx_session_reset(qhx_session*) {
    std::unique_lock<std::mutex> lock(g_probe.mutex);
    g_probe.reset_entered = true;
    g_probe.cv.notify_all();
    if (g_probe.block_reset) {
        g_probe.cv.wait(lock, [] { return g_probe.release_reset; });
    }
}

void qhx_session_cancel(qhx_session* session) {
    if (session != nullptr && session->active.load(std::memory_order_acquire)) {
        session->cancellation_epoch.fetch_add(1, std::memory_order_acq_rel);
    }
    g_probe.cancel_calls.fetch_add(1, std::memory_order_acq_rel);
    g_probe.cv.notify_all();
}

void qhx_gen_cfg_default(qhx_gen_cfg* cfg) {
    if (cfg != nullptr) std::memset(cfg, 0, sizeof(*cfg));
}

void qhx_generate_options_default(qhx_generate_options* options) {
    if (options == nullptr) return;
    std::memset(options, 0, sizeof(*options));
    options->struct_size = sizeof(*options);
}

qhx_status qhx_generate_ex(qhx_session* session, const qhx_inputs*, const qhx_gen_cfg*,
                           const qhx_generate_options* options,
                           qhx_token_cb callback, void* user, qhx_output* output) {
    g_probe.generate_calls.fetch_add(1, std::memory_order_acq_rel);

    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        g_probe.before_publication_entered = true;
        g_probe.cv.notify_all();
        if (g_probe.block_before_publication) {
            g_probe.cv.wait(lock, [] { return g_probe.release_publication; });
        }
    }

    session->active.store(true, std::memory_order_release);
    const uint64_t request_epoch = session->cancellation_epoch.load(std::memory_order_acquire);
    struct ActiveRequest {
        qhx_session* session;
        ~ActiveRequest() { session->active.store(false, std::memory_order_release); }
    } active_request{session};

    auto cancelled_by_probe = [&]() {
        const size_t probe_end = offsetof(qhx_generate_options, should_cancel_user) +
                                 sizeof(options->should_cancel_user);
        if (options == nullptr || options->struct_size < probe_end ||
            options->should_cancel == nullptr) {
            return false;
        }
        g_probe.should_cancel_calls.fetch_add(1, std::memory_order_acq_rel);
        return options->should_cancel(options->should_cancel_user) != 0;
    };
    if (cancelled_by_probe()) return 1;

    g_probe.native_work_calls.fetch_add(1, std::memory_order_acq_rel);

    bool block_generate = false;
    bool emit_fragment = false;
    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        g_probe.generate_entered = true;
        block_generate = g_probe.block_generate;
        emit_fragment = g_probe.emit_fragment;
        g_probe.cv.notify_all();
        if (block_generate) {
            g_probe.cv.wait(lock, [&] {
                return g_probe.release_generate ||
                       session->cancellation_epoch.load(std::memory_order_acquire) != request_epoch;
            });
            if (cancelled_by_probe()) return 1;
            return 1;  // fake QHexRT Aborted
        }
    }

    static const char kText[] = "ok";
    if (emit_fragment && callback != nullptr) {
        // Deliberately return success even if the callback stops, locking the
        // adapter's independent ctx.cancelled status mapping.
        (void)callback(user, kText, 2, 1, 0);
    }
    if (output != nullptr) {
        output->status = 0;
        output->text = kText;
        output->n_generated = 1;
        output->n_prompt = 1;
    }
    return 0;
}

qhx_status qhx_generate(qhx_session* session, const qhx_inputs* inputs,
                        const qhx_gen_cfg* cfg,
                           qhx_token_cb callback, void* user, qhx_output* output) {
    return qhx_generate_ex(session, inputs, cfg, nullptr, callback, user, output);
}

const char* qhx_status_str(qhx_status) { return "fake"; }

}  // extern "C"

int main() {
    if (!test_cancel_during_reset_is_not_lost()) return 1;
    if (!test_cancel_interrupts_prefill_without_waiting_for_a_token_callback()) return 1;
    if (!test_cancel_in_generate_publication_gap_is_transferred_to_native_request()) return 1;
    if (!test_clean_qhexrt_return_after_callback_stop_maps_to_cancelled()) return 1;
    std::puts("QHexRT LLM cancellation tests passed");
    return 0;
}
