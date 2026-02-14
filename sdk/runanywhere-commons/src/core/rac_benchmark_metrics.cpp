/**
 * @file rac_benchmark_metrics.cpp
 * @brief RunAnywhere Commons - Extended Benchmark Metrics Implementation
 *
 * Implements the metrics provider registry. Platform SDKs (iOS/Android)
 * register a provider callback during initialization. The commons layer
 * calls rac_benchmark_capture_metrics() at t0 and t6 to snapshot device state.
 */

#include "rac/core/rac_benchmark_metrics.h"

#include <atomic>
#include <cstring>
#include <mutex>

namespace {

struct MetricsProvider {
    rac_benchmark_metrics_provider_fn fn = nullptr;
    void* user_data = nullptr;
};

// Atomic pointer for lock-free provider access.
// Provider registration is rare; reads are frequent.
std::atomic<MetricsProvider*> g_provider{nullptr};

// Storage for the current provider (swapped atomically)
MetricsProvider g_provider_storage[2];
std::atomic<int> g_provider_index{0};

}  // namespace

extern "C" {

void rac_benchmark_extended_metrics_init(rac_benchmark_extended_metrics_t* metrics) {
    if (metrics == nullptr) {
        return;
    }
    metrics->memory_usage_bytes = -1;
    metrics->memory_peak_bytes = -1;
    metrics->cpu_temperature_celsius = -1.0f;
    metrics->battery_level = -1.0f;
    metrics->gpu_utilization_percent = -1.0f;
    metrics->thermal_state = -1;
}

void rac_benchmark_set_metrics_provider(rac_benchmark_metrics_provider_fn provider,
                                         void* user_data) {
    static std::mutex write_mutex;

    if (provider == nullptr) {
        g_provider.store(nullptr, std::memory_order_release);
        return;
    }

    // Serialize the rare registration path to prevent torn fn/user_data pairs
    std::lock_guard<std::mutex> lock(write_mutex);
    int idx = g_provider_index.load(std::memory_order_relaxed);
    int next = 1 - idx;
    g_provider_storage[next].fn = provider;
    g_provider_storage[next].user_data = user_data;
    g_provider.store(&g_provider_storage[next], std::memory_order_release);
    g_provider_index.store(next, std::memory_order_relaxed);
}

void rac_benchmark_capture_metrics(rac_benchmark_extended_metrics_t* out) {
    if (out == nullptr) {
        return;
    }

    // Initialize to unavailable
    rac_benchmark_extended_metrics_init(out);

    // Call provider if registered
    MetricsProvider* provider = g_provider.load(std::memory_order_acquire);
    if (provider != nullptr && provider->fn != nullptr) {
        provider->fn(out, provider->user_data);
    }
}

}  // extern "C"
