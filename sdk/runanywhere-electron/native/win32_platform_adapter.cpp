// win32_platform_adapter.cpp — see header. M0 Win32 platform adapter.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <wincrypt.h>  // DPAPI: CryptProtectData / CryptUnprotectData (crypt32)

#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <system_error>

#include "win32_platform_adapter.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace fs = std::filesystem;

namespace {

// Set once by rac_electron_fill_win32_adapter before rac_init(); read-only after,
// so the "callbacks may run on any thread" contract holds without locking.
std::string g_secure_dir;

const char* level_name(rac_log_level_t lvl) {
    switch (lvl) {
        case RAC_LOG_TRACE: return "TRACE";
        case RAC_LOG_DEBUG: return "DEBUG";
        case RAC_LOG_INFO: return "INFO";
        case RAC_LOG_WARNING: return "WARN";
        case RAC_LOG_ERROR: return "ERROR";
        case RAC_LOG_FATAL: return "FATAL";
        default: return "?";
    }
}

rac_bool_t win_file_exists(const char* path, void*) {
    if (!path) return RAC_FALSE;
    std::error_code ec;
    return (fs::exists(fs::path(path), ec) && !ec) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t win_file_read(const char* path, void** out_data, size_t* out_size, void*) {
    if (!path || !out_data || !out_size) return RAC_ERROR_INVALID_ARGUMENT;
    *out_data = nullptr;
    *out_size = 0;
    FILE* f = fopen(path, "rb");
    if (!f) return RAC_ERROR_FILE_NOT_FOUND;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) {
        fclose(f);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    void* buf = rac_alloc(static_cast<size_t>(n));
    if (!buf) {
        fclose(f);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    size_t got = fread(buf, 1, static_cast<size_t>(n), f);
    fclose(f);
    if (got != static_cast<size_t>(n)) {
        rac_free(buf);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    *out_data = buf;
    *out_size = static_cast<size_t>(n);
    return RAC_SUCCESS;
}

rac_result_t win_file_write(const char* path, const void* data, size_t size, void*) {
    if (!path || (!data && size)) return RAC_ERROR_INVALID_ARGUMENT;
    FILE* f = fopen(path, "wb");
    if (!f) return RAC_ERROR_FILE_WRITE_FAILED;
    size_t put = size ? fwrite(data, 1, size, f) : 0;
    fclose(f);
    return (put == size) ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

rac_result_t win_file_delete(const char* path, void*) {
    if (!path) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::remove(fs::path(path), ec);
    return ec ? RAC_ERROR_INTERNAL : RAC_SUCCESS;
}

fs::path secure_path(const char* key) { return fs::path(g_secure_dir) / fs::path(key); }

// Secure store backed by Windows DPAPI: values are encrypted with the current
// user's credentials (CryptProtectData, no UI) before hitting disk and decrypted
// on read, so a plaintext-file read cannot recover secrets. The description
// string is bound into the blob; the CRYPTPROTECT_UI_FORBIDDEN flag keeps it
// headless. Data is only decryptable by the same Windows user on this machine.
rac_result_t win_secure_get(const char* key, char** out_value, void*) {
    if (!key || !out_value) return RAC_ERROR_INVALID_ARGUMENT;
    *out_value = nullptr;
    std::error_code ec;
    fs::path p = secure_path(key);
    if (!fs::exists(p, ec) || ec) return RAC_ERROR_FILE_NOT_FOUND;  // clean miss contract
    FILE* f = fopen(p.string().c_str(), "rb");
    if (!f) return RAC_ERROR_FILE_NOT_FOUND;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) {
        fclose(f);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    std::string enc;
    enc.resize(static_cast<size_t>(n));
    size_t got = n ? fread(enc.data(), 1, static_cast<size_t>(n), f) : 0;
    fclose(f);
    if (got != static_cast<size_t>(n)) return RAC_ERROR_SECURE_STORAGE_FAILED;

    DATA_BLOB in{static_cast<DWORD>(enc.size()), reinterpret_cast<BYTE*>(enc.data())};
    DATA_BLOB out{0, nullptr};
    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &out)) {
        // Undecryptable (tampered, or a legacy plaintext blob) -> treat as a
        // clean miss so the caller re-persists a fresh DPAPI-protected value.
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    char* buf = static_cast<char*>(rac_alloc(static_cast<size_t>(out.cbData) + 1));
    if (!buf) {
        LocalFree(out.pbData);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::memcpy(buf, out.pbData, out.cbData);
    buf[out.cbData] = '\0';
    LocalFree(out.pbData);
    *out_value = buf;
    return RAC_SUCCESS;
}

rac_result_t win_secure_set(const char* key, const char* value, void*) {
    if (!key || !value) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::create_directories(fs::path(g_secure_dir), ec);

    DATA_BLOB in{static_cast<DWORD>(std::strlen(value)),
                 reinterpret_cast<BYTE*>(const_cast<char*>(value))};
    DATA_BLOB out{0, nullptr};
    if (!CryptProtectData(&in, L"runanywhere-electron", nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &out)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    FILE* f = fopen(secure_path(key).string().c_str(), "wb");
    if (!f) {
        LocalFree(out.pbData);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    size_t put = out.cbData ? fwrite(out.pbData, 1, out.cbData, f) : 0;
    fclose(f);
    bool ok = (put == out.cbData);
    LocalFree(out.pbData);
    return ok ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

rac_result_t win_secure_delete(const char* key, void*) {
    if (!key) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::remove(secure_path(key), ec);
    return RAC_SUCCESS;  // a clean miss is success
}

void win_log(rac_log_level_t level, const char* category, const char* message, void*) {
    fprintf(stderr, "[%s] %s: %s\n", level_name(level), category ? category : "",
            message ? message : "");
}

int64_t win_now_ms(void*) {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

rac_result_t win_get_memory_info(rac_memory_info_t* out, void*) {
    if (!out) return RAC_ERROR_INVALID_ARGUMENT;
    MEMORYSTATUSEX ms;
    ms.dwLength = sizeof(ms);
    if (!GlobalMemoryStatusEx(&ms)) return RAC_ERROR_INTERNAL;
    out->total_bytes = ms.ullTotalPhys;
    out->available_bytes = ms.ullAvailPhys;
    out->used_bytes = ms.ullTotalPhys - ms.ullAvailPhys;
    return RAC_SUCCESS;
}

rac_result_t win_list_dir(const char* dir_path, rac_directory_entry_t* out_entries,
                          size_t* in_out_count, void*) {
    if (!dir_path || !in_out_count) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::path dir(dir_path);
    if (!fs::is_directory(dir, ec) || ec) return RAC_ERROR_FILE_NOT_FOUND;
    const size_t cap = out_entries ? *in_out_count : 0;
    size_t written = 0, total = 0;
    for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        ++total;
        if (!out_entries || written >= cap) continue;
        std::string name = it->path().filename().string();
        if (name.size() + 1 > RAC_DIRECTORY_ENTRY_NAME_MAX) continue;  // skip oversized
        std::strncpy(out_entries[written].name, name.c_str(), RAC_DIRECTORY_ENTRY_NAME_MAX - 1);
        out_entries[written].name[RAC_DIRECTORY_ENTRY_NAME_MAX - 1] = '\0';
        std::error_code ec2;
        bool is_dir = fs::is_directory(it->path(), ec2);
        out_entries[written].is_dir = is_dir ? RAC_TRUE : RAC_FALSE;
        out_entries[written].size_bytes =
            is_dir ? 0 : static_cast<int64_t>(fs::file_size(it->path(), ec2));
        ++written;
    }
    *in_out_count = out_entries ? written : total;
    return RAC_SUCCESS;
}

rac_bool_t win_is_non_empty_dir(const char* path, void*) {
    if (!path) return RAC_FALSE;
    std::error_code ec;
    fs::path p(path);
    if (!fs::is_directory(p, ec) || ec) return RAC_FALSE;
    fs::directory_iterator it(p, ec), end;
    return (!ec && it != end) ? RAC_TRUE : RAC_FALSE;
}

}  // namespace

void rac_electron_fill_win32_adapter(rac_platform_adapter_t* out, const char* secure_dir) {
    if (!out) return;
    g_secure_dir = secure_dir ? secure_dir : ".";
    std::memset(out, 0, sizeof(*out));
    out->abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    out->struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t));
    out->file_exists = win_file_exists;
    out->file_read = win_file_read;
    out->file_write = win_file_write;
    out->file_delete = win_file_delete;
    out->secure_get = win_secure_get;
    out->secure_set = win_secure_set;
    out->secure_delete = win_secure_delete;
    out->log = win_log;
    out->now_ms = win_now_ms;
    out->get_memory_info = win_get_memory_info;
    out->file_list_directory = win_list_dir;
    out->is_non_empty_directory = win_is_non_empty_dir;
    // http_download / http_download_cancel / extract_archive / get_vendor_id: NULL (M0).
    out->user_data = nullptr;
}
