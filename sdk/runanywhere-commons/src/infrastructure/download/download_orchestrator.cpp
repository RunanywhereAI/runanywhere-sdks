/**
 * @file download_orchestrator.cpp
 * @brief Download Orchestrator - High-Level Model Download Lifecycle Management
 *
 * Consolidates download business logic from Swift/Kotlin/RN/Flutter SDKs into C++.
 * Each SDK now only provides the HTTP transport callback and calls rac_download_orchestrate().
 *
 * Full lifecycle:
 *   1. Compute destination path (temp if extraction needed, final if not)
 *   2. Start HTTP download via platform adapter (rac_http_download)
 *   3. On HTTP completion:
 *      a. If extraction needed → rac_extract_archive_native → find model path → cleanup archive
 *      b. Update download manager state
 *   4. Invoke user's complete_callback with final model path
 */

#include <condition_variable>
#include <atomic>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "core/internal/platform_compat.h"

#ifdef _WIN32
#include <direct.h>  // for _mkdir
#endif

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/download/rac_download.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/extraction/rac_extraction.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "../http/rac_http_internal.h"

#ifdef RAC_HAVE_PROTOBUF
#include "download_service.pb.h"
#endif

static const char* LOG_TAG = "DownloadOrchestrator";

namespace fs = std::filesystem;

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

/**
 * Get file extension from a URL/path string (without dot).
 * Handles compound extensions like .tar.gz, .tar.bz2, .tar.xz.
 */
static std::string get_file_extension(const char* url) {
    if (!url)
        return "";

    std::string path(url);

    // Strip query string and fragment
    auto query_pos = path.find('?');
    if (query_pos != std::string::npos)
        path = path.substr(0, query_pos);
    auto frag_pos = path.find('#');
    if (frag_pos != std::string::npos)
        path = path.substr(0, frag_pos);

    // Find the last path component
    auto slash_pos = path.rfind('/');
    std::string filename = (slash_pos != std::string::npos) ? path.substr(slash_pos + 1) : path;

    // Check for compound extensions first
    if (filename.length() > 7) {
        std::string lower = filename;
        for (auto& c : lower)
            c = static_cast<char>(tolower(c));

        if (lower.rfind(".tar.gz") == lower.length() - 7)
            return "tar.gz";
        if (lower.rfind(".tar.bz2") == lower.length() - 8)
            return "tar.bz2";
        if (lower.rfind(".tar.xz") == lower.length() - 7)
            return "tar.xz";
        if (lower.rfind(".tgz") == lower.length() - 4)
            return "tar.gz";
        if (lower.rfind(".tbz2") == lower.length() - 5)
            return "tar.bz2";
        if (lower.rfind(".txz") == lower.length() - 4)
            return "tar.xz";
    }

    // Simple extension
    auto dot_pos = filename.rfind('.');
    if (dot_pos != std::string::npos && dot_pos < filename.length() - 1) {
        return filename.substr(dot_pos + 1);
    }

    return "";
}

/**
 * Get the filename (without extension) from a URL.
 */
static std::string get_filename_stem(const char* url) {
    if (!url)
        return "";

    std::string path(url);
    auto query_pos = path.find('?');
    if (query_pos != std::string::npos)
        path = path.substr(0, query_pos);

    auto slash_pos = path.rfind('/');
    std::string filename = (slash_pos != std::string::npos) ? path.substr(slash_pos + 1) : path;

    // Strip compound extensions
    std::string lower = filename;
    for (auto& c : lower)
        c = static_cast<char>(tolower(c));

    const char* compound_exts[] = {".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".txz"};
    for (const auto& ext : compound_exts) {
        size_t ext_len = strlen(ext);
        if (lower.length() > ext_len && lower.rfind(ext) == lower.length() - ext_len) {
            return filename.substr(0, filename.length() - ext_len);
        }
    }

    // Strip simple extension
    auto dot_pos = filename.rfind('.');
    if (dot_pos != std::string::npos) {
        return filename.substr(0, dot_pos);
    }

    return filename;
}

static std::string get_filename(const char* url) {
    if (!url)
        return "";

    std::string path(url);
    auto query_pos = path.find('?');
    if (query_pos != std::string::npos)
        path = path.substr(0, query_pos);
    auto frag_pos = path.find('#');
    if (frag_pos != std::string::npos)
        path = path.substr(0, frag_pos);

    auto slash_pos = path.rfind('/');
    std::string filename = (slash_pos != std::string::npos) ? path.substr(slash_pos + 1) : path;
    return filename;
}

/**
 * Check if a file extension is a known model extension.
 */
static bool is_model_extension(const char* ext) {
    if (!ext)
        return false;
    // Compare case-insensitively
    std::string lower(ext);
    for (auto& c : lower)
        c = static_cast<char>(tolower(c));

    return lower == "gguf" || lower == "onnx" || lower == "ort" || lower == "bin" ||
           lower == "mlmodelc" || lower == "mlpackage";
}

/**
 * Check if a directory exists.
 */
static bool dir_exists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

/**
 * Create directories recursively (like mkdir -p).
 */
static bool mkdir_p(const char* path) {
    if (dir_exists(path))
        return true;

    std::string s(path);
    std::string::size_type pos = 0;

    // Accept both '/' and '\\' as separators on Windows so paths like
    // "C:\foo\bar\baz" get their intermediate dirs created correctly.
#ifdef _WIN32
    const char* kSeparators = "/\\";
#else
    const char* kSeparators = "/";
#endif

    while ((pos = s.find_first_of(kSeparators, pos + 1)) != std::string::npos) {
        std::string sub = s.substr(0, pos);
        if (!sub.empty()) {
#ifdef _WIN32
            _mkdir(sub.c_str());
#else
            mkdir(sub.c_str(), 0755);
#endif
        }
    }
#ifdef _WIN32
    return _mkdir(s.c_str()) == 0 || dir_exists(path);
#else
    return mkdir(s.c_str(), 0755) == 0 || dir_exists(path);
#endif
}

/**
 * Delete a file.
 */
static void delete_file(const char* path) {
    if (path) {
        remove(path);
    }
}

#ifdef RAC_HAVE_PROTOBUF
namespace {

namespace rav1 = ::runanywhere::v1;

struct proto_plan_file {
    std::string url;
    std::string destination_path;
    std::string storage_key;
    std::string checksum_sha256;
    int64_t expected_bytes = 0;
    bool requires_extraction = false;
};

struct proto_download_task {
    std::mutex mutex;
    std::string task_id;
    std::string model_id;
    std::string model_folder_path;
    std::vector<proto_plan_file> files;
    rav1::DownloadProgress progress;
    std::atomic<bool> cancel_requested{false};
    bool running = false;
    bool delete_partial_on_cancel = false;
};

struct proto_service_state {
    std::mutex mutex;
    std::map<std::string, std::shared_ptr<proto_download_task>> tasks;
    std::atomic<uint64_t> next_task_id{1};
};

proto_service_state& proto_state() {
    static proto_service_state state;
    return state;
}

struct proto_progress_sink {
    std::mutex mutex;
    rac_download_proto_progress_callback_fn callback = nullptr;
    void* user_data = nullptr;
};

proto_progress_sink& progress_sink() {
    static proto_progress_sink sink;
    return sink;
}

bool is_absolute_path(const std::string& path) {
    if (path.empty())
        return false;
#ifdef _WIN32
    return path.size() > 2 && path[1] == ':';
#else
    return path[0] == '/';
#endif
}

std::string join_path(const std::string& lhs, const std::string& rhs) {
    if (lhs.empty())
        return rhs;
    if (rhs.empty())
        return lhs;
    if (lhs.back() == '/' || lhs.back() == '\\')
        return lhs + rhs;
    return lhs + "/" + rhs;
}

bool looks_like_http_url(const std::string& url) {
    return url.rfind("http://", 0) == 0 || url.rfind("https://", 0) == 0;
}

rac_inference_framework_t proto_framework_to_c(rav1::InferenceFramework framework) {
    switch (framework) {
        case rav1::INFERENCE_FRAMEWORK_ONNX:
            return RAC_FRAMEWORK_ONNX;
        case rav1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return RAC_FRAMEWORK_LLAMACPP;
        case rav1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return RAC_FRAMEWORK_FOUNDATION_MODELS;
        case rav1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return RAC_FRAMEWORK_SYSTEM_TTS;
        case rav1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
            return RAC_FRAMEWORK_FLUID_AUDIO;
        case rav1::INFERENCE_FRAMEWORK_BUILT_IN:
            return RAC_FRAMEWORK_BUILTIN;
        case rav1::INFERENCE_FRAMEWORK_MLX:
            return RAC_FRAMEWORK_MLX;
        case rav1::INFERENCE_FRAMEWORK_COREML:
            return RAC_FRAMEWORK_COREML;
        case rav1::INFERENCE_FRAMEWORK_WHISPERKIT_COREML:
            return RAC_FRAMEWORK_WHISPERKIT_COREML;
        case rav1::INFERENCE_FRAMEWORK_METALRT:
            return RAC_FRAMEWORK_METALRT;
        case rav1::INFERENCE_FRAMEWORK_GENIE:
            return RAC_FRAMEWORK_GENIE;
        case rav1::INFERENCE_FRAMEWORK_SHERPA:
            return RAC_FRAMEWORK_SHERPA;
        case rav1::INFERENCE_FRAMEWORK_NONE:
            return RAC_FRAMEWORK_NONE;
        default:
            return RAC_FRAMEWORK_UNKNOWN;
    }
}

rac_model_format_t proto_format_to_c(rav1::ModelFormat format) {
    switch (format) {
        case rav1::MODEL_FORMAT_ONNX:
            return RAC_MODEL_FORMAT_ONNX;
        case rav1::MODEL_FORMAT_ORT:
            return RAC_MODEL_FORMAT_ORT;
        case rav1::MODEL_FORMAT_GGUF:
            return RAC_MODEL_FORMAT_GGUF;
        case rav1::MODEL_FORMAT_BIN:
            return RAC_MODEL_FORMAT_BIN;
        case rav1::MODEL_FORMAT_COREML:
        case rav1::MODEL_FORMAT_MLMODEL:
        case rav1::MODEL_FORMAT_MLPACKAGE:
            return RAC_MODEL_FORMAT_COREML;
        case rav1::MODEL_FORMAT_QNN_CONTEXT:
            return RAC_MODEL_FORMAT_QNN_CONTEXT;
        default:
            return RAC_MODEL_FORMAT_UNKNOWN;
    }
}

std::string http_status_message(rac_http_download_status_t status, int32_t http_status) {
    switch (status) {
        case RAC_HTTP_DL_OK:
            return "";
        case RAC_HTTP_DL_NETWORK_ERROR:
            return "network error";
        case RAC_HTTP_DL_FILE_ERROR:
            return "file error";
        case RAC_HTTP_DL_INSUFFICIENT_STORAGE:
            return "insufficient storage";
        case RAC_HTTP_DL_INVALID_URL:
            return "invalid URL";
        case RAC_HTTP_DL_CHECKSUM_FAILED:
            return "checksum verification failed";
        case RAC_HTTP_DL_CANCELLED:
            return "download cancelled";
        case RAC_HTTP_DL_SERVER_ERROR:
            return "server error: HTTP " + std::to_string(http_status);
        case RAC_HTTP_DL_TIMEOUT:
            return "download timed out";
        case RAC_HTTP_DL_NETWORK_UNAVAILABLE:
            return "network unavailable";
        case RAC_HTTP_DL_DNS_ERROR:
            return "DNS error";
        case RAC_HTTP_DL_SSL_ERROR:
            return "SSL error";
        default:
            return "download failed";
    }
}

rac_result_t serialize_proto_to_buffer(const ::google::protobuf::MessageLite& message,
                                       rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INTERNAL,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_result);
}

rac_result_t parse_failure(rac_proto_buffer_t* out_result, const char* message) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT, message);
    }
    return RAC_ERROR_INVALID_ARGUMENT;
}

