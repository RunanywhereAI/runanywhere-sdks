/**
 * @file desktop_adapter.cpp
 * @brief Desktop (macOS/Linux) rac_platform_adapter_t implementation.
 *
 * Real POSIX counterparts of the stub adapter used by the commons tests
 * (tests/test_voice_agent.cpp): file I/O via <fcntl.h>/std::filesystem,
 * directory enumeration via opendir/readdir, memory info via host_statistics64
 * (macOS) / /proc/meminfo (Linux), logging to stderr. Secure storage lives in
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

#include <dirent.h>
#include <fcntl.h>
#include <pwd.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <system_error>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <sys/sysctl.h>
#elif defined(__linux__)
#include <fstream>
#include <sys/sysinfo.h>
#endif

#include "desktop/desktop_internal.h"
#include "rac/desktop/rac_desktop.h"

namespace fs = std::filesystem;

namespace rac::desktop {

std::string home_dir() {
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
}

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

std::string default_config_dir() {
    return xdg_dir("XDG_CONFIG_HOME", "/.config");
}

std::string default_data_dir() {
    return xdg_dir("XDG_DATA_HOME", "/.local/share");
}

}  // namespace rac::desktop

namespace {

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

// File system

rac_bool_t desktop_file_exists(const char* path, void* /*user_data*/) {
    if (!path) {
        return RAC_FALSE;
    }
    // Mirrors FileManager.fileExists(atPath:) — true for files AND directories.
    struct stat st{};
    return stat(path, &st) == 0 ? RAC_TRUE : RAC_FALSE;
}

rac_result_t desktop_file_read(const char* path, void** out_data, size_t* out_size,
                               void* /*user_data*/) {
    if (!path || !out_data || !out_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_data = nullptr;
    *out_size = 0;

    FILE* f = std::fopen(path, "rb");
    if (!f) {
        return errno_to_rac(errno, RAC_ERROR_FILE_READ_FAILED);
    }

    rac_result_t result = RAC_SUCCESS;
    void* buffer = nullptr;
    long file_size = -1;
    if (std::fseek(f, 0, SEEK_END) == 0) {
        file_size = std::ftell(f);
    }
    if (file_size < 0 || std::fseek(f, 0, SEEK_SET) != 0) {
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
    fs::path parent = fs::path(path).parent_path();
    if (!parent.empty()) {
        fs::create_directories(parent, ec);  // ec ignored: fopen below surfaces failure
    }

    FILE* f = std::fopen(path, "wb");
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
    if (std::remove(path) != 0) {
        return errno_to_rac(errno, RAC_ERROR_FILE_DELETE_FAILED);
    }
    return RAC_SUCCESS;
}

// Directory enumeration

bool entry_is_hidden(const char* name) {
    return name[0] == '.';
}

rac_result_t desktop_file_list_directory(const char* dir_path, rac_directory_entry_t* out_entries,
                                         size_t* in_out_count, void* /*user_data*/) {
    if (!dir_path || !in_out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    DIR* dir = opendir(dir_path);
    if (!dir) {
        return errno_to_rac(errno, RAC_ERROR_STORAGE_ERROR);
    }

    const size_t capacity = out_entries ? *in_out_count : 0;
    size_t count = 0;
    while (dirent* entry = readdir(dir)) {
        if (entry_is_hidden(entry->d_name)) {
            continue;
        }
        const size_t name_len = std::strlen(entry->d_name);
        if (name_len + 1 > RAC_DIRECTORY_ENTRY_NAME_MAX) {
            // Truncation contract: skip oversized names, never half-copy them.
            std::fprintf(stderr, "[WARN] [PlatformAdapter] skipping oversized entry in %s\n",
                         dir_path);
            continue;
        }

        if (out_entries) {
            if (count >= capacity) {
                break;
            }
            rac_directory_entry_t& dst = out_entries[count];
            std::memcpy(dst.name, entry->d_name, name_len + 1);

            std::string full = std::string(dir_path) + "/" + entry->d_name;
            struct stat st{};
            if (stat(full.c_str(), &st) == 0) {
                dst.is_dir = S_ISDIR(st.st_mode) ? RAC_TRUE : RAC_FALSE;
                dst.size_bytes = S_ISDIR(st.st_mode) ? 0 : static_cast<int64_t>(st.st_size);
            } else {
                dst.is_dir = (entry->d_type == DT_DIR) ? RAC_TRUE : RAC_FALSE;
                dst.size_bytes = 0;
            }
        }
        ++count;
    }
    closedir(dir);

    *in_out_count = count;
    return RAC_SUCCESS;
}

rac_bool_t desktop_is_non_empty_directory(const char* path, void* /*user_data*/) {
    if (!path) {
        return RAC_FALSE;
    }
    DIR* dir = opendir(path);
    if (!dir) {
        return RAC_FALSE;
    }
    rac_bool_t non_empty = RAC_FALSE;
    while (dirent* entry = readdir(dir)) {
        if (std::strcmp(entry->d_name, ".") == 0 || std::strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        non_empty = RAC_TRUE;
        break;
    }
    closedir(dir);
    return non_empty;
}

// Logging / clock / memory

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
#else
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

}  // namespace

// PUBLIC API

extern "C" {

rac_result_t rac_desktop_adapter_init(const rac_desktop_adapter_config_t* config,
                                      rac_platform_adapter_t* out_adapter) {
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
