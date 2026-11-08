// Hermetic checks for posix_file_read / posix_secure_get seek and empty-file
// behavior. Standalone: links the adapter and rac_alloc only, not the addon.

#include "posix_platform_adapter.h"

#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"

namespace fs = std::filesystem;

// posix_list_dir references the logger. These tests never call it.
extern "C" rac_log_level_t rac_logger_get_min_level(void) { return RAC_LOG_ERROR; }

extern "C" void rac_logger_logf(rac_log_level_t, const char*, const rac_log_metadata_t*,
                                const char*, ...) {}

namespace {

int g_failed = 0;
int g_passed = 0;

void check(bool ok, const char* name, const std::string& detail) {
    if (ok) {
        ++g_passed;
        std::cout << "PASS " << name << "\n";
        return;
    }
    ++g_failed;
    std::cout << "FAIL " << name << " " << detail << "\n";
}

std::string rc_text(rac_result_t rc) { return "rc=" + std::to_string(rc); }

struct TempDir {
    fs::path path;
    explicit TempDir(const std::string& tag) {
        const auto unique = std::chrono::steady_clock::now().time_since_epoch().count();
        path = fs::temp_directory_path() / (tag + "-" + std::to_string(unique));
        fs::create_directories(path);
    }
    ~TempDir() {
        std::error_code ec;
        fs::remove_all(path, ec);
    }
};

// Holds the write end of a FIFO open so fopen() on the read end can proceed.
// A FIFO is not seekable: fseek returns ESPIPE.
struct Fifo {
    fs::path path;
    int write_fd = -1;
    std::thread opener;

    explicit Fifo(const fs::path& p) : path(p) {
        ::unlink(path.c_str());
        if (::mkfifo(path.c_str(), 0600) != 0) {
            path.clear();
            return;
        }
        opener = std::thread([this] { write_fd = ::open(path.c_str(), O_WRONLY); });
    }

    ~Fifo() {
        if (!path.empty() && opener.joinable()) {
            // Unblock open() if the reader never arrived.
            int rd = ::open(path.c_str(), O_RDONLY | O_NONBLOCK);
            opener.join();
            if (rd >= 0) ::close(rd);
        } else if (opener.joinable()) {
            opener.join();
        }
        if (write_fd >= 0) ::close(write_fd);
        if (!path.empty()) ::unlink(path.c_str());
    }

    bool ok() const { return !path.empty(); }
};

void test_empty_file(rac_platform_adapter_t* adapter, const fs::path& dir) {
    const fs::path file = dir / "empty.bin";
    { std::ofstream out(file, std::ios::binary); }
    void* data = nullptr;
    size_t size = 99;
    const rac_result_t rc = adapter->file_read(file.c_str(), &data, &size, nullptr);
    const bool pass = rc == RAC_SUCCESS && size == 0 && data != nullptr;
    check(pass, "empty-file", rc_text(rc) + " size=" + std::to_string(size) +
                                  " data=" + (data ? "non-null" : "null"));
    rac_free(data);
}

void test_payload(rac_platform_adapter_t* adapter, const fs::path& dir) {
    const fs::path file = dir / "payload.bin";
    const std::string payload = "abc";
    {
        std::ofstream out(file, std::ios::binary);
        out << payload;
    }
    void* data = nullptr;
    size_t size = 0;
    const rac_result_t rc = adapter->file_read(file.c_str(), &data, &size, nullptr);
    const bool bytes_ok = data != nullptr && size == payload.size() &&
                          std::memcmp(data, payload.data(), payload.size()) == 0;
    check(rc == RAC_SUCCESS && bytes_ok, "payload", rc_text(rc) + " size=" + std::to_string(size));
    rac_free(data);
}

void test_missing(rac_platform_adapter_t* adapter, const fs::path& dir) {
    void* data = reinterpret_cast<void*>(1);
    size_t size = 7;
    const rac_result_t rc =
        adapter->file_read((dir / "no-such.bin").c_str(), &data, &size, nullptr);
    check(rc == RAC_ERROR_FILE_NOT_FOUND && data == nullptr && size == 0, "missing",
          rc_text(rc));
    rac_free(data);
}

void test_fifo_read(rac_platform_adapter_t* adapter, const fs::path& dir) {
    Fifo fifo(dir / "noseek.fifo");
    if (!fifo.ok()) {
        check(false, "fifo-read", "mkfifo failed");
        return;
    }
    void* data = nullptr;
    size_t size = 1;
    const rac_result_t rc = adapter->file_read(fifo.path.c_str(), &data, &size, nullptr);
    check(rc == RAC_ERROR_FILE_READ_FAILED && data == nullptr && size == 0, "fifo-read",
          rc_text(rc) + " size=" + std::to_string(size));
    rac_free(data);
}

void test_empty_secure(rac_platform_adapter_t* adapter) {
    const rac_result_t set_rc = adapter->secure_set("empty-key", "", nullptr);
    char* value = nullptr;
    const rac_result_t get_rc = adapter->secure_get("empty-key", &value, nullptr);
    const bool empty = value != nullptr && value[0] == '\0';
    check(set_rc == RAC_SUCCESS && get_rc == RAC_SUCCESS && empty, "empty-secure",
          "set=" + rc_text(set_rc) + " get=" + rc_text(get_rc));
    rac_free(value);
}

void test_fifo_secure(rac_platform_adapter_t* adapter, const fs::path& dir) {
    Fifo fifo(dir / "seek-key");
    if (!fifo.ok()) {
        check(false, "fifo-secure", "mkfifo failed");
        return;
    }
    char* value = reinterpret_cast<char*>(1);
    const rac_result_t rc = adapter->secure_get("seek-key", &value, nullptr);
    check(rc == RAC_ERROR_SECURE_STORAGE_FAILED && value == nullptr, "fifo-secure", rc_text(rc));
    rac_free(value);
}

}  // namespace

int main() {
    TempDir tmp("rac-posix-read");
    rac_platform_adapter_t adapter{};
    rac_electron_fill_posix_adapter(&adapter, (tmp.path / "secure").c_str());
    if (!adapter.file_read || !adapter.secure_get || !adapter.secure_set) {
        std::cerr << "adapter slots missing\n";
        return 2;
    }

    test_empty_file(&adapter, tmp.path);
    test_payload(&adapter, tmp.path);
    test_missing(&adapter, tmp.path);
    test_fifo_read(&adapter, tmp.path);
    test_empty_secure(&adapter);
    test_fifo_secure(&adapter, tmp.path / "secure");

    std::cout << "passed=" << g_passed << " failed=" << g_failed << "\n";
    return g_failed == 0 ? 0 : 1;
}
