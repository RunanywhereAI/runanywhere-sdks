/**
 * @file rac_tool_calling.h
 * @brief RunAnywhere Commons - Tool Calling API
 *
 * *** SINGLE SOURCE OF TRUTH FOR ALL TOOL CALLING LOGIC ***
 *
 * This header provides ALL tool calling functionality. Platform SDKs should
 * ONLY call these functions - no fallback implementations allowed.
 *
 * Architecture:
 * - C++ handles: ALL parsing, prompt formatting, JSON handling, follow-up prompts
 * - Platform SDKs handle ONLY: tool registry (closures), tool execution (needs platform APIs)
 *
 * Supported Tool Calling Formats:
 * - DEFAULT:  <tool_call>{"tool":"name","arguments":{}}</tool_call> (Most general models)
 * - LFM2:     <|tool_call_start|>[func(arg="val")]<|tool_call_end|> (Liquid AI models)
 *
 * Ported from:
 * - Swift: ToolCallParser.swift
 * - React Native: ToolCallingBridge.cpp
 */

#ifndef RAC_TOOL_CALLING_H
#define RAC_TOOL_CALLING_H

#include "rac_error.h"
#include "rac_proto_buffer.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TOOL CALLING FORMATS - Different models use different formats
// =============================================================================

/**
 * @brief Tool calling format identifiers
 *
 * Different LLM models use different tool calling formats. This enum allows
 * specifying which format to use for parsing and prompt generation.
 */
typedef enum rac_tool_call_format {
    /**
     * @brief SDK Default format: <tool_call>JSON</tool_call>
     *
     * Format: <tool_call>{"tool": "name", "arguments": {...}}</tool_call>
     * Used by: Most general-purpose models (Llama, Qwen, Mistral, etc.)
     */
    RAC_TOOL_FORMAT_DEFAULT = 0,

    /**
     * @brief Liquid AI LFM2-Tool format
     *
     * Format: <|tool_call_start|>[func_name(arg1="val1", arg2="val2")]<|tool_call_end|>
     * Used by: LiquidAI/LFM2-1.2B-Tool, LiquidAI/LFM2-350M-Tool
     * Note: Uses Pythonic function call syntax
     */
    RAC_TOOL_FORMAT_LFM2 = 1,

    /** Number of formats (for iteration) */
    RAC_TOOL_FORMAT_COUNT
} rac_tool_call_format_t;

// =============================================================================
// TYPES - Canonical definitions used by all SDKs
// =============================================================================

/**
 * @brief Parameter types for tool arguments
 */
typedef enum rac_tool_param_type {
    RAC_TOOL_PARAM_STRING = 0,
    RAC_TOOL_PARAM_NUMBER = 1,
    RAC_TOOL_PARAM_BOOLEAN = 2,
    RAC_TOOL_PARAM_OBJECT = 3,
    RAC_TOOL_PARAM_ARRAY = 4
} rac_tool_param_type_t;

/**
 * @brief Tool parameter definition
 */
typedef struct rac_tool_parameter {
    const char* name;           /**< Parameter name */
    rac_tool_param_type_t type; /**< Data type */
    const char* description;    /**< Human-readable description */
    rac_bool_t required;        /**< Whether required */
    const char* enum_values;    /**< JSON array of allowed values (can be NULL) */
} rac_tool_parameter_t;

/**
 * @brief Tool definition
 */
typedef struct rac_tool_definition {
    const char* name;                       /**< Unique tool name (e.g., "get_weather") */
    const char* description;                /**< What the tool does */
    const rac_tool_parameter_t* parameters; /**< Array of parameters */
    size_t num_parameters;                  /**< Number of parameters */
    const char* category;                   /**< Optional category (can be NULL) */
} rac_tool_definition_t;

/**
 * @brief Parsed tool call from LLM output
 */
typedef struct rac_tool_call {
    rac_bool_t has_tool_call;      /**< Whether a tool call was found */
    char* tool_name;               /**< Name of tool to execute (owned, must free) */
    char* arguments_json;          /**< Arguments as JSON string (owned, must free) */
    char* clean_text;              /**< Text without tool call tags (owned, must free) */
    int64_t call_id;               /**< Unique call ID for tracking */
    rac_tool_call_format_t format; /**< Format that was detected/used for parsing */
} rac_tool_call_t;

