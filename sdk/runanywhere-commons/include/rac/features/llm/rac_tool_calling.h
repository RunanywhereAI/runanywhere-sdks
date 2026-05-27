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
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - Proto-byte APIs (rac_tool_call_parse_proto,
 *     rac_tool_call_validate_proto, rac_tool_call_format_prompt_proto):
 *     `SDK-facing default` over runanywhere.v1.ToolParseRequest /
 *     ToolParseResult / ToolCallValidationRequest /
 *     ToolCallValidationResult / ToolPromptFormatRequest /
 *     ToolPromptFormatResult bytes.
 *   - Struct/JSON helpers (rac_tool_call_t, rac_tool_definition_t,
 *     rac_tool_call_validation_t, rac_tool_calling_options_t, parse,
 *     validate, format, normalize, definitions_to_json, etc.):
 *     `delete after SDK migration` for SDK-facing helpers; `internal`
 *     for parser primitives once SDKs are on the proto path.
 */

#ifndef RAC_TOOL_CALLING_H
#define RAC_TOOL_CALLING_H

#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

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
 * @brief Tool call validation result
 *
 * Mirrors the portable parts of the generated ToolCallValidationResult
 * contract without depending on generated headers in the C ABI.
 */
typedef struct rac_tool_call_validation {
    rac_bool_t is_valid;             /**< Whether the call matches a known tool definition */
    char* validation_errors_json;    /**< JSON array of validation error strings (owned) */
    char* matched_tool_json;         /**< Matched tool definition as JSON object (owned) */
    char* normalized_arguments_json; /**< Canonical arguments JSON object (owned) */
    char* error_message;             /**< First validation error, if any (owned) */
    rac_result_t error_code;         /**< RAC_SUCCESS or a validation error code */
} rac_tool_call_validation_t;

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
 * @brief Parse tool calls from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.ToolParseRequest and returns a serialized
 * runanywhere.v1.ToolParseResult in out_result. This keeps SDK bridges from
 * hand-parsing protobuf wire bytes while preserving C++ as the portable parser.
 *
 * @param request_proto_bytes Borrowed ToolParseRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned ToolParseResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_tool_call_parse_proto(const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result);

/**
 * @brief Validate a parsed tool call against local tool definitions
 *
 * Checks that the parsed call names a known tool, has valid JSON object
 * arguments, includes all required parameters, uses the expected parameter
 * types, and respects enum constraints when provided.
 *
 * This does not execute tools or perform permission checks. Host adapters own
 * execution and side effects.
 *
 * @param call Parsed tool call
 * @param definitions Array of allowed tool definitions
 * @param num_definitions Number of definitions
 * @param out_validation Output validation result (free with rac_tool_call_validation_free)
 * @return RAC_SUCCESS on successful validation processing
 */
RAC_API rac_result_t rac_tool_call_validate(const rac_tool_call_t* call,
                                            const rac_tool_definition_t* definitions,
                                            size_t num_definitions,
                                            rac_tool_call_validation_t* out_validation);

/**
 * @brief Validate a parsed tool call against JSON tool definitions
 *
 * Convenience API for adapters that already hold tools as JSON. Supports the
 * same shape produced by rac_tool_call_definitions_to_json and generated-style
 * ToolDefinition JSON objects.
 *
 * @param call Parsed tool call
 * @param tools_json JSON array of tool definitions
 * @param out_validation Output validation result (free with rac_tool_call_validation_free)
 * @return RAC_SUCCESS on successful validation processing
 */
RAC_API rac_result_t rac_tool_call_validate_json(const rac_tool_call_t* call,
                                                 const char* tools_json,
                                                 rac_tool_call_validation_t* out_validation);

/**
 * @brief Validate a tool call from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.ToolCallValidationRequest and returns a serialized
 * runanywhere.v1.ToolCallValidationResult in out_result. This keeps SDK
 * bridges on generated protobuf contracts while C++ owns portable validation.
 *
 * @param request_proto_bytes Borrowed ToolCallValidationRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned ToolCallValidationResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_tool_call_validate_proto(const uint8_t* request_proto_bytes,
                                                  size_t request_proto_size,
                                                  rac_proto_buffer_t* out_result);

/**
 * @brief Free tool call validation result
 * @param validation Validation result to free
 */
