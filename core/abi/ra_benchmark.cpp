// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_benchmark.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <sstream>
#include <string>
#include <vector>

namespace {

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

ra_benchmark_clock_fn g_clock = nullptr;

}  // namespace

struct ra_benchmark_stats_s {
    std::mutex          mu;
    std::vector<double> samples;
};

extern "C" {

int64_t ra_monotonic_now_ms(void) {
    if (g_clock) return g_clock();
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

ra_status_t ra_benchmark_set_metrics_provider(ra_benchmark_clock_fn clock_fn) {
    g_clock = clock_fn;
    return RA_OK;
}

ra_status_t ra_benchmark_timing_init(ra_benchmark_timing_t* t, const char* label) {
    if (!t) return RA_ERR_INVALID_ARGUMENT;
    *t = ra_benchmark_timing_t{};
    t->start_ms = ra_monotonic_now_ms();
    t->end_ms   = 0;
    t->label    = label ? dup_cstr(label) : nullptr;
    return RA_OK;
}

void ra_benchmark_timing_finish(ra_benchmark_timing_t* t) {
    if (!t) return;
    t->end_ms = ra_monotonic_now_ms();
    if (t->call_count <= 0) t->call_count = 1;
}

ra_status_t ra_benchmark_timing_to_json(const ra_benchmark_timing_t* t, char** out_json) {
    if (!t || !out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{\"label\":\"" << (t->label ? t->label : "") << "\","
       << "\"start_ms\":" << t->start_ms << ","
       << "\"end_ms\":" << t->end_ms << ","
       << "\"duration_ms\":" << (t->end_ms - t->start_ms) << ","
       << "\"call_count\":" << t->call_count << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_benchmark_timing_to_csv(const ra_benchmark_timing_t* t, char** out_csv) {
    if (!t || !out_csv) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << (t->label ? t->label : "") << "," << t->start_ms << ","
       << t->end_ms << "," << (t->end_ms - t->start_ms) << "," << t->call_count;
    *out_csv = dup_cstr(os.str());
    return *out_csv ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_benchmark_extended_metrics_init(ra_benchmark_extended_metrics_t* m) {
    if (!m) return RA_ERR_INVALID_ARGUMENT;
    *m = ra_benchmark_extended_metrics_t{};
    return RA_OK;
}

ra_status_t ra_benchmark_capture_metrics(ra_benchmark_extended_metrics_t* out_metrics) {
    if (!out_metrics) return RA_ERR_INVALID_ARGUMENT;
    // Lightweight default: zeroes; the platform bridge can override via
    // ra_benchmark_set_metrics_provider + a custom impl in future.
    *out_metrics = ra_benchmark_extended_metrics_t{};
    return RA_OK;
}

ra_status_t ra_benchmark_stats_create(ra_benchmark_stats_t** out_stats) {
    if (!out_stats) return RA_ERR_INVALID_ARGUMENT;
    *out_stats = new (std::nothrow) ra_benchmark_stats_s();
    return *out_stats ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_benchmark_stats_destroy(ra_benchmark_stats_t* stats) {
    delete stats;
}

void ra_benchmark_stats_record(ra_benchmark_stats_t* stats, double value) {
    if (!stats) return;
    std::lock_guard lock(stats->mu);
    stats->samples.push_back(value);
}

void ra_benchmark_stats_reset(ra_benchmark_stats_t* stats) {
    if (!stats) return;
    std::lock_guard lock(stats->mu);
    stats->samples.clear();
}

int64_t ra_benchmark_stats_count(const ra_benchmark_stats_t* stats) {
    if (!stats) return 0;
    std::lock_guard lock(const_cast<std::mutex&>(stats->mu));
    return static_cast<int64_t>(stats->samples.size());
}

ra_status_t ra_benchmark_stats_get_summary(const ra_benchmark_stats_t* stats,
                                            ra_benchmark_summary_t* out_summary) {
    if (!stats || !out_summary) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(const_cast<std::mutex&>(stats->mu));
    *out_summary = ra_benchmark_summary_t{};
    if (stats->samples.empty()) return RA_OK;
    std::vector<double> sorted = stats->samples;
    std::sort(sorted.begin(), sorted.end());
    out_summary->sample_count = static_cast<int64_t>(sorted.size());
    out_summary->min_value    = sorted.front();
    out_summary->max_value    = sorted.back();
    double sum = 0;
    for (double v : sorted) sum += v;
    out_summary->mean_value = sum / sorted.size();
    auto pct = [&](double p) {
        if (sorted.empty()) return 0.0;
        const auto idx = static_cast<std::size_t>(
            std::min<double>(sorted.size() - 1, std::floor(p * (sorted.size() - 1))));
        return sorted[idx];
    };
    out_summary->p50 = pct(0.50);
    out_summary->p95 = pct(0.95);
    out_summary->p99 = pct(0.99);
    return RA_OK;
}

ra_status_t ra_benchmark_stats_summary_to_json(const ra_benchmark_summary_t* s, char** out_json) {
    if (!s || !out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{\"min\":" << s->min_value << ",\"max\":" << s->max_value
       << ",\"mean\":" << s->mean_value
       << ",\"p50\":" << s->p50 << ",\"p95\":" << s->p95 << ",\"p99\":" << s->p99
       << ",\"count\":" << s->sample_count << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_benchmark_string_free(char* s) { if (s) std::free(s); }

}  // extern "C"
