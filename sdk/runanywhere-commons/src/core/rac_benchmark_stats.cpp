/**
 * @file rac_benchmark_stats.cpp
 * @brief RunAnywhere Commons - Benchmark Statistical Analysis Implementation
 *
 * Collects derived metrics from timing observations and computes
 * percentiles, mean, stddev, and outlier counts.
 */

#include "rac/core/rac_benchmark_stats.h"

#include "rac/core/rac_error.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

/**
 * Internal stats collector.
 * Stores vectors of derived metrics extracted from timing observations.
 */
class BenchmarkStatsCollector {
   public:
    void record(const rac_benchmark_timing_t* timing) {
        if (timing == nullptr) {
            return;
        }

        // Only record successful observations
        if (timing->status != RAC_BENCHMARK_STATUS_SUCCESS) {
            return;
        }

        std::lock_guard<std::mutex> lock(mutex_);

        // TTFT: t4 - t0
        if (timing->t4_first_token_ms > 0 && timing->t0_request_start_ms > 0) {
            ttft_values_.push_back(
                static_cast<double>(timing->t4_first_token_ms - timing->t0_request_start_ms));
        }

        // Prefill: t3 - t2
        if (timing->t3_prefill_end_ms > 0 && timing->t2_prefill_start_ms > 0) {
            prefill_values_.push_back(
                static_cast<double>(timing->t3_prefill_end_ms - timing->t2_prefill_start_ms));
        }

        // Decode TPS: output_tokens / (t5 - t3) * 1000
        if (timing->t5_last_token_ms > 0 && timing->t3_prefill_end_ms > 0 &&
            timing->output_tokens > 0) {
            double decode_ms =
                static_cast<double>(timing->t5_last_token_ms - timing->t3_prefill_end_ms);
            if (decode_ms > 0.0) {
                decode_tps_values_.push_back(
                    static_cast<double>(timing->output_tokens) / decode_ms * 1000.0);
            }
        }

        // E2E: t6 - t0
        if (timing->t6_request_end_ms > 0 && timing->t0_request_start_ms > 0) {
            e2e_values_.push_back(
                static_cast<double>(timing->t6_request_end_ms - timing->t0_request_start_ms));
        }

        count_++;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        ttft_values_.clear();
        prefill_values_.clear();
        decode_tps_values_.clear();
        e2e_values_.clear();
        count_ = 0;
    }

    int32_t count() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return count_;
    }

    rac_result_t get_summary(rac_benchmark_summary_t* out) {
        if (out == nullptr) {
            return RAC_ERROR_NULL_POINTER;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        std::memset(out, 0, sizeof(rac_benchmark_summary_t));

        if (count_ == 0) {
            return RAC_ERROR_INVALID_STATE;
        }

        out->count = count_;

        // TTFT stats
        if (!ttft_values_.empty()) {
            auto sorted = ttft_values_;
            std::sort(sorted.begin(), sorted.end());
            out->ttft_p50_ms = percentile(sorted, 50);
            out->ttft_p95_ms = percentile(sorted, 95);
            out->ttft_p99_ms = percentile(sorted, 99);
            out->ttft_min_ms = sorted.front();
            out->ttft_max_ms = sorted.back();
            out->ttft_mean_ms = mean(sorted);
            out->ttft_stddev_ms = stddev(sorted, out->ttft_mean_ms);
        }

        // Prefill stats
        if (!prefill_values_.empty()) {
            auto sorted = prefill_values_;
            std::sort(sorted.begin(), sorted.end());
            out->prefill_p50_ms = percentile(sorted, 50);
            out->prefill_p95_ms = percentile(sorted, 95);
            out->prefill_p99_ms = percentile(sorted, 99);
        }

        // Decode TPS stats
        if (!decode_tps_values_.empty()) {
            auto sorted = decode_tps_values_;
            std::sort(sorted.begin(), sorted.end());
            out->decode_tps_p50 = percentile(sorted, 50);
            out->decode_tps_p95 = percentile(sorted, 95);
            out->decode_tps_p99 = percentile(sorted, 99);
        }

        // E2E stats + outlier detection
        if (!e2e_values_.empty()) {
            auto sorted = e2e_values_;
            std::sort(sorted.begin(), sorted.end());
            out->e2e_p50_ms = percentile(sorted, 50);
            out->e2e_p95_ms = percentile(sorted, 95);
            out->e2e_p99_ms = percentile(sorted, 99);

            // Outlier detection: count observations > mean + 2*stddev
            double e2e_mean = mean(sorted);
            double e2e_sd = stddev(sorted, e2e_mean);
            double threshold = e2e_mean + 2.0 * e2e_sd;
            int32_t outliers = 0;
            for (double val : e2e_values_) {
                if (val > threshold) {
                    outliers++;
                }
            }
            out->outlier_count = outliers;
        }

        return RAC_SUCCESS;
    }

   private:
    /**
     * Nearest-rank percentile calculation.
     * Assumes sorted is non-empty and sorted in ascending order.
     */
    static double percentile(const std::vector<double>& sorted, int p) {
        size_t n = sorted.size();
        if (n == 1) {
            return sorted[0];
        }
        size_t rank = static_cast<size_t>(std::ceil(static_cast<double>(p) / 100.0 * n));
        if (rank == 0) {
            rank = 1;
        }
        if (rank > n) {
            rank = n;
        }
        return sorted[rank - 1];
    }

    static double mean(const std::vector<double>& values) {
        double sum = 0.0;
        for (double v : values) {
            sum += v;
        }
        return sum / static_cast<double>(values.size());
    }

    static double stddev(const std::vector<double>& values, double mean_val) {
        if (values.size() <= 1) {
            return 0.0;
        }
        double sum_sq = 0.0;
        for (double v : values) {
            double diff = v - mean_val;
            sum_sq += diff * diff;
        }
        return std::sqrt(sum_sq / static_cast<double>(values.size()));
    }

    mutable std::mutex mutex_;
    std::vector<double> ttft_values_;
    std::vector<double> prefill_values_;
    std::vector<double> decode_tps_values_;
    std::vector<double> e2e_values_;
    int32_t count_ = 0;
};

}  // namespace

