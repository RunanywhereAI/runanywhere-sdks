// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — benchmark harness C ABI.
//
// Tracks per-call timing + summarises stats (min/max/mean/p50/p95/p99) for
// LLM generation, STT transcription, and TTS synthesis. Mirrors the legacy
// `rac_benchmark_*` surface so frontends can drive on-device benchmark UIs
// without re-implementing the rolling-stats math in every language.

#ifndef RA_BENCHMARK_H
#define RA_BENCHMARK_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

// Monotonic millisecond clock — matches std::chrono::steady_clock.
int64_t ra_monotonic_now_ms(void);

typedef struct {
    int64_t  start_ms;
    int64_t  end_ms;
    int32_t  call_count;          // For batch operations
    int32_t  _reserved0;
    char*    label;               // Heap-allocated; free with ra_benchmark_string_free
} ra_benchmark_timing_t;

ra_status_t ra_benchmark_timing_init(ra_benchmark_timing_t* t, const char* label);
void        ra_benchmark_timing_finish(ra_benchmark_timing_t* t);
ra_status_t ra_benchmark_timing_to_json(const ra_benchmark_timing_t* t, char** out_json);
ra_status_t ra_benchmark_timing_to_csv(const ra_benchmark_timing_t* t, char** out_csv);

// ---------------------------------------------------------------------------
// Streaming metrics provider
// ---------------------------------------------------------------------------

typedef int64_t (*ra_benchmark_clock_fn)(void);   // Returns ms

ra_status_t ra_benchmark_set_metrics_provider(ra_benchmark_clock_fn clock_fn);

typedef struct {
    double  cpu_percent;
    int64_t memory_bytes;
    int64_t gpu_memory_bytes;
    double  battery_drain_per_min;
    double  thermal_state;          // Apple thermalState as double
} ra_benchmark_extended_metrics_t;

ra_status_t ra_benchmark_extended_metrics_init(ra_benchmark_extended_metrics_t* m);
ra_status_t ra_benchmark_capture_metrics(ra_benchmark_extended_metrics_t* out_metrics);

// ---------------------------------------------------------------------------
// Rolling stats (each instance tracks one metric like "tokens/sec")
// ---------------------------------------------------------------------------

typedef struct ra_benchmark_stats_s ra_benchmark_stats_t;

typedef struct {
    double  min_value;
    double  max_value;
    double  mean_value;
    double  p50;
    double  p95;
    double  p99;
    int64_t sample_count;
} ra_benchmark_summary_t;

ra_status_t ra_benchmark_stats_create(ra_benchmark_stats_t** out_stats);
void        ra_benchmark_stats_destroy(ra_benchmark_stats_t* stats);
void        ra_benchmark_stats_record(ra_benchmark_stats_t* stats, double value);
void        ra_benchmark_stats_reset(ra_benchmark_stats_t* stats);
int64_t     ra_benchmark_stats_count(const ra_benchmark_stats_t* stats);
ra_status_t ra_benchmark_stats_get_summary(const ra_benchmark_stats_t* stats,
                                            ra_benchmark_summary_t* out_summary);
ra_status_t ra_benchmark_stats_summary_to_json(const ra_benchmark_summary_t* summary,
                                                 char** out_json);

void ra_benchmark_string_free(char* s);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_BENCHMARK_H
