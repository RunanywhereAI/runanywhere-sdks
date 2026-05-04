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
#include "core/internal/platform_compat.h"
#include <vector>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#define getpid _getpid
#else
#include <unistd.h>
#endif

// No platform adapter or rac_init() needed — extraction APIs are standalone.

// Portable mkdir wrapper
static inline int compat_mkdir(const char* path) {
#ifdef _WIN32
    return _mkdir(path);
#else
    return mkdir(path, 0755);
#endif
}

// =============================================================================
// Test helpers
// =============================================================================

static std::string g_test_dir;

/** Create a unique temporary directory for test artifacts. */
static std::string create_temp_dir(const std::string& suffix) {
#ifdef _WIN32
    char tmp_path[MAX_PATH];
    GetTempPathA(MAX_PATH, tmp_path);
    char tmp_dir[MAX_PATH];
    snprintf(tmp_dir, sizeof(tmp_dir), "%srac_test_%s_%d", tmp_path, suffix.c_str(), _getpid());
    if (_mkdir(tmp_dir) != 0 && errno != EEXIST) {
        std::cerr << "Failed to create temp dir: " << tmp_dir << " (errno=" << errno << ")\n";
        return "";
    }
    return std::string(tmp_dir);
#else
    char tmpl[256];
    snprintf(tmpl, sizeof(tmpl), "/tmp/rac_test_%s_XXXXXX", suffix.c_str());
    char* result = mkdtemp(tmpl);
    if (!result) {
        std::cerr << "Failed to create temp dir: " << tmpl << "\n";
        return "";
    }
    return std::string(result);
#endif
}

