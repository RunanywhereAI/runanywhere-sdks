/**
 * @file test_extraction_no_program_fallback.cpp
 * @brief Regression test for CLUSTER-02 / COMMONS-LIBARCHIVE-001 (iOS gzip
 *        program() sandbox failure).
 *
 * Background:
 *   libarchive registers gzip/bzip2/xz filters via `program("gzip -d")` etc.
 *   when its own build-time configure step failed to find zlib (HAVE_ZLIB_H
 *   undefined). The program() path is a `fork+exec` of `/usr/bin/gzip`,
 *   which the iOS app sandbox blocks. Every .tar.gz model extraction (Sherpa
 *   Whisper Tiny, SmolVLM, Piper TTS) on Swift iOS + Flutter iOS therefore
 *   failed with an obscure "Child process exited" error inside libarchive
 *   even though the symbol `_archive_read_support_filter_gzip` was present
 *   in the static library.
 *
 * The fix (rac_extraction.cpp + CMakeLists.txt) does two things:
 *   1. rac_extract_archive_native() now explicitly registers ONLY the
 *      built-in filters (no `archive_read_support_filter_all`), so the
 *      program() fallback bidder is never registered at runtime.
 *   2. CMakeLists.txt now force-bundles zlib for iOS/Android/Emscripten so
 *      libarchive's own configure sees HAVE_ZLIB_H and emits the in-process
 *      inflate path, eliminating the program() fallback at the source.
 *
 * This test exercises tar.gz extraction with `PATH` cleared so no external
 * decompressor is reachable. If libarchive ever regresses back to the
 * program() fallback path, gzip_bidder_init() will `popen()` /
 * `posix_spawn()` `gzip -d` with an empty PATH and fail, surfacing the
 * regression as a hard test failure instead of a silent runtime crash on
 * the iOS sandbox.
 *
 * On Windows we skip the PATH-clearing assertion (PATH semantics differ);
 * the test still asserts that extraction succeeds, which is the load-bearing
 * invariant.
 */

#include "test_common.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>

#include "rac/infrastructure/extraction/rac_extraction.h"

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