void copy_file_descriptor_plan(const rav1::ModelFileDescriptor& input,
                               rav1::DownloadFilePlan* output) {
    if (!output) {
        return;
    }
    *output->mutable_file() = input;
}

std::shared_ptr<proto_download_task> find_task(const std::string& task_id,
                                               const std::string& model_id) {
    std::lock_guard<std::mutex> lock(proto_state().mutex);
    if (!task_id.empty()) {
        auto it = proto_state().tasks.find(task_id);
        if (it != proto_state().tasks.end()) {
            return it->second;
        }
    }
    if (!model_id.empty()) {
        for (auto& pair : proto_state().tasks) {
            if (pair.second && pair.second->model_id == model_id) {
                return pair.second;
            }
        }
    }
    return nullptr;
}

void emit_progress(const std::shared_ptr<proto_download_task>& task) {
    if (!task) {
        return;
    }

    rav1::DownloadProgress progress;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        progress = task->progress;
    }

    std::string bytes;
    if (!progress.SerializeToString(&bytes)) {
        return;
    }

    rac_download_proto_progress_callback_fn callback = nullptr;
    void* user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(progress_sink().mutex);
        callback = progress_sink().callback;
        user_data = progress_sink().user_data;
    }

    if (callback) {
        callback(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), user_data);
    }
}

int64_t file_size_or_zero(const std::string& path) {
    std::error_code ec;
    if (path.empty() || !fs::exists(path, ec)) {
        return 0;
    }
    auto size = fs::file_size(path, ec);
    if (ec) {
        return 0;
    }
    return static_cast<int64_t>(size);
}

int64_t delete_partial_file(const std::string& path) {
    int64_t bytes = file_size_or_zero(path);
    std::error_code ec;
    fs::remove(path, ec);
    return ec ? 0 : bytes;
}

void set_task_progress(const std::shared_ptr<proto_download_task>& task,
                       rav1::DownloadState state,
                       rav1::DownloadStage stage,
                       int64_t bytes_downloaded,
                       int64_t total_bytes,
                       int32_t file_index,
                       const std::string& storage_key,
                       const std::string& local_path,
                       const std::string& error_message) {
    if (!task) {
        return;
    }
    std::lock_guard<std::mutex> lock(task->mutex);
    rav1::DownloadProgress* progress = &task->progress;
    progress->set_model_id(task->model_id);
    progress->set_task_id(task->task_id);
    progress->set_state(state);
    progress->set_stage(stage);
    progress->set_bytes_downloaded(bytes_downloaded);
    progress->set_total_bytes(total_bytes);
    progress->set_current_file_index(file_index);
    progress->set_total_files(static_cast<int32_t>(task->files.size()));
    progress->set_storage_key(storage_key);
    if (!local_path.empty()) {
        progress->set_local_path(local_path);
    }
    if (!error_message.empty()) {
        progress->set_error_message(error_message);
    } else {
        progress->clear_error_message();
    }

    float stage_progress = 0.0f;
    if (total_bytes > 0) {
        stage_progress = static_cast<float>(
            std::min<double>(1.0, static_cast<double>(bytes_downloaded) /
                                      static_cast<double>(total_bytes)));
    }
    progress->set_stage_progress(stage_progress);
    progress->set_eta_seconds(-1);
}

