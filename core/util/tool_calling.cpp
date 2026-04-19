// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "tool_calling.h"

#include <cctype>
#include <sstream>

namespace ra::core::util {

namespace {

constexpr std::string_view kDefaultOpen  = "<tool_call>";
constexpr std::string_view kDefaultClose = "</tool_call>";
constexpr std::string_view kLfmOpen      = "<|tool_call_start|>";
constexpr std::string_view kLfmClose     = "<|tool_call_end|>";

std::string trim(std::string_view s) {
    std::size_t a = 0;
    while (a < s.size() && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    std::size_t b = s.size();
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return std::string{s.substr(a, b - a)};
}

std::string lowercase(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (const char c : s)
        out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    return out;
}

// Extract the substring between `open` and `close` (first occurrence).
// Returns empty optional if either tag is missing.
std::optional<std::pair<std::string, std::string>> extract_between(
    std::string_view haystack, std::string_view open, std::string_view close) {
    const auto a = haystack.find(open);
    if (a == std::string_view::npos) return std::nullopt;
    const auto start = a + open.size();
    const auto b = haystack.find(close, start);
    if (b == std::string_view::npos) return std::nullopt;
    std::string inner{haystack.substr(start, b - start)};
    std::string cleaned;
    cleaned.reserve(haystack.size() - (b + close.size() - a));
    cleaned.append(haystack.substr(0, a));
    cleaned.append(haystack.substr(b + close.size()));
    return std::make_pair(std::move(inner), std::move(cleaned));
}

// For a default-format payload {"tool":"name","arguments":{...}} or
// {"name":"...", "arguments":{...}}, extract tool_name + the raw
// `arguments` JSON text. We do a lightweight parse — the arguments
// JSON is passed through verbatim; downstream code treats it as opaque.
ParsedToolCall parse_default(std::string_view payload, std::string clean) {
    ParsedToolCall out;
    out.clean_text = std::move(clean);
    out.format     = ToolCallFormat::kDefault;

    std::string body{payload};

    auto find_string_field = [&](std::string_view key) -> std::optional<std::string> {
        const std::string quoted = "\"" + std::string{key} + "\"";
        const auto a = body.find(quoted);
        if (a == std::string::npos) return std::nullopt;
        const auto colon = body.find(':', a + quoted.size());
        if (colon == std::string::npos) return std::nullopt;
        const auto q1 = body.find('"', colon + 1);
        if (q1 == std::string::npos) return std::nullopt;
        const auto q2 = body.find('"', q1 + 1);
        if (q2 == std::string::npos) return std::nullopt;
        return body.substr(q1 + 1, q2 - q1 - 1);
    };

    if (auto name = find_string_field("tool")) out.tool_name = *name;
    else if (auto name = find_string_field("name")) out.tool_name = *name;

    // Locate "arguments" as a JSON object.
    const auto ak = body.find("\"arguments\"");
    if (ak != std::string::npos) {
        const auto colon = body.find(':', ak + 11);
        if (colon != std::string::npos) {
            std::size_t i = colon + 1;
            while (i < body.size() &&
                   std::isspace(static_cast<unsigned char>(body[i]))) ++i;
            if (i < body.size() && body[i] == '{') {
                int depth = 0;
                const auto start = i;
                for (; i < body.size(); ++i) {
                    if (body[i] == '{') ++depth;
                    else if (body[i] == '}' && --depth == 0) { ++i; break; }
                }
                out.arguments_json = body.substr(start, i - start);
            }
        }
    }

    out.has_call = !out.tool_name.empty();
    return out;
}

// LFM2 payload: `[func_name(arg1="val", arg2=42)]`.
// Translate to JSON arguments {"arg1":"val","arg2":42}. String values
// remain quoted; numbers remain unquoted.
ParsedToolCall parse_lfm2(std::string_view payload, std::string clean) {
    ParsedToolCall out;
    out.clean_text = std::move(clean);
    out.format     = ToolCallFormat::kLFM2;

    std::string body = trim(payload);
    if (body.size() >= 2 && body.front() == '[' && body.back() == ']')
        body = body.substr(1, body.size() - 2);

    const auto paren = body.find('(');
    if (paren == std::string::npos) return out;
    const auto close = body.rfind(')');
    if (close == std::string::npos || close <= paren) return out;

    out.tool_name = trim(body.substr(0, paren));
    std::string args = body.substr(paren + 1, close - paren - 1);

    // Simple key=value splitter — doesn't handle nested commas inside
    // quoted values containing commas; LFM2 prompt templates avoid this.
    std::ostringstream json;
    json << '{';
    bool first = true;
    std::size_t i = 0;
    while (i < args.size()) {
        const auto eq = args.find('=', i);
        if (eq == std::string::npos) break;
        std::string key = trim(args.substr(i, eq - i));
        std::size_t j = eq + 1;
        while (j < args.size() &&
               std::isspace(static_cast<unsigned char>(args[j]))) ++j;
        std::string value;
        if (j < args.size() && args[j] == '"') {
            const auto q2 = args.find('"', j + 1);
            if (q2 == std::string::npos) break;
            value = args.substr(j, q2 - j + 1);
            i = q2 + 1;
        } else {
            const auto comma = args.find(',', j);
            const auto end = comma == std::string::npos ? args.size() : comma;
            value = trim(args.substr(j, end - j));
            i = end;
        }
        if (const auto comma = args.find(',', i); comma != std::string::npos) i = comma + 1;
        else i = args.size();
        if (!first) json << ',';
        first = false;
        json << '"' << key << "\":" << value;
    }
    json << '}';
    out.arguments_json = json.str();
    out.has_call       = !out.tool_name.empty();
    return out;
}

}  // namespace

ToolCallFormat detect_tool_call_format(std::string_view llm_output) {
    if (llm_output.find(kLfmOpen) != std::string_view::npos)
        return ToolCallFormat::kLFM2;
    return ToolCallFormat::kDefault;
}

ParsedToolCall parse_tool_call(std::string_view llm_output,
                                ToolCallFormat   format) {
    if (format == ToolCallFormat::kLFM2) {
        if (auto ex = extract_between(llm_output, kLfmOpen, kLfmClose))
            return parse_lfm2(ex->first, std::move(ex->second));
    } else {
        if (auto ex = extract_between(llm_output, kDefaultOpen, kDefaultClose))
            return parse_default(ex->first, std::move(ex->second));
    }
    ParsedToolCall out;
    out.clean_text = std::string{llm_output};
    out.format     = format;
    return out;
}

ParsedToolCall parse_tool_call(std::string_view llm_output) {
    return parse_tool_call(llm_output, detect_tool_call_format(llm_output));
}

ToolCallFormat tool_call_format_from_name(std::string_view name) {
    const auto lower = lowercase(name);
    if (lower == "lfm2") return ToolCallFormat::kLFM2;
    return ToolCallFormat::kDefault;
}

std::string_view tool_call_format_name(ToolCallFormat format) {
    switch (format) {
        case ToolCallFormat::kLFM2: return "lfm2";
        default:                    return "default";
    }
}

}  // namespace ra::core::util
