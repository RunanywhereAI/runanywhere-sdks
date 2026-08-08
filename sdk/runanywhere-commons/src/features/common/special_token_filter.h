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
 */

#ifndef RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H
#define RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H

#include <cstddef>
#include <cstring>
#include <string>

namespace rac::tokens {

/**
 * Strip tokenizer-internal special tokens from a generated token or chunk
 * before the value reaches user callbacks or downstream proto subscribers.
 *
 * The cleaned output is written to @p buf and is guaranteed NUL-terminated
 * provided @p buf_size >= 1. Returns @p buf for convenience — if the entire
 * token was a sentinel, @p buf points at the empty string.
 */
inline const char* strip_special_tokens(const char* token, char* buf, size_t buf_size) {
    if (!buf || buf_size == 0) {
        return buf;
    }
    if (!token) {
        buf[0] = '\0';
        return buf;
    }

    // Bare-form sentinels matched as exact substrings. Keep the list short:
    // every additional entry costs an O(n*m) scan per token. Patterns must
    // not overlap (`<eos>` is a prefix of `<eos_id>` — not in this list).
    static const char* kBareSentinels[] = {
        "<end_of_utterance>",
        "<endoftext>",
        "<eot>",
        "<eos>",
    };
    constexpr size_t kBareCount = sizeof(kBareSentinels) / sizeof(kBareSentinels[0]);

    size_t out = 0;
    size_t i = 0;
    while (token[i] != '\0' && out + 1 < buf_size) {
        if (token[i] == '<' && token[i + 1] == '|') {
            // Pipe-wrapped form: skip everything through the next |> .
            size_t end = i + 2;
            while (token[end] != '\0') {
                if (token[end] == '|' && token[end + 1] == '>') {
                    i = end + 2;
                    break;
                }
                ++end;
            }
            if (token[end] == '\0') {
                // No closing |> in this chunk — copy `<` literally and
                // continue so a multi-chunk sentinel surfacing across two
                // callback invocations still appears (downstream gets one
                // partial chunk; this never produced the angle-bracket
                // artifact observed in the reports because the runtime
                // emits the full sentinel as a single token).
                buf[out++] = token[i++];
            }
            continue;
        }

        if (token[i] == '<') {
            bool stripped = false;
            for (size_t k = 0; k < kBareCount; ++k) {
                const char* needle = kBareSentinels[k];
                const size_t needle_len = std::strlen(needle);
                if (std::strncmp(token + i, needle, needle_len) == 0) {
                    i += needle_len;
                    stripped = true;
                    break;
                }
            }
            if (stripped) {
                continue;
            }
        }

        buf[out++] = token[i++];
    }
    buf[out] = '\0';
    return buf;
}

/**
 * Whole-string overload for the non-streaming verbs, which hand back one
 * complete answer rather than a sequence of short tokens (a fixed stack buffer
 * would truncate a caption). Stripping only ever shortens, so the input length
 * is always a sufficient bound.
 */
inline std::string strip_special_tokens(const std::string& text) {
    if (text.empty()) {
        return text;
    }
    std::string buf(text.size() + 1, '\0');
    strip_special_tokens(text.c_str(), buf.data(), buf.size());
    buf.resize(std::strlen(buf.c_str()));
    return buf;
}

}  // namespace rac::tokens

#endif  // RAC_FEATURES_COMMON_SPECIAL_TOKEN_FILTER_H
