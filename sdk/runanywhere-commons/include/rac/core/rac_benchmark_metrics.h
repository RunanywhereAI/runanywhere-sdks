/**
 * @file rac_benchmark_metrics.h
 * @brief RunAnywhere Commons - Extended Benchmark Metrics
 *
 * Defines extended device/platform metrics captured alongside benchmark timing.
 * Actual metric collection is platform-specific (iOS/Android) and provided
 * via a callback provider pattern. The C++ layer defines interfaces only.
 *
 * Usage:
 *   // Platform SDK registers a provider during init:
 *   rac_benchmark_set_metrics_provider(my_provider_fn, my_context);
 *
 *   // Commons layer captures metrics at t0 and t6:
 *   rac_benchmark_extended_metrics_t metrics;
 *   rac_benchmark_capture_metrics(&metrics);
 */

#ifndef RAC_BENCHMARK_METRICS_H
#define RAC_BENCHMARK_METRICS_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXTENDED METRICS STRUCT
// =============================================================================

/**
 * Extended device/platform metrics captured during benchmark.
 *
 * All fields default to -1 (unavailable) unless the platform provider
 * populates them. This allows partial metric support across platforms.
 */
typedef struct rac_benchmark_extended_metrics {
    /** Resident memory usage in bytes at capture time (-1 if unavailable) */
    int64_t memory_usage_bytes;

    /** Peak memory usage in bytes during request (-1 if unavailable) */
    int64_t memory_peak_bytes;

    /** CPU temperature in Celsius (-1.0 if unavailable) */
    float cpu_temperature_celsius;

    /** Battery level 0.0-1.0 (-1.0 if unavailable) */
    float battery_level;

    /** GPU utilization 0-100% (-1.0 if unavailable) */
    float gpu_utilization_percent;

    /**
     * Thermal state of the device.
     *  0 = nominal
     *  1 = fair
     *  2 = serious
     *  3 = critical
     * -1 = unavailable
     */
    int32_t thermal_state;

} rac_benchmark_extended_metrics_t;

// =============================================================================
// METRICS PROVIDER CALLBACK
// =============================================================================

/**
 * Callback type for platform-specific metrics collection.
 *
 * The platform SDK (Swift/Kotlin) implements this to fill in
 * whatever device metrics are available on that platform.
 *
 * @param out Metrics struct to populate (pre-initialized to unavailable values)
 * @param user_data Platform context passed during registration
 */
typedef void (*rac_benchmark_metrics_provider_fn)(rac_benchmark_extended_metrics_t* out,
                                                   void* user_data);

// =============================================================================
// METRICS API
// =============================================================================

/**
 * Registers a platform-specific metrics provider.
 *
 * Call this during SDK initialization. Only one provider can be active.
 * Setting a new provider replaces the previous one.
 * Pass NULL to unregister.
 *
 * @param provider Metrics provider callback (NULL to unregister)
 * @param user_data Platform context passed to provider calls
 */
RAC_API void rac_benchmark_set_metrics_provider(rac_benchmark_metrics_provider_fn provider,
                                                 void* user_data);

/**
 * Captures current device metrics using the registered provider.
 *
 * If no provider is registered, all fields are set to unavailable (-1).
 * Thread-safe: can be called from any thread.
 *
 * @param out Metrics struct to populate (must not be NULL)
 */
RAC_API void rac_benchmark_capture_metrics(rac_benchmark_extended_metrics_t* out);

/**
 * Initializes an extended metrics struct to unavailable values.
 *
 * @param metrics Metrics struct to initialize (must not be NULL)
 */
RAC_API void rac_benchmark_extended_metrics_init(rac_benchmark_extended_metrics_t* metrics);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BENCHMARK_METRICS_H */
