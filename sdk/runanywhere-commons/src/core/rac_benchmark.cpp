/**
 * @file rac_benchmark.cpp
 * @brief RunAnywhere Commons - Benchmark Timing Implementation
 *
 * Implements monotonic time helper and benchmark timing utilities.
 * Uses std::chrono::steady_clock for accurate, cross-platform timing
 * that is not affected by system clock adjustments.
 */

#include "rac/core/rac_benchmark.h"

#include <chrono>
#include <cstring>

namespace {

/**
 * Process-local epoch for monotonic timing.
 * Initialized on first call to rac_monotonic_now_ms().
 * Using a local epoch keeps timestamp values small and manageable.
 */
class MonotonicEpoch {
   public:
    static MonotonicEpoch& instance() {
        static MonotonicEpoch epoch;
        return epoch;
    }

    int64_t elapsed_ms() const {
        auto now = std::chrono::steady_clock::now();
        auto duration = now - epoch_;
        return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
    }

   private:
    MonotonicEpoch() : epoch_(std::chrono::steady_clock::now()) {}

    std::chrono::steady_clock::time_point epoch_;
};

}  // namespace

extern "C" {

int64_t rac_monotonic_now_ms(void) {
    return MonotonicEpoch::instance().elapsed_ms();
}

void rac_benchmark_timing_init(rac_benchmark_timing_t* timing) {
    if (timing != nullptr) {
        std::memset(timing, 0, sizeof(rac_benchmark_timing_t));
    }
}

}  // extern "C"
