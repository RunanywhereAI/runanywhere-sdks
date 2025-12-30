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
 */

#ifndef RAC_LLM_STRUCTURED_OUTPUT_H
#define RAC_LLM_STRUCTURED_OUTPUT_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_llm_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STRUCTURED OUTPUT API
// =============================================================================

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
 */
RAC_API rac_result_t rac_structured_output_extract_json(const char* text, char** out_json,
                                                        size_t* out_length);

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
 */
RAC_API rac_bool_t rac_structured_output_find_complete_json(const char* text, size_t* out_start,
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
RAC_API rac_result_t
rac_structured_output_prepare_prompt(const char* original_prompt,
                                     const rac_structured_output_config_t* config,
                                     char** out_prompt);

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
 */
RAC_API rac_result_t rac_structured_output_get_system_prompt(const char* json_schema,
                                                             char** out_prompt);

/**
 * @brief Validate that text contains valid structured output
 *
 * Ported from Swift StructuredOutputHandler.validateStructuredOutput(text:config:) (lines 264-282)
 *
 * @param text Text to validate
 * @param config Structured output configuration (can be NULL for basic validation)
 * @param out_validation Output: Validation result (caller must free extracted_json with rac_free)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t
rac_structured_output_validate(const char* text, const rac_structured_output_config_t* config,
                               rac_structured_output_validation_t* out_validation);

/**
 * @brief Free structured output validation result
 *
 * @param validation Validation result to free
 */
RAC_API void rac_structured_output_validation_free(rac_structured_output_validation_t* validation);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_STRUCTURED_OUTPUT_H */
