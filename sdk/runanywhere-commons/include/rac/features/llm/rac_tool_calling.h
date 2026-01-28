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

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

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
    const char* name;                         /**< Unique tool name (e.g., "get_weather") */
    const char* description;                  /**< What the tool does */
    const rac_tool_parameter_t* parameters;   /**< Array of parameters */
    size_t num_parameters;                    /**< Number of parameters */
    const char* category;                     /**< Optional category (can be NULL) */
} rac_tool_definition_t;

/**
 * @brief Parsed tool call from LLM output
 */
typedef struct rac_tool_call {
    rac_bool_t has_tool_call;        /**< Whether a tool call was found */
    char* tool_name;                 /**< Name of tool to execute (owned, must free) */
    char* arguments_json;            /**< Arguments as JSON string (owned, must free) */
    char* clean_text;                /**< Text without tool call tags (owned, must free) */
    int64_t call_id;                 /**< Unique call ID for tracking */
    rac_tool_call_format_t format;   /**< Format that was detected/used for parsing */
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
#define RAC_TOOL_CALLING_OPTIONS_DEFAULT                                                           \
    {                                                                                              \
        5,         /* max_tool_calls */                                                            \
            1,     /* auto_execute = true */                                                       \
            0.7f,  /* temperature */                                                               \
            1024,  /* max_tokens */                                                                \
            RAC_NULL, /* system_prompt */                                                          \
            0,     /* replace_system_prompt = false */                                             \
            0,     /* keep_tools_available = false */                                              \
            RAC_TOOL_FORMAT_DEFAULT /* format */                                                   \
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
 * Returns RAC_TOOL_FORMAT_AUTO if no recognizable format is found.
 *
 * @param llm_output Raw LLM output text
 * @return Detected format, or RAC_TOOL_FORMAT_AUTO if none detected
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
RAC_API rac_result_t rac_tool_call_format_prompt_with_format(const rac_tool_definition_t* definitions,
                                                             size_t num_definitions,
                                                             rac_tool_call_format_t format,
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
RAC_API rac_result_t rac_tool_call_build_followup_prompt(const char* original_user_prompt,
                                                         const char* tools_prompt,
                                                         const char* tool_name,
                                                         const char* tool_result_json,
                                                         rac_bool_t keep_tools_available,
                                                         char** out_prompt);

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

#ifdef __cplusplus
}
#endif

#endif /* RAC_TOOL_CALLING_H */
