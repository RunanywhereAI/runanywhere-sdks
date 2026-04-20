// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "llm_metrics.h"

namespace ra::core::util {

std::int64_t StreamingMetrics::now_ms() const {
    using namespace std::chrono;
    return duration_cast<milliseconds>(
               steady_clock::now().time_since_epoch())
        .count();
}

void StreamingMetrics::record_started(std::int32_t prompt_tokens) {
    started_ms_     = now_ms();
    first_token_ms_.reset();
    last_token_ms_  = 0;
    input_tokens_   = prompt_tokens;
    output_tokens_  = 0;
    thinking_tokens_ = 0;
    response_tokens_ = 0;
}

void StreamingMetrics::record_token(bool is_thought) {
    const auto ms = now_ms();
    if (!first_token_ms_.has_value()) first_token_ms_ = ms;
    last_token_ms_ = ms;
    ++output_tokens_;
    if (is_thought) ++thinking_tokens_;
    else            ++response_tokens_;
}

StreamingSnapshot StreamingMetrics::snapshot() const {
    StreamingSnapshot s;
    s.input_tokens    = input_tokens_;
    s.output_tokens   = output_tokens_;
    s.thinking_tokens = thinking_tokens_;
    s.response_tokens = response_tokens_;

    if (started_ms_ == 0) return s;

    if (first_token_ms_.has_value()) {
        s.ttft_ms = static_cast<double>(*first_token_ms_ - started_ms_);
    }
    if (last_token_ms_ > 0) {
        s.total_latency_ms = static_cast<double>(last_token_ms_ - started_ms_);
        if (first_token_ms_.has_value() && last_token_ms_ > *first_token_ms_
            && output_tokens_ > 1) {
            const double stream_ms = static_cast<double>(last_token_ms_
                                                          - *first_token_ms_);
            s.tokens_per_second = static_cast<double>(output_tokens_ - 1)
                                  * 1000.0 / stream_ms;
        }
    }
    return s;
}

}  // namespace ra::core::util
