/**
 * @file test_download_orchestrator.cpp
 * @brief Unit tests for download orchestrator utilities.
 *
 * Tests rac_find_model_path_after_extraction(), rac_download_compute_destination(),
 * and rac_download_requires_extraction() from rac_download_orchestrator.h.
 *
 * No ML backend or platform adapter needed — these are pure utility functions.
 */

#include "test_common.h"

#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include "rac/core/rac_platform_compat.h"

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#define getpid _getpid
#else
#include <unistd.h>
#endif

// =============================================================================
// Test helpers
// =============================================================================

/** Create a unique temporary directory for test artifacts. */
static std::string create_temp_dir(const std::string& suffix) {
#ifdef _WIN32
    char tmp_path[MAX_PATH];
    GetTempPathA(MAX_PATH, tmp_path);
    char tmp_dir[MAX_PATH];
    snprintf(tmp_dir, sizeof(tmp_dir), "%srac_dl_test_%s_%d", tmp_path, suffix.c_str(), getpid());
    _mkdir(tmp_dir);
    return std::string(tmp_dir);
#else
    char tmpl[256];
    snprintf(tmpl, sizeof(tmpl), "/tmp/rac_dl_test_%s_XXXXXX", suffix.c_str());
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

/** Create a directory (like mkdir -p). */
static void mkdir_p(const std::string& path) {
#ifdef _WIN32
    // Windows `mkdir` creates intermediate dirs automatically; no -p equivalent needed.
    std::string cmd = "mkdir \"" + path + "\" 2>nul";
#else
    std::string cmd = "mkdir -p \"" + path + "\"";
#endif
    system(cmd.c_str());
}

/** Write a dummy file. */
static void write_dummy_file(const std::string& path, const std::string& content = "model data") {
    std::ofstream f(path, std::ios::binary);
    f << content;
}

// =============================================================================
// Tests: rac_download_requires_extraction
// =============================================================================

static TestResult test_requires_extraction_tar_gz() {
    TestResult r;
    r.test_name = "requires_extraction_tar_gz";

    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.tar.gz") == RAC_TRUE,
                ".tar.gz should require extraction");
    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.tgz") == RAC_TRUE,
                ".tgz should require extraction");

    r.passed = true;
    return r;
}

static TestResult test_requires_extraction_tar_bz2() {
    TestResult r;
    r.test_name = "requires_extraction_tar_bz2";

    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.tar.bz2") == RAC_TRUE,
                ".tar.bz2 should require extraction");
    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.tbz2") == RAC_TRUE,
                ".tbz2 should require extraction");

    r.passed = true;
    return r;
}

static TestResult test_requires_extraction_zip() {
    TestResult r;
    r.test_name = "requires_extraction_zip";

    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.zip") == RAC_TRUE,
                ".zip should require extraction");

    r.passed = true;
    return r;
}

static TestResult test_requires_extraction_no_archive() {
    TestResult r;
    r.test_name = "requires_extraction_no_archive";

    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.gguf") == RAC_FALSE,
                ".gguf should NOT require extraction");
    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.onnx") == RAC_FALSE,
                ".onnx should NOT require extraction");
    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.bin") == RAC_FALSE,
                ".bin should NOT require extraction");
    ASSERT_TRUE(rac_download_requires_extraction(nullptr) == RAC_FALSE,
                "NULL URL should NOT require extraction");

    r.passed = true;
    return r;
}

static TestResult test_requires_extraction_url_with_query() {
    TestResult r;
    r.test_name = "requires_extraction_url_with_query";

    ASSERT_TRUE(
        rac_download_requires_extraction("https://example.com/model.tar.gz?token=abc") == RAC_TRUE,
        ".tar.gz with query string should require extraction");
    ASSERT_TRUE(
        rac_download_requires_extraction("https://example.com/model.gguf?v=2") == RAC_FALSE,
        ".gguf with query string should NOT require extraction");

    r.passed = true;
    return r;
}

// =============================================================================
// Tests: rac_find_model_path_after_extraction
// =============================================================================

