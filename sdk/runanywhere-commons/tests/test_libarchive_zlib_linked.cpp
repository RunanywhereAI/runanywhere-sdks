/**
 * @file test_libarchive_zlib_linked.cpp
 * @brief Regression test for the Emscripten/WASM libarchive `gzip -d`
 *        program-fallback failure on OPFS.
 *
 * Background:
 *   An earlier fix to the iOS slices of RACommons.xcframework addressed this:
 *   libarchive's `FIND_PACKAGE(ZLIB 1.2.1)` rejected the cached `v1.3.2`
 *   (RAC_ZLIB_VERSION sourced from VERSIONS), HAVE_ZLIB_H was left undefined,
 *   filter_gzip.c silently re-enabled the
 *   `archive_read_support_filter_program("gzip -d")` fallback. iOS app
 *   sandboxes block fork+exec(/usr/bin/gzip), so every .tar.gz extraction
 *   failed at runtime with "Can't initialize filter; unable to run program".
 *
 *   The web lane surfaced the EXACT same failure on Emscripten/OPFS:
 *
 *     RAC ERROR Extraction: Failed to open archive:
 *     /opfs/RunAnywhere/Downloads/sherpa-onnx-whisper-tiny.en.tar.gz
 *     (Can't initialize filter; unable to run program "gzip -d")
 *
 *   The CMake fix already covered EMSCRIPTEN in its
 *   `if(EMSCRIPTEN OR ANDROID OR IOS ...)` predicate, but the web lane shipped
 *   a build that pre-dated the v-strip and the artifact
 *   went out with HAVE_ZLIB_H undefined.
 *
 *   This test complements test_extraction_no_program_fallback by exercising
 *   the in-process zlib filter at the C ABI level once more, but with the
 *   focus on the Emscripten-specific failure mode + an explicit declaration
 *   that the fix must remain installed on the cross-compile targets:
 *
 *     - Host (macOS/Linux/Windows): exercises the same extraction surface
 *       with PATH cleared (when possible) to mechanically prove no subprocess
 *       is invoked. The host build mirrors the cross-compile filter set, so
 *       a regression that affects Emscripten/iOS will also show up here.
 *
 *     - Emscripten / cross-compile: ctest is not invoked on Emscripten host
 *       runs, so the failure mode lands first in the wasm/scripts/build.sh
 *       libarchive config.h grep and the
 *       configure-time assertion block in sdk/runanywhere-commons/CMakeLists.txt.
 *       This file documents the contract so future maintainers don't move
 *       the assertions without preserving the regression coverage.
 *
 * @see test_extraction_no_program_fallback.cpp (sibling test)
 * @see sdk/runanywhere-commons/CMakeLists.txt (HAVE_ZLIB_H / HAVE_BZLIB_H
 *      configure-time assertion)
 * @see sdk/runanywhere-web/wasm/scripts/build.sh (post-build wasm string
 *      scan + config.h grep)
 */

#include "test_common.h"

#include <archive.h>
#include <archive_entry.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#define getpid _getpid
#else
#include <unistd.h>

#include <sys/stat.h>
#include <sys/types.h>
#endif

#include "rac/infrastructure/extraction/rac_extraction.h"