/** Recursively remove a directory. */
static void remove_dir(const std::string& path) {
#ifdef _WIN32
    std::string cmd = "rmdir /s /q \"" + path + "\" 2>nul";
#else
    std::string cmd = "rm -rf \"" + path + "\"";
#endif
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

static rac_model_info_t make_test_model(const char* id, rac_inference_framework_t framework,
                                        rac_model_format_t format) {
    rac_model_info_t model = {};
    model.id = const_cast<char*>(id);
    model.name = const_cast<char*>(id);
    model.framework = framework;
    model.format = format;
    model.category = RAC_MODEL_CATEGORY_LANGUAGE;
    model.artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
    return model;
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
    compat_mkdir(content_dir.c_str());
    compat_mkdir(sub_dir.c_str());

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
    compat_mkdir(content_dir.c_str());
    compat_mkdir(sub_dir.c_str());

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
// Test: resolve single-file artifact and checksum
// =============================================================================

static TestResult test_resolve_single_file_with_checksum() {
    std::string model_path = g_test_dir + "/single.gguf";
    ASSERT_TRUE(write_file(model_path, "abc"), "Should write single model file");

    rac_model_info_t model =
        make_test_model("single", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    rac_model_path_resolution_t resolution = {};
    rac_result_t rc = rac_model_paths_resolve_artifact(
        &model, model_path.c_str(),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        &resolution);
    ASSERT_EQ(rc, RAC_SUCCESS, "Single file with matching SHA-256 should resolve");
    ASSERT_TRUE(resolution.primary_model_path != nullptr, "Primary path should be populated");
    ASSERT_TRUE(std::string(resolution.primary_model_path).find("single.gguf") !=
                    std::string::npos,
                "Primary path should point to the GGUF file");
    ASSERT_EQ(resolution.checksum_validated, RAC_TRUE, "Checksum should be validated");
    ASSERT_EQ(resolution.checksum_matched, RAC_TRUE, "Checksum should match");
    rac_model_path_resolution_free(&resolution);

    return TEST_PASS();
}

// =============================================================================
// Test: resolve multi-file artifact companions
// =============================================================================

static TestResult test_resolve_companion_files() {
    std::string dir = create_temp_dir("resolve_companions");
    ASSERT_TRUE(!dir.empty(), "Should create temp dir");
    ASSERT_TRUE(write_file(dir + "/main-model.gguf", "main"), "Should write main model");
    ASSERT_TRUE(write_file(dir + "/mmproj-main-model.gguf", "mmproj"), "Should write mmproj");
    ASSERT_TRUE(write_file(dir + "/tokenizer.json", "{}"), "Should write tokenizer");
    ASSERT_TRUE(write_file(dir + "/config.json", "{}"), "Should write config");

    const char* required[] = {"*.gguf", "tokenizer.json"};
    const char* optional[] = {"merges.txt"};
    rac_expected_model_files_t expected = {};
    expected.required_patterns = required;
    expected.required_pattern_count = 2;
    expected.optional_patterns = optional;
    expected.optional_pattern_count = 1;

    rac_model_info_t model =
        make_test_model("main-model", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    model.artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
    model.artifact_info.expected_files = &expected;

    rac_model_path_resolution_t resolution = {};
    rac_result_t rc = rac_model_paths_resolve_artifact(&model, dir.c_str(), nullptr, &resolution);
    ASSERT_EQ(rc, RAC_SUCCESS, "Multi-file model should resolve");
    ASSERT_TRUE(resolution.primary_model_path != nullptr, "Primary path should be populated");
    ASSERT_TRUE(resolution.mmproj_path != nullptr, "mmproj companion should be discovered");
    ASSERT_TRUE(resolution.tokenizer_path != nullptr, "Tokenizer should be discovered");
    ASSERT_TRUE(resolution.config_path != nullptr, "Config should be discovered");
    ASSERT_EQ(resolution.missing_required_file_count, static_cast<size_t>(0),
              "No required files should be missing");
    rac_model_path_resolution_free(&resolution);
    remove_dir(dir);

    return TEST_PASS();
}

// =============================================================================
// Test: missing required file fails while optional file is allowed
// =============================================================================

static TestResult test_resolve_missing_required_optional_allowed() {
    std::string dir = create_temp_dir("resolve_missing");
    ASSERT_TRUE(!dir.empty(), "Should create temp dir");
    ASSERT_TRUE(write_file(dir + "/model.gguf", "model"), "Should write model");

    const char* required[] = {"*.gguf", "tokenizer.json"};
    const char* optional[] = {"config.json"};
    rac_expected_model_files_t expected = {};
    expected.required_patterns = required;
    expected.required_pattern_count = 2;
    expected.optional_patterns = optional;
    expected.optional_pattern_count = 1;

    rac_model_info_t model =
        make_test_model("model", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    model.artifact_info.expected_files = &expected;

    rac_model_path_resolution_t resolution = {};
    rac_result_t rc = rac_model_paths_resolve_artifact(&model, dir.c_str(), nullptr, &resolution);
    ASSERT_EQ(rc, RAC_ERROR_MODEL_VALIDATION_FAILED,
              "Missing required tokenizer should fail validation");
    ASSERT_EQ(resolution.missing_required_file_count, static_cast<size_t>(1),
              "Exactly one required file should be missing");
    ASSERT_TRUE(std::string(resolution.missing_required_files[0]) == "tokenizer.json",
                "Missing required file should be tokenizer.json");
    rac_model_path_resolution_free(&resolution);
    remove_dir(dir);

    return TEST_PASS();
}

// =============================================================================
// Test: file descriptors participate in required-file validation
// =============================================================================

static TestResult test_resolve_file_descriptor_required() {
    std::string dir = create_temp_dir("resolve_descriptors");
    ASSERT_TRUE(!dir.empty(), "Should create temp dir");
    ASSERT_TRUE(write_file(dir + "/model.gguf", "model"), "Should write model");

    rac_model_file_descriptor_t descriptors[2] = {};
    descriptors[0].relative_path = "model.gguf";
    descriptors[0].destination_path = "model.gguf";
    descriptors[0].is_required = RAC_TRUE;
    descriptors[1].relative_path = "tokenizer.model";
    descriptors[1].destination_path = "tokenizer.model";
    descriptors[1].is_required = RAC_TRUE;

    rac_model_info_t model =
        make_test_model("model", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    model.artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
    model.artifact_info.file_descriptors = descriptors;
    model.artifact_info.file_descriptor_count = 2;

    rac_model_path_resolution_t resolution = {};
    rac_result_t rc = rac_model_paths_resolve_artifact(&model, dir.c_str(), nullptr, &resolution);
    ASSERT_EQ(rc, RAC_ERROR_MODEL_VALIDATION_FAILED,
              "Missing required descriptor should fail validation");
    ASSERT_EQ(resolution.missing_required_file_count, static_cast<size_t>(1),
              "One descriptor should be missing");
    ASSERT_TRUE(std::string(resolution.missing_required_files[0]) == "tokenizer.model",
                "Missing descriptor should be tokenizer.model");
    rac_model_path_resolution_free(&resolution);
    remove_dir(dir);

    return TEST_PASS();
}

// =============================================================================
// Test: checksum mismatch fails validation
// =============================================================================

static TestResult test_resolve_checksum_mismatch() {
    std::string model_path = g_test_dir + "/checksum-mismatch.gguf";
    ASSERT_TRUE(write_file(model_path, "abc"), "Should write checksum test model");

    rac_model_info_t model =
        make_test_model("checksum-mismatch", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    rac_model_path_resolution_t resolution = {};
    rac_result_t rc = rac_model_paths_resolve_artifact(
        &model, model_path.c_str(),
        "0000000000000000000000000000000000000000000000000000000000000000",
        &resolution);
    ASSERT_EQ(rc, RAC_ERROR_MODEL_VALIDATION_FAILED,
              "Wrong checksum should fail validation");
    ASSERT_EQ(resolution.checksum_validated, RAC_TRUE, "Checksum should be attempted");
    ASSERT_EQ(resolution.checksum_matched, RAC_FALSE, "Checksum should not match");
    rac_model_path_resolution_free(&resolution);

    return TEST_PASS();
}

// =============================================================================
// Test: extract archive and resolve model path in one native call
// =============================================================================

static TestResult test_extract_and_resolve_archive() {
    if (!has_tar()) {
        TestResult r;
        r.passed = true;
        r.details = "SKIPPED (tar not available)";
        return r;
    }

    std::string archive_dir = create_temp_dir("resolve_archive_src");
    std::string content_dir = archive_dir + "/bundle";
    compat_mkdir(content_dir.c_str());
    ASSERT_TRUE(write_file(content_dir + "/bundle.gguf", "abc"), "Should write archive model");
    ASSERT_TRUE(write_file(content_dir + "/tokenizer.json", "{}"), "Should write tokenizer");

    std::string archive_path = archive_dir + "/bundle.tar.gz";
    std::string cmd = "tar czf \"" + archive_path + "\" -C \"" + archive_dir + "\" bundle";
    ASSERT_TRUE(system(cmd.c_str()) == 0, "Should create model archive");

    std::string dest_dir = create_temp_dir("resolve_archive_dest");
    ASSERT_TRUE(!dest_dir.empty(), "Should create destination dir");

    const char* required[] = {"*.gguf", "tokenizer.json"};
    rac_expected_model_files_t expected = {};
    expected.required_patterns = required;
    expected.required_pattern_count = 2;

    rac_model_info_t model =
        make_test_model("bundle", RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF);
    model.artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
    model.artifact_info.archive_type = RAC_ARCHIVE_TYPE_TAR_GZ;
    model.artifact_info.archive_structure = RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
    model.artifact_info.expected_files = &expected;

    rac_model_extraction_result_t result = {};
    rac_result_t rc = rac_extract_model_archive_native(
        archive_path.c_str(), dest_dir.c_str(), &model,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", nullptr,
        nullptr, nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Archive extraction and model resolution should succeed");
    ASSERT_EQ(result.archive_type, RAC_ARCHIVE_TYPE_TAR_GZ, "Archive type should be detected");
    ASSERT_TRUE(result.extraction.files_extracted >= 2, "Should extract model and tokenizer");
    ASSERT_TRUE(result.resolution.primary_model_path != nullptr,
                "Resolved primary path should be populated");
    ASSERT_TRUE(std::string(result.resolution.primary_model_path).find("bundle.gguf") !=
                    std::string::npos,
                "Resolved primary path should point to extracted GGUF");
    rac_model_extraction_result_free(&result);
    remove_dir(archive_dir);
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
    compat_mkdir(content_dir.c_str());
    compat_mkdir(macosx_dir.c_str());

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
    compat_mkdir(content_dir.c_str());
    compat_mkdir(macosx_dir.c_str());

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
    suite.add("resolve_single_file_with_checksum", test_resolve_single_file_with_checksum);
    suite.add("resolve_companion_files", test_resolve_companion_files);
    suite.add("resolve_missing_required_optional_allowed",
              test_resolve_missing_required_optional_allowed);
    suite.add("resolve_file_descriptor_required", test_resolve_file_descriptor_required);
    suite.add("resolve_checksum_mismatch", test_resolve_checksum_mismatch);
    suite.add("extract_and_resolve_archive", test_extract_and_resolve_archive);
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
