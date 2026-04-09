/**
 * @file test_extraction.cpp
 * @brief Integration tests for native archive extraction (libarchive).
 *
 * Tests rac_extract_archive_native() and rac_detect_archive_type() from
 * rac_extraction.h. No ML backend dependency — only links rac_commons.
 *
 * Uses system `tar` and `zip` commands to create test archives on macOS/Linux.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/infrastructure/extraction/rac_extraction.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

// No platform adapter or rac_init() needed — extraction APIs are standalone.

// =============================================================================
// Test helpers
// =============================================================================

static std::string g_test_dir;

/** Create a unique temporary directory for test artifacts. */
static std::string create_temp_dir(const std::string& suffix) {
    char tmpl[256];
    snprintf(tmpl, sizeof(tmpl), "/tmp/rac_test_%s_XXXXXX", suffix.c_str());
    char* result = mkdtemp(tmpl);
    if (!result) {
        std::cerr << "Failed to create temp dir: " << tmpl << "\n";
        return "";
    }
    return std::string(result);
}

/** Recursively remove a directory. */
static void remove_dir(const std::string& path) {
    std::string cmd = "rm -rf \"" + path + "\"";
    system(cmd.c_str());
}

/** Check if a file exists. */
static bool file_exists(const std::string& path) {
    struct stat st;
    return stat(path.c_str(), &st) == 0;
}

/** Read entire file contents. */
static std::string read_file_contents(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return "";
    return std::string((std::istreambuf_iterator<char>(f)),
                        std::istreambuf_iterator<char>());
}

/** Write bytes to a file. */
static bool write_file(const std::string& path, const void* data, size_t size) {
    std::ofstream f(path, std::ios::binary);
    if (!f.is_open()) return false;
    f.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
    return f.good();
}

/** Write string to a file. */
static bool write_file(const std::string& path, const std::string& content) {
    return write_file(path, content.data(), content.size());
}

/** Check if tar command is available. */
static bool has_tar() {
    return system("tar --version > /dev/null 2>&1") == 0;
}

/** Check if zip command is available. */
static bool has_zip() {
    return system("zip --version > /dev/null 2>&1") == 0;
}

/**
 * Create a tar.gz archive containing test files.
 * Returns path to the created archive, or empty string on failure.
 */
static std::string create_test_tar_gz(const std::string& base_dir) {
    std::string content_dir = base_dir + "/content";
    std::string sub_dir = content_dir + "/subdir";
    mkdir(content_dir.c_str(), 0755);
    mkdir(sub_dir.c_str(), 0755);

    write_file(content_dir + "/hello.txt", "Hello, World!\n");
    write_file(content_dir + "/data.bin", std::string(256, '\x42'));
    write_file(sub_dir + "/nested.txt", "Nested file content\n");

    std::string archive_path = base_dir + "/test.tar.gz";
    std::string cmd = "tar czf \"" + archive_path + "\" -C \"" + base_dir + "\" content";
    if (system(cmd.c_str()) != 0) return "";
    return archive_path;
}

/**
 * Create a ZIP archive containing test files.
 * Returns path to the created archive, or empty string on failure.
 */
static std::string create_test_zip(const std::string& base_dir) {
    std::string content_dir = base_dir + "/zipcontent";
    std::string sub_dir = content_dir + "/subdir";
    mkdir(content_dir.c_str(), 0755);
    mkdir(sub_dir.c_str(), 0755);

    write_file(content_dir + "/readme.txt", "ZIP test file\n");
    write_file(content_dir + "/binary.dat", std::string(128, '\xAB'));
    write_file(sub_dir + "/deep.txt", "Deep nested\n");

    std::string archive_path = base_dir + "/test.zip";
    std::string cmd = "cd \"" + base_dir + "\" && zip -r \"" + archive_path + "\" zipcontent > /dev/null 2>&1";
    if (system(cmd.c_str()) != 0) return "";
    return archive_path;
}

