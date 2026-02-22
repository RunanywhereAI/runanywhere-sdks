/**
 * @file rac_benchmark_stats.h
 * @brief RunAnywhere Commons - Benchmark Statistical Analysis
 *
 * Collects benchmark timing observations and computes statistical summaries
 * including percentiles (P50/P95/P99), mean, stddev, and outlier detection.
 *
 * Usage:
 *   rac_benchmark_stats_handle_t stats;
 *   rac_benchmark_stats_create(&stats);
 *
 *   // Record observations
 *   rac_benchmark_stats_record(stats, &timing1);
 *   rac_benchmark_stats_record(stats, &timing2);
 *
 *   // Get summary
 *   rac_benchmark_summary_t summary;
 *   rac_benchmark_stats_get_summary(stats, &summary);
 *
 *   // Export as JSON
 *   char* json = rac_benchmark_stats_summary_to_json(&summary);
 *   free(json);
 *
 *   rac_benchmark_stats_destroy(stats);
 */

#ifndef RAC_BENCHMARK_STATS_H
#define RAC_BENCHMARK_STATS_H

#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STATS HANDLE (OPAQUE)
// =============================================================================

/** Opaque handle for a benchmark stats collector */
typedef void* rac_benchmark_stats_handle_t;

// =============================================================================
// SUMMARY STRUCT
// =============================================================================

/**
 * Statistical summary of collected benchmark observations.
 *
 * All time values are in milliseconds. Throughput is in tokens/second.
 * Fields are 0 if no valid observations were recorded for that metric.
 */
typedef struct rac_benchmark_summary {
    /** Number of observations recorded */
    int32_t count;

    // Time to First Token stats (t4 - t0)
    double ttft_p50_ms;
    double ttft_p95_ms;
    double ttft_p99_ms;
    double ttft_min_ms;
    double ttft_max_ms;
    double ttft_mean_ms;
    double ttft_stddev_ms;

    // Prefill duration stats (t3 - t2)
    double prefill_p50_ms;
    double prefill_p95_ms;
    double prefill_p99_ms;

    // Decode throughput stats (output_tokens / (t5 - t3) * 1000)
    double decode_tps_p50;
    double decode_tps_p95;
    double decode_tps_p99;

    // End-to-end latency stats (t6 - t0)
    double e2e_p50_ms;
    double e2e_p95_ms;
    double e2e_p99_ms;

    /** Number of observations where E2E > mean + 2*stddev */
    int32_t outlier_count;

} rac_benchmark_summary_t;

// =============================================================================
// STATS COLLECTOR API
// =============================================================================

/**
 * Creates a new benchmark stats collector.
 *
 * @param out_handle Output: collector handle
 * @return RAC_SUCCESS or RAC_ERROR_NULL_POINTER
 */
RAC_API rac_result_t rac_benchmark_stats_create(rac_benchmark_stats_handle_t* out_handle);

/**
 * Destroys a stats collector and frees all associated memory.
 *
 * @param handle Collector handle (NULL is a no-op)
 */
RAC_API void rac_benchmark_stats_destroy(rac_benchmark_stats_handle_t handle);

/**
 * Records a benchmark timing observation.
 *
 * Only observations with status == RAC_BENCHMARK_STATUS_SUCCESS are recorded.
 * Derived metrics (TTFT, prefill, decode TPS, E2E) are extracted and stored.
 *
 * Thread-safe: can be called from any thread.
 *
 * @param handle Collector handle
 * @param timing Timing struct to record
 */
RAC_API void rac_benchmark_stats_record(rac_benchmark_stats_handle_t handle,
                                         const rac_benchmark_timing_t* timing);

/**
 * Resets the collector, discarding all recorded observations.
 *
 * @param handle Collector handle
 */
RAC_API void rac_benchmark_stats_reset(rac_benchmark_stats_handle_t handle);

/**
 * Returns the number of recorded observations.
 *
 * @param handle Collector handle
 * @return Observation count (0 if handle is NULL)
 */
RAC_API int32_t rac_benchmark_stats_count(rac_benchmark_stats_handle_t handle);

/**
 * Computes a statistical summary of all recorded observations.
 *
 * @param handle Collector handle
 * @param out_summary Output: summary struct
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, or RAC_ERROR_INVALID_STATE (no data)
 */
RAC_API rac_result_t rac_benchmark_stats_get_summary(rac_benchmark_stats_handle_t handle,
                                                      rac_benchmark_summary_t* out_summary);

/**
 * Serializes a summary struct as a JSON string.
 *
 * @param summary Summary struct to serialize (NULL returns NULL)
 * @return Heap-allocated JSON string (caller must free()), or NULL on error
 */
RAC_API char* rac_benchmark_stats_summary_to_json(const rac_benchmark_summary_t* summary);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_STATS_H */
