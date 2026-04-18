/**
 * @file rac_benchmark_log.h
 * @brief RunAnywhere Commons - Benchmark Logging and Serialization
 *
 * Provides functions to serialize benchmark timing data as JSON or CSV,
 * and to log benchmark results via the RAC logging system.
 *
 * All functions return rac_result_t for consistent error handling.
 * Serialization functions write a heap-allocated string to an out-parameter
 * (caller must free() on success).
 *
 * Usage:
 *   // Log timing summary
 *   rac_benchmark_timing_log(&timing, "inference_run_1");
 *
 *   // Export as JSON
 *   char* json = NULL;
 *   if (rac_benchmark_timing_to_json(&timing, &json) == RAC_SUCCESS) {
 *       // ... use json ...
 *       free(json);
 *   }
 *
 *   // Export as CSV
 *   char* header = NULL;
 *   char* row = NULL;
 *   rac_benchmark_timing_to_csv(NULL, RAC_TRUE, &header);
 *   rac_benchmark_timing_to_csv(&timing, RAC_FALSE, &row);
 *   free(header);
 *   free(row);
 */

#ifndef RAC_BENCHMARK_LOG_H
#define RAC_BENCHMARK_LOG_H

#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_error.h"
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
 * On success, *out_json is set to a heap-allocated string that the caller
 * must release via free(). On failure, *out_json is set to NULL.
 *
 * @param timing   Timing struct to serialize (must not be NULL)
 * @param out_json Output pointer that receives the JSON string (must not be NULL)
 * @return RAC_SUCCESS on success,
 *         RAC_ERROR_NULL_POINTER if timing or out_json is NULL,
 *         RAC_ERROR_OUT_OF_MEMORY if allocation fails
 */
RAC_API rac_result_t rac_benchmark_timing_to_json(const rac_benchmark_timing_t* timing,
                                                  char** out_json);

// =============================================================================
// CSV SERIALIZATION
// =============================================================================

/**
 * Serializes a benchmark timing struct as a CSV row.
 *
 * When header is RAC_TRUE, emits the CSV header row (timing may be NULL).
 * When header is RAC_FALSE, emits a data row (timing must not be NULL).
 *
 * On success, *out_csv is set to a heap-allocated string that the caller
 * must release via free(). On failure, *out_csv is set to NULL.
 *
 * @param timing  Timing struct to serialize (ignored when header is RAC_TRUE,
 *                otherwise must not be NULL)
 * @param header  If RAC_TRUE, emits the CSV header row instead of data
 * @param out_csv Output pointer that receives the CSV string (must not be NULL)
 * @return RAC_SUCCESS on success,
 *         RAC_ERROR_NULL_POINTER if out_csv is NULL, or if header is RAC_FALSE
 *             and timing is NULL,
 *         RAC_ERROR_OUT_OF_MEMORY if allocation fails
 */
RAC_API rac_result_t rac_benchmark_timing_to_csv(const rac_benchmark_timing_t* timing,
                                                 rac_bool_t header, char** out_csv);

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
 * @param timing Timing struct to log (must not be NULL)
 * @param label  Optional label for this benchmark run (may be NULL)
 * @return RAC_SUCCESS on success,
 *         RAC_ERROR_NULL_POINTER if timing is NULL
 */
RAC_API rac_result_t rac_benchmark_timing_log(const rac_benchmark_timing_t* timing,
                                              const char* label);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_LOG_H */
