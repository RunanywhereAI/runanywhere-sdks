// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tool-calling output parser. Ports the parsing subset of
// `sdk/runanywhere-commons/include/rac/features/llm/rac_tool_calling.h`
// into C++20 / std::string. Prompt-formatting helpers are intentionally
// left out — frontends that need them build prompts at the Swift/Kotlin
// layer today.
//
// Supported formats:
//   kDefault: <tool_call>{"tool":"name","arguments":{...}}</tool_call>
//             (Llama, Qwen, Mistral, etc.)
//   kLFM2:    <|tool_call_start|>[func_name(arg="val")]<|tool_call_end|>
//             (LiquidAI LFM2-1.2B-Tool, LFM2-350M-Tool)

#ifndef RA_CORE_TOOL_CALLING_H
#define RA_CORE_TOOL_CALLING_H

#include <optional>
#include <string>
#include <string_view>

namespace ra::core::util {

enum class ToolCallFormat {
    kDefault = 0,
    kLFM2    = 1,
};

struct ParsedToolCall {
    bool           has_call = false;
    std::string    tool_name;          // Extracted function name
    std::string    arguments_json;     // Arguments serialized to JSON
    std::string    clean_text;         // Input with tool-call tags removed
    ToolCallFormat format = ToolCallFormat::kDefault;
};

// Detect which format is present in `llm_output`. Returns kDefault if no
// recognizable tags are seen (callers should treat that as "no tool call").
ToolCallFormat detect_tool_call_format(std::string_view llm_output);

// Parse using a specific format. Returns a populated struct; when no tool
// call is found, has_call=false and clean_text mirrors the input.
ParsedToolCall parse_tool_call(std::string_view llm_output,
                                ToolCallFormat   format);

// Convenience: auto-detect format, then parse.
ParsedToolCall parse_tool_call(std::string_view llm_output);

// Format name ↔ enum mapping. Unknown names default to kDefault.
ToolCallFormat tool_call_format_from_name(std::string_view name);
std::string_view tool_call_format_name(ToolCallFormat format);

}  // namespace ra::core::util

#endif  // RA_CORE_TOOL_CALLING_H
