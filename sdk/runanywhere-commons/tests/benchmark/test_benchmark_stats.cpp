/**
 * @file test_benchmark_stats.cpp
 * @brief Tests for benchmark statistical analysis
 */

#include <gtest/gtest.h>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_benchmark_stats.h"

namespace {

// Helper: create a timing with known derived metric values
rac_benchmark_timing_t make_timing(int64_t ttft_ms, int64_t prefill_ms, double decode_tps_target,
                                    int32_t output_tokens, int64_t e2e_ms) {
    rac_benchmark_timing_t timing;
    rac_benchmark_timing_init(&timing);

    timing.t0_request_start_ms = 1000;
    timing.t2_prefill_start_ms = 1010;
    timing.t3_prefill_end_ms = 1010 + prefill_ms;
    timing.t4_first_token_ms = 1000 + ttft_ms;
    timing.output_tokens = output_tokens;

    // Compute t5 from target decode_tps: t5 - t3 = output_tokens / decode_tps * 1000
    if (decode_tps_target > 0.0 && output_tokens > 0) {
        int64_t decode_ms =
            static_cast<int64_t>(static_cast<double>(output_tokens) / decode_tps_target * 1000.0);
        timing.t5_last_token_ms = timing.t3_prefill_end_ms + decode_ms;
    }

    timing.t6_request_end_ms = 1000 + e2e_ms;
    timing.prompt_tokens = 50;
    timing.status = RAC_BENCHMARK_STATUS_SUCCESS;
    timing.error_code = 0;

    return timing;
}

}  // namespace

// =============================================================================
// CREATE / DESTROY
// =============================================================================

TEST(BenchmarkStats, CreateDestroy) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_result_t result = rac_benchmark_stats_create(&handle);

    EXPECT_EQ(result, RAC_SUCCESS);
    EXPECT_NE(handle, nullptr);

    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, CreateNullReturnsError) {
    rac_result_t result = rac_benchmark_stats_create(nullptr);
    EXPECT_NE(result, RAC_SUCCESS);
}

TEST(BenchmarkStats, DestroyNullNoCrash) {
    rac_benchmark_stats_destroy(nullptr);
}

// =============================================================================
// RECORD AND COUNT
// =============================================================================

TEST(BenchmarkStats, RecordAndCount) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    for (int i = 0; i < 10; ++i) {
        auto timing = make_timing(65, 50, 100.0, 100, 1070);
        rac_benchmark_stats_record(handle, &timing);
    }

    EXPECT_EQ(rac_benchmark_stats_count(handle), 10);

    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, OnlySuccessfulObservationsRecorded) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    auto timing = make_timing(65, 50, 100.0, 100, 1070);
    rac_benchmark_stats_record(handle, &timing);

    // Error observation should be skipped
    auto error_timing = timing;
    error_timing.status = RAC_BENCHMARK_STATUS_ERROR;
    rac_benchmark_stats_record(handle, &error_timing);

    EXPECT_EQ(rac_benchmark_stats_count(handle), 1);

    rac_benchmark_stats_destroy(handle);
}

// =============================================================================
// RESET
// =============================================================================

TEST(BenchmarkStats, Reset) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    auto timing = make_timing(65, 50, 100.0, 100, 1070);
    rac_benchmark_stats_record(handle, &timing);
    EXPECT_EQ(rac_benchmark_stats_count(handle), 1);

    rac_benchmark_stats_reset(handle);
    EXPECT_EQ(rac_benchmark_stats_count(handle), 0);

    rac_benchmark_stats_destroy(handle);
}

// =============================================================================
// SUMMARY
// =============================================================================

