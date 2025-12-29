/**
 * @file rac_structured_error.cpp
 * @brief RunAnywhere Commons - Structured Error Implementation
 */

#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>

#if defined(__APPLE__) || defined(__linux__)
#include <execinfo.h>
#endif

// =============================================================================
// THREAD-LOCAL STORAGE
// =============================================================================

namespace {

thread_local rac_error_t g_last_error;
thread_local bool g_has_last_error = false;

// Helper to safely copy strings
void safe_strcpy(char* dest, size_t dest_size, const char* src) {
    if (!dest || dest_size == 0) return;
    if (!src) {
        dest[0] = '\0';
        return;
    }
    size_t len = strlen(src);
    if (len >= dest_size) len = dest_size - 1;
    memcpy(dest, src, len);
    dest[len] = '\0';
}

// Get current timestamp in milliseconds
int64_t current_timestamp_ms() {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->now_ms) {
        return adapter->now_ms(adapter->user_data);
    }
    // Fallback
    return static_cast<int64_t>(time(nullptr)) * 1000;
}

} // anonymous namespace

// =============================================================================
// ERROR CREATION & DESTRUCTION
// =============================================================================

extern "C" {

rac_error_t* rac_error_create(rac_result_t code, rac_error_category_t category,
                               const char* message) {
    rac_error_t* error = static_cast<rac_error_t*>(calloc(1, sizeof(rac_error_t)));
    if (!error) return nullptr;

    error->code = code;
    error->category = category;
    safe_strcpy(error->message, sizeof(error->message), message);
    error->timestamp_ms = current_timestamp_ms();

    return error;
}

rac_error_t* rac_error_create_at(rac_result_t code, rac_error_category_t category,
                                  const char* message, const char* file, int32_t line,
                                  const char* function) {
    rac_error_t* error = rac_error_create(code, category, message);
    if (error) {
        rac_error_set_source(error, file, line, function);
    }
    return error;
}

rac_error_t* rac_error_createf(rac_result_t code, rac_error_category_t category,
                                const char* format, ...) {
    char buffer[RAC_MAX_ERROR_MESSAGE];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    return rac_error_create(code, category, buffer);
}

void rac_error_destroy(rac_error_t* error) {
    free(error);
}

rac_error_t* rac_error_copy(const rac_error_t* error) {
    if (!error) return nullptr;

    rac_error_t* copy = static_cast<rac_error_t*>(malloc(sizeof(rac_error_t)));
    if (copy) {
        memcpy(copy, error, sizeof(rac_error_t));
    }
    return copy;
}

// =============================================================================
// ERROR CONFIGURATION
// =============================================================================

void rac_error_set_source(rac_error_t* error, const char* file, int32_t line,
                           const char* function) {
    if (!error) return;

    // Extract filename from path
    if (file) {
        const char* last_slash = strrchr(file, '/');
        const char* last_backslash = strrchr(file, '\\');
        const char* last_sep = (last_slash > last_backslash) ? last_slash : last_backslash;
        const char* filename = last_sep ? last_sep + 1 : file;
        safe_strcpy(error->source_file, sizeof(error->source_file), filename);
    }
    error->source_line = line;
    safe_strcpy(error->source_function, sizeof(error->source_function), function);
}

void rac_error_set_underlying(rac_error_t* error, rac_result_t underlying_code,
                               const char* underlying_message) {
    if (!error) return;
    error->underlying_code = underlying_code;
    safe_strcpy(error->underlying_message, sizeof(error->underlying_message), underlying_message);
}

void rac_error_set_model_context(rac_error_t* error, const char* model_id,
                                  const char* framework) {
    if (!error) return;
    safe_strcpy(error->model_id, sizeof(error->model_id), model_id);
    safe_strcpy(error->framework, sizeof(error->framework), framework);
}

void rac_error_set_session(rac_error_t* error, const char* session_id) {
    if (!error) return;
    safe_strcpy(error->session_id, sizeof(error->session_id), session_id);
}

void rac_error_set_custom(rac_error_t* error, int32_t index, const char* key,
                           const char* value) {
    if (!error || index < 0 || index > 2) return;

    char* key_dest = nullptr;
    char* value_dest = nullptr;
    size_t key_size = 64;
    size_t value_size = RAC_MAX_METADATA_STRING;

    switch (index) {
        case 0:
            key_dest = error->custom_key1;
            value_dest = error->custom_value1;
            break;
        case 1:
            key_dest = error->custom_key2;
            value_dest = error->custom_value2;
            break;
        case 2:
            key_dest = error->custom_key3;
            value_dest = error->custom_value3;
            break;
    }

    if (key_dest && value_dest) {
        safe_strcpy(key_dest, key_size, key);
        safe_strcpy(value_dest, value_size, value);
    }
}

// =============================================================================
// STACK TRACE
// =============================================================================

int32_t rac_error_capture_stack_trace(rac_error_t* error) {
    if (!error) return 0;

#if defined(__APPLE__) || defined(__linux__)
    void* buffer[RAC_MAX_STACK_FRAMES];
    int frame_count = backtrace(buffer, RAC_MAX_STACK_FRAMES);

    // Skip the first few frames (this function and callers)
    int skip = 2;
    int captured = 0;

    for (int i = skip; i < frame_count && captured < RAC_MAX_STACK_FRAMES; i++) {
        error->stack_frames[captured].address = buffer[i];
        error->stack_frames[captured].function = nullptr;
        error->stack_frames[captured].file = nullptr;
        error->stack_frames[captured].line = 0;
        captured++;
    }

    error->stack_frame_count = captured;

    // Try to symbolicate
    char** symbols = backtrace_symbols(buffer + skip, captured);
    if (symbols) {
        // Note: We can't store these strings directly because they're freed
        // For now, we just have addresses. Symbolication happens on the platform side.
        free(symbols);
    }

    return captured;
#else
    // Platform doesn't support backtrace
    error->stack_frame_count = 0;
    return 0;
#endif
}

void rac_error_add_frame(rac_error_t* error, const char* function, const char* file,
                          int32_t line) {
    if (!error || error->stack_frame_count >= RAC_MAX_STACK_FRAMES) return;

    int idx = error->stack_frame_count;
    // Note: We're storing pointers directly, caller must ensure strings outlive error
    error->stack_frames[idx].function = function;
    error->stack_frames[idx].file = file;
    error->stack_frames[idx].line = line;
    error->stack_frames[idx].address = nullptr;
    error->stack_frame_count++;
}

// =============================================================================
// ERROR INFORMATION
// =============================================================================

const char* rac_error_code_name(rac_result_t code) {
    // Note: This is a subset - add more as needed
    switch (code) {
        case RAC_SUCCESS: return "SUCCESS";
        case RAC_ERROR_NOT_INITIALIZED: return "NOT_INITIALIZED";
        case RAC_ERROR_ALREADY_INITIALIZED: return "ALREADY_INITIALIZED";
        case RAC_ERROR_INITIALIZATION_FAILED: return "INITIALIZATION_FAILED";
        case RAC_ERROR_MODEL_NOT_FOUND: return "MODEL_NOT_FOUND";
        case RAC_ERROR_MODEL_LOAD_FAILED: return "MODEL_LOAD_FAILED";
        case RAC_ERROR_MODEL_NOT_LOADED: return "MODEL_NOT_LOADED";
        case RAC_ERROR_GENERATION_FAILED: return "GENERATION_FAILED";
        case RAC_ERROR_TIMEOUT: return "TIMEOUT";
        case RAC_ERROR_CANCELLED: return "CANCELLED";
        case RAC_ERROR_NETWORK_UNAVAILABLE: return "NETWORK_UNAVAILABLE";
        case RAC_ERROR_NETWORK_ERROR: return "NETWORK_ERROR";
        case RAC_ERROR_INVALID_INPUT: return "INVALID_INPUT";
        case RAC_ERROR_INVALID_STATE: return "INVALID_STATE";
        case RAC_ERROR_NOT_SUPPORTED: return "NOT_SUPPORTED";
        case RAC_ERROR_PROCESSING_FAILED: return "PROCESSING_FAILED";
        case RAC_ERROR_INSUFFICIENT_MEMORY: return "INSUFFICIENT_MEMORY";
        case RAC_ERROR_FILE_NOT_FOUND: return "FILE_NOT_FOUND";
        case RAC_ERROR_PERMISSION_DENIED: return "PERMISSION_DENIED";
        case RAC_ERROR_UNKNOWN: return "UNKNOWN";
        default: return "UNKNOWN_CODE";
    }
}

const char* rac_error_category_name(rac_error_category_t category) {
    switch (category) {
        case RAC_CATEGORY_GENERAL: return "general";
        case RAC_CATEGORY_STT: return "stt";
        case RAC_CATEGORY_TTS: return "tts";
        case RAC_CATEGORY_LLM: return "llm";
        case RAC_CATEGORY_VAD: return "vad";
        case RAC_CATEGORY_VLM: return "vlm";
        case RAC_CATEGORY_SPEAKER_DIARIZATION: return "speakerDiarization";
        case RAC_CATEGORY_WAKE_WORD: return "wakeWord";
        case RAC_CATEGORY_VOICE_AGENT: return "voiceAgent";
        case RAC_CATEGORY_DOWNLOAD: return "download";
        case RAC_CATEGORY_FILE_MANAGEMENT: return "fileManagement";
        case RAC_CATEGORY_NETWORK: return "network";
        case RAC_CATEGORY_AUTHENTICATION: return "authentication";
        case RAC_CATEGORY_SECURITY: return "security";
        case RAC_CATEGORY_RUNTIME: return "runtime";
        default: return "unknown";
    }
}

const char* rac_error_recovery_suggestion(rac_result_t code) {
    switch (code) {
        case RAC_ERROR_NOT_INITIALIZED:
            return "Initialize the component before using it.";
        case RAC_ERROR_MODEL_NOT_FOUND:
            return "Ensure the model is downloaded and the path is correct.";
        case RAC_ERROR_NETWORK_UNAVAILABLE:
            return "Check your internet connection and try again.";
        case RAC_ERROR_INSUFFICIENT_STORAGE:
            return "Free up storage space and try again.";
        case RAC_ERROR_INSUFFICIENT_MEMORY:
            return "Close other applications to free up memory.";
        case RAC_ERROR_MICROPHONE_PERMISSION_DENIED:
            return "Grant microphone permission in Settings.";
        case RAC_ERROR_TIMEOUT:
            return "Try again or check your connection.";
        case RAC_ERROR_INVALID_API_KEY:
            return "Verify your API key is correct.";
        case RAC_ERROR_CANCELLED:
            return nullptr; // Expected, no suggestion
        default:
            return nullptr;
    }
}

rac_bool_t rac_error_is_expected_error(const rac_error_t* error) {
    if (!error) return RAC_FALSE;
    return rac_error_is_expected(error->code);
}

// =============================================================================
// SERIALIZATION
// =============================================================================

char* rac_error_to_json(const rac_error_t* error) {
    if (!error) return nullptr;

    // Allocate buffer for JSON
    size_t buffer_size = 4096;
    char* json = static_cast<char*>(malloc(buffer_size));
    if (!json) return nullptr;

    int pos = 0;
    pos += snprintf(json + pos, buffer_size - pos, "{");
    pos += snprintf(json + pos, buffer_size - pos, "\"code\":%d,", error->code);
    pos += snprintf(json + pos, buffer_size - pos, "\"code_name\":\"%s\",",
                    rac_error_code_name(error->code));
    pos += snprintf(json + pos, buffer_size - pos, "\"category\":\"%s\",",
                    rac_error_category_name(error->category));

    // Escape message for JSON
    pos += snprintf(json + pos, buffer_size - pos, "\"message\":\"");
    for (const char* p = error->message; *p && pos < (int)buffer_size - 10; p++) {
        if (*p == '"' || *p == '\\') {
            json[pos++] = '\\';
        }
        json[pos++] = *p;
    }
    pos += snprintf(json + pos, buffer_size - pos, "\",");

    pos += snprintf(json + pos, buffer_size - pos, "\"timestamp_ms\":%lld,",
                    static_cast<long long>(error->timestamp_ms));

    // Source location
    if (error->source_file[0]) {
        pos += snprintf(json + pos, buffer_size - pos,
                        "\"source_file\":\"%s\",\"source_line\":%d,",
                        error->source_file, error->source_line);
    }
    if (error->source_function[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"source_function\":\"%s\",",
                        error->source_function);
    }

    // Model context
    if (error->model_id[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"model_id\":\"%s\",", error->model_id);
    }
    if (error->framework[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"framework\":\"%s\",", error->framework);
    }
    if (error->session_id[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"session_id\":\"%s\",",
                        error->session_id);
    }

    // Underlying error
    if (error->underlying_code != 0) {
        pos += snprintf(json + pos, buffer_size - pos,
                        "\"underlying_code\":%d,\"underlying_message\":\"%s\",",
                        error->underlying_code, error->underlying_message);
    }

    // Stack trace
    if (error->stack_frame_count > 0) {
        pos += snprintf(json + pos, buffer_size - pos, "\"stack_frame_count\":%d,",
                        error->stack_frame_count);
    }

    // Custom metadata
    if (error->custom_key1[0] && error->custom_value1[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key1,
                        error->custom_value1);
    }
    if (error->custom_key2[0] && error->custom_value2[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key2,
                        error->custom_value2);
    }
    if (error->custom_key3[0] && error->custom_value3[0]) {
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key3,
                        error->custom_value3);
    }

    // Remove trailing comma and close
    if (json[pos - 1] == ',') pos--;
    json[pos++] = '}';
    json[pos] = '\0';

    return json;
}