/**
 * @brief Tool calling options
 */
typedef struct rac_tool_calling_options {
    int32_t max_tool_calls;           /**< Max tool calls per turn (default: 5) */
    rac_bool_t auto_execute;          /**< Auto-execute tools (default: true) */
    float temperature;                /**< Generation temperature */
    int32_t max_tokens;               /**< Max tokens to generate */
    const char* system_prompt;        /**< Optional system prompt */
    rac_bool_t replace_system_prompt; /**< Replace vs append tool instructions */
    rac_bool_t keep_tools_available;  /**< Keep tools after first call */
    rac_tool_call_format_t format;    /**< Tool calling format (default: AUTO) */
} rac_tool_calling_options_t;

/**
 * @brief Default tool calling options
 */
#define RAC_TOOL_CALLING_OPTIONS_DEFAULT                            \
    {                                                               \
        5,                      /* max_tool_calls */                \
        1,                      /* auto_execute = true */           \
        0.7f,                   /* temperature */                   \
        1024,                   /* max_tokens */                    \
        RAC_NULL,               /* system_prompt */                 \
        0,                      /* replace_system_prompt = false */ \
        0,                      /* keep_tools_available = false */  \
        RAC_TOOL_FORMAT_DEFAULT /* format */                        \
    }

// =============================================================================
// PARSING API - Single Source of Truth (NO FALLBACKS)
// =============================================================================

/**
 * @brief Parse LLM output for tool calls (auto-detect format)
 *
 * *** THIS IS THE ONLY PARSING IMPLEMENTATION - ALL SDKS MUST USE THIS ***
 *
 * Auto-detects the tool calling format by checking for format-specific tags.
 * Handles ALL edge cases for each format.
 *
 * @param llm_output Raw LLM output text
 * @param out_result Output: Parsed result (caller must free with rac_tool_call_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out_result);

/**
 * @brief Parse LLM output for tool calls with specified format
 *
 * Parses using a specific format.
 *
 * Supported formats:
 * - RAC_TOOL_FORMAT_DEFAULT: <tool_call>JSON</tool_call>
 * - RAC_TOOL_FORMAT_LFM2: <|tool_call_start|>[func(args)]<|tool_call_end|>
 *
 * @param llm_output Raw LLM output text
 * @param format Tool calling format to use
 * @param out_result Output: Parsed result (caller must free with rac_tool_call_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_parse_with_format(const char* llm_output,
                                                     rac_tool_call_format_t format,
                                                     rac_tool_call_t* out_result);

/**
 * @brief Free tool call result
 * @param result Result to free
 */
RAC_API void rac_tool_call_free(rac_tool_call_t* result);

/**
 * @brief Get the human-readable name of a tool calling format
 *
 * @param format The format to get the name for
 * @return Static string with the format name (do not free)
 */
RAC_API const char* rac_tool_call_format_name(rac_tool_call_format_t format);

/**
 * @brief Detect which format is present in LLM output
 *
 * Checks for format-specific markers without fully parsing.
 * Returns RAC_TOOL_FORMAT_DEFAULT if no recognizable format is found.
 *
 * @param llm_output Raw LLM output text
 * @return Detected format, or RAC_TOOL_FORMAT_DEFAULT if none detected
 */
RAC_API rac_tool_call_format_t rac_tool_call_detect_format(const char* llm_output);

/**
 * @brief Convert format name string to format enum
 *
 * This is the SINGLE SOURCE OF TRUTH for valid format names.
 * SDKs should pass strings and let C++ handle the conversion.
 *
 * Valid names (case-insensitive): "default", "lfm2"
 *
 * @param name Format name string
 * @return Corresponding format enum, or RAC_TOOL_FORMAT_DEFAULT if unknown
 */
RAC_API rac_tool_call_format_t rac_tool_call_format_from_name(const char* name);

/**
 * @brief Map a runanywhere.v1.ToolCallFormatName proto enum value to its
 *        canonical runtime hint string.
 *
 * *** SINGLE SOURCE OF TRUTH for the proto-enum -> hint-string mapping. ***
 *
 * SDKs pass their generated `ToolCallFormatName` enum's integer value here and
 * forward the result as `format_hint`, instead of hand-rolling the table. The
 * returned string is always a value rac_tool_call_format_from_name() accepts
 * ("default" or "lfm2"): PYTHONIC (4) / HERMES (6) -> "lfm2"; everything else
 * -> "default".
 *
 * @param format_name runanywhere.v1.ToolCallFormatName enum value as an int32.
 * @return Static lowercase hint string (do not free).
 */
