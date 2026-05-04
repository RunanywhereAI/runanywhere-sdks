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
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include "core/internal/platform_compat.h"

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
    std::vector<uint8_t> payload = fake_payload(256 * 1024);
    int sleep_ms_per_chunk = 0;
};

rac_bool_t fake_send_chunk(rac_http_body_chunk_fn cb, void* cb_user_data,
                           const std::vector<uint8_t>& payload, size_t start,
                           size_t chunk_size, int sleep_ms) {
    uint64_t delivered = 0;
    for (size_t offset = start; offset < payload.size(); offset += chunk_size) {
        size_t n = std::min(chunk_size, payload.size() - offset);
        delivered += n;
        if (cb(payload.data() + offset, n, delivered,
               static_cast<uint64_t>(payload.size() - start), cb_user_data) == RAC_FALSE) {
            return RAC_FALSE;
        }
        if (sleep_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
        }
    }
    return RAC_TRUE;
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
    out_resp_meta->status = 200;
    return fake_send_chunk(cb, cb_user_data, fake->payload, 0, 8192,
                           fake->sleep_ms_per_chunk) == RAC_TRUE
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
    out_resp_meta->status = 206;
    size_t start = std::min<size_t>(static_cast<size_t>(resume_from_byte), fake->payload.size());
    return fake_send_chunk(cb, cb_user_data, fake->payload, start, 8192,
                           fake->sleep_ms_per_chunk) == RAC_TRUE
               ? RAC_SUCCESS
               : RAC_ERROR_CANCELLED;
}

rac_http_transport_ops_t fake_ops = {
    fake_request_send,
    fake_request_stream,
    fake_request_resume,
    nullptr,
    nullptr,
};

struct ScopedFakeTransport {
    explicit ScopedFakeTransport(FakeTransport* fake) {
        rac_http_transport_register(&fake_ops, fake);
    }
    ~ScopedFakeTransport() {
        rac_http_transport_register(nullptr, nullptr);
    }
};

std::string serialize_msg(const google::protobuf::MessageLite& msg) {
    std::string bytes;
    (void)msg.SerializeToString(&bytes);
    return bytes;
}

bool parse_plan(const rac_proto_buffer_t& buffer, rav1::DownloadPlanResult* out) {
    return out && buffer.status == RAC_SUCCESS && buffer.data &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_start(const rac_proto_buffer_t& buffer, rav1::DownloadStartResult* out) {
    return out && buffer.status == RAC_SUCCESS && buffer.data &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_cancel(const rac_proto_buffer_t& buffer, rav1::DownloadCancelResult* out) {
    return out && buffer.status == RAC_SUCCESS && buffer.data &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_resume(const rac_proto_buffer_t& buffer, rav1::DownloadResumeResult* out) {
    return out && buffer.status == RAC_SUCCESS && buffer.data &&
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
    rac_result_t rc = rac_download_progress_poll_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                       bytes.size(), &buffer);
    bool ok = rc == RAC_SUCCESS && buffer.status == RAC_SUCCESS && buffer.data &&
              out_progress->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool wait_for_terminal(const std::string& task_id, rav1::DownloadProgress* out_progress) {
    for (int i = 0; i < 250; ++i) {
        if (poll_progress(task_id, out_progress)) {
            auto state = out_progress->state();
            if (state == rav1::DOWNLOAD_STATE_COMPLETED ||
                state == rav1::DOWNLOAD_STATE_FAILED ||
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
    ~ScopedProgressCallback() {
        rac_download_set_progress_proto_callback(nullptr, nullptr);
    }
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

static TestResult test_proto_start_no_adapter() {
    TestResult r;
    r.test_name = "proto_start_no_adapter";

    rac_http_transport_register(nullptr, nullptr);
    std::string base_dir = create_temp_dir("proto_no_adapter");
    ASSERT_TRUE(!base_dir.empty(), "Failed to create temp dir");
    rac_model_paths_set_base_dir(base_dir.c_str());

    rav1::DownloadPlanResult plan;
    ASSERT_TRUE(make_plan("proto-model-no-adapter", "http://fake/success/model.gguf", 100,
                          &plan),
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
    ASSERT_TRUE(wait_for_any_progress(&capture), "Progress callback should fire");

    rav1::DownloadProgress terminal;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &terminal), "Download should finish");
    ASSERT_TRUE(terminal.state() == rav1::DOWNLOAD_STATE_COMPLETED,
                "Download should complete successfully");
    ASSERT_TRUE(!terminal.local_path().empty(), "Completed progress should include local_path");

    std::ifstream in(terminal.local_path(), std::ios::binary);
    std::vector<uint8_t> downloaded((std::istreambuf_iterator<char>(in)),
                                    std::istreambuf_iterator<char>());
    ASSERT_TRUE(downloaded == fake.payload, "Downloaded file should match streamed payload");

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
    rac_proto_buffer_free(&cancel_buffer);

    rav1::DownloadProgress cancelled;
    ASSERT_TRUE(wait_for_terminal(start.task_id(), &cancelled), "Cancelled task should terminal");
    ASSERT_TRUE(cancelled.state() == rav1::DOWNLOAD_STATE_CANCELLED,
                "Task should be cancelled, not completed");

    int64_t partial_size = 0;
    if (plan.files_size() > 0) {
        std::ifstream partial(plan.files(0).destination_path(), std::ios::binary | std::ios::ate);
        partial_size = partial.good() ? static_cast<int64_t>(partial.tellg()) : 0;
    }
    ASSERT_TRUE(partial_size > 0 && partial_size < static_cast<int64_t>(fake.payload.size()),
                "Cancel should leave partial bytes for resume");

    rav1::DownloadResumeRequest resume;
    resume.set_task_id(start.task_id());
    resume.set_resume_from_bytes(partial_size);
    std::string resume_bytes = serialize_msg(resume);
    rac_proto_buffer_t resume_buffer;
    rac_proto_buffer_init(&resume_buffer);
    ASSERT_TRUE(rac_download_resume_proto(reinterpret_cast<const uint8_t*>(resume_bytes.data()),
                                          resume_bytes.size(), &resume_buffer) == RAC_SUCCESS,
                "Resume call should succeed");
    rav1::DownloadResumeResult resume_result;
    ASSERT_TRUE(parse_resume(resume_buffer, &resume_result), "Resume result should parse");
    ASSERT_TRUE(resume_result.accepted(), "Resume should be accepted");
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

    remove_dir(base_dir);
    r.passed = true;
    return r;
}
#endif

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

#ifdef RAC_HAVE_PROTOBUF
    // proto-byte workflow ABI
    suite.add("proto_plan_single_file", test_proto_plan_single_file);
    suite.add("proto_plan_invalid_url", test_proto_plan_invalid_url);
    suite.add("proto_start_no_adapter", test_proto_start_no_adapter);
    suite.add("proto_start_progress_callback_complete",
              test_proto_start_progress_callback_complete);
    suite.add("proto_cancel_resume", test_proto_cancel_resume);
    suite.add("proto_failed_transfer_no_stale_completion",
              test_proto_failed_transfer_no_stale_completion);
#endif

    return suite.run(argc, argv);
}
