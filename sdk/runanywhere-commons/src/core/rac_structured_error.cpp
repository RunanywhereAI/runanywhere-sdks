/**
 * @file rac_structured_error.cpp
 * @brief RunAnywhere Commons - Structured Error Implementation
 */

#include "rac/core/rac_structured_error.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

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
    if (!dest || dest_size == 0)
        return;
    if (!src) {
        dest[0] = '\0';
        return;
    }
    size_t len = strlen(src);
    if (len >= dest_size)
        len = dest_size - 1;
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

}  // anonymous namespace

// =============================================================================
// ERROR CREATION & DESTRUCTION
// =============================================================================

extern "C" {

rac_error_t* rac_error_create(rac_result_t code, rac_error_category_t category,
                              const char* message) {
    rac_error_t* error = static_cast<rac_error_t*>(calloc(1, sizeof(rac_error_t)));
    if (!error)
        return nullptr;

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

rac_error_t* rac_error_createf(rac_result_t code, rac_error_category_t category, const char* format,
                               ...) {
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
    if (!error)
        return nullptr;

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
    if (!error)
        return;

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
    if (!error)
        return;
    error->underlying_code = underlying_code;
    safe_strcpy(error->underlying_message, sizeof(error->underlying_message), underlying_message);
}

void rac_error_set_model_context(rac_error_t* error, const char* model_id, const char* framework) {
    if (!error)
        return;
    safe_strcpy(error->model_id, sizeof(error->model_id), model_id);
    safe_strcpy(error->framework, sizeof(error->framework), framework);
}

void rac_error_set_session(rac_error_t* error, const char* session_id) {
    if (!error)
        return;
    safe_strcpy(error->session_id, sizeof(error->session_id), session_id);
}

void rac_error_set_custom(rac_error_t* error, int32_t index, const char* key, const char* value) {
    if (!error || index < 0 || index > 2)
        return;

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
        default:
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
    if (!error)
        return 0;

// Note: Android defines __linux__ but doesn't have execinfo.h/backtrace
#if (defined(__APPLE__) || defined(__linux__)) && !defined(__ANDROID__)
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
    // Platform doesn't support backtrace (Android, Windows, etc.)
    error->stack_frame_count = 0;
    return 0;
#endif
}

void rac_error_add_frame(rac_error_t* error, const char* function, const char* file, int32_t line) {
    if (!error || error->stack_frame_count >= RAC_MAX_STACK_FRAMES)
        return;

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
    switch (code) {
        // Success
        case RAC_SUCCESS:
            return "SUCCESS";

        // Initialization Errors (-100 to -109)
        case RAC_ERROR_NOT_INITIALIZED:
            return "notInitialized";
        case RAC_ERROR_ALREADY_INITIALIZED:
            return "alreadyInitialized";
        case RAC_ERROR_INITIALIZATION_FAILED:
            return "initializationFailed";
        case RAC_ERROR_INVALID_CONFIGURATION:
            return "invalidConfiguration";
        case RAC_ERROR_INVALID_API_KEY:
            return "invalidAPIKey";
        case RAC_ERROR_ENVIRONMENT_MISMATCH:
            return "environmentMismatch";
        case RAC_ERROR_INVALID_PARAMETER:
            return "invalidConfiguration";

        // Model Errors (-110 to -129)
        case RAC_ERROR_MODEL_NOT_FOUND:
            return "modelNotFound";
        case RAC_ERROR_MODEL_LOAD_FAILED:
            return "modelLoadFailed";
        case RAC_ERROR_MODEL_VALIDATION_FAILED:
            return "modelValidationFailed";
        case RAC_ERROR_MODEL_INCOMPATIBLE:
            return "modelIncompatible";
        case RAC_ERROR_INVALID_MODEL_FORMAT:
            return "invalidModelFormat";
        case RAC_ERROR_MODEL_STORAGE_CORRUPTED:
            return "modelStorageCorrupted";
        case RAC_ERROR_MODEL_NOT_LOADED:
            return "notInitialized";

        // Generation Errors (-130 to -149)
        case RAC_ERROR_GENERATION_FAILED:
            return "generationFailed";
        case RAC_ERROR_GENERATION_TIMEOUT:
            return "generationTimeout";
        case RAC_ERROR_CONTEXT_TOO_LONG:
            return "contextTooLong";
        case RAC_ERROR_TOKEN_LIMIT_EXCEEDED:
            return "tokenLimitExceeded";
        case RAC_ERROR_COST_LIMIT_EXCEEDED:
            return "costLimitExceeded";
        case RAC_ERROR_INFERENCE_FAILED:
            return "generationFailed";

        // Network Errors (-150 to -179)
        case RAC_ERROR_NETWORK_UNAVAILABLE:
            return "networkUnavailable";
        case RAC_ERROR_NETWORK_ERROR:
            return "networkError";
        case RAC_ERROR_REQUEST_FAILED:
            return "requestFailed";
        case RAC_ERROR_DOWNLOAD_FAILED:
            return "downloadFailed";
        case RAC_ERROR_SERVER_ERROR:
            return "serverError";
        case RAC_ERROR_TIMEOUT:
            return "timeout";
        case RAC_ERROR_INVALID_RESPONSE:
            return "invalidResponse";
        case RAC_ERROR_HTTP_ERROR:
            return "httpError";
        case RAC_ERROR_CONNECTION_LOST:
            return "connectionLost";
        case RAC_ERROR_PARTIAL_DOWNLOAD:
            return "partialDownload";
        case RAC_ERROR_HTTP_REQUEST_FAILED:
            return "requestFailed";
        case RAC_ERROR_HTTP_NOT_SUPPORTED:
            return "notSupported";

        // Storage Errors (-180 to -219)
        case RAC_ERROR_INSUFFICIENT_STORAGE:
            return "insufficientStorage";
        case RAC_ERROR_STORAGE_FULL:
            return "storageFull";
        case RAC_ERROR_STORAGE_ERROR:
            return "storageError";
        case RAC_ERROR_FILE_NOT_FOUND:
            return "fileNotFound";
        case RAC_ERROR_FILE_READ_FAILED:
            return "fileReadFailed";
        case RAC_ERROR_FILE_WRITE_FAILED:
            return "fileWriteFailed";
        case RAC_ERROR_PERMISSION_DENIED:
            return "permissionDenied";
        case RAC_ERROR_DELETE_FAILED:
            return "deleteFailed";
        case RAC_ERROR_MOVE_FAILED:
            return "moveFailed";
        case RAC_ERROR_DIRECTORY_CREATION_FAILED:
            return "directoryCreationFailed";
        case RAC_ERROR_DIRECTORY_NOT_FOUND:
            return "directoryNotFound";
        case RAC_ERROR_INVALID_PATH:
            return "invalidPath";
        case RAC_ERROR_INVALID_FILE_NAME:
            return "invalidFileName";
        case RAC_ERROR_TEMP_FILE_CREATION_FAILED:
            return "tempFileCreationFailed";

        // Hardware Errors (-220 to -229)
        case RAC_ERROR_HARDWARE_UNSUPPORTED:
            return "hardwareUnsupported";
        case RAC_ERROR_INSUFFICIENT_MEMORY:
            return "insufficientMemory";

        // Component State Errors (-230 to -249)
        case RAC_ERROR_COMPONENT_NOT_READY:
            return "componentNotReady";
        case RAC_ERROR_INVALID_STATE:
            return "invalidState";
        case RAC_ERROR_SERVICE_NOT_AVAILABLE:
            return "serviceNotAvailable";
        case RAC_ERROR_SERVICE_BUSY:
            return "serviceBusy";
        case RAC_ERROR_PROCESSING_FAILED:
            return "processingFailed";
        case RAC_ERROR_START_FAILED:
            return "startFailed";
        case RAC_ERROR_NOT_SUPPORTED:
            return "notSupported";

        // Validation Errors (-250 to -279)
        case RAC_ERROR_VALIDATION_FAILED:
            return "validationFailed";
        case RAC_ERROR_INVALID_INPUT:
            return "invalidInput";
        case RAC_ERROR_INVALID_FORMAT:
            return "invalidFormat";
        case RAC_ERROR_EMPTY_INPUT:
            return "emptyInput";
        case RAC_ERROR_TEXT_TOO_LONG:
            return "textTooLong";
        case RAC_ERROR_INVALID_SSML:
            return "invalidSSML";
        case RAC_ERROR_INVALID_SPEAKING_RATE:
            return "invalidSpeakingRate";
        case RAC_ERROR_INVALID_PITCH:
            return "invalidPitch";
        case RAC_ERROR_INVALID_VOLUME:
            return "invalidVolume";
        case RAC_ERROR_INVALID_ARGUMENT:
            return "invalidInput";
        case RAC_ERROR_NULL_POINTER:
            return "invalidInput";
        case RAC_ERROR_BUFFER_TOO_SMALL:
            return "invalidInput";

        // Audio Errors (-280 to -299)
        case RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED:
            return "audioFormatNotSupported";
        case RAC_ERROR_AUDIO_SESSION_FAILED:
            return "audioSessionFailed";
        case RAC_ERROR_MICROPHONE_PERMISSION_DENIED:
            return "microphonePermissionDenied";
        case RAC_ERROR_INSUFFICIENT_AUDIO_DATA:
            return "insufficientAudioData";
        case RAC_ERROR_EMPTY_AUDIO_BUFFER:
            return "emptyAudioBuffer";
        case RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED:
            return "audioSessionActivationFailed";

        // Language/Voice Errors (-300 to -319)
        case RAC_ERROR_LANGUAGE_NOT_SUPPORTED:
            return "languageNotSupported";
        case RAC_ERROR_VOICE_NOT_AVAILABLE:
            return "voiceNotAvailable";
        case RAC_ERROR_STREAMING_NOT_SUPPORTED:
            return "streamingNotSupported";
        case RAC_ERROR_STREAM_CANCELLED:
            return "streamCancelled";

        // Authentication Errors (-320 to -329)
        case RAC_ERROR_AUTHENTICATION_FAILED:
            return "authenticationFailed";
        case RAC_ERROR_UNAUTHORIZED:
            return "unauthorized";
        case RAC_ERROR_FORBIDDEN:
            return "forbidden";

        // Security Errors (-330 to -349)
        case RAC_ERROR_KEYCHAIN_ERROR:
            return "keychainError";
        case RAC_ERROR_ENCODING_ERROR:
            return "encodingError";
        case RAC_ERROR_DECODING_ERROR:
            return "decodingError";
        case RAC_ERROR_SECURE_STORAGE_FAILED:
            return "keychainError";

        // Extraction Errors (-350 to -369)
        case RAC_ERROR_EXTRACTION_FAILED:
            return "extractionFailed";
        case RAC_ERROR_CHECKSUM_MISMATCH:
            return "checksumMismatch";
        case RAC_ERROR_UNSUPPORTED_ARCHIVE:
            return "unsupportedArchive";

        // Calibration Errors (-370 to -379)
        case RAC_ERROR_CALIBRATION_FAILED:
            return "calibrationFailed";
        case RAC_ERROR_CALIBRATION_TIMEOUT:
            return "calibrationTimeout";

        // Cancellation (-380 to -389)
        case RAC_ERROR_CANCELLED:
            return "cancelled";

        // Module/Service Errors (-400 to -499)
        case RAC_ERROR_MODULE_NOT_FOUND:
            return "frameworkNotAvailable";
        case RAC_ERROR_MODULE_ALREADY_REGISTERED:
            return "alreadyInitialized";
        case RAC_ERROR_MODULE_LOAD_FAILED:
            return "initializationFailed";
        case RAC_ERROR_SERVICE_NOT_FOUND:
            return "serviceNotAvailable";
        case RAC_ERROR_SERVICE_ALREADY_REGISTERED:
            return "alreadyInitialized";
        case RAC_ERROR_SERVICE_CREATE_FAILED:
            return "initializationFailed";
        case RAC_ERROR_CAPABILITY_NOT_FOUND:
            return "featureNotAvailable";
        case RAC_ERROR_PROVIDER_NOT_FOUND:
            return "serviceNotAvailable";
        case RAC_ERROR_NO_CAPABLE_PROVIDER:
            return "serviceNotAvailable";
        case RAC_ERROR_NOT_FOUND:
            return "modelNotFound";

        // Platform Adapter Errors (-500 to -599)
        case RAC_ERROR_ADAPTER_NOT_SET:
            return "notInitialized";

        // Backend Errors (-600 to -699)
        case RAC_ERROR_BACKEND_NOT_FOUND:
            return "frameworkNotAvailable";
        case RAC_ERROR_BACKEND_NOT_READY:
            return "componentNotReady";
        case RAC_ERROR_BACKEND_INIT_FAILED:
            return "initializationFailed";
        case RAC_ERROR_BACKEND_BUSY:
            return "serviceBusy";
        case RAC_ERROR_INVALID_HANDLE:
            return "invalidState";

        // Event Errors (-700 to -799)
        case RAC_ERROR_EVENT_INVALID_CATEGORY:
            return "invalidInput";
        case RAC_ERROR_EVENT_SUBSCRIPTION_FAILED:
            return "unknown";
        case RAC_ERROR_EVENT_PUBLISH_FAILED:
            return "unknown";

        // Other Errors (-800 to -899)
        case RAC_ERROR_NOT_IMPLEMENTED:
            return "notImplemented";
        case RAC_ERROR_FEATURE_NOT_AVAILABLE:
            return "featureNotAvailable";
        case RAC_ERROR_FRAMEWORK_NOT_AVAILABLE:
            return "frameworkNotAvailable";
        case RAC_ERROR_UNSUPPORTED_MODALITY:
            return "unsupportedModality";
        case RAC_ERROR_UNKNOWN:
            return "unknown";
        case RAC_ERROR_INTERNAL:
            return "unknown";

        default:
            return "unknown";
    }
}

const char* rac_error_category_name(rac_error_category_t category) {
    switch (category) {
        case RAC_CATEGORY_GENERAL:
            return "general";
        case RAC_CATEGORY_STT:
            return "stt";
        case RAC_CATEGORY_TTS:
            return "tts";
        case RAC_CATEGORY_LLM:
            return "llm";
        case RAC_CATEGORY_VAD:
            return "vad";
        case RAC_CATEGORY_VLM:
            return "vlm";
        case RAC_CATEGORY_SPEAKER_DIARIZATION:
            return "speakerDiarization";
        case RAC_CATEGORY_WAKE_WORD:
            return "wakeWord";
        case RAC_CATEGORY_VOICE_AGENT:
            return "voiceAgent";
        case RAC_CATEGORY_DOWNLOAD:
            return "download";
        case RAC_CATEGORY_FILE_MANAGEMENT:
            return "fileManagement";
        case RAC_CATEGORY_NETWORK:
            return "network";
        case RAC_CATEGORY_AUTHENTICATION:
            return "authentication";
        case RAC_CATEGORY_SECURITY:
            return "security";
        case RAC_CATEGORY_RUNTIME:
            return "runtime";
        default:
            return "unknown";
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
            return nullptr;  // Expected, no suggestion
        default:
            return nullptr;
    }
}

rac_bool_t rac_error_is_expected_error(const rac_error_t* error) {
    if (!error)
        return RAC_FALSE;
    return rac_error_is_expected(error->code);
}

// =============================================================================
// SERIALIZATION
// =============================================================================

char* rac_error_to_json(const rac_error_t* error) {
    if (!error)
        return nullptr;

    // Allocate buffer for JSON
    size_t buffer_size = 4096;
    char* json = static_cast<char*>(malloc(buffer_size));
    if (!json)
        return nullptr;

    int pos = 0;
    pos += snprintf(json + pos, buffer_size - pos, "{");
    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\"code\":%d,", error->code);
    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\"code_name\":\"%s\",",
                    rac_error_code_name(error->code));
    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\"category\":\"%s\",",
                    rac_error_category_name(error->category));

    // Escape message for JSON
    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\"message\":\"");
    for (const char* p = error->message; *p != '\0' && pos < (int)buffer_size - 10; p++) {
        if (*p == '"' || *p == '\\') {
            json[pos++] = '\\';
        }
        json[pos++] = *p;
    }
    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\",");

    // NOLINTNEXTLINE(modernize-raw-string-literal)
    pos += snprintf(json + pos, buffer_size - pos, "\"timestamp_ms\":%lld,",
                    static_cast<long long>(error->timestamp_ms));

    // Source location
    if (error->source_file[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"source_file\":\"%s\",\"source_line\":%d,",
                        error->source_file, error->source_line);
    }
    if (error->source_function[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"source_function\":\"%s\",",
                        error->source_function);
    }

    // Model context
    if (error->model_id[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"model_id\":\"%s\",", error->model_id);
    }
    if (error->framework[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"framework\":\"%s\",", error->framework);
    }
    if (error->session_id[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"session_id\":\"%s\",", error->session_id);
    }

    // Underlying error
    if (error->underlying_code != 0) {
        pos += snprintf(
            json + pos, buffer_size - pos,
            "\"underlying_code\":%d,\"underlying_message\":\"%s\",",  // NOLINT(modernize-raw-string-literal)
            error->underlying_code, error->underlying_message);
    }

    // Stack trace
    if (error->stack_frame_count > 0) {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"stack_frame_count\":%d,",
                        error->stack_frame_count);
    }

    // Custom metadata
    if (error->custom_key1[0] != '\0' && error->custom_value1[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key1,
                        error->custom_value1);
    }
    if (error->custom_key2[0] != '\0' && error->custom_value2[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key2,
                        error->custom_value2);
    }
    if (error->custom_key3[0] != '\0' && error->custom_value3[0] != '\0') {
        // NOLINTNEXTLINE(modernize-raw-string-literal)
        pos += snprintf(json + pos, buffer_size - pos, "\"%s\":\"%s\",", error->custom_key3,
                        error->custom_value3);
    }

    // Remove trailing comma and close
    if (json[pos - 1] == ',')
        pos--;
    json[pos++] = '}';
    json[pos] = '\0';

    return json;
}

