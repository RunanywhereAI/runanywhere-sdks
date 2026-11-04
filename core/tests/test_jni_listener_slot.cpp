#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <mutex>
#include <thread>
#include <vector>

#include "jni/listener_slot.h"

namespace {

using namespace std::chrono_literals;
using rac::jni::replace_listener_then_register;

#define EXPECT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "EXPECT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return false;                                                                        \
        }                                                                                        \
    } while (0)

int g_a = 0;
int g_b = 0;

// Mirrors the download progress sink: emit holds sink_mutex while the callback
// takes listener_mutex, so registration must not hold listener_mutex.
bool registration_does_not_hold_listener_mutex() {
    std::mutex listener_mutex;
    std::mutex sink_mutex;
    int* slot = nullptr;
    std::vector<int*> released;

    std::promise<void> emitter_holds_sink;
    std::promise<void> setter_entered;
    auto setter_entered_future = setter_entered.get_future();
    std::thread emitter([&] {
        std::lock_guard<std::mutex> sink(sink_mutex);
        emitter_holds_sink.set_value();
        setter_entered_future.wait();
        std::lock_guard<std::mutex> listener(listener_mutex);
    });
    emitter_holds_sink.get_future().wait();

    auto rc = replace_listener_then_register(
        listener_mutex, slot, &g_a,
        [&](bool has_listener) {
            setter_entered.set_value();
            std::lock_guard<std::mutex> sink(sink_mutex);
            return has_listener ? 0 : 1;
        },
        [&](int* ref) { released.push_back(ref); });
    emitter.join();

    EXPECT_TRUE(rc == 0);
    EXPECT_TRUE(slot == &g_a);
    EXPECT_TRUE(released.empty());
    return true;
}

bool success_releases_previous_listener() {
    std::mutex mutex;
    int* slot = &g_a;
    std::vector<int*> released;
    auto rc = replace_listener_then_register(
        mutex, slot, &g_b, [](bool has_listener) { return has_listener ? 0 : 1; },
        [&](int* ref) { released.push_back(ref); });
    EXPECT_TRUE(rc == 0);
    EXPECT_TRUE(slot == &g_b);
    EXPECT_TRUE(released.size() == 1 && released[0] == &g_a);

    released.clear();
    rc = replace_listener_then_register(
        mutex, slot, static_cast<int*>(nullptr), [](bool) { return 0; },
        [&](int* ref) { released.push_back(ref); });
    EXPECT_TRUE(rc == 0);
    EXPECT_TRUE(slot == nullptr);
    EXPECT_TRUE(released.size() == 1 && released[0] == &g_b);
    return true;
}

bool failure_restores_previous_and_releases_new() {
    std::mutex mutex;
    int* slot = &g_a;
    std::vector<int*> released;
    auto rc = replace_listener_then_register(
        mutex, slot, &g_b, [](bool) { return -1; }, [&](int* ref) { released.push_back(ref); });
    EXPECT_TRUE(rc == -1);
    EXPECT_TRUE(slot == &g_a);
    EXPECT_TRUE(released.size() == 1 && released[0] == &g_b);
    return true;
}

bool failure_after_concurrent_replace_releases_only_previous() {
    std::mutex mutex;
    int* slot = &g_a;
    std::vector<int*> released;
    auto rc = replace_listener_then_register(
        mutex, slot, &g_b,
        [&](bool) {
            // Another setter swaps &g_b out (and so owns it) before this one fails.
            std::lock_guard<std::mutex> lock(mutex);
            slot = nullptr;
            return -1;
        },
        [&](int* ref) { released.push_back(ref); });
    EXPECT_TRUE(rc == -1);
    EXPECT_TRUE(slot == nullptr);
    EXPECT_TRUE(released.size() == 1 && released[0] == &g_a);
    return true;
}

}  // namespace

int main() {
    // A regression to holding the listener mutex across registration deadlocks
    // the first case; fail instead of hanging ctest.
    auto first = std::async(std::launch::async, registration_does_not_hold_listener_mutex);
    if (first.wait_for(5s) != std::future_status::ready) {
        std::fprintf(stderr, "FAILED: registration_does_not_hold_listener_mutex (deadlock)\n");
        std::fflush(stderr);
        std::_Exit(1);
    }
    const bool ok = first.get() && success_releases_previous_listener() &&
                    failure_restores_previous_and_releases_new() &&
                    failure_after_concurrent_replace_releases_only_previous();
    if (!ok) {
        return 1;
    }
    std::printf("jni listener slot tests passed\n");
    return 0;
}
