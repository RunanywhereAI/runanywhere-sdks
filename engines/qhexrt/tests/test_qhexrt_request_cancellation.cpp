/** Request-latch regression tests independent of the private QHexRT ABI. */

#include "qhexrt_request_cancellation.h"

#include <atomic>
#include <cstdio>
#include <thread>

int main() {
    qhexrt_engine::RequestCancellation requests;
    std::atomic<bool> request_started{false};
    std::atomic<bool> cancellation_sent{false};
    uint64_t first_id = 0;
    bool cancellation_observed = false;

    std::thread request([&] {
        first_id = requests.begin();
        request_started.store(true, std::memory_order_release);
        while (!cancellation_sent.load(std::memory_order_acquire)) {
            std::this_thread::yield();
        }
        cancellation_observed = requests.is_cancelled(first_id);
        requests.finish(first_id);
    });

    while (!request_started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    requests.cancel_active();
    cancellation_sent.store(true, std::memory_order_release);
    request.join();

    if (!cancellation_observed) {
        std::fprintf(stderr, "cancel was lost during the request setup window\n");
        return 1;
    }
    if (requests.active_id.load(std::memory_order_acquire) != 0) {
        std::fprintf(stderr, "finished request remained active\n");
        return 1;
    }

    requests.cancel_active();  // no active request; must not pre-cancel its successor
    const uint64_t second_id = requests.begin();
    if (second_id == first_id || requests.is_cancelled(second_id)) {
        std::fprintf(stderr, "successor inherited an earlier cancellation\n");
        return 1;
    }
    requests.finish(second_id);
    return 0;
}
