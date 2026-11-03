#ifndef RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H
#define RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H

#include <cctype>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#include "features/llm/utf8_internal.h"

namespace rac::llm::tool_calling {

namespace key_repair_detail {

/**
 * Arguments aliases the parser decodes as an object (see
 * `extract_tool_name_and_args`'s ARGUMENT_KEYS). A JSON-encoded object carried
 * in one of these string values keeps its keys inside a single token, out of
 * reach of the raw-token scan, so that value has to be decoded and scanned in
 * turn.
 */
inline bool is_argument_alias(const std::string& key) {
    return key == "arguments" || key == "args" || key == "params" || key == "parameters" ||
           key == "input";
}

/**
 * Decode the escapes of one quoted JSON string token, exactly as the parser's
 * `extract_json_string` does: drop the backslash and emit the escaped byte
 * literally. Malformed raw bytes and `\uXXXX` sequences are carried through
 * untouched, which is what keeps their repair provenance observable.
 *
 * @param token Quoted token, quotes included.
 */
inline std::string decode_json_string_token(const std::string& token) {
    std::string decoded;
    if (token.size() < 2) {
        return decoded;
    }
    decoded.reserve(token.size() - 2);
    for (size_t i = 1; i + 1 < token.size(); ++i) {
        const char ch = token[i];
        if (ch != '\\' || i + 2 >= token.size()) {
            decoded += ch;
            continue;
        }
        const char escaped = token[++i];
        switch (escaped) {
            case 'n':
                decoded += '\n';
                break;
            case 'r':
                decoded += '\r';
                break;
            case 't':
                decoded += '\t';
                break;
            default:
                decoded += escaped;
                break;
        }
    }
    return decoded;
}

}  // namespace key_repair_detail

// Declared up front so a string-encoded arguments value can be scanned
// recursively.
inline bool has_repaired_key_collision(const std::string& text, bool first_object_only);

/**
 * Inspect raw string tokens before repair erases their provenance. Only strings
 * followed by ':' are keys; braces inside strings never change object scope.
 * String values under an arguments alias are decoded and scanned as well, since
 * an OpenAI-style envelope JSON-encodes its whole argument object inside one
 * token. Valid duplicate keys keep their existing last-wins behavior.
 */
inline bool has_repaired_key_collision(const std::string& text, bool first_object_only = false) {
    std::vector<std::unordered_map<std::string, bool>> objects;
    std::string value_key;  // last key parsed in the innermost object
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '{') {
            objects.emplace_back();
            value_key.clear();
        } else if (text[i] == '}') {
            if (!objects.empty()) {
                objects.pop_back();
                value_key.clear();
                if (first_object_only && objects.empty()) {
                    break;
                }
            }
        } else if (text[i] == '"') {
            const size_t start = i++;
            for (; i < text.size(); ++i) {
                if (text[i] == '\\') {
                    ++i;
                } else if (text[i] == '"') {
                    break;
                }
            }
            if (i >= text.size()) {
                break;
            }
            size_t next = i + 1;
            while (next < text.size() && std::isspace(static_cast<unsigned char>(text[next]))) {
                ++next;
            }
            if (objects.empty()) {
                continue;
            }
            if (next < text.size() && text[next] == ':') {
                const std::string raw = text.substr(start, i - start + 1);
                const std::string repaired = rac::llm::sanitize_utf8(raw);
                const auto key = nlohmann::json::parse(repaired, nullptr, false);
                if (!key.is_string()) {
                    value_key.clear();
                    continue;
                }
                const bool changed = raw != repaired;
                const auto [entry, inserted] =
                    objects.back().emplace(key.get<std::string>(), changed);
                if (!inserted && (entry->second || changed)) {
                    return true;
                }
                value_key = key.get<std::string>();
                continue;
            }
            // A string in value position. Only an arguments alias carries a
            // JSON-encoded object the parser will expand into keys of its own.
            if (!value_key.empty() && key_repair_detail::is_argument_alias(value_key)) {
                const std::string decoded =
                    key_repair_detail::decode_json_string_token(text.substr(start, i - start + 1));
                if (has_repaired_key_collision(decoded, false)) {
                    return true;
                }
            }
            value_key.clear();
        }
    }
    return false;
}

/**
 * Generation must check before sanitizing output for the protobuf boundary.
 * Every default envelope is scanned, not just the first: with
 * `parallel_tool_calls` later envelopes are dispatched too, and their colliding
 * keys must not be repaired out of sight before parsing.
 */
inline bool default_call_has_repaired_key_collision(const std::string& text) {
    constexpr const char* start_tag = "<tool_call>";
    constexpr const char* end_tag = "</tool_call>";
    const size_t start_tag_len = std::char_traits<char>::length(start_tag);
    const size_t end_tag_len = std::char_traits<char>::length(end_tag);
    size_t cursor = 0;
    for (;;) {
        const size_t start = text.find(start_tag, cursor);
        if (start == std::string::npos) {
            return false;
        }
        const size_t body = start + start_tag_len;
        const size_t end = text.find(end_tag, body);
        const size_t len = end == std::string::npos ? std::string::npos : end - body;
        if (has_repaired_key_collision(text.substr(body, len), true)) {
            return true;
        }
        if (end == std::string::npos) {
            return false;  // Unterminated final envelope; nothing follows it.
        }
        cursor = end + end_tag_len;
    }
}

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H
