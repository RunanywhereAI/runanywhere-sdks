/**
 * @file rac_llm_structured_output.h
 * @brief RunAnywhere Commons - LLM Structured Output JSON Parsing
 *
 * C port of Swift's StructuredOutputHandler.swift from:
 * Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputHandler.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 *
 * Provides JSON extraction and parsing functions for structured output generation.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - Proto-byte APIs (rac_structured_output_parse_proto,
 *     rac_structured_output_generate_proto,
 *     rac_structured_output_generate_stream_proto,
 *     rac_structured_output_prepare_prompt_proto,
 *     rac_structured_output_validate_proto): `SDK-facing default` over
 *     runanywhere.v1.StructuredOutputRequest /
 *     StructuredOutputParseRequest / StructuredOutputResult /
 *     StructuredOutputValidation / StructuredOutputStreamEvent /
 *     StructuredOutputPromptResult bytes.
 *   - Struct/JSON helpers (rac_structured_output_parse_result_t,
 *     extract_json, find_complete_json, find_matching_brace/bracket,
 *     prepare_prompt, get_system_prompt, validate, validation_free):
 *     `delete after SDK migration` for SDK-facing entry points;
 *     `internal` for parser primitives.
 */

#ifndef RAC_LLM_STRUCTURED_OUTPUT_H
#define RAC_LLM_STRUCTURED_OUTPUT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STRUCTURED OUTPUT API
// =============================================================================

/**
 * @brief Parsed structured output result
 *
 * Mirrors the portable fields of the generated StructuredOutputResult contract
 * without depending on generated headers in the C ABI.
 */
typedef struct rac_structured_output_parse_result {
    rac_bool_t is_valid;          /**< Whether JSON extraction and validation succeeded */
    rac_bool_t contains_json;     /**< Whether a JSON candidate was found in the text */
    char* parsed_json;            /**< Canonical extracted JSON string (owned) */
    char* raw_text;               /**< Original model text (owned) */
    char* error_message;          /**< First parse/validation error, if any (owned) */
    char* validation_errors_json; /**< JSON array of validation errors (owned) */
    rac_result_t error_code;      /**< RAC_SUCCESS or validation/parse error code */
} rac_structured_output_parse_result_t;

/**
 * @brief Extract JSON from potentially mixed text
 *
 * Ported from Swift StructuredOutputHandler.extractJSON(from:) (lines 102-132)
 *
 * Searches for complete JSON objects or arrays in the given text,
 * handling cases where the text contains additional content before/after JSON.
 *
 * @param text Input text that may contain JSON mixed with other content
 * @param out_json Output: Allocated JSON string (caller must free with rac_free)
 * @param out_length Output: Length of extracted JSON string (can be NULL)
 * @return RAC_SUCCESS if JSON found and extracted, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           parser helper used by `rac_structured_output_parse_proto`;
 *           SDKs receive extracted JSON via proto bytes.
 */
rac_result_t rac_structured_output_extract_json(const char* text, char** out_json,
                                                size_t* out_length);

/**
 * @brief Extract, parse, canonicalize, and validate structured output JSON
 *
 * @param text Model output text
 * @param config Structured output configuration (can be NULL for syntax-only validation)
 * @param out_result Output parse result (free with rac_structured_output_parse_result_free)
 * @return RAC_SUCCESS on successful parse processing
 */
RAC_API rac_result_t rac_structured_output_parse(const char* text,
                                                 const rac_structured_output_config_t* config,
                                                 rac_structured_output_parse_result_t* out_result);

/**
 * @brief Parse structured output from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.StructuredOutputParseRequest and returns a
 * runanywhere.v1.StructuredOutputResult in out_result. When the protobuf
 * runtime is unavailable, out_result is set to RAC_ERROR_FEATURE_NOT_AVAILABLE.
 *
 * @param request_proto_bytes Borrowed StructuredOutputParseRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned StructuredOutputResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_structured_output_parse_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       rac_proto_buffer_t* out_result);

/**
 * @brief Generate and parse structured output from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.StructuredOutputRequest, runs the lifecycle-owned
 * LLM model, strips thinking tags before parsing, and returns a serialized
 * runanywhere.v1.StructuredOutputResult in out_result.
 *
 * @param request_proto_bytes Borrowed StructuredOutputRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned StructuredOutputResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_structured_output_generate_proto(const uint8_t* request_proto_bytes,
                                                          size_t request_proto_size,
                                                          rac_proto_buffer_t* out_result);

/**
 * @brief Stream structured generation from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.StructuredOutputRequest and emits serialized
 * runanywhere.v1.StructuredOutputStreamEvent payloads through callback.
 * The stream includes token events, partial JSON events when a complete JSON
 * value becomes available, and one terminal completed/error event.
 *
 * @param request_proto_bytes Borrowed StructuredOutputRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param callback Borrowed proto-byte callback for StructuredOutputStreamEvent.
 * @param user_data Opaque user context passed to callback.
 * @return RAC_SUCCESS when the generation transport completed successfully.
 */
