// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_download.h"
#include "ra_platform_adapter.h"

#include "../model_registry/model_downloader.h"
#include "../util/extraction.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;

namespace {

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

struct Task {
    std::string                       id;
    std::string                       url;
    std::string                       destination_path;
    std::atomic<int64_t>              bytes_downloaded{0};
    std::atomic<int64_t>              total_bytes{0};
    std::atomic<int32_t>              state{RA_DOWNLOAD_STATE_PENDING};
    std::atomic<bool>                 cancel_requested{false};
    std::atomic<bool>                 paused{false};
    std::thread                       thread;
    ra_download_progress_callback_fn  progress_cb = nullptr;
    ra_download_complete_callback_fn  complete_cb = nullptr;
    void*                             user_data   = nullptr;
};

}  // namespace

struct ra_download_manager_s {
    std::mutex                                mu;
    std::map<std::string, std::shared_ptr<Task>> tasks;
    std::atomic<uint64_t>                     next_id{1};
};

namespace {

void run_task(std::shared_ptr<Task> t) {
    t->state = RA_DOWNLOAD_STATE_DOWNLOADING;

    auto downloader = ra::core::ModelDownloader::create();
    if (!downloader) {
        t->state = RA_DOWNLOAD_STATE_FAILED;
        if (t->complete_cb)
            t->complete_cb(RA_ERR_RUNTIME_UNAVAILABLE, t->id.c_str(),
                            t->destination_path.c_str(), t->user_data);
        return;
    }

    auto rc = downloader->fetch(
        t->url, t->destination_path, "",
        [&](const ra::core::DownloadProgress& p) {
            t->bytes_downloaded = static_cast<int64_t>(p.bytes_downloaded);
            t->total_bytes      = static_cast<int64_t>(p.total_bytes);
            if (t->progress_cb) {
                ra_download_progress_t prog{};
                prog.bytes_downloaded = t->bytes_downloaded;
                prog.total_bytes      = t->total_bytes;
                prog.percent          = static_cast<float>(p.percent / 100.0);
                prog.state            = RA_DOWNLOAD_STATE_DOWNLOADING;
                t->progress_cb(&prog, t->user_data);
            }
        });
    if (t->cancel_requested) {
        t->state = RA_DOWNLOAD_STATE_CANCELLED;
        if (t->complete_cb)
            t->complete_cb(RA_ERR_CANCELLED, t->id.c_str(),
                            t->destination_path.c_str(), t->user_data);
        return;
    }
    t->state = (rc == RA_OK) ? RA_DOWNLOAD_STATE_COMPLETE
                                : RA_DOWNLOAD_STATE_FAILED;
    if (t->complete_cb)
        t->complete_cb(rc, t->id.c_str(), t->destination_path.c_str(), t->user_data);
}

}  // namespace

