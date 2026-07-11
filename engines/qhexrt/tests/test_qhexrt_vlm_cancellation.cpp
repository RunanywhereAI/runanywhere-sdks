/** Focused request-lifetime cancellation tests for the QHexRT VLM adapter. */

#include "qhexrt_session.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_service.h"

extern "C" const rac_vlm_service_ops_t g_qhexrt_vlm_ops;

struct qhx_model {};
struct qhx_session {};

namespace {

using namespace std::chrono_literals;

struct Probe {
    std::mutex mutex;
    std::condition_variable cv;
    bool block_reset{false};
    bool reset_entered{false};
    bool release_reset{false};
    std::atomic<int> generate_calls{0};

    void reset() {
        std::lock_guard<std::mutex> lock(mutex);
        block_reset = false;
        reset_entered = false;
        release_reset = false;
        generate_calls.store(0, std::memory_order_release);
    }
} g_probe;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

rac_result_t process(qhexrt_engine::Session* session) {
    rac_vlm_image_t image{};
    image.file_path = const_cast<char*>("fixture.jpg");
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    rac_vlm_result_t result{};
    const rac_result_t rc =
        g_qhexrt_vlm_ops.process(session, &image, "describe", &options, &result);
    rac_vlm_result_free(&result);
    return rc;
}

bool test_cancel_during_reset_targets_announced_request_only() {
    g_probe.reset();
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_reset = true;
    }

    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;
    std::atomic<rac_result_t> first_rc{RAC_SUCCESS};
    std::thread first([&] { first_rc.store(process(&session), std::memory_order_release); });

    {
        std::unique_lock<std::mutex> lock(g_probe.mutex);
        EXPECT_TRUE(g_probe.cv.wait_for(lock, 2s, [] { return g_probe.reset_entered; }));
    }
    EXPECT_TRUE(g_qhexrt_vlm_ops.cancel(&session) == RAC_SUCCESS);
    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.release_reset = true;
    }
    g_probe.cv.notify_all();
    first.join();

    EXPECT_TRUE(first_rc.load(std::memory_order_acquire) == RAC_ERROR_CANCELLED);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_acquire) == 0);

    {
        std::lock_guard<std::mutex> lock(g_probe.mutex);
        g_probe.block_reset = false;
        g_probe.reset_entered = false;
        g_probe.release_reset = false;
    }
    EXPECT_TRUE(process(&session) == RAC_SUCCESS);
    EXPECT_TRUE(g_probe.generate_calls.load(std::memory_order_acquire) == 1);
    return true;
}

bool test_idle_cancel_does_not_poison_next_request() {
    g_probe.reset();
    qhexrt_engine::Session session;
    qhx_session fake_session;
    session.sess = &fake_session;

    EXPECT_TRUE(g_qhexrt_vlm_ops.cancel(&session) == RAC_SUCCESS);
    EXPECT_TRUE(process(&session) == RAC_SUCCESS);
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

void qhx_gen_cfg_default(qhx_gen_cfg* cfg) {
    if (cfg != nullptr) std::memset(cfg, 0, sizeof(*cfg));
}

qhx_status qhx_generate(qhx_session*, const qhx_inputs*, const qhx_gen_cfg*, qhx_token_cb callback,
                        void* user, qhx_output* output) {
    g_probe.generate_calls.fetch_add(1, std::memory_order_acq_rel);
    static const char kText[] = "grounded result";
    if (callback != nullptr && callback(user, kText, sizeof(kText) - 1, 1, 0) == 0) {
        return -1;
    }
    if (output != nullptr) {
        output->status = 0;
        output->text = kText;
        output->n_generated = 2;
        output->n_prompt = 3;
        output->prefill_ms = 1.0;
        output->decode_ms = 1.0;
    }
    return 0;
}

const char* qhx_status_str(qhx_status) { return "fake"; }

}  // extern "C"

int main() {
    if (!test_cancel_during_reset_targets_announced_request_only()) return 1;
    if (!test_idle_cancel_does_not_poison_next_request()) return 1;
    std::puts("QHexRT VLM cancellation tests passed");
    return 0;
}
