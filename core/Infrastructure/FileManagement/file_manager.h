// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Cross-platform file-system helpers. Ports the capability surface from
// `sdk/runanywhere-commons/include/rac/infrastructure/file_management/
// rac_file_manager.h`.
//
// Everything here is a thin wrapper over std::filesystem — the legacy
// commons used a callback-based abstraction for platform-native file
// ops because it supported iOS 12 / Android API 21. std::filesystem is
// now available everywhere we ship (iOS 13+, Android NDK 25+, macOS 10.15+),
// so the wrappers are simple.

#ifndef RA_CORE_UTIL_FILE_MANAGER_H
#define RA_CORE_UTIL_FILE_MANAGER_H

#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace ra::core::util {

// Directory lifecycle ------------------------------------------------------

bool        create_directory(std::string_view path);
bool        remove_path(std::string_view path);       // recursive
bool        path_exists(std::string_view path);
bool        is_directory(std::string_view path);
bool        is_regular_file(std::string_view path);

// Listing ------------------------------------------------------------------

std::vector<std::string> list_directory(std::string_view path);
std::vector<std::string> list_directory_recursive(std::string_view path);

// Size --------------------------------------------------------------------

// Recursive directory size in bytes. Returns 0 if path doesn't exist.
std::uint64_t directory_size_bytes(std::string_view path);

// Single-file size. Returns 0 on error.
std::uint64_t file_size_bytes(std::string_view path);

// Platform storage directories -------------------------------------------
//
// These return the canonical per-platform base directories. On Apple
// they map to NSFileManager URLs; on Linux to $XDG_*; on Android to
// getCacheDir/getFilesDir via JNI (the JNI bridge populates these at
// SDK initialization time — see sdk/runanywhere-kotlin/modules/core).
// When no platform adapter is registered, falls back to the user home
// directory with conventional subdir names.

std::filesystem::path app_support_dir();   // ~/Library/Application Support/RunAnywhere  or  $XDG_DATA_HOME/runanywhere
std::filesystem::path cache_dir();         // ~/Library/Caches/RunAnywhere              or  $XDG_CACHE_HOME/runanywhere
std::filesystem::path tmp_dir();           // /tmp, wrapped to a per-process subdir

// Models dir — where the model registry places downloaded artifacts.
// Legacy convention: {base}/RunAnywhere/Models/{framework}/{model_id}/
// The new convention uses app_support_dir() as the base.
std::filesystem::path models_dir();

// Convenience: full model path for a given framework + id. Caller is
// responsible for creating intermediate directories.
std::filesystem::path model_path(std::string_view framework,
                                   std::string_view model_id);

// Cleanup -----------------------------------------------------------------

// Empties the entire cache directory. Returns bytes reclaimed.
std::uint64_t clear_cache();
// Empties the tmp directory. Returns bytes reclaimed.
std::uint64_t clear_tmp();

}  // namespace ra::core::util

#endif  // RA_CORE_UTIL_FILE_MANAGER_H
