/**
 * @file tool_calling.cpp
 * @brief RunAnywhere Commons - Tool Calling Implementation
 *
 * *** SINGLE SOURCE OF TRUTH FOR ALL TOOL CALLING LOGIC ***
 *
 * This implementation consolidates all tool calling logic from:
 * - Swift: ToolCallParser.swift
 * - React Native: ToolCallingBridge.cpp
 *
 * NO FALLBACKS - All SDKs must use these functions exclusively.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_tool_calling.h"

// =============================================================================
// CONSTANTS
// =============================================================================

static const char* TOOL_CALL_START_TAG = "<tool_call>";
static const char* TOOL_CALL_END_TAG = "</tool_call>";

// Standard keys for tool name (case-insensitive matching)
static const char* TOOL_NAME_KEYS[] = {"tool", "name", "function", "func", "method",
                                       "action", "command", nullptr};

// Standard keys for arguments (case-insensitive matching)
static const char* ARGUMENT_KEYS[] = {"arguments", "args", "params", "parameters", "input", nullptr};

// =============================================================================
// HELPER FUNCTIONS - String Operations
// =============================================================================

/**
 * @brief Case-insensitive string comparison
 */
static bool str_equals_ignore_case(const char* a, const char* b) {
    if (!a || !b)
        return false;
    while (*a && *b) {
        char ca = (*a >= 'A' && *a <= 'Z') ? (*a + 32) : *a;
        char cb = (*b >= 'A' && *b <= 'Z') ? (*b + 32) : *b;
        if (ca != cb)
            return false;
        a++;
        b++;
    }
    return *a == *b;
}

/**
 * @brief Trim whitespace from beginning and end
 */
static void trim_whitespace(const char* str, size_t len, size_t* out_start, size_t* out_end) {
    size_t start = 0;
    size_t end = len;

    while (start < len && (str[start] == ' ' || str[start] == '\t' || str[start] == '\n' ||
                           str[start] == '\r')) {
        start++;
    }

    while (end > start && (str[end - 1] == ' ' || str[end - 1] == '\t' || str[end - 1] == '\n' ||
                           str[end - 1] == '\r')) {
        end--;
    }

    *out_start = start;
    *out_end = end;
}

/**
 * @brief Find substring in string
 */
static const char* find_str(const char* haystack, const char* needle) {
    return strstr(haystack, needle);
}

/**
 * @brief Check if character is a key character (alphanumeric or underscore)
 */
static bool is_key_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

// =============================================================================
// JSON PARSING HELPERS (Manual - No External Library)
// =============================================================================

/**
 * @brief Find matching closing brace for JSON object
 *
 * Tracks string boundaries to ignore braces inside strings.
 *
 * @param str String to search
 * @param start_pos Position of opening brace '{'
 * @param out_end Output: Position of matching closing brace '}'
 * @return true if found, false otherwise
 */
static bool find_matching_brace(const char* str, size_t start_pos, size_t* out_end) {
    if (!str || str[start_pos] != '{') {
        return false;
    }

    size_t len = strlen(str);
    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start_pos; i < len; i++) {
        char ch = str[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"') {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
                if (depth == 0) {
                    *out_end = i;
                    return true;
                }
            }
        }
    }

    return false;
}

/**
 * @brief Skip whitespace in string
 */
static size_t skip_whitespace(const char* str, size_t pos, size_t len) {
    while (pos < len && (str[pos] == ' ' || str[pos] == '\t' || str[pos] == '\n' || str[pos] == '\r')) {
        pos++;
    }
    return pos;
}

/**
 * @brief Extract a JSON string value starting at the given position (must be after opening quote)
 *
 * @param str Input string
 * @param pos Position after opening quote
 * @param len Length of input string
 * @param out_value Output: Allocated string value (caller must free)
 * @param out_end_pos Output: Position after closing quote
 * @return true if successful
 */