RAC_API rac_result_t rac_structured_output_generate_stream_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_bytes_callback_fn callback, void* user_data);

/**
 * @brief Find complete JSON boundaries in text
 *
 * Ported from Swift StructuredOutputHandler.findCompleteJSON(in:) (lines 135-176)
 *
 * Uses a character-by-character state machine to find matching braces/brackets
 * while properly handling string escapes and nesting.
 *
 * @param text Text to search for JSON
 * @param out_start Output: Start position of JSON (0-indexed)
 * @param out_end Output: End position of JSON (exclusive)
 * @return RAC_TRUE if complete JSON found, RAC_FALSE otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           scanner used by streaming structured-output; SDKs should not
 *           call it directly.
 */
rac_bool_t rac_structured_output_find_complete_json(const char* text, size_t* out_start,
                                                    size_t* out_end);

/**
 * @brief Find matching closing brace for an opening brace
 *
 * Ported from Swift StructuredOutputHandler.findMatchingBrace(in:startingFrom:) (lines 179-212)
 *
 * @param text Text to search
 * @param start_pos Position of opening brace '{'
 * @param out_end_pos Output: Position of matching closing brace '}'
 * @return RAC_TRUE if matching brace found, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_structured_output_find_matching_brace(const char* text, size_t start_pos,
                                                             size_t* out_end_pos);

/**
 * @brief Find matching closing bracket for an opening bracket
 *
 * Ported from Swift StructuredOutputHandler.findMatchingBracket(in:startingFrom:) (lines 215-248)
 *
 * @param text Text to search
 * @param start_pos Position of opening bracket '['
 * @param out_end_pos Output: Position of matching closing bracket ']'
 * @return RAC_TRUE if matching bracket found, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_structured_output_find_matching_bracket(const char* text, size_t start_pos,
                                                               size_t* out_end_pos);

/**
 * @brief Prepare prompt with structured output instructions
 *
 * Ported from Swift StructuredOutputHandler.preparePrompt(originalPrompt:config:) (lines 43-82)
 *
 * Adds JSON schema and generation instructions to the prompt.
 *
 * @param original_prompt Original user prompt
 * @param config Structured output configuration with JSON schema
 * @param out_prompt Output: Allocated prepared prompt (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_structured_output_prepare_prompt(
    const char* original_prompt, const rac_structured_output_config_t* config, char** out_prompt);

/**
 * @brief Prepare a structured-output prompt from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.StructuredOutputRequest and returns a serialized
 * runanywhere.v1.StructuredOutputPromptResult in out_result.
 *
 * @param request_proto_bytes Borrowed StructuredOutputRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned StructuredOutputPromptResult bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_structured_output_prepare_prompt_proto(const uint8_t* request_proto_bytes,
                                                                size_t request_proto_size,
                                                                rac_proto_buffer_t* out_result);

/**
 * @brief Get system prompt for structured output generation
 *
 * Ported from Swift StructuredOutputHandler.getSystemPrompt(for:) (lines 10-30)
 *
 * Generates a system prompt instructing the model to output only valid JSON.
 *
 * @param json_schema JSON schema describing expected output structure
 * @param out_prompt Output: Allocated system prompt (caller must free with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 *
 * @internal Classification: `delete after SDK migration`. Commons-internal
 *           helper used by `rac_structured_output_prepare_prompt_proto`;
 *           SDKs should call the proto API.
 */
rac_result_t rac_structured_output_get_system_prompt(const char* json_schema, char** out_prompt);

/**
 * @brief Validate that text contains valid structured output
 *
 * Ported from Swift StructuredOutputHandler.validateStructuredOutput(text:config:) (lines 264-282)
 *
 * @param text Text to validate
 * @param config Structured output configuration (can be NULL for basic validation)
 * @param out_validation Output validation result (free with rac_structured_output_validation_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t
rac_structured_output_validate(const char* text, const rac_structured_output_config_t* config,
                               rac_structured_output_validation_t* out_validation);

/**
 * @brief Validate structured output from serialized generated proto bytes.
 *
 * Accepts a runanywhere.v1.StructuredOutputValidationRequest and returns a
 * serialized runanywhere.v1.StructuredOutputValidation in out_result.
 *
 * @param request_proto_bytes Borrowed StructuredOutputValidationRequest bytes.
 * @param request_proto_size Size of request_proto_bytes.
 * @param out_result Owned StructuredOutputValidation bytes or typed error.
 * @return RAC_SUCCESS when out_result carries a serialized result.
 */
RAC_API rac_result_t rac_structured_output_validate_proto(const uint8_t* request_proto_bytes,
                                                          size_t request_proto_size,
                                                          rac_proto_buffer_t* out_result);

/**
 * @brief Free structured output validation result
 *
 * @param validation Validation result to free
 */
RAC_API void rac_structured_output_validation_free(rac_structured_output_validation_t* validation);

/**
 * @brief Free structured output parse result
 *
 * @param result Parse result to free
 */
RAC_API void rac_structured_output_parse_result_free(rac_structured_output_parse_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_STRUCTURED_OUTPUT_H */
