// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "file_manager.h"

#include <cstdlib>
#include <system_error>

namespace ra::core::util {

namespace fs = std::filesystem;

bool create_directory(std::string_view path) {
    std::error_code ec;
    fs::create_directories(fs::path(std::string{path}), ec);
    return !ec;
}

bool remove_path(std::string_view path) {
    std::error_code ec;
    fs::remove_all(fs::path(std::string{path}), ec);
    return !ec;
}

bool path_exists(std::string_view path) {
    std::error_code ec;
    return fs::exists(fs::path(std::string{path}), ec);
}

bool is_directory(std::string_view path) {
    std::error_code ec;
    return fs::is_directory(fs::path(std::string{path}), ec);
}

bool is_regular_file(std::string_view path) {
    std::error_code ec;
    return fs::is_regular_file(fs::path(std::string{path}), ec);
}

std::vector<std::string> list_directory(std::string_view path) {
    std::vector<std::string> out;
    std::error_code ec;
    for (auto& entry : fs::directory_iterator(fs::path(std::string{path}), ec)) {
        if (ec) break;
        out.push_back(entry.path().string());
    }
    return out;
}

std::vector<std::string> list_directory_recursive(std::string_view path) {
    std::vector<std::string> out;
    std::error_code ec;
    for (auto& entry :
         fs::recursive_directory_iterator(fs::path(std::string{path}), ec)) {
        if (ec) break;
        out.push_back(entry.path().string());
    }
    return out;
}

std::uint64_t directory_size_bytes(std::string_view path) {
    std::error_code ec;
    std::uint64_t total = 0;
    for (auto& entry :
         fs::recursive_directory_iterator(fs::path(std::string{path}), ec)) {
        if (ec) break;
        if (entry.is_regular_file(ec)) {
            total += static_cast<std::uint64_t>(entry.file_size(ec));
        }
    }
    return total;
}

std::uint64_t file_size_bytes(std::string_view path) {
    std::error_code ec;
    const auto n = fs::file_size(fs::path(std::string{path}), ec);
    return ec ? 0u : static_cast<std::uint64_t>(n);
}

// ---- Platform-specific directory lookups -------------------------------

namespace {

fs::path home_dir() {
    if (const char* h = std::getenv("HOME"); h && *h) return fs::path(h);
    return fs::path("/tmp");
}

fs::path env_or(fs::path default_path, const char* envvar) {
    if (const char* v = std::getenv(envvar); v && *v) return fs::path(v);
    return default_path;
}

}  // namespace

fs::path app_support_dir() {
#if defined(__APPLE__)
    return home_dir() / "Library" / "Application Support" / "RunAnywhere";
#elif defined(__linux__) || defined(__ANDROID__)
    return env_or(home_dir() / ".local/share", "XDG_DATA_HOME") / "runanywhere";
#elif defined(_WIN32)
    return env_or(home_dir() / "AppData/Roaming", "APPDATA") / "RunAnywhere";
#else
    return home_dir() / ".runanywhere";
#endif
}

fs::path cache_dir() {
#if defined(__APPLE__)
    return home_dir() / "Library" / "Caches" / "RunAnywhere";
#elif defined(__linux__) || defined(__ANDROID__)
    return env_or(home_dir() / ".cache", "XDG_CACHE_HOME") / "runanywhere";
#elif defined(_WIN32)
    return env_or(home_dir() / "AppData/Local", "LOCALAPPDATA") / "RunAnywhere/Cache";
#else
    return home_dir() / ".cache" / "runanywhere";
#endif
}

fs::path tmp_dir() {
    // std::filesystem::temp_directory_path already resolves $TMPDIR / $TMP etc.
    std::error_code ec;
    auto t = fs::temp_directory_path(ec);
    if (ec) t = "/tmp";
    return t / "runanywhere";
}

fs::path models_dir() {
    // Legacy convention: {base}/RunAnywhere/Models/... but since we put
    // everything under app_support_dir() which already has "RunAnywhere"
    // in the Apple case, just append "Models".
    return app_support_dir() / "Models";
}

fs::path model_path(std::string_view framework, std::string_view model_id) {
    return models_dir() / fs::path(std::string{framework})
                         / fs::path(std::string{model_id});
}

// ---- Cleanup helpers ----------------------------------------------------

std::uint64_t clear_cache() {
    const auto dir = cache_dir();
    const std::uint64_t before = directory_size_bytes(dir.string());
    remove_path(dir.string());
    create_directory(dir.string());
    return before;
}

std::uint64_t clear_tmp() {
    const auto dir = tmp_dir();
    const std::uint64_t before = directory_size_bytes(dir.string());
    remove_path(dir.string());
    create_directory(dir.string());
    return before;
}

}  // namespace ra::core::util
