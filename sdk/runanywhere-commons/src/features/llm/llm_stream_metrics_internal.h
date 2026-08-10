/**
 * @file llm_stream_metrics_internal.h
 * @brief Timing/throughput arithmetic for a streamed generation.
 *
 * Extracted from `llm_module.cpp` so the arithmetic can be unit-tested against
 * synthetic timings, because the figure it replaces was wrong by more than an
 * order of magnitude and nothing caught it.
 *
 * ## What was wrong, precisely
 *
 * The previous rate was `completion_tokens / (total_ms - ttft_ms)`, where
 * `ttft_ms` was the time to the first token that was *dispatched to the
 * consumer*. On a reasoning model with `include_in_output = false`, thought
 * deltas are accumulated but not dispatched, so "first dispatched token" is the
 * first token AFTER `</think>` — seconds into the request. That put nearly the
 * whole generation inside the TTFT term and left a sliver as the denominator,
 * while the numerator still counted every reasoning token. Measured on this
 * stack it reported **612-1594 tok/s against an engine doing 57**, and it made
 * a `min_decode_toks` floor unfalsifiable: a floor that cannot fail is not a
 * gate.
 *
 * Two independent defects, both fixed here:
 *   1. **TTFT moved when a display flag moved.** A latency metric that depends
 *      on whether the caller wants to *see* reasoning is not measuring the
 *      model. Timestamps are now taken where tokens are PRODUCED, before any
 *      visibility gate.
 *   2. **The window and the numerator disagreed.** `total - ttft` is not the
 *      decode window on a model whose first dispatched token is late. The
 *      window is now first-produced-token to last-produced-token, stated
 *      explicitly rather than inferred by subtraction.
 *
 * All timestamps arrive from commons (`now_ms()` at production), never
 * reconstructed from arrival times in a platform SDK — that would measure IPC
 * latency, not the model.
 */

#ifndef RAC_FEATURES_LLM_STREAM_METRICS_INTERNAL_H
#define RAC_FEATURES_LLM_STREAM_METRICS_INTERNAL_H

#include <algorithm>
#include <cstdint>

namespace rac::llm {

/** Raw observations collected during the stream. Every `*_ms` is an absolute
 *  `now_ms()` reading taken at the moment the event happened; 0 means "never
 *  observed". Token counts are ENGINE deltas, not post-split segments. */
struct StreamTokenTiming {
    int64_t started_ms = 0;
    /** First delta of any kind, taken before the reasoning-visibility gate. */
    int64_t first_token_ms = 0;
    /** First delta classified as CONTENT — i.e. after the reasoning boundary.
     *  Equals `first_token_ms` on a model that never reasons. */
    int64_t first_content_token_ms = 0;
    /** Last delta of any kind. */
    int64_t last_token_ms = 0;
    /** Terminal event time; the end of the ungameable wall clock. */
    int64_t completed_ms = 0;
    /** Engine deltas seen, reasoning and content together. */
    int32_t total_tokens = 0;
};

struct StreamTimingMetrics {
    /** Request start to terminal event. The only figure that cannot be gamed by
     *  redefining a window, so a throughput floor should be checkable against
     *  it. */
    int64_t wall_ms = 0;

    /** Start to the first delta of ANY kind. "The engine is alive." On a
     *  reasoning model this is NOT what the user waits for. */
    int64_t ttft_ms = 0;

    /** Start to the first CONTENT delta — what the user actually waits for,
     *  because everything before it is hidden reasoning. On maple this is
     *  seconds later than `ttft_ms`. Equal to `ttft_ms` when nothing reasoned. */
    int64_t time_to_first_content_token_ms = 0;

    /** Prefill / prompt-eval window: start to the first delta of any kind.
     *  Reported separately from decode because the engine measures them
     *  separately (QHexRT logs `PROMPT n tok seed X ms` apart from
     *  `DECODE n tok @ Y ms/tok`) and flattening them hides which one regressed. */
    int64_t prefill_ms = 0;

    /** Decode window: first produced delta to last produced delta. Stated, not
     *  derived by subtracting a TTFT that may mean something else. */
    int64_t decode_ms = 0;

    /** Tokens per second across the decode window, counting reasoning AND
     *  content — the accelerator decoded every one of them.
     *
     *  Numerator is `total_tokens - 1`, not `total_tokens`: the window opens
     *  when token 1 ARRIVES, so only tokens 2..N were produced inside it.
     *  Counting all N over N-1 intervals reads ~1/N high, and this number
     *  exists to be scrutinised. Token 1's cost is reported as `prefill_ms`. */
    double decode_tokens_per_second = 0.0;

