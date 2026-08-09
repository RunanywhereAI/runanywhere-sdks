/**
 * @file special_token_filter.h
 * @brief One sentinel stripper for every generative feature module.
 *
 * Backends occasionally leak a tokenizer-internal end-of-utterance / end-of-text
 * sentinel into the streaming callback when the runtime's own swallow path
 * missed it (notably SmolVLM / Idefics, Qwen-VL, Llama-3 — see B-RN-14-001).
 * Left in place the angle-bracket artifact reaches the user: an
 * `<end_of_utterance>` suffix was observed rendered inside a live-camera
 * caption, and `<|im_end|>` inside chat bubbles.
 *
 * This header exists because the LLM and VLM modules each carried their own
 * file-local copy of this filter and the copies drifted: the LLM one grew a
 * bare-sentinel allowlist (`<end_of_utterance>` and friends), the VLM one never
 * did, so the same model was clean in chat and contaminated in captions. There
 * is now exactly one implementation, so an allowlist entry can no longer be
 * added for one modality and forgotten for the other.
 *
 * Two pattern families are recognised:
 *   1. `<|TOKEN|>` — Qwen / Llama-3 / GPT-style pipe-wrapped sentinels. The
 *      scanner consumes everything between `<|` and the next `|>`, which
 *      naturally covers `im_end`, `eot_id`, `endoftext`, `im_start`,
 *      `vision_start`, `vision_end`, etc.
 *   2. Bare `<TOKEN>` sentinels — `<eot>`, `<end_of_utterance>`, `<endoftext>`,
 *      `<eos>`. Only the explicit allowlist is stripped so legitimate user
 *      content containing `<` is preserved.
 *
 * Two entry points, because a stream and a finished answer are different
 * problems:
 *   - `strip_special_tokens(const std::string&)` for the non-streaming verbs,
 *     which hand back one complete answer.
 *   - `StreamFilter` for the streaming callbacks. A sentinel is a property of
 *     the *text*, not of one callback: a backend is free to split `<|im_end|>`
 *     across two invocations, and neither half is recognisable alone. The
 *     filter therefore holds an unresolved prefix until the next chunk either
 *     completes it (strip both halves) or disproves it (emit both halves).
 *     Filtering each chunk independently could only ever emit the `<` and then
 *     fail to match the remainder, which is the artifact this file exists to
 *     remove.
 *
 * Neither entry point has a fixed output capacity: a decoded chunk is whatever
 * the backend hands over — llama.cpp emits a piece at a time, but a batched or
 * detokenise-on-flush runtime can deliver hundreds of bytes in one call — and
 * an output buffer that silently drops the suffix would corrupt the answer.
 */

#ifndef RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H
#define RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H

#include <cstddef>
#include <cstring>
#include <string>

