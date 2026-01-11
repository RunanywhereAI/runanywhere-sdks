/**
 * @file logger.h
 * @brief RunAnywhere Core - Internal Logger
 *
 * Simple logging utilities for runanywhere-core that can be optionally
 * connected to an external logging system (e.g., the platform adapter).
 *
 * Usage:
 *   RA_LOG_INFO("STT.ONNX", "Model loaded: %s", model_id);
 *   RA_LOG_ERROR("STT.ONNX", "Failed to load: %s", error);
 */

#ifndef RUNANYWHERE_CORE_LOGGER_H
#define RUNANYWHERE_CORE_LOGGER_H

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace runanywhere {

// =============================================================================
// LOG LEVELS
// =============================================================================

enum class LogLevel : int { Trace = 0, Debug = 1, Info = 2, Warning = 3, Error = 4, Fatal = 5 };

// =============================================================================
// LOG CALLBACK TYPE
// =============================================================================

/**
 * External log callback type.
 * Set this to route logs to your platform's logging system.
 *
 * @param level Log level
 * @param category Log category (e.g., "STT.ONNX")
 * @param message Formatted message
 * @param user_data Optional user context
 */
using LogCallback = void (*)(LogLevel level, const char* category, const char* message,
                             void* user_data);

// =============================================================================
// LOGGER CLASS
// =============================================================================

class Logger {
   public:
    static Logger& instance() {
        static Logger logger;
        return logger;
    }

    // Set external callback for routing logs
    void setCallback(LogCallback callback, void* user_data = nullptr) {
        std::lock_guard<std::mutex> lock(mutex_);
        callback_ = callback;
        user_data_ = user_data;
    }

    // Set minimum log level
    void setMinLevel(LogLevel level) {
        std::lock_guard<std::mutex> lock(mutex_);
        min_level_ = level;
    }

    // Enable/disable stderr fallback
    void setStderrFallback(bool enabled) {
        std::lock_guard<std::mutex> lock(mutex_);
        stderr_fallback_ = enabled;
    }

    // Core log function
    void log(LogLevel level, const char* category, const char* format, ...) {
        if (static_cast<int>(level) < static_cast<int>(min_level_)) {
            return;
        }

        // Format the message
        char buffer[2048];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);

        // Route to callback or fallback
        std::lock_guard<std::mutex> lock(mutex_);
        if (callback_) {
            callback_(level, category, buffer, user_data_);
        } else if (stderr_fallback_) {
            logToStderr(level, category, buffer);
        }
    }

   private:
    Logger() = default;

    void logToStderr(LogLevel level, const char* category, const char* message) {
        const char* level_str = levelToString(level);
        FILE* stream = (level >= LogLevel::Error) ? stderr : stdout;
        fprintf(stream, "[%s][%s] %s\n", level_str, category, message);
        fflush(stream);
    }

    static const char* levelToString(LogLevel level) {
        switch (level) {
            case LogLevel::Trace:
                return "TRACE";
            case LogLevel::Debug:
                return "DEBUG";
            case LogLevel::Info:
                return "INFO";
            case LogLevel::Warning:
                return "WARN";
            case LogLevel::Error:
                return "ERROR";
            case LogLevel::Fatal:
                return "FATAL";
            default:
                return "???";
        }
    }

    std::mutex mutex_;
    LogCallback callback_ = nullptr;
    void* user_data_ = nullptr;
    LogLevel min_level_ = LogLevel::Debug;
    bool stderr_fallback_ = true;
};

// =============================================================================
// CONVENIENCE MACROS
// =============================================================================

#define RA_LOG_TRACE(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Trace, category, __VA_ARGS__)

#define RA_LOG_DEBUG(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Debug, category, __VA_ARGS__)

#define RA_LOG_INFO(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Info, category, __VA_ARGS__)

#define RA_LOG_WARNING(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Warning, category, __VA_ARGS__)

#define RA_LOG_ERROR(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Error, category, __VA_ARGS__)

#define RA_LOG_FATAL(category, ...) \
    runanywhere::Logger::instance().log(runanywhere::LogLevel::Fatal, category, __VA_ARGS__)

// Category-specific convenience
#define RA_LOG_STT_INFO(...) RA_LOG_INFO("STT", __VA_ARGS__)
#define RA_LOG_STT_ERROR(...) RA_LOG_ERROR("STT", __VA_ARGS__)
#define RA_LOG_TTS_INFO(...) RA_LOG_INFO("TTS", __VA_ARGS__)
#define RA_LOG_TTS_ERROR(...) RA_LOG_ERROR("TTS", __VA_ARGS__)
#define RA_LOG_VAD_INFO(...) RA_LOG_INFO("VAD", __VA_ARGS__)
#define RA_LOG_VAD_ERROR(...) RA_LOG_ERROR("VAD", __VA_ARGS__)
#define RA_LOG_LLM_INFO(...) RA_LOG_INFO("LLM", __VA_ARGS__)
#define RA_LOG_LLM_ERROR(...) RA_LOG_ERROR("LLM", __VA_ARGS__)
#define RA_LOG_ONNX_INFO(...) RA_LOG_INFO("ONNX", __VA_ARGS__)
#define RA_LOG_ONNX_ERROR(...) RA_LOG_ERROR("ONNX", __VA_ARGS__)

}  // namespace runanywhere

#endif  // RUNANYWHERE_CORE_LOGGER_H
