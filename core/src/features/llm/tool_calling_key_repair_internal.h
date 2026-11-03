#ifndef RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H
#define RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H

#include <cctype>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#include "features/llm/utf8_internal.h"

namespace rac::llm::tool_calling {

// Inspect raw string tokens before repair erases their provenance. Only strings
// followed by ':' are keys; braces inside strings never change object scope.
// Valid duplicate keys keep their existing last-wins behavior.
inline bool has_repaired_key_collision(const std::string& text, bool first_object_only = false) {
    std::vector<std::unordered_map<std::string, bool>> objects;
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '{') {
            objects.emplace_back();
        } else if (text[i] == '}') {
            if (!objects.empty()) {
                objects.pop_back();
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
            if (objects.empty() || next == text.size() || text[next] != ':') {
                continue;
            }
            const std::string raw = text.substr(start, i - start + 1);
            const std::string repaired = rac::llm::sanitize_utf8(raw);
            const auto key = nlohmann::json::parse(repaired, nullptr, false);
            if (!key.is_string()) {
                continue;
            }
            const bool changed = raw != repaired;
            const auto [entry, inserted] = objects.back().emplace(key.get<std::string>(), changed);
            if (!inserted && (entry->second || changed)) {
                return true;
            }
        }
    }
    return false;
}

// Generation must check before sanitizing output for the protobuf boundary.
inline bool default_call_has_repaired_key_collision(const std::string& text) {
    constexpr const char* start_tag = "<tool_call>";
    const size_t start = text.find(start_tag);
    if (start == std::string::npos) {
        return false;
    }
    const size_t body = start + std::char_traits<char>::length(start_tag);
    const size_t end = text.find("</tool_call>", body);
    return has_repaired_key_collision(
        text.substr(body, end == std::string::npos ? std::string::npos : end - body), true);
}

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_CALLING_KEY_REPAIR_INTERNAL_H
