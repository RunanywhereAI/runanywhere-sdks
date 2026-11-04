/**
 * @file test_jni_directory_probe.cpp
 * @brief Real filesystem coverage for rac_classify_null_directory_listing.
 */

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>

#include "rac/infrastructure/file_management/rac_directory_probe.h"

namespace {

namespace fs = std::filesystem;

#define EXPECT_EQ(actual, expected)                                                          \
    do {                                                                                     \
        if ((actual) != (expected)) {                                                        \
            std::fprintf(stderr, "EXPECT FAILED: %s == %s at line %d\n", #actual, #expected, \
                         __LINE__);                                                          \
            return 1;                                                                        \
        }                                                                                    \
    } while (0)

struct DirectoryFixture {
    fs::path root = fs::temp_directory_path() /
                    ("rac-jni-probe-" +
                     std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::path blocked = root / "blocked";
    fs::path model = blocked / "model";
    fs::perms original_permissions;

    DirectoryFixture() {
        fs::create_directories(model);
        original_permissions = fs::status(blocked).permissions();
    }

    ~DirectoryFixture() {
        std::error_code ignored;
        fs::permissions(blocked, original_permissions, ignored);
        fs::remove_all(root, ignored);
    }
};

}  // namespace

int main() {
    DirectoryFixture fixture;
    const auto missing = fixture.root / "missing";
    const auto file = fixture.root / "weights.gguf";
    std::ofstream(file) << "weights";
    EXPECT_EQ(fs::is_regular_file(file), true);

    EXPECT_EQ(rac_classify_null_directory_listing(nullptr), RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(rac_classify_null_directory_listing(missing.string().c_str()),
              RAC_ERROR_FILE_NOT_FOUND);
    EXPECT_EQ(rac_classify_null_directory_listing(file.string().c_str()), RAC_ERROR_FILE_NOT_FOUND);
    const auto beneath_file = file / "model";
    EXPECT_EQ(rac_classify_null_directory_listing(beneath_file.string().c_str()),
              RAC_ERROR_FILE_NOT_FOUND);
    // A null Java result followed by an existing directory is inconclusive.
    EXPECT_EQ(rac_classify_null_directory_listing(fixture.model.string().c_str()),
              RAC_ERROR_FILE_READ_FAILED);

    // The path argument is UTF-8 on every platform. On Windows a narrow-path
    // probe would decode it with the ANSI code page and miss this directory.
    const auto non_ascii = fixture.root / fs::path(u8"modèle-模型");
    fs::create_directories(non_ascii);
    const auto to_utf8 = [](const fs::path& p) {
        const auto u8 = p.u8string();
        return std::string(u8.begin(), u8.end());
    };
    EXPECT_EQ(rac_classify_null_directory_listing(to_utf8(non_ascii).c_str()),
              RAC_ERROR_FILE_READ_FAILED);
    EXPECT_EQ(rac_classify_null_directory_listing(to_utf8(non_ascii / u8"缺").c_str()),
              RAC_ERROR_FILE_NOT_FOUND);
#if defined(_WIN32)
    // Malformed UTF-8 cannot name a path reliably, so it must stay inconclusive.
    const std::string malformed = to_utf8(fixture.root) + "\\bad\xC3\x28name";
    EXPECT_EQ(rac_classify_null_directory_listing(malformed.c_str()), RAC_ERROR_FILE_READ_FAILED);
#endif

    std::error_code error;
    fs::permissions(fixture.blocked, fs::perms::none, error);
    if (error) {
        std::puts("SKIP: filesystem does not support the permission-denial fixture");
        return 77;
    }
    const bool visible = fs::exists(fixture.model, error);
    if (visible || error != std::errc::permission_denied) {
        std::puts("SKIP: host bypasses filesystem permissions (for example, an elevated user)");
        return 77;
    }
    // No synthetic File overrides: the existing model cannot be stat'ed
    // through its denied ancestor, and must not become a missing-download result.
    EXPECT_EQ(rac_classify_null_directory_listing(fixture.model.string().c_str()),
              RAC_ERROR_FILE_READ_FAILED);
    std::puts("JNI directory probe tests passed, including real permission denial");
    return 0;
}