RAC_API void rac_tool_call_validation_free(rac_tool_call_validation_t* validation);

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
 * @brief Derive the tool-call format from a serialized RAModelInfo.
 *
 * CONSOLIDATE-A canonical replacement for per-example heuristics like Swift's
 * `LLMViewModel.detectToolCallFormat(for:)`, Flutter's
 * `_detectToolCallFormat()`, Kotlin's `ToolSettingsViewModel.detectToolCallFormat()`,
 * and the React Native equivalent. Every example was duplicating the same
 * `name.contains("lfm2") && name.contains("tool")` mapping; this commons-owned
 * accessor centralizes the rule so SDKs derive the format from `RAModelInfo`
 * proto bytes and example apps never reach into model-naming conventions.
 *
 * Inspection rule (case-insensitive on `name`, `id`, and `description`):
 *   - LiquidAI LFM2-Tool family (e.g. "LFM2-1.2B-Tool", "LFM2-350M-Tool") →
 *     RAC_TOOL_FORMAT_LFM2 (Pythonic <|tool_call_start|>...<|tool_call_end|>).
 *   - Anything else → RAC_TOOL_FORMAT_DEFAULT (JSON-tagged <tool_call>…</tool_call>).
 *
 * Empty / NULL model_info_proto_bytes (size==0) is accepted and returns
 * RAC_TOOL_FORMAT_DEFAULT — examples occasionally call the helper while the
 * model registry is empty.
 *
 * @param model_info_proto_bytes Borrowed runanywhere.v1.ModelInfo bytes (may
 *                               be NULL when @p size is 0).
 * @param size                   Byte count of @p model_info_proto_bytes.
 * @param out_format             Output: derived tool-call format. Must not be
 *                               NULL. Set to RAC_TOOL_FORMAT_DEFAULT on
 *                               recoverable failures (empty/invalid bytes).
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER when @p out_format is
 *         NULL, RAC_ERROR_DECODING_ERROR when the bytes do not parse as
 *         runanywhere.v1.ModelInfo.
 */
RAC_API rac_result_t rac_tool_call_format_from_model_info_proto(
    const uint8_t* model_info_proto_bytes, size_t size, rac_tool_call_format_t* out_format);

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
 *
 * @internal Classification: `delete after SDK migration` (see
 *           docs/CPP_PROTO_OWNERSHIP.md). Kept for commons-internal use by
 *           `rac_tool_call_format_prompt_proto` and the RAG pipeline. SDKs
 *           must call `rac_tool_call_format_prompt_proto` instead.
 */
rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt);

/**
 * @brief Format tools from JSON array string with specified format
 *
 * @param tools_json JSON array of tool definitions
 * @param format Tool calling format to use for instructions
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           only. SDKs must call `rac_tool_call_format_prompt_proto`.
 */
rac_result_t rac_tool_call_format_prompt_json_with_format(const char* tools_json,
                                                          rac_tool_call_format_t format,
                                                          char** out_prompt);

/**
 * @brief Format tools from JSON array string with format specified by name
 *
 * Valid format names (case-insensitive): "default", "lfm2"
 * Unknown names default to "default" format.
 *
 * @param tools_json JSON array of tool definitions
 * @param format_name Format name string (e.g., "lfm2", "default")
 * @param out_prompt Output: Allocated prompt string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           only. SDKs must call `rac_tool_call_format_prompt_proto`.
 */
