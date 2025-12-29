/**
 * @file rac_logger.h
 * @brief RunAnywhere Commons - Structured Logging System
 *
 * Provides a structured logging system that:
 * - Routes logs through the platform adapter to Swift/Kotlin
 * - Captures source location metadata (file, line, function)
 * - Supports log levels, categories, and structured metadata
 * - Enables remote telemetry for production error tracking
 *
 * Usage:
 *   RAC_LOG_INFO("LLM", "Model loaded successfully");
 *   RAC_LOG_ERROR("STT", "Failed to load model: %s", error_msg);
 *   RAC_LOG_DEBUG("VAD", "Energy level: %.2f", energy);
 *
 * With metadata:
 *   rac_log_with_metadata(RAC_LOG_ERROR, "ONNX", "Load failed",
 *       (rac_log_metadata_t){
 *           .model_id = "whisper-tiny",
 *           .error_code = -100,
 *           .file = __FILE__,
 *           .line = __LINE__,
 *           .function = __func__
 *       });
 */

#ifndef RAC_LOGGER_H
#define RAC_LOGGER_H

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// LOG METADATA STRUCTURE
// =============================================================================

/**
 * @brief Metadata attached to a log entry.
 *
 * All fields are optional - set to NULL/0 if not applicable.
 * This metadata flows through to Swift/Kotlin for remote telemetry.
 */
typedef struct rac_log_metadata {
    // Source location (auto-populated by macros)
    const char* file;      /**< Source file name (use __FILE__) */
    int32_t line;          /**< Source line number (use __LINE__) */
    const char* function;  /**< Function name (use __func__) */

    // Error context
    int32_t error_code;    /**< Error code if applicable (0 = none) */
    const char* error_msg; /**< Additional error message */

    // Model context
    const char* model_id;  /**< Model ID if applicable */
    const char* framework; /**< Framework name (e.g., "sherpa-onnx") */

    // Custom key-value pairs (for extensibility)
    const char* custom_key1;
    const char* custom_value1;
    const char* custom_key2;
    const char* custom_value2;
} rac_log_metadata_t;

/** Default empty metadata */
#define RAC_LOG_METADATA_EMPTY \
    (rac_log_metadata_t) { NULL, 0, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL }

// =============================================================================
// CORE LOGGING API
// =============================================================================

/**
 * @brief Initialize the logging system.
 *
 * Call this after rac_set_platform_adapter() to enable logging.
 * If not called, logs will fall back to stderr.
 *
 * @param min_level Minimum log level to output
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_logger_init(rac_log_level_t min_level);

/**
 * @brief Shutdown the logging system.
 *
 * Flushes any pending logs.
 */
RAC_API void rac_logger_shutdown(void);

/**
 * @brief Set the minimum log level.
 *
 * Messages below this level will be filtered out.
 *
 * @param level Minimum log level
 */
RAC_API void rac_logger_set_min_level(rac_log_level_t level);

/**
 * @brief Get the current minimum log level.
 *
 * @return Current minimum log level
 */
RAC_API rac_log_level_t rac_logger_get_min_level(void);

/**
 * @brief Enable or disable fallback to stderr when platform adapter unavailable.
 *
 * @param enabled Whether to fallback to stderr (default: true)
 */
RAC_API void rac_logger_set_stderr_fallback(rac_bool_t enabled);

/**
 * @brief Enable or disable ALWAYS logging to stderr (in addition to platform adapter).
 *
 * When enabled (default: true), logs are ALWAYS written to stderr first,
 * then forwarded to the platform adapter if available. This is essential
 * for debugging crashes during static initialization before Swift/Kotlin
 * is ready to receive logs.
 *
 * Set to false in production to reduce duplicate logging overhead.
 *
 * @param enabled Whether to always log to stderr (default: true)
 */
RAC_API void rac_logger_set_stderr_always(rac_bool_t enabled);