extern "C" {

ra_status_t ra_download_manager_create(ra_download_manager_t** out_manager) {
    if (!out_manager) return RA_ERR_INVALID_ARGUMENT;
    *out_manager = new (std::nothrow) ra_download_manager_s();
    return *out_manager ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_download_manager_destroy(ra_download_manager_t* manager) {
    if (!manager) return;
    {
        std::lock_guard lock(manager->mu);
        for (auto& [id, t] : manager->tasks) {
            t->cancel_requested = true;
            if (t->thread.joinable()) t->thread.detach();
        }
    }
    delete manager;
}

ra_download_manager_t* ra_download_manager_global(void) {
    static ra_download_manager_t* g = nullptr;
    static std::once_flag flag;
    std::call_once(flag, [&]() { ra_download_manager_create(&g); });
    return g;
}

ra_status_t ra_download_manager_start(ra_download_manager_t*           manager,
                                       const char*                      url,
                                       const char*                      destination_path,
                                       const char*                      /*expected_sha256*/,
                                       ra_download_progress_callback_fn progress_cb,
                                       ra_download_complete_callback_fn complete_cb,
                                       void*                            user_data,
                                       char**                           out_task_id) {
    if (!manager || !url || !destination_path || !out_task_id) return RA_ERR_INVALID_ARGUMENT;
    auto t = std::make_shared<Task>();
    t->id               = "task-" + std::to_string(manager->next_id.fetch_add(1));
    t->url              = url;
    t->destination_path = destination_path;
    t->progress_cb      = progress_cb;
    t->complete_cb      = complete_cb;
    t->user_data        = user_data;
    {
        std::lock_guard lock(manager->mu);
        manager->tasks[t->id] = t;
    }
    auto task_copy = t;
    t->thread = std::thread([task_copy]() { run_task(task_copy); });
    *out_task_id = dup_cstr(t->id);
    return *out_task_id ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_download_manager_cancel(ra_download_manager_t* manager, const char* task_id) {
    if (!manager || !task_id) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(manager->mu);
    auto it = manager->tasks.find(task_id);
    if (it == manager->tasks.end()) return RA_ERR_INVALID_ARGUMENT;
    it->second->cancel_requested = true;
    return RA_OK;
}

ra_status_t ra_download_manager_pause_all(ra_download_manager_t* manager) {
    if (!manager) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(manager->mu);
    for (auto& [id, t] : manager->tasks) t->paused = true;
    return RA_OK;
}

ra_status_t ra_download_manager_resume_all(ra_download_manager_t* manager) {
    if (!manager) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(manager->mu);
    for (auto& [id, t] : manager->tasks) t->paused = false;
    return RA_OK;
}

ra_status_t ra_download_manager_get_progress(ra_download_manager_t*  manager,
                                              const char*             task_id,
                                              ra_download_progress_t* out_progress) {
    if (!manager || !task_id || !out_progress) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(manager->mu);
    auto it = manager->tasks.find(task_id);
    if (it == manager->tasks.end()) return RA_ERR_INVALID_ARGUMENT;
    auto& t = *it->second;
    out_progress->bytes_downloaded = t.bytes_downloaded;
    out_progress->total_bytes      = t.total_bytes;
    out_progress->percent          = t.total_bytes > 0
        ? static_cast<float>(t.bytes_downloaded) / t.total_bytes : 0.0f;
    out_progress->state            = t.state;
    return RA_OK;
}

ra_status_t ra_download_manager_get_active_tasks(ra_download_manager_t* manager,
                                                  char***                out_ids,
                                                  int32_t*               out_count) {
    if (!manager || !out_ids || !out_count) return RA_ERR_INVALID_ARGUMENT;
    std::lock_guard lock(manager->mu);
    std::vector<std::string> ids;
    for (auto& [id, t] : manager->tasks) {
        const auto s = t->state.load();
        if (s == RA_DOWNLOAD_STATE_DOWNLOADING || s == RA_DOWNLOAD_STATE_PENDING ||
            s == RA_DOWNLOAD_STATE_EXTRACTING || s == RA_DOWNLOAD_STATE_PAUSED) {
            ids.push_back(id);
        }
    }
    *out_count = static_cast<int32_t>(ids.size());
    if (ids.empty()) { *out_ids = nullptr; return RA_OK; }
    *out_ids = static_cast<char**>(std::malloc(ids.size() * sizeof(char*)));
    if (!*out_ids) return RA_ERR_OUT_OF_MEMORY;
    for (std::size_t i = 0; i < ids.size(); ++i) (*out_ids)[i] = dup_cstr(ids[i]);
    return RA_OK;
}

uint8_t ra_download_requires_extraction(const char* archive_path) {
    if (!archive_path) return 0;
    std::string p = archive_path;
    auto ends = [&](std::string_view sfx) {
        return p.size() >= sfx.size() &&
            std::equal(p.end() - sfx.size(), p.end(), sfx.begin(), sfx.end());
    };
    return (ends(".zip") || ends(".tar") || ends(".tar.gz") || ends(".tgz") ||
            ends(".tar.bz2") || ends(".tar.xz")) ? 1 : 0;
}

ra_status_t ra_download_compute_destination(const char* models_root,
                                             const char* model_id,
                                             const char* url,
                                             char**      out_path) {
    if (!models_root || !model_id || !url || !out_path) return RA_ERR_INVALID_ARGUMENT;
    fs::path p = fs::path(models_root) / model_id;
    std::string_view u{url};
    auto slash = u.find_last_of('/');
    std::string filename = (slash == std::string_view::npos) ? std::string(u)
                                                              : std::string(u.substr(slash + 1));
    if (filename.empty()) filename = "model.bin";
    p /= filename;
    *out_path = dup_cstr(p.string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_find_model_path_after_extraction(const char* extracted_dir,
                                                 char**      out_model_path) {
    if (!extracted_dir || !out_model_path) return RA_ERR_INVALID_ARGUMENT;
    fs::path root = extracted_dir;
    if (!fs::exists(root) || !fs::is_directory(root)) return RA_ERR_IO;
    fs::path best;
    std::uintmax_t best_size = 0;
    for (auto& e : fs::recursive_directory_iterator(root)) {
        if (!e.is_regular_file()) continue;
        const auto ext = e.path().extension().string();
        if (ext != ".gguf" && ext != ".onnx" && ext != ".bin" &&
            ext != ".safetensors" && ext != ".mlmodelc" && ext != ".pte")
            continue;
        const auto sz = e.file_size();
        if (sz > best_size) { best_size = sz; best = e.path(); }
    }
    if (best.empty()) return RA_ERR_MODEL_NOT_FOUND;
    *out_model_path = dup_cstr(best.string());
    return *out_model_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_download_orchestrate(const char* url,
                                     const char* destination_path,
                                     const char* expected_sha256,
                                     ra_download_progress_callback_fn progress_cb,
                                     void*                            user_data,
                                     char**                           out_final_path) {
    if (!url || !destination_path || !out_final_path) return RA_ERR_INVALID_ARGUMENT;

    auto downloader = ra::core::ModelDownloader::create();
    if (!downloader) return RA_ERR_RUNTIME_UNAVAILABLE;

    auto rc = downloader->fetch(
        url, destination_path, expected_sha256 ? expected_sha256 : "",
        [&](const ra::core::DownloadProgress& p) {
            if (progress_cb) {
                ra_download_progress_t prog{};
                prog.bytes_downloaded = static_cast<int64_t>(p.bytes_downloaded);
                prog.total_bytes      = static_cast<int64_t>(p.total_bytes);
                prog.percent          = static_cast<float>(p.percent / 100.0);
                prog.state            = RA_DOWNLOAD_STATE_DOWNLOADING;
                progress_cb(&prog, user_data);
            }
        });
    if (rc != RA_OK) return rc;

    fs::path final_path = destination_path;
    if (ra_download_requires_extraction(destination_path)) {
        if (progress_cb) {
            ra_download_progress_t prog{};
            prog.state = RA_DOWNLOAD_STATE_EXTRACTING;
            prog.percent = 0.0f;
            progress_cb(&prog, user_data);
        }
        fs::path dest_dir = fs::path(destination_path).parent_path();
#ifndef RA_NO_EXTRACTION
        auto er = ra::core::util::extract_archive(destination_path, dest_dir.string());
        if (!er.ok) return er.status;
#else
        // Platform without libarchive — frontend must call its own extractor
        // via the platform adapter (ra_extract_archive_via_adapter).
        return RA_ERR_CAPABILITY_UNSUPPORTED;
#endif
        char* model_path = nullptr;
        rc = ra_find_model_path_after_extraction(dest_dir.string().c_str(), &model_path);
        if (rc != RA_OK) return rc;
        final_path = model_path;
        std::free(model_path);
    }
    *out_final_path = dup_cstr(final_path.string());
    return *out_final_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_download_string_free(char* s) { if (s) std::free(s); }
void ra_download_task_free(ra_download_task_t* task) {
    if (!task) return;
    if (task->task_id)          std::free(task->task_id);
    if (task->url)              std::free(task->url);
    if (task->destination_path) std::free(task->destination_path);
    *task = ra_download_task_t{};
}
void ra_download_task_ids_free(char** ids, int32_t count) {
    if (!ids) return;
    for (int32_t i = 0; i < count; ++i) std::free(ids[i]);
    std::free(ids);
}

}  // extern "C"