rac_result_t rac_tool_call_format_prompt_json_with_format_name(const char* tools_json,
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
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           only. SDKs should compose the prompt through
 *           `rac_tool_call_format_prompt_proto`.
 */
rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt, const char* tools_json,
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
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           only. SDKs should maintain tool-calling sessions through
 *           `rac_tool_call_*_proto`.
 */
rac_result_t rac_tool_call_build_followup_prompt(const char* original_user_prompt,
                                                 const char* tools_prompt, const char* tool_name,
                                                 const char* tool_result_json,
                                                 rac_bool_t keep_tools_available,
                                                 char** out_prompt);

/**
 * @brief Format tool prompts from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.ToolPromptFormatRequest and returns a serialized
 * runanywhere.v1.ToolPromptFormatResult in out_result. Native/Web SDKs should
 * pass generated request bytes through to this API instead of duplicating
 * protobuf parsing, tool-definition JSON conversion, or prompt-building logic.
 *
 * @param request_proto_bytes Borrowed ToolPromptFormatRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned ToolPromptFormatResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_tool_call_format_prompt_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

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
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           helper used by `rac_tool_call_parse`; SDKs consume normalized
 *           arguments via the `_proto` family.
 */
rac_result_t rac_tool_call_normalize_json(const char* json_str, char** out_normalized);

/**
 * @brief Serialize tool definitions to JSON array
 *
 * @param definitions Array of tool definitions
 * @param num_definitions Number of definitions
 * @param out_json Output: JSON array string (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           helper; SDKs should use generated proto messages.
 */
rac_result_t rac_tool_call_definitions_to_json(const rac_tool_definition_t* definitions,
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
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           helper; SDKs should use generated proto messages.
 */
rac_result_t rac_tool_call_result_to_json(const char* tool_name, rac_bool_t success,
                                          const char* result_json, const char* error_message,
                                          char** out_json);

// =============================================================================
// TOOL VALUE JSON BRIDGE (G3) - Replaces hand-written per-SDK JSON serializers
// =============================================================================
//
// SDKs treat ToolValue (the recursive JSON-typed carrier defined in
// idl/tool_calling.proto) as JSON when crossing the user-facing surface:
// arguments_json / result_json are JSON strings. Every SDK previously
// reimplemented the recursive walk over the ToolValue oneof to/from JSON.
// These two ABIs move that walk into commons.

/**
 * @brief Serialize a runanywhere.v1.ToolValue proto to its JSON string.
 *
 * Input bytes are a serialized runanywhere.v1.ToolValue. The output buffer
 * carries a serialized runanywhere.v1.ToolValueJSON whose `json` field holds
 * the canonical JSON text.
 *
 * @param in_tool_value_bytes Borrowed serialized ToolValue bytes.
 * @param in_size             Size of in_tool_value_bytes.
 * @param out_string_proto    Owned serialized ToolValueJSON on success.
 * @return RAC_SUCCESS when out_string_proto carries a serialized result.
 */
RAC_API rac_result_t rac_tool_value_to_json_proto(const uint8_t* in_tool_value_bytes,
                                                  size_t in_size,
                                                  rac_proto_buffer_t* out_string_proto);

/**
 * @brief Parse a JSON string into a runanywhere.v1.ToolValue proto.
 *
 * Input bytes are a serialized runanywhere.v1.ToolValueJSON whose `json`
 * field carries the JSON text. The output buffer carries a serialized
 * runanywhere.v1.ToolValue derived from that text.
 *
 * @param in_string_bytes  Borrowed serialized ToolValueJSON bytes.
 * @param in_size          Size of in_string_bytes.
 * @param out_tool_value   Owned serialized ToolValue on success.
 * @return RAC_SUCCESS when out_tool_value carries a serialized result.
 */
RAC_API rac_result_t rac_tool_value_from_json_proto(const uint8_t* in_string_bytes, size_t in_size,
                                                    rac_proto_buffer_t* out_tool_value);

// =============================================================================
// TOOL CALLING SESSION (Wave D-4) - Native orchestration state machine
// =============================================================================

typedef void (*rac_tool_calling_session_event_callback_fn)(const uint8_t* event_bytes,
                                                           size_t event_size, void* user_data);

RAC_API rac_result_t
rac_tool_calling_session_create_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                      rac_tool_calling_session_event_callback_fn callback,
                                      void* user_data, uint64_t* out_session_handle);

RAC_API rac_result_t rac_tool_calling_session_step_with_result_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size);

RAC_API rac_result_t rac_tool_calling_session_destroy_proto(uint64_t session_handle);

/**
 * @brief Cancel an in-flight tool-calling session (pass2-syn-007).
 *
 * Sets the cancel flag on the session's in-flight LifecycleLlmRef so the
 * underlying backend `ops->generate` returns at the next cancel boundary.
 * The cancel does NOT touch the session registry — the host should still
 * call rac_tool_calling_session_destroy_proto once the in-flight call has
 * resolved. Safe to invoke from any thread (does not take the session
 * mutex held by the generate caller). Idempotent — a stale or zero handle
 * is a no-op and still returns RAC_SUCCESS so SDK adapters can fan
 * structured-concurrency cancels into this entry point without
 * coordinating with session destroy (matches
 * rac_tool_calling_run_loop_cancel_proto semantics).
 *
 * @param session_handle Handle returned by rac_tool_calling_session_create_proto.
 * @return RAC_SUCCESS even when the handle is stale (idempotent semantics).
 */
RAC_API rac_result_t rac_tool_calling_session_cancel_proto(uint64_t session_handle);

