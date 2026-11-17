/**
 * @file desktop_adapter.cpp
 * @brief Desktop (macOS/Linux/Windows) rac_platform_adapter_t implementation.
 *
 * Native counterparts of the stub adapter used by the commons tests
 * (tests/test_voice_agent.cpp): file I/O and enumeration via std::filesystem,
 * memory info via host_statistics64 (macOS), /proc/meminfo (Linux), or
 * GlobalMemoryStatusEx (Windows), logging to stderr. Secure storage lives in
 * desktop_secure_store.cpp; HTTP in http_transport_curl.cpp.
 *
 * Slots intentionally left NULL:
 *   - http_download / http_download_cancel: downloads route through the
 *     registered libcurl transport (rac_desktop_http_transport_register).
 *   - extract_archive: the download orchestrator extracts in-core via
 *     rac_extract_archive_native (libarchive is always linked into commons).
 *   - get_vendor_id: Apple-mobile concept; commons synthesizes and persists a
 *     UUID through secure storage instead.
 */

#include "../infrastructure/device/rac_device_live_state_internal.h"
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <system_error>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <pwd.h>
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <mach/mach.h>
#include <sys/sysctl.h>
#elif defined(__linux__)
#include <fstream>
#include <sys/sysinfo.h>
#endif

#include "desktop/desktop_internal.h"
#include "desktop/desktop_path_utf8.h"  // utf8_to_path / utf8_fopen / utf8_remove / filename_utf8
#include "rac/core/rac_logger.h"
#include "rac/desktop/rac_desktop.h"

namespace fs = std::filesystem;

namespace rac::desktop {

std::string home_dir() {
#if defined(_WIN32)
    for (const char* key : {"USERPROFILE", "LOCALAPPDATA"}) {
        const char* value = std::getenv(key);
        if (value && value[0] != '\0') {
            return value;
        }
    }
    return {};
#else
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        return home;
    }
    if (const passwd* pw = getpwuid(getuid())) {
        if (pw->pw_dir && pw->pw_dir[0] != '\0') {
            return pw->pw_dir;
        }
    }
    return {};
#endif
}

#if !defined(_WIN32)
static std::string xdg_dir(const char* env_name, const char* home_suffix) {
    const char* env = std::getenv(env_name);
    std::string base;
    if (env && env[0] != '\0') {
        base = env;
    } else {
        std::string home = home_dir();
        if (home.empty()) {
            return {};
        }
        base = home + home_suffix;
    }
    while (!base.empty() && base.back() == '/') {
        base.pop_back();
    }
    return base + "/runanywhere";
}
#else
static std::string windows_app_dir(const char* preferred_env) {
    const char* env = std::getenv(preferred_env);
    std::string base;
    if (env && env[0] != '\0') {
        base = env;
    } else {
        base = home_dir();
    }
    if (base.empty()) {
        return {};
    }
    while (!base.empty() && (base.back() == '/' || base.back() == '\\')) {
        base.pop_back();
    }
    return base + "/RunAnywhere";
}
#endif

std::string default_config_dir() {
#if defined(_WIN32)
    return windows_app_dir("APPDATA");
#else
    return xdg_dir("XDG_CONFIG_HOME", "/.config");
#endif
}

std::string default_data_dir() {
#if defined(_WIN32)
    return windows_app_dir("LOCALAPPDATA");
#else
    return xdg_dir("XDG_DATA_HOME", "/.local/share");
#endif
}

}  // namespace rac::desktop