TEST(BenchmarkStats, EmptyDataReturnsError) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    rac_benchmark_summary_t summary;
    rac_result_t result = rac_benchmark_stats_get_summary(handle, &summary);
    EXPECT_NE(result, RAC_SUCCESS);

    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, SingleObservation) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    auto timing = make_timing(65, 50, 100.0, 100, 1070);
    rac_benchmark_stats_record(handle, &timing);

    rac_benchmark_summary_t summary;
    rac_result_t result = rac_benchmark_stats_get_summary(handle, &summary);
    EXPECT_EQ(result, RAC_SUCCESS);
    EXPECT_EQ(summary.count, 1);

    // For a single observation, P50=P95=P99=that value
    EXPECT_DOUBLE_EQ(summary.ttft_p50_ms, summary.ttft_p95_ms);
    EXPECT_DOUBLE_EQ(summary.ttft_p95_ms, summary.ttft_p99_ms);
    EXPECT_EQ(summary.ttft_p50_ms, 65.0);

    // Stddev should be 0 for a single observation
    EXPECT_DOUBLE_EQ(summary.ttft_stddev_ms, 0.0);

    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, PercentilesBasic) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    // Record 100 observations with TTFT values 1,2,3,...,100
    for (int i = 1; i <= 100; ++i) {
        auto timing = make_timing(i, 50, 100.0, 100, 100 + i);
        rac_benchmark_stats_record(handle, &timing);
    }

    rac_benchmark_summary_t summary;
    rac_result_t result = rac_benchmark_stats_get_summary(handle, &summary);
    EXPECT_EQ(result, RAC_SUCCESS);
    EXPECT_EQ(summary.count, 100);

    // P50 should be 50 (nearest rank: ceil(50/100 * 100) = 50th element = 50)
    EXPECT_DOUBLE_EQ(summary.ttft_p50_ms, 50.0);

    // P95 should be 95
    EXPECT_DOUBLE_EQ(summary.ttft_p95_ms, 95.0);

    // P99 should be 99
    EXPECT_DOUBLE_EQ(summary.ttft_p99_ms, 99.0);

    // Min and max
    EXPECT_DOUBLE_EQ(summary.ttft_min_ms, 1.0);
    EXPECT_DOUBLE_EQ(summary.ttft_max_ms, 100.0);

    // Mean should be 50.5
    EXPECT_NEAR(summary.ttft_mean_ms, 50.5, 0.01);

    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, OutlierDetection) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    // Record 99 normal observations (E2E = 100ms) + 1 extreme (E2E = 10000ms)
    for (int i = 0; i < 99; ++i) {
        auto timing = make_timing(10, 10, 100.0, 100, 100);
        rac_benchmark_stats_record(handle, &timing);
    }

    auto extreme = make_timing(10, 10, 100.0, 100, 10000);
    rac_benchmark_stats_record(handle, &extreme);

    rac_benchmark_summary_t summary;
    rac_result_t result = rac_benchmark_stats_get_summary(handle, &summary);
    EXPECT_EQ(result, RAC_SUCCESS);
    EXPECT_GE(summary.outlier_count, 1);

    rac_benchmark_stats_destroy(handle);
}

// =============================================================================
// JSON EXPORT
// =============================================================================

TEST(BenchmarkStats, SummaryToJson) {
    rac_benchmark_stats_handle_t handle = nullptr;
    rac_benchmark_stats_create(&handle);

    auto timing = make_timing(65, 50, 100.0, 100, 1070);
    rac_benchmark_stats_record(handle, &timing);

    rac_benchmark_summary_t summary;
    rac_benchmark_stats_get_summary(handle, &summary);

    char* json = rac_benchmark_stats_summary_to_json(&summary);
    ASSERT_NE(json, nullptr);

    std::string s(json);
    EXPECT_EQ(s.front(), '{');
    EXPECT_EQ(s.back(), '}');
    EXPECT_NE(s.find("\"count\":1"), std::string::npos);
    EXPECT_NE(s.find("\"ttft_p50_ms\":"), std::string::npos);
    EXPECT_NE(s.find("\"outlier_count\":"), std::string::npos);

    free(json);
    rac_benchmark_stats_destroy(handle);
}

TEST(BenchmarkStats, SummaryToJsonNullReturnsNull) {
    char* json = rac_benchmark_stats_summary_to_json(nullptr);
    EXPECT_EQ(json, nullptr);
}
