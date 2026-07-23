#include "features/llm/tool_calling_grammar.h"

#include <sstream>
#include <vector>

namespace rac::llm::tool_calling {

#if defined(RAC_HAVE_PROTOBUF)

namespace {

// Escapes a string for use inside a GBNF double-quoted literal ("...").
// Tool names are developer-declared identifiers in practice, but this stays
// defensive rather than assuming well-formed input reaches here.
std::string escape_gbnf_literal(const std::string& raw) {
    std::string out;
    out.reserve(raw.size());
    for (char c : raw) {
        if (c == '"' || c == '\\') {
            out.push_back('\\');
        }
        out.push_back(c);
    }
    return out;
}

// A permissive GBNF production for an arbitrary JSON value — this is what
// "arguments" decodes against. Argument SHAPE is intentionally
// unconstrained in this pass (TC-1 only constrains tool name + envelope,
// not per-parameter argument shape — see tool_calling_grammar.h). Mirrors
// the standard permissive JSON grammar shipped as llama.cpp's own
// grammars/json.gbnf, inlined here (not as a separate root) so it can be
// referenced from the tool-call root built below.
constexpr const char* kJsonValueRules =
    "ws ::= [ \\t\\n]*\n"
    "value ::= object | array | string | number | (\"true\" | \"false\" | \"null\")\n"
    "object ::= \"{\" ws (member (ws \",\" ws member)*)? ws \"}\"\n"
    "member ::= string ws \":\" ws value\n"
    "array ::= \"[\" ws (value (ws \",\" ws value)*)? ws \"]\"\n"
    "string ::= \"\\\"\" ([^\"\\\\\\x00-\\x1f] | \"\\\\\" ([\"\\\\/bfnrt] | \"u\" [0-9a-fA-F]"
    "[0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]))* \"\\\"\"\n"
    "number ::= \"-\"? (\"0\" | [1-9] [0-9]*) (\".\" [0-9]+)? ([eE] [+-]? [0-9]+)?\n";

}  // namespace

ToolCallGrammar build_tool_call_grammar(const runanywhere::v1::ToolCallingOptions& tool_options,
                                        bool has_tool_choice,
                                        runanywhere::v1::ToolChoiceMode tool_choice,
                                        const std::string& forced_tool_name, bool parallel) {
    ToolCallGrammar result;
    if (tool_options.tools_size() == 0) {
        return result;
    }
    if (has_tool_choice && tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_NONE) {
        return result;
    }

    // Determine the live tool-name set this generation step may call.
    const bool is_specific = has_tool_choice &&
                             tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_SPECIFIC &&
                             !forced_tool_name.empty();
    std::vector<std::string> names;
    if (is_specific) {
        names.push_back(forced_tool_name);
    } else {
        for (const auto& tool : tool_options.tools()) {
            names.push_back(tool.name());
        }
    }
    if (names.empty()) {
        return result;
    }

    const bool must_call =
        is_specific ||
        (has_tool_choice && tool_choice == runanywhere::v1::TOOL_CHOICE_MODE_REQUIRED);

    // --- qhexrt dialect: the native toolcall:/toolcall_opt: GrammarKinds
    // already do exactly this at the engine level (qhexrt_llm_ops.cpp), so
    // this half needs no grammar authoring — just the prefix + comma-joined
    // name list.
    {
        std::ostringstream joined;
        for (size_t i = 0; i < names.size(); ++i) {
            if (i > 0) {
                joined << ",";
            }
            joined << names[i];
        }
        result.qhexrt = (must_call ? "toolcall:" : "toolcall_opt:") + joined.str();
    }

    // --- llamacpp (GBNF) dialect: only constrain when the model is already
    // committed to calling a tool (REQUIRED/SPECIFIC). AUTO is left
    // unconstrained on this engine — GBNF has no clean "structured tool call
    // OR free natural-language text" root, so forcing one here would corrupt
    // ordinary chat responses; qhexrt's native toolcall_opt kind covers the
    // AUTO case on that engine instead.
    if (must_call) {
        // `call`: the fixed <tool_call>{"tool":...,"arguments":{...}}</tool_call>
        // envelope with exactly two free choices — which tool name, and what
        // the arguments object contains. Each quoted fragment below is a GBNF
        // string literal matched verbatim against the output text; `tool-name`
        // and `object` are rule references (defined below / in kJsonValueRules).
        // Concatenated, `call` produces exactly:
        //   <tool_call>{"tool":"<name>","arguments":<object>}</tool_call>
        //
        // `root` is `call` for a single required call, or `call+` when the
        // caller opted into parallel_tool_calls — letting the model emit
        // several back-to-back envelopes in one grammar-constrained
        // generation instead of being capped at exactly one by the grammar
        // itself (the parser's own duplicate-call guard still applies on
        // top of whatever the grammar allows through).
        std::ostringstream gbnf;
        gbnf << "root ::= " << (parallel ? "call+" : "call") << "\n";
        gbnf
            << R"(call ::= "<tool_call>{\"tool\":" tool-name ",\"arguments\":" object "}</tool_call>")"
            << "\n";

        // tool-name ::= "\"nameA\"" | "\"nameB\"" | ...
        // Each alternative is a GBNF literal that matches the tool name
        // WITH its surrounding quote characters (so the concatenation above
        // doesn't need to add them). R"(" \")" / R"(\"")" are raw strings —
        // no C++ escaping — so they read as the literal GBNF text `"\"` and
        // `\""` respectively.
        gbnf << "tool-name ::= ";
        for (size_t i = 0; i < names.size(); ++i) {
            if (i > 0) {
                gbnf << " | ";
            }
            gbnf << R"("\")" << escape_gbnf_literal(names[i]) << R"(\"")";
        }
        gbnf << "\n";

        // `object` (not the looser `value`) keeps "arguments" to a JSON
        // object, matching ToolCall.arguments_json's documented contract
        // ("JSON-encoded arguments... Empty object {} if no args").
        gbnf << kJsonValueRules;
        result.gbnf = gbnf.str();
    }

    return result;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::llm::tool_calling
