/**
 * @file llm_thinking_stream_internal.h
 * @brief Incremental reasoning/content splitter for streamed LLM output.
 *
 * The whole-text splitter (`rac_llm_thinking.cpp`) cannot serve a stream: it
 * needs the complete response, and a stream must classify each delta as it
 * arrives. This is the streaming twin.
 *
 * **How the two are kept in agreement.** Not by asserting that two independent
 * implementations happen to match — they did not, and the claim that a test
 * proved it was false. The streaming path's TERMINAL result is produced by
 * calling the whole-text splitter on the accumulated raw text
 * (`dispatch_terminal_once` in `llm_module.cpp`), so the final
 * `LLMGenerationResult` of a stream is byte-identical to the unary result for
 * the same generated text *by construction*. This type's job is narrower and
 * cannot be done by the whole-text splitter: deciding, per delta, which channel
 * the consumer sees the text on while the text is still arriving.
 *
 * The two therefore agree region for region, and differ in exactly one
 * documented way: the whole-text splitter trims each region and joins multiple
 * answer regions with `'\n'` (Swift `ThinkingContentParser` parity), while the
 * live channel delivers the model's own spacing byte for byte.
 * `test_llm_thinking.cpp::test_stream_and_unary_agree` asserts both halves of
 * that statement over a table of shapes.
 *
 * Three properties are the reason this is a separate, dependency-free type
 * rather than a lambda inside `llm_module.cpp`:
 *
 *  1. **A delimiter can straddle a delta.** Engines emit whatever the tokenizer
 *     produced, so `</think>` routinely arrives as `</thi` + `nk>`. A per-delta
 *     `find()` misses it and the reasoning leaks into the answer only sometimes
 *     — which reads as a flaky model, and is worse than failing every time. Any
 *     tail that could still become a delimiter is held back until the next delta
 *     resolves it, and `flush()` releases it at end of stream so no text is ever
 *     lost.
 *
 *  2. **The opening tag may never be generated at all.** A reasoning chat
 *     template may prefill it into the PROMPT — maple-preview's manifest sets
 *     `gen_prefill: "<think>\n"` — so generated text is reasoning body, closing
 *     tag, answer, with no opening tag anywhere. A closing tag with no opening
 *     tag before it therefore closes a reasoning region that began before the
 *     first token. Reading it as "no reasoning here" is what echoed a bare
 *     `</think>` into the answer.
 *
 *  3. **That boundary is discovered late, and the late discovery cannot be
 *     applied to a callback that already fired.** Two ways to survive that, and
 *     which one is correct depends on what the caller knows:
 *
 *     - **Nothing is known about the model** — no reasoning pattern declared,
 *       so the text is overwhelmingly likely to be a plain answer. Deltas go out
 *       optimistically as CONTENT and a closing tag carries
 *       `reclassify_prior_content_as_reasoning`, which repairs the accumulators
 *       but not the already-dispatched deltas. Holding every model's whole
 *       answer to end of stream to cover a case with no evidence for it would
 *       trade streaming itself for a rare cosmetic fault.
 *
 *     - **The model declares a reasoning pattern** — then a prefilled opening
 *       tag is a live possibility on this very stream, and `set_hold_ambiguous_
 *       prefix(true)` makes the splitter WITHHOLD text until the ambiguity is
 *       settled rather than guess. The hold ends at the first delimiter (a
 *       closing tag proves prefilled reasoning, an opening tag proves the text
 *       before it was answer) or at end of stream. Nothing is ever delivered on
 *       the wrong channel, and no correction is needed because nothing was
 *       corrected-into-existence.
 *
 *     The hold is deliberately NOT the same thing as asserting the stream begins
 *     inside reasoning (see `start_inside_reasoning`): a wrong assertion routes
 *     an entire answer to the reasoning channel, where `emit_thoughts == false`
 *     discards it and the caller receives nothing. A wrong hold costs latency
 *     and nothing else.
 *
 * Header-only and free of protobuf / `rac_*` dependencies so the unit test
 * compiles it directly.
 */

