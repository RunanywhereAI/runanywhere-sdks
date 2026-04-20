// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "llm_metrics.h"

#include <gtest/gtest.h>

#include <chrono>
#include <thread>

namespace {

using ra::core::util::StreamingMetrics;

TEST(LlmMetrics, NotStartedReturnsZeros) {
    StreamingMetrics m;
    const auto s = m.snapshot();
    EXPECT_EQ(s.output_tokens, 0);
    EXPECT_EQ(s.ttft_ms, 0.0);
    EXPECT_EQ(s.tokens_per_second, 0.0);
}

TEST(LlmMetrics, RecordsTTFTAndTokenRate) {
    StreamingMetrics m;
    m.record_started(/*prompt_tokens=*/12);
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    m.record_token();  // first token
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    m.record_token();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    m.record_token();

    const auto s = m.snapshot();
    EXPECT_GE(s.ttft_ms, 25.0);                // ~30 ms, some scheduling slack
    EXPECT_EQ(s.input_tokens, 12);
    EXPECT_EQ(s.output_tokens, 3);
    EXPECT_EQ(s.response_tokens, 3);
    EXPECT_EQ(s.thinking_tokens, 0);
    EXPECT_GT(s.tokens_per_second, 0.0);       // 2 tokens across ~40 ms
}

TEST(LlmMetrics, SeparatesThinkingFromResponseTokens) {
    StreamingMetrics m;
    m.record_started();
    m.record_token(/*is_thought=*/true);
    m.record_token(/*is_thought=*/true);
    m.record_token();
    m.record_token();

    const auto s = m.snapshot();
    EXPECT_EQ(s.thinking_tokens, 2);
    EXPECT_EQ(s.response_tokens, 2);
    EXPECT_EQ(s.output_tokens, 4);
}

}  // namespace
