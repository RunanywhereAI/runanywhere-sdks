/**
 * @file test_desktop_adapter.cpp
 * @brief Unit tests for the desktop platform adapter (RAC_DESKTOP_ADAPTER).
 *
 * Exercises the desktop adapter slots directly (no rac_init needed), secure
 * secure-store contract, the libcurl transport registration, and the
 * model-paths base-dir dedup rule the desktop layout depends on. Network
 * behavior is covered by the Docker CLI e2e (hermetic local-HTTP pull), not
 * here.
 */

#include "test_common.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <set>
#include <string>
#include <vector>

#if !defined(_WIN32)
#include <sys/stat.h>
#endif

#include "rac/core/rac_platform_adapter.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace fs = std::filesystem;

namespace {

// RAII temp directory under the system temp root.
struct TempDir {
    std::string path;

    TempDir() {
        const auto unique = std::chrono::steady_clock::now().time_since_epoch().count();
        // u8string() (not string(), which uses the Windows ANSI code page) so the
        // path handed to the UTF-8 adapter API round-trips on non-ASCII temp roots.
        const auto u8 =
            (fs::temp_directory_path() / ("rac_desktop_test_" + std::to_string(unique))).u8string();
        path = std::string(reinterpret_cast<const char*>(u8.data()), u8.size());
        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec) {
            path.clear();
        }
    }

    ~TempDir() {
        if (!path.empty()) {
            std::error_code ec;
            fs::remove_all(path, ec);
        }
    }
};

bool make_adapter(const std::string& store_dir, rac_platform_adapter_t* out) {
    rac_desktop_adapter_config_t config{};
    config.secure_store_dir = store_dir.empty() ? nullptr : store_dir.c_str();
    return rac_desktop_adapter_init(&config, out) == RAC_SUCCESS;
}

