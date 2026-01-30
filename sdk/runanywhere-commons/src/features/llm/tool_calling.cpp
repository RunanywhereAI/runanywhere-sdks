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
 *
 * Supported formats:
 * - DEFAULT:  <tool_call>{"tool":"name","arguments":{}}</tool_call> (Most general models)
 * - LFM2:     <|tool_call_start|>[func(arg="val")]<|tool_call_end|> (Liquid AI models)
 */

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_tool_calling.h"

// =============================================================================
// CONSTANTS - Format-specific tags
// =============================================================================

// Format: DEFAULT (<tool_call>JSON</tool_call>)
static const char* TAG_DEFAULT_START = "<tool_call>";
static const char* TAG_DEFAULT_END = "</tool_call>";

// Format: LFM2 (Liquid AI)
static const char* TAG_LFM2_START = "<|tool_call_start|>";
static const char* TAG_LFM2_END = "<|tool_call_end|>";

// Format names for logging/display
static const char* FORMAT_NAMES[] = {
    "Default",        // RAC_TOOL_FORMAT_DEFAULT
    "LFM2 (Liquid)",  // RAC_TOOL_FORMAT_LFM2
};

// Legacy alias for backward compatibility
static const char* TOOL_CALL_START_TAG = TAG_DEFAULT_START;
static const char* TOOL_CALL_END_TAG = TAG_DEFAULT_END;

// Standard keys for tool name (case-insensitive matching)
static const char* TOOL_NAME_KEYS[] = {"tool", "name", "function", "func", "method",
                                       "action", "command", nullptr};

// Standard keys for arguments (case-insensitive matching)
static const char* ARGUMENT_KEYS[] = {"arguments", "args", "params", "parameters", "input", nullptr};

// =============================================================================
// FORMAT DETECTION AND NAMING
// =============================================================================

extern "C" const char* rac_tool_call_format_name(rac_tool_call_format_t format) {
    if (format >= 0 && format < RAC_TOOL_FORMAT_COUNT) {
        return FORMAT_NAMES[format];
    }
    return "Unknown";
}

extern "C" rac_tool_call_format_t rac_tool_call_format_from_name(const char* name) {
    if (!name) {
        return RAC_TOOL_FORMAT_DEFAULT;
    }
    
    // Case-insensitive comparison
    std::string name_lower(name);
    for (char& c : name_lower) {
        c = static_cast<char>(tolower(c));
    }
    
    if (name_lower == "default") {
        return RAC_TOOL_FORMAT_DEFAULT;
    } else if (name_lower == "lfm2" || name_lower == "lfm" || name_lower == "liquid") {
        return RAC_TOOL_FORMAT_LFM2;
    }
    
    // Unknown format - default to DEFAULT
    RAC_LOG_WARNING("ToolCalling", "Unknown tool call format name: '%s', using default", name);
    return RAC_TOOL_FORMAT_DEFAULT;
}

extern "C" rac_tool_call_format_t rac_tool_call_detect_format(const char* llm_output) {
    if (!llm_output) {
        return RAC_TOOL_FORMAT_DEFAULT;
    }

    // Check for each format's start tag
    // Order matters - check more specific formats first

    // Check LFM2 format: <|tool_call_start|>
    if (strstr(llm_output, TAG_LFM2_START) != nullptr) {
        return RAC_TOOL_FORMAT_LFM2;
    }

    // Check Default format: <tool_call>
    if (strstr(llm_output, TAG_DEFAULT_START) != nullptr) {
        return RAC_TOOL_FORMAT_DEFAULT;
    }

    // No recognizable format detected - return DEFAULT
    return RAC_TOOL_FORMAT_DEFAULT;
}

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
// FORMAT-SPECIFIC PARSERS
// =============================================================================

/**
 * @brief Parse LFM2 (Liquid AI) format: <|tool_call_start|>[func(arg="val")]<|tool_call_end|>
 *
 * LFM2 uses Pythonic function call syntax:
 * [func_name(arg1="value1", arg2="value2")]
 *
 * @return true if successfully parsed, false otherwise
 */