struct proto_download_callback_ctx {
    std::shared_ptr<proto_download_task> task;
    int file_index = 0;
    int64_t completed_before_file = 0;
    int64_t total_expected = 0;
    std::string storage_key;
    std::string destination_path;
};

rac_bool_t proto_http_progress(uint64_t bytes_written, uint64_t total_bytes, void* user_data) {
    auto* ctx = static_cast<proto_download_callback_ctx*>(user_data);
    if (!ctx || !ctx->task) {
        return RAC_TRUE;
    }
    if (ctx->task->cancel_requested.load()) {
        return RAC_FALSE;
    }

    int64_t total = ctx->total_expected > 0
                        ? ctx->total_expected
                        : (total_bytes > 0 ? static_cast<int64_t>(total_bytes) : 0);
    int64_t downloaded = ctx->total_expected > 0
                             ? ctx->completed_before_file + static_cast<int64_t>(bytes_written)
                             : static_cast<int64_t>(bytes_written);

    set_task_progress(ctx->task, rav1::DOWNLOAD_STATE_DOWNLOADING,
                      rav1::DOWNLOAD_STAGE_DOWNLOADING, downloaded, total, ctx->file_index,
                      ctx->storage_key, "", "");
    emit_progress(ctx->task);
    return RAC_TRUE;
}

int64_t plan_total_expected(const std::vector<proto_plan_file>& files) {
    int64_t total = 0;
    for (const auto& file : files) {
        if (file.expected_bytes <= 0) {
            return 0;
        }
        total += file.expected_bytes;
    }
    return total;
}

void run_proto_download_worker(std::shared_ptr<proto_download_task> task, int64_t resume_from) {
    if (!task) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = true;
    }

    const int64_t total_expected = plan_total_expected(task->files);
    int64_t completed_before_file = 0;
    std::string final_path;

    for (size_t i = 0; i < task->files.size(); ++i) {
        proto_plan_file file = task->files[i];
        if (task->cancel_requested.load()) {
            break;
        }

        uint64_t file_resume_from = 0;
        if (i == 0 && resume_from > 0) {
            file_resume_from = static_cast<uint64_t>(resume_from);
        }

        proto_download_callback_ctx cb_ctx;
        cb_ctx.task = task;
        cb_ctx.file_index = static_cast<int>(i);
        cb_ctx.completed_before_file = completed_before_file;
        cb_ctx.total_expected = total_expected;
        cb_ctx.storage_key = file.storage_key;
        cb_ctx.destination_path = file.destination_path;

        rac_http_download_request_t req{};
        req.url = file.url.c_str();
        req.destination_path = file.destination_path.c_str();
        req.timeout_ms = 0;
        req.follow_redirects = RAC_TRUE;
        req.resume_from_byte = file_resume_from;
        req.expected_sha256_hex =
            file.checksum_sha256.empty() ? nullptr : file.checksum_sha256.c_str();

        int32_t http_status = 0;
        rac_http_download_status_t status =
            rac::http::execute_stream(req, proto_http_progress, &cb_ctx, &http_status);

        if (task->cancel_requested.load() || status == RAC_HTTP_DL_CANCELLED) {
            int64_t deleted = 0;
            {
                std::lock_guard<std::mutex> lock(task->mutex);
                if (task->delete_partial_on_cancel) {
                    deleted = delete_partial_file(file.destination_path);
                }
                task->running = false;
                task->progress.set_state(rav1::DOWNLOAD_STATE_CANCELLED);
                task->progress.set_stage(rav1::DOWNLOAD_STAGE_DOWNLOADING);
                task->progress.set_error_message("download cancelled");
                (void)deleted;
            }
            emit_progress(task);
            return;
        }

        if (status != RAC_HTTP_DL_OK) {
            std::string error = http_status_message(status, http_status);
            set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED,
                              rav1::DOWNLOAD_STAGE_DOWNLOADING,
                              total_expected > 0 ? completed_before_file : 0, total_expected,
                              static_cast<int32_t>(i), file.storage_key, "", error);
            {
                std::lock_guard<std::mutex> lock(task->mutex);
                task->running = false;
            }
            emit_progress(task);
            return;
        }

        if (file.requires_extraction) {
            set_task_progress(task, rav1::DOWNLOAD_STATE_EXTRACTING,
                              rav1::DOWNLOAD_STAGE_EXTRACTING,
                              total_expected > 0 ? completed_before_file + file.expected_bytes : 0,
                              total_expected, static_cast<int32_t>(i), file.storage_key, "", "");
            emit_progress(task);

            rac_extraction_result_t extraction_result{};
            rac_result_t extract_rc = rac_extract_archive_native(file.destination_path.c_str(),
                                                                 task->model_folder_path.c_str(),
                                                                 nullptr, nullptr, nullptr,
                                                                 &extraction_result);
            if (extract_rc != RAC_SUCCESS) {
                set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED,
                                  rav1::DOWNLOAD_STAGE_EXTRACTING,
                                  total_expected > 0 ? completed_before_file + file.expected_bytes
                                                     : 0,
                                  total_expected, static_cast<int32_t>(i), file.storage_key, "",
                                  "archive extraction failed");
                {
                    std::lock_guard<std::mutex> lock(task->mutex);
                    task->running = false;
                }
                emit_progress(task);
                return;
            }

            delete_file(file.destination_path.c_str());
            final_path = task->model_folder_path;
        } else {
            final_path = file.destination_path;
        }

        if (total_expected > 0) {
            completed_before_file += std::max<int64_t>(file.expected_bytes, 0);
        }
    }

    if (task->cancel_requested.load()) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED,
                          rav1::DOWNLOAD_STAGE_DOWNLOADING, completed_before_file, total_expected,
                          0, "", "", "download cancelled");
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            task->running = false;
        }
        emit_progress(task);
        return;
    }

    set_task_progress(task, rav1::DOWNLOAD_STATE_COMPLETED, rav1::DOWNLOAD_STAGE_COMPLETED,
                      total_expected, total_expected, static_cast<int32_t>(task->files.size() - 1),
                      task->files.empty() ? "" : task->files.back().storage_key, final_path, "");
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = false;
    }
    emit_progress(task);
}

std::string destination_from_model_file(const std::string& model_folder,
                                        const rav1::ModelFileDescriptor& file,
                                        const std::string& url,
                                        const std::string& fallback_model_id) {
    if (file.has_destination_path() && !file.destination_path().empty()) {
        return is_absolute_path(file.destination_path())
                   ? file.destination_path()
                   : join_path(model_folder, file.destination_path());
    }
    std::string filename = file.filename();
    if (filename.empty()) {
        filename = get_filename(url.c_str());
    }
    if (filename.empty()) {
        filename = fallback_model_id;
    }
    return join_path(model_folder, filename);
}