// =============================================================================
// Test: null pointer handling
// =============================================================================

static TestResult test_null_pointer() {
    rac_result_t rc = rac_extract_archive_native(nullptr, "/tmp", nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "NULL archive_path should return RAC_ERROR_NULL_POINTER");

    rc = rac_extract_archive_native("/tmp/test.tar.gz", nullptr, nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "NULL destination_dir should return RAC_ERROR_NULL_POINTER");

    rc = rac_extract_archive_native(nullptr, nullptr, nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "Both NULL should return RAC_ERROR_NULL_POINTER");

    return TEST_PASS();
}

// =============================================================================
// Test: file not found
// =============================================================================

static TestResult test_file_not_found() {
    rac_result_t rc = rac_extract_archive_native(
        "/nonexistent/path/archive.tar.gz", "/tmp/dest",
        nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_FILE_NOT_FOUND,
              "Non-existent archive should return RAC_ERROR_FILE_NOT_FOUND");

    return TEST_PASS();
}

// =============================================================================
// Test: detect archive type - null handling
// =============================================================================

static TestResult test_detect_null() {
    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(nullptr, &type), RAC_FALSE,
              "NULL file_path should return RAC_FALSE");
    ASSERT_EQ(rac_detect_archive_type("/tmp/test.bin", nullptr), RAC_FALSE,
              "NULL out_type should return RAC_FALSE");

    return TEST_PASS();
}

// =============================================================================
// Test: detect archive type - non-existent file
// =============================================================================

static TestResult test_detect_nonexistent() {
    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type("/nonexistent/file.bin", &type), RAC_FALSE,
              "Non-existent file should return RAC_FALSE");

    return TEST_PASS();
}

// =============================================================================
// Test: detect ZIP magic bytes
// =============================================================================

static TestResult test_detect_zip() {
    std::string path = g_test_dir + "/magic_zip.bin";
    unsigned char zip_magic[] = {0x50, 0x4B, 0x03, 0x04, 0x00, 0x00};
    write_file(path, zip_magic, sizeof(zip_magic));

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_TRUE,
              "ZIP magic bytes should be detected");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_ZIP, "Type should be RAC_ARCHIVE_TYPE_ZIP");

    return TEST_PASS();
}

// =============================================================================
// Test: detect GZIP magic bytes
// =============================================================================

static TestResult test_detect_gzip() {
    std::string path = g_test_dir + "/magic_gzip.bin";
    unsigned char gz_magic[] = {0x1F, 0x8B, 0x08, 0x00};
    write_file(path, gz_magic, sizeof(gz_magic));

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_TRUE,
              "GZIP magic bytes should be detected");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_GZ, "Type should be RAC_ARCHIVE_TYPE_TAR_GZ");

    return TEST_PASS();
}

// =============================================================================
// Test: detect BZIP2 magic bytes
// =============================================================================

static TestResult test_detect_bzip2() {
    std::string path = g_test_dir + "/magic_bz2.bin";
    unsigned char bz2_magic[] = {0x42, 0x5A, 0x68, 0x39};  // "BZh9"
    write_file(path, bz2_magic, sizeof(bz2_magic));

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_TRUE,
              "BZIP2 magic bytes should be detected");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_BZ2, "Type should be RAC_ARCHIVE_TYPE_TAR_BZ2");

    return TEST_PASS();
}

// =============================================================================
// Test: detect XZ magic bytes
// =============================================================================

static TestResult test_detect_xz() {
    std::string path = g_test_dir + "/magic_xz.bin";
    unsigned char xz_magic[] = {0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00};
    write_file(path, xz_magic, sizeof(xz_magic));

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_TRUE,
              "XZ magic bytes should be detected");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_XZ, "Type should be RAC_ARCHIVE_TYPE_TAR_XZ");

    return TEST_PASS();
}

// =============================================================================
// Test: detect unknown format
// =============================================================================

