/**
 * @file directory_probe.cpp
 * @brief Implementation of rac_classify_null_directory_listing.
 */

#include <filesystem>
#include <system_error>

#include "rac/infrastructure/file_management/rac_directory_probe.h"

#if defined(_WIN32)
#include <string>

// rac_to_wstring_strict; also brings in <windows.h> with the repo's macro guards.
#include "core/internal/platform_compat.h"
#endif

// File.exists()/isDirectory() hide stat errors behind false. After the platform
// returns a null listing, confirm absence using a probe that retains its error.
// An existing directory is inconclusive too: it may have become accessible
// since the platform probe, so preserve its registered path until a later refresh.
extern "C" rac_result_t rac_classify_null_directory_listing(const char* path) {
    if (!path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::error_code error;
    std::filesystem::file_status status;
    try {
#if defined(_WIN32)
        // The narrow std::filesystem::path constructor uses the ANSI code page
        // on Windows, so convert the UTF-8 path to UTF-16 first.
        std::wstring wide;
        if (!rac_to_wstring_strict(path, &wide)) {
            // Can't name the path reliably, so don't claim it's missing.
            return RAC_ERROR_FILE_READ_FAILED;
        }
        status = std::filesystem::status(std::filesystem::path(wide), error);
#else
        status = std::filesystem::status(path, error);
#endif
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
