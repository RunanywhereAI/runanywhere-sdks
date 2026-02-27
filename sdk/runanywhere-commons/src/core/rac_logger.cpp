/**
 * @file rac_logger.cpp
 * @brief RunAnywhere Commons - Logger Implementation
 *
 * Implements the structured logging system that routes through the platform
 * adapter to Swift/Kotlin for proper telemetry and error tracking.
 */

#include "rac/core/rac_logger.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_platform_adapter.h"

// =============================================================================
// INTERNAL STATE
// =============================================================================

namespace {

// Logger configuration
// min_level is atomic so log-level checks can skip the mutex entirely.
// stderr_fallback/stderr_always are also atomic for lock-free reads in the hot path.
struct LoggerState {
    std::atomic<rac_log_level_t> min_level{RAC_LOG_INFO};
    std::atomic<rac_bool_t> stderr_fallback{RAC_TRUE};
    std::atomic<rac_bool_t> stderr_always{RAC_TRUE};
    std::atomic<rac_bool_t> initialized{RAC_FALSE};
    std::mutex mutex;  // Only used for write operations (init/shutdown/set)
};

LoggerState& state() {
    static LoggerState s;
    return s;
}

// Level to string
const char* level_to_string(rac_log_level_t level) {
    switch (level) {
        case RAC_LOG_TRACE:
            return "TRACE";
        case RAC_LOG_DEBUG:
            return "DEBUG";
        case RAC_LOG_INFO:
            return "INFO";
        case RAC_LOG_WARNING:
            return "WARN";
        case RAC_LOG_ERROR:
            return "ERROR";
        case RAC_LOG_FATAL:
            return "FATAL";
        default:
            return "???";
    }
}

// Extract filename from path
const char* filename_from_path(const char* path) {
    if (!path)
        return nullptr;
    const char* last_slash = strrchr(path, '/');
    const char* last_backslash = strrchr(path, '\\');
    // Pick the later separator. Avoid comparing two pointers from unrelated
    // arrays (UB when one is nullptr): explicitly handle the null cases.
    const char* last_sep;
    if (last_slash && last_backslash) {
        last_sep = last_slash > last_backslash ? last_slash : last_backslash;
    } else {
        last_sep = last_slash ? last_slash : last_backslash;
    }
    return last_sep ? last_sep + 1 : path;
}

// Format message with metadata for platform adapter
void format_message_with_metadata(char* buffer, size_t buffer_size, const char* message,
                                  const rac_log_metadata_t* metadata) {
    if (!metadata) {
        snprintf(buffer, buffer_size, "%s", message);
        return;
    }

    // Start with the message
    size_t pos = snprintf(buffer, buffer_size, "%s", message);

    // Add metadata if present
    bool has_meta = false;

    if (metadata->file && pos < buffer_size) {
        const char* filename = filename_from_path(metadata->file);
        if (filename) {
            pos += snprintf(buffer + pos, buffer_size - pos, "%s file=%s:%d", has_meta ? "," : " |",
                            filename, metadata->line);
            has_meta = true;
        }
    }

    if (metadata->function && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s func=%s", has_meta ? "," : " |",
                        metadata->function);
        has_meta = true;
    }

    if (metadata->error_code != 0 && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s error_code=%d", has_meta ? "," : " |",
                        metadata->error_code);
        has_meta = true;
    }

    if (metadata->error_msg && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s error=%s", has_meta ? "," : " |",
                        metadata->error_msg);
        has_meta = true;
    }

    if (metadata->model_id && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s model=%s", has_meta ? "," : " |",
                        metadata->model_id);
        has_meta = true;
    }

    if (metadata->framework && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s framework=%s", has_meta ? "," : " |",
                        metadata->framework);
        has_meta = true;
    }

    // Custom key-value pairs
    if (metadata->custom_key1 && metadata->custom_value1 && pos < buffer_size) {
        pos += snprintf(buffer + pos, buffer_size - pos, "%s %s=%s", has_meta ? "," : " |",
                        metadata->custom_key1, metadata->custom_value1);
        has_meta = true;
    }

    if (metadata->custom_key2 && metadata->custom_value2 && pos < buffer_size) {
        snprintf(buffer + pos, buffer_size - pos, "%s %s=%s", has_meta ? "," : " |",
                 metadata->custom_key2, metadata->custom_value2);
    }
}

