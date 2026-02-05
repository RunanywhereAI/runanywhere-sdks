/**
 * @file rac_benchmark.h
 * @brief RunAnywhere Commons - Benchmark Timing Support
 *
 * This header provides types and functions for benchmark timing instrumentation.
 * The timing struct captures key timestamps during LLM inference for performance
 * measurement and analysis.
 *
 * Design principles:
 * - Zero overhead when not benchmarking: timing is opt-in via pointer parameter
 * - Monotonic clock: uses steady_clock for accurate cross-platform timing
 * - All timestamps are relative to a process-local epoch (not wall-clock)
 */

#ifndef RAC_BENCHMARK_H
#define RAC_BENCHMARK_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// BENCHMARK TIMING STRUCT
// =============================================================================

/**
 * Benchmark timing structure for LLM inference.
 *
 * Captures timestamps at key points during inference:
 * - t0: Request start (component API entry)
 * - t2: Prefill start (backend, before llama_decode for prompt)
 * - t3: Prefill end (backend, after llama_decode returns)
 * - t4: First token (component, first token callback)
 * - t5: Last token (backend, decode loop exits)
 * - t6: Request end (component, before complete callback)
 *
 * All timestamps are in milliseconds from a process-local epoch.
 * Use rac_monotonic_now_ms() to get comparable timestamps.
 *
 * Note: t1 is intentionally skipped to match the specification.
 */
typedef struct rac_benchmark_timing {
    /** t0: Request start - recorded at component API entry */
    int64_t t0_request_start_ms;

    /** t2: Prefill start - recorded before llama_decode for prompt batch */
    int64_t t2_prefill_start_ms;

    /** t3: Prefill end - recorded after llama_decode returns for prompt */
    int64_t t3_prefill_end_ms;

    /** t4: First token - recorded when first token callback is invoked */
    int64_t t4_first_token_ms;

    /** t5: Last token - recorded when decode loop exits */
    int64_t t5_last_token_ms;

    /** t6: Request end - recorded before complete callback */
    int64_t t6_request_end_ms;

    /** Number of tokens in the prompt */
    int32_t prompt_tokens;

    /** Number of tokens generated */
    int32_t output_tokens;

    /**
     * Status of the request:
     * - 0: Success
     * - Non-zero: Error code (from rac_result_t)
     */
    int32_t status;

} rac_benchmark_timing_t;

// =============================================================================
// BENCHMARK STATUS CODES
// =============================================================================

/** Benchmark request completed successfully */
#define RAC_BENCHMARK_STATUS_SUCCESS ((int32_t)0)

/** Benchmark request failed due to error */
#define RAC_BENCHMARK_STATUS_ERROR ((int32_t)1)

/** Benchmark request timed out */
#define RAC_BENCHMARK_STATUS_TIMEOUT ((int32_t)2)

/** Benchmark request was cancelled */
#define RAC_BENCHMARK_STATUS_CANCELLED ((int32_t)3)

// =============================================================================
// MONOTONIC TIME API
// =============================================================================

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

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Initializes a benchmark timing struct to zero values.
 *
 * @param timing Pointer to timing struct to initialize
 */
RAC_API void rac_benchmark_timing_init(rac_benchmark_timing_t* timing);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_H */