static TestResult test_detect_unknown() {
    std::string path = g_test_dir + "/magic_unknown.bin";
    unsigned char random_bytes[] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
    write_file(path, random_bytes, sizeof(random_bytes));

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_FALSE,
              "Unknown magic bytes should return RAC_FALSE");

    return TEST_PASS();
}

// =============================================================================
// Test: detect empty file
// =============================================================================

static TestResult test_detect_empty_file() {
    std::string path = g_test_dir + "/empty.bin";
    write_file(path, "", 0);

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(path.c_str(), &type), RAC_FALSE,
              "Empty file should return RAC_FALSE");

    return TEST_PASS();
}

// =============================================================================
// Test: extract tar.gz archive
// =============================================================================

static TestResult test_extract_tar_gz() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("tgz_src");
    std::string dest_dir = create_temp_dir("tgz_dest");
    ASSERT_TRUE(!archive_dir.empty(), "Should create archive source dir");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    std::string archive_path = create_test_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create tar.gz archive");
    ASSERT_TRUE(file_exists(archive_path), "Archive file should exist");

    // Verify detection
    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(archive_path.c_str(), &type), RAC_TRUE,
              "Should detect tar.gz");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_GZ, "Should be TAR_GZ");

    // Extract
    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction should succeed");

    // Verify extracted files
    ASSERT_TRUE(result.files_extracted >= 3, "Should extract at least 3 files");
    ASSERT_TRUE(result.directories_created >= 1, "Should create at least 1 directory");
    ASSERT_TRUE(result.bytes_extracted > 0, "Should extract some bytes");

    // Verify file contents
    std::string hello_content = read_file_contents(dest_dir + "/content/hello.txt");
    ASSERT_TRUE(hello_content == "Hello, World!\n",
                "hello.txt content should match");

    std::string nested_content = read_file_contents(dest_dir + "/content/subdir/nested.txt");
    ASSERT_TRUE(nested_content == "Nested file content\n",
                "nested.txt content should match");

    std::string data_content = read_file_contents(dest_dir + "/content/data.bin");
    ASSERT_EQ(static_cast<int>(data_content.size()), 256, "data.bin should be 256 bytes");
    ASSERT_TRUE(data_content[0] == '\x42', "data.bin content should be 0x42");

    // Cleanup
    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: extract ZIP archive
// =============================================================================

static TestResult test_extract_zip() {
    if (!has_zip()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (zip not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("zip_src");
    std::string dest_dir = create_temp_dir("zip_dest");
    ASSERT_TRUE(!archive_dir.empty(), "Should create archive source dir");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    std::string archive_path = create_test_zip(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create ZIP archive");
    ASSERT_TRUE(file_exists(archive_path), "Archive file should exist");

    // Verify detection
    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(archive_path.c_str(), &type), RAC_TRUE,
              "Should detect ZIP");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_ZIP, "Should be ZIP");

    // Extract
    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "ZIP extraction should succeed");

    // Verify extracted files
    ASSERT_TRUE(result.files_extracted >= 3, "Should extract at least 3 files");
    ASSERT_TRUE(result.bytes_extracted > 0, "Should extract some bytes");

    // Verify file contents
    std::string readme_content = read_file_contents(dest_dir + "/zipcontent/readme.txt");
    ASSERT_TRUE(readme_content == "ZIP test file\n",
                "readme.txt content should match");

    std::string deep_content = read_file_contents(dest_dir + "/zipcontent/subdir/deep.txt");
    ASSERT_TRUE(deep_content == "Deep nested\n",
                "deep.txt content should match");

    // Cleanup
    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: progress callback is invoked
// =============================================================================

struct ProgressData {
    int callback_count;
    int32_t last_files_extracted;
    int64_t last_bytes_extracted;
};

static void test_progress_callback(int32_t files_extracted, int32_t /*total_files*/,
                                    int64_t bytes_extracted, void* user_data) {
    auto* data = static_cast<ProgressData*>(user_data);
    data->callback_count++;
    data->last_files_extracted = files_extracted;
    data->last_bytes_extracted = bytes_extracted;
}

static TestResult test_progress_callback_invoked() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("prog_src");
    std::string dest_dir = create_temp_dir("prog_dest");
    ASSERT_TRUE(!archive_dir.empty() && !dest_dir.empty(), "Should create dirs");

    std::string archive_path = create_test_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create archive");

    ProgressData progress = {0, 0, 0};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, test_progress_callback, &progress, nullptr);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction with progress should succeed");
    ASSERT_TRUE(progress.callback_count > 0,
                "Progress callback should be invoked at least once");
    ASSERT_TRUE(progress.last_files_extracted > 0,
                "Last files_extracted should be > 0");
    ASSERT_TRUE(progress.last_bytes_extracted > 0,
                "Last bytes_extracted should be > 0");

    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: extraction result statistics
