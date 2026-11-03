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

/** Lowercases one ASCII byte. JSON keywords are ASCII, so no locale is needed. */
inline char ascii_lower(char ch) {
    return (ch >= 'A' && ch <= 'Z') ? static_cast<char>(ch - 'A' + 'a') : ch;
}

/** Lowercased copy for case-insensitive keyword comparison. */
inline std::string ascii_lower(const std::string& value) {
    std::string lowered = value;
    for (char& ch : lowered) {
        ch = ascii_lower(ch);
    }
    return lowered;
}

/**
 * Keys the parser accepts as the tool-call wrapper (`TOOL_NAME_KEYS` in
 * tool_calling.cpp). An object reached through one of these is an envelope the
 * parser unwraps, and string-encoded arguments inside it are decoded.
 */
inline bool is_tool_alias(const std::string& key) {
    const std::string lowered = ascii_lower(key);
    return lowered == "tool" || lowered == "name" || lowered == "function" || lowered == "func" ||
           lowered == "method" || lowered == "action" || lowered == "command";
}

/**
 * Keys the parser decodes as an argument object (`ARGUMENT_KEYS` in
 * tool_calling.cpp). The parser matches them case-insensitively, so this must
 * too: `"Arguments"` is decoded exactly like `"arguments"`.
 */
inline bool is_argument_alias(const std::string& key) {
    const std::string lowered = ascii_lower(key);
    return lowered == "arguments" || lowered == "args" || lowered == "params" ||
           lowered == "parameters" || lowered == "input";
}

/** Appends one code point as UTF-8. */
inline void append_utf8(unsigned int codepoint, std::string* out) {
    if (codepoint < 0x80) {
        out->push_back(static_cast<char>(codepoint));
    } else if (codepoint < 0x800) {
        out->push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
        out->push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint < 0x10000) {
        out->push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
        out->push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else {
        out->push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
        out->push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    }
}

/** Reads four hex digits at @p pos of @p token. False when they are not hex. */
inline bool read_hex4(const std::string& token, size_t pos, unsigned int* out) {
    if (pos + 3 >= token.size()) {
        return false;
    }
    unsigned int value = 0;
    for (size_t i = 0; i < 4; ++i) {
        const char ch = token[pos + i];
        unsigned int digit = 0;
        if (ch >= '0' && ch <= '9') {
            digit = static_cast<unsigned int>(ch - '0');
        } else if (ch >= 'a' && ch <= 'f') {
            digit = static_cast<unsigned int>(ch - 'a') + 10;
        } else if (ch >= 'A' && ch <= 'F') {
            digit = static_cast<unsigned int>(ch - 'A') + 10;
        } else {
            return false;
        }
        value = (value << 4) | digit;
    }
    *out = value;
    return true;
}

/**
 * Decode one quoted JSON string token into the bytes the parser's JSON layer
 * sees. `\uXXXX` escapes are decoded (including surrogate pairs) because the
 * default-format envelope is re-serialized by nlohmann before extraction:
 * `\u007B` reaches the parser as `{`, so it has to reach the scan as `{` too or
 * the encoded object stays invisible. Malformed raw bytes are carried through
 * untouched, which is what keeps their repair provenance observable.
 *
 * @param token Quoted token, quotes included.
 */
inline std::string decode_json_string_token(const std::string& token) {
    std::string decoded;
    if (token.size() < 2) {
        return decoded;
    }
    const size_t last = token.size() - 2;  // last content byte
    decoded.reserve(last);
    for (size_t i = 1; i <= last; ++i) {
        const char ch = token[i];
        if (ch != '\\' || i + 1 > last) {
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
            case 'b':
                decoded += '\b';
                break;
            case 'f':
                decoded += '\f';
                break;
            case 'u': {
                unsigned int codepoint = 0;
                if (!read_hex4(token, i + 1, &codepoint)) {
                    decoded += escaped;  // Not a \u escape; keep the byte.
                    break;
                }
                i += 4;
                if (codepoint >= 0xD800 && codepoint <= 0xDBFF && i + 6 <= last &&
                    token[i + 1] == '\\' && token[i + 2] == 'u') {
                    unsigned int low = 0;
                    if (read_hex4(token, i + 3, &low) && low >= 0xDC00 && low <= 0xDFFF) {
                        codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                        i += 6;
                    }
                }
                if (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
                    // A lone surrogate is not representable; nlohmann replaces it
                    // with U+FFFD, so the scan has to see the same key.
                    codepoint = 0xFFFD;
                }
                append_utf8(codepoint, &decoded);
                break;
            }
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
 * Valid duplicate keys keep their existing last-wins behavior.
 *
 * A string value is scanned recursively only where the parser itself decodes
 * one: an argument alias (`arguments`/`args`/`params`/`parameters`/`input`,
 * matched case-insensitively) that is a direct member of an object the parser
 * treats as a wrapper (an envelope reached through a tool alias, or an element
 * of a `tool_calls` array). Object-valued arguments are passed through
 * unchanged by the parser, so JSON text nested inside ordinary tool data is
 * data, not keys, and must not be rejected.
 */
inline bool has_repaired_key_collision(const std::string& text, bool first_object_only = false) {
    struct ObjectFrame {
        std::unordered_map<std::string, bool> keys;
        // True when the parser decodes string-encoded arguments on this object.
        bool parser_wrapper = false;
    };
    std::vector<ObjectFrame> objects;
    // One entry per open array: true for the `tool_calls` array, whose object
    // elements the parser unwraps.
    std::vector<bool> arrays;
    std::string last_key;  // last key parsed in the innermost object
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '{') {
            const bool wrapper =
                key_repair_detail::is_tool_alias(last_key) || (!arrays.empty() && arrays.back());
            objects.push_back(ObjectFrame{{}, wrapper});
            last_key.clear();
        } else if (text[i] == '}') {
            if (!objects.empty()) {
                objects.pop_back();
                last_key.clear();
                if (first_object_only && objects.empty()) {
                    break;
                }
            }
        } else if (text[i] == '[') {
            arrays.push_back(key_repair_detail::ascii_lower(last_key) == "tool_calls");
            last_key.clear();
        } else if (text[i] == ']') {
            if (!arrays.empty()) {
                arrays.pop_back();
            }
            last_key.clear();
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
                    last_key.clear();
                    continue;
                }
                const bool changed = raw != repaired;
                const auto [entry, inserted] =
                    objects.back().keys.emplace(key.get<std::string>(), changed);
                if (!inserted && (entry->second || changed)) {
                    return true;
                }
                last_key = key.get<std::string>();
                continue;
            }
            // A string in value position. Only a parser-decoded argument alias
            // carries a JSON-encoded object that becomes keys of its own.
            if (objects.back().parser_wrapper && key_repair_detail::is_argument_alias(last_key)) {
                const std::string decoded =
                    key_repair_detail::decode_json_string_token(text.substr(start, i - start + 1));
                if (has_repaired_key_collision(decoded, false)) {
                    return true;
                }
            }
            last_key.clear();
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
