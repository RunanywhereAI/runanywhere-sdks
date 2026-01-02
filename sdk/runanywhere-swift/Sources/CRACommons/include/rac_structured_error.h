/**
 * @file rac_structured_error.h
 * @brief RunAnywhere Commons - Structured Error System
 *
 * Provides a comprehensive structured error type that mirrors Swift's SDKError.
 * This is the source of truth for error structures across all platforms
 * (Swift, Kotlin, React Native, Flutter).
 *
 * Features:
 * - Error codes and categories matching Swift's ErrorCode and ErrorCategory
 * - Stack trace capture (platform-dependent)
 * - Structured metadata for telemetry
 * - Serialization to JSON for remote logging
 *
 * Usage:
 *   rac_error_t* error = rac_error_create(RAC_ERROR_MODEL_NOT_FOUND,
 *                                          RAC_CATEGORY_STT,
 *                                          "Model not found: whisper-tiny.en");
 *   rac_error_set_model_context(error, "whisper-tiny.en", "sherpa-onnx");
 *   rac_error_capture_stack_trace(error);
 *   // ... use error ...
 *   rac_error_destroy(error);
 */

#ifndef RAC_STRUCTURED_ERROR_H
#define RAC_STRUCTURED_ERROR_H

#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// ERROR CATEGORIES
// =============================================================================

/**
 * @brief Error categories matching Swift's ErrorCategory.
 *
 * These define which component/modality an error belongs to.
 */
typedef enum rac_error_category {
    RAC_CATEGORY_GENERAL = 0,             /**< General SDK errors */
    RAC_CATEGORY_STT = 1,                 /**< Speech-to-Text errors */
    RAC_CATEGORY_TTS = 2,                 /**< Text-to-Speech errors */
    RAC_CATEGORY_LLM = 3,                 /**< Large Language Model errors */
    RAC_CATEGORY_VAD = 4,                 /**< Voice Activity Detection errors */
    RAC_CATEGORY_VLM = 5,                 /**< Vision Language Model errors */
    RAC_CATEGORY_SPEAKER_DIARIZATION = 6, /**< Speaker Diarization errors */
    RAC_CATEGORY_WAKE_WORD = 7,           /**< Wake Word Detection errors */
    RAC_CATEGORY_VOICE_AGENT = 8,         /**< Voice Agent errors */
    RAC_CATEGORY_DOWNLOAD = 9,            /**< Download errors */
    RAC_CATEGORY_FILE_MANAGEMENT = 10,    /**< File management errors */
    RAC_CATEGORY_NETWORK = 11,            /**< Network errors */
    RAC_CATEGORY_AUTHENTICATION = 12,     /**< Authentication errors */
    RAC_CATEGORY_SECURITY = 13,           /**< Security errors */
    RAC_CATEGORY_RUNTIME = 14,            /**< Runtime/backend errors */
} rac_error_category_t;

// =============================================================================
// STACK FRAME
// =============================================================================

/**
 * @brief A single frame in a stack trace.
 */
typedef struct rac_stack_frame {
    const char* function; /**< Function name */
    const char* file;     /**< Source file name */
    int32_t line;         /**< Line number */
    void* address;        /**< Memory address (for symbolication) */
} rac_stack_frame_t;

// =============================================================================
// STRUCTURED ERROR
// =============================================================================

/**
 * @brief Maximum number of stack frames to capture.
 */
#define RAC_MAX_STACK_FRAMES 32

/**
 * @brief Maximum length of error message.
 */
#define RAC_MAX_ERROR_MESSAGE 1024

/**
 * @brief Maximum length of metadata strings.
 */
#define RAC_MAX_METADATA_STRING 256

/**
 * @brief Structured error type matching Swift's SDKError.
 *
 * Contains all information needed for error reporting, logging, and telemetry.
 */
