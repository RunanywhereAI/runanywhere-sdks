// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "text_sanitizer.h"

#include <array>
#include <string>
#include <string_view>

namespace ra::core {

namespace {

constexpr std::array kMarkdownTokens = {
    "**", "__", "```", "~~", "`",
};

constexpr std::array<std::pair<const char*, const char*>, 10>
    kAbbreviations = {{
        {"Mr.",  "Mister"},
        {"Mrs.", "Missus"},
        {"Ms.",  "Miss"},
        {"Dr.",  "Doctor"},
        {"St.",  "Saint"},
        {"Jr.",  "Junior"},
        {"Sr.",  "Senior"},
        {"vs.",  "versus"},
        {"etc.", "et cetera"},
        {"i.e.", "that is"},
    }};

std::string strip_between(const std::string& in,
                           std::string_view open_tag,
                           std::string_view close_tag) {
    std::string out;
    out.reserve(in.size());
    std::size_t pos = 0;
    while (pos < in.size()) {
        auto start = in.find(open_tag, pos);
        if (start == std::string::npos) {
            out.append(in, pos, std::string::npos);
            break;
        }
        out.append(in, pos, start - pos);
        auto end = in.find(close_tag, start + open_tag.size());
        if (end == std::string::npos) {
            // Unclosed tag — keep the rest verbatim.
            out.append(in, start, std::string::npos);
            break;
        }
        pos = end + close_tag.size();
    }
    return out;
}

std::string replace_all(std::string in, std::string_view from, std::string_view to) {
    if (from.empty()) return in;
    std::string out;
    out.reserve(in.size());
    std::size_t pos = 0;
    while (pos < in.size()) {
        auto hit = in.find(from, pos);
        if (hit == std::string::npos) {
            out.append(in, pos, std::string::npos);
            break;
        }
        out.append(in, pos, hit - pos);
        out.append(to);
        pos = hit + from.size();
    }
    return out;
}

}  // namespace

std::string TextSanitizer::sanitize(std::string_view input) const {
    std::string text(input);

    if (cfg_.strip_thought_tags) {
        text = strip_between(text, "<think>",  "</think>");
        text = strip_between(text, "<thought>", "</thought>");
        text = strip_between(text, "<reasoning>", "</reasoning>");
    }

    if (cfg_.strip_markdown) {
        for (const char* tok : kMarkdownTokens) {
            text = replace_all(text, tok, "");
        }
        // Strip leading "# " headers.
        std::string stripped_headers;
        stripped_headers.reserve(text.size());
        bool at_line_start = true;
        for (char c : text) {
            if (at_line_start && c == '#') {
                // Skip one or more '#' and the following space.
                continue;
            }
            at_line_start = (c == '\n');
            stripped_headers.push_back(c);
        }
        text.swap(stripped_headers);
    }

    if (cfg_.expand_abbreviations) {
        for (const auto& [abbr, expansion] : kAbbreviations) {
            text = replace_all(text, abbr, expansion);
        }
    }

    if (cfg_.normalize_whitespace) {
        std::string out;
        out.reserve(text.size());
        bool prev_space = false;
        for (char c : text) {
            if (c == '\n' || c == '\t' || c == '\r') c = ' ';
            if (c == ' ') {
                if (!prev_space) out.push_back(' ');
                prev_space = true;
            } else {
                out.push_back(c);
                prev_space = false;
            }
        }
        // Trim trailing space.
        while (!out.empty() && out.back() == ' ') out.pop_back();
        text.swap(out);
    }

    return text;
}

}  // namespace ra::core
