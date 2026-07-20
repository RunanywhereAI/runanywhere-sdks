/**
 * @file tool_calling_grammar.h
 * @brief TC-1: derives grammar-constrained-decoding specs for the tool-calling
 * run-loop from the live tool set + tool_choice policy.
 *
 * Two independent dialects because llamacpp and qhexrt read
 * rac_llm_options_t.grammar with incompatible conventions — see
 * tool_calling_generation_internal.h::GenerationState for the split and
 * engines/llamacpp/llamacpp_backend.cpp / engines/qhexrt/qhexrt_llm_ops.cpp
 * for how each engine consumes its dialect. Scoped to the default JSON
 * <tool_call>{"tool":...,"arguments":{...}}</tool_call> wire format
 * (tool_calling.cpp's TAG_DEFAULT_START path) — callers must leave this
 * empty for the LFM2 wire format, which keeps today's post-hoc validation.
 */

#ifndef RAC_FEATURES_LLM_TOOL_CALLING_GRAMMAR_H
#define RAC_FEATURES_LLM_TOOL_CALLING_GRAMMAR_H

#include <string>

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace rac::llm::tool_calling {

#if defined(RAC_HAVE_PROTOBUF)

struct ToolCallGrammar {
    // llama.cpp dialect (raw GBNF, root rule name "root"). Empty = run
    // unconstrained on this engine.
    std::string gbnf;
    // qhexrt dialect (kind-prefixed spec: "toolcall:<names>" /
    // "toolcall_opt:<names>"). Empty = run unconstrained on this engine.
    std::string qhexrt;
};

// Builds the grammar pair that constrains the model to emit ONLY a
// tool-name-and-envelope-valid tool call from `tool_options.tools()` (or
// just `forced_tool_name` under TOOL_CHOICE_MODE_SPECIFIC). Tool argument
// *shapes* are left unconstrained (permissive JSON object) — full
// per-parameter JSON-Schema-driven argument grammar is separate follow-up
// work (see the source doc's gso-1/D02).
//
// Returns an all-empty ToolCallGrammar when tool_options.tools() is empty
// or tool_choice == NONE (matches today's unconstrained behavior).
ToolCallGrammar build_tool_call_grammar(const runanywhere::v1::ToolCallingOptions& tool_options,
                                        bool has_tool_choice,
                                        runanywhere::v1::ToolChoiceMode tool_choice,
                                        const std::string& forced_tool_name);

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_CALLING_GRAMMAR_H