typedef struct rac_error {
    // Core error info
    rac_result_t code;                   /**< Error code (RAC_ERROR_*) */
    rac_error_category_t category;       /**< Error category */
    char message[RAC_MAX_ERROR_MESSAGE]; /**< Human-readable message */

    // Source location where error occurred
    char source_file[RAC_MAX_METADATA_STRING];     /**< Source file name */
    int32_t source_line;                           /**< Source line number */
    char source_function[RAC_MAX_METADATA_STRING]; /**< Function name */

    // Stack trace
    rac_stack_frame_t stack_frames[RAC_MAX_STACK_FRAMES];
    int32_t stack_frame_count;

    // Underlying error (optional)
    rac_result_t underlying_code;                   /**< Underlying error code (0 if none) */
    char underlying_message[RAC_MAX_ERROR_MESSAGE]; /**< Underlying error message */

    // Context metadata
    char model_id[RAC_MAX_METADATA_STRING];   /**< Model ID if applicable */
    char framework[RAC_MAX_METADATA_STRING];  /**< Framework (e.g., "sherpa-onnx") */
    char session_id[RAC_MAX_METADATA_STRING]; /**< Session ID for correlation */

    // Timing
    int64_t timestamp_ms; /**< When error occurred (unix ms) */

    // Custom metadata (key-value pairs for extensibility)
    char custom_key1[64];
    char custom_value1[RAC_MAX_METADATA_STRING];
    char custom_key2[64];
    char custom_value2[RAC_MAX_METADATA_STRING];
    char custom_key3[64];
    char custom_value3[RAC_MAX_METADATA_STRING];
} rac_error_t;

// =============================================================================
// ERROR CREATION & DESTRUCTION
// =============================================================================

/**
 * @brief Creates a new structured error.
 *
 * @param code Error code (RAC_ERROR_*)
 * @param category Error category
 * @param message Human-readable error message
 * @return New error instance (caller must call rac_error_destroy)
 */
RAC_API rac_error_t* rac_error_create(rac_result_t code, rac_error_category_t category,
                                      const char* message);

/**
 * @brief Creates an error with source location.
 *
 * Use the RAC_ERROR_HERE macro for convenient source location capture.
 *
 * @param code Error code
 * @param category Error category
 * @param message Error message
 * @param file Source file (__FILE__)
 * @param line Source line (__LINE__)
 * @param function Function name (__func__)
 * @return New error instance
 */
RAC_API rac_error_t* rac_error_create_at(rac_result_t code, rac_error_category_t category,
                                         const char* message, const char* file, int32_t line,
                                         const char* function);

/**
 * @brief Creates an error with formatted message.
 *
 * @param code Error code
 * @param category Error category
 * @param format Printf-style format string
 * @param ... Format arguments
 * @return New error instance
 */
RAC_API rac_error_t* rac_error_createf(rac_result_t code, rac_error_category_t category,
                                       const char* format, ...);

/**
 * @brief Destroys a structured error and frees memory.
 *
 * @param error Error to destroy (can be NULL)
 */
RAC_API void rac_error_destroy(rac_error_t* error);

/**
 * @brief Creates a copy of an error.
 *
 * @param error Error to copy
 * @return New copy of the error (caller must destroy)
 */
RAC_API rac_error_t* rac_error_copy(const rac_error_t* error);

// =============================================================================
// ERROR CONFIGURATION
// =============================================================================

/**
 * @brief Sets the source location for an error.
 *
 * @param error Error to modify
 * @param file Source file name
 * @param line Source line number
 * @param function Function name
 */
RAC_API void rac_error_set_source(rac_error_t* error, const char* file, int32_t line,
                                  const char* function);

/**
 * @brief Sets the underlying error.
 *
 * @param error Error to modify
 * @param underlying_code Underlying error code
 * @param underlying_message Underlying error message
 */
RAC_API void rac_error_set_underlying(rac_error_t* error, rac_result_t underlying_code,
                                      const char* underlying_message);

