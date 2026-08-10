/**
 * @file rac_llm_thinking.cpp
 * @brief Implementation of the rac_llm_thinking C ABI.
 *
 * Behavioral equivalence target: Swift's
 * ThinkingContentParser.{extract,splitTokens,strip} (RunAnywhere+TextGeneration.swift).
 * Same character-ratio heuristic for token splits, same trim semantics,
 * same handling of trailing unclosed <think> on streaming output.
 *
 * This is also the authority for the STREAMING terminal result: rather than
 * accumulate the streaming splitter's per-delta segments and hope the two agree,
 * `dispatch_terminal_once` (llm_module.cpp) re-splits the accumulated raw text
 * through `rac_llm_extract_thinking_with_tags` here. One function, one answer —
 * the only structural way to keep a whole-text splitter and its incremental twin
 * from drifting, and they had drifted (trailing whitespace, a second bare
 * closing tag, a second reasoning block).
 */

#include "rac/features/llm/rac_llm_thinking.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>

namespace {

constexpr std::array<std::pair<std::string_view, std::string_view>, 2> kDefaultTagPairs = {{
    {std::string_view{"<think>"}, std::string_view{"</think>"}},
    {std::string_view{"<thinking>"}, std::string_view{"</thinking>"}},
}};

/* Thread-local storage for the C-string return values. The header contract
 * is "valid until next call on this thread"; one slot per output channel. */
thread_local std::string tl_response;
thread_local std::string tl_thinking;
thread_local std::string tl_stripped;

bool is_ws(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

/** Mirrors Swift's `String.trimmingCharacters(in: .whitespacesAndNewlines)`. */
std::string trim(std::string_view sv) {
    size_t b = 0, e = sv.size();
    while (b < e && is_ws(sv[b]))
        ++b;
    while (e > b && is_ws(sv[e - 1]))
        --e;
    return std::string(sv.substr(b, e - b));
}

struct ThinkingSplit {
    std::string response;
    std::string thinking;
};

using TagPair = std::pair<std::string_view, std::string_view>;

/** Appends a trimmed segment, newline-joining it to whatever is already there. */
void append_segment(std::string* dst, std::string_view segment) {
    const std::string trimmed = trim(segment);
    if (trimmed.empty())
        return;
    if (!dst->empty())
        *dst += '\n';
    *dst += trimmed;
}

/** Earliest occurrence of any pair's opening (or closing) delimiter. All pairs
 *  are searched together rather than one being chosen up front: picking a pair
 *  by its opening tag sent `</thinking>` output to the `<think>` recognizer,
 *  which cannot see it, and picking one at all is wrong for a response that
 *  legitimately uses two families. */
const TagPair* find_earliest(std::string_view sv, const TagPair* pairs, size_t pair_count,
                             bool want_close, size_t* out_pos) {
    size_t best = std::string_view::npos;
    const TagPair* best_pair = nullptr;
    for (size_t i = 0; i < pair_count; ++i) {
        const size_t pos = sv.find(want_close ? pairs[i].second : pairs[i].first);
        if (pos < best) {
            best = pos;
            best_pair = &pairs[i];
        }
    }
    *out_pos = best;
    return best_pair;
}

/** Whole-text split.
 *
 *  This is the same state machine `ThinkingStreamSplitter::push` runs, applied
 *  to the complete response instead of delta by delta, and that is deliberate:
 *  the previous version handled ONE leading close-before-open plus ONE matched
 *  pair and then appended the rest verbatim, so `R1</think>A1</think>A2` came
 *  back with a raw `</think>` inside the answer and `<think>a</think>X<think>b
 *  </think>Y` echoed the second block whole. The streaming twin looped and got
 *  both right, which is precisely the divergence that must not exist.
 *
 *  The three rules, in the order the loop applies them:
 *   - Inside reasoning, a further opening tag is swallowed (never a channel
 *     change) and the first closing tag ends the region.
 *   - In answer mode, a closing tag reached before any opening tag closes a
 *     reasoning region that began before the first generated token. That is not
 *     malformed output: a reasoning chat template may put the opening tag in the
 *     PROMPT rather than ask the model to emit it (maple-preview's manifest sets
 *     `gen_prefill: "<think>\n"`). Only the FIRST such tag reclassifies what
 *     precedes it; a later bare closing tag is swallowed so the delimiter never
 *     reaches the answer, but the answer around it survives.
 *   - An opening tag begins a reasoning region and the text before it stays
 *     answer text.
 *
 *  Every segment is trimmed, so no whitespace that hugged a delimiter can reach
 *  either channel. */
ThinkingSplit split_all(std::string_view sv, const TagPair* pairs, size_t pair_count) {
    ThinkingSplit out;
    bool inside_reasoning = false;
    bool saw_delimiter = false;

    for (;;) {
        size_t open_pos = std::string_view::npos;
        size_t close_pos = std::string_view::npos;
        const TagPair* open_pair = find_earliest(sv, pairs, pair_count, false, &open_pos);
        const TagPair* close_pair = find_earliest(sv, pairs, pair_count, true, &close_pos);

        if (inside_reasoning) {
            if (open_pair != nullptr && (close_pair == nullptr || open_pos < close_pos)) {
                append_segment(&out.thinking, sv.substr(0, open_pos));
                sv.remove_prefix(open_pos + open_pair->first.size());
                continue;
            }
            if (close_pair != nullptr) {
                append_segment(&out.thinking, sv.substr(0, close_pos));
                sv.remove_prefix(close_pos + close_pair->second.size());
                inside_reasoning = false;
                continue;
            }
            // A generation that exhausted its token budget inside a thinking
            // phase leaves the opening tag unterminated. The remainder is
            // thinking — never surfaced as an answer, never dropped either.
            append_segment(&out.thinking, sv);
            return out;
        }

        if (close_pair != nullptr && (open_pair == nullptr || close_pos < open_pos)) {
            append_segment(saw_delimiter ? &out.response : &out.thinking, sv.substr(0, close_pos));
            sv.remove_prefix(close_pos + close_pair->second.size());
            saw_delimiter = true;
            continue;
        }
        if (open_pair != nullptr) {
            append_segment(&out.response, sv.substr(0, open_pos));
            sv.remove_prefix(open_pos + open_pair->first.size());
            inside_reasoning = true;
            saw_delimiter = true;
            continue;
        }
        append_segment(&out.response, sv);
        return out;
    }
}

rac_result_t extract_thinking_with_pairs(const char* text, const TagPair* pairs, size_t pair_count,
                                         const char** out_response, size_t* out_response_len,
                                         const char** out_thinking, size_t* out_thinking_len) {
    if (text == nullptr || out_response == nullptr || out_response_len == nullptr ||
        out_thinking == nullptr || out_thinking_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    const std::string_view sv(text);
    // Text carrying no delimiter of any recognized pair is returned verbatim —
    // no trim, no reflow. A response with no thinking at all must be
    // bit-identical to its input.
    bool has_delimiter = false;
    for (size_t i = 0; i < pair_count && !has_delimiter; ++i) {
        has_delimiter = sv.find(pairs[i].first) != std::string_view::npos ||
                        sv.find(pairs[i].second) != std::string_view::npos;
    }
    if (!has_delimiter) {
        tl_response.assign(text);
        tl_thinking.clear();
        *out_response = tl_response.c_str();
        *out_response_len = tl_response.size();
        *out_thinking = nullptr;
        *out_thinking_len = 0;
        return RAC_SUCCESS;
    }

    ThinkingSplit split = split_all(sv, pairs, pair_count);
    tl_response = std::move(split.response);
    tl_thinking = std::move(split.thinking);
    *out_response = tl_response.c_str();
    *out_response_len = tl_response.size();
    *out_thinking = tl_thinking.empty() ? nullptr : tl_thinking.c_str();
    *out_thinking_len = tl_thinking.size();
    return RAC_SUCCESS;
}

rac_result_t extract_thinking_with_default_pairs(const char* text, const char** out_response,
                                                 size_t* out_response_len,
                                                 const char** out_thinking,
                                                 size_t* out_thinking_len) {
    return extract_thinking_with_pairs(text, kDefaultTagPairs.data(), kDefaultTagPairs.size(),
                                       out_response, out_response_len, out_thinking,
                                       out_thinking_len);
}

}  // namespace

extern "C" {

rac_result_t rac_llm_extract_thinking(const char* text, const char** out_response,
                                      size_t* out_response_len, const char** out_thinking,
                                      size_t* out_thinking_len) {
    return extract_thinking_with_default_pairs(text, out_response, out_response_len, out_thinking,
                                               out_thinking_len);
}

rac_result_t rac_llm_extract_thinking_with_tags(const char* text, const char* open_tag,
                                                const char* close_tag, const char** out_response,
                                                size_t* out_response_len, const char** out_thinking,
                                                size_t* out_thinking_len) {
    if (open_tag == nullptr || open_tag[0] == '\0' || close_tag == nullptr ||
        close_tag[0] == '\0') {
        return rac_llm_extract_thinking(text, out_response, out_response_len, out_thinking,
                                        out_thinking_len);
    }
    const std::array<std::pair<std::string_view, std::string_view>, 3> tag_pairs = {{
        {std::string_view{open_tag}, std::string_view{close_tag}},
        kDefaultTagPairs[0],
        kDefaultTagPairs[1],
    }};

    // A prefilled opening tag needs no special case here any more: the shared
    // recognizer treats a close-before-open as a thinking region that started
    // before the first token, so a model WITH a configured pattern and a model
    // WITHOUT one split identically. That equivalence is the fix — the app
    // registers local bundles that carry no ThinkingTagPattern, so a
    // pattern-gated rule never fired for them.
    return extract_thinking_with_pairs(text, tag_pairs.data(), tag_pairs.size(), out_response,
                                       out_response_len, out_thinking, out_thinking_len);
}

rac_result_t rac_llm_strip_thinking(const char* text, const char** out_stripped,
                                    size_t* out_stripped_len) {
    if (text == nullptr || out_stripped == nullptr || out_stripped_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string buf(text);

    /* A closing tag with no opening tag before it closes a thinking region that
     * began before the first generated token — the prefilled `gen_prefill:
     * "<think>\n"` shape. This function is what the voice agent runs before
     * handing text to TTS (voice_agent_internal_helpers.cpp), so skipping this
     * rule did not merely render the whole chain of thought, it SPOKE it, bare
     * delimiter included. Only the first such tag reclassifies what precedes it,
     * matching rac_llm_extract_thinking; later ones are handled below. */
    {
        size_t lead_close = std::string::npos;
        std::string_view lead_close_tag;
        size_t lead_open = std::string::npos;
        for (const auto& pair : kDefaultTagPairs) {
            const size_t close = buf.find(pair.second);
            if (close < lead_close) {
                lead_close = close;
                lead_close_tag = pair.second;
            }
            lead_open = std::min(lead_open, buf.find(pair.first));
        }
        if (lead_close != std::string::npos && lead_close < lead_open) {
            buf.erase(0, lead_close + lead_close_tag.size());
        }
    }

    /* Remove every complete thinking block. */
    while (true) {
        size_t best_open = std::string::npos;
        std::string_view best_open_tag;
        std::string_view best_close_tag;
        for (const auto& pair : kDefaultTagPairs) {
            const size_t open = buf.find(pair.first);
            if (open != std::string::npos && open < best_open) {
                best_open = open;
                best_open_tag = pair.first;
                best_close_tag = pair.second;
            }
        }
        if (best_open == std::string::npos)
            break;
        const size_t close = buf.find(best_close_tag, best_open + best_open_tag.size());
        if (close == std::string::npos)
            break;
        buf.erase(best_open, (close + best_close_tag.size()) - best_open);
    }

    /* Drop a trailing unclosed opening tag (still streaming). */
    size_t trailing_open = std::string::npos;
    std::string_view trailing_open_tag;
    std::string_view trailing_close_tag;
    for (const auto& pair : kDefaultTagPairs) {
        const size_t open = buf.rfind(pair.first);
        if (open != std::string::npos &&
            (trailing_open == std::string::npos || open > trailing_open)) {
            trailing_open = open;
            trailing_open_tag = pair.first;
            trailing_close_tag = pair.second;
        }
    }
    if (trailing_open != std::string::npos) {
        if (buf.find(trailing_close_tag, trailing_open + trailing_open_tag.size()) ==
            std::string::npos) {
            buf.erase(trailing_open);
        }
    }

    /* Whatever closing tags survive both passes are bare: no block opened them
     * and the leading-region rule has already fired once. Drop the delimiter and
     * keep the text around it, exactly as the splitter does — a delimiter that
     * reaches a screen or a speech synthesiser is the failure this whole family
     * of functions exists to prevent. */
    for (const auto& pair : kDefaultTagPairs) {
        for (size_t at = buf.find(pair.second); at != std::string::npos;
             at = buf.find(pair.second, at)) {
            buf.erase(at, pair.second.size());
        }
    }

    tl_stripped = trim(buf);
    *out_stripped = tl_stripped.c_str();
    *out_stripped_len = tl_stripped.size();
    return RAC_SUCCESS;
}

rac_result_t rac_llm_split_thinking_tokens(int32_t total_completion_tokens,
                                           const char* response_text, const char* thinking_text,
                                           int32_t* out_thinking_tokens,
                                           int32_t* out_response_tokens) {
    if (out_thinking_tokens == nullptr || out_response_tokens == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (thinking_text == nullptr || *thinking_text == '\0') {
        *out_thinking_tokens = 0;
        *out_response_tokens = total_completion_tokens;
        return RAC_SUCCESS;
    }

    const size_t thinking_chars = std::strlen(thinking_text);
    const size_t response_chars = (response_text != nullptr) ? std::strlen(response_text) : 0;
    const size_t total_chars = thinking_chars + response_chars;

    if (total_chars == 0 || total_completion_tokens <= 0) {
        *out_thinking_tokens = 0;
        *out_response_tokens = total_completion_tokens;
        return RAC_SUCCESS;
    }

    const double ratio = static_cast<double>(thinking_chars) / static_cast<double>(total_chars);
    int32_t thinking = static_cast<int32_t>(ratio * static_cast<double>(total_completion_tokens));
    if (thinking < 0)
        thinking = 0;
    if (thinking > total_completion_tokens)
        thinking = total_completion_tokens;

    *out_thinking_tokens = thinking;
    *out_response_tokens = total_completion_tokens - thinking;
    return RAC_SUCCESS;
}

}  // extern "C"
