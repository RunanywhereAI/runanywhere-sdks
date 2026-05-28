/**
 * @file rac_llm_thinking.cpp
 * @brief Implementation of the rac_llm_thinking C ABI.
 *
 * v2 close-out Phase 5. Behavioral equivalence target: Swift's
 * ThinkingContentParser.{extract,splitTokens,strip} (RunAnywhere+TextGeneration.swift).
 * Same character-ratio heuristic for token splits, same trim semantics,
 * same handling of trailing unclosed <think> on streaming output.
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

/* Both `<think>` and `<thinking>` are emitted by upstream models (Qwen3,
 * Hermes variants). Same pair ordering as the streaming path's kOpenTags /
 * kCloseTags in rac_llm_proto_service.cpp so blocking and streaming consumers
 * agree on what a thinking block is. */
constexpr std::array<std::pair<std::string_view, std::string_view>, 2> kThinkTagPairs = {{
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

/** Earliest match of any open tag from kThinkTagPairs in @p sv starting at
 * @p from. Returns npos when no tag matches; otherwise writes the matching
 * pair index to @p out_pair_index. */
size_t find_earliest_open_tag(std::string_view sv, size_t from, size_t* out_pair_index) {
    size_t best = std::string_view::npos;
    size_t best_idx = 0;
    for (size_t i = 0; i < kThinkTagPairs.size(); ++i) {
        const size_t pos = sv.find(kThinkTagPairs[i].first, from);
        if (pos != std::string_view::npos && pos < best) {
            best = pos;
            best_idx = i;
        }
    }
    if (best != std::string_view::npos && out_pair_index != nullptr) {
        *out_pair_index = best_idx;
    }
    return best;
}

}  // namespace

extern "C" {

rac_result_t rac_llm_extract_thinking(const char* text, const char** out_response,
                                      size_t* out_response_len, const char** out_thinking,
                                      size_t* out_thinking_len) {
    if (text == nullptr || out_response == nullptr || out_response_len == nullptr ||
        out_thinking == nullptr || out_thinking_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string_view sv(text);
    size_t pair_idx = 0;
    const size_t open = find_earliest_open_tag(sv, 0, &pair_idx);
    const std::string_view open_tag =
        (open != std::string_view::npos) ? kThinkTagPairs[pair_idx].first : std::string_view{};
    const std::string_view close_tag =
        (open != std::string_view::npos) ? kThinkTagPairs[pair_idx].second : std::string_view{};
    const size_t close = (open != std::string_view::npos)
                             ? sv.find(close_tag, open + open_tag.size())
                             : std::string_view::npos;

    if (open == std::string_view::npos || close == std::string_view::npos) {
        // No (well-formed) thinking block.
        tl_response.assign(text);
        tl_thinking.clear();
        *out_response = tl_response.c_str();
        *out_response_len = tl_response.size();
        *out_thinking = nullptr;
        *out_thinking_len = 0;
        return RAC_SUCCESS;
    }

    std::string thinking =
        trim(sv.substr(open + open_tag.size(), close - (open + open_tag.size())));
    std::string before = trim(sv.substr(0, open));
    std::string after = trim(sv.substr(close + close_tag.size()));

    std::string response;
    if (!before.empty())
        response = before;
    if (!after.empty()) {
        if (!response.empty())
            response += '\n';
        response += after;
    }

    tl_response = std::move(response);
    *out_response = tl_response.c_str();
    *out_response_len = tl_response.size();

    if (thinking.empty()) {
        tl_thinking.clear();
        *out_thinking = nullptr;
        *out_thinking_len = 0;
    } else {
        tl_thinking = std::move(thinking);
        *out_thinking = tl_thinking.c_str();
        *out_thinking_len = tl_thinking.size();
    }
    return RAC_SUCCESS;
}

rac_result_t rac_llm_strip_thinking(const char* text, const char** out_stripped,
                                    size_t* out_stripped_len) {
    if (text == nullptr || out_stripped == nullptr || out_stripped_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string buf(text);

    /* Remove every complete thinking block. Either tag form is honored. */
    while (true) {
        size_t pair_idx = 0;
        const size_t open = find_earliest_open_tag(buf, 0, &pair_idx);
        if (open == std::string::npos)
            break;
        const std::string_view open_tag = kThinkTagPairs[pair_idx].first;
        const std::string_view close_tag = kThinkTagPairs[pair_idx].second;
        const size_t close = buf.find(close_tag, open + open_tag.size());
        if (close == std::string::npos)
            break;
        buf.erase(open, (close + close_tag.size()) - open);
    }

    /* Drop a trailing unclosed opening tag (still streaming). Pick the
     * latest opening across both tag forms; only strip if no matching close
     * appears after it. */
    size_t trailing_open = std::string::npos;
    size_t trailing_idx = 0;
    for (size_t i = 0; i < kThinkTagPairs.size(); ++i) {
        const size_t pos = buf.rfind(kThinkTagPairs[i].first);
        if (pos == std::string::npos)
            continue;
        if (trailing_open == std::string::npos || pos > trailing_open) {
            trailing_open = pos;
            trailing_idx = i;
        }
    }
    if (trailing_open != std::string::npos) {
        const std::string_view open_tag = kThinkTagPairs[trailing_idx].first;
        const std::string_view close_tag = kThinkTagPairs[trailing_idx].second;
        if (buf.find(close_tag, trailing_open + open_tag.size()) == std::string::npos) {
            buf.erase(trailing_open);
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
