/**
 * @file desktop_secure_store.cpp
 * @brief Desktop secure-storage slots backed by protected per-key files.
 *
 * POSIX stores each value in a 0600 file under a 0700 directory. Windows
 * encrypts each value with the current user's DPAPI key before writing it
 * under AppData. There is no shared parser and each key maps to one file.
 *
 * Contract (rac_platform_adapter.h secure_get docs):
 *   - clean miss            → RAC_ERROR_FILE_NOT_FOUND, *out_value untouched
 *   - any real failure      → RAC_ERROR_SECURE_STORAGE_FAILED
 *   - success               → *out_value heap-allocated, freed via rac_free()
 */

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <wincrypt.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>

#include <sys/stat.h>
#endif

#include "desktop/desktop_internal.h"
#include "desktop/desktop_path_utf8.h"  // utf8_to_path / utf8_fopen / utf8_remove
#include "rac/core/rac_error.h"

namespace rac::desktop {

namespace {

namespace fs = std::filesystem;

std::mutex g_store_mutex;
std::string g_store_dir;  // <config dir>; files live in <config dir>/secure/

// Keys may contain arbitrary bytes; encode anything outside [A-Za-z0-9._-] as
// %XX so every key maps to exactly one safe filename.
std::string encode_key(const char* key) {
    static const char hex[] = "0123456789ABCDEF";
    std::string encoded;
    for (const char* p = key; *p != '\0'; ++p) {
        const unsigned char c = static_cast<unsigned char>(*p);
        const bool safe = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                          (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
        if (safe) {
            encoded.push_back(static_cast<char>(c));
        } else {
            encoded.push_back('%');
            encoded.push_back(hex[c >> 4]);
            encoded.push_back(hex[c & 0xF]);
        }
    }
    return encoded;
}

// Returns the absolute file path for a key, creating the store directory
// hierarchy (0700) on demand. Empty string when the store is unconfigured.
std::string key_path_locked(const char* key) {
    if (g_store_dir.empty()) {
        return {};
    }
    const std::string secure_dir = g_store_dir + "/secure";
    std::error_code ec;
    fs::create_directories(utf8_to_path(secure_dir), ec);
    if (ec) {
        return {};
    }
#if !defined(_WIN32)
    // Existing directories may have wider permissions than the current umask.
    if (chmod(g_store_dir.c_str(), S_IRWXU) != 0 || chmod(secure_dir.c_str(), S_IRWXU) != 0) {
        return {};
    }
#endif
    return secure_dir + "/" + encode_key(key);
}

}  // namespace

void secure_store_set_dir(const std::string& dir) {
    std::lock_guard<std::mutex> lock(g_store_mutex);
    g_store_dir = dir;
    while (!g_store_dir.empty() && (g_store_dir.back() == '/' || g_store_dir.back() == '\\')) {
        g_store_dir.pop_back();
    }
}

rac_result_t secure_get(const char* key, char** out_value, void* /*user_data*/) {
    if (!key || !out_value) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    std::lock_guard<std::mutex> lock(g_store_mutex);
    const std::string path = key_path_locked(key);
    if (path.empty()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    FILE* f = utf8_fopen(path.c_str(), "rb");
    if (!f) {
        return (errno == ENOENT) ? RAC_ERROR_FILE_NOT_FOUND : RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    std::string value;
    char buffer[512];
    size_t n = 0;
    while ((n = std::fread(buffer, 1, sizeof(buffer), f)) > 0) {
        value.append(buffer, n);
    }
    const bool read_ok = std::ferror(f) == 0;
    std::fclose(f);
    if (!read_ok) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

#if defined(_WIN32)
    DATA_BLOB protected_blob{};
    protected_blob.cbData = static_cast<DWORD>(value.size());
    protected_blob.pbData = reinterpret_cast<BYTE*>(value.data());
    DATA_BLOB clear_blob{};
    if (!CryptUnprotectData(&protected_blob, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &clear_blob)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    char* copy = static_cast<char*>(std::malloc(clear_blob.cbData + 1));
    if (!copy) {
        LocalFree(clear_blob.pbData);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    std::memcpy(copy, clear_blob.pbData, clear_blob.cbData);
    copy[clear_blob.cbData] = '\0';
    LocalFree(clear_blob.pbData);
#else
    char* copy = static_cast<char*>(std::malloc(value.size() + 1));
    if (!copy) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    std::memcpy(copy, value.c_str(), value.size() + 1);
#endif
    *out_value = copy;
    return RAC_SUCCESS;
}

rac_result_t secure_set(const char* key, const char* value, void* /*user_data*/) {
    if (!key || !value) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    std::lock_guard<std::mutex> lock(g_store_mutex);
    const std::string path = key_path_locked(key);
    if (path.empty()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

#if defined(_WIN32)
    DATA_BLOB clear_blob{};
    clear_blob.cbData = static_cast<DWORD>(std::strlen(value));
    clear_blob.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(value));
    DATA_BLOB protected_blob{};
    if (!CryptProtectData(&clear_blob, L"RunAnywhere rcli", nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &protected_blob)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    FILE* file = utf8_fopen(path.c_str(), "wb");
    bool ok = false;
    if (file) {
        const size_t written = std::fwrite(protected_blob.pbData, 1, protected_blob.cbData, file);
        const int close_rc = std::fclose(file);
        ok = written == protected_blob.cbData && close_rc == 0;
    }
    LocalFree(protected_blob.pbData);
    return ok ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
#else
    // O_CREAT with 0600 so the value is never world-readable, even briefly.
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
    if (fd < 0) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    const size_t len = std::strlen(value);
    size_t written = 0;
    bool ok = true;
    while (written < len) {
        const ssize_t n = write(fd, value + written, len - written);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            ok = false;
            break;
        }
        written += static_cast<size_t>(n);
    }
    // Pre-existing files keep old modes; enforce 0600 on every write.
    ok = (fchmod(fd, S_IRUSR | S_IWUSR) == 0) && ok;
    ok = (close(fd) == 0) && ok;
    return ok ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
#endif
}

rac_result_t secure_delete(const char* key, void* /*user_data*/) {
    if (!key) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    std::lock_guard<std::mutex> lock(g_store_mutex);
    const std::string path = key_path_locked(key);
    if (path.empty()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    if (utf8_remove(path.c_str()) != 0 && errno != ENOENT) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    return RAC_SUCCESS;  // deleting an absent key is a no-op, like Keychain
}

}  // namespace rac::desktop
