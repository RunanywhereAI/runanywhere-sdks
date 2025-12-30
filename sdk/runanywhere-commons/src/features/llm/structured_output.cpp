/**
 * @file structured_output.cpp
 * @brief LLM Structured Output JSON Parsing Implementation
 *
 * C++ port of Swift's StructuredOutputHandler.swift from:
 * Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputHandler.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_platform_adapter.h"
#include "rac/features/llm/rac_llm_structured_output.h"

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * @brief Trim whitespace from the beginning and end of a string
 *
 * @param str Input string
 * @param out_start Output: Start position after leading whitespace
 * @param out_end Output: End position before trailing whitespace (exclusive)
 */
static void trim_whitespace(const char* str, size_t* out_start, size_t* out_end) {
    size_t len = strlen(str);
    size_t start = 0;
    size_t end = len;

    // Skip leading whitespace
    while (start < len && (str[start] == ' ' || str[start] == '\t' || str[start] == '\n' ||
                           str[start] == '\r')) {
        start++;
    }

    // Skip trailing whitespace
    while (end > start && (str[end - 1] == ' ' || str[end - 1] == '\t' || str[end - 1] == '\n' ||
                           str[end - 1] == '\r')) {
        end--;
    }

    *out_start = start;
    *out_end = end;
}

/**
 * @brief Find the first occurrence of a character in a string starting from a position
 *
 * @param str Input string
 * @param ch Character to find
 * @param start_pos Starting position
 * @param out_pos Output: Position of character if found
 * @return true if found, false otherwise
 */
static bool find_char(const char* str, char ch, size_t start_pos, size_t* out_pos) {
    size_t len = strlen(str);
    for (size_t i = start_pos; i < len; i++) {
        if (str[i] == ch) {
            *out_pos = i;
            return true;
        }
    }
    return false;
}

// =============================================================================
// FIND MATCHING BRACE - Ported from Swift lines 179-212
// =============================================================================

extern "C" rac_bool_t rac_structured_output_find_matching_brace(const char* text, size_t start_pos,
                                                                size_t* out_end_pos) {
    if (!text || !out_end_pos) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (start_pos >= len || text[start_pos] != '{') {
        return RAC_FALSE;
    }

    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start_pos; i < len; i++) {
        char ch = text[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"' && !escaped) {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
                if (depth == 0) {
                    *out_end_pos = i;
                    return RAC_TRUE;
                }
            }
        }
    }

    return RAC_FALSE;
}

// =============================================================================
// FIND MATCHING BRACKET - Ported from Swift lines 215-248
// =============================================================================

extern "C" rac_bool_t rac_structured_output_find_matching_bracket(const char* text,
                                                                  size_t start_pos,
                                                                  size_t* out_end_pos) {
    if (!text || !out_end_pos) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (start_pos >= len || text[start_pos] != '[') {
        return RAC_FALSE;
    }

    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start_pos; i < len; i++) {
        char ch = text[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"' && !escaped) {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '[') {
                depth++;
            } else if (ch == ']') {
                depth--;
                if (depth == 0) {
                    *out_end_pos = i;
                    return RAC_TRUE;
                }
            }
        }
    }

    return RAC_FALSE;
}

// =============================================================================
// FIND COMPLETE JSON - Ported from Swift lines 135-176
// =============================================================================

extern "C" rac_bool_t rac_structured_output_find_complete_json(const char* text, size_t* out_start,
                                                               size_t* out_end) {
    if (!text || !out_start || !out_end) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (len == 0) {
        return RAC_FALSE;
    }

    // Try to find JSON object or array
    const char start_chars[] = {'{', '['};
    const char end_chars[] = {'}', ']'};

    for (int type = 0; type < 2; type++) {
        char start_char = start_chars[type];
        char end_char = end_chars[type];

        size_t start_pos;
        if (!find_char(text, start_char, 0, &start_pos)) {
            continue;
        }

        int depth = 0;
        bool in_string = false;
        bool escaped = false;

        for (size_t i = start_pos; i < len; i++) {
            char ch = text[i];

            if (escaped) {
                escaped = false;
                continue;
            }

            if (ch == '\\') {
                escaped = true;
                continue;
            }

            if (ch == '"' && !escaped) {
                in_string = !in_string;
                continue;
            }

            if (!in_string) {
                if (ch == start_char) {
                    depth++;
                } else if (ch == end_char) {
                    depth--;
                    if (depth == 0) {
                        *out_start = start_pos;
                        *out_end = i + 1;  // Exclusive end
                        return RAC_TRUE;
                    }
                }
            }
        }
    }

    return RAC_FALSE;
}