static TestResult test_find_model_single_gguf() {
    TestResult r;
    r.test_name = "find_model_single_gguf";

    std::string dir = create_temp_dir("gguf");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // Create a single .gguf file at root
    write_dummy_file(dir + "/llama-7b.gguf");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED, RAC_FRAMEWORK_LLAMACPP,
        RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should find model path");

    std::string found(out_path);
    ASSERT_TRUE(found.find("llama-7b.gguf") != std::string::npos,
                "Should find the .gguf file");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_nested_gguf() {
    TestResult r;
    r.test_name = "find_model_nested_gguf";

    std::string dir = create_temp_dir("nested_gguf");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // Create a .gguf file nested one level deep (common archive pattern)
    mkdir_p(dir + "/model-folder");
    write_dummy_file(dir + "/model-folder/model.gguf");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED, RAC_FRAMEWORK_LLAMACPP,
        RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should find nested model path");

    std::string found(out_path);
    ASSERT_TRUE(found.find("model.gguf") != std::string::npos,
                "Should find the nested .gguf file");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_nested_directory() {
    TestResult r;
    r.test_name = "find_model_nested_directory";

    std::string dir = create_temp_dir("nested_dir");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // Sherpa-ONNX pattern: archive extracts to a single subdirectory
    mkdir_p(dir + "/vits-piper-en_US-libritts_r-medium");
    write_dummy_file(dir + "/vits-piper-en_US-libritts_r-medium/model.onnx");
    write_dummy_file(dir + "/vits-piper-en_US-libritts_r-medium/tokens.txt");
    write_dummy_file(dir + "/vits-piper-en_US-libritts_r-medium/lexicon.txt");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY, RAC_FRAMEWORK_ONNX,
        RAC_MODEL_FORMAT_ONNX, out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should find nested directory");

    std::string found(out_path);
    ASSERT_TRUE(found.find("vits-piper-en_US-libritts_r-medium") != std::string::npos,
                "Should return the nested subdirectory path");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_directory_based_onnx() {
    TestResult r;
    r.test_name = "find_model_directory_based_onnx";

    std::string dir = create_temp_dir("onnx_dir");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // ONNX directory-based model: multiple files at root
    write_dummy_file(dir + "/encoder.onnx");
    write_dummy_file(dir + "/decoder.onnx");
    write_dummy_file(dir + "/tokens.txt");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED, RAC_FRAMEWORK_ONNX,
        RAC_MODEL_FORMAT_ONNX, out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should succeed for directory-based model");

    // For ONNX directory-based, should return the directory itself
    std::string found(out_path);
    ASSERT_TRUE(found == dir, "Should return the extraction directory for directory-based ONNX");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_skips_hidden_files() {
    TestResult r;
    r.test_name = "find_model_skips_hidden_files";

    std::string dir = create_temp_dir("hidden");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // Create macOS resource fork and hidden files (should be ignored)
    write_dummy_file(dir + "/._model.gguf");
    mkdir_p(dir + "/.DS_Store");
    mkdir_p(dir + "/__MACOSX");
    // Real model in subdirectory
    mkdir_p(dir + "/model-dir");
    write_dummy_file(dir + "/model-dir/real-model.gguf");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED, RAC_FRAMEWORK_LLAMACPP,
        RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should find real model file");

    std::string found(out_path);
    ASSERT_TRUE(found.find("real-model.gguf") != std::string::npos,
                "Should find the real model, not hidden files");
    ASSERT_TRUE(found.find("._model") == std::string::npos,
                "Should NOT match macOS resource fork files");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_unknown_structure() {
    TestResult r;
    r.test_name = "find_model_unknown_structure";

    std::string dir = create_temp_dir("unknown");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    // Single .bin file at root
    write_dummy_file(dir + "/model.bin");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_UNKNOWN, RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_BIN,
        out_path, sizeof(out_path));

    ASSERT_TRUE(result == RAC_SUCCESS, "Should find model with unknown structure");

    std::string found(out_path);
    ASSERT_TRUE(found.find("model.bin") != std::string::npos,
                "Should find the .bin model file");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_empty_dir() {
    TestResult r;
    r.test_name = "find_model_empty_dir";

    std::string dir = create_temp_dir("empty");
    ASSERT_TRUE(!dir.empty(), "Failed to create temp dir");

    char out_path[4096];
    rac_result_t result = rac_find_model_path_after_extraction(
        dir.c_str(), RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED, RAC_FRAMEWORK_LLAMACPP,
        RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path));

    // Should still succeed (returns the directory itself as fallback)
    ASSERT_TRUE(result == RAC_SUCCESS, "Should succeed even for empty dir");

    remove_dir(dir);
    r.passed = true;
    return r;
}

static TestResult test_find_model_null_args() {
    TestResult r;
    r.test_name = "find_model_null_args";

    char out_path[4096];

    ASSERT_TRUE(rac_find_model_path_after_extraction(nullptr, RAC_ARCHIVE_STRUCTURE_UNKNOWN,
                                                      RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF,
                                                      out_path, sizeof(out_path)) ==
                    RAC_ERROR_INVALID_ARGUMENT,
                "NULL extracted_dir should return INVALID_ARGUMENT");

    ASSERT_TRUE(rac_find_model_path_after_extraction("/tmp", RAC_ARCHIVE_STRUCTURE_UNKNOWN,
                                                      RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF,
                                                      nullptr, 0) == RAC_ERROR_INVALID_ARGUMENT,
                "NULL out_path should return INVALID_ARGUMENT");

    r.passed = true;
    return r;
}

// =============================================================================
// Tests: rac_download_compute_destination
// =============================================================================

static TestResult test_compute_destination_needs_base_dir() {
    TestResult r;
    r.test_name = "compute_destination_needs_base_dir";

    // Set up base dir for model paths
    std::string base_dir = create_temp_dir("base");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");

    rac_model_paths_set_base_dir(base_dir.c_str());

    char out_path[4096];
    rac_bool_t needs_extraction = RAC_FALSE;

    rac_result_t result = rac_download_compute_destination(
        "test-model", "https://example.com/model.gguf", RAC_FRAMEWORK_LLAMACPP,
        RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path), &needs_extraction);

    ASSERT_TRUE(result == RAC_SUCCESS, "Should compute destination successfully");
    ASSERT_TRUE(needs_extraction == RAC_FALSE, ".gguf should not need extraction");

    std::string path(out_path);
    ASSERT_TRUE(path.find("model.gguf") != std::string::npos,
                "Should contain the filename");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_compute_destination_archive() {
    TestResult r;
    r.test_name = "compute_destination_archive";

    std::string base_dir = create_temp_dir("base_archive");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");

    rac_model_paths_set_base_dir(base_dir.c_str());

    char out_path[4096];
    rac_bool_t needs_extraction = RAC_FALSE;

    rac_result_t result = rac_download_compute_destination(
        "sherpa-model", "https://example.com/sherpa-model.tar.bz2", RAC_FRAMEWORK_ONNX,
        RAC_MODEL_FORMAT_ONNX, out_path, sizeof(out_path), &needs_extraction);

    ASSERT_TRUE(result == RAC_SUCCESS, "Should compute destination for archive");
    ASSERT_TRUE(needs_extraction == RAC_TRUE, ".tar.bz2 should need extraction");

    std::string path(out_path);
    ASSERT_TRUE(path.find("Downloads") != std::string::npos || path.find("download") != std::string::npos,
                "Archive should download to downloads/temp directory");
    ASSERT_TRUE(path.find(".tar.bz2") != std::string::npos,
                "Should preserve archive extension");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_compute_destination_null_args() {
    TestResult r;
    r.test_name = "compute_destination_null_args";

    char out_path[4096];
    rac_bool_t needs_extraction = RAC_FALSE;

    ASSERT_TRUE(rac_download_compute_destination(nullptr, "url", RAC_FRAMEWORK_LLAMACPP,
                                                  RAC_MODEL_FORMAT_GGUF, out_path,
                                                  sizeof(out_path),
                                                  &needs_extraction) == RAC_ERROR_INVALID_ARGUMENT,
                "NULL model_id should return INVALID_ARGUMENT");

    r.passed = true;
    return r;
}

// =============================================================================
// Test runner
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("download_orchestrator");

    // rac_download_requires_extraction
    suite.add("requires_extraction_tar_gz", test_requires_extraction_tar_gz);
    suite.add("requires_extraction_tar_bz2", test_requires_extraction_tar_bz2);
    suite.add("requires_extraction_zip", test_requires_extraction_zip);
    suite.add("requires_extraction_no_archive", test_requires_extraction_no_archive);
    suite.add("requires_extraction_url_with_query", test_requires_extraction_url_with_query);

    // rac_find_model_path_after_extraction
    suite.add("find_model_single_gguf", test_find_model_single_gguf);
    suite.add("find_model_nested_gguf", test_find_model_nested_gguf);
    suite.add("find_model_nested_directory", test_find_model_nested_directory);
    suite.add("find_model_directory_based_onnx", test_find_model_directory_based_onnx);
    suite.add("find_model_skips_hidden_files", test_find_model_skips_hidden_files);
    suite.add("find_model_unknown_structure", test_find_model_unknown_structure);
    suite.add("find_model_empty_dir", test_find_model_empty_dir);
    suite.add("find_model_null_args", test_find_model_null_args);

    // rac_download_compute_destination
    suite.add("compute_destination_needs_base_dir", test_compute_destination_needs_base_dir);
    suite.add("compute_destination_archive", test_compute_destination_archive);
    suite.add("compute_destination_null_args", test_compute_destination_null_args);

    return suite.run(argc, argv);
}