static bool extract_json_string(const char* str, size_t pos, size_t len, char** out_value,
                                size_t* out_end_pos) {
    std::string result;
    bool escaped = false;

    for (size_t i = pos; i < len; i++) {
        char ch = str[i];

        if (escaped) {
            switch (ch) {
            case 'n':
                result += '\n';
                break;
            case 'r':
                result += '\r';
                break;
            case 't':
                result += '\t';
                break;
            case '\\':
                result += '\\';
                break;
            case '"':
                result += '"';
                break;
            default:
                result += ch;
                break;
            }
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"') {
            // End of string
            *out_value = static_cast<char*>(malloc(result.size() + 1));
            if (*out_value) {
                memcpy(*out_value, result.c_str(), result.size() + 1);
            }
            *out_end_pos = i + 1;
            return true;
        }

        result += ch;
    }

    return false;
}

/**
 * @brief Extract a JSON object as a raw string (including braces)
 */
static bool extract_json_object_raw(const char* str, size_t pos, size_t len, char** out_value,
                                    size_t* out_end_pos) {
    if (str[pos] != '{') {
        return false;
    }

    size_t end_brace;
    if (!find_matching_brace(str, pos, &end_brace)) {
        return false;
    }

    size_t obj_len = end_brace - pos + 1;
    *out_value = static_cast<char*>(malloc(obj_len + 1));
    if (!*out_value) {
        return false;
    }

    memcpy(*out_value, str + pos, obj_len);
    (*out_value)[obj_len] = '\0';
    *out_end_pos = end_brace + 1;
    return true;
}

/**
 * @brief Simple JSON key-value extractor
 *
 * Extracts a string or object value for a given key from a JSON object string.
 *
 * @param json_obj JSON object string (must include braces)
 * @param key Key to find (case-insensitive)
 * @param out_value Output: Allocated value string (caller must free)
 * @param out_is_object Output: Whether the value is an object (vs string)
 * @return true if found
 */
static bool extract_json_value(const char* json_obj, const char* key, char** out_value,
                               bool* out_is_object) {
    if (!json_obj || !key || !out_value) {
        return false;
    }

    *out_value = nullptr;
    *out_is_object = false;

    size_t len = strlen(json_obj);
    bool in_string = false;
    bool escaped = false;

    for (size_t i = 0; i < len; i++) {
        char ch = json_obj[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"') {
            if (!in_string) {
                // Start of a key string - extract it
                size_t key_start = i + 1;
                char* found_key = nullptr;
                size_t key_end;

                if (extract_json_string(json_obj, key_start, len, &found_key, &key_end)) {
                    // Check if this key matches
                    bool matches = str_equals_ignore_case(found_key, key);
                    free(found_key);

                    if (matches) {
                        // Skip to colon
                        size_t pos = skip_whitespace(json_obj, key_end, len);
                        if (pos < len && json_obj[pos] == ':') {
                            pos++;
                            pos = skip_whitespace(json_obj, pos, len);

                            // Extract value
                            if (pos < len) {
                                if (json_obj[pos] == '"') {
                                    // String value
                                    size_t value_end;
                                    if (extract_json_string(json_obj, pos + 1, len, out_value,
                                                            &value_end)) {
                                        *out_is_object = false;
                                        return true;
                                    }
                                } else if (json_obj[pos] == '{') {
                                    // Object value
                                    size_t value_end;
                                    if (extract_json_object_raw(json_obj, pos, len, out_value,
                                                                &value_end)) {
                                        *out_is_object = true;
                                        return true;
                                    }
                                }
                            }
                        }
                    }

                    // Move to end of key for continued scanning
                    i = key_end - 1;
                }
            }
            in_string = !in_string;
        }
    }

    return false;
}

/**
 * @brief Get all keys from a JSON object (for fallback strategy)
 */
static std::vector<std::string> get_json_keys(const char* json_obj) {
    std::vector<std::string> keys;
    if (!json_obj) {
        return keys;
    }

    size_t len = strlen(json_obj);
    bool in_string = false;
    bool escaped = false;
    int depth = 0;

    for (size_t i = 0; i < len; i++) {
        char ch = json_obj[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"') {
            if (!in_string && depth == 1) {
                // Start of a key at depth 1 (top-level)
                size_t key_start = i + 1;
                char* found_key = nullptr;
                size_t key_end;

                if (extract_json_string(json_obj, key_start, len, &found_key, &key_end)) {
                    // Verify it's followed by colon
                    size_t pos = skip_whitespace(json_obj, key_end, len);
                    if (pos < len && json_obj[pos] == ':') {
                        keys.push_back(found_key);
                    }
                    free(found_key);
                    i = key_end - 1;
                    continue;
                }
            }
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
            }
        }
    }

    return keys;
}

