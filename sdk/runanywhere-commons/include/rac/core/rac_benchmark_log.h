/**
 * @file rac_benchmark_log.h
 * @brief RunAnywhere Commons - Benchmark Logging and Serialization
 *
 * Provides functions to serialize benchmark timing data as JSON or CSV,
 * and to log benchmark results via the RAC logging system.
 *
 * Usage:
 *   // Log timing summary
 *   rac_benchmark_timing_log(&timing, "inference_run_1");
 *
 *   // Export as JSON
 *   char* json = rac_benchmark_timing_to_json(&timing);
 *   // ... use json ...
 *   free(json);
 *
 *   // Export as CSV
 *   char* header = rac_benchmark_timing_to_csv(NULL, RAC_TRUE);
 *   char* row = rac_benchmark_timing_to_csv(&timing, RAC_FALSE);
 *   free(header);
 *   free(row);
 */

#ifndef RAC_BENCHMARK_LOG_H
#define RAC_BENCHMARK_LOG_H

#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// JSON SERIALIZATION
// =============================================================================

/**
 * Serializes a benchmark timing struct as a JSON string.
 *
 * Includes all timing fields plus derived metrics:
 * - ttft_ms: Time to first token (t4 - t0)
 * - prefill_ms: Prefill duration (t3 - t2)
 * - decode_ms: Decode duration (t5 - t3)
 * - e2e_ms: End-to-end latency (t6 - t0)
 * - decode_tps: Decode throughput (output_tokens / decode_ms * 1000)
 *
 * @param timing Timing struct to serialize (NULL returns NULL)
 * @return Heap-allocated JSON string (caller must free()), or NULL on error
 */
RAC_API char* rac_benchmark_timing_to_json(const rac_benchmark_timing_t* timing);

// =============================================================================
// CSV SERIALIZATION
// =============================================================================

/**
 * Serializes a benchmark timing struct as a CSV row.
 *
 * @param timing Timing struct to serialize (ignored when header is RAC_TRUE)
 * @param header If RAC_TRUE, returns the CSV header row instead of data
 * @return Heap-allocated CSV string (caller must free()), or NULL on error
 */
RAC_API char* rac_benchmark_timing_to_csv(const rac_benchmark_timing_t* timing, rac_bool_t header);

// =============================================================================
// LOGGING
// =============================================================================

/**
 * Logs a benchmark timing summary via the RAC logging system.
 *
 * Outputs key metrics at INFO level under the "Benchmark" category:
 * - TTFT, prefill time, decode time, E2E latency
 * - Token counts and throughput
 * - Status and error code
 *
 * @param timing Timing struct to log (NULL is a no-op)
 * @param label Optional label for this benchmark run (can be NULL)
 */
RAC_API void rac_benchmark_timing_log(const rac_benchmark_timing_t* timing, const char* label);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_LOG_H */