namespace rac::tokens {

namespace detail {

// A `<` is only worth holding back while it could still become a sentinel.
// `<end_of_utterance>` (18 bytes) is the longest form in the wild; past this
// bound the `<` belongs to ordinary text — a comparison, a code block, an HTML
// snippet — and holding it would stall the stream on content that will never
// resolve.
constexpr size_t kMaxHeldBytes = 64;

/**
 * Copy @p len bytes of @p text into @p out with sentinels removed; return how
 * many input bytes were consumed.
 *
 * With @p hold_partial the scan stops at a tail that could still grow into a
 * sentinel (`"<"`, `"<|im_"`, `"<end_of_utter"`) and leaves it unconsumed for
 * the caller to carry into the next chunk. Without it every such tail is
 * emitted literally, which is the honest answer for a string with nothing more
 * coming: an unfinished prefix at that point is just text.
 */
inline size_t scan(const char* text, size_t len, std::string& out, bool hold_partial) {
    // Bare-form sentinels matched as exact substrings. Keep the list short:
    // every additional entry costs an O(n*m) scan per token. Patterns must
    // not overlap (`<eos>` is a prefix of `<eos_id>` — not in this list).
    static const char* const kBareSentinels[] = {
        "<end_of_utterance>",
        "<endoftext>",
        "<eot>",
        "<eos>",
    };
    constexpr size_t kBareCount = sizeof(kBareSentinels) / sizeof(kBareSentinels[0]);

    size_t i = 0;
    while (i < len) {
        if (text[i] != '<') {
            out.push_back(text[i++]);
            continue;
        }

        // A trailing `<` could still open either family on the next chunk.
        if (i + 1 == len) {
            if (hold_partial) {
                return i;
            }
            out.push_back(text[i++]);
            continue;
        }

        if (text[i + 1] == '|') {
            // Pipe-wrapped form: skip everything through the next `|>`.
            size_t end = i + 2;
            bool closed = false;
            while (end + 1 < len) {
                if (text[end] == '|' && text[end + 1] == '>') {
                    closed = true;
                    break;
                }
                ++end;
            }
            if (closed) {
                i = end + 2;
                continue;
            }
            if (hold_partial && len - i <= kMaxHeldBytes) {
                return i;
            }
            // Never a sentinel: emit the `<` literally and rescan from the
            // next byte so anything nested inside is still examined.
            out.push_back(text[i++]);
            continue;
        }

        bool stripped = false;
        bool could_complete = false;
        for (size_t k = 0; k < kBareCount; ++k) {
            const char* needle = kBareSentinels[k];
            const size_t needle_len = std::strlen(needle);
            const size_t avail = len - i;
            if (avail >= needle_len) {
                if (std::memcmp(text + i, needle, needle_len) == 0) {
                    i += needle_len;
                    stripped = true;
                    break;
                }
            } else if (std::memcmp(text + i, needle, avail) == 0) {
                // The chunk ends mid-needle; the rest may be in the next one.
                could_complete = true;
            }
        }
        if (stripped) {
            continue;
        }
        if (could_complete && hold_partial) {
            return i;
        }
        out.push_back(text[i++]);
    }
    return len;
}

}  // namespace detail

/**
 * Strip tokenizer-internal special tokens from a complete string, for the
 * non-streaming verbs which hand back one whole answer.
 */
inline std::string strip_special_tokens(const std::string& text) {
    std::string out;
    out.reserve(text.size());
    detail::scan(text.data(), text.size(), out, /*hold_partial=*/false);
    return out;
}

/**
 * Per-stream sentinel filter: one instance per generation, living in the
 * stream context beside the accumulated text.
 *
 * `feed()` returns the text that is safe to deliver *now*; a tail that could
 * still turn out to be a sentinel is held until the next chunk decides it.
 * `flush()` releases whatever is still held and must be called once when the
 * stream ends, or a `<` that happened to arrive as the final byte would be
 * silently dropped from the answer.
 *
 * Both return a reference to a buffer owned by the filter (reused across
 * chunks so a token stream does not allocate per token); it stays valid until
 * the next `feed()` / `flush()` on the same instance.
 */
class StreamFilter {
   public:
    const std::string& feed(const char* chunk) {
        out_.clear();
        if (chunk == nullptr || chunk[0] == '\0') {
            return out_;
        }
        if (pending_.empty()) {
            const size_t len = std::strlen(chunk);
            const size_t consumed = detail::scan(chunk, len, out_, /*hold_partial=*/true);
            pending_.assign(chunk + consumed, len - consumed);
        } else {
            pending_.append(chunk);
            const size_t consumed =
                detail::scan(pending_.data(), pending_.size(), out_, /*hold_partial=*/true);
            pending_.erase(0, consumed);
        }
        return out_;
    }

    const std::string& flush() {
        out_.clear();
        if (!pending_.empty()) {
            detail::scan(pending_.data(), pending_.size(), out_, /*hold_partial=*/false);
            pending_.clear();
        }
        return out_;
    }

   private:
    std::string pending_;
    std::string out_;
};

}  // namespace rac::tokens

#endif  // RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H