// =============================================================================

static TestResult test_extraction_result_stats() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("stats_src");
    std::string dest_dir = create_temp_dir("stats_dest");
    ASSERT_TRUE(!archive_dir.empty() && !dest_dir.empty(), "Should create dirs");

    std::string archive_path = create_test_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create archive");

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction should succeed");

    // We created 3 files (hello.txt, data.bin, nested.txt)
    ASSERT_EQ(result.files_extracted, 3,
              "Should extract exactly 3 files");
    // We created 2 directories (content, content/subdir)
    ASSERT_TRUE(result.directories_created >= 1,
                "Should create at least 1 directory");
    // hello.txt(14) + data.bin(256) + nested.txt(20) = 290 bytes
    ASSERT_TRUE(result.bytes_extracted >= 290,
                "bytes_extracted should account for all file data");
    // No entries should be skipped (no macOS resource forks, no unsafe paths)
    ASSERT_EQ(result.entries_skipped, 0,
              "No entries should be skipped");

    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: unsupported archive format
// =============================================================================

static TestResult test_unsupported_format() {
    std::string path = g_test_dir + "/not_an_archive.dat";
    // Write random data that isn't a valid archive
    std::string garbage(1024, '\xAB');
    write_file(path, garbage);

    std::string dest_dir = create_temp_dir("unsup_dest");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    rac_result_t rc = rac_extract_archive_native(
        path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_UNSUPPORTED_ARCHIVE,
              "Invalid archive should return RAC_ERROR_UNSUPPORTED_ARCHIVE");

    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: extraction creates destination directory
// =============================================================================

static TestResult test_creates_dest_dir() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("mkdir_src");
    ASSERT_TRUE(!archive_dir.empty(), "Should create archive source dir");

    std::string archive_path = create_test_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create archive");

    // Destination directory that doesn't exist yet
    std::string dest_dir = g_test_dir + "/new_nested/extraction/output";
    ASSERT_TRUE(!file_exists(dest_dir), "Dest dir should not exist yet");

    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, nullptr);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction should create destination and succeed");
    ASSERT_TRUE(file_exists(dest_dir), "Destination dir should now exist");
    ASSERT_TRUE(file_exists(dest_dir + "/content/hello.txt"),
                "Extracted file should exist");

    remove_dir(archive_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: default options (skip macOS resources)
// =============================================================================

static TestResult test_default_options_skip_macos() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    // Create content with macOS resource fork files
    std::string archive_dir = create_temp_dir("macos_src");
    std::string content_dir = archive_dir + "/macos_content";
    std::string macosx_dir = content_dir + "/__MACOSX";
    mkdir(content_dir.c_str(), 0755);
    mkdir(macosx_dir.c_str(), 0755);

    write_file(content_dir + "/real_file.txt", "real content\n");
    write_file(content_dir + "/._resource_fork", "resource fork\n");
    write_file(macosx_dir + "/metadata.plist", "macos metadata\n");

    std::string archive_path = archive_dir + "/macos_test.tar.gz";
    std::string cmd = "tar czf \"" + archive_path + "\" -C \"" + archive_dir + "\" macos_content";
    ASSERT_TRUE(system(cmd.c_str()) == 0, "Should create tar.gz with macOS entries");

    std::string dest_dir = create_temp_dir("macos_dest");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        nullptr, nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction should succeed");

    // real_file.txt should be extracted
    ASSERT_TRUE(file_exists(dest_dir + "/macos_content/real_file.txt"),
                "Real file should be extracted");

    // macOS resource forks should be skipped
    ASSERT_TRUE(result.entries_skipped > 0,
                "Should skip macOS resource entries");
    ASSERT_TRUE(!file_exists(dest_dir + "/macos_content/__MACOSX/metadata.plist"),
                "__MACOSX directory contents should be skipped");
    ASSERT_TRUE(!file_exists(dest_dir + "/macos_content/._resource_fork"),
                "._ resource fork files should be skipped");

    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: extraction with custom options (don't skip macOS resources)
// =============================================================================

static TestResult test_custom_options_keep_macos() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("keepmac_src");
    std::string content_dir = archive_dir + "/keep_content";
    std::string macosx_dir = content_dir + "/__MACOSX";
    mkdir(content_dir.c_str(), 0755);
    mkdir(macosx_dir.c_str(), 0755);

    write_file(content_dir + "/file.txt", "content\n");
    write_file(macosx_dir + "/meta.plist", "metadata\n");

    std::string archive_path = archive_dir + "/keep_macos.tar.gz";
    std::string cmd = "tar czf \"" + archive_path + "\" -C \"" + archive_dir + "\" keep_content";
    ASSERT_TRUE(system(cmd.c_str()) == 0, "Should create tar.gz");

    std::string dest_dir = create_temp_dir("keepmac_dest");
    ASSERT_TRUE(!dest_dir.empty(), "Should create dest dir");

    // Don't skip macOS resources
    rac_extraction_options_t opts = {};
    opts.skip_macos_resources = RAC_FALSE;
    opts.skip_symlinks = RAC_FALSE;
    opts.archive_type_hint = RAC_ARCHIVE_TYPE_NONE;

    rac_extraction_result_t result = {};
    rac_result_t rc = rac_extract_archive_native(
        archive_path.c_str(), dest_dir.c_str(),
        &opts, nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Extraction should succeed");

    // Both files should be extracted (no skipping)
    ASSERT_TRUE(file_exists(dest_dir + "/keep_content/file.txt"),
                "file.txt should be extracted");
    ASSERT_TRUE(file_exists(dest_dir + "/keep_content/__MACOSX/meta.plist"),
                "__MACOSX content should be extracted when skip_macos_resources=FALSE");

    remove_dir(archive_dir);
    remove_dir(dest_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: detect archive type from real tar.gz
// =============================================================================

static TestResult test_detect_real_tar_gz() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("detect_src");
    std::string archive_path = create_test_tar_gz(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create archive");

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(archive_path.c_str(), &type), RAC_TRUE,
              "Should detect real tar.gz archive");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_GZ, "Should be TAR_GZ");

    remove_dir(archive_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: detect archive type from real ZIP
// =============================================================================

static TestResult test_detect_real_zip() {
    if (!has_zip()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (zip not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("detectzip_src");
    std::string archive_path = create_test_zip(archive_dir);
    ASSERT_TRUE(!archive_path.empty(), "Should create archive");

    rac_archive_type_t type;
    ASSERT_EQ(rac_detect_archive_type(archive_path.c_str(), &type), RAC_TRUE,
              "Should detect real ZIP archive");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_ZIP, "Should be ZIP");

    remove_dir(archive_dir);

    return TEST_PASS();
}

// =============================================================================
// Test: archive_type_extension helper
// =============================================================================

static TestResult test_archive_type_extension() {
    ASSERT_TRUE(std::strcmp(rac_archive_type_extension(RAC_ARCHIVE_TYPE_ZIP), "zip") == 0,
                "ZIP extension should be 'zip'");
    ASSERT_TRUE(std::strcmp(rac_archive_type_extension(RAC_ARCHIVE_TYPE_TAR_GZ), "tar.gz") == 0,
                "TAR_GZ extension should be 'tar.gz'");
    ASSERT_TRUE(std::strcmp(rac_archive_type_extension(RAC_ARCHIVE_TYPE_TAR_BZ2), "tar.bz2") == 0,
                "TAR_BZ2 extension should be 'tar.bz2'");
    ASSERT_TRUE(std::strcmp(rac_archive_type_extension(RAC_ARCHIVE_TYPE_TAR_XZ), "tar.xz") == 0,
                "TAR_XZ extension should be 'tar.xz'");

    return TEST_PASS();
}

// =============================================================================
// Test: archive_type_from_path helper
// =============================================================================

static TestResult test_archive_type_from_path() {
    rac_archive_type_t type;

    ASSERT_EQ(rac_archive_type_from_path("model.tar.gz", &type), RAC_TRUE,
              "Should detect tar.gz from path");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_GZ, "Should be TAR_GZ");

    ASSERT_EQ(rac_archive_type_from_path("model.tar.bz2", &type), RAC_TRUE,
              "Should detect tar.bz2 from path");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_BZ2, "Should be TAR_BZ2");

    ASSERT_EQ(rac_archive_type_from_path("model.zip", &type), RAC_TRUE,
              "Should detect zip from path");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_ZIP, "Should be ZIP");

    ASSERT_EQ(rac_archive_type_from_path("model.tar.xz", &type), RAC_TRUE,
              "Should detect tar.xz from path");
    ASSERT_EQ(type, RAC_ARCHIVE_TYPE_TAR_XZ, "Should be TAR_XZ");

    ASSERT_EQ(rac_archive_type_from_path("model.gguf", &type), RAC_FALSE,
              "Should not detect archive from .gguf");

    return TEST_PASS();
}

// =============================================================================
// Main: register tests and dispatch via CLI args
// =============================================================================

int main(int argc, char** argv) {
    // Create shared temp directory for all tests
    g_test_dir = create_temp_dir("extraction");
    if (g_test_dir.empty()) {
        std::cerr << "FATAL: Cannot create temp directory\n";
        return 1;
    }

    TestSuite suite("extraction");

    // Null/error handling
    suite.add("null_pointer", test_null_pointer);
    suite.add("file_not_found", test_file_not_found);
    suite.add("unsupported_format", test_unsupported_format);

    // Archive type detection (magic bytes)
    suite.add("detect_null", test_detect_null);
    suite.add("detect_nonexistent", test_detect_nonexistent);
    suite.add("detect_zip", test_detect_zip);
    suite.add("detect_gzip", test_detect_gzip);
    suite.add("detect_bzip2", test_detect_bzip2);
    suite.add("detect_xz", test_detect_xz);
    suite.add("detect_unknown", test_detect_unknown);
    suite.add("detect_empty_file", test_detect_empty_file);
    suite.add("detect_real_tar_gz", test_detect_real_tar_gz);
    suite.add("detect_real_zip", test_detect_real_zip);

    // Type helper functions
    suite.add("archive_type_extension", test_archive_type_extension);
    suite.add("archive_type_from_path", test_archive_type_from_path);

    // Extraction
    suite.add("extract_tar_gz", test_extract_tar_gz);
    suite.add("extract_zip", test_extract_zip);
    suite.add("progress_callback", test_progress_callback_invoked);
    suite.add("extraction_result_stats", test_extraction_result_stats);
    suite.add("creates_dest_dir", test_creates_dest_dir);

    // Options
    suite.add("default_options_skip_macos", test_default_options_skip_macos);
    suite.add("custom_options_keep_macos", test_custom_options_keep_macos);

    int result = suite.run(argc, argv);

    // Cleanup shared temp directory
    remove_dir(g_test_dir);

    return result;
}