int32_t rac_error_get_telemetry_properties(const rac_error_t* error, char** out_keys,
                                            char** out_values) {
    if (!error || !out_keys || !out_values) return 0;

    int32_t count = 0;

    // Error code
    out_keys[count] = strdup("error_code");
    out_values[count] = strdup(rac_error_code_name(error->code));
    count++;

    // Error category
    out_keys[count] = strdup("error_category");
    out_values[count] = strdup(rac_error_category_name(error->category));
    count++;

    // Error message
    out_keys[count] = strdup("error_message");
    out_values[count] = strdup(error->message);
    count++;

    return count;
}

char* rac_error_to_string(const rac_error_t* error) {
    if (!error) return nullptr;

    size_t size = 512;
    char* str = static_cast<char*>(malloc(size));
    if (!str) return nullptr;

    snprintf(str, size, "SDKError[%s.%s]: %s", rac_error_category_name(error->category),
             rac_error_code_name(error->code), error->message);

    return str;
}

char* rac_error_to_debug_string(const rac_error_t* error) {
    if (!error) return nullptr;

    size_t size = 2048;
    char* str = static_cast<char*>(malloc(size));
    if (!str) return nullptr;

    int pos = 0;
    pos += snprintf(str + pos, size - pos, "SDKError[%s.%s]: %s",
                    rac_error_category_name(error->category),
                    rac_error_code_name(error->code), error->message);

    if (error->underlying_code != 0) {
        pos += snprintf(str + pos, size - pos, "\n  Caused by: %s (%d)",
                        error->underlying_message, error->underlying_code);
    }

    if (error->source_file[0]) {
        pos += snprintf(str + pos, size - pos, "\n  At: %s:%d in %s", error->source_file,
                        error->source_line, error->source_function);
    }

    if (error->model_id[0]) {
        pos += snprintf(str + pos, size - pos, "\n  Model: %s (%s)", error->model_id,
                        error->framework);
    }

    if (error->stack_frame_count > 0) {
        pos += snprintf(str + pos, size - pos, "\n  Stack trace (%d frames):",
                        error->stack_frame_count);
        for (int i = 0; i < error->stack_frame_count && i < 5 && pos < (int)size - 100; i++) {
            if (error->stack_frames[i].function) {
                pos += snprintf(str + pos, size - pos, "\n    %s at %s:%d",
                                error->stack_frames[i].function,
                                error->stack_frames[i].file ? error->stack_frames[i].file : "?",
                                error->stack_frames[i].line);
            } else if (error->stack_frames[i].address) {
                pos += snprintf(str + pos, size - pos, "\n    %p",
                                error->stack_frames[i].address);
            }
        }
    }

    return str;
}

// =============================================================================
// GLOBAL ERROR
// =============================================================================

void rac_set_last_error(const rac_error_t* error) {
    if (error) {
        memcpy(&g_last_error, error, sizeof(rac_error_t));
        g_has_last_error = true;
    } else {
        rac_clear_last_error();
    }
}

const rac_error_t* rac_get_last_error(void) {
    return g_has_last_error ? &g_last_error : nullptr;
}

void rac_clear_last_error(void) {
    memset(&g_last_error, 0, sizeof(rac_error_t));
    g_has_last_error = false;
}

rac_result_t rac_set_error(rac_result_t code, rac_error_category_t category,
                            const char* message) {
    rac_error_t* error = rac_error_create(code, category, message);
    if (error) {
        // Log the error
        if (!rac_error_is_expected(code)) {
            RAC_LOG_ERROR(rac_error_category_name(category), "%s (code: %d)", message, code);
        }

        rac_set_last_error(error);
        rac_error_destroy(error);
    }
    return code;
}

} // extern "C"