namespace {

using rac::desktop::filename_utf8;
using rac::desktop::utf8_fopen;
using rac::desktop::utf8_remove;
using rac::desktop::utf8_to_path;

rac_result_t errno_to_rac(int err, rac_result_t fallback) {
    switch (err) {
        case ENOENT:
            return RAC_ERROR_FILE_NOT_FOUND;
        case EACCES:
        case EPERM:
            return RAC_ERROR_PERMISSION_DENIED;
        case ENOSPC:
            return RAC_ERROR_STORAGE_FULL;
        default:
            return fallback;
    }
}

rac_result_t filesystem_error_to_rac(const std::error_code& ec, rac_result_t fallback) {
    if (ec == std::errc::no_such_file_or_directory) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    if (ec == std::errc::permission_denied) {
        return RAC_ERROR_PERMISSION_DENIED;
    }
    if (ec == std::errc::no_space_on_device) {
        return RAC_ERROR_STORAGE_FULL;
    }
    return fallback;
}

// -----------------------------------------------------------------------------
// File system
// -----------------------------------------------------------------------------

rac_bool_t desktop_file_exists(const char* path, void* /*user_data*/) {
    if (!path) {
        return RAC_FALSE;
    }
    // Mirrors FileManager.fileExists(atPath:) — true for files AND directories.
    std::error_code ec;
    return fs::exists(utf8_to_path(path), ec) && !ec ? RAC_TRUE : RAC_FALSE;
}

rac_result_t desktop_file_read(const char* path, void** out_data, size_t* out_size,
                               void* /*user_data*/) {
    if (!path || !out_data || !out_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_data = nullptr;
    *out_size = 0;

    FILE* f = utf8_fopen(path, "rb");
    if (!f) {
        return errno_to_rac(errno, RAC_ERROR_FILE_READ_FAILED);
    }

    rac_result_t result = RAC_SUCCESS;
    void* buffer = nullptr;
#if defined(_WIN32)
    __int64 file_size = -1;
    if (_fseeki64(f, 0, SEEK_END) == 0) {
        file_size = _ftelli64(f);
    }
    if (file_size < 0 || _fseeki64(f, 0, SEEK_SET) != 0) {
#else
    long file_size = -1;
    if (std::fseek(f, 0, SEEK_END) == 0) {
        file_size = std::ftell(f);
    }
    if (file_size < 0 || std::fseek(f, 0, SEEK_SET) != 0) {
#endif
        result = RAC_ERROR_FILE_READ_FAILED;
    } else {
        // malloc so callers can release with rac_free (it wraps free()).
        buffer = std::malloc(file_size > 0 ? static_cast<size_t>(file_size) : 1);
        if (!buffer) {
            result = RAC_ERROR_OUT_OF_MEMORY;
        } else if (file_size > 0 && std::fread(buffer, 1, static_cast<size_t>(file_size), f) !=
                                        static_cast<size_t>(file_size)) {
            result = RAC_ERROR_FILE_READ_FAILED;
        }
    }
    std::fclose(f);

    if (result != RAC_SUCCESS) {
        std::free(buffer);
        return result;
    }
    *out_data = buffer;
    *out_size = static_cast<size_t>(file_size);
    return RAC_SUCCESS;
}

rac_result_t desktop_file_write(const char* path, const void* data, size_t size,
                                void* /*user_data*/) {
    if (!path || (!data && size > 0)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::error_code ec;
    fs::path parent = utf8_to_path(path).parent_path();
    if (!parent.empty()) {
        fs::create_directories(parent, ec);  // ec ignored: fopen below surfaces failure
    }

    FILE* f = utf8_fopen(path, "wb");
    if (!f) {
        return errno_to_rac(errno, RAC_ERROR_FILE_WRITE_FAILED);
    }
    size_t written = (size > 0) ? std::fwrite(data, 1, size, f) : 0;
    int close_rc = std::fclose(f);
    if (written != size || close_rc != 0) {
        return RAC_ERROR_FILE_WRITE_FAILED;
    }
    return RAC_SUCCESS;
}

rac_result_t desktop_file_delete(const char* path, void* /*user_data*/) {
    if (!path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (utf8_remove(path) != 0) {
        return errno_to_rac(errno, RAC_ERROR_FILE_DELETE_FAILED);
    }
    return RAC_SUCCESS;
}

// -----------------------------------------------------------------------------
// Directory enumeration
// -----------------------------------------------------------------------------

// Confirm that `directory` exists and is a directory. Only an affirmative
// missing/non-directory result maps to FILE_NOT_FOUND; denied or unknown
// probes stay inconclusive for callers that preserve registry state.
bool is_confirmed_missing(const std::error_code& ec) {
    return ec == std::errc::no_such_file_or_directory || ec == std::errc::not_a_directory;
}

rac_result_t classify_directory_probe(const fs::path& directory) {
    std::error_code ec;
    const fs::file_status status = fs::status(directory, ec);
    if (is_confirmed_missing(ec)) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }
    if (ec) {
        return RAC_ERROR_FILE_READ_FAILED;
    }
    switch (status.type()) {
        case fs::file_type::not_found:
            return RAC_ERROR_FILE_NOT_FOUND;
        case fs::file_type::none:
        case fs::file_type::unknown:
            return RAC_ERROR_FILE_READ_FAILED;
        default:
            return fs::is_directory(status) ? RAC_SUCCESS : RAC_ERROR_FILE_NOT_FOUND;
    }
}

rac_result_t desktop_file_list_directory(const char* dir_path, rac_directory_entry_t* out_entries,
                                         size_t* in_out_count, void* /*user_data*/) {
    if (!dir_path || !in_out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const fs::path dir = utf8_to_path(dir_path);
    const rac_result_t probe_rc = classify_directory_probe(dir);
    if (probe_rc != RAC_SUCCESS) {
        return probe_rc;
    }

    const size_t capacity = out_entries ? *in_out_count : 0;
    size_t total = 0;
    std::error_code ec;
    fs::directory_iterator iterator(dir, ec);
    if (ec) {
        return RAC_ERROR_FILE_READ_FAILED;
    }
    const fs::directory_iterator end;
    for (; iterator != end; iterator.increment(ec)) {
        // A failed increment can advance the iterator to `end`, ending the loop
        // before this guard runs on the next pass — so the final increment is
        // re-checked after the loop below.
        if (ec) {
            return RAC_ERROR_FILE_READ_FAILED;
        }
        const fs::directory_entry& entry = *iterator;
        const std::string name = filename_utf8(entry.path());
        const size_t name_len = name.size();
        if (name_len + 1 > RAC_DIRECTORY_ENTRY_NAME_MAX) {
            // A skipped name makes this a partial listing; callers must not
            // mistake it for a complete directory.
            RAC_LOG_WARNING("PlatformAdapter", "oversized entry in %s", dir_path);
            return RAC_ERROR_FILE_READ_FAILED;
        }

        if (out_entries && total < capacity) {
            rac_directory_entry_t& dst = out_entries[total];
            std::memcpy(dst.name, name.c_str(), name_len + 1);

            std::error_code type_ec;
            fs::file_status child_status = fs::status(entry.path(), type_ec);
            if (is_confirmed_missing(type_ec)) {
                // A dangling symlink has a missing target but is still a
                // non-directory entry; a vanished entry stays inconclusive.
                type_ec.clear();
                child_status = fs::symlink_status(entry.path(), type_ec);
            }
            if (type_ec || child_status.type() == fs::file_type::none ||
                child_status.type() == fs::file_type::unknown ||
                child_status.type() == fs::file_type::not_found) {
                return RAC_ERROR_FILE_READ_FAILED;
            }
            const bool is_dir = fs::is_directory(child_status);
            dst.is_dir = is_dir ? RAC_TRUE : RAC_FALSE;
            if (is_dir) {
                dst.size_bytes = 0;
            } else {
                std::error_code size_ec;
                const auto size = fs::file_size(entry.path(), size_ec);
                dst.size_bytes = size_ec ? 0 : static_cast<int64_t>(size);
            }
        }
        ++total;
    }
    // Catch a failure from the increment that advanced the iterator to `end`.
    if (ec) {
        return RAC_ERROR_FILE_READ_FAILED;
    }
    if (out_entries && total > capacity) {
        // The caller's buffer was too small: a partial fill is not a listing.
        return RAC_ERROR_FILE_READ_FAILED;
    }

    *in_out_count = total;
    return RAC_SUCCESS;
}

rac_bool_t desktop_is_non_empty_directory(const char* path, void* /*user_data*/) {
    if (!path) {
        return RAC_FALSE;
    }
    std::error_code ec;
    fs::directory_iterator iterator(utf8_to_path(path), ec);
    return !ec && iterator != fs::directory_iterator{} ? RAC_TRUE : RAC_FALSE;
}

// -----------------------------------------------------------------------------
// Logging / clock / memory
// -----------------------------------------------------------------------------

const char* level_tag(rac_log_level_t level) {
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
            return "?";
    }
}

void desktop_log(rac_log_level_t level, const char* category, const char* message,
                 void* /*user_data*/) {
    std::fprintf(stderr, "[%s] [%s] %s\n", level_tag(level), category ? category : "?",
                 message ? message : "");
}

int64_t desktop_now_ms(void* /*user_data*/) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

rac_result_t desktop_get_memory_info(rac_memory_info_t* out_info, void* /*user_data*/) {
    if (!out_info) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#if defined(__APPLE__)
    uint64_t total = 0;
    size_t size = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &size, nullptr, 0) != 0) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    vm_statistics64_data_t vm_stats{};
    mach_msg_type_number_t info_count = HOST_VM_INFO64_COUNT;
    uint64_t available = 0;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          reinterpret_cast<host_info64_t>(&vm_stats),
                          &info_count) == KERN_SUCCESS) {
        vm_size_t page_size = 0;
        host_page_size(mach_host_self(), &page_size);
        available = (static_cast<uint64_t>(vm_stats.free_count) +
                     static_cast<uint64_t>(vm_stats.inactive_count)) *
                    static_cast<uint64_t>(page_size);
    }

