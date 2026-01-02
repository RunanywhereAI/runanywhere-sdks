/**
 * @file rac_log.h
 * @brief RunAnywhere Commons - Logging API
 *
 * Provides simple logging macros for the C++ commons layer.
 * These are internal logging utilities that route to the platform adapter
 * when available, or to stdout/stderr for debugging.
 */

#ifndef RAC_LOG_H
#define RAC_LOG_H

#include <stdarg.h>
#include <stdio.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// LOGGING FUNCTIONS
// =============================================================================

/**
 * @brief Internal logging function.
 * @param level Log level (uses rac_log_level_t from rac_types.h)
 * @param category Log category (e.g., "LLM.Analytics")
 * @param format Printf-style format string
 * @param ... Format arguments
 */
static inline void rac_log_impl(rac_log_level_t level, const char* category, const char* format,
                                ...) {
    // TODO: Route to platform adapter's logging when available
    // For now, output to stderr for debugging

    const char* level_str = "???";
    switch (level) {
        case RAC_LOG_TRACE:
            level_str = "TRACE";
            break;
        case RAC_LOG_DEBUG:
            level_str = "DEBUG";
            break;
        case RAC_LOG_INFO:
            level_str = "INFO";
            break;
        case RAC_LOG_WARNING:
            level_str = "WARN";
            break;
        case RAC_LOG_ERROR:
            level_str = "ERROR";
            break;
        case RAC_LOG_FATAL:
            level_str = "FATAL";
            break;
    }

    va_list args;
    va_start(args, format);

    fprintf(stderr, "[RAC][%s][%s] ", level_str, category);
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");

    va_end(args);
}

// =============================================================================
// CONVENIENCE MACROS
// =============================================================================

/**
 * @brief Log a debug message.
 * @param category Log category
 * @param ... Printf-style format string and arguments
 */
#define log_debug(category, ...) rac_log_impl(RAC_LOG_DEBUG, category, __VA_ARGS__)

/**
 * @brief Log an info message.
 * @param category Log category
 * @param ... Printf-style format string and arguments
 */
#define log_info(category, ...) rac_log_impl(RAC_LOG_INFO, category, __VA_ARGS__)

/**
 * @brief Log a warning message.
 * @param category Log category
 * @param ... Printf-style format string and arguments
 */
#define log_warning(category, ...) rac_log_impl(RAC_LOG_WARNING, category, __VA_ARGS__)

/**
 * @brief Log an error message.
 * @param category Log category
 * @param ... Printf-style format string and arguments
 */
#define log_error(category, ...) rac_log_impl(RAC_LOG_ERROR, category, __VA_ARGS__)

#ifdef __cplusplus
}
#endif

#endif /* RAC_LOG_H */
