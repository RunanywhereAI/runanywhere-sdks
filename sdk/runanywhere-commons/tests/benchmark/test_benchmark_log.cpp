/**
 * @file test_benchmark_log.cpp
 * @brief Tests for benchmark JSON/CSV serialization and logging
 */

#include <gtest/gtest.h>

#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_benchmark.h"
#include "rac/core/rac_benchmark_log.h"

namespace {

// Helper: create a populated timing struct for testing
rac_benchmark_timing_t make_test_timing() {
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
    timing.status = RAC_BENCHMARK_STATUS_SUCCESS;
    timing.error_code = 0;

    return timing;
}

}  // namespace

// =============================================================================
// JSON SERIALIZATION
// =============================================================================

TEST(BenchmarkLog, TimingToJsonContainsAllFields) {
    auto timing = make_test_timing();
    char* json = rac_benchmark_timing_to_json(&timing);

    ASSERT_NE(json, nullptr);

    std::string s(json);

    // Verify raw timing fields
    EXPECT_NE(s.find("\"t0_request_start_ms\":1000"), std::string::npos);
    EXPECT_NE(s.find("\"t2_prefill_start_ms\":1010"), std::string::npos);
    EXPECT_NE(s.find("\"t3_prefill_end_ms\":1060"), std::string::npos);
    EXPECT_NE(s.find("\"t4_first_token_ms\":1065"), std::string::npos);
    EXPECT_NE(s.find("\"t5_last_token_ms\":2065"), std::string::npos);
    EXPECT_NE(s.find("\"t6_request_end_ms\":2070"), std::string::npos);
    EXPECT_NE(s.find("\"prompt_tokens\":50"), std::string::npos);
    EXPECT_NE(s.find("\"output_tokens\":100"), std::string::npos);
    EXPECT_NE(s.find("\"status\":0"), std::string::npos);
    EXPECT_NE(s.find("\"error_code\":0"), std::string::npos);

    // Verify derived metrics exist
    EXPECT_NE(s.find("\"ttft_ms\":"), std::string::npos);
    EXPECT_NE(s.find("\"prefill_ms\":"), std::string::npos);
    EXPECT_NE(s.find("\"decode_ms\":"), std::string::npos);
    EXPECT_NE(s.find("\"e2e_ms\":"), std::string::npos);
    EXPECT_NE(s.find("\"decode_tps\":"), std::string::npos);

    // Verify it's valid JSON (starts with { and ends with })
    EXPECT_EQ(s.front(), '{');
    EXPECT_EQ(s.back(), '}');

    free(json);
}

TEST(BenchmarkLog, TimingToJsonNullReturnsNull) {
    char* json = rac_benchmark_timing_to_json(nullptr);
    EXPECT_EQ(json, nullptr);
}

// =============================================================================
// CSV SERIALIZATION
// =============================================================================

TEST(BenchmarkLog, TimingToCsvHeader) {
    char* header = rac_benchmark_timing_to_csv(nullptr, RAC_TRUE);

    ASSERT_NE(header, nullptr);

    std::string s(header);
    EXPECT_NE(s.find("t0_request_start_ms"), std::string::npos);
    EXPECT_NE(s.find("ttft_ms"), std::string::npos);
    EXPECT_NE(s.find("decode_tps"), std::string::npos);

    free(header);
}

TEST(BenchmarkLog, TimingToCsvRow) {
    auto timing = make_test_timing();
    char* row = rac_benchmark_timing_to_csv(&timing, RAC_FALSE);

    ASSERT_NE(row, nullptr);

    std::string s(row);
    // Should contain the t0 value
    EXPECT_NE(s.find("1000"), std::string::npos);
    // Should contain commas separating fields
    size_t comma_count = 0;
    for (char c : s) {
        if (c == ',') comma_count++;
    }
    // CSV header has 14 commas (15 fields), data row should match
    EXPECT_EQ(comma_count, 14u);

    free(row);
}

TEST(BenchmarkLog, TimingToCsvNullDataReturnsNull) {
    char* row = rac_benchmark_timing_to_csv(nullptr, RAC_FALSE);
    EXPECT_EQ(row, nullptr);
}

// =============================================================================
// LOGGING
// =============================================================================

TEST(BenchmarkLog, TimingLogNoCrash) {
    auto timing = make_test_timing();

    // Should not crash even without platform adapter
    rac_benchmark_timing_log(&timing, "test_run");
    rac_benchmark_timing_log(&timing, nullptr);
    rac_benchmark_timing_log(nullptr, "test_run");
}