void append_planned_file(rav1::DownloadPlanResult* result,
                         const rav1::ModelFileDescriptor& descriptor,
                         const std::string& model_folder,
                         const std::string& model_id,
                         const std::string& url,
                         int64_t expected_bytes,
                         const std::string& checksum_sha256,
                         bool requires_extraction) {
    rav1::DownloadFilePlan* out_file = result->add_files();
    copy_file_descriptor_plan(descriptor, out_file);
    if (out_file->file().url().empty()) {
        out_file->mutable_file()->set_url(url);
    }
    std::string destination =
        destination_from_model_file(model_folder, out_file->file(), url, model_id);

    if (requires_extraction) {
        char computed[4096];
        rac_bool_t ignored = RAC_FALSE;
        if (rac_download_compute_destination(model_id.c_str(), url.c_str(), RAC_FRAMEWORK_LLAMACPP,
                                             RAC_MODEL_FORMAT_UNKNOWN, computed,
                                             sizeof(computed), &ignored) == RAC_SUCCESS) {
            destination = computed;
        }
    }

    std::string filename = get_filename(url.c_str());
    if (filename.empty()) {
        filename = model_id;
    }

    out_file->set_storage_key("model://" + model_id + "/" + filename);
    out_file->set_destination_path(destination);
    out_file->set_expected_bytes(expected_bytes);
    out_file->set_requires_extraction(requires_extraction);
    out_file->set_checksum_sha256(checksum_sha256);
}

std::vector<proto_plan_file> files_from_plan(const rav1::DownloadPlanResult& plan) {
    std::vector<proto_plan_file> files;
    files.reserve(static_cast<size_t>(plan.files_size()));
    for (const auto& input : plan.files()) {
        proto_plan_file file;
        file.url = input.file().url();
        file.destination_path = input.destination_path();
        file.storage_key = input.storage_key();
        file.expected_bytes = input.expected_bytes();
        file.checksum_sha256 = input.checksum_sha256();
        file.requires_extraction = input.requires_extraction();
        files.push_back(std::move(file));
    }
    return files;
}

}  // namespace
#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// POST-EXTRACTION MODEL PATH FINDING (ported from Swift ExtractionService)
// =============================================================================

/**
 * Find a single model file in a directory, searching recursively up to max_depth levels.
 * Ported from Swift's ExtractionService.findSingleModelFile().
 */
static bool find_single_model_file(const char* directory, int depth, int max_depth, char* out_path,
                                   size_t path_size) {
    if (depth >= max_depth)
        return false;

    DIR* dir = opendir(directory);
    if (!dir)
        return false;

    struct dirent* entry;
    std::string found_model;
    std::vector<std::string> subdirs;

    while ((entry = readdir(dir)) != nullptr) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        // Skip hidden files and macOS resource forks
        if (entry->d_name[0] == '.')
            continue;

        std::string full_path = std::string(directory) + "/" + entry->d_name;

        struct stat st;
        if (stat(full_path.c_str(), &st) != 0)
            continue;

        if (S_ISREG(st.st_mode)) {
            // Check if this is a model file
            const char* dot = strrchr(entry->d_name, '.');
            if (dot && is_model_extension(dot + 1)) {
                found_model = full_path;
                break;  // Found it
            }
        } else if (S_ISDIR(st.st_mode)) {
            subdirs.push_back(full_path);
        }
    }
    closedir(dir);

    if (!found_model.empty()) {
        snprintf(out_path, path_size, "%s", found_model.c_str());
        return true;
    }

    // Recursively check subdirectories
    for (const auto& subdir : subdirs) {
        if (find_single_model_file(subdir.c_str(), depth + 1, max_depth, out_path, path_size)) {
            return true;
        }
    }

    return false;
}

/**
 * Find the nested directory (single visible subdirectory) in an extracted archive.
 * Ported from Swift's ExtractionService.findNestedDirectory().
 *
 * Common pattern: archive contains one subdirectory with all the files.
 * e.g., sherpa-onnx archives extract to: extractedDir/vits-xxx/
 */
static std::string find_nested_directory(const char* extracted_dir) {
    DIR* dir = opendir(extracted_dir);
    if (!dir)
        return extracted_dir;

    struct dirent* entry;
    std::vector<std::string> visible_dirs;

    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        // Skip hidden files and macOS resource forks
        if (entry->d_name[0] == '.')
            continue;
        if (strncmp(entry->d_name, "._", 2) == 0)
            continue;

        std::string full_path = std::string(extracted_dir) + "/" + entry->d_name;

        struct stat st;
        if (stat(full_path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
            visible_dirs.push_back(full_path);
        }
    }
    closedir(dir);

    // If there's exactly one visible subdirectory, return it
    if (visible_dirs.size() == 1) {
        return visible_dirs[0];
    }

    if (visible_dirs.size() > 1) {
        RAC_LOG_WARNING(LOG_TAG,
                        "find_nested_directory: found %zu subdirectories in '%s', "
                        "falling back to root (expected exactly 1)",
                        visible_dirs.size(), extracted_dir);
    }

    return extracted_dir;
}

// =============================================================================
// ORCHESTRATION CONTEXT (passed through HTTP callbacks)
// =============================================================================

struct orchestrate_context {
    // Download manager handle
    rac_download_manager_handle_t dm_handle;

    // Model info
    std::string model_id;
    std::string download_url;
    rac_inference_framework_t framework;
    rac_model_format_t format;
    rac_archive_structure_t archive_structure;

    // Paths
    std::string download_dest_path;  // Where HTTP downloads to
    std::string model_folder_path;   // Final model folder
    bool needs_extraction;

    // Task tracking
    std::string task_id;

    // User callbacks
    rac_download_progress_callback_fn user_progress_callback;
    rac_download_complete_callback_fn user_complete_callback;
    void* user_data;
};

/**
 * Prevent double-free of orchestrate_context when async callbacks race with error paths.
 *
 * The context is wrapped in a shared_ptr stored in a shared_ctx_holder.
 * The holder is passed as raw void* to C callbacks.
 * Both the caller and the callback own a reference via the shared_ptr,
 * ensuring the context outlives all users.
 */
struct shared_ctx_holder {
    std::shared_ptr<orchestrate_context> ctx;
};

/**
 * HTTP progress callback — forwards to download manager which recalculates overall progress.
 *
 * Adapts the `rac_http_download_progress_fn` signature (uint64 / rac_bool_t return) to
 * the existing `orchestrate_context` / download-manager progress API. Returning RAC_TRUE
 * keeps the transfer going — the orchestrator currently never cancels from inside
 * progress itself (download-manager observes cancellation separately).
 */
static rac_bool_t orchestrate_http_progress(uint64_t bytes_downloaded, uint64_t total_bytes,
                                            void* callback_user_data) {
    auto* holder = static_cast<shared_ctx_holder*>(callback_user_data);
    if (!holder || !holder->ctx || !holder->ctx->dm_handle)
        return RAC_TRUE;

    auto& ctx = holder->ctx;
    rac_download_manager_update_progress(ctx->dm_handle, ctx->task_id.c_str(),
                                         static_cast<int64_t>(bytes_downloaded),
                                         static_cast<int64_t>(total_bytes));
    return RAC_TRUE;
}

/**
 * HTTP completion callback — handles post-download extraction and cleanup.
 * Deletes the holder (releasing its shared_ptr reference) when done.
 */