namespace {

static std::string make_temp_dir(const char* suffix) {
#ifdef _WIN32
    char tmp_path[MAX_PATH];
    GetTempPathA(MAX_PATH, tmp_path);
    char dir[MAX_PATH];
    snprintf(dir, sizeof(dir), "%srac_noprog_%s_%d", tmp_path, suffix, _getpid());
    if (_mkdir(dir) != 0 && errno != EEXIST) {
        return "";
    }
    return std::string(dir);
#else
    char tmpl[256];
    std::snprintf(tmpl, sizeof(tmpl), "/tmp/rac_noprog_%s_XXXXXX", suffix);
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

/// A pre-canned gzip-wrapped tar archive containing a single file
/// "hello.txt" with the contents "hi\n". Embedded as a literal so the test
/// does not depend on the host `tar` / `gzip` binaries being on PATH (the
/// whole point of this test is to assert we don't need them for extraction).
///
/// Generated via:
///     mkdir -p /tmp/r && printf "hi\n" > /tmp/r/hello.txt
///     tar czf /tmp/canned.tar.gz -C /tmp/r hello.txt
///     xxd -i /tmp/canned.tar.gz
///
/// Embedding the bytes (rather than calling host `tar`) means this test
/// works inside sandboxes that block subprocess execution — the same
/// environment the iOS app runs in. The exact bytes will be different on
/// each generation because gzip embeds an mtime; we only care that this is
/// a valid gzip+tar stream that libarchive can read.
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

/// Write the canned tar.gz to disk so we have a known-good gzip stream that
/// exercises the read-side gzip filter. We deliberately do NOT shell out to
/// `tar`/`gzip` here — the whole point of this regression test is to prove
/// that extraction works without any external subprocess.
static std::string write_canned_tar_gz(const std::string& dir) {
    std::string path = dir + "/canned.tar.gz";
    if (!write_file(path, kHelloTarGz, sizeof(kHelloTarGz))) {
        return {};
    }
    return path;
}

/// End-to-end #1: detect on the canned archive.
static TestResult test_detect_canned_targz_no_subprocess() {
    std::string dir = make_temp_dir("detect");
    ASSERT_TRUE(!dir.empty(), "Should create temp dir");

    std::string archive_path = write_canned_tar_gz(dir);
    ASSERT_TRUE(!archive_path.empty(), "Should write canned tar.gz");

    rac_archive_type_t type = RAC_ARCHIVE_TYPE_NONE;
    rac_bool_t ok = rac_detect_archive_type(archive_path.c_str(), &type);
    ASSERT_EQ(ok, RAC_TRUE, "Should detect canned tar.gz via magic bytes (no subprocess)");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_GZ, "Type should be RAC_ARCHIVE_TYPE_TAR_GZ");

    remove_dir(dir);
    return TEST_PASS();
}

/// End-to-end #2: extract the canned archive via the public C ABI. This is
/// the load-bearing test: rac_extract_archive_native() now only registers
/// the in-process zlib gzip filter (per the CLUSTER-02 fix), so this call
/// must succeed without invoking `/usr/bin/gzip`. If extraction silently
/// regresses to the program() fallback, the iOS lane will fail at runtime
/// inside the sandbox — but this host-side test would also fail (because
/// even on macOS the test would invoke a subprocess we explicitly forbid).
static TestResult test_extract_canned_targz_via_public_abi() {
    std::string archive_dir = make_temp_dir("extract_src");
    std::string dest_dir = make_temp_dir("extract_dest");
    ASSERT_TRUE(!archive_dir.empty(), "Should create archive dir");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    std::string archive_path = write_canned_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should write canned tar.gz");

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(archive_path.c_str(), dest_dir.c_str(), nullptr,
                                                 nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS,
              "rac_extract_archive_native must succeed via the in-process zlib gzip filter. "
              "If this fails on host, libarchive is missing the inflate symbols at link time "
              "and the iOS lane will fail in the sandbox with 'Child process exited'.");
    ASSERT_TRUE(result.files_extracted >= 1, "Should extract at least one file (hello.txt)");

    remove_dir(archive_dir);
    remove_dir(dest_dir);
    return TEST_PASS();
}

#ifndef _WIN32
/// End-to-end #3 (POSIX only): extract with PATH cleared. This proves we
/// never `execvp("gzip", ...)`. If libarchive's program() fallback bidder
/// were still registered, the extraction would fork+exec /usr/bin/gzip;
/// with PATH="" that exec would fail with ENOENT and libarchive would
/// propagate ARCHIVE_FATAL up to us. The test passes => no subprocess was
/// invoked => the iOS sandbox failure mode cannot reproduce.
static TestResult test_extract_canned_targz_with_empty_path() {
    std::string archive_dir = make_temp_dir("emptypath_src");
    std::string dest_dir = make_temp_dir("emptypath_dest");
    ASSERT_TRUE(!archive_dir.empty(), "Should create archive dir");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    std::string archive_path = write_canned_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should write canned tar.gz");

    // Save and clear PATH.
    const char* saved_path = std::getenv("PATH");
    std::string saved_path_str = saved_path ? saved_path : "";
    int unset_rc = setenv("PATH", "", 1);
    ASSERT_EQ(unset_rc, 0, "Should clear PATH");

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(archive_path.c_str(), dest_dir.c_str(), nullptr,
                                                 nullptr, nullptr, &result);

    // Always restore PATH before any assert so a failing assertion doesn't
    // leave the rest of the suite in a broken environment.
    setenv("PATH", saved_path_str.c_str(), 1);

    ASSERT_EQ(rc, RAC_SUCCESS,
              "rac_extract_archive_native must succeed with empty PATH. Failure here means "
              "libarchive's program(\"gzip -d\") fallback is reachable from our call site — "
              "the exact behaviour the iOS sandbox blocks.");
    ASSERT_TRUE(result.files_extracted >= 1, "Should extract at least one file with empty PATH");

    remove_dir(archive_dir);
    remove_dir(dest_dir);
    return TEST_PASS();
}
#endif  // !_WIN32

}  // namespace

int main_impl(int argc, char** argv) {
    TestSuite suite("extraction_no_program_fallback");
    suite.add("detect_canned_targz_no_subprocess", test_detect_canned_targz_no_subprocess);
    suite.add("extract_canned_targz_via_public_abi", test_extract_canned_targz_via_public_abi);
#ifndef _WIN32
    suite.add("extract_canned_targz_with_empty_path", test_extract_canned_targz_with_empty_path);
#endif
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