/**
 * @brief Spin-wait until all in-flight tool-calling session event dispatches
 *        have returned (commons-features-llm-rag-003).
 *
 * The tool-calling session event dispatcher (drain_and_dispatch) snapshots
 * (callback, user_data) under the session mutex, releases the lock, then
 * fires the host callback. A concurrent rac_tool_calling_session_destroy_proto
 * can race the dispatcher between the unlock and the callback fire, freeing
 * @c user_data before @c cb(payload, size, ud) executes. This helper
 * spin-waits on a process-global in-flight counter so destroy paths can
 * guarantee no callback is mid-flight before returning to the host.
 *
 * Mirrors @c rac_llm_proto_quiesce / @c rac_vlm_proto_quiesce /
 * @c rac_stt_proto_quiesce. Already called internally from
 * @c rac_tool_calling_session_destroy_proto. Exposed publicly so SDK bridges
 * tearing down on their own (e.g. SDK-level shutdown that races a still-active
 * event dispatcher) can coordinate user_data lifetime without re-entering the
 * destroy path. Safe to call from any thread.
 */
RAC_API void rac_tool_calling_session_proto_quiesce(void);

// =============================================================================
// TOOL CALLING RUN LOOP (P2-T8) - Single-call native orchestration
// =============================================================================
//
// Collapses the per-SDK generate -> parse -> validate -> execute -> follow-up
// loop into a single C ABI call. Caller provides:
//   - serialized runanywhere.v1.ToolCallingSessionCreateRequest (reused as
//     input shape; identical fields to a hypothetical RunLoopRequest)
//   - on_execute callback that synchronously executes a tool call and
//     returns its serialized runanywhere.v1.ToolResult bytes
//
// On return, out_result carries a serialized runanywhere.v1.ToolCallingResult
// describing the final text, recorded tool calls, executed tool results,
// is_complete flag, and iterations_used counter.
//
// SINGLE SOURCE OF TRUTH: the orchestration loop lives in commons. Swift,
// Kotlin, Flutter, and React Native call this and only register the tool
// executor (which owns platform side-effects).

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
typedef rac_result_t (*rac_tool_execute_callback_fn)(const uint8_t* in_tool_call_bytes,
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
RAC_API rac_result_t rac_tool_calling_run_loop_proto(const uint8_t* in_request_bytes,
                                                     size_t in_size,
                                                     rac_tool_execute_callback_fn on_execute,
                                                     void* user_data,
                                                     rac_proto_buffer_t* out_result);

/**
 * @brief Same as rac_tool_calling_run_loop_proto but additionally publishes
 *        an opaque handle the host can pass to rac_tool_calling_run_loop_cancel_proto
 *        to interrupt the in-flight loop from another thread (pass2-syn-007).
 *
 * The handle is owned by commons; it is automatically reclaimed when this
 * function returns, so the host MUST NOT use it past the return. A typical
 * cancellation pattern wires this together with a Swift
 * `withTaskCancellationHandler`, Kotlin `Job.invokeOnCompletion`,
 * Flutter `StreamSubscription.onCancel`, RN `AbortSignal`, or Web
 * `AbortController.abort()` so the structured-concurrency context can fan
 * its cancel into the native loop.
 *
 * @warning Handle-publication races (pass3-syn-028 / cross-SDK contract):
 *          @p out_run_loop_handle is written SYNCHRONOUSLY inside this call
 *          before the iteration loop begins, but the call itself is
 *          synchronous from the caller's perspective. SDKs that need to
 *          observe the handle from a DIFFERENT thread (Swift's actor,
 *          Kotlin's coroutine, RN's JS thread) must publish the handle into
 *          a thread-safe sink BEFORE invoking this function — typical
 *          patterns:
 *            - capture @p out_run_loop_handle inside the worker thread and
 *              push it to a Mailbox/CompletableDeferred/AtomicReference the
 *              outer scope reads before issuing cancel;
 *            - or use rac_tool_calling_run_loop_with_handle_and_cb_proto()
 *              (preferred — see below) which invokes a publication callback
 *              the moment the handle is minted, letting the SDK fan the
 *              value into its own thread-safe destination synchronously.
 *
 * @param in_request_bytes    Serialized ToolCallingSessionCreateRequest.
 * @param in_size             Size of in_request_bytes.
 * @param on_execute          Synchronous tool-execute callback.
 * @param user_data           Opaque pointer forwarded to on_execute.
 * @param out_run_loop_handle Output handle for cancellation. 0 if unavailable.
 * @param out_result          Owned serialized ToolCallingResult on success.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_tool_calling_run_loop_with_handle_proto(
    const uint8_t* in_request_bytes, size_t in_size, rac_tool_execute_callback_fn on_execute,
    void* user_data, uint64_t* out_run_loop_handle, rac_proto_buffer_t* out_result);

/**
 * @brief Callback fired synchronously from inside the run-loop the moment a
 *        cancellable handle is minted (pass3-syn-028 / cross-SDK contract).
 *
 * @param run_loop_handle Just-minted handle. Identical to the value that
 *                        rac_tool_calling_run_loop_with_handle_proto would
 *                        write into out_run_loop_handle. Valid only for the
 *                        lifetime of the run-loop call.
 * @param user_data       Opaque pointer registered with
 *                        rac_tool_calling_run_loop_with_handle_and_cb_proto.
 *
 * @warning Execution context: this callback fires on the THREAD THAT
 *          INVOKED the run-loop. It runs BEFORE the first generate iteration
 *          starts, so SDK callers can safely route the handle into a
 *          thread-safe sink (Swift `HandleBox.set`, Kotlin
 *          `CompletableDeferred.complete`, RN `onHandle` JS callback,
 *          Flutter `Completer.complete`, Web synchronous capture) and
 *          arrange for cancel to fan in via
 *          rac_tool_calling_run_loop_cancel_proto. Keep the callback work
 *          minimal — long-running publication blocks the generate loop.
 *          MUST NOT reentrantly call any rac_tool_calling_* API.
 */
typedef void (*rac_tool_calling_run_loop_on_handle_published_cb_t)(uint64_t run_loop_handle,
                                                                   void* user_data);

/**
 * @brief Variant of rac_tool_calling_run_loop_with_handle_proto that adds a
 *        synchronous handle-publication callback (pass3-syn-028).
 *
 * Fires @p on_handle_published(handle, on_handle_user_data) SYNCHRONOUSLY
 * the moment the cancellable run-loop handle is minted, BEFORE the first
 * generate iteration runs. This lets SDKs route the handle into a
 * thread-safe sink (Swift `HandleBox.set`, Kotlin `CompletableDeferred`,
 * RN JS-thread callback, Flutter `Completer`, Web synchronous capture)
 * without racing the worker thread that owns the run-loop. The pointer-shape
 * @p out_run_loop_handle is still populated so legacy hosts that observe
 * both have a stable contract.
 *
 * @param in_request_bytes        Borrowed serialized
 *                                runanywhere.v1.ToolCallingSessionCreateRequest.
 * @param in_size                 Size of in_request_bytes.
 * @param on_execute              Synchronous tool-execute callback.
 * @param on_execute_user_data    Opaque pointer forwarded to on_execute.
 * @param on_handle_published     Synchronous handle-publication callback.
 *                                Pass NULL to use the pointer-shape only.
 * @param on_handle_user_data     Opaque pointer forwarded to on_handle_published.
 * @param out_run_loop_handle     Output handle for cancellation. 0 if unavailable.
 * @param out_result              Owned serialized ToolCallingResult on success.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_tool_calling_run_loop_with_handle_and_cb_proto(
    const uint8_t* in_request_bytes, size_t in_size,
    rac_tool_execute_callback_fn on_execute, void* on_execute_user_data,
    rac_tool_calling_run_loop_on_handle_published_cb_t on_handle_published,
    void* on_handle_user_data, uint64_t* out_run_loop_handle,
    rac_proto_buffer_t* out_result);

/**
 * @brief Cancel an in-flight tool-calling run loop (pass2-syn-007).
 *
 * Looks up the run-loop handle published by
 * rac_tool_calling_run_loop_with_handle_proto and asks the in-flight
 * LifecycleLlmRef to cancel. Safe to call from any thread; a no-op if
 * the handle has already been retired (RAC_SUCCESS is still returned to
 * make idempotent cancellation paths in the SDK adapters easy).
 *
 * @param run_loop_handle Handle out-parameter from with_handle_proto.
 * @return RAC_SUCCESS even when the handle is stale (idempotent semantics).
 */
RAC_API rac_result_t rac_tool_calling_run_loop_cancel_proto(uint64_t run_loop_handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TOOL_CALLING_H */