/**
 * @brief Check if key is a standard/reserved key
 */
static bool is_standard_key(const char* key) {
    // Standard tool keys
    for (int i = 0; TOOL_NAME_KEYS[i] != nullptr; i++) {
        if (str_equals_ignore_case(key, TOOL_NAME_KEYS[i])) {
            return true;
        }
    }
    // Standard argument keys
    for (int i = 0; ARGUMENT_KEYS[i] != nullptr; i++) {
        if (str_equals_ignore_case(key, ARGUMENT_KEYS[i])) {
            return true;
        }
    }
    return false;
}

// =============================================================================
// JSON NORMALIZATION
// =============================================================================

extern "C" rac_result_t rac_tool_call_normalize_json(const char* json_str, char** out_normalized) {
    if (!json_str || !out_normalized) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    size_t len = strlen(json_str);
    std::string result;
    result.reserve(len + 32);

    bool in_string = false;

    for (size_t i = 0; i < len; i++) {
        char c = json_str[i];

        // Track if we're inside a string
        if (c == '"' && (i == 0 || json_str[i - 1] != '\\')) {
            in_string = !in_string;
            result += c;
            continue;
        }

        if (in_string) {
            result += c;
            continue;
        }

        // Look for unquoted keys: { key: or , key:
        if ((c == '{' || c == ',') && i + 1 < len) {
            result += c;

            // Skip whitespace
            size_t j = i + 1;
            while (j < len && (json_str[j] == ' ' || json_str[j] == '\t' || json_str[j] == '\n')) {
                result += json_str[j];
                j++;
            }

            // Check if next is an unquoted identifier followed by colon
            if (j < len && json_str[j] != '"' && json_str[j] != '{' && json_str[j] != '[') {
                size_t key_start = j;
                while (j < len && is_key_char(json_str[j])) {
                    j++;
                }

                if (j < len && j > key_start) {
                    size_t key_end = j;
                    // Skip whitespace to find colon
                    while (j < len && (json_str[j] == ' ' || json_str[j] == '\t')) {
                        j++;
                    }
                    if (j < len && json_str[j] == ':') {
                        // This is an unquoted key - add quotes
                        result += '"';
                        result.append(json_str + key_start, key_end - key_start);
                        result += '"';
                        i = key_end - 1;  // -1 because loop will increment
                        continue;
                    }
                }
            }

            i = j - 1;  // -1 because loop will increment
            continue;
        }

        result += c;
    }

    *out_normalized = static_cast<char*>(malloc(result.size() + 1));
    if (!*out_normalized) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_normalized, result.c_str(), result.size() + 1);

    return RAC_SUCCESS;
}

// =============================================================================
// TOOL NAME AND ARGUMENTS EXTRACTION
// =============================================================================

/**
 * @brief Extract tool name and arguments using multiple strategies
 *
 * Strategies in order:
 * 1. Standard format: {"tool": "name", "arguments": {...}}
 * 2. Name/function variant: {"name": "name", "params": {...}}
 * 3. Placeholder key with value being tool name
 * 4. Tool name as key: {"calculate": "5 * 100"}
 */
