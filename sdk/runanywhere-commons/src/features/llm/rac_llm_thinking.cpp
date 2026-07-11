/**
 * @file rac_llm_thinking.cpp
 * @brief Implementation of the rac_llm_thinking C ABI.
 *
 * Behavioral equivalence target: Swift's
 * ThinkingContentParser.{extract,splitTokens,strip} (RunAnywhere+TextGeneration.swift).
 * Same character-ratio heuristic for token splits, same trim semantics,
 * same handling of trailing unclosed <think> on streaming output.
 */

#include "rac/features/llm/rac_llm_thinking.h"

#include <array>
#include <cctype>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>

namespace {

constexpr std::string_view kDefaultOpenTag{"<think>"};
constexpr std::string_view kDefaultCloseTag{"</think>"};
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

rac_result_t extract_thinking_with_pair(const char* text, std::string_view open_tag,
                                        std::string_view close_tag,
                                        const char** out_response, size_t* out_response_len,
                                        const char** out_thinking,
                                        size_t* out_thinking_len) {
    if (text == nullptr || out_response == nullptr || out_response_len == nullptr ||
        out_thinking == nullptr || out_thinking_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string_view sv(text);
    const size_t open = sv.find(open_tag);
    const size_t close = (open != std::string_view::npos)
                             ? sv.find(close_tag, open + open_tag.size())
                             : std::string_view::npos;

    if (open == std::string_view::npos) {
        // No thinking block.
        tl_response.assign(text);
        tl_thinking.clear();
        *out_response = tl_response.c_str();
        *out_response_len = tl_response.size();
        *out_thinking = nullptr;
        *out_thinking_len = 0;
        return RAC_SUCCESS;
    }

    if (close == std::string_view::npos) {
        // A generation that exhausts its token budget inside a thinking phase
        // commonly leaves the opening tag unterminated. Keep any visible text
        // before it, classify the remainder as thinking, and never surface the
        // raw tag/body as an answer. Preserve deliberately malformed close-
        // before-open text for compatibility with the parser's prior contract.
        if (sv.find(close_tag) != std::string_view::npos) {
            tl_response.assign(text);
            tl_thinking.clear();
            *out_response = tl_response.c_str();
            *out_response_len = tl_response.size();
            *out_thinking = nullptr;
            *out_thinking_len = 0;
            return RAC_SUCCESS;
        }

        tl_response = trim(sv.substr(0, open));
        tl_thinking = trim(sv.substr(open + open_tag.size()));
        *out_response = tl_response.c_str();
        *out_response_len = tl_response.size();
        *out_thinking = tl_thinking.empty() ? nullptr : tl_thinking.c_str();
        *out_thinking_len = tl_thinking.size();
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

rac_result_t extract_thinking_with_pairs(
    const char* text, const std::pair<std::string_view, std::string_view>* pairs,
    size_t pair_count, const char** out_response, size_t* out_response_len,
    const char** out_thinking, size_t* out_thinking_len) {
    if (text == nullptr || out_response == nullptr || out_response_len == nullptr ||
        out_thinking == nullptr || out_thinking_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string_view sv(text);
    size_t best_open = std::string_view::npos;
    std::string_view best_open_tag;
    std::string_view best_close_tag;
    for (size_t i = 0; i < pair_count; ++i) {
        const auto& pair = pairs[i];
        const size_t open = sv.find(pair.first);
        if (open != std::string_view::npos && open < best_open) {
            best_open = open;
            best_open_tag = pair.first;
            best_close_tag = pair.second;
        }
    }
    if (best_open == std::string_view::npos) {
        return extract_thinking_with_pair(text, kDefaultOpenTag, kDefaultCloseTag, out_response,
                                          out_response_len, out_thinking, out_thinking_len);
    }
    return extract_thinking_with_pair(text, best_open_tag, best_close_tag, out_response,
                                      out_response_len, out_thinking, out_thinking_len);
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
                                                const char* close_tag,
                                                const char** out_response,
                                                size_t* out_response_len,
                                                const char** out_thinking,
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
    return extract_thinking_with_pairs(text, tag_pairs.data(), tag_pairs.size(), out_response,
                                       out_response_len, out_thinking, out_thinking_len);
}

rac_result_t rac_llm_strip_thinking(const char* text, const char** out_stripped,
                                    size_t* out_stripped_len) {
    if (text == nullptr || out_stripped == nullptr || out_stripped_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string buf(text);

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