TestResult test_file_roundtrip() {
    TestResult result;
    result.test_name = "file_roundtrip";

    TempDir tmp;
    rac_platform_adapter_t adapter{};
    if (tmp.path.empty() || !make_adapter(tmp.path, &adapter)) {
        result.details = "setup failed";
        return result;
    }

    // Nested path: file_write must create missing parent directories.
    const std::string file_path = tmp.path + "/nested/dir/data.bin";
    const std::string payload = "runanywhere-desktop\x01\x02";

    if (adapter.file_exists(file_path.c_str(), nullptr) != RAC_FALSE) {
        result.details = "file_exists true before write";
        return result;
    }
    if (adapter.file_write(file_path.c_str(), payload.data(), payload.size(), nullptr) !=
        RAC_SUCCESS) {
        result.details = "file_write failed";
        return result;
    }
    if (adapter.file_exists(file_path.c_str(), nullptr) != RAC_TRUE) {
        result.details = "file_exists false after write";
        return result;
    }

    void* data = nullptr;
    size_t size = 0;
    if (adapter.file_read(file_path.c_str(), &data, &size, nullptr) != RAC_SUCCESS) {
        result.details = "file_read failed";
        return result;
    }
    const bool content_ok = size == payload.size() && std::memcmp(data, payload.data(), size) == 0;
    free(data);
    if (!content_ok) {
        result.details = "file_read returned different bytes";
        return result;
    }

    if (adapter.file_delete(file_path.c_str(), nullptr) != RAC_SUCCESS ||
        adapter.file_exists(file_path.c_str(), nullptr) != RAC_FALSE) {
        result.details = "file_delete did not remove the file";
        return result;
    }
    if (adapter.file_read(file_path.c_str(), &data, &size, nullptr) != RAC_ERROR_FILE_NOT_FOUND) {
        result.details = "file_read on missing file should be RAC_ERROR_FILE_NOT_FOUND";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_list_directory() {
    TestResult result;
    result.test_name = "list_directory";

    TempDir tmp;
    rac_platform_adapter_t adapter{};
    if (tmp.path.empty() || !make_adapter(tmp.path, &adapter)) {
        result.details = "setup failed";
        return result;
    }

    const std::string dir = tmp.path + "/models";
    fs::create_directories(dir + "/sub");
    const std::string content = "0123456789";
    adapter.file_write((dir + "/a.gguf").c_str(), content.data(), content.size(), nullptr);
    adapter.file_write((dir + "/b.onnx").c_str(), content.data(), content.size(), nullptr);
    adapter.file_write((dir + "/.hidden").c_str(), content.data(), content.size(), nullptr);

    // Capacity query (NULL entries).
    size_t count = 0;
    if (adapter.file_list_directory(dir.c_str(), nullptr, &count, nullptr) != RAC_SUCCESS) {
        result.details = "capacity query failed";
        return result;
    }
    if (count != 3) {  // a.gguf, b.onnx, sub — dotfiles filtered
        result.details = "capacity query expected 3 entries, got " + std::to_string(count);
        return result;
    }

    std::vector<rac_directory_entry_t> entries(count);
    if (adapter.file_list_directory(dir.c_str(), entries.data(), &count, nullptr) != RAC_SUCCESS ||
        count != 3) {
        result.details = "fill call failed";
        return result;
    }

    std::set<std::string> names;
    for (size_t i = 0; i < count; ++i) {
        names.insert(entries[i].name);
        const bool is_sub = std::strcmp(entries[i].name, "sub") == 0;
        if (is_sub && entries[i].is_dir != RAC_TRUE) {
            result.details = "subdirectory not flagged is_dir";
            return result;
        }
        if (!is_sub && entries[i].size_bytes != static_cast<int64_t>(content.size())) {
            result.details = "file size mismatch for " + std::string(entries[i].name);
            return result;
        }
    }
    if (names != std::set<std::string>{"a.gguf", "b.onnx", "sub"}) {
        result.details = "unexpected entry names";
        return result;
    }

    size_t missing_count = 0;
    if (adapter.file_list_directory((tmp.path + "/absent").c_str(), nullptr, &missing_count,
                                    nullptr) != RAC_ERROR_FILE_NOT_FOUND) {
        result.details = "missing dir should be RAC_ERROR_FILE_NOT_FOUND";
        return result;
    }

    if (adapter.is_non_empty_directory(dir.c_str(), nullptr) != RAC_TRUE) {
        result.details = "is_non_empty_directory false for populated dir";
        return result;
    }
    const std::string empty_dir = tmp.path + "/empty";
    fs::create_directories(empty_dir);
    if (adapter.is_non_empty_directory(empty_dir.c_str(), nullptr) != RAC_FALSE) {
        result.details = "is_non_empty_directory true for empty dir";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_secure_store() {
    TestResult result;
    result.test_name = "secure_store";

    TempDir tmp;
    rac_platform_adapter_t adapter{};
    if (tmp.path.empty() || !make_adapter(tmp.path + "/cfg", &adapter)) {
        result.details = "setup failed";
        return result;
    }

    char* value = nullptr;
    if (adapter.secure_get("rac.device.id", &value, nullptr) != RAC_ERROR_FILE_NOT_FOUND) {
        result.details = "miss must be RAC_ERROR_FILE_NOT_FOUND";
        return result;
    }

    if (adapter.secure_set("rac.device.id", "device-1234", nullptr) != RAC_SUCCESS) {
        result.details = "secure_set failed";
        return result;
    }
    if (adapter.secure_get("rac.device.id", &value, nullptr) != RAC_SUCCESS || value == nullptr) {
        result.details = "secure_get failed after set";
        return result;
    }
    const bool value_ok = std::strcmp(value, "device-1234") == 0;
    free(value);
    if (!value_ok) {
        result.details = "secure_get returned wrong value";
        return result;
    }

    // Permission contract: POSIX uses 0600/0700. Windows stores a DPAPI blob.
    const std::string key_file = tmp.path + "/cfg/secure/rac.device.id";
#if defined(_WIN32)
    // Construct the path from UTF-8 so MSVC's <fstream> does not reinterpret it
    // through the ANSI code page. Scope the stream so the handle is released
    // before secure_delete below — Windows cannot unlink a file that is open.
    std::string stored;
    {
        std::ifstream encrypted(fs::path(reinterpret_cast<const char8_t*>(key_file.c_str())),
                                std::ios::binary);
        stored.assign((std::istreambuf_iterator<char>(encrypted)),
                      std::istreambuf_iterator<char>());
    }
    if (stored.empty() || stored.find("device-1234") != std::string::npos) {
        result.details = "Windows secure-store value was not DPAPI protected";
        return result;
    }
#else
    struct stat st{};
    if (stat(key_file.c_str(), &st) != 0) {
        result.details = "expected key file at " + key_file;
        return result;
    }
    if ((st.st_mode & 0777) != 0600) {
        result.details = "key file mode is not 0600";
        return result;
    }
    struct stat dir_st{};
    if (stat((tmp.path + "/cfg/secure").c_str(), &dir_st) != 0 || (dir_st.st_mode & 0777) != 0700) {
        result.details = "secure dir mode is not 0700";
        return result;
    }
#endif

    // Keys with separators must be encoded, not treated as paths.
    if (adapter.secure_set("a/b:c", "x", nullptr) != RAC_SUCCESS) {
        result.details = "secure_set with unsafe key failed";
        return result;
    }
    if (adapter.secure_get("a/b:c", &value, nullptr) != RAC_SUCCESS) {
        result.details = "secure_get with unsafe key failed";
        return result;
    }
    free(value);

    if (adapter.secure_delete("rac.device.id", nullptr) != RAC_SUCCESS) {
        result.details = "secure_delete failed";
        return result;
    }
    if (adapter.secure_get("rac.device.id", &value, nullptr) != RAC_ERROR_FILE_NOT_FOUND) {
        result.details = "secure_get after delete should miss";
        return result;
    }
    if (adapter.secure_delete("never-existed", nullptr) != RAC_SUCCESS) {
        result.details = "deleting an absent key should be a no-op success";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_memory_info_and_clock() {
    TestResult result;
    result.test_name = "memory_info_and_clock";

    TempDir tmp;
    rac_platform_adapter_t adapter{};
    if (tmp.path.empty() || !make_adapter(tmp.path, &adapter)) {
        result.details = "setup failed";
        return result;
    }

    rac_memory_info_t info{};
    if (adapter.get_memory_info(&info, nullptr) != RAC_SUCCESS) {
        result.details = "get_memory_info failed";
        return result;
    }
    if (info.total_bytes == 0 || info.available_bytes > info.total_bytes) {
        result.details = "implausible memory numbers";
        return result;
    }

    const int64_t t0 = adapter.now_ms(nullptr);
    if (t0 < 1577836800000LL) {  // 2020-01-01 — sanity floor for epoch ms
        result.details = "now_ms not epoch milliseconds";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_http_transport_registration() {
    TestResult result;
    result.test_name = "http_transport_registration";

    if (rac_desktop_http_transport_register() != RAC_SUCCESS) {
        result.details = "rac_desktop_http_transport_register failed";
        return result;
    }
    if (rac_http_transport_is_registered() != RAC_TRUE) {
        result.details = "transport not reported as registered";
        return result;
    }
    // Unregister so later suites observe a clean process state.
    rac_http_transport_register(nullptr, nullptr);
    if (rac_http_transport_is_registered() != RAC_FALSE) {
        result.details = "transport still registered after unregister";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_model_paths_desktop_dedup() {
    TestResult result;
    result.test_name = "model_paths_desktop_dedup";

    TempDir tmp;
    if (tmp.path.empty()) {
        result.details = "setup failed";
        return result;
    }

    char buffer[1024] = {};

    // Desktop convention: base dir already named "runanywhere" → no extra
    // RunAnywhere segment, matching the test rig / playground layout.
    const std::string desktop_base = tmp.path + "/runanywhere";
    if (rac_model_paths_set_base_dir(desktop_base.c_str()) != RAC_SUCCESS ||
        rac_model_paths_get_models_directory(buffer, sizeof(buffer)) != RAC_SUCCESS) {
        result.details = "set_base_dir/get_models_directory failed";
        return result;
    }
    if (std::string(buffer) != desktop_base + "/Models") {
        result.details = "expected dedup: got " + std::string(buffer);
        return result;
    }

    // Mobile convention unchanged: arbitrary sandbox root gets /RunAnywhere.
    const std::string mobile_base = tmp.path + "/Documents";
    if (rac_model_paths_set_base_dir(mobile_base.c_str()) != RAC_SUCCESS ||
        rac_model_paths_get_models_directory(buffer, sizeof(buffer)) != RAC_SUCCESS) {
        result.details = "set_base_dir/get_models_directory failed (mobile)";
        return result;
    }
    if (std::string(buffer) != mobile_base + "/RunAnywhere/Models") {
        result.details = "mobile layout changed: got " + std::string(buffer);
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_default_base_dir() {
    TestResult result;
    result.test_name = "default_base_dir";

    char buffer[1024] = {};
    if (rac_desktop_default_base_dir(buffer, sizeof(buffer)) != RAC_SUCCESS) {
        result.details = "rac_desktop_default_base_dir failed";
        return result;
    }
    const std::string dir(buffer);
#if defined(_WIN32)
    // Windows: <LOCALAPPDATA>\RunAnywhere — drive-letter rooted, "RunAnywhere".
    const bool rooted = dir.size() >= 2 && dir[1] == ':';
    if (dir.empty() || dir.find("RunAnywhere") == std::string::npos || !rooted) {
        result.details = "unexpected default base dir: " + dir;
        return result;
    }
#else
    if (dir.empty() || dir.find("runanywhere") == std::string::npos || dir.front() != '/') {
        result.details = "unexpected default base dir: " + dir;
        return result;
    }
#endif

    char tiny[4] = {};
    if (rac_desktop_default_base_dir(tiny, sizeof(tiny)) != RAC_ERROR_BUFFER_TOO_SMALL) {
        result.details = "tiny buffer should be RAC_ERROR_BUFFER_TOO_SMALL";
        return result;
    }

    result.passed = true;
    return result;
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("desktop_adapter");
    suite.add("file_roundtrip", test_file_roundtrip);
    suite.add("list_directory", test_list_directory);
    suite.add("secure_store", test_secure_store);
    suite.add("memory_info_and_clock", test_memory_info_and_clock);
    suite.add("http_transport_registration", test_http_transport_registration);
    suite.add("model_paths_desktop_dedup", test_model_paths_desktop_dedup);
    suite.add("default_base_dir", test_default_base_dir);
    return suite.run(argc, argv);
}
