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
 * Ported from:
 * - Swift: ToolCallParser.swift
 * - React Native: ToolCallingBridge.cpp
 */

#ifndef RAC_TOOL_CALLING_H
#define RAC_TOOL_CALLING_H

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

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
    rac_bool_t has_tool_call;   /**< Whether a tool call was found */
    char* tool_name;            /**< Name of tool to execute (owned, must free) */
    char* arguments_json;       /**< Arguments as JSON string (owned, must free) */
    char* clean_text;           /**< Text without tool call tags (owned, must free) */
    int64_t call_id;            /**< Unique call ID for tracking */
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
            0      /* keep_tools_available = false */                                              \
    }

// =============================================================================
// PARSING API - Single Source of Truth (NO FALLBACKS)
// =============================================================================

/**
 * @brief Parse LLM output for tool calls
 *
 * *** THIS IS THE ONLY PARSING IMPLEMENTATION - ALL SDKS MUST USE THIS ***
 *
 * Looks for <tool_call>JSON</tool_call> pattern in output.
 * Handles ALL edge cases:
 * - Missing closing tags (brace-matching)
 * - Unquoted JSON keys ({tool: "name"} → {"tool": "name"})
 * - Multiple key naming conventions ("tool"/"name"/"function", "arguments"/"params"/"input")
 * - Placeholder keys with tool name as value
 * - Tool name as key pattern
 *
 * @param llm_output Raw LLM output text
 * @param out_result Output: Parsed result (caller must free with rac_tool_call_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out_result);

/**
 * @brief Free tool call result
 * @param result Result to free
 */
RAC_API void rac_tool_call_free(rac_tool_call_t* result);

// =============================================================================
// PROMPT FORMATTING API - All prompt building happens here
// =============================================================================

/**
 * @brief Format tool definitions into system prompt
 *
 * Creates instruction text describing available tools and expected output format.
 * Includes:
 * - Tool descriptions and parameters
 * - <tool_call> format instructions
 * - Example usage
 * - Rules for when to use tools
 *
 * @param definitions Array of tool definitions
 * @param num_definitions Number of definitions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t* definitions,
                                                 size_t num_definitions, char** out_prompt);

/**
 * @brief Format tools from JSON array string
 *
 * Convenience function when tools are provided as JSON.
 *
 * @param tools_json JSON array of tool definitions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt);

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