// Fallback to stderr
void log_to_stderr(rac_log_level_t level, const char* category, const char* message,
                   const rac_log_metadata_t* metadata) {
    const char* const level_str = level_to_string(level);

    // Determine output stream
    FILE* const stream = (level >= RAC_LOG_ERROR) ? stderr : stdout;

    // Print base message
    fprintf(stream, "[RAC][%s][%s] %s", level_str, category, message);

    // Print metadata if present
    if (metadata) {
        if (metadata->file) {
            const char* filename = filename_from_path(metadata->file);
            if (filename) {
                fprintf(stream, " | file=%s:%d", filename, metadata->line);
            }
        }
        if (metadata->function) {
            fprintf(stream, ", func=%s", metadata->function);
        }
        if (metadata->error_code != 0) {
            fprintf(stream, ", error_code=%d", metadata->error_code);
        }
        if (metadata->model_id) {
            fprintf(stream, ", model=%s", metadata->model_id);
        }
        if (metadata->framework) {
            fprintf(stream, ", framework=%s", metadata->framework);
        }
    }

    fprintf(stream, "\n");
    fflush(stream);
}

}  // anonymous namespace

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_logger_init(rac_log_level_t min_level) {
    state().min_level.store(min_level, std::memory_order_relaxed);
    state().initialized.store(RAC_TRUE, std::memory_order_release);
    return RAC_SUCCESS;
}

void rac_logger_shutdown(void) {
    state().initialized.store(RAC_FALSE, std::memory_order_release);
}

void rac_logger_set_min_level(rac_log_level_t level) {
    state().min_level.store(level, std::memory_order_relaxed);
}

rac_log_level_t rac_logger_get_min_level(void) {
    return state().min_level.load(std::memory_order_relaxed);
}

void rac_logger_set_stderr_fallback(rac_bool_t enabled) {
    state().stderr_fallback.store(enabled, std::memory_order_relaxed);
}

void rac_logger_set_stderr_always(rac_bool_t enabled) {
    state().stderr_always.store(enabled, std::memory_order_relaxed);
}

void rac_logger_log(rac_log_level_t level, const char* category, const char* message,
                    const rac_log_metadata_t* metadata) {
    if (!message)
        return;
    if (!category)
        category = "RAC";

    // Atomic reads — no mutex needed for the hot-path level check
    const rac_log_level_t min_level = state().min_level.load(std::memory_order_relaxed);
    const rac_bool_t stderr_always = state().stderr_always.load(std::memory_order_relaxed);
    const rac_bool_t stderr_fallback = state().stderr_fallback.load(std::memory_order_relaxed);

    // Check min level (early out before any formatting work)
    if (level < min_level)
        return;

    // ALWAYS log to stderr first if enabled (safe during static initialization)
    // This ensures we can debug crashes even before platform adapter is ready
    if (stderr_always != 0) {
        log_to_stderr(level, category, message, metadata);
    }

    // Also forward to platform adapter if available
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->log) {
        // Format message with metadata for the platform
        char formatted[2048];
        format_message_with_metadata(formatted, sizeof(formatted), message, metadata);
        adapter->log(level, category, formatted, adapter->user_data);
    } else if (stderr_always == 0 && stderr_fallback != 0) {
        // Fallback to stderr only if we haven't already logged there
        log_to_stderr(level, category, message, metadata);
    }
}

void rac_logger_logf(rac_log_level_t level, const char* category,
                     const rac_log_metadata_t* metadata, const char* format, ...) {
    if (!format)
        return;

    // Early level check: skip vsnprintf entirely if this message will be filtered
    if (level < state().min_level.load(std::memory_order_relaxed))
        return;

    va_list args;
    va_start(args, format);
    rac_logger_logv(level, category, metadata, format, args);
    va_end(args);
}

void rac_logger_logv(rac_log_level_t level, const char* category,
                     const rac_log_metadata_t* metadata, const char* format, va_list args) {
    if (!format)
        return;

    // Early level check: skip vsnprintf entirely if this message will be filtered
    if (level < state().min_level.load(std::memory_order_relaxed))
        return;

    // Format the message (only reached when level passes)
    char buffer[2048];
    vsnprintf(buffer, sizeof(buffer), format, args);

    rac_logger_log(level, category, buffer, metadata);
}

}  // extern "C"
