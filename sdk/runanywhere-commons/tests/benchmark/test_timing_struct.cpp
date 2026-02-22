/**
 * @file test_timing_struct.cpp
 * @brief Tests for rac_benchmark_timing_t struct and initialization
 */

#include <gtest/gtest.h>

#include <cstring>

#include "rac/core/rac_benchmark.h"

// =============================================================================
// INITIALIZATION
// =============================================================================

TEST(TimingStruct, InitZeroesAllFields) {
    rac_benchmark_timing_t timing;

    // Fill with non-zero to ensure init actually clears
    std::memset(&timing, 0xFF, sizeof(timing));

    rac_benchmark_timing_init(&timing);

    EXPECT_EQ(timing.t0_request_start_ms, 0);
    EXPECT_EQ(timing.t2_prefill_start_ms, 0);
    EXPECT_EQ(timing.t3_prefill_end_ms, 0);
    EXPECT_EQ(timing.t4_first_token_ms, 0);
    EXPECT_EQ(timing.t5_last_token_ms, 0);
    EXPECT_EQ(timing.t6_request_end_ms, 0);
    EXPECT_EQ(timing.prompt_tokens, 0);
    EXPECT_EQ(timing.output_tokens, 0);
    EXPECT_EQ(timing.status, 0);
    EXPECT_EQ(timing.error_code, 0);
}

TEST(TimingStruct, InitNullPointerNoCrash) {
    // Should not crash
    rac_benchmark_timing_init(nullptr);
}

// =============================================================================
// STATUS CODES
// =============================================================================

TEST(TimingStruct, StatusCodeValues) {
    EXPECT_EQ(RAC_BENCHMARK_STATUS_SUCCESS, 0);
    EXPECT_EQ(RAC_BENCHMARK_STATUS_ERROR, 1);
    EXPECT_EQ(RAC_BENCHMARK_STATUS_TIMEOUT, 2);
    EXPECT_EQ(RAC_BENCHMARK_STATUS_CANCELLED, 3);
}

// =============================================================================
// FIELD ORDERING AND USAGE PATTERNS
// =============================================================================

TEST(TimingStruct, TimestampOrdering) {
    rac_benchmark_timing_t timing;
    rac_benchmark_timing_init(&timing);

    // Simulate a successful inference with ordered timestamps
    timing.t0_request_start_ms = 100;
    timing.t2_prefill_start_ms = 110;
    timing.t3_prefill_end_ms = 150;
    timing.t4_first_token_ms = 155;
    timing.t5_last_token_ms = 500;
    timing.t6_request_end_ms = 510;

    EXPECT_LE(timing.t0_request_start_ms, timing.t2_prefill_start_ms);
    EXPECT_LE(timing.t2_prefill_start_ms, timing.t3_prefill_end_ms);
    EXPECT_LE(timing.t3_prefill_end_ms, timing.t4_first_token_ms);
    EXPECT_LE(timing.t4_first_token_ms, timing.t5_last_token_ms);
    EXPECT_LE(timing.t5_last_token_ms, timing.t6_request_end_ms);
}

TEST(TimingStruct, ErrorPathTimestamps) {
    rac_benchmark_timing_t timing;
    rac_benchmark_timing_init(&timing);

    // Simulate error: only t0 and t6 captured
    timing.t0_request_start_ms = 100;
    timing.t6_request_end_ms = 105;
    timing.status = RAC_BENCHMARK_STATUS_ERROR;
    timing.error_code = -130;  // Some error code

    // Middle timestamps should remain 0
    EXPECT_EQ(timing.t2_prefill_start_ms, 0);
    EXPECT_EQ(timing.t3_prefill_end_ms, 0);
    EXPECT_EQ(timing.t4_first_token_ms, 0);
    EXPECT_EQ(timing.t5_last_token_ms, 0);

    // But t0, t6, status, error_code should be set
    EXPECT_GT(timing.t0_request_start_ms, 0);
    EXPECT_GT(timing.t6_request_end_ms, 0);
    EXPECT_EQ(timing.status, RAC_BENCHMARK_STATUS_ERROR);
    EXPECT_NE(timing.error_code, RAC_SUCCESS);
}

TEST(TimingStruct, DerivedMetrics) {
    rac_benchmark_timing_t timing;
    rac_benchmark_timing_init(&timing);

    timing.t0_request_start_ms = 1000;
    timing.t2_prefill_start_ms = 1010;
    timing.t3_prefill_end_ms = 1060;
    timing.t4_first_token_ms = 1065;
    timing.t5_last_token_ms = 2065;
    timing.t6_request_end_ms = 2070;
    timing.prompt_tokens = 50;
    timing.output_tokens = 100;

    // TTFT: t4 - t0 = 65ms
    EXPECT_EQ(timing.t4_first_token_ms - timing.t0_request_start_ms, 65);

    // Prefill: t3 - t2 = 50ms
    EXPECT_EQ(timing.t3_prefill_end_ms - timing.t2_prefill_start_ms, 50);

    // Decode: t5 - t3 = 1005ms
    int64_t decode_ms = timing.t5_last_token_ms - timing.t3_prefill_end_ms;
    EXPECT_EQ(decode_ms, 1005);

    // Decode TPS: 100 tokens / 1.005s ≈ 99.50 tokens/s
    double tps = static_cast<double>(timing.output_tokens) / static_cast<double>(decode_ms) * 1000.0;
    EXPECT_NEAR(tps, 99.50, 0.1);

    // E2E: t6 - t0 = 1070ms
    EXPECT_EQ(timing.t6_request_end_ms - timing.t0_request_start_ms, 1070);

    // Component overhead: E2E - decode - prefill
    int64_t overhead = (timing.t6_request_end_ms - timing.t0_request_start_ms) -
                       decode_ms -
                       (timing.t3_prefill_end_ms - timing.t2_prefill_start_ms);
    EXPECT_EQ(overhead, 15);  // 1070 - 1005 - 50 = 15ms
}
