#ifndef RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H
#define RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H

#include <cctype>
#include <climits>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#include "features/llm/utf8_internal.h"

namespace rac::llm::tool_calling {

/**
 * Keys naming the tool, and keys holding its arguments, both matched
 * case-insensitively and tried in this order. The parser (`TOOL_NAME_KEYS` and
 * `ARGUMENT_KEYS` in tool_calling.cpp) and the collision scan below read these
 * same tables, so the two cannot drift apart.
 */
inline constexpr const char* kToolNameKeys[] = {"tool",   "name",   "function", "func",
                                                "method", "action", "command",  nullptr};
inline constexpr const char* kArgumentKeys[] = {"arguments",  "args",  "params",
                                                "parameters", "input", nullptr};

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
 * Rank of @p key in a null-terminated alias table, matched case-insensitively as
 * the parser does, or -1 when it is not an alias. The parser tries aliases in
 * table order, so the lowest rank present wins.
 */
inline int alias_rank(const char* const* table, const std::string& key) {
    const std::string lowered = ascii_lower(key);
    for (int i = 0; table[i] != nullptr; ++i) {
        if (lowered == table[i]) {
            return i;
        }
    }
    return -1;
}

/** Identifier bytes the normalizer quotes as an unquoted key (`is_key_char`). */
inline bool is_unquoted_key_char(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
           ch == '_';
}

/**
 * Mirror of the unquoted-key repair in rac_tool_call_normalize_json: after `{`
 * or `,`, skip spaces, tabs and newlines, then an identifier, then spaces and
 * tabs, then `:`. The parser then reads that key exactly like a quoted one.
 *
 * @param pos First byte after the `{` or `,`.
 * @return Index of the `:`, or npos when no unquoted key starts at @p pos.
 */
inline size_t unquoted_key_colon(const std::string& text, size_t pos, std::string* key) {
    size_t j = pos;
    while (j < text.size() && (text[j] == ' ' || text[j] == '\t' || text[j] == '\n')) {
        ++j;
    }
    const size_t key_start = j;
    while (j < text.size() && is_unquoted_key_char(text[j])) {
        ++j;
    }
    if (j == key_start || j >= text.size()) {
        return std::string::npos;
    }
    const size_t key_end = j;
    while (j < text.size() && (text[j] == ' ' || text[j] == '\t')) {
        ++j;
    }
    if (j >= text.size() || text[j] != ':') {
        return std::string::npos;
    }
    *key = text.substr(key_start, key_end - key_start);
    return j;
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
 * `{` reaches the parser as `{`, so it has to reach the scan as `{` too or
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

/**
 * The scan behind has_repaired_key_collision.
 *
 * @param root_is_data True for a decoded arguments object: its own keys are
 *        checked, but nothing inside it is a call the parser would unwrap.
 */
inline bool scan_repaired_key_collision(const std::string& text, bool first_object_only,
                                        bool root_is_data) {
    // Parser traversal levels, mirroring extract_tool_name_and_args. Only an
    // envelope or a tool_calls element that names its tool directly has its
    // string-encoded arguments decoded.
    enum class Nesting { kRoot, kEnvelope, kArrayElement, kData };
    constexpr int kAbsent = INT_MAX;
    struct Container {
        bool is_array = false;

        // Arrays: the root call's `tool_calls` array. The parser unwraps it only
        // when it holds exactly one element and that element is an object.
        bool elements_are_wrappers = false;
        int commas = 0;
        int object_elements = 0;
        bool first_element_names_call = false;
        bool first_element_collides = false;

        // Objects: the parser level this object is reached at, and the tool
        // alias it was reached through when it is an envelope.
        Nesting nesting = Nesting::kData;
        int envelope_alias = kAbsent;
        // Decoded key -> was the raw token changed by repair.
        std::unordered_map<std::string, bool> keys;
        // A tool alias holds a non-empty string: the object names its call
        // directly, which takes precedence over any envelope or tool_calls.
        bool names_call = false;
        // The lowest-ranked argument alias present (the one the parser reads),
        // and whether it is a string decoding to an object whose keys collide.
        int args_alias = kAbsent;
        bool args_collide = false;
        // The lowest-ranked envelope that names a call, and its verdict.
        int envelope_match = kAbsent;
        bool envelope_collides = false;
        // The lone tool_calls element names a call, and its verdict.
        bool calls_match = false;
        bool calls_collide = false;
    };
    std::vector<Container> containers;
    std::string last_key;  // last key parsed in the innermost object

    // Settle the innermost container once its whole body is known; the parser
    // decides precedence per object, and a direct name may follow an envelope.
    // Returns true when a call the parser would execute has colliding keys.
    auto close_innermost = [&]() -> bool {
        Container frame = std::move(containers.back());
        containers.pop_back();
        last_key.clear();
        Container* parent = containers.empty() ? nullptr : &containers.back();
        if (frame.is_array) {
            if (parent != nullptr && frame.elements_are_wrappers && frame.commas == 0 &&
                frame.object_elements == 1) {
                parent->calls_match = frame.first_element_names_call;
                parent->calls_collide = frame.first_element_collides;
            }
            return false;
        }
        bool names_call = false;
        bool collides = false;
        if (frame.names_call) {
            // Top-level string arguments are wrapped as {"input": ...}, not decoded.
            names_call = true;
            collides = frame.nesting != Nesting::kRoot && frame.args_collide;
        } else if (frame.nesting != Nesting::kEnvelope && frame.envelope_match != kAbsent) {
            names_call = true;
            collides = frame.envelope_collides;
        } else if (frame.nesting == Nesting::kRoot && frame.calls_match) {
            names_call = true;
            collides = frame.calls_collide;
        }
        switch (frame.nesting) {
            case Nesting::kRoot:
                return collides;
            case Nesting::kEnvelope:
                if (parent != nullptr && names_call &&
                    frame.envelope_alias < parent->envelope_match) {
                    parent->envelope_match = frame.envelope_alias;
                    parent->envelope_collides = collides;
                }
                return false;
            case Nesting::kArrayElement:
                if (parent != nullptr && parent->object_elements == 1) {
                    parent->first_element_names_call = names_call;
                    parent->first_element_collides = collides;
                }
                return false;
            case Nesting::kData:
                return false;
        }
        return false;
    };

    // Record a key of the innermost object. Returns true on a repaired collision.
    auto add_key = [&](const std::string& key, bool changed) -> bool {
        Container& frame = containers.back();
        const auto [entry, inserted] = frame.keys.emplace(key, changed);
        if (!inserted && (entry->second || changed)) {
            return true;
        }
        last_key = key;
        const int rank = alias_rank(kArgumentKeys, key);
        if (rank >= 0 && rank < frame.args_alias) {
            frame.args_alias = rank;
            frame.args_collide = false;
        }
        return false;
    };

    // After `{` or `,` in an object, take an unquoted key the normalizer would
    // quote. Returns true on a repaired collision; advances @p i to its `:`.
    auto take_unquoted_key = [&](size_t* i) -> bool {
        std::string key;
        const size_t colon = unquoted_key_colon(text, *i + 1, &key);
        if (colon == std::string::npos) {
            return false;
        }
        *i = colon;
        return add_key(key, false);
    };

    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '{') {
            Container frame;
            if (containers.empty()) {
                frame.nesting = root_is_data ? Nesting::kData : Nesting::kRoot;
            } else {
                Container& parent = containers.back();
                if (parent.is_array) {
                    ++parent.object_elements;
                    frame.nesting = parent.elements_are_wrappers ? Nesting::kArrayElement
                                                                 : Nesting::kData;
                } else {
                    const int alias = alias_rank(kToolNameKeys, last_key);
                    if ((parent.nesting == Nesting::kRoot ||
                         parent.nesting == Nesting::kArrayElement) &&
                        alias >= 0) {
                        frame.nesting = Nesting::kEnvelope;
                        frame.envelope_alias = alias;
                    }
                }
            }
            containers.push_back(std::move(frame));
            last_key.clear();
            if (take_unquoted_key(&i)) {
                return true;
            }
        } else if (text[i] == '}') {
            if (!containers.empty() && !containers.back().is_array) {
                if (close_innermost()) {
                    return true;
                }
                if (first_object_only && containers.empty()) {
                    break;
                }
            }
        } else if (text[i] == '[') {
            Container frame;
            frame.is_array = true;
            // Only the root call's own `tool_calls` array is unwrapped; one
            // nested inside object-valued arguments is data.
            frame.elements_are_wrappers =
                !containers.empty() && !containers.back().is_array &&
                containers.back().nesting == Nesting::kRoot &&
                ascii_lower(last_key) == "tool_calls";
            containers.push_back(std::move(frame));
            last_key.clear();
        } else if (text[i] == ']') {
            if (!containers.empty() && containers.back().is_array) {
                close_innermost();
            }
            last_key.clear();
        } else if (text[i] == ',') {
            if (containers.empty()) {
                continue;
            }
            if (containers.back().is_array) {
                ++containers.back().commas;
            } else if (take_unquoted_key(&i)) {
                return true;
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
            if (containers.empty() || containers.back().is_array) {
                continue;
            }
            const std::string raw = text.substr(start, i - start + 1);
            if (next < text.size() && text[next] == ':') {
                const std::string repaired = rac::llm::sanitize_utf8(raw);
                const auto key = nlohmann::json::parse(repaired, nullptr, false);
                if (!key.is_string()) {
                    last_key.clear();
                    continue;
                }
                if (add_key(key.get<std::string>(), raw != repaired)) {
                    return true;
                }
                continue;
            }
            // A string in value position.
            Container& frame = containers.back();
            if (alias_rank(kToolNameKeys, last_key) >= 0 && raw.size() > 2) {
                frame.names_call = true;
            }
            // Only the argument alias the parser reads, inside an object whose
            // string arguments it decodes, carries keys of its own, and only
            // when the string decodes to a JSON object.
            const int rank = alias_rank(kArgumentKeys, last_key);
            if ((frame.nesting == Nesting::kEnvelope || frame.nesting == Nesting::kArrayElement) &&
                rank >= 0 && rank == frame.args_alias) {
                const std::string decoded = decode_json_string_token(raw);
                const auto args =
                    nlohmann::json::parse(rac::llm::sanitize_utf8(decoded), nullptr, false);
                if (args.is_object() && scan_repaired_key_collision(decoded, false, true)) {
                    frame.args_collide = true;
                }
            }
            last_key.clear();
        }
    }
    // A truncated call is settled as if it closed here, so an unterminated
    // envelope cannot hide a collision.
    while (!containers.empty()) {
        if (close_innermost()) {
            return true;
        }
    }
    return false;
}

}  // namespace key_repair_detail

/**
 * Inspect raw string tokens before repair erases their provenance. Only strings
 * followed by ':' are keys (plus the unquoted `key:` the normalizer quotes);
 * braces inside strings never change object scope. Valid duplicate keys keep
 * their existing last-wins behavior.
 *
 * A string value is scanned recursively only where the parser itself decodes
 * one, following extract_tool_name_and_args: the argument alias it reads (the
 * lowest-ranked one present) in an envelope or lone `tool_calls` element that
 * names its tool directly, when that string decodes to a JSON object. A direct
 * name takes precedence over an envelope, an envelope over `tool_calls`, so each
 * object is settled when it closes. The decoded arguments are data: their own
 * keys are checked, but nothing inside them is unwrapped. Object-valued
 * arguments pass through unchanged, so JSON text nested inside ordinary tool
 * data is data, not keys, and must not be rejected.
 */
inline bool has_repaired_key_collision(const std::string& text, bool first_object_only = false) {
    return key_repair_detail::scan_repaired_key_collision(text, first_object_only, false);
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
