/**
 * @file bench_metrics.h
 * @brief Pure consume-only mapping from commons result protos → bench fields.
 *
 * No tok/s, decode_ms, RTF, or chars/s reconstruction. Missing commons values
 * stay 0 / absent. Harness wall clocks (load/warmup/measured e2e) are separate.
 */

#ifndef RCLI_COMMANDS_BENCH_METRICS_H
#define RCLI_COMMANDS_BENCH_METRICS_H

#include "llm_options.pb.h"
#include "vlm_options.pb.h"

#include <cstdint>

namespace rcli::commands::bench_metrics {

struct LlmVlmMetrics {
    double end_to_end_ms = 0.0;
    double tokens_per_second = 0.0;
    double prompt_eval_ms = 0.0;
    double decode_ms = 0.0;
    int32_t output_tokens = 0;
};

/** Prefill from prompt_eval_time_ms, else TokenUsage.prefill_ms — never TTFT.
 */
inline double measured_prefill_ms(int64_t prompt_eval_time_ms, int64_t usage_prefill_ms) {
    if (prompt_eval_time_ms > 0) {
        return static_cast<double>(prompt_eval_time_ms);
    }
    if (usage_prefill_ms > 0) {
        return static_cast<double>(usage_prefill_ms);
    }
    return 0.0;
}

/**
 * Map LLMGenerationResult → LLM bench metrics.
 * @param measured_e2e_ms harness stopwatch; used only when generation_time_ms
 * is 0.
 * @return false when output_tokens <= 0 (not a successful LLM trial).
 */
inline bool fill_llm(const runanywhere::v1::LLMGenerationResult& r, double measured_e2e_ms,
                     LlmVlmMetrics* out) {
    const int32_t out_tokens = r.usage().output_tokens();
    if (out_tokens <= 0) {
        return false;
    }
    out->output_tokens = out_tokens;
    out->end_to_end_ms = r.generation_time_ms() > 0.0 ? r.generation_time_ms() : measured_e2e_ms;
    out->tokens_per_second = r.usage().decode_tokens_per_second();
    out->decode_ms = r.decode_time_ms() > 0 ? static_cast<double>(r.decode_time_ms()) : 0.0;
    out->prompt_eval_ms = measured_prefill_ms(r.prompt_eval_time_ms(), r.usage().prefill_ms());
    return true;
}

/**
 * Map VLMResult → VLM bench metrics.
 * No decode window on VLMResult — decode_ms stays 0.
 */
inline bool fill_vlm(const runanywhere::v1::VLMResult& r, double measured_e2e_ms,
                     LlmVlmMetrics* out) {
    const int32_t out_tokens = r.usage().output_tokens();
    if (out_tokens <= 0) {
        return false;
    }
    out->output_tokens = out_tokens;
    out->end_to_end_ms =
        r.total_time_ms() > 0 ? static_cast<double>(r.total_time_ms()) : measured_e2e_ms;
    out->tokens_per_second = r.usage().decode_tokens_per_second();
    out->prompt_eval_ms = measured_prefill_ms(/*prompt_eval_time_ms=*/0, r.usage().prefill_ms());
    out->decode_ms = 0.0;
    return true;
}

}  // namespace rcli::commands::bench_metrics

#endif  // RCLI_COMMANDS_BENCH_METRICS_H
