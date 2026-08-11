// download_bridge.cpp — the commons download orchestrator and storage analyzer
// over the proto ABI.
//
// Downloads are handle-free: rac_download_*_proto keys every task by model id
// and task id inside commons, and progress arrives on one process-wide callback
// rather than per call, so the subscription here is a long-lived
// ThreadSafeFunction instead of the per-stream session the inference bridges use.
//
// Storage is the opposite shape: rac_storage_analyzer_*_proto all take a handle
// built from a rac_storage_callbacks_t, so this file owns the one analyzer the
// process needs and fills its callbacks with std::filesystem. Deletion is a
// platform-adapter boundary by design — commons decides what is safe to remove
// and only the delete_path callback below actually removes it.

#include "download_bridge.h"

#include "proto_bridge.h"

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

namespace fs = std::filesystem;

namespace rac_electron {
namespace {

// ---------------------------------------------------------------------------
// Download progress subscription
// ---------------------------------------------------------------------------

std::mutex g_progress_mutex;
Napi::ThreadSafeFunction g_progress_emit;
bool g_progress_active = false;

// Commons recycles its emitted buffer after 32 further emissions, so the bytes
// are copied here before they are queued for the event loop.
void ForwardProgress(const uint8_t* proto_bytes, size_t proto_size, void*) {
    if (!proto_bytes || proto_size == 0) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_progress_mutex);
    if (!g_progress_active) {
        return;
    }
    auto* payload = new std::vector<uint8_t>(proto_bytes, proto_bytes + proto_size);
    const napi_status status = g_progress_emit.NonBlockingCall(
        payload, [](Napi::Env env, Napi::Function callback, std::vector<uint8_t>* bytes) {
            callback.Call({Napi::Buffer<uint8_t>::Copy(env, bytes->data(), bytes->size())});
            delete bytes;
        });
    if (status != napi_ok) {
        delete payload;
    }
}

void DetachProgress() {
    // Clear commons' pointer BEFORE taking the mutex: an emit already inside
    // ForwardProgress holds this mutex while commons holds its own, so taking
    // them in the other order here would deadlock the two.
    rac_download_set_progress_proto_callback(nullptr, nullptr);
    std::lock_guard<std::mutex> lock(g_progress_mutex);
    if (!g_progress_active) {
        return;
    }
    g_progress_active = false;
    g_progress_emit.Release();
}

Napi::Value SubscribeProgress(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsFunction()) {
        throw Napi::TypeError::New(env, "downloadSubscribeProgress(onProgress) expects a function");
    }
    DetachProgress();
    {
        std::lock_guard<std::mutex> lock(g_progress_mutex);
        g_progress_emit = Napi::ThreadSafeFunction::New(env, info[0].As<Napi::Function>(),
                                                        "runanywhere_download_progress", 0, 1);
        // A subscription that is merely open must not keep node alive; only an
        // in-flight download should, and that is the worker's own business.
        g_progress_emit.Unref(env);
        g_progress_active = true;
    }
    const rac_result_t rc = rac_download_set_progress_proto_callback(ForwardProgress, nullptr);
    if (rc != RAC_SUCCESS) {
        DetachProgress();
        ThrowProtoError(env, rc, "rac_download_set_progress_proto_callback");
    }
    return env.Undefined();
}

Napi::Value UnsubscribeProgress(const Napi::CallbackInfo& info) {
    DetachProgress();
    return info.Env().Undefined();
}

// ---------------------------------------------------------------------------
// Download workflow
// ---------------------------------------------------------------------------

Napi::Value Plan(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "download_plan", rac_download_plan_proto,
                         RequireProtoBytes(info, 0, "downloadPlanProto(requestBytes)"));
}

Napi::Value Start(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "download_start", rac_download_start_proto,
                         RequireProtoBytes(info, 0, "downloadStartProto(requestBytes)"));
}

Napi::Value Cancel(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "download_cancel", rac_download_cancel_proto,
                         RequireProtoBytes(info, 0, "downloadCancelProto(requestBytes)"));
}

Napi::Value PollProgress(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "download_progress_poll", rac_download_progress_poll_proto,
                         RequireProtoBytes(info, 0, "downloadProgressProto(requestBytes)"));
}

Napi::Value CleanupTerminal(const Napi::CallbackInfo& info) {
    auto purged = std::make_shared<size_t>(0);
    return RunNativeCall(
        info.Env(), "download_cleanup_terminal_tasks",
        [purged]() { return rac_download_cleanup_terminal_tasks_proto(purged.get()); },
        [purged](Napi::Env env) {
            return Napi::Number::New(env, static_cast<double>(*purged));
        });
}