static bool parse_lfm2_format(const char* llm_output, char** out_tool_name, char** out_args_json,
                              char** out_clean_text) {
    *out_tool_name = nullptr;
    *out_args_json = nullptr;
    *out_clean_text = nullptr;

    RAC_LOG_INFO("ToolCalling", "parse_lfm2_format: input='%.200s'%s", 
                 llm_output, strlen(llm_output) > 200 ? "..." : "");

    // Find start tag
    const char* start_tag = strstr(llm_output, TAG_LFM2_START);
    if (!start_tag) {
        RAC_LOG_INFO("ToolCalling", "LFM2 start tag '%s' not found in output", TAG_LFM2_START);
        return false;
    }

    RAC_LOG_INFO("ToolCalling", "Found LFM2 start tag at position: %zu", (size_t)(start_tag - llm_output));

    size_t tag_start_pos = start_tag - llm_output;
    const char* content_start = start_tag + strlen(TAG_LFM2_START);

    // Find end tag
    const char* end_tag = strstr(content_start, TAG_LFM2_END);
    if (!end_tag) {
        // Try to parse until end of line or end of string
        const char* line_end = strchr(content_start, '\n');
        if (line_end) {
            end_tag = line_end;
        } else {
            end_tag = content_start + strlen(content_start);
        }
    }

    // Extract content between tags
    size_t content_len = end_tag - content_start;
    std::string content(content_start, content_len);

    // Parse Pythonic format: [func_name(arg1="val1", arg2="val2")]
    // First, strip leading/trailing whitespace and brackets
    size_t start = 0, end = content.size();
    while (start < end && (content[start] == ' ' || content[start] == '\n' || content[start] == '[')) {
        start++;
    }
    while (end > start && (content[end - 1] == ' ' || content[end - 1] == '\n' || content[end - 1] == ']')) {
        end--;
    }

    if (start >= end) {
        return false;
    }

    std::string call_str = content.substr(start, end - start);

    RAC_LOG_INFO("ToolCalling", "LFM2 call_str: '%s'", call_str.c_str());

    // Find function name (everything before '(')
    size_t paren_pos = call_str.find('(');
    if (paren_pos == std::string::npos) {
        // No arguments - whole thing is function name
        *out_tool_name = static_cast<char*>(malloc(call_str.size() + 1));
        if (*out_tool_name) {
            strcpy(*out_tool_name, call_str.c_str());
        }
        *out_args_json = static_cast<char*>(malloc(3));
        if (*out_args_json) {
            strcpy(*out_args_json, "{}");
        }
    } else {
        std::string func_name = call_str.substr(0, paren_pos);

        // Trim whitespace from function name
        while (!func_name.empty() && func_name.back() == ' ') {
            func_name.pop_back();
        }

        *out_tool_name = static_cast<char*>(malloc(func_name.size() + 1));
        if (*out_tool_name) {
            strcpy(*out_tool_name, func_name.c_str());
        }

        // Parse arguments: arg1="val1", arg2="val2", ...
        // Convert to JSON format
        size_t args_start = paren_pos + 1;
        size_t args_end = call_str.rfind(')');
        if (args_end == std::string::npos) {
            args_end = call_str.size();
        }

        std::string args_str = call_str.substr(args_start, args_end - args_start);

        RAC_LOG_INFO("ToolCalling", "LFM2 args_str: '%s' (paren=%zu, end=%zu)", 
                     args_str.c_str(), paren_pos, args_end);

        // Convert Python-style args to JSON
        std::string json_args = "{";
        bool first_arg = true;
        bool in_string = false;
        char string_char = 0;
        std::string current_key;
        std::string current_value;
        bool parsing_key = true;

        for (size_t i = 0; i < args_str.size(); i++) {
            char c = args_str[i];

            if (in_string) {
                if (c == string_char && (i == 0 || args_str[i - 1] != '\\')) {
                    in_string = false;
                    // End of value
                    if (!current_key.empty()) {
                        if (!first_arg) {
                            json_args += ",";
                        }
                        json_args += "\"" + current_key + "\":\"" + current_value + "\"";
                        first_arg = false;
                        current_key.clear();
                        current_value.clear();
                        parsing_key = true;
                    }
                } else {
                    current_value += c;
                }
            } else {
                if (c == '"' || c == '\'') {
                    in_string = true;
                    string_char = c;
                    parsing_key = false;
                } else if (c == '=') {
                    parsing_key = false;
                } else if (c == ',') {
                    // Handle unquoted values or numeric values
                    if (!current_key.empty() && !current_value.empty()) {
                        if (!first_arg) {
                            json_args += ",";
                        }
                        // Check if value is numeric
                        bool is_numeric = true;
                        for (char vc : current_value) {
                            if (!isdigit(vc) && vc != '.' && vc != '-') {
                                is_numeric = false;
                                break;
                            }
                        }
                        if (is_numeric) {
                            json_args += "\"" + current_key + "\":" + current_value;
                        } else {
                            json_args += "\"" + current_key + "\":\"" + current_value + "\"";
                        }
                        first_arg = false;
                    }
                    current_key.clear();
                    current_value.clear();
                    parsing_key = true;
                } else if (c != ' ' || in_string) {
                    if (parsing_key) {
                        current_key += c;
                    } else {
                        current_value += c;
                    }
                }
            }
        }

        // Handle last argument
        if (!current_key.empty() && !current_value.empty()) {
            if (!first_arg) {
                json_args += ",";
            }
            bool is_numeric = true;
            for (char vc : current_value) {
                if (!isdigit(vc) && vc != '.' && vc != '-') {
                    is_numeric = false;
                    break;
                }
            }
            if (is_numeric) {
                json_args += "\"" + current_key + "\":" + current_value;
            } else {
                json_args += "\"" + current_key + "\":\"" + current_value + "\"";
            }
        }

        json_args += "}";

        RAC_LOG_INFO("ToolCalling", "LFM2 parsed json_args: '%s'", json_args.c_str());

        *out_args_json = static_cast<char*>(malloc(json_args.size() + 1));
        if (*out_args_json) {
            strcpy(*out_args_json, json_args.c_str());
        }
    }

    RAC_LOG_INFO("ToolCalling", "LFM2 RESULT: tool='%s', args='%s'",
                 *out_tool_name ? *out_tool_name : "(null)",
                 *out_args_json ? *out_args_json : "(null)");

    // Build clean text
    std::string clean_text;
    clean_text.append(llm_output, tag_start_pos);

    const char* after_end = end_tag;
    if (strstr(end_tag, TAG_LFM2_END) == end_tag) {
        after_end = end_tag + strlen(TAG_LFM2_END);
    }
    if (*after_end) {
        clean_text.append(after_end);
    }

    // Trim
    size_t trim_start = 0, trim_end = clean_text.size();
    while (trim_start < trim_end && (clean_text[trim_start] == ' ' || clean_text[trim_start] == '\n')) {
        trim_start++;
    }
    while (trim_end > trim_start && (clean_text[trim_end - 1] == ' ' || clean_text[trim_end - 1] == '\n')) {
        trim_end--;
    }

    *out_clean_text = static_cast<char*>(malloc(trim_end - trim_start + 1));
    if (*out_clean_text) {
        memcpy(*out_clean_text, clean_text.c_str() + trim_start, trim_end - trim_start);
        (*out_clean_text)[trim_end - trim_start] = '\0';
    }

    return *out_tool_name != nullptr;
}

