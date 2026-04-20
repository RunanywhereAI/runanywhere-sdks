// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// LLM streaming metrics — TTFT (time-to-first-token) + tokens/sec.
// Ports the capability from
// `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_metrics.h`.
//
// Frontends attach one collector per generation: record_started() on
// request, record_token() for each streamed token, snapshot() when the
// stream terminates. The resulting numbers drive SDK analytics + the
// on-screen "57 t/s" indicator most sample apps display.

#ifndef RA_CORE_LLM_METRICS_H
#define RA_CORE_LLM_METRICS_H

#include <chrono>
#include <cstdint>
#include <optional>

namespace ra::core::util {

struct StreamingSnapshot {
    double ttft_ms           = 0.0;  // time until first token
    double total_latency_ms  = 0.0;  // request → last token
    double tokens_per_second = 0.0;  // excludes TTFT ramp
    std::int32_t input_tokens  = 0;
    std::int32_t output_tokens = 0;
    std::int32_t thinking_tokens = 0;
    std::int32_t response_tokens = 0;
};

class StreamingMetrics {
public:
    void record_started(std::int32_t prompt_tokens = 0);

    // Call once for every emitted token. `is_thought` marks chain-of-
    // thought tokens (qwen3 / deepseek-r1) so frontends can split the
    // thinking t/s from the response t/s.
    void record_token(bool is_thought = false);

    // Optional override when the caller already knows total output tokens
    // (non-streaming path). Doesn't affect TTFT.
    void set_output_tokens(std::int32_t n) { output_tokens_ = n; }

    // Collect a snapshot. Idempotent — can be called multiple times.
    StreamingSnapshot snapshot() const;

    // Raw timestamps for callers that want to compute differently.
    std::int64_t started_ms() const { return started_ms_; }
    bool         has_first_token() const { return first_token_ms_.has_value(); }

private:
    std::int64_t now_ms() const;

    std::int64_t                started_ms_  = 0;
    std::optional<std::int64_t> first_token_ms_;
    std::int64_t                last_token_ms_ = 0;
    std::int32_t                input_tokens_  = 0;
    std::int32_t                output_tokens_ = 0;
    std::int32_t                thinking_tokens_ = 0;
    std::int32_t                response_tokens_ = 0;
};

}  // namespace ra::core::util

#endif  // RA_CORE_LLM_METRICS_H