    out_info->total_bytes = total;
    out_info->available_bytes = available;
    out_info->used_bytes = (total > available) ? (total - available) : 0;
    return RAC_SUCCESS;
#elif defined(__linux__)
    uint64_t total_kb = 0;
    uint64_t available_kb = 0;
    std::ifstream meminfo("/proc/meminfo");
    std::string key;
    uint64_t value = 0;
    std::string unit;
    while (meminfo >> key >> value >> unit) {
        if (key == "MemTotal:") {
            total_kb = value;
        } else if (key == "MemAvailable:") {
            available_kb = value;
        }
        if (total_kb && available_kb) {
            break;
        }
    }
    if (total_kb == 0) {
        struct sysinfo info{};
        if (sysinfo(&info) != 0) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        total_kb = (static_cast<uint64_t>(info.totalram) * info.mem_unit) / 1024;
        available_kb = (static_cast<uint64_t>(info.freeram) * info.mem_unit) / 1024;
    }

    out_info->total_bytes = total_kb * 1024;
    out_info->available_bytes = available_kb * 1024;
    out_info->used_bytes = (out_info->total_bytes > out_info->available_bytes)
                               ? (out_info->total_bytes - out_info->available_bytes)
                               : 0;
    return RAC_SUCCESS;
#elif defined(_WIN32)
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    out_info->total_bytes = status.ullTotalPhys;
    out_info->available_bytes = status.ullAvailPhys;
    out_info->used_bytes = status.ullTotalPhys - status.ullAvailPhys;
    return RAC_SUCCESS;
#else
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_result_t rac_desktop_adapter_init(const rac_desktop_adapter_config_t* config,
                                      rac_platform_adapter_t* out_adapter) {
    // Desktop callbacks are plain C — live telemetry sampling is thread-safe.
    rac_telemetry_enable_live_platform_sampling();

    if (!out_adapter) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string store_dir;
    if (config && config->secure_store_dir && config->secure_store_dir[0] != '\0') {
        store_dir = config->secure_store_dir;
    } else {
        store_dir = rac::desktop::default_config_dir();
    }
    if (store_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;  // $HOME unresolvable
    }
    rac::desktop::secure_store_set_dir(store_dir);

    rac_platform_adapter_t adapter = {};
    adapter.abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    adapter.struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t));
    adapter.file_exists = desktop_file_exists;
    adapter.file_read = desktop_file_read;
    adapter.file_write = desktop_file_write;
    adapter.file_delete = desktop_file_delete;
    adapter.secure_get = rac::desktop::secure_get;
    adapter.secure_set = rac::desktop::secure_set;
    adapter.secure_delete = rac::desktop::secure_delete;
    adapter.log = desktop_log;
    adapter.now_ms = desktop_now_ms;
    adapter.get_memory_info = desktop_get_memory_info;
    adapter.file_list_directory = desktop_file_list_directory;
    adapter.is_non_empty_directory = desktop_is_non_empty_directory;

    *out_adapter = adapter;
    return RAC_SUCCESS;
}

rac_result_t rac_desktop_default_base_dir(char* out_path, size_t path_size) {
    if (!out_path || path_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::string dir = rac::desktop::default_data_dir();
    if (dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    if (dir.size() >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    std::memcpy(out_path, dir.c_str(), dir.size() + 1);
    return RAC_SUCCESS;
}

}  // extern "C"
