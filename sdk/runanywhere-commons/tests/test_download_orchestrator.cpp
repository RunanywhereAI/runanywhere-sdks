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

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <utility>

#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/core/rac_core.h"

#ifdef RAC_HAVE_PROTOBUF
#include "download_service.pb.h"
#endif

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
    return {result};
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

    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.tar.gz?token=abc") ==
                    RAC_TRUE,
                ".tar.gz with query string should require extraction");
    ASSERT_TRUE(rac_download_requires_extraction("https://example.com/model.gguf?v=2") == RAC_FALSE,
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
    ASSERT_TRUE(found.find("llama-7b.gguf") != std::string::npos, "Should find the .gguf file");

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
    ASSERT_TRUE(found.find("model.gguf") != std::string::npos, "Should find the nested .gguf file");

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
    ASSERT_TRUE(found.find("model.bin") != std::string::npos, "Should find the .bin model file");

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
    ASSERT_TRUE(path.find("model.gguf") != std::string::npos, "Should contain the filename");

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
    ASSERT_TRUE(path.find("Downloads") != std::string::npos ||
                    path.find("download") != std::string::npos,
                "Archive should download to downloads/temp directory");
    ASSERT_TRUE(path.find(".tar.bz2") != std::string::npos, "Should preserve archive extension");

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
                                                 RAC_MODEL_FORMAT_GGUF, out_path, sizeof(out_path),
                                                 &needs_extraction) == RAC_ERROR_INVALID_ARGUMENT,
                "NULL model_id should return INVALID_ARGUMENT");

    r.passed = true;
    return r;
}

#ifdef RAC_HAVE_PROTOBUF
// =============================================================================
// Tests: proto-byte download workflow ABI
// =============================================================================