/**
 * @brief Sets model context for the error.
 *
 * @param error Error to modify
 * @param model_id Model ID
 * @param framework Framework name (e.g., "sherpa-onnx", "llama.cpp")
 */
RAC_API void rac_error_set_model_context(rac_error_t* error, const char* model_id,
                                         const char* framework);

/**
 * @brief Sets session ID for correlation.
 *
 * @param error Error to modify
 * @param session_id Session ID
 */
RAC_API void rac_error_set_session(rac_error_t* error, const char* session_id);

/**
 * @brief Sets custom metadata on the error.
 *
 * @param error Error to modify
 * @param index Custom slot (0-2)
 * @param key Metadata key
 * @param value Metadata value
 */
RAC_API void rac_error_set_custom(rac_error_t* error, int32_t index, const char* key,
                                  const char* value);

// =============================================================================
// STACK TRACE
// =============================================================================

/**
 * @brief Captures the current stack trace into the error.
 *
 * Platform-dependent. On some platforms, only addresses may be captured
 * and symbolication happens later.
 *
 * @param error Error to capture stack trace into
 * @return Number of frames captured
 */
RAC_API int32_t rac_error_capture_stack_trace(rac_error_t* error);

/**
 * @brief Adds a manual stack frame to the error.
 *
 * Use this when automatic stack capture is not available.
 *
 * @param error Error to modify
 * @param function Function name
 * @param file File name
 * @param line Line number
 */
RAC_API void rac_error_add_frame(rac_error_t* error, const char* function, const char* file,
                                 int32_t line);

// =============================================================================
// ERROR INFORMATION
// =============================================================================

/**
 * @brief Gets the error code name as a string.
 *
 * @param code Error code
 * @return Static string with code name (e.g., "MODEL_NOT_FOUND")
 */
RAC_API const char* rac_error_code_name(rac_result_t code);

/**
 * @brief Gets the category name as a string.
 *
 * @param category Error category
 * @return Static string with category name (e.g., "stt", "llm")
 */
RAC_API const char* rac_error_category_name(rac_error_category_t category);

/**
 * @brief Gets a recovery suggestion for the error.
 *
 * Mirrors Swift's SDKError.recoverySuggestion.
 *
 * @param code Error code
 * @return Static string with suggestion, or NULL if none
 */
RAC_API const char* rac_error_recovery_suggestion(rac_result_t code);

/**
 * @brief Checks if an error is expected (like cancellation).
 *
 * Expected errors should typically not be logged as errors.
 *
 * @param error Error to check
 * @return RAC_TRUE if expected, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_error_is_expected_error(const rac_error_t* error);

// =============================================================================
// SERIALIZATION
// =============================================================================

/**
 * @brief Serializes error to JSON string for telemetry.
 *
 * Returns a compact JSON representation suitable for sending to analytics.
 * The returned string must be freed with rac_free().
 *
 * @param error Error to serialize
 * @return JSON string (caller must free), or NULL on failure
 */
RAC_API char* rac_error_to_json(const rac_error_t* error);

/**
 * @brief Gets telemetry properties as key-value pairs.
 *
 * Returns essential fields for analytics/telemetry events.
 * Keys and values must be freed by caller.
 *
 * @param error Error to get properties from
 * @param out_keys Output array of keys (caller allocates, at least 10 slots)
 * @param out_values Output array of values (caller allocates, at least 10 slots)
 * @return Number of properties written
 */
RAC_API int32_t rac_error_get_telemetry_properties(const rac_error_t* error, char** out_keys,
                                                   char** out_values);

/**
 * @brief Formats error as a human-readable string.
 *
 * Format: "SDKError[category.code]: message"
 * The returned string must be freed with rac_free().
 *
 * @param error Error to format
 * @return Formatted string (caller must free)
 */
RAC_API char* rac_error_to_string(const rac_error_t* error);

