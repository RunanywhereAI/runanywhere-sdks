// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_download.h"
#include "ra_platform_adapter.h"

#include "model_downloader.h"
#include "extraction.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
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
    std::string                       expected_sha256;     // empty = skip verify
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
        t->url, t->destination_path, t->expected_sha256,
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

    // Post-download SHA-256 verification — belt-and-braces in addition to
    // the downloader's own hash pass. If the upstream doesn't provide a
    // hash (common for public mirrors) the expected string is empty and
    // we skip this step. Mismatches are treated as fatal failures.
    if (rc == RA_OK && !t->expected_sha256.empty()) {
        const ra_status_t vrc = ra_download_verify_sha256(
            t->destination_path.c_str(), t->expected_sha256.c_str());
        if (vrc != RA_OK) {
            rc = vrc;
            std::error_code ec;
            fs::remove(t->destination_path, ec);
        }
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
                                       const char*                      expected_sha256,
                                       ra_download_progress_callback_fn progress_cb,
                                       ra_download_complete_callback_fn complete_cb,
                                       void*                            user_data,
                                       char**                           out_task_id) {
    if (!manager || !url || !destination_path || !out_task_id) return RA_ERR_INVALID_ARGUMENT;
    auto t = std::make_shared<Task>();
    t->id               = "task-" + std::to_string(manager->next_id.fetch_add(1));
    t->url              = url;
    t->destination_path = destination_path;
    t->expected_sha256  = expected_sha256 ? expected_sha256 : "";
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

ra_status_t ra_download_orchestrate_with_retry(
    const char* url,
    const char* destination_path,
    const char* expected_sha256,
    int32_t                          max_retries,
    int32_t                          base_backoff_ms,
    int32_t                          max_backoff_ms,
    ra_download_progress_callback_fn progress_cb,
    void*                            user_data,
    char**                           out_final_path) {
    if (max_retries < 0) return RA_ERR_INVALID_ARGUMENT;
    const int32_t base = base_backoff_ms > 0 ? base_backoff_ms : 500;
    const int32_t max_b = max_backoff_ms > 0 ? max_backoff_ms : 60000;
    ra_status_t last = RA_ERR_INTERNAL;
    for (int32_t attempt = 0; attempt <= max_retries; ++attempt) {
        last = ra_download_orchestrate(url, destination_path, expected_sha256,
                                        progress_cb, user_data, out_final_path);
        if (last == RA_OK || last == RA_ERR_CANCELLED ||
            last == RA_ERR_INVALID_ARGUMENT) {
            return last;
        }
        if (attempt == max_retries) break;
        int32_t wait_ms = base << attempt;
        if (wait_ms > max_b) wait_ms = max_b;
        std::this_thread::sleep_for(std::chrono::milliseconds(wait_ms));
    }
    return last;
}

ra_status_t ra_download_sha256_file(const char* file_path, char** out_hex) {
    if (!file_path || !out_hex) return RA_ERR_INVALID_ARGUMENT;
    std::error_code ec;
    if (!fs::exists(file_path, ec)) return RA_ERR_INVALID_ARGUMENT;
    // Pure-C++ SHA-256 over the file. Kept inline so we don't have to add
    // a platform-adapter hook or an OpenSSL dep for a single hash.
    constexpr std::uint32_t K[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    std::uint32_t H[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    auto rotr = [](std::uint32_t x, int n) { return (x >> n) | (x << (32 - n)); };
    auto process_block = [&](const std::uint8_t* blk) {
        std::uint32_t W[64];
        for (int i = 0; i < 16; ++i) {
            W[i] = (std::uint32_t(blk[i*4])   << 24) |
                    (std::uint32_t(blk[i*4+1]) << 16) |
                    (std::uint32_t(blk[i*4+2]) << 8)  |
                    (std::uint32_t(blk[i*4+3]));
        }
        for (int i = 16; i < 64; ++i) {
            std::uint32_t s0 = rotr(W[i-15],7) ^ rotr(W[i-15],18) ^ (W[i-15] >> 3);
            std::uint32_t s1 = rotr(W[i-2],17) ^ rotr(W[i-2],19) ^ (W[i-2] >> 10);
            W[i] = W[i-16] + s0 + W[i-7] + s1;
        }
        std::uint32_t a=H[0],b=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];
        for (int i = 0; i < 64; ++i) {
            std::uint32_t S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
            std::uint32_t ch = (e & f) ^ (~e & g);
            std::uint32_t t1 = h + S1 + ch + K[i] + W[i];
            std::uint32_t S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
            std::uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
            std::uint32_t t2 = S0 + mj;
            h = g; g = f; f = e; e = d + t1;
            d = c; c = b; b = a; a = t1 + t2;
        }
        H[0]+=a;H[1]+=b;H[2]+=c;H[3]+=d;H[4]+=e;H[5]+=f;H[6]+=g;H[7]+=h;
    };
    std::ifstream ifs(file_path, std::ios::binary);
    if (!ifs) return RA_ERR_IO;
    std::vector<std::uint8_t> buf(64);
    std::uint64_t total_bits = 0;
    while (ifs) {
        ifs.read(reinterpret_cast<char*>(buf.data()), 64);
        auto got = static_cast<std::size_t>(ifs.gcount());
        if (got == 64) { process_block(buf.data()); total_bits += 512; continue; }
        // Final partial block + padding.
        total_bits += got * 8;
        std::vector<std::uint8_t> pad(got);
        std::memcpy(pad.data(), buf.data(), got);
        pad.push_back(0x80);
        while ((pad.size() % 64) != 56) pad.push_back(0);
        for (int i = 7; i >= 0; --i) pad.push_back(static_cast<std::uint8_t>((total_bits >> (i*8)) & 0xff));
        for (std::size_t off = 0; off < pad.size(); off += 64) process_block(pad.data() + off);
        break;
    }
    char hex[65] = {};
    for (int i = 0; i < 8; ++i) {
        std::snprintf(hex + i*8, 9, "%08x", H[i]);
    }
    *out_hex = dup_cstr(std::string(hex));
    return *out_hex ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_download_verify_sha256(const char* file_path,
                                        const char* expected_hex_sha256) {
    if (!file_path || !expected_hex_sha256) return RA_ERR_INVALID_ARGUMENT;
    char* actual = nullptr;
    auto rc = ra_download_sha256_file(file_path, &actual);
    if (rc != RA_OK) return rc;
    const bool match = std::strncmp(actual, expected_hex_sha256, 64) == 0;
    std::free(actual);
    return match ? RA_OK : RA_ERR_IO;
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