namespace {
namespace rav1 = ::runanywhere::v1;

std::vector<uint8_t> fake_payload(size_t n) {
    std::vector<uint8_t> bytes(n);
    for (size_t i = 0; i < n; ++i) {
        bytes[i] = static_cast<uint8_t>((i * 13) & 0xff);
    }
    return bytes;
}

struct FakeTransport {
    std::vector<uint8_t> payload = fake_payload(static_cast<size_t>(256) * 1024);
    int sleep_ms_per_chunk = 0;
    // Flaky-mode accounting for "/flaky" URLs (transient-retry coverage). Each
    // distinct URL fails its FIRST fresh-stream attempt with a mid-transfer
    // network drop (after flushing a prefix to the ".part" sidecar), then every
    // subsequent attempt — a resume — succeeds. Shared across the parallel
    // worker threads, so the bookkeeping is mutex-guarded and observable.
    std::mutex flaky_mutex;
    std::set<std::string> flaky_urls_failed_once;  // URLs that already took their fail
    int stream_attempts = 0;                       // total fresh-stream calls seen
    int resume_attempts = 0;                        // total resume calls seen
};

// The prefix a "/flaky" stream flushes to disk before the simulated drop. Small
// enough to leave a real resume tail; a multiple of the 8 KiB chunk size so the
// partial ends on a chunk boundary (mirrors a socket teardown between chunks).
constexpr size_t kFlakyPrefixBytes = static_cast<size_t>(64) * 1024;

rac_bool_t fake_send_chunk(rac_http_body_chunk_fn cb, void* cb_user_data,
                           const std::vector<uint8_t>& payload, size_t start, size_t chunk_size,
                           int sleep_ms) {
    uint64_t delivered = 0;
    for (size_t offset = start; offset < payload.size(); offset += chunk_size) {
        size_t n = std::min(chunk_size, payload.size() - offset);
        delivered += n;
        if (cb(payload.data() + offset, n, delivered, static_cast<uint64_t>(payload.size() - start),
               cb_user_data) == RAC_FALSE) {
            return RAC_FALSE;
        }
        if (sleep_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
        }
    }
    return RAC_TRUE;
}

// Deliver only [start, start+limit) of the payload, then stop. Returns true if
// the whole limited range was delivered without the callback cancelling — used
// to flush a partial prefix before a simulated network drop.
bool fake_send_prefix(rac_http_body_chunk_fn cb, void* cb_user_data,
                      const std::vector<uint8_t>& payload, size_t start, size_t limit,
                      size_t chunk_size) {
    const size_t end = std::min(payload.size(), start + limit);
    uint64_t delivered = 0;
    for (size_t offset = start; offset < end; offset += chunk_size) {
        size_t n = std::min(chunk_size, end - offset);
        delivered += n;
        if (cb(payload.data() + offset, n, delivered,
               static_cast<uint64_t>(payload.size() - start), cb_user_data) == RAC_FALSE) {
            return false;
        }
    }
    return true;
}

rac_result_t fake_request_send(void*, const rac_http_request_t*, rac_http_response_t* out_resp) {
    if (!out_resp) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_resp->status = 200;
    return RAC_SUCCESS;
}

rac_result_t fake_request_stream(void* user_data, const rac_http_request_t* req,
                                 rac_http_body_chunk_fn cb, void* cb_user_data,
                                 rac_http_response_t* out_resp_meta) {
    auto* fake = static_cast<FakeTransport*>(user_data);
    if (!fake || !req || !req->url || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::string url(req->url);
    if (url.find("/network") != std::string::npos) {
        return RAC_ERROR_NETWORK_ERROR;
    }
    if (url.find("/fail") != std::string::npos) {
        out_resp_meta->status = 500;
        return RAC_SUCCESS;
    }
    // Transient-failure simulation: the first fresh-stream attempt for each
    // distinct "/flaky" URL flushes a prefix to the ".part" sidecar and then
    // reports a network drop, so the orchestrator's bounded resume-retry loop
    // has to re-drive the transfer (via the resume path) to complete.
    if (url.find("/flaky") != std::string::npos) {
        bool should_fail = false;
        {
            std::lock_guard<std::mutex> lock(fake->flaky_mutex);
            fake->stream_attempts++;
            should_fail = fake->flaky_urls_failed_once.insert(url).second;
        }
        if (should_fail) {
            out_resp_meta->status = 200;
            // Flush a real prefix, then drop the connection mid-transfer.
            (void)fake_send_prefix(cb, cb_user_data, fake->payload, 0, kFlakyPrefixBytes, 8192);
            return RAC_ERROR_NETWORK_ERROR;
        }
        // A retried "/flaky" fresh stream (no partial on disk yet) succeeds.
        out_resp_meta->status = 200;
        return fake_send_chunk(cb, cb_user_data, fake->payload, 0, 8192,
                               fake->sleep_ms_per_chunk) == RAC_TRUE
                   ? RAC_SUCCESS
                   : RAC_ERROR_CANCELLED;
    }
    out_resp_meta->status = 200;
    return fake_send_chunk(cb, cb_user_data, fake->payload, 0, 8192, fake->sleep_ms_per_chunk) ==
                   RAC_TRUE
               ? RAC_SUCCESS
               : RAC_ERROR_CANCELLED;
}

rac_result_t fake_request_resume(void* user_data, const rac_http_request_t* req,
                                 uint64_t resume_from_byte, rac_http_body_chunk_fn cb,
                                 void* cb_user_data, rac_http_response_t* out_resp_meta) {
    auto* fake = static_cast<FakeTransport*>(user_data);
    if (!fake || !req || !req->url || !cb || !out_resp_meta) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    {
        std::lock_guard<std::mutex> lock(fake->flaky_mutex);
        fake->resume_attempts++;
    }
    out_resp_meta->status = 206;
    size_t start = std::min<size_t>(static_cast<size_t>(resume_from_byte), fake->payload.size());
    return fake_send_chunk(cb, cb_user_data, fake->payload, start, 8192,
                           fake->sleep_ms_per_chunk) == RAC_TRUE
               ? RAC_SUCCESS
               : RAC_ERROR_CANCELLED;
}

rac_http_transport_ops_t fake_ops = {
    fake_request_send, fake_request_stream, fake_request_resume, nullptr, nullptr,
};

struct ScopedFakeTransport {
    explicit ScopedFakeTransport(FakeTransport* fake) {
        rac_http_transport_register(&fake_ops, fake);
    }
    ~ScopedFakeTransport() { rac_http_transport_register(nullptr, nullptr); }
};

std::string serialize_msg(const google::protobuf::MessageLite& msg) {
    std::string bytes;
    (void)msg.SerializeToString(&bytes);
    return bytes;
}

bool parse_plan(const rac_proto_buffer_t& buffer, rav1::DownloadPlanResult* out) {
    return out != nullptr && buffer.status == RAC_SUCCESS && buffer.data != nullptr &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_start(const rac_proto_buffer_t& buffer, rav1::DownloadStartResult* out) {
    return out != nullptr && buffer.status == RAC_SUCCESS && buffer.data != nullptr &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_cancel(const rac_proto_buffer_t& buffer, rav1::DownloadCancelResult* out) {
    return out != nullptr && buffer.status == RAC_SUCCESS && buffer.data != nullptr &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_resume(const rac_proto_buffer_t& buffer, rav1::DownloadResumeResult* out) {
    return out != nullptr && buffer.status == RAC_SUCCESS && buffer.data != nullptr &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

rav1::ModelInfo make_download_model(const std::string& model_id, const std::string& url,
                                    int64_t size) {
    rav1::ModelInfo model;
    model.set_id(model_id);
    model.set_download_url(url);
    model.set_download_size_bytes(size);
    model.set_framework(rav1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_format(rav1::MODEL_FORMAT_GGUF);
    return model;
}

bool make_plan(const std::string& model_id, const std::string& url, int64_t size,
               rav1::DownloadPlanResult* out_plan) {
    rav1::DownloadPlanRequest request;
    request.set_model_id(model_id);
    *request.mutable_model() = make_download_model(model_id, url, size);
    std::string bytes = serialize_msg(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_download_plan_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                              bytes.size(), &buffer);
    bool ok = (rc == RAC_SUCCESS && parse_plan(buffer, out_plan));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool start_from_plan(const rav1::DownloadPlanResult& plan, bool resume,
                     rav1::DownloadStartResult* out_start) {
    rav1::DownloadStartRequest request;
    request.set_model_id(plan.model_id());
    *request.mutable_plan() = plan;
    request.set_resume(resume);
    std::string bytes = serialize_msg(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_download_start_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                               bytes.size(), &buffer);
    bool ok = (rc == RAC_SUCCESS && parse_start(buffer, out_start));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool poll_progress(const std::string& task_id, rav1::DownloadProgress* out_progress) {
    rav1::DownloadSubscribeRequest request;
    request.set_task_id(task_id);
    std::string bytes = serialize_msg(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_download_progress_poll_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buffer);
    bool ok = rc == RAC_SUCCESS && buffer.status == RAC_SUCCESS && buffer.data != nullptr &&
              out_progress->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool wait_for_terminal(const std::string& task_id, rav1::DownloadProgress* out_progress) {
    for (int i = 0; i < 250; ++i) {
        if (poll_progress(task_id, out_progress)) {
            auto state = out_progress->state();
            if (state == rav1::DOWNLOAD_STATE_COMPLETED || state == rav1::DOWNLOAD_STATE_FAILED ||
                state == rav1::DOWNLOAD_STATE_CANCELLED) {
                return true;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return false;
}

// Like wait_for_terminal but with a caller-chosen budget. The bounded
// resume-retry loop (execute_stream_with_retry) backs off 500ms + 1s + 2s
// between its 4 attempts, so a permanently-failing transfer needs >3.5s to
// exhaust the budget and terminate — longer than the default 2.5s poll.
bool wait_for_terminal_ms(const std::string& task_id, int max_wait_ms,
                          rav1::DownloadProgress* out_progress) {
    const int iterations = std::max(1, max_wait_ms / 10);
    for (int i = 0; i < iterations; ++i) {
        if (poll_progress(task_id, out_progress)) {
            auto state = out_progress->state();
            if (state == rav1::DOWNLOAD_STATE_COMPLETED || state == rav1::DOWNLOAD_STATE_FAILED ||
                state == rav1::DOWNLOAD_STATE_CANCELLED) {
                return true;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return false;
}

bool wait_for_state(const std::string& task_id, rav1::DownloadState expected,
                    rav1::DownloadProgress* out_progress) {
    for (int i = 0; i < 250; ++i) {
        if (poll_progress(task_id, out_progress) && out_progress->state() == expected) {
            return true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return false;
}

struct ProgressCapture {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<rav1::DownloadProgress> events;
};

void progress_capture_cb(const uint8_t* bytes, size_t size, void* user_data);

struct ScopedProgressCallback {
    explicit ScopedProgressCallback(ProgressCapture* capture) {
        rac_download_set_progress_proto_callback(progress_capture_cb, capture);
    }
    ~ScopedProgressCallback() { rac_download_set_progress_proto_callback(nullptr, nullptr); }
};

void progress_capture_cb(const uint8_t* bytes, size_t size, void* user_data) {
    auto* capture = static_cast<ProgressCapture*>(user_data);
    rav1::DownloadProgress progress;
    if (!capture || !bytes || !progress.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(capture->mutex);
        capture->events.push_back(progress);
    }
    capture->cv.notify_all();
}

bool wait_for_any_progress(ProgressCapture* capture) {
    std::unique_lock<std::mutex> lock(capture->mutex);
    return capture->cv.wait_for(lock, std::chrono::seconds(2),
                                [&] { return !capture->events.empty(); });
}

bool wait_for_downloaded_progress(ProgressCapture* capture) {
    std::unique_lock<std::mutex> lock(capture->mutex);
    return capture->cv.wait_for(lock, std::chrono::seconds(2), [&] {
        for (const auto& event : capture->events) {
            if (event.bytes_downloaded() > 0) {
                return true;
            }
        }
        return false;
    });
}

}  // namespace

static TestResult test_proto_plan_single_file() {
    TestResult r;
    r.test_name = "proto_plan_single_file";

    std::string base_dir = create_temp_dir("proto_plan");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-plan", "http://fake/success/model.gguf", 4096, &plan),
                "Plan should serialize and parse");
    ASSERT_TRUE(plan.can_start(), "Plan should be startable");
    ASSERT_TRUE(plan.model_id() == "proto-model-plan", "Plan should preserve model_id");
    ASSERT_TRUE(plan.files_size() == 1, "Plan should contain one file");
    ASSERT_TRUE(plan.total_bytes() == 4096, "Plan should preserve expected bytes");
    ASSERT_TRUE(plan.files(0).destination_path().find("model.gguf") != std::string::npos,
                "Plan should include a concrete destination path");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_plan_multifile_uses_declared_aggregate_when_head_unknown() {
    TestResult r;
    r.test_name = "proto_plan_multifile_uses_declared_aggregate_when_head_unknown";

    // The fake HEAD transport deliberately returns no Content-Length. A
    // curated multi-file model with an exact aggregate must remain startable
    // even when legacy descriptors do not carry their per-file sizes.
    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);

    std::string base_dir = create_temp_dir("proto_multifile_aggregate");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    constexpr int64_t kCanaryBundleBytes = 207170046;
    rav1::DownloadPlanRequest request;
    request.set_model_id("canary-aggregate-fallback");
    request.set_available_storage_bytes(1LL << 30);  // 1 GiB
    rav1::ModelInfo* model = request.mutable_model();
    model->set_id(request.model_id());
    model->set_framework(rav1::INFERENCE_FRAMEWORK_SHERPA);
    model->set_format(rav1::MODEL_FORMAT_ONNX);

    for (const char* filename : {"encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"}) {
        rav1::ModelFileDescriptor* file = model->mutable_multi_file()->add_files();
        file->set_url(std::string("http://fake/no-content-length/") + filename);
        file->set_filename(filename);
        file->set_is_required(true);
    }

    std::string unknown_bytes = serialize_msg(request);
    rac_proto_buffer_t unknown_buffer;
    rac_proto_buffer_init(&unknown_buffer);
    ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(unknown_bytes.data()),
                                        unknown_bytes.size(), &unknown_buffer) == RAC_SUCCESS,
                "Unknown-size plan call should return a result proto");
    rav1::DownloadPlanResult unknown_plan;
    ASSERT_TRUE(parse_plan(unknown_buffer, &unknown_plan), "Unknown-size plan should parse");
    rac_proto_buffer_free(&unknown_buffer);
    ASSERT_TRUE(!unknown_plan.can_start(), "Missing per-file and aggregate sizes must fail closed");
    ASSERT_TRUE(unknown_plan.total_bytes() == 0, "Unknown-size plan must not invent a total");

    model->set_download_size_bytes(kCanaryBundleBytes);
    std::string bytes = serialize_msg(request);
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                        bytes.size(), &buffer) == RAC_SUCCESS,
                "Plan call should return a result proto");
    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(parse_plan(buffer, &plan), "Plan should parse");
    rac_proto_buffer_free(&buffer);

    ASSERT_TRUE(plan.can_start(), "Declared aggregate should keep the multi-file plan startable");
    ASSERT_TRUE(plan.total_bytes() == kCanaryBundleBytes,
                "Plan should use the model's declared aggregate size");
    ASSERT_TRUE(plan.files_size() == 3, "Plan should preserve every file");
    for (const auto& file : plan.files()) {
        ASSERT_TRUE(file.expected_bytes() == 0,
                    "Aggregate fallback must not invent a per-file expected size");
    }
    bool aggregate_warning = false;
    for (const auto& warning : plan.warnings()) {
        aggregate_warning = aggregate_warning ||
                            warning.find("using model download_size_bytes") != std::string::npos;
    }
    ASSERT_TRUE(aggregate_warning, "Plan should disclose the aggregate-size fallback");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_plan_invalid_url() {
    TestResult r;
    r.test_name = "proto_plan_invalid_url";

    std::string base_dir = create_temp_dir("proto_invalid");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-invalid", "ftp://fake/model.gguf", 100, &plan),
                "Invalid URL plan should still return a result proto");
    ASSERT_TRUE(!plan.can_start(), "Invalid URL should not be startable");
    ASSERT_TRUE(plan.error_message().find("http") != std::string::npos,
                "Invalid URL should explain http(s) requirement");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_plan_resume_metadata() {
    TestResult r;
    r.test_name = "proto_plan_resume_metadata";

    std::string base_dir = create_temp_dir("proto_resume_meta");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    const std::string model_id = "proto-model-resume-meta";
    const std::string model_url = "http://fake/success/model.gguf";
    char destination[4096];
    rac_bool_t needs_extraction = RAC_FALSE;
    ASSERT_TRUE(rac_download_compute_destination(model_id.c_str(), model_url.c_str(),
                                                 RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF,
                                                 destination, sizeof(destination),
                                                 &needs_extraction) == RAC_SUCCESS,
                "Destination should compute");
    std::string dest_path(destination);
    auto slash = dest_path.rfind('/');
    if (slash != std::string::npos) {
        mkdir_p(dest_path.substr(0, slash));
    }
    // Resumable bytes live in the ".part" sidecar the writer streams into until
    // its finalize rename; the final path only appears once the download is
    // complete. Seed the partial there so the planner can detect it for resume.
    write_dummy_file(dest_path + ".part", std::string(128, 'p'));

    rav1::DownloadPlanRequest request;
    request.set_model_id(model_id);
    *request.mutable_model() = make_download_model(model_id, model_url, 1024);
    request.mutable_model()->set_checksum_sha256(std::string(64, 'a'));
    request.set_resume_existing(true);
    request.set_validate_existing_bytes(true);
    request.set_verify_checksums(true);
    request.set_storage_namespace("cpp04");
    request.set_required_free_bytes_after_download(256);
    // Free space must clear the planner's free-space margin (a 128 MiB floor for
    // FS metadata / extraction temp), so use a realistic device value here — the
    // tiny synthetic 1 KiB model is otherwise dwarfed by that margin and would
    // trip the insufficient-storage gate this test isn't exercising.
    request.set_available_storage_bytes(1LL << 30);  // 1 GiB
    std::string bytes = serialize_msg(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                        bytes.size(), &buffer) == RAC_SUCCESS,
                "Plan call should succeed");
    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(parse_plan(buffer, &plan), "Plan should parse");
    rac_proto_buffer_free(&buffer);

    ASSERT_TRUE(plan.can_start(), "Validated partial bytes should be startable");
    ASSERT_TRUE(plan.can_resume(), "Plan should be resumable");
    ASSERT_TRUE(plan.resume_from_bytes() == 128, "Resume offset should match partial bytes");
    ASSERT_TRUE(!plan.resume_token().empty(), "Plan should include a logical resume token");
    ASSERT_TRUE(plan.storage_namespace() == "cpp04", "Plan should preserve namespace");
    ASSERT_TRUE(plan.required_free_bytes_after_download() == 256,
                "Plan should preserve post-download free-space requirement");
    ASSERT_TRUE(plan.files_size() == 1, "Plan should include one file");
    ASSERT_TRUE(plan.files(0).is_resume_candidate(), "File should be marked resumable");
    ASSERT_TRUE(plan.files(0).checksum_sha256() == std::string(64, 'a'),
                "Plan should carry checksum validation metadata");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

// Oversized partials (existing bytes > declared expected size) are
// self-healed by the planner when validate_existing_bytes is requested: the
// stale partial is deleted and the entry replanned as a fresh download. The
// plan fails with OVERSIZE_PARTIAL_BYTES only when that deletion itself
// fails (see seed_resume_candidate in download_orchestrator.cpp).
static TestResult test_proto_plan_self_heals_oversized_existing_bytes() {
    TestResult r;
    r.test_name = "proto_plan_self_heals_oversized_existing_bytes";

    std::string base_dir = create_temp_dir("proto_bad_existing");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    const std::string model_id = "proto-model-bad-existing";
    const std::string model_url = "http://fake/success/model.gguf";
    char destination[4096];
    rac_bool_t needs_extraction = RAC_FALSE;
    ASSERT_TRUE(rac_download_compute_destination(model_id.c_str(), model_url.c_str(),
                                                 RAC_FRAMEWORK_LLAMACPP, RAC_MODEL_FORMAT_GGUF,
                                                 destination, sizeof(destination),
                                                 &needs_extraction) == RAC_SUCCESS,
                "Destination should compute");
    std::string dest_path(destination);
    auto slash = dest_path.rfind('/');
    if (slash != std::string::npos) {
        mkdir_p(dest_path.substr(0, slash));
    }
    // The oversized stale bytes live in the ".part" sidecar (the resumable-partial
    // location); the planner self-heals by deleting that sidecar and replanning fresh.
    write_dummy_file(dest_path + ".part", std::string(256, 'p'));

    rav1::DownloadPlanRequest request;
    request.set_model_id(model_id);
    *request.mutable_model() = make_download_model(model_id, model_url, 128);
    request.set_resume_existing(true);
    request.set_validate_existing_bytes(true);
    std::string bytes = serialize_msg(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                        bytes.size(), &buffer) == RAC_SUCCESS,
                "Plan call should return a result proto");
    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(parse_plan(buffer, &plan), "Plan should parse");
    rac_proto_buffer_free(&buffer);

    ASSERT_TRUE(plan.can_start(), "Oversized partial should self-heal into a startable plan");
    ASSERT_TRUE(plan.files_size() == 1, "Plan should include one file");
    ASSERT_TRUE(!plan.files(0).is_resume_candidate(),
                "Healed entry must replan as a fresh download, not a resume");
    ASSERT_TRUE(plan.resume_from_bytes() == 0, "Fresh plan should not carry a resume offset");
    ASSERT_TRUE(!std::ifstream(dest_path + ".part").good(),
                "Stale oversized partial should be deleted");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

// security-privacy-storage-network-001 / pass2-syn-115 regression:
// Malicious descriptor.destination_path values ("../escape.gguf",
// "/etc/passwd", "..\\windows\\system32") must be rejected by the planner
// (destination_from_model_file → safe_descriptor_path_under), causing the
// emitted DownloadFilePlan.destination_path to fall back to a safe location
// rooted under the per-model storage folder. The plan must still be
// startable (the planner logs a warning and continues so a single malicious
// descriptor doesn't poison the rest of the multi-file plan).
static TestResult test_proto_plan_rejects_path_traversal_destination() {
    TestResult r;
    r.test_name = "proto_plan_rejects_path_traversal_destination";

    std::string base_dir = create_temp_dir("proto_pathtrav");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    char model_folder[4096];
    ASSERT_TRUE(rac_model_paths_get_model_folder("ptrav-model", RAC_FRAMEWORK_LLAMACPP,
                                                 model_folder, sizeof(model_folder)) == RAC_SUCCESS,
                "model folder should compute");
    std::string folder(model_folder);

    // Try several traversal vectors via descriptor.destination_path.
    const std::vector<std::string> malicious_paths = {
        "../escape.gguf",
        "../../escape.gguf",
        "subdir/../../escape.gguf",
        "/etc/passwd",
        "..\\windows\\system32\\evil.gguf",
        ".",
        "..",
        "",
    };

    for (const auto& bad_path : malicious_paths) {
        rav1::DownloadPlanRequest request;
        request.set_model_id("ptrav-model");
        rav1::ModelInfo* model = request.mutable_model();
        model->set_id("ptrav-model");
        model->set_download_url("http://fake/success/parent.tar.gz");
        model->set_framework(rav1::INFERENCE_FRAMEWORK_LLAMA_CPP);
        model->set_format(rav1::MODEL_FORMAT_GGUF);

        rav1::ExpectedModelFiles* expected = model->mutable_expected_files();
        rav1::ModelFileDescriptor* file = expected->add_files();
        file->set_url("http://fake/success/inner.gguf");
        file->set_filename("inner.gguf");
        file->set_is_required(true);
        if (!bad_path.empty()) {
            file->set_destination_path(bad_path);
        } else {
            // Force destination_path presence with an empty string by going
            // through the explicit setter; proto3 optional semantics mean
            // an unset value triggers a different branch.
            file->set_destination_path("");
        }

        std::string bytes = serialize_msg(request);
        rac_proto_buffer_t buffer;
        rac_proto_buffer_init(&buffer);
        ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                            bytes.size(), &buffer) == RAC_SUCCESS,
                    "Plan call should succeed regardless of malicious destination_path");
        rav1::DownloadPlanResult plan;
        ASSERT_TRUE(parse_plan(buffer, &plan), "Plan should parse");
        rac_proto_buffer_free(&buffer);

        ASSERT_TRUE(plan.files_size() == 1, "Plan should still emit one file plan");
        const std::string& planned = plan.files(0).destination_path();
        ASSERT_TRUE(!planned.empty(), "Planned destination_path must not be empty");
        // CRITICAL: the planned destination must stay under the per-model
        // storage folder. We do not allow lexical escapes like "../" or
        // absolute paths outside the storage root.
        ASSERT_TRUE(planned.find("..") == std::string::npos,
                    "Planned destination must not contain '..' traversal segments");
        ASSERT_TRUE(planned.rfind(folder, 0) == 0,
                    "Planned destination must remain rooted under model_folder");
        // Sanity: the original malicious string must not survive verbatim.
        if (!bad_path.empty()) {
            ASSERT_TRUE(planned != bad_path, "Planner must not echo the malicious path verbatim");
            ASSERT_TRUE(planned.find("escape.gguf") == std::string::npos ||
                            planned.rfind(folder, 0) == 0,
                        "If escape.gguf survives, it must be inside model_folder");
        }
    }

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

// Companion regression: rac_download_start_proto must skip plan entries whose
// destination_path contains traversal segments when callers bypass the
// trusted planner. is_traversal_safe_destination is the defensive gate.
static TestResult test_proto_start_skips_traversal_unsafe_plan_entry() {
    TestResult r;
    r.test_name = "proto_start_skips_traversal_unsafe_plan_entry";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);

    std::string base_dir = create_temp_dir("proto_start_trav");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    // Build a plan by hand that pretends to come from the trusted planner
    // but slips in a traversal-unsafe destination_path on its single file.
    rav1::DownloadPlanResult plan;
    plan.set_can_start(true);
    plan.set_model_id("ptrav-start");
    plan.set_total_bytes(static_cast<int64_t>(fake.payload.size()));
    rav1::DownloadFilePlan* f = plan.add_files();
    f->mutable_file()->set_url("http://fake/success/model.gguf");
    f->mutable_file()->set_filename("model.gguf");
    f->set_destination_path("/tmp/../../etc/passwd");
    f->set_expected_bytes(static_cast<int64_t>(fake.payload.size()));

    rav1::DownloadStartRequest request;
    request.set_model_id("ptrav-start");
    *request.mutable_plan() = plan;
    request.set_resume(false);

    std::string bytes = serialize_msg(request);
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_TRUE(rac_download_start_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                         bytes.size(), &buffer) == RAC_SUCCESS,
                "Start call should succeed");
    rav1::DownloadStartResult start;
    ASSERT_TRUE(parse_start(buffer, &start), "Start result should parse");
    rac_proto_buffer_free(&buffer);

    // With every entry skipped, start must report a clean rejection rather
    // than accepting a download targeted at /etc/passwd.
    ASSERT_TRUE(!start.accepted(),
                "Start must reject a plan whose only file has a traversal-unsafe path");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_start_no_adapter() {
    TestResult r;
    r.test_name = "proto_start_no_adapter";

    rac_http_transport_register(nullptr, nullptr);
    std::string base_dir = create_temp_dir("proto_no_adapter");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-no-adapter", "http://fake/success/model.gguf", 100, &plan),
                "Plan should succeed");

    rav1::DownloadStartResult start;
    ASSERT_TRUE(start_from_plan(plan, false, &start), "Start should return a result proto");
    ASSERT_TRUE(!start.accepted(), "Start should be rejected without HTTP adapter");
    ASSERT_TRUE(start.error_message().find("HTTP transport") != std::string::npos,
                "Start should explain missing adapter");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_start_progress_callback_complete() {
    TestResult r;
    r.test_name = "proto_start_progress_callback_complete";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);
    ProgressCapture capture;
    ScopedProgressCallback progress_scope(&capture);

    std::string base_dir = create_temp_dir("proto_complete");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-complete", "http://fake/success/model.gguf",
                          static_cast<int64_t>(fake.payload.size()), &plan),
                "Plan should succeed");

    rav1::DownloadStartResult start;
    ASSERT_TRUE(start_from_plan(plan, false, &start), "Start should serialize and parse");
    ASSERT_TRUE(start.accepted(), "Start should be accepted");
    ASSERT_TRUE(!start.resume_token().empty(), "Start should return a logical resume token");
    ASSERT_TRUE(start.initial_progress().resume_token() == start.resume_token(),
                "Initial progress should carry the same resume token");
    ASSERT_TRUE(wait_for_any_progress(&capture), "Progress callback should fire");

    rav1::DownloadProgress terminal;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &terminal), "Download should finish");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_COMPLETED,
                "Download should complete successfully");
    ASSERT_TRUE(!terminal.local_path().empty(), "Completed progress should include local_path");
    ASSERT_TRUE(terminal.overall_progress() == 1.0f,
                "Completed progress should report overall progress");
    ASSERT_TRUE(!terminal.resume_token().empty(),
                "Completed progress should preserve resume token");
    ASSERT_TRUE(terminal.updated_at_unix_ms() >= terminal.started_at_unix_ms(),
                "Progress timestamps should be populated");

    std::ifstream in(terminal.local_path(), std::ios::binary);
    std::vector<uint8_t> downloaded((std::istreambuf_iterator<char>(in)),
                                    std::istreambuf_iterator<char>());
    ASSERT_TRUE(downloaded == fake.payload, "Downloaded file should match streamed payload");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_nested_multifile_reports_model_root() {
    TestResult r;
    r.test_name = "proto_nested_multifile_reports_model_root";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);
    std::string base_dir = create_temp_dir("proto_nested_multifile");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    const std::string model_id = "proto-nested-multifile";
    const std::string model_name = "Nested multifile";
    const std::string model_url = "http://fake/success";
    rac_model_info_t registered{};
    registered.id = const_cast<char*>(model_id.c_str());
    registered.name = const_cast<char*>(model_name.c_str());
    registered.download_url = const_cast<char*>(model_url.c_str());
    registered.category = RAC_MODEL_CATEGORY_IMAGE_GENERATION;
    registered.framework = RAC_FRAMEWORK_QHEXRT;
    registered.format = RAC_MODEL_FORMAT_QNN_CONTEXT;
    ASSERT_TRUE(rac_register_model(&registered) == RAC_SUCCESS,
                "Model must be registered so the start path resolves its framework root");

    rav1::DownloadPlanRequest request;
    request.set_model_id(model_id);
    rav1::ModelInfo* model = request.mutable_model();
    model->set_id(model_id);
    model->set_name(model_name);
    model->set_download_url(model_url);
    model->set_framework(rav1::INFERENCE_FRAMEWORK_QHEXRT);
    model->set_format(rav1::MODEL_FORMAT_QNN_CONTEXT);
    for (const auto& relative : {std::string("context/model.bin"), std::string("manifest.json")}) {
        auto* file = model->mutable_multi_file()->add_files();
        file->set_url(model_url + "/" + relative);
        file->set_filename(relative.substr(relative.find_last_of('/') + 1));
        file->set_relative_path(relative);
        file->set_is_required(true);
        file->set_size_bytes(static_cast<int64_t>(fake.payload.size()));
    }

    std::string plan_bytes = serialize_msg(request);
    rac_proto_buffer_t plan_buffer;
    rac_proto_buffer_init(&plan_buffer);
    ASSERT_TRUE(rac_download_plan_proto(reinterpret_cast<const uint8_t*>(plan_bytes.data()),
                                        plan_bytes.size(), &plan_buffer) == RAC_SUCCESS,
                "Nested multi-file plan should succeed");
    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(parse_plan(plan_buffer, &plan), "Nested multi-file plan should parse");
    rac_proto_buffer_free(&plan_buffer);
    ASSERT_TRUE(plan.can_start() && plan.files_size() == 2,
                "Nested multi-file plan should contain both files");

    rav1::DownloadStartResult start;
    ASSERT_TRUE(start_from_plan(plan, false, &start), "Nested multi-file start should parse");
    ASSERT_TRUE(start.accepted(), "Nested multi-file start should be accepted");
    rav1::DownloadProgress terminal;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &terminal), "Nested multi-file download should finish");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_COMPLETED,
                "Nested multi-file download should complete");

    char model_folder[4096];
    ASSERT_TRUE(rac_model_paths_get_model_folder(model_id.c_str(), RAC_FRAMEWORK_QHEXRT,
                                                 model_folder, sizeof(model_folder)) == RAC_SUCCESS,
                "Canonical model root should resolve");
    ASSERT_TRUE(terminal.local_path() == std::string(model_folder),
                "Completed multi-file local_path must be the model root, not the first nested parent");
    ASSERT_TRUE(std::ifstream(std::string(model_folder) + "/context/model.bin").good(),
                "Nested context should exist under the model root");
    ASSERT_TRUE(std::ifstream(std::string(model_folder) + "/manifest.json").good(),
                "Root manifest should exist beside the nested context directory");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

// Builds + plans a 2-file bundle whose per-file URLs share `url_base`, each
// carrying an explicit size so the pre-flight gate + parallel accounting have
// per-file totals. Two required non-archive files with resume_from==0 satisfy
// can_download_files_in_parallel(), so the start path drives
// run_parallel_direct_download_worker. Returns the parsed start result.
static bool plan_and_start_parallel_bundle(FakeTransport& fake, const std::string& model_id,
                                           const std::string& url_base, int64_t per_file_bytes,
                                           rav1::DownloadStartResult* out_start) {
    rac_model_info_t registered{};
    registered.id = const_cast<char*>(model_id.c_str());
    registered.name = const_cast<char*>(model_id.c_str());
    std::string base_copy = url_base;
    registered.download_url = const_cast<char*>(base_copy.c_str());
    registered.category = RAC_MODEL_CATEGORY_IMAGE_GENERATION;
    registered.framework = RAC_FRAMEWORK_QHEXRT;
    registered.format = RAC_MODEL_FORMAT_QNN_CONTEXT;
    if (rac_register_model(&registered) != RAC_SUCCESS)
        return false;

    rav1::DownloadPlanRequest request;
    request.set_model_id(model_id);
    rav1::ModelInfo* model = request.mutable_model();
    model->set_id(model_id);
    model->set_name(model_id);
    model->set_download_url(url_base);
    model->set_framework(rav1::INFERENCE_FRAMEWORK_QHEXRT);
    model->set_format(rav1::MODEL_FORMAT_QNN_CONTEXT);
    for (const auto& relative : {std::string("part_a.bin"), std::string("part_b.bin")}) {
        auto* file = model->mutable_multi_file()->add_files();
        file->set_url(url_base + "/" + relative);
        file->set_filename(relative);
        file->set_relative_path(relative);
        file->set_is_required(true);
        file->set_size_bytes(per_file_bytes);
    }

    std::string plan_bytes = serialize_msg(request);
    rac_proto_buffer_t plan_buffer;
    rac_proto_buffer_init(&plan_buffer);
    if (rac_download_plan_proto(reinterpret_cast<const uint8_t*>(plan_bytes.data()),
                                plan_bytes.size(), &plan_buffer) != RAC_SUCCESS) {
        rac_proto_buffer_free(&plan_buffer);
        return false;
    }
    rav1::DownloadPlanResult plan;
    bool parsed = parse_plan(plan_buffer, &plan);
    rac_proto_buffer_free(&plan_buffer);
    if (!parsed || !plan.can_start() || plan.files_size() != 2)
        return false;

    return start_from_plan(plan, /*resume=*/false, out_start);
}

// #4 parallel retry: a transient network drop on a bundle file must NOT fail the
// whole download. The parallel worker shares execute_stream_with_retry with the
// sequential path, so each part resumes from its ".part" sidecar and completes.
// The "/flaky" transport fails each part's first stream once (after flushing a
// prefix) and then serves the resume tail — so a successful terminal state and
// on-disk files prove the parallel worker retried.
static TestResult test_proto_parallel_retries_transient_then_completes() {
    TestResult r;
    r.test_name = "proto_parallel_retries_transient_then_completes";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);

    std::string base_dir = create_temp_dir("proto_parallel_retry");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    const std::string model_id = "proto-parallel-retry";
    rav1::DownloadStartResult start;
    ASSERT_TRUE(plan_and_start_parallel_bundle(fake, model_id, "http://fake/flaky",
                                               static_cast<int64_t>(fake.payload.size()), &start),
                "Flaky 2-file bundle should plan and start");
    ASSERT_TRUE(start.accepted(), "Parallel bundle start should be accepted");

    rav1::DownloadProgress terminal;
    // One 500ms backoff per part plus the transfer — 8s is generous headroom.
    ASSERT_TRUE(wait_for_terminal_ms(start.task_id(), 8000, &terminal),
                "Parallel retry download should reach a terminal state");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_COMPLETED,
                "Transient drops must be retried, not fail the whole download");

    // Each distinct "/flaky" part failed its first fresh stream exactly once and
    // then completed via a resume, so both a fail and a resume must have run.
    {
        std::lock_guard<std::mutex> lock(fake.flaky_mutex);
        ASSERT_TRUE(fake.flaky_urls_failed_once.size() == 2,
                    "Both parallel parts should have taken their one transient failure");
        ASSERT_TRUE(fake.resume_attempts >= 2,
                    "Both parts should have resumed from their .part sidecar after the drop");
    }

    char model_folder[4096];
    ASSERT_TRUE(rac_model_paths_get_model_folder(model_id.c_str(), RAC_FRAMEWORK_QHEXRT,
                                                 model_folder, sizeof(model_folder)) == RAC_SUCCESS,
                "Model root should resolve");
    std::string folder(model_folder);
    for (const auto& part : {std::string("part_a.bin"), std::string("part_b.bin")}) {
        std::ifstream in(folder + "/" + part, std::ios::binary);
        std::vector<uint8_t> got((std::istreambuf_iterator<char>(in)),
                                 std::istreambuf_iterator<char>());
        ASSERT_TRUE(got == fake.payload,
                    "Retried+resumed part must equal the full payload byte-for-byte");
        // The finalize rename must have consumed the ".part" sidecar.
        ASSERT_TRUE(!std::ifstream(folder + "/" + part + ".part").good(),
                    "No .part sidecar should survive a completed retry");
    }

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

// #4 retry is BOUNDED: a URL that network-errors on every attempt must give up
// after the fixed attempt budget and fail the whole parallel download rather
// than spin forever. "/network" always returns a network error (never a prefix,
// never a resume tail), so no part can complete.
static TestResult test_proto_parallel_permanent_error_fails_after_retries() {
    TestResult r;
    r.test_name = "proto_parallel_permanent_error_fails_after_retries";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);

    std::string base_dir = create_temp_dir("proto_parallel_permanent");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    const std::string model_id = "proto-parallel-permanent";
    rav1::DownloadStartResult start;
    ASSERT_TRUE(plan_and_start_parallel_bundle(fake, model_id, "http://fake/network",
                                               static_cast<int64_t>(fake.payload.size()), &start),
                "Always-failing 2-file bundle should still plan and start");
    ASSERT_TRUE(start.accepted(), "Parallel bundle start should be accepted");

    rav1::DownloadProgress terminal;
    // 4 attempts back off 500ms + 1s + 2s = 3.5s per part before giving up;
    // 15s covers that plus the two parts running concurrently, with margin.
    ASSERT_TRUE(wait_for_terminal_ms(start.task_id(), 15000, &terminal),
                "Bounded retry must terminate (not hang) on a permanent network error");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_FAILED,
                "A permanently unreachable part must fail after the retry budget is exhausted");
    ASSERT_TRUE(terminal.local_path().empty(),
                "A failed parallel download must not publish a final path");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_cancel_resume() {
    TestResult r;
    r.test_name = "proto_cancel_resume";

    FakeTransport fake;
    fake.sleep_ms_per_chunk = 2;
    ScopedFakeTransport scoped(&fake);
    ProgressCapture capture;
    ScopedProgressCallback progress_scope(&capture);

    std::string base_dir = create_temp_dir("proto_cancel_resume");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-resume", "http://fake/success/model.gguf",
                          static_cast<int64_t>(fake.payload.size()), &plan),
                "Plan should succeed");

    rav1::DownloadStartResult start;
    ASSERT_TRUE(start_from_plan(plan, false, &start), "Start should succeed");
    ASSERT_TRUE(start.accepted(), "Start should be accepted");
    ASSERT_TRUE(wait_for_downloaded_progress(&capture),
                "Downloaded progress should arrive before cancel");

    rav1::DownloadCancelRequest cancel;
    cancel.set_task_id(start.task_id());
    cancel.set_delete_partial_bytes(false);
    std::string cancel_bytes = serialize_msg(cancel);
    rac_proto_buffer_t cancel_buffer;
    rac_proto_buffer_init(&cancel_buffer);
    ASSERT_TRUE(rac_download_cancel_proto(reinterpret_cast<const uint8_t*>(cancel_bytes.data()),
                                          cancel_bytes.size(), &cancel_buffer) == RAC_SUCCESS,
                "Cancel call should succeed");
    rav1::DownloadCancelResult cancel_result;
    ASSERT_TRUE(parse_cancel(cancel_buffer, &cancel_result), "Cancel result should parse");
    ASSERT_TRUE(cancel_result.success(), "Cancel result should report success");
    ASSERT_TRUE(cancel_result.was_running(), "Cancel should observe a running task");
    ASSERT_TRUE(cancel_result.partial_bytes_preserved(),
                "Cancel without deletion should preserve partial bytes");
    ASSERT_TRUE(!cancel_result.resume_token().empty(),
                "Cancel result should preserve the resume token");
    rac_proto_buffer_free(&cancel_buffer);

    rav1::DownloadProgress cancelled;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &cancelled), "Cancelled task should terminal");
    ASSERT_TRUE(cancelled.state() == rav1::DOWNLOAD_STATE_CANCELLED,
                "Task should be cancelled, not completed");
    ASSERT_TRUE(cancelled.bytes_downloaded() > 0,
                "Cancelled progress should preserve partial byte count");
    ASSERT_TRUE(cancelled.resume_token() == cancel_result.resume_token(),
                "Cancelled progress should carry the resume token");

    int64_t partial_size = 0;
    if (plan.files_size() > 0) {
        // A cancelled transfer preserves its bytes in the ".part" sidecar; the
        // final path only materializes on the finalize rename after completion.
        std::ifstream partial(plan.files(0).destination_path() + ".part",
                              std::ios::binary | std::ios::ate);
        partial_size = partial.good() ? static_cast<int64_t>(partial.tellg()) : 0;
    }
    ASSERT_TRUE(partial_size > 0 && std::cmp_less(partial_size, fake.payload.size()),
                "Cancel should leave partial bytes for resume");

    rav1::DownloadResumeRequest stale_resume;
    stale_resume.set_task_id(start.task_id());
    stale_resume.set_resume_token(cancel_result.resume_token());
    stale_resume.set_resume_from_bytes(partial_size + 8192);
    stale_resume.set_validate_partial_bytes(true);
    std::string stale_resume_bytes = serialize_msg(stale_resume);
    rac_proto_buffer_t stale_resume_buffer;
    rac_proto_buffer_init(&stale_resume_buffer);
    ASSERT_TRUE(
        rac_download_resume_proto(reinterpret_cast<const uint8_t*>(stale_resume_bytes.data()),
                                  stale_resume_bytes.size(), &stale_resume_buffer) == RAC_SUCCESS,
        "Stale resume call should return a result proto");
    rav1::DownloadResumeResult stale_resume_result;
    ASSERT_TRUE(parse_resume(stale_resume_buffer, &stale_resume_result),
                "Stale resume result should parse");
    ASSERT_TRUE(!stale_resume_result.accepted(),
                "Stale resume offset should be rejected when validation is requested");
    rac_proto_buffer_free(&stale_resume_buffer);

    rav1::DownloadResumeRequest resume;
    resume.set_task_id(start.task_id());
    resume.set_resume_token(cancel_result.resume_token());
    resume.set_resume_from_bytes(partial_size);
    resume.set_validate_partial_bytes(true);
    std::string resume_bytes = serialize_msg(resume);
    rac_proto_buffer_t resume_buffer;
    rac_proto_buffer_init(&resume_buffer);
    ASSERT_TRUE(rac_download_resume_proto(reinterpret_cast<const uint8_t*>(resume_bytes.data()),
                                          resume_bytes.size(), &resume_buffer) == RAC_SUCCESS,
                "Resume call should succeed");
    rav1::DownloadResumeResult resume_result;
    ASSERT_TRUE(parse_resume(resume_buffer, &resume_result), "Resume result should parse");
    ASSERT_TRUE(resume_result.accepted(), "Resume should be accepted");
    ASSERT_TRUE(resume_result.resume_token() == cancel_result.resume_token(),
                "Resume should preserve the logical resume token");
    ASSERT_TRUE(resume_result.initial_progress().bytes_downloaded() == partial_size,
                "Resume initial progress should preserve partial byte count");
    rac_proto_buffer_free(&resume_buffer);

    rav1::DownloadProgress completed;
    ASSERT_TRUE(wait_for_state(start.task_id(), rav1::DOWNLOAD_STATE_COMPLETED, &completed),
                "Resumed task should finish");
    ASSERT_TRUE(completed.state() == rav1::DOWNLOAD_STATE_COMPLETED,
                "Resumed task should complete");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}

