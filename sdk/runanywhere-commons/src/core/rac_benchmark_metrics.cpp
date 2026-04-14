/**
 * @file rac_benchmark_metrics.cpp
 * @brief RunAnywhere Commons - Extended Benchmark Metrics Implementation
 *
 * Implements the metrics provider registry. Platform SDKs (iOS/Android)
 * register a provider callback during initialization. The commons layer
 * calls rac_benchmark_capture_metrics() at t0 and t6 to snapshot device state.
 */

#include "rac/core/rac_benchmark_metrics.h"

#include <cstring>
#include <memory>
#include <mutex>

namespace {

struct ProviderWrapper {
    rac_benchmark_metrics_provider_fn fn = nullptr;
    void* user_data = nullptr;
};

// Published as a shared_ptr under a mutex so concurrent capture callers keep
// the wrapper (fn + user_data) alive for the duration of their invocation,
// even if the platform unregisters or replaces the provider mid-call.
//
// A std::atomic<std::shared_ptr<T>> would be preferable, but Apple Clang's
// libc++ has not yet shipped the C++20 specialization (requires trivially
// copyable T). A short mutex-guarded load/store is equally lifetime-safe and
// only marginally slower on the capture path — which is invoked twice per
// benchmark, not in a hot loop.
std::mutex g_provider_mutex;
std::shared_ptr<ProviderWrapper> g_provider;

std::shared_ptr<ProviderWrapper> load_provider() {
    std::lock_guard<std::mutex> lock(g_provider_mutex);
    return g_provider;
}

void store_provider(std::shared_ptr<ProviderWrapper> next) {
    std::lock_guard<std::mutex> lock(g_provider_mutex);
    g_provider = std::move(next);
}

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
    if (provider == nullptr) {
        store_provider(nullptr);
        return;
    }

    store_provider(std::make_shared<ProviderWrapper>(ProviderWrapper{provider, user_data}));
}

void rac_benchmark_capture_metrics(rac_benchmark_extended_metrics_t* out) {
    if (out == nullptr) {
        return;
    }

    // Initialize to unavailable
    rac_benchmark_extended_metrics_init(out);

    // Snapshot the provider; the local shared_ptr keeps the wrapper (and its
    // user_data pointer) alive for the duration of the call, even if another
    // thread concurrently unregisters or replaces it.
    auto local = load_provider();
    if (local && local->fn != nullptr) {
        local->fn(out, local->user_data);
    }
}

}  // extern "C"
