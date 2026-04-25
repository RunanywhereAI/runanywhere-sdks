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
#include <cctype>
#include <cstring>
#include <string>
#include <string_view>

namespace {

constexpr std::string_view kOpenTag  = "<think>";
constexpr std::string_view kCloseTag = "</think>";

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
    while (b < e && is_ws(sv[b])) ++b;
    while (e > b && is_ws(sv[e - 1])) --e;
    return std::string(sv.substr(b, e - b));
}

}  // namespace

extern "C" {

rac_result_t rac_llm_extract_thinking(const char*  text,
                                       const char** out_response,
                                       size_t*      out_response_len,
                                       const char** out_thinking,
                                       size_t*      out_thinking_len) {
    if (text == nullptr || out_response == nullptr || out_response_len == nullptr ||
        out_thinking == nullptr || out_thinking_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string_view sv(text);
    auto open  = sv.find(kOpenTag);
    auto close = sv.find(kCloseTag);

    if (open == std::string_view::npos ||
        close == std::string_view::npos ||
        open + kOpenTag.size() > close) {
        // No (well-formed) <think> block.
        tl_response.assign(text);
        tl_thinking.clear();
        *out_response     = tl_response.c_str();
        *out_response_len = tl_response.size();
        *out_thinking     = nullptr;
        *out_thinking_len = 0;
        return RAC_SUCCESS;
    }

    std::string thinking = trim(sv.substr(open + kOpenTag.size(),
                                          close - (open + kOpenTag.size())));
    std::string before   = trim(sv.substr(0, open));
    std::string after    = trim(sv.substr(close + kCloseTag.size()));

    std::string response;
    if (!before.empty()) response = before;
    if (!after.empty()) {
        if (!response.empty()) response += '\n';
        response += after;
    }

    tl_response = std::move(response);
    *out_response     = tl_response.c_str();
    *out_response_len = tl_response.size();

    if (thinking.empty()) {
        tl_thinking.clear();
        *out_thinking     = nullptr;
        *out_thinking_len = 0;
    } else {
        tl_thinking       = std::move(thinking);
        *out_thinking     = tl_thinking.c_str();
        *out_thinking_len = tl_thinking.size();
    }
    return RAC_SUCCESS;
}

rac_result_t rac_llm_strip_thinking(const char*  text,
                                     const char** out_stripped,
                                     size_t*      out_stripped_len) {
    if (text == nullptr || out_stripped == nullptr || out_stripped_len == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string buf(text);

    /* Remove all complete <think>...</think> blocks. */
    while (true) {
        auto open = buf.find(kOpenTag);
        if (open == std::string::npos) break;
        auto close = buf.find(kCloseTag, open + kOpenTag.size());
        if (close == std::string::npos) break;
        buf.erase(open, (close + kCloseTag.size()) - open);
    }

    /* Drop trailing unclosed <think>... (still streaming). */
    auto trailing_open = buf.rfind(kOpenTag);
    if (trailing_open != std::string::npos) {
        auto after_open = trailing_open + kOpenTag.size();
        if (buf.find(kCloseTag, after_open) == std::string::npos) {
            buf.erase(trailing_open);
        }
    }

    tl_stripped = trim(buf);
    *out_stripped     = tl_stripped.c_str();
    *out_stripped_len = tl_stripped.size();
    return RAC_SUCCESS;
}

rac_result_t rac_llm_split_thinking_tokens(int32_t     total_completion_tokens,
                                            const char* response_text,
                                            const char* thinking_text,
                                            int32_t*    out_thinking_tokens,
                                            int32_t*    out_response_tokens) {
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
    const size_t total_chars    = thinking_chars + response_chars;

    if (total_chars == 0 || total_completion_tokens <= 0) {
        *out_thinking_tokens = 0;
        *out_response_tokens = total_completion_tokens;
        return RAC_SUCCESS;
    }

    const double ratio    = static_cast<double>(thinking_chars) / static_cast<double>(total_chars);
    int32_t      thinking = static_cast<int32_t>(ratio * static_cast<double>(total_completion_tokens));
    if (thinking < 0) thinking = 0;
    if (thinking > total_completion_tokens) thinking = total_completion_tokens;

    *out_thinking_tokens = thinking;
    *out_response_tokens = total_completion_tokens - thinking;
    return RAC_SUCCESS;
}

}  // extern "C"
