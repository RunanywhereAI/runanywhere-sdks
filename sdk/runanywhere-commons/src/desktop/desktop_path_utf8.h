#ifndef RAC_DESKTOP_PATH_UTF8_H
#define RAC_DESKTOP_PATH_UTF8_H

/**
 * @file desktop_path_utf8.h
 * @brief UTF-8-correct filesystem helpers shared by the desktop platform
 *        adapter and the desktop secure store.
 *
 * The rac_platform_adapter_t contract documents every path/name as UTF-8. On
 * Windows the narrow std::fopen / std::remove / fs::path(const char*) overloads
 * decode bytes with the process ANSI code page, not UTF-8, so a non-ASCII path
 * (CJK / accented AppData or custom dir) would reach the wrong file or
 * spuriously report ENOENT. These wrappers convert to wide with the shared
 * rac_to_wstring helper (the same one ONNX Runtime session paths use) and call
 * the wide CRT/filesystem APIs. On POSIX the narrow byte string is already
 * UTF-8, so each helper reduces to the original call with no behavior change.
 */

#include <cstdio>
#include <filesystem>
#include <string>

#if defined(_WIN32)
#include "core/internal/platform_compat.h"  // rac_to_wstring
#endif

namespace rac::desktop {

inline std::filesystem::path utf8_to_path(const char* utf8) {
#if defined(_WIN32)
    return std::filesystem::path(rac_to_wstring(utf8));
#else
    return std::filesystem::path(utf8);
#endif
}

inline std::filesystem::path utf8_to_path(const std::string& utf8) {
    return utf8_to_path(utf8.c_str());
}

inline FILE* utf8_fopen(const char* utf8, const char* mode) {
#if defined(_WIN32)
    // mode is ASCII ("rb"/"wb"), so widening it byte-for-byte is safe.
    return _wfopen(rac_to_wstring(utf8).c_str(), rac_to_wstring(mode).c_str());
#else
    return std::fopen(utf8, mode);
#endif
}

inline int utf8_remove(const char* utf8) {
#if defined(_WIN32)
    return _wremove(rac_to_wstring(utf8).c_str());
#else
    return std::remove(utf8);
#endif
}

// UTF-8 filename, never the ANSI code page: fs::path::string() throws on Windows
// for code points the active code page cannot represent, and that exception
// would escape a C-ABI callback. u8string() is always UTF-8.
inline std::string filename_utf8(const std::filesystem::path& p) {
    const auto name = p.filename().u8string();  // std::u8string, always UTF-8
    return std::string(reinterpret_cast<const char*>(name.data()), name.size());
}

}  // namespace rac::desktop

#endif  // RAC_DESKTOP_PATH_UTF8_H
