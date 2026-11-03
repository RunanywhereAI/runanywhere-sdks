/**
 * @file test_jni_directory_probe.cpp
 * @brief Real filesystem coverage for the JNI null-listing classification.
 */

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <system_error>

#include "jni/directory_probe_internal.h"

namespace {

namespace fs = std::filesystem;
using rac::jni::classify_null_directory_listing;

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

    EXPECT_EQ(classify_null_directory_listing(nullptr), RAC_ERROR_INVALID_ARGUMENT);
    EXPECT_EQ(classify_null_directory_listing(missing.string().c_str()), RAC_ERROR_FILE_NOT_FOUND);
    EXPECT_EQ(classify_null_directory_listing(file.string().c_str()), RAC_ERROR_FILE_NOT_FOUND);
    const auto beneath_file = file / "model";
    EXPECT_EQ(classify_null_directory_listing(beneath_file.string().c_str()),
              RAC_ERROR_FILE_NOT_FOUND);
    // A null Java result followed by an existing directory is inconclusive.
    EXPECT_EQ(classify_null_directory_listing(fixture.model.string().c_str()),
              RAC_ERROR_FILE_READ_FAILED);

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
    EXPECT_EQ(classify_null_directory_listing(fixture.model.string().c_str()),
              RAC_ERROR_FILE_READ_FAILED);
    std::puts("JNI directory probe tests passed, including real permission denial");
    return 0;
}
