/**
 * @file json_schema_to_gbnf.cpp
 * @brief JSON Schema → GBNF compiler (commons-owned).
 *
 * Port of bindings/python/runanywhere/grammar.py /
 * bindings/electron/src/grammar.ts so platform SDKs pass schema and
 * commons constrains decoding. Deterministic output matching those ports.
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <nlohmann/json.hpp>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "features/llm/json_schema_to_gbnf_internal.h"

namespace rac::llm {
namespace {

using nlohmann::json;

const char* kPrimitiveWs = "ws ::= [ \\t\\n]*";
const char* kPrimitiveString =
    "string ::= \"\\\"\" ( [^\"\\\\] | \"\\\\\" [\"\\\\/bfnrt] )* \"\\\"\"";
const char* kPrimitiveInteger = "integer ::= \"-\"? ( \"0\" | [1-9] [0-9]* )";
const char* kPrimitiveNumber =
    "number ::= \"-\"? ( \"0\" | [1-9] [0-9]* ) ( \".\" [0-9]+ )? ( [eE] [-+]? [0-9]+ )?";
const char* kPrimitiveBoolean = "boolean ::= \"true\" | \"false\"";

std::string lit(const std::string& s) {
    std::string out = "\"";
    for (char c : s) {
        if (c == '\\' || c == '"') {
            out.push_back('\\');
        }
        out.push_back(c);
    }
    out.push_back('"');
    return out;
}

// Match JS JSON.stringify for scalar const/enum values: integer-valued floats
// render without ".0", and non-ASCII is not escaped.
std::string json_stringify_scalar(const json& v) {
    if (v.is_number_float()) {
        const double d = v.get<double>();
        if (std::isfinite(d) && std::floor(d) == d) {
            return json(static_cast<std::int64_t>(d)).dump();
        }
    }
    return v.dump(-1, ' ', false, json::error_handler_t::replace);
}

struct Builder {
    std::vector<std::string> rules;
    // Insertion-ordered membership (mirrors JS Set / Python dict).
    std::map<std::string, int> used_order;
    int used_seq = 0;
    int counter = 0;

    void mark_used(const char* name) {
        if (used_order.find(name) == used_order.end()) {
            used_order.emplace(name, used_seq++);
        }
    }

    std::string build(const json& s) {
        if (!s.is_object()) {
            mark_used("string");
            return "string";
        }
        if (s.contains("anyOf") && s["anyOf"].is_array() && !s["anyOf"].empty()) {
            const std::string name = "any" + std::to_string(counter++);
            std::ostringstream rhs;
            bool first = true;
            for (const auto& sub : s["anyOf"]) {
                if (!first) {
                    rhs << " | ";
                }
                first = false;
                rhs << build(sub);
            }
            rules.push_back(name + " ::= " + rhs.str());
            return name;
        }
        if (s.contains("const")) {
            const std::string name = "const" + std::to_string(counter++);
            rules.push_back(name + " ::= " + lit(json_stringify_scalar(s["const"])));
            return name;
        }
        if (s.contains("enum") && s["enum"].is_array() && !s["enum"].empty()) {
            const std::string name = "enum" + std::to_string(counter++);
            std::ostringstream rhs;
            bool first = true;
            for (const auto& v : s["enum"]) {
                if (!first) {
                    rhs << " | ";
                }
                first = false;
                rhs << lit(json_stringify_scalar(v));
            }
            rules.push_back(name + " ::= " + rhs.str());
            return name;
        }

        const std::string type = s.value("type", "");
        if (type == "object") {
            json props = json::object();
            if (s.contains("properties") && s["properties"].is_object()) {
                props = s["properties"];
            }
            const std::string name = "obj" + std::to_string(counter++);
            mark_used("ws");
            if (props.empty()) {
                rules.push_back(name + " ::= \"{\" ws \"}\"");
                return name;
            }
            std::ostringstream parts;
            bool first = true;
            for (auto it = props.begin(); it != props.end(); ++it) {
                if (!first) {
                    parts << " ws \",\" ws ";
                }
                first = false;
                parts << lit(std::string("\"") + it.key() + "\"") << " ws \":\" ws "
                      << build(it.value());
            }
            rules.push_back(name + " ::= \"{\" ws " + parts.str() + " ws \"}\"");
            return name;
        }

        if (type == "array") {
            std::string item = "string";
            if (s.contains("items")) {
                item = build(s["items"]);
            } else {
                mark_used("string");
            }
            const std::string name = "arr" + std::to_string(counter++);
            mark_used("ws");

            int max_items = -1;
            if (s.contains("maxItems") && s["maxItems"].is_number() &&
                !s["maxItems"].is_boolean()) {
                max_items = static_cast<int>(std::floor(s["maxItems"].get<double>()));
            }
            if (max_items < 0) {
                rules.push_back(name + " ::= \"[\" ws ( " + item + " ( ws \",\" ws " + item +
                                " )* )? ws \"]\"");
            } else if (max_items <= 0) {
                rules.push_back(name + " ::= \"[\" ws \"]\"");
            } else {
                std::string prev;
                for (int k = 1; k <= max_items; ++k) {
                    const std::string tn = name + "t" + std::to_string(k);
                    if (k == 1) {
                        rules.push_back(tn + " ::= " + item);
                    } else {
                        rules.push_back(tn + " ::= " + item + " ( ws \",\" ws " + prev + " )?");
                    }
                    prev = tn;
                }
                rules.push_back(name + " ::= \"[\" ws ( " + prev + " )? ws \"]\"");
            }
            return name;
        }

        if (type == "integer") {
            mark_used("integer");
            return "integer";
        }
        if (type == "number") {
            mark_used("number");
            return "number";
        }
        if (type == "boolean") {
            mark_used("boolean");
            return "boolean";
        }
        if (type == "null") {
            return "\"null\"";
        }
        mark_used("string");
        return "string";
    }

    std::string finish(const std::string& root) {
        std::ostringstream out;
        out << "root ::= " << root;
        for (const auto& rule : rules) {
            out << '\n' << rule;
        }
        std::vector<std::pair<int, std::string>> ordered;
        ordered.reserve(used_order.size());
        for (const auto& kv : used_order) {
            ordered.emplace_back(kv.second, kv.first);
        }
        std::sort(ordered.begin(), ordered.end());
        for (const auto& kv : ordered) {
            out << '\n';
            if (kv.second == "ws") {
                out << kPrimitiveWs;
            } else if (kv.second == "string") {
                out << kPrimitiveString;
            } else if (kv.second == "integer") {
                out << kPrimitiveInteger;
            } else if (kv.second == "number") {
                out << kPrimitiveNumber;
            } else if (kv.second == "boolean") {
                out << kPrimitiveBoolean;
            }
        }
        return out.str();
    }
};

}  // namespace

bool json_schema_to_gbnf(const std::string& schema_json, std::string* out_grammar,
                         std::string* out_error) {
    if (!out_grammar) {
        if (out_error) {
            *out_error = "out_grammar is null";
        }
        return false;
    }
    json schema = json::parse(schema_json, nullptr, false);
    if (schema.is_discarded()) {
        if (out_error) {
            *out_error = "schema is not valid JSON";
        }
        return false;
    }
    Builder b;
    const std::string root = b.build(schema);
    *out_grammar = b.finish(root);
    return true;
}

std::string structured_output_repair_prompt(const std::string& original_prompt,
                                            const std::string& invalid_output,
                                            const std::string& schema_json) {
    return original_prompt +
           "\n\nYour previous answer did not match the required JSON schema. "
           "Reply again with ONLY JSON that satisfies this schema.\n\nSchema: " +
           schema_json + "\nPrevious invalid answer: " + invalid_output;
}

}  // namespace rac::llm