// =============================================================================
// EXTRACT JSON - Ported from Swift lines 102-132
// =============================================================================

extern "C" rac_result_t rac_structured_output_extract_json(const char* text, char** out_json,
                                                           size_t* out_length) {
    if (!text || !out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Trim whitespace
    size_t trim_start, trim_end;
    trim_whitespace(text, &trim_start, &trim_end);

    if (trim_start >= trim_end) {
        rac_log(RAC_LOG_ERROR, "StructuredOutput", "Empty text provided");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    size_t trimmed_len = trim_end - trim_start;
    const char* trimmed = text + trim_start;

    // First, try to find a complete JSON object
    size_t json_start, json_end;
    if (rac_structured_output_find_complete_json(trimmed, &json_start, &json_end)) {
        size_t json_len = json_end - json_start;
        char* result = static_cast<char*>(malloc(json_len + 1));
        if (!result) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(result, trimmed + json_start, json_len);
        result[json_len] = '\0';
        *out_json = result;
        if (out_length) {
            *out_length = json_len;
        }
        return RAC_SUCCESS;
    }

    // Fallback: Try to find JSON object boundaries with findMatchingBrace
    size_t brace_start;
    if (find_char(trimmed, '{', 0, &brace_start)) {
        size_t brace_end;
        if (rac_structured_output_find_matching_brace(trimmed, brace_start, &brace_end)) {
            size_t json_len = brace_end - brace_start + 1;
            char* result = static_cast<char*>(malloc(json_len + 1));
            if (!result) {
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            memcpy(result, trimmed + brace_start, json_len);
            result[json_len] = '\0';
            *out_json = result;
            if (out_length) {
                *out_length = json_len;
            }
            return RAC_SUCCESS;
        }
    }

    // Try to find JSON array boundaries
    size_t bracket_start;
    if (find_char(trimmed, '[', 0, &bracket_start)) {
        size_t bracket_end;
        if (rac_structured_output_find_matching_bracket(trimmed, bracket_start, &bracket_end)) {
            size_t json_len = bracket_end - bracket_start + 1;
            char* result = static_cast<char*>(malloc(json_len + 1));
            if (!result) {
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            memcpy(result, trimmed + bracket_start, json_len);
            result[json_len] = '\0';
            *out_json = result;
            if (out_length) {
                *out_length = json_len;
            }
            return RAC_SUCCESS;
        }
    }

    // If no clear JSON boundaries, check if the entire text might be JSON
    if (trimmed[0] == '{' || trimmed[0] == '[') {
        char* result = static_cast<char*>(malloc(trimmed_len + 1));
        if (!result) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(result, trimmed, trimmed_len);
        result[trimmed_len] = '\0';
        *out_json = result;
        if (out_length) {
            *out_length = trimmed_len;
        }
        return RAC_SUCCESS;
    }

    // Log the text that couldn't be parsed
    rac_log(RAC_LOG_ERROR, "StructuredOutput", "No valid JSON found in the response");
    return RAC_ERROR_INVALID_FORMAT;
}

// =============================================================================
// GET SYSTEM PROMPT - Ported from Swift lines 10-30
// =============================================================================

extern "C" rac_result_t rac_structured_output_get_system_prompt(const char* json_schema,
                                                                char** out_prompt) {
    if (!out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* schema = json_schema ? json_schema : "{}";

    // Build the system prompt - matches Swift getSystemPrompt(for:)
    const char* format =
        "You are a JSON generator that outputs ONLY valid JSON without any additional text.\n"
        "\n"
        "CRITICAL RULES:\n"
        "1. Your entire response must be valid JSON that can be parsed\n"
        "2. Start with { and end with }\n"
        "3. No text before the opening {\n"
        "4. No text after the closing }\n"
        "5. Follow the provided schema exactly\n"
        "6. Include all required fields\n"
        "7. Use proper JSON syntax (quotes, commas, etc.)\n"
        "\n"
        "Expected JSON Schema:\n"
        "%s\n"
        "\n"
        "Remember: Output ONLY the JSON object, nothing else.";

    size_t needed = snprintf(NULL, 0, format, schema) + 1;
    char* result = static_cast<char*>(malloc(needed));
    if (!result) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    snprintf(result, needed, format, schema);
    *out_prompt = result;

    return RAC_SUCCESS;
}

// =============================================================================
// PREPARE PROMPT - Ported from Swift lines 43-82
// =============================================================================

extern "C" rac_result_t
rac_structured_output_prepare_prompt(const char* original_prompt,
                                     const rac_structured_output_config_t* config,
                                     char** out_prompt) {
    if (!original_prompt || !out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // If no config or schema not included in prompt, return original
    if (!config || !config->include_schema_in_prompt) {
        size_t len = strlen(original_prompt);
        char* result = static_cast<char*>(malloc(len + 1));
        if (!result) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(result, original_prompt, len + 1);
        *out_prompt = result;
        return RAC_SUCCESS;
    }

    const char* schema = config->json_schema ? config->json_schema : "{}";

    // Build structured output instructions - matches Swift preparePrompt()
    const char* format =
        "System: You are a JSON generator. You must output only valid JSON.\n"
        "\n"
        "%s\n"
        "\n"
        "CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is "
        "allowed.\n"
        "\n"
        "JSON Schema:\n"
        "%s\n"
        "\n"
        "RULES:\n"
        "1. Start your response with { and end with }\n"
        "2. Include NO text before the opening {\n"
        "3. Include NO text after the closing }\n"
        "4. Follow the schema exactly\n"
        "5. All required fields must be present\n"
        "6. Use exact field names from the schema\n"
        "7. Ensure proper JSON syntax (quotes, commas, etc.)\n"
        "\n"
        "IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any "
        "explanations, comments, or additional text.\n"
        "\n"
        "Remember: Output ONLY the JSON object, nothing else.";

    size_t needed = snprintf(NULL, 0, format, original_prompt, schema) + 1;
    char* result = static_cast<char*>(malloc(needed));
    if (!result) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    snprintf(result, needed, format, original_prompt, schema);
    *out_prompt = result;

    return RAC_SUCCESS;
}

// =============================================================================
// VALIDATE STRUCTURED OUTPUT - Ported from Swift lines 264-282
// =============================================================================

extern "C" rac_result_t
rac_structured_output_validate(const char* text, const rac_structured_output_config_t* config,
                               rac_structured_output_validation_t* out_validation) {
    (void)config;  // Currently unused, reserved for future schema validation

    if (!text || !out_validation) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    out_validation->is_valid = RAC_FALSE;
    out_validation->error_message = nullptr;
    out_validation->extracted_json = nullptr;

    // Try to extract JSON
    char* extracted = nullptr;
    rac_result_t result = rac_structured_output_extract_json(text, &extracted, nullptr);

    if (result == RAC_SUCCESS && extracted) {
        out_validation->is_valid = RAC_TRUE;
        out_validation->extracted_json = extracted;
        return RAC_SUCCESS;
    }

    // Extraction failed
    out_validation->is_valid = RAC_FALSE;
    out_validation->error_message = "No valid JSON found in the response";

    return RAC_SUCCESS;  // Function succeeded, validation just returned false
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

extern "C" void
rac_structured_output_validation_free(rac_structured_output_validation_t* validation) {
    if (!validation) {
        return;
    }

    if (validation->extracted_json) {
        free(validation->extracted_json);
        validation->extracted_json = nullptr;
    }

    // error_message is static, don't free it
    validation->error_message = nullptr;
    validation->is_valid = RAC_FALSE;
}