static void orchestrate_http_complete(rac_result_t result, const char* downloaded_path,
                                      void* callback_user_data) {
    auto* holder = static_cast<shared_ctx_holder*>(callback_user_data);
    if (!holder || !holder->ctx) {
        delete holder;
        return;
    }

    // Take ownership — holder is deleted at every exit path below
    auto ctx = holder->ctx;
    delete holder;

    if (result != RAC_SUCCESS) {
        // HTTP download failed
        RAC_LOG_ERROR(LOG_TAG, "HTTP download failed for model: %s", ctx->model_id.c_str());
        rac_download_manager_mark_failed(ctx->dm_handle, ctx->task_id.c_str(), result,
                                         "HTTP download failed");

        if (ctx->user_complete_callback) {
            ctx->user_complete_callback(ctx->task_id.c_str(), result, nullptr, ctx->user_data);
        }
        return;
    }

    std::string final_path;

    if (ctx->needs_extraction) {
        // Mark download as complete (transitions to EXTRACTING state)
        rac_download_manager_mark_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                           downloaded_path ? downloaded_path
                                                           : ctx->download_dest_path.c_str());

        RAC_LOG_INFO(LOG_TAG, "Starting extraction for model: %s", ctx->model_id.c_str());

        // Extract archive using native libarchive
        rac_extraction_result_t extraction_result = {};
        rac_result_t extract_result = rac_extract_archive_native(
            downloaded_path ? downloaded_path : ctx->download_dest_path.c_str(),
            ctx->model_folder_path.c_str(), nullptr /* default options */,
            nullptr /* no progress */, nullptr /* no user data */, &extraction_result);

        if (extract_result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_TAG, "Extraction failed for model: %s", ctx->model_id.c_str());
            rac_download_manager_mark_extraction_failed(
                ctx->dm_handle, ctx->task_id.c_str(), extract_result, "Archive extraction failed");

            if (ctx->user_complete_callback) {
                ctx->user_complete_callback(ctx->task_id.c_str(), extract_result, nullptr,
                                            ctx->user_data);
            }

            // Cleanup temp archive
            delete_file(ctx->download_dest_path.c_str());
            return;
        }

        RAC_LOG_INFO(LOG_TAG, "Extraction complete: %d files, %lld bytes",
                     extraction_result.files_extracted, extraction_result.bytes_extracted);

        // Find the actual model path after extraction
        char model_path[4096];
        rac_result_t find_result = rac_find_model_path_after_extraction(
            ctx->model_folder_path.c_str(), ctx->archive_structure, ctx->framework, ctx->format,
            model_path, sizeof(model_path));

        if (find_result == RAC_SUCCESS) {
            final_path = model_path;
        } else {
            // Fallback to model folder itself
            final_path = ctx->model_folder_path;
            RAC_LOG_WARNING(LOG_TAG,
                            "Could not find specific model file after extraction, using folder: %s",
                            final_path.c_str());
        }

        // Cleanup temp archive file
        delete_file(ctx->download_dest_path.c_str());

        // Mark extraction complete
        rac_download_manager_mark_extraction_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                                      final_path.c_str());
    } else {
        // No extraction needed — file downloaded directly to model folder
        final_path = downloaded_path ? std::string(downloaded_path) : ctx->download_dest_path;

        rac_download_manager_mark_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                           final_path.c_str());
    }

    RAC_LOG_INFO(LOG_TAG, "Download orchestration complete for model: %s → %s",
                 ctx->model_id.c_str(), final_path.c_str());

    // Invoke user callback
    if (ctx->user_complete_callback) {
        ctx->user_complete_callback(ctx->task_id.c_str(), RAC_SUCCESS, final_path.c_str(),
                                    ctx->user_data);
    }
}

// =============================================================================
// PUBLIC API — DOWNLOAD ORCHESTRATION
// =============================================================================