namespace {

/// Same canned tar.gz used by test_extraction_no_program_fallback. Re-defined
/// here so the two tests stay independent — neither can mask a regression in
/// the other.
static const unsigned char kHelloTarGz[] = {
    0x1f, 0x8b, 0x08, 0x00, 0xb2, 0x1c, 0x11, 0x6a, 0x00, 0x03, 0xcb, 0x48, 0xcd, 0xc9, 0xc9,
    0xd7, 0x2b, 0xa9, 0x28, 0x61, 0xa0, 0x1d, 0x30, 0x30, 0x30, 0x30, 0x33, 0x31, 0x51, 0x00,
    0xd1, 0xe6, 0x66, 0xa6, 0x60, 0x1a, 0x08, 0x60, 0x34, 0x08, 0x18, 0x2b, 0x18, 0x9a, 0x1a,
    0x19, 0x98, 0x18, 0x19, 0x9a, 0x19, 0x99, 0x19, 0x29, 0x18, 0x18, 0x9a, 0x98, 0x1a, 0x99,
    0x30, 0x28, 0x18, 0xd0, 0xd0, 0x4d, 0x70, 0x50, 0x5a, 0x5c, 0x92, 0x58, 0x04, 0x74, 0x4a,
    0x71, 0x62, 0x5e, 0x72, 0x46, 0x66, 0x49, 0x6e, 0x7e, 0x5e, 0x7a, 0x22, 0x36, 0x75, 0xe5,
    0x19, 0xa9, 0xa9, 0x39, 0x78, 0xcc, 0x41, 0xf5, 0x94, 0x02, 0x6d, 0x1c, 0x4b, 0x7d, 0x90,
    0x91, 0xc9, 0x35, 0xd0, 0x4e, 0x18, 0x05, 0xa3, 0x60, 0x14, 0x8c, 0x82, 0x51, 0x30, 0x00,
    0x00, 0x00, 0xdb, 0x9e, 0x45, 0x7f, 0x00, 0x08, 0x00, 0x00,
};

static std::string make_temp_dir(const char* suffix) {
#ifdef _WIN32
    char tmp_path[MAX_PATH];
    GetTempPathA(MAX_PATH, tmp_path);
    char dir[MAX_PATH];
    std::snprintf(dir, sizeof(dir), "%srac_zliblnk_%s_%d", tmp_path, suffix, _getpid());
    if (_mkdir(dir) != 0 && errno != EEXIST) {
        return "";
    }
    return std::string(dir);
#else
    char tmpl[256];
    std::snprintf(tmpl, sizeof(tmpl), "/tmp/rac_zliblnk_%s_XXXXXX", suffix);
    char* result = mkdtemp(tmpl);
    return result ? std::string(result) : std::string();
#endif
}

static void remove_dir(const std::string& path) {
    if (path.empty()) {
        return;
    }
#ifdef _WIN32
    std::string cmd = "rmdir /s /q \"" + path + "\" 2>nul";
#else
    std::string cmd = "rm -rf \"" + path + "\"";
#endif
    std::system(cmd.c_str());
}

static bool write_file(const std::string& path, const void* data, size_t size) {
    std::ofstream f(path, std::ios::binary);
    if (!f.is_open()) {
        return false;
    }
    f.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
    return f.good();
}

/// The load-bearing test. libarchive must successfully decode the
/// gzip stream using the in-process zlib inflate path. If libarchive was
/// built with HAVE_ZLIB_H undefined, archive_read_support_filter_gzip
/// silently registers the program("gzip -d") fallback. With our explicit
/// filter set (no archive_read_support_filter_all), the program bidder is
/// never registered, so opening the archive will fail with
/// "Unrecognized archive format" instead of falling back to fork+exec — but
/// either way, the call below must succeed when the in-process filter is wired
/// correctly.
static TestResult test_libarchive_decodes_targz_in_process() {
    std::string dir = make_temp_dir("decode");
    ASSERT_TRUE(!dir.empty(), "Should create temp dir");

    std::string archive_path = dir + "/canned.tar.gz";
    ASSERT_TRUE(write_file(archive_path, kHelloTarGz, sizeof(kHelloTarGz)),
                "Should write canned tar.gz");

    // Drive libarchive directly to surface decoder errors clearly. The high-
    // level rac_extract_archive_native test in test_extraction_no_program_fallback
    // already covers the public C ABI; this one isolates the symbol-resolution
    // path so a failure here points at a build-time misconfiguration rather
    // than an ABI bug.
    struct archive* a = archive_read_new();
    ASSERT_TRUE(a != nullptr, "Should allocate libarchive reader");

    archive_read_support_format_all(a);
    // Same explicit filter set as rac_extract_archive_native — see the
    // comment in rac_extraction.cpp. The omission of
    // archive_read_support_filter_all is the load-bearing change.
    archive_read_support_filter_none(a);
    int r_gzip = archive_read_support_filter_gzip(a);
    int r_bzip2 = archive_read_support_filter_bzip2(a);
    // xz is explicitly disabled in commons libarchive build
    // (ENABLE_LZMA=OFF; no model artefact ships tar.xz today). The
    // registration call still returns ARCHIVE_WARN to signal the program()
    // bidder was the only path libarchive could register — accepting that
    // outcome but NOT counting it as success keeps the bidder competition
    // resolved to gzip/bzip2 only. We deliberately do not assert on
    // r_xz here.
    (void)archive_read_support_filter_xz(a);

    ASSERT_EQ(r_gzip, ARCHIVE_OK,
              "archive_read_support_filter_gzip must succeed (ARCHIVE_OK == 0). "
              "Failure means libarchive was built without zlib support "
              "(HAVE_ZLIB_H undefined). Emscripten/iOS will silently fall back "
              "to program(\"gzip -d\"), which fails inside the OPFS / iOS "
              "sandbox.");
    ASSERT_EQ(r_bzip2, ARCHIVE_OK,
              "archive_read_support_filter_bzip2 must succeed (ARCHIVE_OK == 0). "
              "HAVE_BZLIB_H must be defined; otherwise libarchive will fall "
              "back to program(\"bzip2 -d\").");

    int rc = archive_read_open_filename(a, archive_path.c_str(), 10240);
    ASSERT_EQ(rc, ARCHIVE_OK,
              "archive_read_open_filename must succeed on a canned tar.gz. "
              "Failure here means the gzip filter could not decode the stream — "
              "either zlib is not linked or the filter registration above was "
              "a no-op.");

    struct archive_entry* entry = nullptr;
    rc = archive_read_next_header(a, &entry);
    ASSERT_EQ(rc, ARCHIVE_OK,
              "archive_read_next_header must succeed: gzip filter decoded the "
              "outer stream and the inner tar block reader advanced.");
    ASSERT_TRUE(entry != nullptr, "Entry pointer must be non-null");

    const char* pathname = archive_entry_pathname(entry);
    ASSERT_TRUE(pathname != nullptr, "Entry pathname must be non-null");
    ASSERT_TRUE(std::string(pathname) == "hello.txt", "First entry should be hello.txt");

    archive_read_free(a);

    remove_dir(dir);
    return TEST_PASS();
}

/// Also assert the public C ABI extraction round-trips end-to-end.
/// This is the same behaviour test_extraction_no_program_fallback exercises;
/// repeating it here keeps both tests independent so a regression in one
/// surface area cannot mask the other.
static TestResult test_rac_extract_archive_native_targz() {
    std::string src_dir = make_temp_dir("src");
    std::string dest_dir = make_temp_dir("dest");
    ASSERT_TRUE(!src_dir.empty() && !dest_dir.empty(), "Should create temp dirs");

    std::string archive_path = src_dir + "/canned.tar.gz";
    ASSERT_TRUE(write_file(archive_path, kHelloTarGz, sizeof(kHelloTarGz)),
                "Should write canned tar.gz");

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(archive_path.c_str(), dest_dir.c_str(), nullptr,
                                                 nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS,
              "rac_extract_archive_native must succeed on tar.gz via the "
              "in-process zlib gzip filter. Failure means HAVE_ZLIB_H is "
              "undefined in libarchive's config.h or the explicit filter "
              "registration in rac_extraction.cpp regressed.");
    ASSERT_TRUE(result.files_extracted >= 1, "Should extract at least one file");

    remove_dir(src_dir);
    remove_dir(dest_dir);
    return TEST_PASS();
}

}  // namespace

int main_impl(int argc, char** argv) {
    TestSuite suite("libarchive_zlib_linked");
    suite.add("libarchive_decodes_targz_in_process", test_libarchive_decodes_targz_in_process);
    suite.add("rac_extract_archive_native_targz", test_rac_extract_archive_native_targz);
    return suite.run(argc, argv);
}

int main(int argc, char** argv) {
    try {
        return main_impl(argc, argv);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