RAC_API const char* rac_tool_call_format_hint_from_format_name(int32_t format_name);

// =============================================================================
// PROMPT FORMATTING API - All prompt building happens here
// =============================================================================

/**
 * @brief Format tool definitions into system prompt (default format)
 *
 * Creates instruction text describing available tools and expected output format.
 * Uses RAC_TOOL_FORMAT_DEFAULT (<tool_call>JSON</tool_call>).
 *
 * @param definitions Array of tool definitions
 * @param num_definitions Number of definitions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t* definitions,
                                                 size_t num_definitions, char** out_prompt);

/**
 * @brief Format tool definitions with specified format
 *
 * Creates instruction text using the specified tool calling format.
 * Each format has different tag patterns and syntax instructions.
 *
 * @param definitions Array of tool definitions
 * @param num_definitions Number of definitions
 * @param format Tool calling format to use for instructions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt_with_format(
    const rac_tool_definition_t* definitions, size_t num_definitions, rac_tool_call_format_t format,
    char** out_prompt);

/**
 * @brief Format tools from JSON array string (default format)
 *
 * Convenience function when tools are provided as JSON.
 *
 * @param tools_json JSON array of tool definitions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt);

/**
 * @brief Format tools from JSON array string with specified format
 *
 * @param tools_json JSON array of tool definitions
 * @param format Tool calling format to use for instructions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt_json_with_format(const char* tools_json,
                                                                  rac_tool_call_format_t format,
                                                                  char** out_prompt);

/**
 * @brief Format tools from JSON array string with format specified by name
 *
 * *** PREFERRED API FOR SDKS - Uses string format name ***
 *
 * Valid format names (case-insensitive): "default", "lfm2"
 * Unknown names default to "default" format.
 *
 * @param tools_json JSON array of tool definitions
 * @param format_name Format name string (e.g., "lfm2", "default")
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt_json_with_format_name(const char* tools_json,
                                                                       const char* format_name,
                                                                       char** out_prompt);

/**
 * @brief Build the initial prompt with tools and user query
 *
 * Combines system prompt, tool instructions, and user prompt.
 *
 * @param user_prompt The user's question/request
 * @param tools_json JSON array of tool definitions
 * @param options Tool calling options (can be NULL for defaults)
 * @param out_prompt Output: Complete formatted prompt (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt,
                                                        const char* tools_json,
                                                        const rac_tool_calling_options_t* options,
                                                        char** out_prompt);

/**
 * @brief Build follow-up prompt after tool execution
 *
 * Creates the prompt to continue generation after a tool was executed.
 * Handles both keepToolsAvailable=true and keepToolsAvailable=false cases.
 *
 * @param original_user_prompt The original user prompt
 * @param tools_prompt The formatted tools prompt (can be NULL if not keeping tools)
 * @param tool_name Name of the tool that was executed
 * @param tool_result_json JSON string of the tool result
 * @param keep_tools_available Whether to include tool definitions in follow-up
 * @param out_prompt Output: Follow-up prompt (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_build_followup_prompt(
    const char* original_user_prompt, const char* tools_prompt, const char* tool_name,
    const char* tool_result_json, rac_bool_t keep_tools_available, char** out_prompt);

// =============================================================================
// JSON UTILITY API - All JSON handling happens here
// =============================================================================

/**
 * @brief Normalize JSON by adding quotes around unquoted keys
 *
 * Handles common LLM output patterns: {tool: "name"} → {"tool": "name"}
 *
 * @param json_str Input JSON string
 * @param out_normalized Output: Normalized JSON (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_normalize_json(const char* json_str, char** out_normalized);

/**
 * @brief Serialize tool definitions to JSON array
 *
 * @param definitions Array of tool definitions
 * @param num_definitions Number of definitions
 * @param out_json Output: JSON array string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_definitions_to_json(const rac_tool_definition_t* definitions,
                                                       size_t num_definitions, char** out_json);

/**
 * @brief Serialize a tool result to JSON
 *
 * @param tool_name Name of the tool
 * @param success Whether execution succeeded
 * @param result_json Result data as JSON (can be NULL)
 * @param error_message Error message if failed (can be NULL)
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_result_to_json(const char* tool_name, rac_bool_t success,
                                                  const char* result_json,
                                                  const char* error_message, char** out_json);

// =============================================================================
// TOOL VALUE JSON BRIDGE - Replaces hand-written per-SDK JSON serializers
// =============================================================================

/**
 * @brief Serialize a runanywhere.v1.ToolValue proto to its JSON string.
 *
 * Input bytes are a serialized runanywhere.v1.ToolValue. The output buffer
 * carries a serialized runanywhere.v1.ToolValueJSON whose `json` field holds
 * the canonical JSON text.
 */