/**
 * @brief Log a message with metadata.
 *
 * This is the main logging function. Use the RAC_LOG_* macros for convenience.
 *
 * @param level Log level
 * @param category Log category (e.g., "LLM", "STT.ONNX")
 * @param message Log message (can include printf-style format specifiers)
 * @param metadata Optional metadata (can be NULL)
 */
RAC_API void rac_logger_log(rac_log_level_t level, const char* category, const char* message,
                            const rac_log_metadata_t* metadata);

/**
 * @brief Log a formatted message with metadata.
 *
 * @param level Log level
 * @param category Log category
 * @param metadata Optional metadata (can be NULL)
 * @param format Printf-style format string
 * @param ... Format arguments
 */
RAC_API void rac_logger_logf(rac_log_level_t level, const char* category,
                             const rac_log_metadata_t* metadata, const char* format, ...);

/**
 * @brief Log a formatted message (variadic version).
 *
 * @param level Log level
 * @param category Log category
 * @param metadata Optional metadata
 * @param format Printf-style format string
 * @param args Variadic arguments
 */
RAC_API void rac_logger_logv(rac_log_level_t level, const char* category,
                             const rac_log_metadata_t* metadata, const char* format, va_list args);

// =============================================================================
// CONVENIENCE MACROS
// =============================================================================

/**
 * Helper to create metadata with source location.
 */
#define RAC_LOG_META_HERE() \
    (rac_log_metadata_t) { __FILE__, __LINE__, __func__, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL }

/**
 * Helper to create metadata with source location and error code.
 */
#define RAC_LOG_META_ERROR(code, msg)                                         \
    (rac_log_metadata_t) {                                                    \
        __FILE__, __LINE__, __func__, (code), (msg), NULL, NULL, NULL, NULL, NULL, NULL \
    }

/**
 * Helper to create metadata with model context.
 */
#define RAC_LOG_META_MODEL(mid, fw)                                           \
    (rac_log_metadata_t) {                                                    \
        __FILE__, __LINE__, __func__, 0, NULL, (mid), (fw), NULL, NULL, NULL, NULL \
    }

// --- Level-specific logging macros with automatic source location ---

#define RAC_LOG_TRACE(category, ...)                                        \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_TRACE, category, &_meta, __VA_ARGS__);      \
    } while (0)

#define RAC_LOG_DEBUG(category, ...)                                        \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_DEBUG, category, &_meta, __VA_ARGS__);      \
    } while (0)

#define RAC_LOG_INFO(category, ...)                                         \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_INFO, category, &_meta, __VA_ARGS__);       \
    } while (0)

#define RAC_LOG_WARNING(category, ...)                                      \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_WARNING, category, &_meta, __VA_ARGS__);    \
    } while (0)

#define RAC_LOG_ERROR(category, ...)                                        \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_ERROR, category, &_meta, __VA_ARGS__);      \
    } while (0)

#define RAC_LOG_FATAL(category, ...)                                        \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_HERE();                     \
        rac_logger_logf(RAC_LOG_FATAL, category, &_meta, __VA_ARGS__);      \
    } while (0)

// --- Error logging with code ---

#define RAC_LOG_ERROR_CODE(category, code, ...)                             \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_ERROR(code, NULL);          \
        rac_logger_logf(RAC_LOG_ERROR, category, &_meta, __VA_ARGS__);      \
    } while (0)

// --- Model context logging ---

#define RAC_LOG_MODEL_INFO(category, model_id, framework, ...)              \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_MODEL(model_id, framework); \
        rac_logger_logf(RAC_LOG_INFO, category, &_meta, __VA_ARGS__);       \
    } while (0)

#define RAC_LOG_MODEL_ERROR(category, model_id, framework, ...)             \
    do {                                                                    \
        rac_log_metadata_t _meta = RAC_LOG_META_MODEL(model_id, framework); \
        rac_logger_logf(RAC_LOG_ERROR, category, &_meta, __VA_ARGS__);      \
    } while (0)