#ifdef RAC_HAVE_PROTOBUF
extern "C" rac_result_t rac_download_set_progress_proto_callback(
    rac_download_proto_progress_callback_fn callback, void* user_data) {
    std::lock_guard<std::mutex> lock(progress_sink().mutex);
    progress_sink().callback = callback;
    progress_sink().user_data = user_data;
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_download_plan_proto(const uint8_t* request_bytes,
                                                 size_t request_size,
                                                 rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!request_bytes || request_size == 0) {
        return parse_failure(out_result, "DownloadPlanRequest bytes are required");
    }

    rav1::DownloadPlanRequest request;
    if (!request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return parse_failure(out_result, "failed to parse DownloadPlanRequest");
    }

    rav1::DownloadPlanResult result;
    std::string model_id = request.model_id();
    if (model_id.empty() && request.has_model()) {
        model_id = request.model().id();
    }
    result.set_model_id(model_id);

    if (model_id.empty()) {
        result.set_can_start(false);
        result.set_error_message("model_id is required");
        return serialize_proto_to_buffer(result, out_result);
    }
    if (!request.has_model()) {
        result.set_can_start(false);
        result.set_error_message("model metadata is required for download planning");
        return serialize_proto_to_buffer(result, out_result);
    }

    const rav1::ModelInfo& model = request.model();
    rac_inference_framework_t framework = proto_framework_to_c(model.framework());
    if (framework == RAC_FRAMEWORK_UNKNOWN) {
        framework = RAC_FRAMEWORK_LLAMACPP;
        result.add_warnings("unknown framework; using llama.cpp storage path");
    }
    rac_model_format_t format = proto_format_to_c(model.format());

    char model_folder[4096];
    rac_result_t path_rc =
        rac_model_paths_get_model_folder(model_id.c_str(), framework, model_folder,
                                         sizeof(model_folder));
    if (path_rc != RAC_SUCCESS) {
        result.set_can_start(false);
        result.set_error_message("failed to compute model storage path");
        return serialize_proto_to_buffer(result, out_result);
    }

    int64_t total_bytes = 0;
    bool all_sizes_known = true;
    bool any_extraction = false;
    std::string model_checksum = model.has_checksum_sha256() ? model.checksum_sha256() : "";

    if (model.has_expected_files() && model.expected_files().files_size() > 0) {
        for (const auto& file : model.expected_files().files()) {
            std::string url = file.url();
            if (url.empty() && !model.download_url().empty() && file.has_relative_path() &&
                !file.relative_path().empty()) {
                url = model.download_url();
                if (!url.empty() && url.back() != '/') {
                    url += "/";
                }
                url += file.relative_path();
            }

            if (!looks_like_http_url(url)) {
                result.set_can_start(false);
                result.set_error_message("invalid or missing file URL");
                return serialize_proto_to_buffer(result, out_result);
            }

            rac_archive_type_t archive_type;
            bool requires_extraction = rac_archive_type_from_path(url.c_str(), &archive_type) ==
                                       RAC_TRUE;
            any_extraction = any_extraction || requires_extraction;

            int64_t expected_bytes = file.has_size_bytes() ? file.size_bytes() : 0;
            if (expected_bytes > 0) {
                total_bytes += expected_bytes;
            } else {
                all_sizes_known = false;
            }
            std::string checksum = file.has_checksum() ? file.checksum() : "";
            append_planned_file(&result, file, model_folder, model_id, url, expected_bytes,
                                checksum, requires_extraction);
        }
    } else {
        std::string url = model.download_url();
        if (!looks_like_http_url(url)) {
            result.set_can_start(false);
            result.set_error_message("model.download_url must be an http(s) URL");
            return serialize_proto_to_buffer(result, out_result);
        }

        rac_bool_t needs_extraction = RAC_FALSE;
        char destination[4096];
        rac_result_t dest_rc = rac_download_compute_destination(
            model_id.c_str(), url.c_str(), framework, format, destination, sizeof(destination),
            &needs_extraction);
        if (dest_rc != RAC_SUCCESS) {
            result.set_can_start(false);
            result.set_error_message("failed to compute download destination");
            return serialize_proto_to_buffer(result, out_result);
        }

        rav1::ModelFileDescriptor descriptor;
        descriptor.set_url(url);
        descriptor.set_filename(get_filename(url.c_str()));
        descriptor.set_destination_path(destination);
        if (model.download_size_bytes() > 0) {
            descriptor.set_size_bytes(model.download_size_bytes());
        }
        descriptor.set_is_required(true);

        int64_t expected_bytes = model.download_size_bytes();
        if (expected_bytes > 0) {
            total_bytes += expected_bytes;
        } else {
            all_sizes_known = false;
        }
        any_extraction = needs_extraction == RAC_TRUE;
        append_planned_file(&result, descriptor, model_folder, model_id, url, expected_bytes,
                            model_checksum, any_extraction);
        result.mutable_files(0)->set_destination_path(destination);
    }

    if (!all_sizes_known) {
        total_bytes = 0;
        result.add_warnings("one or more file sizes are unknown");
    }

    int64_t resume_from = 0;
    if (request.resume_existing() && result.files_size() > 0) {
        resume_from = file_size_or_zero(result.files(0).destination_path());
    }

    if (request.available_storage_bytes() > 0 && total_bytes > 0 &&
        total_bytes > request.available_storage_bytes()) {
        result.set_can_start(false);
        result.set_error_message("insufficient storage for planned download");
    } else {
        result.set_can_start(result.files_size() > 0);
    }
    result.set_total_bytes(total_bytes);
    result.set_requires_extraction(any_extraction);
    result.set_can_resume(resume_from > 0);
    result.set_resume_from_bytes(resume_from);

    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_start_proto(const uint8_t* request_bytes,
                                                  size_t request_size,
                                                  rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!request_bytes || request_size == 0) {
        return parse_failure(out_result, "DownloadStartRequest bytes are required");
    }

    rav1::DownloadStartRequest request;
    if (!request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return parse_failure(out_result, "failed to parse DownloadStartRequest");
    }

    rav1::DownloadStartResult result;
    std::string model_id = request.model_id().empty() ? request.plan().model_id()
                                                      : request.model_id();
    result.set_model_id(model_id);

    if (model_id.empty() || !request.has_plan() || request.plan().files_size() == 0 ||
        !request.plan().can_start()) {
        result.set_accepted(false);
        result.set_error_message("start request requires a startable plan");
        return serialize_proto_to_buffer(result, out_result);
    }
    if (!rac_http_transport_is_registered()) {
        result.set_accepted(false);
        result.set_error_message("no HTTP transport adapter registered");
        return serialize_proto_to_buffer(result, out_result);
    }

    auto task = std::make_shared<proto_download_task>();
    task->model_id = model_id;
    task->files = files_from_plan(request.plan());
    task->task_id = "download-proto-" + std::to_string(proto_state().next_task_id.fetch_add(1));

    fs::path first_dest(task->files.front().destination_path);
    if (first_dest.has_parent_path()) {
        task->model_folder_path = first_dest.parent_path().string();
    }
    if (task->model_folder_path.empty()) {
        task->model_folder_path = ".";
    }

    set_task_progress(task, request.resume() ? rav1::DOWNLOAD_STATE_RESUMING
                                             : rav1::DOWNLOAD_STATE_PENDING,
                      rav1::DOWNLOAD_STAGE_DOWNLOADING, 0, request.plan().total_bytes(), 0,
                      task->files.front().storage_key, "", "");
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = true;
    }
    {
        std::lock_guard<std::mutex> lock(proto_state().mutex);
        proto_state().tasks[task->task_id] = task;
    }

    result.set_accepted(true);
    result.set_task_id(task->task_id);
    *result.mutable_initial_progress() = task->progress;

    int64_t resume_from = request.resume() ? request.plan().resume_from_bytes() : 0;
    std::thread([task, resume_from]() {
        run_proto_download_worker(std::move(task), resume_from);
    }).detach();

    emit_progress(task);
    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_cancel_proto(const uint8_t* request_bytes,
                                                   size_t request_size,
                                                   rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!request_bytes || request_size == 0) {
        return parse_failure(out_result, "DownloadCancelRequest bytes are required");
    }

    rav1::DownloadCancelRequest request;
    if (!request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return parse_failure(out_result, "failed to parse DownloadCancelRequest");
    }

    rav1::DownloadCancelResult result;
    result.set_task_id(request.task_id());
    result.set_model_id(request.model_id());

    auto task = find_task(request.task_id(), request.model_id());
    if (!task) {
        result.set_success(false);
        result.set_error_message("download task not found");
        return serialize_proto_to_buffer(result, out_result);
    }

    int64_t deleted = 0;
    bool was_running = false;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->cancel_requested.store(true);
        task->delete_partial_on_cancel = request.delete_partial_bytes();
        was_running = task->running;
        result.set_task_id(task->task_id);
        result.set_model_id(task->model_id);
        if (!task->running && request.delete_partial_bytes() && !task->files.empty()) {
            deleted = delete_partial_file(task->files.front().destination_path);
        }
        if (!task->running) {
            task->progress.set_state(rav1::DOWNLOAD_STATE_CANCELLED);
            task->progress.set_error_message("download cancelled");
        }
    }

    result.set_success(true);
    result.set_partial_bytes_deleted(deleted);
    if (!was_running) {
        emit_progress(task);
    }
    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_resume_proto(const uint8_t* request_bytes,
                                                   size_t request_size,
                                                   rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!request_bytes || request_size == 0) {
        return parse_failure(out_result, "DownloadResumeRequest bytes are required");
    }

    rav1::DownloadResumeRequest request;
    if (!request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return parse_failure(out_result, "failed to parse DownloadResumeRequest");
    }

    rav1::DownloadResumeResult result;
    result.set_task_id(request.task_id());
    result.set_model_id(request.model_id());

    auto task = find_task(request.task_id(), request.model_id());
    if (!task) {
        result.set_accepted(false);
        result.set_error_message("download task not found");
        return serialize_proto_to_buffer(result, out_result);
    }
    if (!rac_http_transport_is_registered()) {
        result.set_accepted(false);
        result.set_error_message("no HTTP transport adapter registered");
        return serialize_proto_to_buffer(result, out_result);
    }

    int64_t resume_from = request.resume_from_bytes();
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        if (task->running) {
            result.set_accepted(false);
            result.set_error_message("download task is already running");
            return serialize_proto_to_buffer(result, out_result);
        }
        if (resume_from <= 0 && !task->files.empty()) {
            resume_from = file_size_or_zero(task->files.front().destination_path);
        }
        task->cancel_requested.store(false);
        task->delete_partial_on_cancel = false;
        task->running = true;
        task->progress.set_state(rav1::DOWNLOAD_STATE_RESUMING);
        task->progress.set_stage(rav1::DOWNLOAD_STAGE_DOWNLOADING);
        task->progress.set_error_message("");
        task->progress.set_bytes_downloaded(resume_from);
    }

    result.set_accepted(true);
    result.set_task_id(task->task_id);
    result.set_model_id(task->model_id);
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        *result.mutable_initial_progress() = task->progress;
    }

    std::thread([task, resume_from]() {
        run_proto_download_worker(std::move(task), resume_from);
    }).detach();

    emit_progress(task);
    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_progress_poll_proto(const uint8_t* request_bytes,
                                                          size_t request_size,
                                                          rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!request_bytes || request_size == 0) {
        return parse_failure(out_result, "DownloadSubscribeRequest bytes are required");
    }

    rav1::DownloadSubscribeRequest request;
    if (!request.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return parse_failure(out_result, "failed to parse DownloadSubscribeRequest");
    }

    auto task = find_task(request.task_id(), request.model_id());
    if (!task) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_FOUND,
                                          "download task not found");
    }

    rav1::DownloadProgress progress;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        progress = task->progress;
    }
    return serialize_proto_to_buffer(progress, out_result);
}
#else
extern "C" rac_result_t rac_download_set_progress_proto_callback(
    rac_download_proto_progress_callback_fn, void*) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

extern "C" rac_result_t rac_download_plan_proto(const uint8_t*, size_t,
                                                 rac_proto_buffer_t* out_result) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                   "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