extern "C" {

rac_result_t rac_benchmark_stats_create(rac_benchmark_stats_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* collector = new (std::nothrow) BenchmarkStatsCollector();
    if (collector == nullptr) {
        return RAC_ERROR_INITIALIZATION_FAILED;
    }

    *out_handle = static_cast<rac_benchmark_stats_handle_t>(collector);
    return RAC_SUCCESS;
}

void rac_benchmark_stats_destroy(rac_benchmark_stats_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    delete static_cast<BenchmarkStatsCollector*>(handle);
}

void rac_benchmark_stats_record(rac_benchmark_stats_handle_t handle,
                                 const rac_benchmark_timing_t* timing) {
    if (handle == nullptr || timing == nullptr) {
        return;
    }
    static_cast<BenchmarkStatsCollector*>(handle)->record(timing);
}

void rac_benchmark_stats_reset(rac_benchmark_stats_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    static_cast<BenchmarkStatsCollector*>(handle)->reset();
}

int32_t rac_benchmark_stats_count(rac_benchmark_stats_handle_t handle) {
    if (handle == nullptr) {
        return 0;
    }
    return static_cast<BenchmarkStatsCollector*>(handle)->count();
}

rac_result_t rac_benchmark_stats_get_summary(rac_benchmark_stats_handle_t handle,
                                              rac_benchmark_summary_t* out_summary) {
    if (handle == nullptr || out_summary == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    return static_cast<BenchmarkStatsCollector*>(handle)->get_summary(out_summary);
}

char* rac_benchmark_stats_summary_to_json(const rac_benchmark_summary_t* summary) {
    if (summary == nullptr) {
        return nullptr;
    }

    std::string json;
    json.reserve(1024);

    char buf[64];

    json += "{";
    json += "\"count\":" + std::to_string(summary->count) + ",";

    // TTFT
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_p50_ms);
    json += "\"ttft_p50_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_p95_ms);
    json += "\"ttft_p95_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_p99_ms);
    json += "\"ttft_p99_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_min_ms);
    json += "\"ttft_min_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_max_ms);
    json += "\"ttft_max_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_mean_ms);
    json += "\"ttft_mean_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->ttft_stddev_ms);
    json += "\"ttft_stddev_ms\":" + std::string(buf) + ",";

    // Prefill
    snprintf(buf, sizeof(buf), "%.2f", summary->prefill_p50_ms);
    json += "\"prefill_p50_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->prefill_p95_ms);
    json += "\"prefill_p95_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->prefill_p99_ms);
    json += "\"prefill_p99_ms\":" + std::string(buf) + ",";

    // Decode TPS
    snprintf(buf, sizeof(buf), "%.2f", summary->decode_tps_p50);
    json += "\"decode_tps_p50\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->decode_tps_p95);
    json += "\"decode_tps_p95\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->decode_tps_p99);
    json += "\"decode_tps_p99\":" + std::string(buf) + ",";

    // E2E
    snprintf(buf, sizeof(buf), "%.2f", summary->e2e_p50_ms);
    json += "\"e2e_p50_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->e2e_p95_ms);
    json += "\"e2e_p95_ms\":" + std::string(buf) + ",";
    snprintf(buf, sizeof(buf), "%.2f", summary->e2e_p99_ms);
    json += "\"e2e_p99_ms\":" + std::string(buf) + ",";

    // Outliers
    json += "\"outlier_count\":" + std::to_string(summary->outlier_count);

    json += "}";

    char* result = static_cast<char*>(malloc(json.size() + 1));
    if (result != nullptr) {
        memcpy(result, json.c_str(), json.size() + 1);
    }
    return result;
}

}  // extern "C"