// =============================================================================
// LEGACY COMPATIBILITY (maps to new logging system)
// =============================================================================

/**
 * Legacy log_info macro - maps to RAC_LOG_INFO.
 * @deprecated Use RAC_LOG_INFO instead.
 */
#define log_info(category, ...) RAC_LOG_INFO(category, __VA_ARGS__)

/**
 * Legacy log_debug macro - maps to RAC_LOG_DEBUG.
 * @deprecated Use RAC_LOG_DEBUG instead.
 */
#define log_debug(category, ...) RAC_LOG_DEBUG(category, __VA_ARGS__)

/**
 * Legacy log_warning macro - maps to RAC_LOG_WARNING.
 * @deprecated Use RAC_LOG_WARNING instead.
 */
#define log_warning(category, ...) RAC_LOG_WARNING(category, __VA_ARGS__)

/**
 * Legacy log_error macro - maps to RAC_LOG_ERROR.
 * @deprecated Use RAC_LOG_ERROR instead.
 */
#define log_error(category, ...) RAC_LOG_ERROR(category, __VA_ARGS__)

#ifdef __cplusplus
}
#endif

// =============================================================================
// C++ CONVENIENCE CLASS
// =============================================================================

#ifdef __cplusplus

#include <sstream>
#include <string>

namespace rac {

/**
 * @brief C++ Logger class for convenient logging with RAII.
 *
 * Usage:
 *   rac::Logger log("STT.ONNX");
 *   log.info("Model loaded: %s", model_id);
 *   log.error("Failed with code %d", error_code);
 */
class Logger {
public:
    explicit Logger(const char* category) : category_(category) {}
    explicit Logger(const std::string& category) : category_(category.c_str()) {}

    void trace(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_TRACE, category_, nullptr, format, args);
        va_end(args);
    }

    void debug(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_DEBUG, category_, nullptr, format, args);
        va_end(args);
    }

    void info(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_INFO, category_, nullptr, format, args);
        va_end(args);
    }

    void warning(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_WARNING, category_, nullptr, format, args);
        va_end(args);
    }

    void error(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_ERROR, category_, nullptr, format, args);
        va_end(args);
    }

    void error(int32_t code, const char* format, ...) const {
        rac_log_metadata_t meta = RAC_LOG_METADATA_EMPTY;
        meta.error_code = code;

        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_ERROR, category_, &meta, format, args);
        va_end(args);
    }

    void fatal(const char* format, ...) const {
        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_FATAL, category_, nullptr, format, args);
        va_end(args);
    }

    // Log with model context
    void modelInfo(const char* model_id, const char* framework, const char* format, ...) const {
        rac_log_metadata_t meta = RAC_LOG_METADATA_EMPTY;
        meta.model_id = model_id;
        meta.framework = framework;

        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_INFO, category_, &meta, format, args);
        va_end(args);
    }

    void modelError(const char* model_id, const char* framework, int32_t code,
                    const char* format, ...) const {
        rac_log_metadata_t meta = RAC_LOG_METADATA_EMPTY;
        meta.model_id = model_id;
        meta.framework = framework;
        meta.error_code = code;

        va_list args;
        va_start(args, format);
        rac_logger_logv(RAC_LOG_ERROR, category_, &meta, format, args);
        va_end(args);
    }

private:
    const char* category_;
};

// Predefined loggers for common categories
namespace log {
inline Logger llm("LLM");
inline Logger stt("STT");
inline Logger tts("TTS");
inline Logger vad("VAD");
inline Logger onnx("ONNX");
inline Logger llamacpp("LlamaCpp");
inline Logger download("Download");
inline Logger models("Models");
inline Logger core("Core");
} // namespace log

} // namespace rac

#endif // __cplusplus

#endif /* RAC_LOGGER_H */