/**
 * @brief Formats error with full debug info including stack trace.
 *
 * The returned string must be freed with rac_free().
 *
 * @param error Error to format
 * @return Debug string (caller must free)
 */
RAC_API char* rac_error_to_debug_string(const rac_error_t* error);

// =============================================================================
// CONVENIENCE MACROS
// =============================================================================

/**
 * @brief Creates an error with automatic source location capture.
 */
#define RAC_ERROR(code, category, message) \
    rac_error_create_at(code, category, message, __FILE__, __LINE__, __func__)

/**
 * @brief Creates an error with formatted message and source location.
 */
#define RAC_ERRORF(code, category, ...) \
    rac_error_create_at_f(code, category, __FILE__, __LINE__, __func__, __VA_ARGS__)

/**
 * @brief Category-specific error macros.
 */
#define RAC_ERROR_STT(code, msg) RAC_ERROR(code, RAC_CATEGORY_STT, msg)
#define RAC_ERROR_TTS(code, msg) RAC_ERROR(code, RAC_CATEGORY_TTS, msg)
#define RAC_ERROR_LLM(code, msg) RAC_ERROR(code, RAC_CATEGORY_LLM, msg)
#define RAC_ERROR_VAD(code, msg) RAC_ERROR(code, RAC_CATEGORY_VAD, msg)
#define RAC_ERROR_GENERAL(code, msg) RAC_ERROR(code, RAC_CATEGORY_GENERAL, msg)
#define RAC_ERROR_NETWORK(code, msg) RAC_ERROR(code, RAC_CATEGORY_NETWORK, msg)
#define RAC_ERROR_DOWNLOAD(code, msg) RAC_ERROR(code, RAC_CATEGORY_DOWNLOAD, msg)

// =============================================================================
// GLOBAL ERROR (Thread-Local Last Error)
// =============================================================================

/**
 * @brief Sets the last error for the current thread.
 *
 * This copies the error into thread-local storage. The original error
 * can be destroyed after this call.
 *
 * @param error Error to set (can be NULL to clear)
 */
RAC_API void rac_set_last_error(const rac_error_t* error);

/**
 * @brief Gets the last error for the current thread.
 *
 * @return Pointer to thread-local error (do not free), or NULL if none
 */
RAC_API const rac_error_t* rac_get_last_error(void);

/**
 * @brief Clears the last error for the current thread.
 */
RAC_API void rac_clear_last_error(void);

/**
 * @brief Convenience: creates, logs, and sets last error in one call.
 *
 * @param code Error code
 * @param category Error category
 * @param message Error message
 * @return The error code (for easy return statements)
 */
RAC_API rac_result_t rac_set_error(rac_result_t code, rac_error_category_t category,
                                   const char* message);

/**
 * @brief Convenience macro to set error and return.
 */
#define RAC_RETURN_ERROR(code, category, msg) return rac_set_error(code, category, msg)

// =============================================================================
// UNIFIED ERROR HANDLING (Log + Track)
// =============================================================================

/**
 * @brief Creates, logs, and tracks a structured error.
 *
 * This is the recommended way to handle errors in C++ code. It:
 * 1. Creates a structured error with source location
 * 2. Captures stack trace (if available)
 * 3. Logs the error via the logging system
 * 4. Sends to error tracking (Sentry) via platform adapter
 * 5. Sets as last error for retrieval
 *
 * @param code Error code
 * @param category Error category
 * @param message Error message
 * @param file Source file (__FILE__)
 * @param line Source line (__LINE__)
 * @param function Function name (__func__)
 * @return The error code (for easy return statements)
 */
RAC_API rac_result_t rac_error_log_and_track(rac_result_t code, rac_error_category_t category,
                                             const char* message, const char* file, int32_t line,
                                             const char* function);