static bool extract_tool_name_and_args(const char* json_obj, char** out_tool_name,
                                       char** out_args_json) {
    *out_tool_name = nullptr;
    *out_args_json = nullptr;

    // Strategy 1 & 2: Try standard tool name keys
    for (int i = 0; TOOL_NAME_KEYS[i] != nullptr; i++) {
        char* value = nullptr;
        bool is_obj = false;
        if (extract_json_value(json_obj, TOOL_NAME_KEYS[i], &value, &is_obj)) {
            if (!is_obj && value && strlen(value) > 0) {
                *out_tool_name = value;

                // Now find arguments
                for (int j = 0; ARGUMENT_KEYS[j] != nullptr; j++) {
                    char* args_value = nullptr;
                    bool args_is_obj = false;
                    if (extract_json_value(json_obj, ARGUMENT_KEYS[j], &args_value, &args_is_obj)) {
                        if (args_is_obj) {
                            *out_args_json = args_value;
                        } else {
                            // Wrap scalar in {"input": value}
                            size_t wrap_len = strlen(args_value) + 20;
                            *out_args_json = static_cast<char*>(malloc(wrap_len));
                            if (*out_args_json) {
                                snprintf(*out_args_json, wrap_len, "{\"input\":\"%s\"}", args_value);
                            }
                            free(args_value);
                        }
                        return true;
                    }
                }

                // No arguments found - use empty object
                *out_args_json = static_cast<char*>(malloc(3));
                if (*out_args_json) {
                    strcpy(*out_args_json, "{}");
                }
                return true;
            }
            free(value);
        }
    }

    // Strategy 3 & 4: Tool name as key (non-standard key)
    std::vector<std::string> keys = get_json_keys(json_obj);
    for (const auto& key : keys) {
        if (!is_standard_key(key.c_str())) {
            // Found a non-standard key - treat it as tool name
            char* value = nullptr;
            bool is_obj = false;
            if (extract_json_value(json_obj, key.c_str(), &value, &is_obj)) {
                *out_tool_name = static_cast<char*>(malloc(key.size() + 1));
                if (*out_tool_name) {
                    strcpy(*out_tool_name, key.c_str());
                }

                if (is_obj) {
                    // Value is object - use as arguments
                    *out_args_json = value;
                } else if (value) {
                    // Value is scalar - wrap in {"input": value}
                    size_t wrap_len = strlen(value) + 20;
                    *out_args_json = static_cast<char*>(malloc(wrap_len));
                    if (*out_args_json) {
                        snprintf(*out_args_json, wrap_len, "{\"input\":\"%s\"}", value);
                    }
                    free(value);
                } else {
                    *out_args_json = static_cast<char*>(malloc(3));
                    if (*out_args_json) {
                        strcpy(*out_args_json, "{}");
                    }
                }
                return true;
            }
        }
    }

    return false;
}

// =============================================================================
// PARSE TOOL CALL
// =============================================================================