#ifndef RAC_FEATURES_LLM_THINKING_STREAM_INTERNAL_H
#define RAC_FEATURES_LLM_THINKING_STREAM_INTERNAL_H

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rac::llm {

/** One reasoning delimiter pair, e.g. `<think>` / `</think>`. */
struct ThinkingTagPair {
    std::string open;
    std::string close;
};

/** The two output channels. Never merged — the whole point is that a consumer
 *  reading only CONTENT never sees reasoning text. */
enum class ThinkingChannel { kContent, kReasoning };

struct ThinkingStreamSegment {
    std::string text;
    ThinkingChannel channel = ThinkingChannel::kContent;

    /** Set on the segment that closes a reasoning region whose opening tag was
     *  never generated (property 2 above). Everything already accepted as
     *  CONTENT preceded that boundary and is reasoning: move it to the
     *  reasoning channel BEFORE appending this segment. Set at most once per
     *  stream — a later stray closing tag is swallowed without touching an
     *  answer that has legitimately begun.
     *
     *  Never set while `set_hold_ambiguous_prefix(true)` is in force: the hold
     *  resolves the same ambiguity before anything reaches the consumer, so
     *  there is nothing to reclassify. */
    bool reclassify_prior_content_as_reasoning = false;
};

/** The delimiters commons recognizes with no model-specific configuration. */
inline std::vector<ThinkingTagPair> default_thinking_tag_pairs() {
    return {{"<think>", "</think>"}, {"<thinking>", "</thinking>"}};
}

class ThinkingStreamSplitter {
public:
    /** Ceiling on withheld text. Not a tuning knob and not a latency policy: the
     *  hold normally ends at the model's own closing tag, which arrives after a
     *  reasoning block, and no reasoning block observed on device comes close to
     *  this. It exists so a pathological stream cannot buffer without bound;
     *  past it the splitter falls back to the optimistic-CONTENT rule above. */
    static constexpr size_t kAmbiguousHoldLimitBytes = 64u * 1024u;

    ThinkingStreamSplitter() : pairs_(default_thinking_tag_pairs()) {}

    /** Replaces the recognized delimiters. A model-declared pair is prepended
     *  by the caller; the built-ins stay so a model that ignores its own
     *  declared pattern still splits. */
    void set_pairs(std::vector<ThinkingTagPair> pairs) {
        // A half-empty pair would make `find()` match at offset 0 forever, so a
        // malformed model pattern is dropped rather than trusted.
        pairs.erase(std::remove_if(pairs.begin(), pairs.end(),
                                   [](const ThinkingTagPair& p) {
                                       return p.open.empty() || p.close.empty();
                                   }),
                    pairs.end());
        if (!pairs.empty()) {
            pairs_ = std::move(pairs);
        }
    }

    /** Withhold answer-channel text until the prefilled-opening-tag ambiguity is
     *  settled, instead of dispatching it optimistically and repairing the
     *  accumulators afterwards. Correct for any model that MIGHT prefill — i.e.
     *  any model that declares a reasoning pattern with thinking left enabled —
     *  because the cost is asymmetric: when the model does reason the answer is
     *  not delayed at all (the hold ends at `</think>`, and the reasoning it
     *  covered was never going to be shown), and when it does not the answer is
     *  merely delivered late rather than delivered on the wrong channel.
     *
     *  @see kAmbiguousHoldLimitBytes for the backstop. */
    void set_hold_ambiguous_prefix(bool hold) { holding_ = hold && !saw_delimiter_; }

    /** True while answer-channel text is being withheld. The caller uses this to
     *  remember WHEN the withheld run was produced: if it later resolves to
     *  answer text, time-to-first-content is the moment that text left the
     *  engine, not the moment the hold released it. */
    bool holding_ambiguous_prefix() const { return holding_; }

    /** Assert that the stream begins inside reasoning — correct ONLY when the
     *  caller knows the chat template prefilled the opening tag into the prompt.
     *
     *  Commons cannot know that today. `ModelInfo.supports_thinking` and the
     *  `ThinkingTagPattern` that `normalize_thinking_capability()` derives from
     *  it are a CAPABILITY ("this model can reason"), not a statement about the
     *  template; the prefill lives in the model bundle's own manifest
     *  (`gen_prefill`), which never reaches commons and has no field in
     *  `idl/thinking_tag_pattern.proto`. Calling this on the capability alone
     *  sends the entire output of a reasoning-capable model that answered
     *  WITHOUT reasoning to the reasoning channel, where `emit_thoughts == false`
     *  drops it: no deltas, empty answer. Production uses
     *  `set_hold_ambiguous_prefix()` instead, which survives being wrong.
     *
     *  Kept because it is the correct call the day a typed prefill signal
     *  exists, and because the unit test needs to pin the failure mode. */
    void start_inside_reasoning() {
        inside_reasoning_ = true;
        holding_ = false;
    }

    bool inside_reasoning() const { return inside_reasoning_; }

    /** Absorbs one delta, appending zero or more classified segments to @p out.
     *  @p out is appended to, not cleared, so a caller may batch. */
    void push(std::string_view chunk, std::vector<ThinkingStreamSegment>* out) {
        if (out == nullptr) {
            return;
        }
        pending_.append(chunk.data(), chunk.size());
        for (;;) {
            // Whitespace that hugged a delimiter belongs to the delimiter, not
            // to either channel: `gen_prefill: "<think>\n"` and the blank line
            // models put after `</think>` would otherwise open the answer with
            // a newline on every reasoning model.
            if (skip_leading_ws_) {
                const size_t visible = pending_.find_first_not_of(" \t\r\n\v\f");
                if (visible == std::string::npos) {
                    pending_.clear();
                    return;
                }
                pending_.erase(0, visible);
                skip_leading_ws_ = false;
            }

            size_t open_pos = std::string::npos;
            size_t close_pos = std::string::npos;
            const ThinkingTagPair* open_pair = find_earliest_open(&open_pos);
            const ThinkingTagPair* close_pair = find_earliest_close(&close_pos);

            if (inside_reasoning_) {
                // A second opening tag inside reasoning is swallowed rather
                // than surfaced; it is never a channel change.
                if (open_pair != nullptr &&
                    (close_pair == nullptr || open_pos < close_pos)) {
                    emit(out, pending_.substr(0, open_pos), ThinkingChannel::kReasoning, false);
                    pending_.erase(0, open_pos + open_pair->open.size());
                    skip_leading_ws_ = true;
                    continue;
                }
                if (close_pair != nullptr) {
                    emit(out, pending_.substr(0, close_pos), ThinkingChannel::kReasoning, false);
                    pending_.erase(0, close_pos + close_pair->close.size());
                    inside_reasoning_ = false;
                    saw_delimiter_ = true;
                    skip_leading_ws_ = true;
                    continue;
                }
                emit_holding_back_partial_tag(out, ThinkingChannel::kReasoning);
                return;
            }

            // Content mode. A closing tag reached before any opening tag is the
            // prefilled-open case: everything before it — including deltas
            // already handed to the consumer — was reasoning.
            if (close_pair != nullptr && (open_pair == nullptr || close_pos < open_pos)) {
                const bool first = !saw_delimiter_;
                if (first && holding_) {
                    // The hold paid off. Because nothing was dispatched as
                    // answer text there is nothing to reclassify — the consumer
                    // is told this is reasoning the first time it hears of it.
                    emit(out, take_hold(pending_.substr(0, close_pos)),
                         ThinkingChannel::kReasoning, false);
                } else {
                    emit(out, pending_.substr(0, close_pos),
                         first ? ThinkingChannel::kReasoning : ThinkingChannel::kContent, first);
                }
                pending_.erase(0, close_pos + close_pair->close.size());
                saw_delimiter_ = true;
                skip_leading_ws_ = true;
                continue;
            }
            if (open_pair != nullptr) {
                // An opening tag proves the text before it is answer text and
                // not a prefilled reasoning body, so the hold resolves the other
                // way: release it as CONTENT and start a real reasoning region.
                emit(out, take_hold(pending_.substr(0, open_pos)), ThinkingChannel::kContent,
                     false);
                pending_.erase(0, open_pos + open_pair->open.size());
                inside_reasoning_ = true;
                saw_delimiter_ = true;
                skip_leading_ws_ = true;
                continue;
            }
            emit_holding_back_partial_tag(out, ThinkingChannel::kContent);
            return;
        }
    }

    /** Releases the held tail at end of stream. Two things can be held: the
     *  partial-delimiter tail (property 1) and, when the hold is armed, the
     *  whole ambiguous prefix (property 3).
     *
     *  An opening tag that was never closed (the generation hit its token cap
     *  mid-reasoning) leaves the splitter inside reasoning, so the remainder
     *  lands in the reasoning channel and the answer is legitimately empty. An
     *  armed hold that reached end of stream without ever meeting a closing tag
     *  is the disproof of the prefill guess: the withheld text was the answer
     *  all along and is released as CONTENT. Either way the text is delivered,
     *  never dropped. */
    void flush(std::vector<ThinkingStreamSegment>* out) {
        if (out == nullptr || (pending_.empty() && held_.empty())) {
            return;
        }
        const ThinkingChannel channel =
            inside_reasoning_ ? ThinkingChannel::kReasoning : ThinkingChannel::kContent;
        emit(out, take_hold(pending_), channel, false);
        pending_.clear();
    }

private:
    /** Detaches the withheld prefix, disarms the hold, and returns it with
     *  @p tail appended — the single way held text ever leaves this object, so
     *  a release can never be half-applied. */
    std::string take_hold(std::string tail) {
        if (!holding_ && held_.empty()) {
            return tail;
        }
        holding_ = false;
        std::string text = std::move(held_);
        held_.clear();
        text += tail;
        return text;
    }

    void emit(std::vector<ThinkingStreamSegment>* out, std::string text, ThinkingChannel channel,
              bool reclassify) {
        // A reclassification must reach the consumer even when the segment that
        // carries it is empty (a stream whose first delta IS the closing tag).
        if (text.empty() && !reclassify) {
            return;
        }
        if (holding_ && channel == ThinkingChannel::kContent) {
            held_ += text;
            if (held_.size() <= kAmbiguousHoldLimitBytes) {
                return;
            }
            // Backstop reached: stop withholding and fall back to the
            // optimistic-CONTENT rule, retroactive correction included.
            text = take_hold(std::string());
        }
        ThinkingStreamSegment segment;
        segment.text = std::move(text);
        segment.channel = channel;
        segment.reclassify_prior_content_as_reasoning = reclassify;
        out->push_back(std::move(segment));
    }

    /** Emits everything except a trailing run that could still grow into a
     *  delimiter. On return only that held tail remains, so the caller is done
     *  until the next delta arrives. */
    void emit_holding_back_partial_tag(std::vector<ThinkingStreamSegment>* out,
                                       ThinkingChannel channel) {
        // Both directions are held in both modes: a `<think>` opening a nested
        // block and a `</think>` closing a prefilled one are equally able to
        // straddle a delta, and holding only one of them is how a split tag
        // leaks half of itself as text.
        size_t hold = 0;
        for (const ThinkingTagPair& pair : pairs_) {
            hold = std::max(hold, partial_tag_suffix_len(pending_, pair.open));
            hold = std::max(hold, partial_tag_suffix_len(pending_, pair.close));
        }
        if (hold >= pending_.size()) {
            return;
        }
        emit(out, pending_.substr(0, pending_.size() - hold), channel, false);
        pending_.erase(0, pending_.size() - hold);
    }

    /** Length of the longest suffix of @p text that is a proper prefix of
     *  @p tag — the run that might still complete into a delimiter. */
    static size_t partial_tag_suffix_len(const std::string& text, const std::string& tag) {
        if (tag.empty()) {
            return 0;
        }
        const size_t max_len = std::min(tag.size() - 1, text.size());
        for (size_t len = max_len; len > 0; --len) {
            if (text.compare(text.size() - len, len, tag, 0, len) == 0) {
                return len;
            }
        }
        return 0;
    }

    const ThinkingTagPair* find_earliest_open(size_t* out_pos) const {
        return find_earliest(out_pos, /*want_close=*/false);
    }
    const ThinkingTagPair* find_earliest_close(size_t* out_pos) const {
        return find_earliest(out_pos, /*want_close=*/true);
    }
    const ThinkingTagPair* find_earliest(size_t* out_pos, bool want_close) const {
        size_t best = std::string::npos;
        const ThinkingTagPair* best_pair = nullptr;
        for (const ThinkingTagPair& pair : pairs_) {
            const size_t pos = pending_.find(want_close ? pair.close : pair.open);
            if (pos < best) {
                best = pos;
                best_pair = &pair;
            }
        }
        *out_pos = best;
        return best_pair;
    }

    std::vector<ThinkingTagPair> pairs_;
    std::string pending_;
    /** Answer-channel text withheld while the prefilled-open ambiguity stands. */
    std::string held_;
    bool inside_reasoning_ = false;
    bool saw_delimiter_ = false;
    bool skip_leading_ws_ = false;
    bool holding_ = false;
};

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_THINKING_STREAM_INTERNAL_H