/**
 * @brief Creates, logs, and tracks a structured error with model context.
 *
 * Same as rac_error_log_and_track but includes model information.
 *
 * @param code Error code
 * @param category Error category
 * @param message Error message
 * @param model_id Model ID
 * @param framework Framework name
 * @param file Source file
 * @param line Source line
 * @param function Function name
 * @return The error code
 */
RAC_API rac_result_t rac_error_log_and_track_model(rac_result_t code, rac_error_category_t category,
                                                   const char* message, const char* model_id,
                                                   const char* framework, const char* file,
                                                   int32_t line, const char* function);

/**
 * @brief Convenience macro to create, log, track error and return.
 *
 * Usage:
 *   if (model == NULL) {
 *       RAC_RETURN_TRACKED_ERROR(RAC_ERROR_MODEL_NOT_FOUND, RAC_CATEGORY_LLM, "Model not found");
 *   }
 */
#define RAC_RETURN_TRACKED_ERROR(code, category, msg) \
    return rac_error_log_and_track(code, category, msg, __FILE__, __LINE__, __func__)

/**
 * @brief Convenience macro with model context.
 */
#define RAC_RETURN_TRACKED_ERROR_MODEL(code, category, msg, model_id, framework)    \
    return rac_error_log_and_track_model(code, category, msg, model_id, framework,  \
                                         __FILE__, __LINE__, __func__)

#ifdef __cplusplus
}
#endif

// =============================================================================
// C++ CONVENIENCE CLASS
// =============================================================================

#ifdef __cplusplus

#include <memory>
#include <string>

namespace rac {

/**
 * @brief RAII wrapper for rac_error_t.
 */
class Error {
   public:
    Error(rac_result_t code, rac_error_category_t category, const char* message)
        : error_(rac_error_create(code, category, message), rac_error_destroy) {}

    Error(rac_error_t* error) : error_(error, rac_error_destroy) {}

    // Factory methods
    static Error stt(rac_result_t code, const char* msg) { return {code, RAC_CATEGORY_STT, msg}; }
    static Error tts(rac_result_t code, const char* msg) { return {code, RAC_CATEGORY_TTS, msg}; }
    static Error llm(rac_result_t code, const char* msg) { return {code, RAC_CATEGORY_LLM, msg}; }
    static Error vad(rac_result_t code, const char* msg) { return {code, RAC_CATEGORY_VAD, msg}; }
    static Error network(rac_result_t code, const char* msg) {
        return {code, RAC_CATEGORY_NETWORK, msg};
    }

    // Accessors
    rac_result_t code() const { return error_ ? error_->code : RAC_SUCCESS; }
    rac_error_category_t category() const {
        return error_ ? error_->category : RAC_CATEGORY_GENERAL;
    }
    const char* message() const { return error_ ? error_->message : ""; }

    // Configuration
    Error& setModelContext(const char* model_id, const char* framework) {
        if (error_)
            rac_error_set_model_context(error_.get(), model_id, framework);
        return *this;
    }

    Error& setSession(const char* session_id) {
        if (error_)
            rac_error_set_session(error_.get(), session_id);
        return *this;
    }

    Error& captureStackTrace() {
        if (error_)
            rac_error_capture_stack_trace(error_.get());
        return *this;
    }

    // Conversion
    std::string toString() const {
        if (!error_)
            return "";
        char* str = rac_error_to_string(error_.get());
        std::string result(str ? str : "");
        rac_free(str);
        return result;
    }

    std::string toJson() const {
        if (!error_)
            return "{}";
        char* json = rac_error_to_json(error_.get());
        std::string result(json ? json : "{}");
        rac_free(json);
        return result;
    }

    // Raw access
    rac_error_t* get() { return error_.get(); }
    const rac_error_t* get() const { return error_.get(); }
    operator bool() const { return error_ != nullptr; }

   private:
    std::unique_ptr<rac_error_t, decltype(&rac_error_destroy)> error_;
};

}  // namespace rac

#endif  // __cplusplus

#endif /* RAC_STRUCTURED_ERROR_H */
