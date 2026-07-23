#include "blob_store.h"

#include <filesystem>
#include <mutex>
#include <string>
#include <system_error>
#include <unordered_set>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace rac::download::blob_store {

namespace {
namespace fs = std::filesystem;
constexpr const char* kLogTag = "BlobStore";
constexpr const char* kBlobDirName = ".blobs";

// Serializes store mutations (promote / link / GC) so a blob that is momentarily
// unreferenced mid-promote (moved into the store before its symlink exists yet) can't
// be swept by a concurrent gc_orphans() running from a delete path on another thread.
std::mutex& store_mutex() {
    static std::mutex m;
    return m;
}

// {base_dir}/RunAnywhere/Models — the root that holds per-framework model dirs + .blobs.
std::string models_root() {
    const char* base = rac_model_paths_get_base_dir();
    if (base == nullptr || base[0] == '\0') return {};
    return (fs::path(base) / "RunAnywhere" / "Models").string();
}

std::string store_dir() {
    const std::string root = models_root();
    if (root.empty()) return {};
    return (fs::path(root) / kBlobDirName).string();
}

bool is_hex(const std::string& s) {
    if (s.empty() || s.size() > 128) return false;
    for (char c : s) {
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
    }
    return true;
}

// Point `dest` at the store `blob` via a RELATIVE symlink (survives the app data dir
// moving). Android denies hardlinks on app-private storage, but symlinks are allowed
// and mmap/open follow them transparently, so the loader still sees a normal file.
bool make_symlink(const std::string& blob, const std::string& dest, std::error_code& ec) {
    const fs::path rel = fs::path(blob).lexically_relative(fs::path(dest).parent_path());
    ec.clear();
    fs::remove(dest, ec);  // clear any partial/stale target
    ec.clear();
    fs::create_symlink(rel.empty() ? fs::path(blob) : rel, dest, ec);
    return !ec;
}
}  // namespace

bool enabled() {
#if defined(__EMSCRIPTEN__)
    return false;  // OPFS/MEMFS have no symlinks — keep the per-model-copy behavior.
#else
    return !store_dir().empty();
#endif
}

std::string blob_path(const std::string& sha256_hex) {
    if (!enabled() || !is_hex(sha256_hex)) return {};
    return (fs::path(store_dir()) / sha256_hex).string();
}

bool link_from_blob(const std::string& sha256_hex, int64_t expected_bytes,
                    const std::string& dest) {
    if (!enabled() || !is_hex(sha256_hex) || dest.empty()) return false;
    const std::lock_guard<std::mutex> lock(store_mutex());
    const std::string blob = blob_path(sha256_hex);
    std::error_code ec;
    if (!fs::exists(blob, ec) || ec) return false;
    if (expected_bytes > 0) {
        const auto sz = fs::file_size(blob, ec);
        if (ec || static_cast<int64_t>(sz) != expected_bytes) return false;
    }
    if (!make_symlink(blob, dest, ec)) {
        RAC_LOG_DEBUG(kLogTag, "link_from_blob symlink failed for %s: %s", sha256_hex.c_str(),
                      ec.message().c_str());
        return false;
    }
    RAC_LOG_INFO(kLogTag, "de-dup hit: linked %s from shared blob (skipped download)",
                 sha256_hex.c_str());
    return true;
}

void promote(const std::string& sha256_hex, const std::string& dest) {
    if (!enabled() || !is_hex(sha256_hex) || dest.empty()) return;
    const std::lock_guard<std::mutex> lock(store_mutex());
    std::error_code ec;
    // Already a symlink (this file came in via a de-dup hit) — nothing to publish.
    if (fs::is_symlink(dest, ec) && !ec) return;
    ec.clear();
    if (!fs::exists(dest, ec) || ec) return;

    const std::string dir = store_dir();
    fs::create_directories(dir, ec);
    ec.clear();
    const std::string blob = blob_path(sha256_hex);

    if (!fs::exists(blob, ec)) {
        ec.clear();
        // First writer: MOVE the real file into the store, then replace dest with a
        // symlink to it. Move (rename) keeps the bytes once; dest & blob are on the
        // same filesystem (both under Models/), so rename is atomic and cheap.
        fs::rename(dest, blob, ec);
        if (ec) {  // rename unexpectedly failed — leave dest intact, skip de-dup.
            RAC_LOG_DEBUG(kLogTag, "promote(move) failed for %s: %s", sha256_hex.c_str(),
                          ec.message().c_str());
            return;
        }
        if (!make_symlink(blob, dest, ec)) {
            // Couldn't symlink — restore the file at dest so the model still loads.
            std::error_code e2;
            fs::rename(blob, dest, e2);
            RAC_LOG_DEBUG(kLogTag, "promote(symlink) failed for %s: %s", sha256_hex.c_str(),
                          ec.message().c_str());
            return;
        }
        RAC_LOG_INFO(kLogTag, "promoted content %s to shared blob store", sha256_hex.c_str());
        return;
    }
    ec.clear();
    // Blob already exists (another model / concurrent download). Reclaim dest's bytes
    // by replacing this duplicate with a symlink to the shared blob.
    if (!make_symlink(blob, dest, ec)) {
        // Restore a real file at dest from the blob so the model still loads.
        std::error_code e2;
        fs::copy_file(blob, dest, fs::copy_options::overwrite_existing, e2);
    }
}

int64_t gc_orphans() {
    if (!enabled()) return 0;
    const std::lock_guard<std::mutex> lock(store_mutex());
    const std::string dir = store_dir();
    const std::string root = models_root();
    std::error_code ec;
    if (!fs::exists(dir, ec) || ec) return 0;

    // Mark: collect every blob (by sha filename) still referenced by a model symlink.
    // Symlinks give no link-count refcount, so we scan the model tree once. Deletes
    // are infrequent and each model is a handful of files, so this stays cheap.
    std::unordered_set<std::string> referenced;
    for (auto it = fs::recursive_directory_iterator(
             root, fs::directory_options::skip_permission_denied, ec);
         !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
        const fs::path& p = it->path();
        if (p.filename() == kBlobDirName) {
            it.disable_recursion_pending();  // never descend into the store itself
            continue;
        }
        std::error_code e2;
        if (!fs::is_symlink(p, e2) || e2) continue;
        const fs::path tgt = fs::read_symlink(p, e2);
        if (e2) continue;
        referenced.insert(tgt.filename().string());  // the blob's sha filename
    }

    // If the mark pass ended on an error the `referenced` set may be incomplete;
    // sweeping now could delete a blob still linked by an unscanned model. Bail
    // out and reclaim nothing rather than risk deleting live shared content.
    if (ec) {
        RAC_LOG_WARNING(kLogTag,
                        "GC mark pass failed (%s); skipping sweep to avoid deleting live blobs",
                        ec.message().c_str());
        return 0;
    }

    // Sweep: any blob nobody references is orphaned.
    int64_t reclaimed = 0;
    ec.clear();
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (ec) break;
        std::error_code e2;
        if (!entry.is_regular_file(e2) || e2) continue;
        if (referenced.count(entry.path().filename().string()) > 0) continue;
        const auto sz = fs::file_size(entry.path(), e2);
        if (e2) continue;
        fs::remove(entry.path(), e2);
        if (!e2) reclaimed += static_cast<int64_t>(sz);
    }
    if (reclaimed > 0) {
        RAC_LOG_INFO(kLogTag, "GC reclaimed %lld bytes of orphaned shared blobs",
                     static_cast<long long>(reclaimed));
    }
    return reclaimed;
}

}  // namespace rac::download::blob_store