    /** Content-only rate, over first-content-delta to last delta. Deliberately
     *  NOT named a decode rate: it excludes the reasoning the accelerator also
     *  decoded, so it is a user-perceived answer rate and nothing else. */
    double content_tokens_per_second = 0.0;

    /** The backend buffered the whole generation and then released the deltas,
     *  so the decode window is an artifact of the flush rather than of
     *  decoding. Reported explicitly because it is not recoverable from the
     *  other fields. */
    bool batch_buffered = false;
};

/** Rate helper: tokens over a millisecond window, 0 when the window is empty.
 *  A single-token response has a zero-length decode window and must not
 *  divide by zero. */
inline double tokens_per_second(double tokens, int64_t window_ms) {
    if (window_ms <= 0 || tokens <= 0.0) {
        return 0.0;
    }
    return tokens / (static_cast<double>(window_ms) / 1000.0);
}

inline StreamTimingMetrics compute_stream_timing(const StreamTokenTiming& t) {
    StreamTimingMetrics m;
    if (t.completed_ms > t.started_ms) {
        m.wall_ms = t.completed_ms - t.started_ms;
    }
    if (t.total_tokens <= 0 || t.first_token_ms <= 0) {
        return m;
    }

    m.ttft_ms = std::max<int64_t>(0, t.first_token_ms - t.started_ms);
    m.prefill_ms = m.ttft_ms;
    // A stream that never left reasoning has no content token; the honest
    // answer is "no content was ever delivered", not a silent fallback to the
    // any-kind figure.
    m.time_to_first_content_token_ms =
        t.first_content_token_ms > 0 ? std::max<int64_t>(0, t.first_content_token_ms - t.started_ms)
                                     : 0;
    m.decode_ms = t.last_token_ms > t.first_token_ms ? (t.last_token_ms - t.first_token_ms) : 0;

    // A backend that hands over every delta at once collapses the decode
    // window to near zero while having spent the whole wall clock decoding.
    // Rates taken over that window are meaningless, so fall back to wall clock,
    // which errs LOW — the safe direction for anything used as a floor.
    m.batch_buffered = m.decode_ms < std::max<int64_t>(50, m.wall_ms / 20);

    const double decode_numerator = static_cast<double>(t.total_tokens - 1);
    if (m.batch_buffered || m.decode_ms <= 0) {
        m.decode_tokens_per_second = tokens_per_second(static_cast<double>(t.total_tokens),
                                                       m.wall_ms);
    } else {
        m.decode_tokens_per_second = tokens_per_second(decode_numerator, m.decode_ms);
    }

    if (t.first_content_token_ms > 0 && t.last_token_ms > t.first_content_token_ms) {
        // Content deltas are not counted separately by the caller (the split is
        // apportioned by character ratio, matching the unary splitter), so this
        // rate is left to the caller to fill when it knows the content count.
        m.content_tokens_per_second = 0.0;
    }
    return m;
}

/** Adapter for the older handle-based stream path, which observes only
 *  (wall total, TTFT, token count) and has no per-delta timestamps. It gets the
 *  corrected numerator and the batch-buffered fallback, but not the per-channel
 *  figures — those need timing taken at production, which that path does not do.
 *  Present so both stream implementations share one definition of the rate
 *  rather than drifting, which is how the two disagreed before. */
inline StreamTimingMetrics compute_stream_timing_from_totals(int64_t total_ms, int64_t raw_ttft_ms,
                                                             int32_t completion_tokens) {
    StreamTokenTiming t;
    t.started_ms = 1;  // arbitrary non-zero epoch; only differences are read
    t.first_token_ms = t.started_ms + (raw_ttft_ms > 0 ? raw_ttft_ms : 0);
    t.last_token_ms = t.started_ms + total_ms;
    t.completed_ms = t.started_ms + total_ms;
    t.total_tokens = completion_tokens;
    return compute_stream_timing(t);
}

/** Fills `content_tokens_per_second` once the caller knows the content-side
 *  token count. Kept separate so `compute_stream_timing` stays a pure function
 *  of the timing observations. */
inline void set_content_rate(StreamTimingMetrics* m, const StreamTokenTiming& t,
                             int32_t content_tokens) {
    if (m == nullptr || content_tokens <= 0) {
        return;
    }
    const int64_t window = (t.first_content_token_ms > 0 && t.last_token_ms > t.first_content_token_ms)
                               ? (t.last_token_ms - t.first_content_token_ms)
                               : 0;
    // One content token spans no window; fall back to wall clock rather than
    // reporting an infinite rate.
    m->content_tokens_per_second =
        window > 0 ? tokens_per_second(static_cast<double>(content_tokens - 1), window)
                   : tokens_per_second(static_cast<double>(content_tokens), m->wall_ms);
}

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_STREAM_METRICS_INTERNAL_H
