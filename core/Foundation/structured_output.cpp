// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "structured_output.h"

#include <cctype>

namespace ra::core::util {

namespace {

// Find the matching closer for `text[open]`, which must be '{' or '['.
// Returns the index just past the closer, or std::string_view::npos on
// unbalanced input. Handles escape sequences inside JSON strings so that
// '}'/']' inside quoted text doesn't prematurely terminate.
std::size_t find_matching(std::string_view text, std::size_t open) {
    if (open >= text.size()) return std::string_view::npos;
    const char opener = text[open];
    char       closer = 0;
    if      (opener == '{') closer = '}';
    else if (opener == '[') closer = ']';
    else return std::string_view::npos;

    int  depth     = 1;
    bool in_string = false;
    bool escape    = false;
    for (std::size_t i = open + 1; i < text.size(); ++i) {
        const char c = text[i];
        if (escape)      { escape = false; continue; }
        if (c == '\\')   { if (in_string) escape = true; continue; }
        if (c == '"')    { in_string = !in_string; continue; }
        if (in_string)   continue;
        if (c == opener) ++depth;
        else if (c == closer) {
            if (--depth == 0) return i + 1;
        }
    }
    return std::string_view::npos;
}

}  // namespace

std::optional<std::string> extract_json(std::string_view text) {
    // Scan for the first top-level '{' or '['. Earlier prose tokens
    // should not contain raw JSON punctuation; this matches the legacy
    // commons StructuredOutputHandler behavior.
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] != '{' && text[i] != '[') continue;
        const auto end = find_matching(text, i);
        if (end == std::string_view::npos) continue;
        return std::string{text.substr(i, end - i)};
    }
    return std::nullopt;
}

}  // namespace ra::core::util
