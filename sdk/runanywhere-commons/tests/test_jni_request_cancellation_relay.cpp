#include <atomic>
#include <chrono>
#include <cstdio>
#include <thread>

#include "jni/request_cancellation_relay.h"

namespace {

using namespace std::chrono_literals;
using rac::jni::RequestCancellationRelay;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

bool cancel_before_entry_is_request_scoped() {
    RequestCancellationRelay relay;
    int logical_cancels = 0;
    EXPECT_TRUE(relay.request_cancel(1, [&] { ++logical_cancels; }) ==
                RequestCancellationRelay::CancelResult::kPending);
    EXPECT_TRUE(logical_cancels == 1);
    EXPECT_TRUE(relay.start(1) == RequestCancellationRelay::StartResult::kCancelled);

    EXPECT_TRUE(relay.start(2) == RequestCancellationRelay::StartResult::kRun);
    relay.complete(2);
    EXPECT_TRUE(relay.request_cancel(1, [&] { ++logical_cancels; }) ==
                RequestCancellationRelay::CancelResult::kCompleted);
    EXPECT_TRUE(logical_cancels == 1);
    return true;
}

bool abandoned_pre_entry_cancel_does_not_poison_successor() {
    RequestCancellationRelay relay;
    EXPECT_TRUE(relay.request_cancel(1, [] {}) == RequestCancellationRelay::CancelResult::kPending);
    EXPECT_TRUE(relay.start(2) == RequestCancellationRelay::StartResult::kRun);
    relay.complete(2);
    EXPECT_TRUE(relay.start(1) == RequestCancellationRelay::StartResult::kInvalid);
    return true;
}

bool pulses_bridge_backend_publication_gap() {
    RequestCancellationRelay relay;
    std::atomic<bool> wrapper_started{false};
    std::atomic<bool> publish_backend{false};
    std::atomic<bool> backend_active{false};
    std::atomic<bool> backend_cancelled{false};
    std::atomic<int> cancel_attempts{0};

    std::thread request([&] {
        EXPECT_TRUE(relay.start(1) == RequestCancellationRelay::StartResult::kRun);
        wrapper_started.store(true, std::memory_order_release);
        while (!publish_backend.load(std::memory_order_acquire)) {
            std::this_thread::yield();
        }
        backend_active.store(true, std::memory_order_release);
        while (!backend_cancelled.load(std::memory_order_acquire)) {
            std::this_thread::yield();
        }
        relay.complete(1);
        return true;
    });

    while (!wrapper_started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    auto cancel_backend = [&] {
        cancel_attempts.fetch_add(1, std::memory_order_acq_rel);
        if (backend_active.load(std::memory_order_acquire)) {
            backend_cancelled.store(true, std::memory_order_release);
        }
    };
    EXPECT_TRUE(relay.request_cancel(1, cancel_backend) ==
                RequestCancellationRelay::CancelResult::kActive);
    EXPECT_TRUE(!backend_cancelled.load(std::memory_order_acquire));
    publish_backend.store(true, std::memory_order_release);
    while (relay.wait_until_retry_or_complete(1, 1ms)) {
        if (!relay.pulse_if_active(1, cancel_backend)) {
            break;
        }
    }
    request.join();

    EXPECT_TRUE(backend_cancelled.load(std::memory_order_acquire));
    EXPECT_TRUE(cancel_attempts.load(std::memory_order_acquire) >= 2);
    return true;
}

bool pulse_excludes_completion_and_successor() {
    RequestCancellationRelay relay;
    EXPECT_TRUE(relay.start(1) == RequestCancellationRelay::StartResult::kRun);
    std::atomic<bool> pulse_entered{false};
    std::atomic<bool> release_pulse{false};
    std::atomic<bool> completion_returned{false};

    std::thread pulse([&] {
        EXPECT_TRUE(relay.pulse_if_active(1, [&] {
            pulse_entered.store(true, std::memory_order_release);
            while (!release_pulse.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }
        }));
        return true;
    });
    while (!pulse_entered.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }

    std::thread completion([&] {
        relay.complete(1);
        completion_returned.store(true, std::memory_order_release);
    });
    std::this_thread::sleep_for(5ms);
    EXPECT_TRUE(!completion_returned.load(std::memory_order_acquire));
    release_pulse.store(true, std::memory_order_release);
    pulse.join();
    completion.join();

    EXPECT_TRUE(!relay.pulse_if_active(1, [] {}));
    EXPECT_TRUE(relay.start(2) == RequestCancellationRelay::StartResult::kRun);
    relay.complete(2);
    return true;
}

}  // namespace

int main() {
    if (!cancel_before_entry_is_request_scoped())
        return 1;
    if (!abandoned_pre_entry_cancel_does_not_poison_successor())
        return 1;
    if (!pulses_bridge_backend_publication_gap())
        return 1;
    if (!pulse_excludes_completion_and_successor())
        return 1;
    std::puts("JNI request cancellation relay tests passed");
    return 0;
}
