// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — tool-calling C ABI.
//
// Wraps the C++ parser in `core/util/tool_calling.{h,cpp}` so frontends
// (Swift/Kotlin/Dart/TS/Web) can detect, parse and format LLM tool-call
// payloads without re-implementing the parsing logic in every language.
//
// Ports the legacy `rac_tool_calling.h` capability surface onto the new
// `ra_*` C ABI shape. Strings returned in out-params are heap-allocated
// and MUST be freed with `ra_tool_string_free`.

#ifndef RA_TOOL_H
#define RA_TOOL_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Tool-call format enum (matches ra::core::util::ToolCallFormat)
// ---------------------------------------------------------------------------
typedef int32_t ra_tool_call_format_t;
enum {
    RA_TOOL_CALL_FORMAT_DEFAULT = 0,   // <tool_call>{...}</tool_call>
    RA_TOOL_CALL_FORMAT_LFM2    = 1,   // <|tool_call_start|>[func(...)]<|...|>
};

// ---------------------------------------------------------------------------
// Parsed tool-call output. All char* fields are heap-allocated and owned by
// the struct; release with `ra_tool_call_free`.
// ---------------------------------------------------------------------------
typedef struct {
    uint8_t                has_call;        // 0/1
    uint8_t                _reserved0[3];
    char*                  tool_name;       // Function name (may be NULL)
    char*                  arguments_json;  // Arguments JSON (may be NULL)
    char*                  clean_text;      // Original text minus tool tags
    ra_tool_call_format_t  format;
} ra_tool_call_t;

// Parameter descriptor for outgoing tool-definition prompts.
typedef struct {
    const char* name;
    const char* type;          // "string" | "number" | "integer" | "boolean" | "object" | "array"
    const char* description;
    uint8_t     required;      // 0/1
    uint8_t     _reserved0[3];
} ra_tool_parameter_t;

// Tool definition (function-call style).
typedef struct {
    const char*                name;
    const char*                description;
    const ra_tool_parameter_t* parameters;
    int32_t                    parameter_count;
} ra_tool_definition_t;

// Frontend-supplied options for tool-call prompt formatting.
typedef struct {
    ra_tool_call_format_t format;
    uint8_t               include_examples;   // 0/1
    uint8_t               strict_mode;        // 0/1 — refuse non-tool answers
    uint8_t               _reserved0[2];
} ra_tool_calling_options_t;

// ---------------------------------------------------------------------------
// Detection + parsing
// ---------------------------------------------------------------------------

// Auto-detect format from text. Returns RA_TOOL_CALL_FORMAT_DEFAULT when
// nothing recognizable is found.
ra_tool_call_format_t ra_tool_call_detect_format(const char* llm_output);

// Parse using auto-detection. Caller MUST free the result with
// `ra_tool_call_free`.
ra_status_t ra_tool_call_parse(const char* llm_output, ra_tool_call_t* out_call);

// Parse using a specific format. Caller MUST free with `ra_tool_call_free`.
ra_status_t ra_tool_call_parse_with_format(const char*           llm_output,
                                            ra_tool_call_format_t format,
                                            ra_tool_call_t*       out_call);

// Free heap-allocated strings inside a `ra_tool_call_t`. Safe to call on a
// zero-initialised struct; idempotent.
void ra_tool_call_free(ra_tool_call_t* call);

// ---------------------------------------------------------------------------
// Format identification helpers
// ---------------------------------------------------------------------------

// Returns a static string ("default" | "lfm2") naming the format. Never NULL.
const char* ra_tool_call_format_name(ra_tool_call_format_t format);

// Returns the format enum that matches the given name. Unknown names
// resolve to RA_TOOL_CALL_FORMAT_DEFAULT.
ra_tool_call_format_t ra_tool_call_format_from_name(const char* name);

// ---------------------------------------------------------------------------
// Prompt building (heap-allocated UTF-8 strings, free with ra_tool_string_free)
// ---------------------------------------------------------------------------

// Build the system prompt that exposes the supplied tool definitions to the
// LLM. The exact template depends on `format`. `out_prompt` is heap-allocated.
ra_status_t ra_tool_call_format_prompt(const ra_tool_definition_t* tools,
                                        int32_t                     tool_count,
                                        ra_tool_call_format_t       format,
                                        char**                      out_prompt);

// Same, but tool definitions are supplied as a single JSON array.
ra_status_t ra_tool_call_format_prompt_json(const char*           tools_json,
                                             ra_tool_call_format_t format,
                                             char**                out_prompt);

// Build the initial user-turn prompt: combines a system tool description
// with the user query in the format expected by `format`.
ra_status_t ra_tool_call_build_initial_prompt(const ra_tool_definition_t* tools,
                                                int32_t                    tool_count,
                                                const char*                user_query,
                                                ra_tool_call_format_t      format,
                                                char**                     out_prompt);

// Build a follow-up prompt to feed back tool execution results so the LLM
// can synthesize a final answer. `result_json` is the JSON-serialised tool
// output.
ra_status_t ra_tool_call_build_followup_prompt(const char*           tool_name,
                                                 const char*           result_json,
                                                 ra_tool_call_format_t format,
                                                 char**                out_prompt);

// Normalise an arguments JSON string (whitespace, key ordering). Always
// produces canonical JSON suitable for hashing / deduping. Heap-allocated.
ra_status_t ra_tool_call_normalize_json(const char* arguments_json,
                                         char**      out_normalized);

// Serialise a `ra_tool_call_t` (post-parse) back to JSON for round-tripping.
ra_status_t ra_tool_call_to_json(const ra_tool_call_t* call, char** out_json);

// Serialise an array of tool definitions to JSON.
ra_status_t ra_tool_definitions_to_json(const ra_tool_definition_t* tools,
                                         int32_t                     tool_count,
                                         char**                      out_json);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------

// Release a heap-allocated string returned by any helper above. Safe on NULL.
void ra_tool_string_free(char* str);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_TOOL_H