extern "C" rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out_result) {
    if (!llm_output || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize result
    out_result->has_tool_call = RAC_FALSE;
    out_result->tool_name = nullptr;
    out_result->arguments_json = nullptr;
    out_result->clean_text = nullptr;
    out_result->call_id = 0;

    size_t output_len = strlen(llm_output);

    // Find <tool_call> tag
    const char* tag_start = find_str(llm_output, TOOL_CALL_START_TAG);
    if (!tag_start) {
        // No tool call - return clean text as-is
        out_result->clean_text = static_cast<char*>(malloc(output_len + 1));
        if (out_result->clean_text) {
            strcpy(out_result->clean_text, llm_output);
        }
        return RAC_SUCCESS;
    }

    size_t tag_start_pos = tag_start - llm_output;
    size_t json_start_pos = tag_start_pos + strlen(TOOL_CALL_START_TAG);

    // Find </tool_call> end tag
    const char* tag_end = find_str(llm_output + json_start_pos, TOOL_CALL_END_TAG);
    size_t json_end_pos;
    bool has_closing_tag;

    if (tag_end) {
        json_end_pos = (tag_end - llm_output);
        has_closing_tag = true;
    } else {
        // No closing tag - find JSON by matching braces
        size_t brace_end;
        if (!find_matching_brace(llm_output, json_start_pos, &brace_end)) {
            // Can't find valid JSON
            out_result->clean_text = static_cast<char*>(malloc(output_len + 1));
            if (out_result->clean_text) {
                strcpy(out_result->clean_text, llm_output);
            }
            return RAC_SUCCESS;
        }
        json_end_pos = brace_end + 1;  // Include closing brace
        has_closing_tag = false;
    }

    // Extract JSON between tags
    size_t json_len = json_end_pos - json_start_pos;
    char* tool_json_str = static_cast<char*>(malloc(json_len + 1));
    if (!tool_json_str) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(tool_json_str, llm_output + json_start_pos, json_len);
    tool_json_str[json_len] = '\0';

    // Normalize JSON (handle unquoted keys)
    char* normalized_json = nullptr;
    rac_result_t norm_result = rac_tool_call_normalize_json(tool_json_str, &normalized_json);
    free(tool_json_str);

    if (norm_result != RAC_SUCCESS || !normalized_json) {
        out_result->clean_text = static_cast<char*>(malloc(output_len + 1));
        if (out_result->clean_text) {
            strcpy(out_result->clean_text, llm_output);
        }
        return RAC_SUCCESS;
    }

    // Extract tool name and arguments
    char* tool_name = nullptr;
    char* args_json = nullptr;

    if (!extract_tool_name_and_args(normalized_json, &tool_name, &args_json)) {
        free(normalized_json);
        out_result->clean_text = static_cast<char*>(malloc(output_len + 1));
        if (out_result->clean_text) {
            strcpy(out_result->clean_text, llm_output);
        }
        return RAC_SUCCESS;
    }

    free(normalized_json);

    // Build clean text (everything except the tool call tags)
    std::string clean_text;
    clean_text.append(llm_output, tag_start_pos);

    if (has_closing_tag) {
        size_t after_tag = json_end_pos + strlen(TOOL_CALL_END_TAG);
        if (after_tag < output_len) {
            clean_text.append(llm_output + after_tag);
        }
    } else {
        if (json_end_pos < output_len) {
            clean_text.append(llm_output + json_end_pos);
        }
    }

    // Trim whitespace
    size_t trim_start, trim_end;
    trim_whitespace(clean_text.c_str(), clean_text.size(), &trim_start, &trim_end);

    // Populate result
    out_result->has_tool_call = RAC_TRUE;
    out_result->tool_name = tool_name;
    out_result->arguments_json = args_json;

    size_t clean_len = trim_end - trim_start;
    out_result->clean_text = static_cast<char*>(malloc(clean_len + 1));
    if (out_result->clean_text) {
        memcpy(out_result->clean_text, clean_text.c_str() + trim_start, clean_len);
        out_result->clean_text[clean_len] = '\0';
    }

    // Generate unique call ID based on timestamp
    out_result->call_id = static_cast<int64_t>(time(nullptr)) * 1000 + (rand() % 1000);

    return RAC_SUCCESS;
}

extern "C" void rac_tool_call_free(rac_tool_call_t* result) {
    if (!result) {
        return;
    }

    if (result->tool_name) {
        free(result->tool_name);
        result->tool_name = nullptr;
    }

    if (result->arguments_json) {
        free(result->arguments_json);
        result->arguments_json = nullptr;
    }

    if (result->clean_text) {
        free(result->clean_text);
        result->clean_text = nullptr;
    }

    result->has_tool_call = RAC_FALSE;
    result->call_id = 0;
}

// =============================================================================
// PROMPT FORMATTING
// =============================================================================

/**
 * @brief Escape a string for JSON output (manual implementation)
 */
static std::string escape_json_string(const char* str) {
    if (!str) {
        return "";
    }

    std::string result;
    result.reserve(strlen(str) + 16);

    for (size_t i = 0; str[i]; i++) {
        char c = str[i];
        switch (c) {
        case '"':
            result += "\\\"";
            break;
        case '\\':
            result += "\\\\";
            break;
        case '\n':
            result += "\\n";
            break;
        case '\r':
            result += "\\r";
            break;
        case '\t':
            result += "\\t";
            break;
        default:
            result += c;
            break;
        }
    }

    return result;
}

/**
 * @brief Get parameter type name
 */
static const char* get_param_type_name(rac_tool_param_type_t type) {
    switch (type) {
    case RAC_TOOL_PARAM_STRING:
        return "string";
    case RAC_TOOL_PARAM_NUMBER:
        return "number";
    case RAC_TOOL_PARAM_BOOLEAN:
        return "boolean";
    case RAC_TOOL_PARAM_OBJECT:
        return "object";
    case RAC_TOOL_PARAM_ARRAY:
        return "array";
    default:
        return "unknown";
    }
}

extern "C" rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t* definitions,
                                                    size_t num_definitions, char** out_prompt) {
    if (!out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!definitions || num_definitions == 0) {
        *out_prompt = static_cast<char*>(malloc(1));
        if (*out_prompt) {
            (*out_prompt)[0] = '\0';
        }
        return RAC_SUCCESS;
    }

    std::string prompt;
    prompt.reserve(1024);

    prompt += "You have access to these tools:\n\n";

    for (size_t i = 0; i < num_definitions; i++) {
        const rac_tool_definition_t& tool = definitions[i];

        prompt += "- ";
        prompt += tool.name ? tool.name : "unknown";
        prompt += ": ";
        prompt += tool.description ? tool.description : "";
        prompt += "\n";

        if (tool.parameters && tool.num_parameters > 0) {
            prompt += "  Parameters:\n";
            for (size_t j = 0; j < tool.num_parameters; j++) {
                const rac_tool_parameter_t& param = tool.parameters[j];
                prompt += "    - ";
                prompt += param.name ? param.name : "unknown";
                prompt += " (";
                prompt += get_param_type_name(param.type);
                if (param.required) {
                    prompt += ", required";
                }
                prompt += "): ";
                prompt += param.description ? param.description : "";
                prompt += "\n";
            }
        }
        prompt += "\n";
    }

    prompt += "TOOL CALLING FORMAT - YOU MUST USE THIS EXACT FORMAT:\n";
    prompt += "When you need to use a tool, output ONLY this (no other text before or after):\n";
    prompt += "<tool_call>{\"tool\": \"TOOL_NAME\", \"arguments\": {\"PARAM_NAME\": \"VALUE\"}}</tool_call>\n\n";

    prompt += "EXAMPLE - If user asks \"what's the weather in Paris\":\n";
    prompt += "<tool_call>{\"tool\": \"get_weather\", \"arguments\": {\"location\": \"Paris\"}}</tool_call>\n\n";

    prompt += "RULES:\n";
    prompt += "1. For greetings or general chat, respond normally without tools\n";
    prompt += "2. When using a tool, output ONLY the <tool_call> tag, nothing else\n";
    prompt += "3. Use the exact parameter names shown in the tool definitions above";

    *out_prompt = static_cast<char*>(malloc(prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, prompt.c_str(), prompt.size() + 1);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt) {
    if (!out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!tools_json || strlen(tools_json) == 0 || strcmp(tools_json, "[]") == 0) {
        *out_prompt = static_cast<char*>(malloc(1));
        if (*out_prompt) {
            (*out_prompt)[0] = '\0';
        }
        return RAC_SUCCESS;
    }

    // Build comprehensive prompt including the JSON
    std::string prompt;
    prompt.reserve(1024 + strlen(tools_json));

    prompt += "# Available Tools\n\n";
    prompt += "You have access to the following tools. ONLY use them when the user specifically asks for information that requires them:\n\n";
    prompt += tools_json;
    prompt += "\n\n";

    prompt += "# Tool Usage Instructions\n\n";
    prompt += "IMPORTANT RULES:\n";
    prompt += "- For normal conversation (greetings, questions, chat), respond naturally WITHOUT using any tools.\n";
    prompt += "- Only use a tool if the user explicitly asks for something the tool provides.\n";
    prompt += "- Do NOT use tools for general questions or conversation.\n\n";

    prompt += "When you DO need to use a tool, respond with:\n";
    prompt += "<tool_call>{\"tool\": \"tool_name\", \"arguments\": {\"param1\": \"value1\"}}</tool_call>\n\n";

    prompt += "If the user just says \"hello\" or asks a general question, respond normally without any tool calls.";

    *out_prompt = static_cast<char*>(malloc(prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, prompt.c_str(), prompt.size() + 1);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt,
                                                           const char* tools_json,
                                                           const rac_tool_calling_options_t* options,
                                                           char** out_prompt) {
    if (!user_prompt || !out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Format tools prompt
    char* tools_prompt = nullptr;
    rac_result_t result = rac_tool_call_format_prompt_json(tools_json, &tools_prompt);
    if (result != RAC_SUCCESS) {
        return result;
    }

    std::string full_prompt;
    full_prompt.reserve(2048);

    // Add system prompt if provided
    if (options && options->system_prompt) {
        if (options->replace_system_prompt) {
            // Replace entirely - just use the system prompt
            full_prompt += options->system_prompt;
            full_prompt += "\n\n";
        } else {
            // Append tool instructions after system prompt
            full_prompt += options->system_prompt;
            full_prompt += "\n\n";
        }
    }

    // Add tools prompt (unless replace_system_prompt is true and we already have system_prompt)
    if (!(options && options->replace_system_prompt && options->system_prompt)) {
        if (tools_prompt && strlen(tools_prompt) > 0) {
            full_prompt += tools_prompt;
            full_prompt += "\n\n";
        }
    }

    // Add user prompt
    full_prompt += "User: ";
    full_prompt += user_prompt;

    free(tools_prompt);

    *out_prompt = static_cast<char*>(malloc(full_prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, full_prompt.c_str(), full_prompt.size() + 1);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tool_call_build_followup_prompt(const char* original_user_prompt,
                                                            const char* tools_prompt,
                                                            const char* tool_name,
                                                            const char* tool_result_json,
                                                            rac_bool_t keep_tools_available,
                                                            char** out_prompt) {
    if (!original_user_prompt || !tool_name || !out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string prompt;
    prompt.reserve(1024);

    // Include tools again if keepToolsAvailable
    if (keep_tools_available && tools_prompt && strlen(tools_prompt) > 0) {
        prompt += tools_prompt;
        prompt += "\n\n";
    }

    prompt += "Previous user question: ";
    prompt += original_user_prompt;
    prompt += "\n\n";

    prompt += "Tool '";
    prompt += tool_name;
    prompt += "' was executed with this result:\n";
    prompt += tool_result_json ? tool_result_json : "{}";
    prompt += "\n\n";

    if (keep_tools_available) {
        prompt += "Using this information, respond to the user's original question. ";
        prompt += "You may use additional tools if needed.";
    } else {
        prompt += "Using this information, provide a natural response to the user's original question. ";
        prompt += "Do not use any tool tags in your response - just respond naturally.";
    }

    *out_prompt = static_cast<char*>(malloc(prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, prompt.c_str(), prompt.size() + 1);

    return RAC_SUCCESS;
}

// =============================================================================
// JSON SERIALIZATION UTILITIES
// =============================================================================

extern "C" rac_result_t rac_tool_call_definitions_to_json(const rac_tool_definition_t* definitions,
                                                          size_t num_definitions,
                                                          char** out_json) {
    if (!out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!definitions || num_definitions == 0) {
        *out_json = static_cast<char*>(malloc(3));
        if (*out_json) {
            strcpy(*out_json, "[]");
        }
        return RAC_SUCCESS;
    }

    std::string json;
    json.reserve(512 * num_definitions);
    json += "[";

    for (size_t i = 0; i < num_definitions; i++) {
        if (i > 0) {
            json += ",";
        }

        const rac_tool_definition_t& tool = definitions[i];

        json += "{";
        json += "\"name\":\"";
        json += escape_json_string(tool.name);
        json += "\",";
        json += "\"description\":\"";
        json += escape_json_string(tool.description);
        json += "\",";
        json += "\"parameters\":[";

        if (tool.parameters) {
            for (size_t j = 0; j < tool.num_parameters; j++) {
                if (j > 0) {
                    json += ",";
                }

                const rac_tool_parameter_t& param = tool.parameters[j];

                json += "{";
                json += "\"name\":\"";
                json += escape_json_string(param.name);
                json += "\",";
                json += "\"type\":\"";
                json += get_param_type_name(param.type);
                json += "\",";
                json += "\"description\":\"";
                json += escape_json_string(param.description);
                json += "\",";
                json += "\"required\":";
                json += param.required ? "true" : "false";
                json += "}";
            }
        }

        json += "]";

        if (tool.category) {
            json += ",\"category\":\"";
            json += escape_json_string(tool.category);
            json += "\"";
        }

        json += "}";
    }

    json += "]";

    *out_json = static_cast<char*>(malloc(json.size() + 1));
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_json, json.c_str(), json.size() + 1);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tool_call_result_to_json(const char* tool_name, rac_bool_t success,
                                                     const char* result_json,
                                                     const char* error_message,
                                                     char** out_json) {
    if (!tool_name || !out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string json;
    json.reserve(256);

    json += "{";
    json += "\"toolName\":\"";
    json += escape_json_string(tool_name);
    json += "\",";
    json += "\"success\":";
    json += success ? "true" : "false";

    if (success && result_json) {
        json += ",\"result\":";
        json += result_json;  // Already JSON
    }

    if (!success && error_message) {
        json += ",\"error\":\"";
        json += escape_json_string(error_message);
        json += "\"";
    }

    json += "}";

    *out_json = static_cast<char*>(malloc(json.size() + 1));
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_json, json.c_str(), json.size() + 1);

    return RAC_SUCCESS;
}
