/**
 * @file rac_benchmark.h
 * @brief RunAnywhere Commons - Monotonic timing.
 *
 * Process-local monotonic millisecond clock used for cross-platform latency
 * measurement: steady_clock-based, unaffected by wall-clock changes, relative
 * to a process-local epoch (the first call).
 */

#ifndef RAC_BENCHMARK_H
#define RAC_BENCHMARK_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Gets the current monotonic time in milliseconds.
 *
 * Uses std::chrono::steady_clock for accurate, monotonic timing that is not
 * affected by system clock changes. The returned value is relative to a
 * process-local epoch (the first call to this function).
 *
 * This function is thread-safe and lock-free on all supported platforms.
 *
 * @return Current monotonic time in milliseconds from process-local epoch
 */
RAC_API int64_t rac_monotonic_now_ms(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_H */
