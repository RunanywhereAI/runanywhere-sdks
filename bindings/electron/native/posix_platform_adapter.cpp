// posix_platform_adapter.cpp — see header. Cross-platform POSIX platform adapter
// (Linux + macOS). Structured to mirror win32_platform_adapter.cpp slot-for-slot;
// the fill symbol is rac_electron_fill_posix_adapter and the secure store is a
// plaintext, owner-only file store (0600 files under a 0700 directory) instead of
// DPAPI. The whole translation unit is compiled only off-Windows.
#if !defined(_WIN32)

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <limits>
#include <string>
#include <system_error>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <sys/sysctl.h>
#elif defined(__linux__)
#include <unistd.h>  // sysconf
#endif

#include "posix_platform_adapter.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"

namespace fs = std::filesystem;

namespace {

// Set once by rac_electron_fill_posix_adapter before rac_init(); read-only after,
// so the "callbacks may run on any thread" contract holds without locking.
std::string g_secure_dir;

// Distinguish a confirmed missing/non-directory path from a permission or I/O
// failure. The boolean std::filesystem probes collapse both into false, which
// lets orphan pruning mistake an unreadable download folder for a vanished one.
bool is_confirmed_missing(const std::error_code& ec) {
    return ec == std::errc::no_such_file_or_directory || ec == std::errc::not_a_directory;
}

// Confirm that `directory` exists and is a directory. Only an affirmative
// missing/non-directory result maps to FILE_NOT_FOUND; denied or unknown
// probes stay inconclusive for callers that preserve registry state.
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

// ---------------------------------------------------------------------------
// File system operations (portable — identical bodies to win32's fs:: versions)
// ---------------------------------------------------------------------------

rac_bool_t posix_file_exists(const char* path, void*) {
    if (!path) return RAC_FALSE;
    std::error_code ec;
    return (fs::exists(fs::path(path), ec) && !ec) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t posix_file_read(const char* path, void** out_data, size_t* out_size, void*) {
    if (!path || !out_data || !out_size) return RAC_ERROR_INVALID_ARGUMENT;
    *out_data = nullptr;
    *out_size = 0;
    FILE* f = fopen(path, "rb");
    if (!f) return RAC_ERROR_FILE_NOT_FOUND;
    // Both seek results are checked, and the measured position is validated as a
    // nonnegative value representable in size_t, before any allocation or read.
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    long n = ftell(f);
    if (n < 0 || static_cast<unsigned long long>(n) >
                     static_cast<unsigned long long>(std::numeric_limits<size_t>::max())) {
        fclose(f);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    const size_t size = static_cast<size_t>(n);
    // rac_alloc(0) returns null: allocate one owned byte for an empty file so a
    // valid zero-byte read reports success (logical size stays 0), not OOM.
    void* buf = rac_alloc(size > 0 ? size : 1);
    if (!buf) {
        fclose(f);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    size_t got = fread(buf, 1, size, f);
    fclose(f);
    if (got != size) {
        rac_free(buf);
        return RAC_ERROR_FILE_READ_FAILED;
    }
    *out_data = buf;
    *out_size = size;
    return RAC_SUCCESS;
}

rac_result_t posix_file_write(const char* path, const void* data, size_t size, void*) {
    if (!path || (!data && size)) return RAC_ERROR_INVALID_ARGUMENT;
    FILE* f = fopen(path, "wb");
    if (!f) return RAC_ERROR_FILE_WRITE_FAILED;
    size_t put = size ? fwrite(data, 1, size, f) : 0;
    int close_rc = fclose(f);
    return (put == size && close_rc == 0) ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

rac_result_t posix_file_delete(const char* path, void*) {
    if (!path) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::remove(fs::path(path), ec);
    return ec ? RAC_ERROR_INTERNAL : RAC_SUCCESS;
}

// ---------------------------------------------------------------------------
// Secure storage
//
// COMPILE-TIME SEAM: this is a plaintext file store restricted to the owning
// user — values are written to per-key files with mode 0600 inside a 0700
// directory, so another local user cannot read them, but they are NOT encrypted
// at rest (unlike the Windows DPAPI adapter). On macOS the intended later upgrade
// is a real Keychain backend (SecItemAdd / SecItemCopyMatching under an
// #if defined(__APPLE__) block here); on Linux the analogue is libsecret /
// Secret Service. Until then the 0600/0700 owner-only permissions are the only
// protection, which matches how a headless service account typically runs.
// ---------------------------------------------------------------------------

fs::path secure_path(const char* key) { return fs::path(g_secure_dir) / fs::path(key); }

// The secure store is a flat key -> file namespace. Reject a key that could escape the store
// directory (a path separator, '..', or an absolute path) so secure_set/get/delete cannot
// reach an arbitrary file. Defense in depth: the JS facade validates too.
bool secure_key_ok(const char* key) {
    if (!key || !*key) return false;
    std::string k(key);
    if (k == "." || k == "..") return false;
    if (k.find('/') != std::string::npos || k.find('\\') != std::string::npos) return false;
    if (fs::path(k).is_absolute()) return false;
    return true;
}

rac_result_t posix_secure_get(const char* key, char** out_value, void*) {
    if (!key || !out_value) return RAC_ERROR_INVALID_ARGUMENT;
    if (!secure_key_ok(key)) return RAC_ERROR_INVALID_ARGUMENT;
    *out_value = nullptr;
    std::error_code ec;
    fs::path p = secure_path(key);
    if (!fs::exists(p, ec) || ec) return RAC_ERROR_FILE_NOT_FOUND;  // clean miss contract
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) return RAC_ERROR_FILE_NOT_FOUND;
    // Same seek contract as posix_file_read. The +1 NUL byte must not wrap size_t.
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    long n = ftell(f);
    if (n < 0 || static_cast<unsigned long long>(n) >=
                     static_cast<unsigned long long>(std::numeric_limits<size_t>::max())) {
        fclose(f);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    char* buf = static_cast<char*>(rac_alloc(static_cast<size_t>(n) + 1));
    if (!buf) {
        fclose(f);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    size_t got = n ? fread(buf, 1, static_cast<size_t>(n), f) : 0;
    fclose(f);
    if (got != static_cast<size_t>(n)) {
        rac_free(buf);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    buf[n] = '\0';
    *out_value = buf;
    return RAC_SUCCESS;
}

rac_result_t posix_secure_set(const char* key, const char* value, void*) {
    if (!key || !value) return RAC_ERROR_INVALID_ARGUMENT;
    if (!secure_key_ok(key)) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::create_directories(fs::path(g_secure_dir), ec);
    // Restrict the store directory to the owner (0700). Best-effort: chmod may
    // fail on a filesystem without POSIX permissions, which is not fatal.
    ::chmod(g_secure_dir.c_str(), S_IRWXU);

    // Create/truncate the per-key file with owner-only 0600 permissions up front
    // (open + O_CREAT|O_TRUNC honours the mode on creation) so the secret never
    // exists with wider permissions, even briefly.
    fs::path p = secure_path(key);
    int fd = ::open(p.c_str(), O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
    if (fd < 0) return RAC_ERROR_SECURE_STORAGE_FAILED;
    // Re-assert 0600 in case an existing file kept looser permissions.
    ::fchmod(fd, S_IRUSR | S_IWUSR);

    size_t len = std::strlen(value);
    size_t off = 0;
    bool ok = true;
    while (off < len) {
        ssize_t w = ::write(fd, value + off, len - off);
        if (w <= 0) {
            ok = false;
            break;
        }
        off += static_cast<size_t>(w);
    }
    ::close(fd);
    return ok ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

rac_result_t posix_secure_delete(const char* key, void*) {
    if (!key) return RAC_ERROR_INVALID_ARGUMENT;
    if (!secure_key_ok(key)) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::remove(secure_path(key), ec);
    return RAC_SUCCESS;  // a clean miss is success
}

// ---------------------------------------------------------------------------
// Logging + clock
// ---------------------------------------------------------------------------

void posix_log(rac_log_level_t level, const char* category, const char* message, void*) {
    fprintf(stderr, "[%s] %s: %s\n", level_name(level), category ? category : "",
            message ? message : "");
}

int64_t posix_now_ms(void*) {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

// ---------------------------------------------------------------------------
// Memory info
// ---------------------------------------------------------------------------

rac_result_t posix_get_memory_info(rac_memory_info_t* out, void*) {
    if (!out) return RAC_ERROR_INVALID_ARGUMENT;

#if defined(__APPLE__)
    // Total physical memory: sysctl HW_MEMSIZE (64-bit byte count).
    uint64_t total = 0;
    size_t total_len = sizeof(total);
    int mib[2] = {CTL_HW, HW_MEMSIZE};
    if (sysctl(mib, 2, &total, &total_len, nullptr, 0) != 0 || total == 0) {
        return RAC_ERROR_INTERNAL;
    }

    // Free memory: free + inactive VM pages from host_statistics64(HOST_VM_INFO64).
    vm_size_t page_size = 0;
    if (host_page_size(mach_host_self(), &page_size) != KERN_SUCCESS) {
        return RAC_ERROR_INTERNAL;
    }
    vm_statistics64_data_t vm_stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          reinterpret_cast<host_info64_t>(&vm_stats), &count) != KERN_SUCCESS) {
        return RAC_ERROR_INTERNAL;
    }
    // Treat free + inactive (reclaimable) pages as available, matching the
    // spirit of "available memory" used by GlobalMemoryStatusEx on Windows.
    uint64_t available = (static_cast<uint64_t>(vm_stats.free_count) +
                          static_cast<uint64_t>(vm_stats.inactive_count)) *
                         static_cast<uint64_t>(page_size);
    if (available > total) available = total;

    out->total_bytes = total;
    out->available_bytes = available;
    out->used_bytes = total - available;
    return RAC_SUCCESS;

#elif defined(__linux__)
    long page_size = sysconf(_SC_PAGE_SIZE);
    long phys_pages = sysconf(_SC_PHYS_PAGES);
    long avail_pages = sysconf(_SC_AVPHYS_PAGES);
    if (page_size <= 0 || phys_pages <= 0 || avail_pages < 0) {
        return RAC_ERROR_INTERNAL;
    }
    uint64_t total = static_cast<uint64_t>(phys_pages) * static_cast<uint64_t>(page_size);
    uint64_t available = static_cast<uint64_t>(avail_pages) * static_cast<uint64_t>(page_size);
    if (available > total) available = total;

    out->total_bytes = total;
    out->available_bytes = available;
    out->used_bytes = total - available;
    return RAC_SUCCESS;

#else
    // Unknown POSIX host: no portable physical-memory query. Report unsupported
    // so callers can degrade gracefully rather than trust zeroed figures.
    (void)out;
    return RAC_ERROR_NOT_SUPPORTED;
#endif
}

// ---------------------------------------------------------------------------
// Directory enumeration + probe (portable — same as win32's std::filesystem)
// ---------------------------------------------------------------------------

rac_result_t posix_list_dir(const char* dir_path, rac_directory_entry_t* out_entries,
                            size_t* in_out_count, void*) {
    if (!dir_path || !in_out_count) return RAC_ERROR_INVALID_ARGUMENT;
    std::error_code ec;
    fs::path dir(dir_path);
    const rac_result_t probe_rc = classify_directory_probe(dir);
    if (probe_rc != RAC_SUCCESS) return probe_rc;
    const size_t cap = out_entries ? *in_out_count : 0;
    size_t written = 0, total = 0;
    for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        ++total;
        if (!out_entries || written >= cap) continue;
        std::string name = it->path().filename().string();
        if (name.size() + 1 > RAC_DIRECTORY_ENTRY_NAME_MAX) {
            // A skipped name makes this a partial listing; callers must not
            // mistake it for a complete directory.
            RAC_LOG_WARNING("PlatformAdapter", "oversized entry in %s", dir_path);
            return RAC_ERROR_FILE_READ_FAILED;
        }
        // The type probe decides whether the walk recurses. A failed probe
        // must stay inconclusive instead of reporting a regular file.
        std::error_code type_ec;
        fs::file_status child_status = fs::status(it->path(), type_ec);
        if (is_confirmed_missing(type_ec)) {
            // A dangling symlink has a missing target but is still a
            // non-directory entry; a vanished entry stays inconclusive.
            type_ec.clear();
            child_status = fs::symlink_status(it->path(), type_ec);
        }
        if (type_ec || child_status.type() == fs::file_type::none ||
            child_status.type() == fs::file_type::unknown ||
            child_status.type() == fs::file_type::not_found) {
            return RAC_ERROR_FILE_READ_FAILED;
        }
        const bool is_dir = fs::is_directory(child_status);
        std::strncpy(out_entries[written].name, name.c_str(), RAC_DIRECTORY_ENTRY_NAME_MAX - 1);
        out_entries[written].name[RAC_DIRECTORY_ENTRY_NAME_MAX - 1] = '\0';
        out_entries[written].is_dir = is_dir ? RAC_TRUE : RAC_FALSE;
        if (is_dir) {
            out_entries[written].size_bytes = 0;
        } else {
            std::error_code size_ec;
            const auto size = fs::file_size(it->path(), size_ec);
            out_entries[written].size_bytes = size_ec ? 0 : static_cast<int64_t>(size);
        }
        ++written;
    }
    // A failed open/advance is an I/O error, not an empty or shorter listing.
    if (ec) return RAC_ERROR_FILE_READ_FAILED;
    if (out_entries && total > cap) {
        // The caller's buffer was too small: a partial fill is not a listing.
        return RAC_ERROR_FILE_READ_FAILED;
    }
    *in_out_count = out_entries ? written : total;
    return RAC_SUCCESS;
}

rac_bool_t posix_is_non_empty_dir(const char* path, void*) {
    if (!path) return RAC_FALSE;
    std::error_code ec;
    fs::path p(path);
    if (!fs::is_directory(p, ec) || ec) return RAC_FALSE;
    fs::directory_iterator it(p, ec), end;
    return (!ec && it != end) ? RAC_TRUE : RAC_FALSE;
}

}  // namespace

void rac_electron_fill_posix_adapter(rac_platform_adapter_t* out, const char* secure_dir) {
    if (!out) return;
    g_secure_dir = secure_dir ? secure_dir : ".";
    std::memset(out, 0, sizeof(*out));
    out->abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    out->struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t));
    out->file_exists = posix_file_exists;
    out->file_read = posix_file_read;
    out->file_write = posix_file_write;
    out->file_delete = posix_file_delete;
    out->secure_get = posix_secure_get;
    out->secure_set = posix_secure_set;
    out->secure_delete = posix_secure_delete;
    out->log = posix_log;
    out->now_ms = posix_now_ms;
    out->get_memory_info = posix_get_memory_info;
    out->file_list_directory = posix_list_dir;
    out->is_non_empty_directory = posix_is_non_empty_dir;
    // http_download / http_download_cancel: NULL by design (D4). Downloads go
    // through rac_desktop_http_transport_register() in addon.cpp — do not fill
    // these slots. extract_archive / get_vendor_id: also NULL.
    out->user_data = nullptr;
}

#endif  // !defined(_WIN32)