extern "C" rac_result_t rac_download_start_proto(const uint8_t*, size_t,
                                                  rac_proto_buffer_t* out_result) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                   "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

extern "C" rac_result_t rac_download_cancel_proto(const uint8_t*, size_t,
                                                   rac_proto_buffer_t* out_result) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                   "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

extern "C" rac_result_t rac_download_resume_proto(const uint8_t*, size_t,
                                                   rac_proto_buffer_t* out_result) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                   "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

extern "C" rac_result_t rac_download_progress_poll_proto(const uint8_t*, size_t,
                                                          rac_proto_buffer_t* out_result) {
    if (out_result) {
        rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                   "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}
#endif

rac_result_t rac_download_orchestrate(rac_download_manager_handle_t dm_handle, const char* model_id,
                                      const char* download_url, rac_inference_framework_t framework,
                                      rac_model_format_t format,
                                      rac_archive_structure_t archive_structure,
                                      rac_download_progress_callback_fn progress_callback,
                                      rac_download_complete_callback_fn complete_callback,
                                      void* user_data, char** out_task_id) {
    if (!dm_handle || !model_id || !download_url || !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // 1. Compute model folder path
    char model_folder[4096];
    rac_result_t path_result =
        rac_model_paths_get_model_folder(model_id, framework, model_folder, sizeof(model_folder));
    if (path_result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to compute model folder path for: %s", model_id);
        return path_result;
    }

    // Ensure model folder exists
    mkdir_p(model_folder);

    // 2. Determine if extraction is needed
    rac_archive_type_t archive_type;
    bool needs_extraction = rac_archive_type_from_path(download_url, &archive_type) == RAC_TRUE;

    // 3. Compute download destination
    std::string download_dest;
    if (needs_extraction) {
        // Download to temp path — will be extracted to model folder
        char downloads_dir[4096];
        rac_result_t dl_result =
            rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir));
        if (dl_result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_TAG, "Failed to get downloads directory");
            return dl_result;
        }
        mkdir_p(downloads_dir);

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty())
            stem = model_id;

        download_dest = std::string(downloads_dir) + "/" + stem + (ext.empty() ? "" : "." + ext);
    } else {
        // Download directly to model folder
        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty())
            stem = model_id;

        download_dest = std::string(model_folder) + "/" + stem + (ext.empty() ? "" : "." + ext);
    }

    // 4. Register with download manager (creates task tracking state)
    char* task_id = nullptr;
    rac_result_t start_result =
        rac_download_manager_start(dm_handle, model_id, download_url, download_dest.c_str(),
                                   needs_extraction ? RAC_TRUE : RAC_FALSE, progress_callback,
                                   nullptr /* we handle complete */, user_data, &task_id);

    if (start_result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to register download task for: %s", model_id);
        return start_result;
    }

    // 5. Create orchestration context for callbacks (shared_ptr for safe async lifetime)
    auto ctx = std::make_shared<orchestrate_context>();
    ctx->dm_handle = dm_handle;
    ctx->model_id = model_id;
    ctx->download_url = download_url;
    ctx->framework = framework;
    ctx->format = format;
    ctx->archive_structure = archive_structure;
    ctx->download_dest_path = download_dest;
    ctx->model_folder_path = model_folder;
    ctx->needs_extraction = needs_extraction;
    ctx->task_id = task_id;
    ctx->user_progress_callback = progress_callback;
    ctx->user_complete_callback = complete_callback;
    ctx->user_data = user_data;

    // Wrap in holder for C callback void* — callback takes ownership and deletes holder
    auto* holder = new shared_ctx_holder{ctx};

    // 6. Start HTTP download via the internal C++ facade (Stage 2 refactor).
    //
    // Previously this invoked the platform adapter's async `rac_http_download`
    // callback, which returned immediately and delivered the completion on a
    // platform-owned thread. The facade is synchronous, so we spawn a worker
    // thread that drives the transfer via `rac::http::execute_stream` and then
    // invokes `orchestrate_http_complete` — preserving the exact external
    // contract (function returns immediately, completion callback fires later
    // on a background thread).
    std::thread([ctx, holder, download_url_str = std::string(download_url),
                 download_dest_str = download_dest]() {
        rac_http_download_request_t dl_req{};
        dl_req.url = download_url_str.c_str();
        dl_req.destination_path = download_dest_str.c_str();
        dl_req.timeout_ms = 0;  // library default — matches old platform-adapter behaviour
        dl_req.follow_redirects = RAC_TRUE;
        dl_req.resume_from_byte = 0;
        dl_req.expected_sha256_hex = nullptr;

        int32_t http_status = 0;
        rac_http_download_status_t status = rac::http::execute_stream(
            dl_req, orchestrate_http_progress, holder, &http_status);

        // Map the download status back to rac_result_t for the existing
        // completion-callback signature. Anything non-OK maps to a download
        // failure; the specific sub-code (cancel/timeout/etc.) is still
        // available via the download manager's failure path.
        rac_result_t rc = RAC_SUCCESS;
        if (status != RAC_HTTP_DL_OK) {
            switch (status) {
                case RAC_HTTP_DL_CANCELLED:
                    rc = RAC_ERROR_CANCELLED;
                    break;
                case RAC_HTTP_DL_TIMEOUT:
                    rc = RAC_ERROR_TIMEOUT;
                    break;
                case RAC_HTTP_DL_INVALID_URL:
                    rc = RAC_ERROR_INVALID_ARGUMENT;
                    break;
                default:
                    rc = RAC_ERROR_DOWNLOAD_FAILED;
                    break;
            }
        }

        // Deliver the completion event on this worker thread — same threading
        // contract as the old platform-adapter callback (invoked from a
        // non-caller thread). orchestrate_http_complete deletes the holder.
        orchestrate_http_complete(rc, download_dest_str.c_str(), holder);
    }).detach();

    *out_task_id = task_id;

    RAC_LOG_INFO(LOG_TAG, "Download orchestration started: model=%s, extraction=%s", model_id,
                 needs_extraction ? "yes" : "no");

    return RAC_SUCCESS;
}