// ---------------------------------------------------------------------------
// Storage analyzer platform callbacks
// ---------------------------------------------------------------------------

int64_t PathSize(const fs::path& path) {
    std::error_code ec;
    const fs::file_status status = fs::symlink_status(path, ec);
    if (ec) {
        return 0;
    }
    if (fs::is_regular_file(status)) {
        const auto size = fs::file_size(path, ec);
        return ec ? 0 : static_cast<int64_t>(size);
    }
    if (!fs::is_directory(status)) {
        return 0;  // symlink, socket, fifo: no bytes of its own
    }
    int64_t total = 0;
    fs::recursive_directory_iterator it(path, fs::directory_options::skip_permission_denied, ec);
    if (ec) {
        return 0;
    }
    for (const fs::directory_entry& entry : it) {
        std::error_code entry_ec;
        if (!entry.is_regular_file(entry_ec) || entry_ec) {
            continue;
        }
        const auto size = entry.file_size(entry_ec);
        if (!entry_ec) {
            total += static_cast<int64_t>(size);
        }
    }
    return total;
}

int64_t StorageDirSize(const char* path, void*) {
    return (path && *path) ? PathSize(fs::path(path)) : 0;
}

int64_t StorageFileSize(const char* path, void*) {
    if (!path || !*path) {
        return -1;
    }
    std::error_code ec;
    const auto size = fs::file_size(fs::path(path), ec);
    return ec ? -1 : static_cast<int64_t>(size);
}

rac_bool_t StoragePathExists(const char* path, rac_bool_t* is_directory, void*) {
    if (is_directory) {
        *is_directory = RAC_FALSE;
    }
    if (!path || !*path) {
        return RAC_FALSE;
    }
    std::error_code ec;
    const fs::file_status status = fs::status(fs::path(path), ec);
    if (ec || !fs::exists(status)) {
        return RAC_FALSE;
    }
    if (is_directory) {
        *is_directory = fs::is_directory(status) ? RAC_TRUE : RAC_FALSE;
    }
    return RAC_TRUE;
}

// The volume the model store lives on. The store itself may not exist yet on a
// first run, so walk up to the nearest existing ancestor rather than reporting
// zero free bytes and making every availability check fail.
fs::path StorageProbePath() {
    char base[1024] = {0};
    fs::path probe =
        rac_model_paths_get_base_directory(base, sizeof(base)) == RAC_SUCCESS && base[0] != '\0'
            ? fs::path(base)
            : fs::current_path();
    std::error_code ec;
    for (int i = 0; i < 16 && !fs::exists(probe, ec); ++i) {
        const fs::path parent = probe.parent_path();
        if (parent.empty() || parent == probe) {
            break;
        }
        probe = parent;
    }
    return probe;
}

int64_t StorageAvailableSpace(void*) {
    std::error_code ec;
    const fs::space_info space = fs::space(StorageProbePath(), ec);
    return ec ? -1 : static_cast<int64_t>(space.available);
}

int64_t StorageTotalSpace(void*) {
    std::error_code ec;
    const fs::space_info space = fs::space(StorageProbePath(), ec);
    return ec ? -1 : static_cast<int64_t>(space.capacity);
}

// The only place in this process that removes model bytes. Commons decides what
// to pass here; a path that is already gone is a completed delete, not an error,
// which is what makes models.delete() idempotent.
rac_result_t StorageDeletePath(const char* path, int recursive, void*) {
    if (!path || !*path) {
        return RAC_ERROR_INVALID_PATH;
    }
    std::error_code ec;
    const fs::path target(path);
    if (!fs::exists(fs::symlink_status(target, ec))) {
        return RAC_SUCCESS;
    }
    if (recursive) {
        fs::remove_all(target, ec);
    } else {
        fs::remove(target, ec);
    }
    return ec ? RAC_ERROR_DELETE_FAILED : RAC_SUCCESS;
}

std::mutex g_analyzer_mutex;
rac_storage_analyzer_handle_t g_analyzer = nullptr;

