// SPDX-License-Identifier: Apache-2.0

#include "expression.h"

#include <nlohmann/json.hpp>

namespace rac::agent {
namespace {

using nlohmann::json;

std::string trim(const std::string& text) {
    const size_t first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return {};
    const size_t last = text.find_last_not_of(" \t\r\n");
    return text.substr(first, last - first + 1);
}

std::vector<std::string> split_path(const std::string& reference) {
    std::vector<std::string> parts;
    size_t start = 0;
    while (start <= reference.size()) {
        const size_t dot = reference.find('.', start);
        if (dot == std::string::npos) {
            parts.push_back(reference.substr(start));
            break;
        }
        parts.push_back(reference.substr(start, dot - start));
        start = dot + 1;
    }
    return parts;
}

/// Render a resolved value for interpolation into surrounding text. Strings
/// lose their quotes so `Hello {{ A.name }}` reads naturally; everything else
/// keeps its JSON form.
std::string to_text(const json& value) {
    if (value.is_string())
        return value.get<std::string>();
    if (value.is_null())
        return "null";
    return value.dump();
}

bool navigate(const json& root, const std::vector<std::string>& path, size_t start, json* out,
              std::string* out_error) {
    const json* cursor = &root;
    for (size_t i = start; i < path.size(); ++i) {
        const std::string& segment = path[i];
        if (segment.empty())
            continue;

        if (cursor->is_array()) {
            char* end = nullptr;
            const long index = std::strtol(segment.c_str(), &end, 10);
            if (end == segment.c_str() || *end != '\0' || index < 0 ||
                static_cast<size_t>(index) >= cursor->size()) {
                *out_error = "no element '" + segment + "' in array";
                return false;
            }
            cursor = &(*cursor)[static_cast<size_t>(index)];
            continue;
        }

        if (!cursor->is_object() || !cursor->contains(segment)) {
            *out_error = "no field '" + segment + "' in referenced value";
            return false;
        }
        cursor = &(*cursor)[segment];
    }
    *out = *cursor;
    return true;
}

bool resolve_reference(const std::string& reference, const ExpressionContext& context, json* out,
                       std::string* out_error) {
    const std::vector<std::string> path = split_path(reference);
    if (path.empty() || path[0].empty()) {
        *out_error = "empty expression";
        return false;
    }

    const std::string& head = path[0];

    if (head == "item") {
        if (!context.has_current_item) {
            *out_error = "'item' is only available inside a loop body";
            return false;
        }
        json parsed = json::parse(context.current_item_json, nullptr, false);
        if (parsed.is_discarded()) {
            *out_error = "current loop item is not valid JSON";
            return false;
        }
        return navigate(parsed, path, 1, out, out_error);
    }

    auto it = context.node_outputs.find(head);
    if (it == context.node_outputs.end()) {
        *out_error = "node '" + head + "' has not produced output yet";
        return false;
    }
    if (it->second.empty()) {
        *out_error = "node '" + head + "' produced no items";
        return false;
    }

    json parsed = json::parse(it->second.front(), nullptr, false);
    if (parsed.is_discarded()) {
        *out_error = "output of node '" + head + "' is not valid JSON";
        return false;
    }

    // `Name.output.x` and `Name.json.x` address the same thing as `Name.x`.
    // Both spellings appear in n8n material users will have copied from, and
    // neither is a plausible field name on a real payload.
    size_t next = 1;
    if (path.size() > 1 && (path[1] == "output" || path[1] == "json"))
        next = 2;

    return navigate(parsed, path, next, out, out_error);
}

}  // namespace

bool resolve_expression(const std::string& expression, const ExpressionContext& context,
                        std::string* out_value, std::string* out_error) {
    const size_t open = expression.find("{{");
    if (open == std::string::npos) {
        *out_value = expression;
        return true;
    }

    const size_t close = expression.find("}}", open + 2);
    if (close == std::string::npos) {
        *out_error = "unbalanced '{{' in expression";
        return false;
    }

    const bool whole = open == 0 && close + 2 == expression.size();
    if (whole) {
        json value;
        if (!resolve_reference(trim(expression.substr(2, close - 2)), context, &value, out_error))
            return false;
        *out_value = value.is_string() ? value.get<std::string>() : value.dump();
        return true;
    }

    std::string result;
    size_t cursor = 0;
    while (cursor < expression.size()) {
        const size_t start = expression.find("{{", cursor);
        if (start == std::string::npos) {
            result.append(expression, cursor, std::string::npos);
            break;
        }
        const size_t end = expression.find("}}", start + 2);
        if (end == std::string::npos) {
            *out_error = "unbalanced '{{' in expression";
            return false;
        }

        result.append(expression, cursor, start - cursor);

        json value;
        if (!resolve_reference(trim(expression.substr(start + 2, end - start - 2)), context, &value,
                               out_error))
            return false;
        result.append(to_text(value));
        cursor = end + 2;
    }

    *out_value = result;
    return true;
}

}  // namespace rac::agent