rac_result_t rac_download_orchestrate_multi(
    rac_download_manager_handle_t dm_handle, const char* model_id,
    const rac_model_file_descriptor_t* files, size_t file_count, const char* base_download_url,
    rac_inference_framework_t framework, rac_model_format_t format,
    rac_download_progress_callback_fn progress_callback,
    rac_download_complete_callback_fn complete_callback, void* user_data, char** out_task_id) {
    if (!dm_handle || !model_id || !files || file_count == 0 || !base_download_url ||
        !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Compute model folder
    char model_folder[4096];
    rac_result_t path_result =
        rac_model_paths_get_model_folder(model_id, framework, model_folder, sizeof(model_folder));
    if (path_result != RAC_SUCCESS) {
        return path_result;
    }
    mkdir_p(model_folder);

    // Register a single task for the multi-file download
    std::string composite_url =
        std::string(base_download_url) + " [" + std::to_string(file_count) + " files]";
    char* task_id = nullptr;
    rac_result_t start_result = rac_download_manager_start(
        dm_handle, model_id, composite_url.c_str(), model_folder, RAC_FALSE /* no extraction */,
        progress_callback, complete_callback, user_data, &task_id);

    if (start_result != RAC_SUCCESS) {
        return start_result;
    }

    // Shared state for async completion barrier across all file downloads.
    // Each launched download increments pending; its callback decrements and notifies.
    // After the loop we wait until all in-flight downloads have reported back.
    struct multi_download_barrier {
        std::mutex mtx;
        std::condition_variable cv;
        int pending{0};
        bool any_required_failed{false};
    };
    auto barrier = std::make_shared<multi_download_barrier>();

    // Per-file context passed through the C callback void*.
    struct multi_file_holder {
        std::shared_ptr<multi_download_barrier> barrier;
        bool is_required;
    };

    // Stage 2 refactor: there's no synchronous "failed to launch" path
    // anymore — spawning the worker thread itself is the only thing that
    // can fail before the request runs, and that throws. Failures are
    // now observed via `barrier->any_required_failed`.
    for (size_t i = 0; i < file_count; ++i) {
        const rac_model_file_descriptor_t& file = files[i];

        // Build full download URL
        std::string file_url = std::string(base_download_url);
        if (!file_url.empty() && file_url.back() != '/')
            file_url += "/";
        file_url += file.relative_path;

        // Build destination path
        std::string dest_path = std::string(model_folder);
        if (file.destination_path && file.destination_path[0] != '\0') {
            dest_path += "/" + std::string(file.destination_path);
        } else {
            dest_path += "/" + std::string(file.relative_path);
        }

        // Ensure parent directory exists
        auto last_slash = dest_path.rfind('/');
        if (last_slash != std::string::npos) {
            mkdir_p(dest_path.substr(0, last_slash).c_str());
        }

        // Update download manager with file-level progress
        int64_t fake_downloaded =
            static_cast<int64_t>(static_cast<double>(i) / static_cast<double>(file_count) * 100);
        rac_download_manager_update_progress(dm_handle, task_id, fake_downloaded, 100);

        // Increment pending count *before* launching so the barrier is always ahead of callbacks
        {
            std::lock_guard<std::mutex> lk(barrier->mtx);
            barrier->pending++;
        }

        auto* file_holder = new multi_file_holder{barrier, file.is_required == RAC_TRUE};

        // Stage 2 HTTP refactor: replace the async platform adapter with the
        // synchronous C++ facade driven on a detached worker thread. The
        // completion bookkeeping (barrier decrement, required-failed flag)
        // stays identical so the outer wait loop still works unchanged.
        std::thread([file_holder, file_url, dest_path]() {
            rac_http_download_request_t dl_req{};
            dl_req.url = file_url.c_str();
            dl_req.destination_path = dest_path.c_str();
            dl_req.timeout_ms = 0;
            dl_req.follow_redirects = RAC_TRUE;
            dl_req.resume_from_byte = 0;
            dl_req.expected_sha256_hex = nullptr;

            int32_t http_status = 0;
            rac_http_download_status_t status = rac::http::execute_stream(
                dl_req, nullptr /* no per-file progress */, nullptr, &http_status);

            // Emulate the old `file_complete` callback inline.
            auto b = file_holder->barrier;
            bool required = file_holder->is_required;
            delete file_holder;

            std::lock_guard<std::mutex> lk(b->mtx);
            if (status != RAC_HTTP_DL_OK && required) {
                b->any_required_failed = true;
            }
            b->pending--;
            b->cv.notify_all();
        }).detach();

        // Download started — detached thread owns file_holder
    }

    // Wait for all in-flight downloads to complete before reporting final status
    {
        std::unique_lock<std::mutex> lk(barrier->mtx);
        barrier->cv.wait(lk, [&barrier] { return barrier->pending == 0; });
    }

    bool any_failed = barrier->any_required_failed;

    if (any_failed) {
        rac_download_manager_mark_failed(dm_handle, task_id, RAC_ERROR_DOWNLOAD_FAILED,
                                         "One or more required files failed to download");
        *out_task_id = task_id;
        return RAC_ERROR_DOWNLOAD_FAILED;
    } else {
        // Update final progress
        rac_download_manager_update_progress(dm_handle, task_id, 100, 100);
        rac_download_manager_mark_complete(dm_handle, task_id, model_folder);
    }

    *out_task_id = task_id;
    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API — POST-EXTRACTION MODEL PATH FINDING
// =============================================================================

rac_result_t rac_find_model_path_after_extraction(const char* extracted_dir,
                                                  rac_archive_structure_t structure,
                                                  rac_inference_framework_t framework,
                                                  rac_model_format_t format, char* out_path,
                                                  size_t path_size) {
    if (!extracted_dir || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // For directory-based frameworks (ONNX), the directory itself is the model path
    if (rac_framework_uses_directory_based_models(framework) == RAC_TRUE) {
        // Check for nested directory pattern
        std::string nested = find_nested_directory(extracted_dir);
        snprintf(out_path, path_size, "%s", nested.c_str());
        return RAC_SUCCESS;
    }

    // Handle based on archive structure
    switch (structure) {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED: {
            // Look for a single model file, possibly in a subdirectory (up to 2 levels deep)
            if (find_single_model_file(extracted_dir, 0, 2, out_path, path_size)) {
                return RAC_SUCCESS;
            }
            // Fallback: return extracted dir
            snprintf(out_path, path_size, "%s", extracted_dir);
            return RAC_SUCCESS;
        }

        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY: {
            // Common pattern: archive contains one subdirectory with all the files
            std::string nested = find_nested_directory(extracted_dir);
            snprintf(out_path, path_size, "%s", nested.c_str());
            return RAC_SUCCESS;
        }

        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:
        case RAC_ARCHIVE_STRUCTURE_UNKNOWN:
        default: {
            // Try to find a model file first
            if (find_single_model_file(extracted_dir, 0, 2, out_path, path_size)) {
                return RAC_SUCCESS;
            }
            // Check for nested directory
            std::string nested = find_nested_directory(extracted_dir);
            snprintf(out_path, path_size, "%s", nested.c_str());
            return RAC_SUCCESS;
        }
    }
}

// =============================================================================
// PUBLIC API — UTILITY FUNCTIONS
// =============================================================================

rac_result_t rac_download_compute_destination(const char* model_id, const char* download_url,
                                              rac_inference_framework_t framework,
                                              rac_model_format_t format, char* out_path,
                                              size_t path_size, rac_bool_t* out_needs_extraction) {
    if (!model_id || !download_url || !out_path || path_size == 0 || !out_needs_extraction) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if extraction is needed
    rac_archive_type_t archive_type;
    bool needs_extraction = rac_archive_type_from_path(download_url, &archive_type) == RAC_TRUE;
    *out_needs_extraction = needs_extraction ? RAC_TRUE : RAC_FALSE;

    if (needs_extraction) {
        // Temp path in downloads directory
        char downloads_dir[4096];
        rac_result_t result =
            rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir));
        if (result != RAC_SUCCESS)
            return result;

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty())
            stem = model_id;

        snprintf(out_path, path_size, "%s/%s%s%s", downloads_dir, stem.c_str(),
                 ext.empty() ? "" : ".", ext.empty() ? "" : ext.c_str());
    } else {
        // Direct to model folder
        char model_folder[4096];
        rac_result_t result = rac_model_paths_get_model_folder(model_id, framework, model_folder,
                                                               sizeof(model_folder));
        if (result != RAC_SUCCESS)
            return result;

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty())
            stem = model_id;

        snprintf(out_path, path_size, "%s/%s%s%s", model_folder, stem.c_str(),
                 ext.empty() ? "" : ".", ext.empty() ? "" : ext.c_str());
    }

    return RAC_SUCCESS;
}

rac_bool_t rac_download_requires_extraction(const char* download_url) {
    if (!download_url)
        return RAC_FALSE;

    rac_archive_type_t type;
    return rac_archive_type_from_path(download_url, &type);
}