RAC_API rac_result_t rac_tool_value_to_json_proto(
    const uint8_t* in_tool_value_bytes,
    size_t in_size,
    rac_proto_buffer_t* out_string_proto);

/**
 * @brief Parse a JSON string into a runanywhere.v1.ToolValue proto.
 *
 * Input bytes are a serialized runanywhere.v1.ToolValueJSON whose `json`
 * field carries the JSON text. The output buffer carries a serialized
 * runanywhere.v1.ToolValue derived from that text.
 */
RAC_API rac_result_t rac_tool_value_from_json_proto(
    const uint8_t* in_string_bytes,
    size_t in_size,
    rac_proto_buffer_t* out_tool_value);

// =============================================================================
// TOOL CALLING RUN LOOP - Single-call native orchestration
// =============================================================================
//
// Collapses the per-SDK generate -> parse -> validate -> execute -> follow-up
// loop into a single C ABI call. Caller provides:
//   - serialized runanywhere.v1.ToolCallingSessionCreateRequest (re-used as
//     input shape; identical fields to a hypothetical RunLoopRequest)
//   - on_execute callback that synchronously executes a tool call and
//     returns its serialized runanywhere.v1.ToolResult bytes
//
// On return, out_result carries a serialized runanywhere.v1.ToolCallingResult
// describing the final text, recorded tool calls, executed tool results,
// is_complete flag, and iterations_used counter.

/**
 * @brief Synchronous tool-execute callback used by rac_tool_calling_run_loop_proto.
 *
 * Borrowed inputs:
 *   - in_tool_call_bytes / in_size: serialized runanywhere.v1.ToolCall
 * Owned output:
 *   - out_tool_result_bytes: filled with a serialized
 *     runanywhere.v1.ToolResult (caller of the callback owns the buffer
 *     and must release it with rac_proto_buffer_free()).
 *
 * Returning anything other than RAC_SUCCESS terminates the loop and
 * surfaces a failed ToolResult with the error code in out_result.
 */
typedef rac_result_t (*rac_tool_execute_callback_fn)(
    const uint8_t* in_tool_call_bytes,
    size_t in_size,
    rac_proto_buffer_t* out_tool_result_bytes,
    void* user_data);

/**
 * @brief Run the full tool-calling loop in commons.
 *
 * Loop:
 *   1. Build initial prompt from request (tools + format + system prompt)
 *   2. Generate response via the lifecycle-owned LLM
 *   3. Parse output for a tool call
 *   4. If found and validate_calls: validate against the request's tools
 *   5. Invoke on_execute(tool_call) -> tool_result
 *   6. Build follow-up prompt and loop
 *   7. Stop when no tool call found, max_iterations reached, or error
 *
 * @param in_request_bytes    Borrowed serialized
 *                            runanywhere.v1.ToolCallingSessionCreateRequest.
 * @param in_size             Size of in_request_bytes.
 * @param on_execute          Synchronous tool-execute callback.
 * @param user_data           Opaque pointer forwarded to on_execute.
 * @param out_result          Owned serialized
 *                            runanywhere.v1.ToolCallingResult on success.
 * @return RAC_SUCCESS when out_result carries a serialized result; a negative
 *         rac_result_t on failure (out_result also carries the status text).
 */
RAC_API rac_result_t rac_tool_calling_run_loop_proto(
    const uint8_t* in_request_bytes,
    size_t in_size,
    rac_tool_execute_callback_fn on_execute,
    void* user_data,
    rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TOOL_CALLING_H */