static TestResult test_proto_failed_transfer_no_stale_completion() {
    TestResult r;
    r.test_name = "proto_failed_transfer_no_stale_completion";

    FakeTransport fake;
    ScopedFakeTransport scoped(&fake);

    std::string base_dir = create_temp_dir("proto_fail");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-fail", "http://fake/fail/model.gguf",
                          static_cast<int64_t>(fake.payload.size()), &plan),
                "Plan should succeed");

    rav1::DownloadStartResult start;
    ASSERT_TRUE(start_from_plan(plan, false, &start), "Start should return result");
    ASSERT_TRUE(start.accepted(), "Start should be accepted");

    rav1::DownloadProgress terminal;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &terminal), "Failed task should terminal");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_FAILED,
                "Failed transfer must not be marked completed");
    ASSERT_TRUE(terminal.local_path().empty(), "Failed transfer should not publish final path");
    ASSERT_TRUE(!terminal.resume_token().empty(), "Failed progress should preserve resume token");

    remove_dir(base_dir);
    r.passed = true;
    return r;
}
#endif

// =============================================================================
// Test runner
// =============================================================================

int main(int argc, char** argv) {
    try {
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

#ifdef RAC_HAVE_PROTOBUF
        // proto-byte workflow ABI
        suite.add("proto_plan_single_file", test_proto_plan_single_file);
        suite.add("proto_plan_multifile_uses_declared_aggregate_when_head_unknown",
                  test_proto_plan_multifile_uses_declared_aggregate_when_head_unknown);
        suite.add("proto_plan_invalid_url", test_proto_plan_invalid_url);
        suite.add("proto_plan_resume_metadata", test_proto_plan_resume_metadata);
        suite.add("proto_plan_self_heals_oversized_existing_bytes",
                  test_proto_plan_self_heals_oversized_existing_bytes);
        // pass2-syn-115 / security-privacy-storage-network-001 regression
        suite.add("proto_plan_rejects_path_traversal_destination",
                  test_proto_plan_rejects_path_traversal_destination);
        suite.add("proto_start_skips_traversal_unsafe_plan_entry",
                  test_proto_start_skips_traversal_unsafe_plan_entry);
        suite.add("proto_start_no_adapter", test_proto_start_no_adapter);
        suite.add("proto_start_progress_callback_complete",
                  test_proto_start_progress_callback_complete);
        suite.add("proto_nested_multifile_reports_model_root",
                  test_proto_nested_multifile_reports_model_root);
        // #4 parallel download retry-with-resume (shared execute_stream_with_retry).
        suite.add("proto_parallel_retries_transient_then_completes",
                  test_proto_parallel_retries_transient_then_completes);
        suite.add("proto_parallel_permanent_error_fails_after_retries",
                  test_proto_parallel_permanent_error_fails_after_retries);
        suite.add("proto_cancel_resume", test_proto_cancel_resume);
        suite.add("proto_failed_transfer_no_stale_completion",
                  test_proto_failed_transfer_no_stale_completion);
#endif

        return suite.run(argc, argv);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: uncaught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        std::fprintf(stderr, "FATAL: uncaught unknown exception\n");
        return 1;
    }
}
