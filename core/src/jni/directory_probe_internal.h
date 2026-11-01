/**
 * @file directory_probe_internal.h
 * @brief Error-aware classification of an ambiguous Java directory probe.
 */

#ifndef RAC_JNI_DIRECTORY_PROBE_INTERNAL_H
#define RAC_JNI_DIRECTORY_PROBE_INTERNAL_H

#include <filesystem>
#include <system_error>

#include "rac/core/rac_error.h"

namespace rac::jni {

// File.exists()/isDirectory() hide stat errors behind false. After Kotlin
// returns a null listing, confirm absence using a probe that retains its error.
// An existing directory is inconclusive too: it may have become accessible
// since the Java probe, so preserve its registered path until a later refresh.
inline rac_result_t classify_null_directory_listing(const char* path) noexcept {
    if (!path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::error_code error;
    std::filesystem::file_status status;
    try {
        status = std::filesystem::status(path, error);
    } catch (...) {
        // Path construction can allocate even with the error-code overload.
        // Keep failures inconclusive instead of letting them escape through JNI.
        return RAC_ERROR_FILE_READ_FAILED;
    }
    if (error == std::errc::no_such_file_or_directory || error == std::errc::not_a_directory) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    if (!error && status.type() != std::filesystem::file_type::none &&
        status.type() != std::filesystem::file_type::unknown &&
        !std::filesystem::is_directory(status)) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    return RAC_ERROR_FILE_READ_FAILED;
}

}  // namespace rac::jni

#endif  // RAC_JNI_DIRECTORY_PROBE_INTERNAL_H