// is_model_loaded / unload_model stay NULL: the lifecycle store is reachable
// only through rac_model_lifecycle_current_model_proto, which needs the
// generated C++ protos this addon does not link. Commons degrades to a warning
// on the result and the SDK releases a resident model before it deletes it.
rac_result_t EnsureAnalyzer(rac_storage_analyzer_handle_t* out_handle) {
    std::lock_guard<std::mutex> lock(g_analyzer_mutex);
    if (!g_analyzer) {
        rac_storage_callbacks_t callbacks;
        std::memset(&callbacks, 0, sizeof(callbacks));
        callbacks.calculate_dir_size = StorageDirSize;
        callbacks.get_file_size = StorageFileSize;
        callbacks.path_exists = StoragePathExists;
        callbacks.get_available_space = StorageAvailableSpace;
        callbacks.get_total_space = StorageTotalSpace;
        callbacks.delete_path = StorageDeletePath;
        const rac_result_t rc = rac_storage_analyzer_create(&callbacks, &g_analyzer);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
    }
    *out_handle = g_analyzer;
    return RAC_SUCCESS;
}

using StorageProtoFn = rac_result_t (*)(rac_storage_analyzer_handle_t,
                                        rac_model_registry_handle_t, const uint8_t*, size_t,
                                        rac_proto_buffer_t*);

Napi::Promise RunStorageCall(Napi::Env env, std::string context, StorageProtoFn fn,
                             std::vector<uint8_t> request) {
    return RunProtoCall(env, std::move(context),
                        [fn, request = std::move(request)](rac_proto_buffer_t* out) {
                            rac_storage_analyzer_handle_t analyzer = nullptr;
                            const rac_result_t rc = EnsureAnalyzer(&analyzer);
                            if (rc != RAC_SUCCESS) {
                                return rc;
                            }
                            return fn(analyzer, rac_get_model_registry(),
                                      request.empty() ? nullptr : request.data(), request.size(),
                                      out);
                        });
}

Napi::Value StorageInfo(const Napi::CallbackInfo& info) {
    return RunStorageCall(info.Env(), "storage_info", rac_storage_analyzer_info_proto,
                          RequireProtoBytes(info, 0, "storageInfoProto(requestBytes)"));
}

Napi::Value StorageAvailability(const Napi::CallbackInfo& info) {
    return RunStorageCall(info.Env(), "storage_availability",
                          rac_storage_analyzer_availability_proto,
                          RequireProtoBytes(info, 0, "storageAvailabilityProto(requestBytes)"));
}

Napi::Value StorageDeletePlan(const Napi::CallbackInfo& info) {
    return RunStorageCall(info.Env(), "storage_delete_plan",
                          rac_storage_analyzer_delete_plan_proto,
                          RequireProtoBytes(info, 0, "storageDeletePlanProto(requestBytes)"));
}

Napi::Value StorageDelete(const Napi::CallbackInfo& info) {
    return RunStorageCall(info.Env(), "storage_delete", rac_storage_analyzer_delete_proto,
                          RequireProtoBytes(info, 0, "storageDeleteProto(requestBytes)"));
}

Napi::Value ProgressPercent(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsNumber() || !info[2].IsNumber()) {
        Napi::TypeError::New(env, "downloadProgressPercent(overall, bytesDownloaded, totalBytes)")
            .ThrowAsJavaScriptException();
        return env.Null();
    }
    const float overall = info[0].As<Napi::Number>().FloatValue();
    const int64_t downloaded = info[1].As<Napi::Number>().Int64Value();
    const int64_t total = info[2].As<Napi::Number>().Int64Value();
    return Napi::Number::New(env, rac_download_progress_percent(overall, downloaded, total));
}

}  // namespace

void RegisterDownloadBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("downloadPlanProto", Napi::Function::New(env, Plan));
    exports.Set("downloadStartProto", Napi::Function::New(env, Start));
    exports.Set("downloadCancelProto", Napi::Function::New(env, Cancel));
    exports.Set("downloadProgressProto", Napi::Function::New(env, PollProgress));
    exports.Set("downloadCleanupProto", Napi::Function::New(env, CleanupTerminal));
    exports.Set("downloadSubscribeProgress", Napi::Function::New(env, SubscribeProgress));
    exports.Set("downloadUnsubscribeProgress", Napi::Function::New(env, UnsubscribeProgress));
    exports.Set("downloadProgressPercent", Napi::Function::New(env, ProgressPercent));
    exports.Set("storageInfoProto", Napi::Function::New(env, StorageInfo));
    exports.Set("storageAvailabilityProto", Napi::Function::New(env, StorageAvailability));
    exports.Set("storageDeletePlanProto", Napi::Function::New(env, StorageDeletePlan));
    exports.Set("storageDeleteProto", Napi::Function::New(env, StorageDelete));
}

void ShutdownDownloadBridge() {
    DetachProgress();
    std::lock_guard<std::mutex> lock(g_analyzer_mutex);
    if (g_analyzer) {
        rac_storage_analyzer_destroy(g_analyzer);
        g_analyzer = nullptr;
    }
}

}  // namespace rac_electron
