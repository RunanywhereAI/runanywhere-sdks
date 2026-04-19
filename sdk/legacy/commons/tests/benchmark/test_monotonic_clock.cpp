/**
 * @file test_monotonic_clock.cpp
 * @brief Tests for rac_monotonic_now_ms() monotonic clock
 */

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

#include "rac/core/rac_benchmark.h"

// =============================================================================
// BASIC FUNCTIONALITY
// =============================================================================

TEST(MonotonicClock, ReturnsNonNegative) {
    int64_t now = rac_monotonic_now_ms();
    EXPECT_GE(now, 0);
}

TEST(MonotonicClock, MonotonicallyNonDecreasing) {
    int64_t prev = rac_monotonic_now_ms();
    for (int i = 0; i < 1000; ++i) {
        int64_t curr = rac_monotonic_now_ms();
        EXPECT_GE(curr, prev) << "Clock went backwards at iteration " << i;
        prev = curr;
    }
}

TEST(MonotonicClock, ElapsedTimeAccuracy) {
    int64_t before = rac_monotonic_now_ms();
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    int64_t after = rac_monotonic_now_ms();

    int64_t elapsed = after - before;
    // Allow generous range for CI environments: 80ms to 300ms
    EXPECT_GE(elapsed, 80) << "Elapsed time too short: " << elapsed << "ms";
    EXPECT_LE(elapsed, 300) << "Elapsed time too long: " << elapsed << "ms";
}

TEST(MonotonicClock, DistinctOverTime) {
    int64_t first = rac_monotonic_now_ms();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    int64_t second = rac_monotonic_now_ms();

    EXPECT_GT(second, first) << "Two calls 10ms apart should produce distinct values";
}

// =============================================================================
// THREAD SAFETY
// =============================================================================

TEST(MonotonicClock, ThreadSafety) {
    constexpr int kNumThreads = 8;
    constexpr int kCallsPerThread = 10000;

    std::atomic<bool> any_negative{false};
    std::atomic<bool> any_decreasing{false};

    auto worker = [&]() {
        int64_t prev = rac_monotonic_now_ms();
        for (int i = 0; i < kCallsPerThread; ++i) {
            int64_t curr = rac_monotonic_now_ms();
            if (curr < 0) {
                any_negative.store(true, std::memory_order_relaxed);
            }
            if (curr < prev) {
                any_decreasing.store(true, std::memory_order_relaxed);
            }
            prev = curr;
        }
    };

    std::vector<std::thread> threads;
    threads.reserve(kNumThreads);
    for (int i = 0; i < kNumThreads; ++i) {
        threads.emplace_back(worker);
    }
    for (auto& t : threads) {
        t.join();
    }

    EXPECT_FALSE(any_negative.load()) << "Got negative timestamp from thread";
    EXPECT_FALSE(any_decreasing.load()) << "Clock went backwards in thread";
}