/**
 * @brief Parse default format: <tool_call>JSON</tool_call>
 *
 * This is the original SDK format with JSON inside the tags.
 * Handles edge cases like missing closing tags, unquoted keys, etc.
 *
 * @return true if successfully parsed, false otherwise
 */
static bool parse_default_format(const char* llm_output, char** out_tool_name, char** out_args_json,
                                 char** out_clean_text);

// =============================================================================
// PARSE TOOL CALL - Main entry points
// =============================================================================

extern "C" rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out_result) {
    // Auto-detect format from output, then parse
    rac_tool_call_format_t detected = rac_tool_call_detect_format(llm_output);
    return rac_tool_call_parse_with_format(llm_output, detected, out_result);
}

/**
 * @brief Implementation of parse_default_format
 *
 * Parses the default <tool_call>JSON</tool_call> format.
 */
static bool parse_default_format(const char* llm_output, char** out_tool_name, char** out_args_json,
                                 char** out_clean_text) {
    *out_tool_name = nullptr;
    *out_args_json = nullptr;
    *out_clean_text = nullptr;

    size_t output_len = strlen(llm_output);

    // Find <tool_call> tag
    const char* tag_start = find_str(llm_output, TAG_DEFAULT_START);
    if (!tag_start) {
        return false;
    }

    size_t tag_start_pos = tag_start - llm_output;
    size_t json_start_pos = tag_start_pos + strlen(TAG_DEFAULT_START);

    // Find </tool_call> end tag
    const char* tag_end = find_str(llm_output + json_start_pos, TAG_DEFAULT_END);
    size_t json_end_pos;
    bool has_closing_tag;

    if (tag_end) {
        json_end_pos = (tag_end - llm_output);
        has_closing_tag = true;
    } else {
        // No closing tag - find JSON by matching braces
        size_t brace_end;
        if (!find_matching_brace(llm_output, json_start_pos, &brace_end)) {
            return false;
        }
        json_end_pos = brace_end + 1;
        has_closing_tag = false;
    }

    // Extract JSON between tags
    size_t json_len = json_end_pos - json_start_pos;
    char* tool_json_str = static_cast<char*>(malloc(json_len + 1));
    if (!tool_json_str) {
        return false;
    }
    memcpy(tool_json_str, llm_output + json_start_pos, json_len);
    tool_json_str[json_len] = '\0';

    // Normalize JSON (handle unquoted keys)
    char* normalized_json = nullptr;
    rac_result_t norm_result = rac_tool_call_normalize_json(tool_json_str, &normalized_json);
    free(tool_json_str);

    if (norm_result != RAC_SUCCESS || !normalized_json) {
        return false;
    }

    // Extract tool name and arguments
    if (!extract_tool_name_and_args(normalized_json, out_tool_name, out_args_json)) {
        free(normalized_json);
        return false;
    }

    free(normalized_json);

    // Build clean text (everything except the tool call tags)
    std::string clean_text;
    clean_text.append(llm_output, tag_start_pos);

    if (has_closing_tag) {
        size_t after_tag = json_end_pos + strlen(TAG_DEFAULT_END);
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

    size_t clean_len = trim_end - trim_start;
    *out_clean_text = static_cast<char*>(malloc(clean_len + 1));
    if (*out_clean_text) {
        memcpy(*out_clean_text, clean_text.c_str() + trim_start, clean_len);
        (*out_clean_text)[clean_len] = '\0';
    }

    return *out_tool_name != nullptr;
}

extern "C" rac_result_t rac_tool_call_parse_with_format(const char* llm_output,
                                                        rac_tool_call_format_t format,
                                                        rac_tool_call_t* out_result) {
    if (!llm_output || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize result
    out_result->has_tool_call = RAC_FALSE;
    out_result->tool_name = nullptr;
    out_result->arguments_json = nullptr;
    out_result->clean_text = nullptr;
    out_result->call_id = 0;
    out_result->format = RAC_TOOL_FORMAT_DEFAULT;

    size_t output_len = strlen(llm_output);

    // Parse using the appropriate format parser
    char* tool_name = nullptr;
    char* args_json = nullptr;
    char* clean_text = nullptr;
    bool parsed = false;

    switch (format) {
    case RAC_TOOL_FORMAT_DEFAULT:
        parsed = parse_default_format(llm_output, &tool_name, &args_json, &clean_text);
        break;

    case RAC_TOOL_FORMAT_LFM2:
        parsed = parse_lfm2_format(llm_output, &tool_name, &args_json, &clean_text);
        break;

    default:
        parsed = false;
        break;
    }

    if (parsed && tool_name) {
        out_result->has_tool_call = RAC_TRUE;
        out_result->tool_name = tool_name;
        out_result->arguments_json = args_json;
        out_result->clean_text = clean_text;
        out_result->format = format;
        out_result->call_id = static_cast<int64_t>(time(nullptr)) * 1000 + (rand() % 1000);
    } else {
        // Parsing failed - clean up any partial results
        if (tool_name) free(tool_name);
        if (args_json) free(args_json);
        if (clean_text) free(clean_text);

        // Return original text as clean_text
        out_result->clean_text = static_cast<char*>(malloc(output_len + 1));
        if (out_result->clean_text) {
            strcpy(out_result->clean_text, llm_output);
        }
    }

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

/**
 * @brief Generate format-specific tool calling instructions
 *
 * Returns the format-specific syntax, examples, and rules.
 */
static std::string get_format_instructions(rac_tool_call_format_t format) {
    std::string instructions;

    switch (format) {
    case RAC_TOOL_FORMAT_LFM2:
        // Liquid AI LFM2 format
        instructions += "TOOL CALLING FORMAT (LFM2):\n";
        instructions += "When you need to use a tool, output ONLY this format:\n";
        instructions += "<|tool_call_start|>[TOOL_NAME(param=\"VALUE_FROM_USER_QUERY\")]<|tool_call_end|>\n\n";

        instructions += "CRITICAL: Extract the EXACT value from the user's question:\n";
        instructions += "- User asks 'weather in Tokyo' -> <|tool_call_start|>[get_weather(location=\"Tokyo\")]<|tool_call_end|>\n";
        instructions += "- User asks 'weather in sf' -> <|tool_call_start|>[get_weather(location=\"San Francisco\")]<|tool_call_end|>\n\n";

        instructions += "RULES:\n";
        instructions += "1. For greetings or general chat, respond normally without tools\n";
        instructions += "2. Use Python-style function call syntax inside the tags\n";
        instructions += "3. String values MUST be quoted with double quotes\n";
        instructions += "4. Multiple arguments are separated by commas";
        break;

    case RAC_TOOL_FORMAT_DEFAULT:
    default:
        // Default SDK format
        instructions += "TOOL CALLING FORMAT - YOU MUST USE THIS EXACT FORMAT:\n";
        instructions += "When you need to use a tool, output ONLY this (no other text before or after):\n";
        instructions += "<tool_call>{\"tool\": \"TOOL_NAME\", \"arguments\": {\"PARAM_NAME\": \"VALUE_FROM_USER_QUERY\"}}</tool_call>\n\n";

        instructions += "CRITICAL: Extract the EXACT value from the user's question:\n";
        instructions += "- User asks 'weather in Tokyo' -> <tool_call>{\"tool\": \"get_weather\", \"arguments\": {\"location\": \"Tokyo\"}}</tool_call>\n";
        instructions += "- User asks 'weather in sf' -> <tool_call>{\"tool\": \"get_weather\", \"arguments\": {\"location\": \"San Francisco\"}}</tool_call>\n\n";

        instructions += "RULES:\n";
        instructions += "1. For greetings or general chat, respond normally without tools\n";
        instructions += "2. When using a tool, output ONLY the <tool_call> tag, nothing else\n";
        instructions += "3. Use the exact parameter names shown in the tool definitions above";
        break;
    }

    return instructions;
}

/**
 * @brief Generate format-specific example for JSON prompt
 */
static std::string get_format_example_json(rac_tool_call_format_t format) {
    std::string example;

    switch (format) {
    case RAC_TOOL_FORMAT_LFM2:
        // LFM2 format - enhanced with more math examples for better reliability
        example += "## OUTPUT FORMAT\n";
        example += "You MUST respond with ONLY a tool call in this exact format:\n";
        example += "<|tool_call_start|>[function_name(param=\"value\")]<|tool_call_end|>\n\n";
        example += "CRITICAL: Always include the FULL format with <|tool_call_start|> and <|tool_call_end|> tags.\n\n";
        example += "## EXAMPLES\n";
        example += "Q: What's the weather in NYC?\n";
        example += "A: <|tool_call_start|>[get_weather(location=\"New York\")]<|tool_call_end|>\n\n";
        example += "Q: weather in sf\n";
        example += "A: <|tool_call_start|>[get_weather(location=\"San Francisco\")]<|tool_call_end|>\n\n";
        example += "Q: calculate 2+2\n";
        example += "A: <|tool_call_start|>[calculate(expression=\"2+2\")]<|tool_call_end|>\n\n";
        example += "Q: What's 5*10?\n";
        example += "A: <|tool_call_start|>[calculate(expression=\"5*10\")]<|tool_call_end|>\n\n";
        example += "Q: What is 100/4?\n";
        example += "A: <|tool_call_start|>[calculate(expression=\"100/4\")]<|tool_call_end|>\n";
        break;

    case RAC_TOOL_FORMAT_DEFAULT:
    default:
        example += "## OUTPUT FORMAT\n";
        example += "You MUST respond with ONLY a tool call in this exact format:\n";
        example += "<tool_call>{\"tool\": \"function_name\", \"arguments\": {\"param\": \"value\"}}</tool_call>\n\n";
        example += "## EXAMPLES\n";
        example += "Q: What's the weather in NYC?\n";
        example += "A: <tool_call>{\"tool\": \"get_weather\", \"arguments\": {\"location\": \"New York\"}}</tool_call>\n\n";
        example += "Q: weather in sf\n";
        example += "A: <tool_call>{\"tool\": \"get_weather\", \"arguments\": {\"location\": \"San Francisco\"}}</tool_call>\n\n";
        example += "Q: calculate 2+2\n";
        example += "A: <tool_call>{\"tool\": \"calculate\", \"arguments\": {\"expression\": \"2+2\"}}</tool_call>\n";
        break;
    }

    return example;
}

// =============================================================================
// FORMAT-AWARE PROMPT GENERATION
// =============================================================================

extern "C" rac_result_t rac_tool_call_format_prompt_with_format(const rac_tool_definition_t* definitions,
                                                                size_t num_definitions,
                                                                rac_tool_call_format_t format,
                                                                char** out_prompt) {
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

    rac_tool_call_format_t actual_format = format;

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

    // Add format-specific instructions
    prompt += get_format_instructions(actual_format);

    *out_prompt = static_cast<char*>(malloc(prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, prompt.c_str(), prompt.size() + 1);

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tool_call_format_prompt_json_with_format(const char* tools_json,
                                                                     rac_tool_call_format_t format,
                                                                     char** out_prompt) {
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

    rac_tool_call_format_t actual_format = format;

    std::string prompt;
    prompt.reserve(1024 + strlen(tools_json));

    prompt += "# TOOLS\n";
    prompt += tools_json;
    prompt += "\n\n";

    // Add format-specific example with direct instructions
    prompt += get_format_example_json(actual_format);

    prompt += "\n\n## RULES\n";
    prompt += "- Weather question = call get_weather\n";
    prompt += "- Math/calculation question (add, subtract, multiply, divide, \"what's X*Y\", etc.) = call calculate with the EXPRESSION as a string\n";
    prompt += "- Time question = call get_current_time\n";
    prompt += "- DO NOT compute answers yourself. ALWAYS use the tool with the original expression.\n";

    // Format-specific tag instructions
    if (actual_format == RAC_TOOL_FORMAT_LFM2) {
        prompt += "- ALWAYS include <|tool_call_start|> and <|tool_call_end|> tags.\n";
    } else {
        prompt += "- ALWAYS include <tool_call> and </tool_call> tags.\n";
    }
    
    RAC_LOG_INFO("ToolCalling", "Generated tool prompt (format=%d): %.500s...", 
                 (int)actual_format, prompt.c_str());

    *out_prompt = static_cast<char*>(malloc(prompt.size() + 1));
    if (!*out_prompt) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*out_prompt, prompt.c_str(), prompt.size() + 1);

    return RAC_SUCCESS;
}

// =============================================================================
// LEGACY PROMPT GENERATION (uses DEFAULT format)
// =============================================================================

extern "C" rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t* definitions,
                                                    size_t num_definitions, char** out_prompt) {
    // Delegate to format-aware version with DEFAULT format
    return rac_tool_call_format_prompt_with_format(definitions, num_definitions,
                                                   RAC_TOOL_FORMAT_DEFAULT, out_prompt);
}

extern "C" rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt) {
    // Delegate to format-aware version with DEFAULT format
    return rac_tool_call_format_prompt_json_with_format(tools_json, RAC_TOOL_FORMAT_DEFAULT, out_prompt);
}

extern "C" rac_result_t rac_tool_call_format_prompt_json_with_format_name(const char* tools_json,
                                                                          const char* format_name,
                                                                          char** out_prompt) {
    // Convert format name to enum and delegate
    rac_tool_call_format_t format = rac_tool_call_format_from_name(format_name);
    RAC_LOG_INFO("ToolCalling", "Formatting prompt with format_name='%s' -> enum=%d", 
                 format_name ? format_name : "null", (int)format);
    return rac_tool_call_format_prompt_json_with_format(tools_json, format, out_prompt);
}

extern "C" rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt,
                                                           const char* tools_json,
                                                           const rac_tool_calling_options_t* options,
                                                           char** out_prompt) {
    if (!user_prompt || !out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Get format from options (default to DEFAULT)
    rac_tool_call_format_t format = options ? options->format : RAC_TOOL_FORMAT_DEFAULT;

    // Format tools prompt with the specified format
    char* tools_prompt = nullptr;
    rac_result_t result = rac_tool_call_format_prompt_json_with_format(tools_json, format, &tools_prompt);
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