int32_t rac_error_get_telemetry_properties(const rac_error_t* error, char** out_keys,
                                           char** out_values) {
    if (!error || !out_keys || !out_values)
        return 0;

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
    if (!error)
        return nullptr;

    size_t size = 512;
    char* str = static_cast<char*>(malloc(size));
    if (!str)
        return nullptr;

    snprintf(str, size, "SDKError[%s.%s]: %s", rac_error_category_name(error->category),
             rac_error_code_name(error->code), error->message);

    return str;
}

char* rac_error_to_debug_string(const rac_error_t* error) {
    if (!error)
        return nullptr;

    size_t size = 2048;
    char* str = static_cast<char*>(malloc(size));
    if (!str)
        return nullptr;

    int pos = 0;
    pos += snprintf(str + pos, size - pos, "SDKError[%s.%s]: %s",
                    rac_error_category_name(error->category), rac_error_code_name(error->code),
                    error->message);

    if (error->underlying_code != 0) {
        pos += snprintf(str + pos, size - pos, "\n  Caused by: %s (%d)", error->underlying_message,
                        error->underlying_code);
    }

    if (error->source_file[0] != '\0') {
        pos += snprintf(str + pos, size - pos, "\n  At: %s:%d in %s", error->source_file,
                        error->source_line, error->source_function);
    }

    if (error->model_id[0] != '\0') {
        pos += snprintf(str + pos, size - pos, "\n  Model: %s (%s)", error->model_id,
                        error->framework);
    }

    if (error->stack_frame_count > 0) {
        pos += snprintf(str + pos, size - pos,
                        "\n  Stack trace (%d frames):", error->stack_frame_count);
        for (int i = 0; i < error->stack_frame_count && i < 5 && pos < (int)size - 100; i++) {
            if (error->stack_frames[i].function != nullptr) {
                pos += snprintf(
                    str + pos, size - pos, "\n    %s at %s:%d", error->stack_frames[i].function,
                    error->stack_frames[i].file != nullptr ? error->stack_frames[i].file : "?",
                    error->stack_frames[i].line);
            } else if (error->stack_frames[i].address != nullptr) {
                pos += snprintf(str + pos, size - pos, "\n    %p", error->stack_frames[i].address);
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

rac_result_t rac_set_error(rac_result_t code, rac_error_category_t category, const char* message) {
    rac_error_t* error = rac_error_create(code, category, message);
    if (error) {
        // Log the error
        if (rac_error_is_expected(code) == 0) {
            RAC_LOG_ERROR(rac_error_category_name(category), "%s (code: %d)", message, code);
        }

        rac_set_last_error(error);
        rac_error_destroy(error);
    }
    return code;
}

// =============================================================================
// UNIFIED ERROR HANDLING
// =============================================================================

rac_result_t rac_error_log_and_track(rac_result_t code, rac_error_category_t category,
                                     const char* message, const char* file, int32_t line,
                                     const char* function) {
    // Create structured error with source location
    rac_error_t* error = rac_error_create_at(code, category, message, file, line, function);
    if (!error) {
        return code;
    }

    // Capture stack trace
    rac_error_capture_stack_trace(error);

    // Set as last error
    rac_set_last_error(error);

    // Skip logging and tracking for expected errors (cancellation, etc.)
    if (rac_error_is_expected(code) != 0) {
        rac_error_destroy(error);
        return code;
    }

    // Log the error
    rac_log_metadata_t meta = RAC_LOG_METADATA_EMPTY;
    meta.file = file;
    meta.line = line;
    meta.function = function;
    meta.error_code = code;
    rac_logger_log(RAC_LOG_ERROR, rac_error_category_name(category), message, &meta);

    // Track error via platform adapter (for Sentry)
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->track_error) {
        char* json = rac_error_to_json(error);
        if (json) {
            adapter->track_error(json, adapter->user_data);
            rac_free(json);
        }
    }

    rac_error_destroy(error);
    return code;
}

rac_result_t rac_error_log_and_track_model(rac_result_t code, rac_error_category_t category,
                                           const char* message, const char* model_id,
                                           const char* framework, const char* file, int32_t line,
                                           const char* function) {
    // Create structured error with source location
    rac_error_t* error = rac_error_create_at(code, category, message, file, line, function);
    if (!error) {
        return code;
    }

    // Add model context
    rac_error_set_model_context(error, model_id, framework);

    // Capture stack trace
    rac_error_capture_stack_trace(error);

    // Set as last error
    rac_set_last_error(error);

    // Skip logging and tracking for expected errors
    if (rac_error_is_expected(code) != 0) {
        rac_error_destroy(error);
        return code;
    }

    // Log the error with model context
    rac_log_metadata_t meta = RAC_LOG_METADATA_EMPTY;
    meta.file = file;
    meta.line = line;
    meta.function = function;
    meta.error_code = code;
    meta.model_id = model_id;
    meta.framework = framework;
    rac_logger_log(RAC_LOG_ERROR, rac_error_category_name(category), message, &meta);

    // Track error via platform adapter (for Sentry)
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->track_error) {
        char* json = rac_error_to_json(error);
        if (json) {
            adapter->track_error(json, adapter->user_data);
            rac_free(json);
        }
    }

    rac_error_destroy(error);
    return code;
}

}  // extern "C"
