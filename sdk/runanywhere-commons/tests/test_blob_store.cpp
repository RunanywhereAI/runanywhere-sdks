// Unit tests for the content-addressed blob store (blob_store.cpp).
//
// The blob store is the only download-path code that DELETES files (gc_orphans)
// and MOVES verified model bytes (promote), so its de-dup and GC invariants are
// exercised directly here rather than only through the full download orchestrator.
//
// The store keys blobs by an opaque sha256 hex string (validated as hex, never
// re-hashed against content), so these tests use fixed 64-char hex ids as content
// keys and assert on the resulting on-disk symlink/blob topology under a temp
// base dir. Symlink-only platforms: skipped where std::filesystem symlinks are
// unavailable (the store itself is disabled there and every op is a no-op).

#include "test_common.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>

#include "infrastructure/download/blob_store.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace fs = std::filesystem;
namespace bs = rac::download::blob_store;

namespace {

// Opaque 64-hex content ids (blob_store treats the sha as a key, never re-hashes).
constexpr const char* kShaA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
constexpr const char* kShaB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

int g_unique = 0;

std::string make_base() {
    std::error_code ec;
    fs::path root = fs::temp_directory_path(ec);
    if (ec) root = fs::path(".");
    const auto stamp = static_cast<unsigned long long>(
        std::chrono::steady_clock::now().time_since_epoch().count());
    fs::path base = root / ("rac_blob_test_" + std::to_string(++g_unique) + "_" +
                            std::to_string(stamp));
    fs::remove_all(base, ec);
    fs::create_directories(base, ec);
    return base.string();
}

// models_root as blob_store computes it: {base}/RunAnywhere/Models. Per-model files
// (and the .blobs store) live under here; gc scans this tree for symlinks.
fs::path models_root(const std::string& base) {
    return fs::path(base) / "RunAnywhere" / "Models";
}

fs::path model_file(const std::string& base, const std::string& model, const std::string& name) {
    return models_root(base) / "llamacpp" / model / name;
}

void write_file(const fs::path& p, const std::string& content) {
    std::error_code ec;
    fs::create_directories(p.parent_path(), ec);
    std::ofstream f(p, std::ios::binary);
    f << content;
}

std::string read_file(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

}  // namespace

// promote() publishes verified bytes into the store and swaps dest for a symlink;
// link_from_blob() then de-dups a second dest to the SAME single physical blob.
static TestResult test_promote_then_link_dedups() {
    TestResult r;
    r.test_name = "promote_then_link_dedups";

    const std::string base = make_base();
    rac_model_paths_set_base_dir(base.c_str());
    ASSERT_TRUE(bs::enabled(), "blob store must be enabled on a native FS");

    const std::string content(64 * 1024, 'A');  // >0, deterministic size
    const int64_t size = static_cast<int64_t>(content.size());

    const fs::path destA = model_file(base, "model-a", "weights.bin");
    write_file(destA, content);
    bs::promote(kShaA, destA.string());

    const fs::path blob(bs::blob_path(kShaA));
    std::error_code ec;
    ASSERT_TRUE(!blob.empty() && fs::exists(blob, ec) && !ec, "promote must publish the blob");
    ASSERT_TRUE(fs::is_symlink(destA, ec) && !ec, "dest must become a symlink after promote");
    ASSERT_TRUE(read_file(destA) == content, "content must survive promote via the symlink");
    ASSERT_TRUE(static_cast<int64_t>(fs::file_size(blob, ec)) == size && !ec,
                "blob size must match the promoted file");

    // Second model, same content: link_from_blob de-dups (no re-download).
    const fs::path destB = model_file(base, "model-b", "weights.bin");
    fs::create_directories(destB.parent_path(), ec);
    ASSERT_TRUE(bs::link_from_blob(kShaA, size, destB.string()),
                "link_from_blob must de-dup the second dest");
    ASSERT_TRUE(fs::is_symlink(destB, ec) && !ec, "de-duped dest must be a symlink");
    ASSERT_TRUE(read_file(destB) == content, "de-duped content must read back through the blob");

    // Exactly one physical copy: both symlinks resolve to the same blob file.
    ASSERT_TRUE(fs::read_symlink(destA, ec).filename() == blob.filename() && !ec,
                "destA must target the shared blob");
    ASSERT_TRUE(fs::read_symlink(destB, ec).filename() == blob.filename() && !ec,
                "destB must target the shared blob");

    fs::remove_all(base, ec);
    r.passed = true;
    return r;
}

// link_from_blob's size gate refuses a mismatched size, and a missing blob refuses
// too — the caller then falls back to a real download.
static TestResult test_link_size_gate_and_missing_blob() {
    TestResult r;
    r.test_name = "link_size_gate_and_missing_blob";

    const std::string base = make_base();
    rac_model_paths_set_base_dir(base.c_str());

    const std::string content(4096, 'A');
    const int64_t size = static_cast<int64_t>(content.size());
    const fs::path destA = model_file(base, "model-a", "weights.bin");
    write_file(destA, content);
    bs::promote(kShaA, destA.string());

    std::error_code ec;
    const fs::path destC = model_file(base, "model-c", "weights.bin");
    fs::create_directories(destC.parent_path(), ec);
    ASSERT_TRUE(!bs::link_from_blob(kShaA, size + 999, destC.string()),
                "size mismatch must refuse the de-dup");
    ASSERT_TRUE(!fs::exists(destC, ec), "no symlink may be created on a size-gate refusal");

    ASSERT_TRUE(!bs::link_from_blob(kShaB, 0, destC.string()),
                "a missing blob must refuse the de-dup");
    ASSERT_TRUE(!fs::exists(destC, ec), "no symlink may be created when the blob is absent");

    fs::remove_all(base, ec);
    r.passed = true;
    return r;
}

// promote() is a no-op when dest is already a symlink (came in via a de-dup hit):
// it must not disturb the shared blob or the link.
static TestResult test_promote_noop_when_already_symlink() {
    TestResult r;
    r.test_name = "promote_noop_when_already_symlink";

    const std::string base = make_base();
    rac_model_paths_set_base_dir(base.c_str());

    const std::string content(8192, 'A');
    const fs::path destA = model_file(base, "model-a", "weights.bin");
    write_file(destA, content);
    bs::promote(kShaA, destA.string());  // dest becomes a symlink

    std::error_code ec;
    ASSERT_TRUE(fs::is_symlink(destA, ec) && !ec, "precondition: dest is a symlink");

    bs::promote(kShaA, destA.string());  // second promote must early-return
    ASSERT_TRUE(fs::is_symlink(destA, ec) && !ec, "dest must stay a symlink after a no-op promote");
    ASSERT_TRUE(read_file(destA) == content, "content must be intact after a no-op promote");

    fs::remove_all(base, ec);
    r.passed = true;
    return r;
}

// gc_orphans never sweeps a symlink-referenced blob, reclaims only unreferenced
// ones, and reclaims a blob once its last referrer is deleted.
static TestResult test_gc_reclaims_only_orphans() {
    TestResult r;
    r.test_name = "gc_reclaims_only_orphans";

    const std::string base = make_base();
    rac_model_paths_set_base_dir(base.c_str());

    std::error_code ec;
    ASSERT_TRUE(bs::gc_orphans() == 0, "gc on an empty/nonexistent store must reclaim 0");

    const std::string content(16 * 1024, 'A');
    const int64_t size = static_cast<int64_t>(content.size());
    const fs::path destA = model_file(base, "model-a", "weights.bin");
    write_file(destA, content);
    bs::promote(kShaA, destA.string());

    const fs::path destB = model_file(base, "model-b", "weights.bin");
    fs::create_directories(destB.parent_path(), ec);
    ASSERT_TRUE(bs::link_from_blob(kShaA, size, destB.string()), "second dest must de-dup");

    // Both models reference blob A -> nothing to reclaim, blob survives.
    ASSERT_TRUE(bs::gc_orphans() == 0, "a referenced blob must not be swept");
    ASSERT_TRUE(fs::exists(fs::path(bs::blob_path(kShaA)), ec) && !ec,
                "referenced blob survives gc");

    // Drop a genuinely unreferenced blob directly into the store -> reclaimed.
    const std::string orphan(9000, 'B');
    const fs::path orphan_blob(bs::blob_path(kShaB));
    write_file(orphan_blob, orphan);
    const int64_t reclaimed = bs::gc_orphans();
    ASSERT_TRUE(reclaimed == static_cast<int64_t>(orphan.size()),
                "gc must reclaim exactly the unreferenced blob's bytes");
    ASSERT_TRUE(!fs::exists(orphan_blob, ec), "the orphan blob must be deleted");
    ASSERT_TRUE(fs::exists(fs::path(bs::blob_path(kShaA)), ec) && !ec,
                "the still-referenced blob must remain after reclaiming the orphan");

    // Delete every referrer of blob A -> its last reference is gone -> reclaimed.
    fs::remove_all(models_root(base) / "llamacpp", ec);
    const int64_t reclaimed2 = bs::gc_orphans();
    ASSERT_TRUE(reclaimed2 == size, "gc must reclaim blob A once its last referrer is deleted");
    ASSERT_TRUE(!fs::exists(fs::path(bs::blob_path(kShaA)), ec),
                "blob A must be deleted after its last referrer is gone");

    fs::remove_all(base, ec);
    r.passed = true;
    return r;
}

int main(int argc, char** argv) {
    try {
        TestSuite suite("blob_store");
        suite.add("promote_then_link_dedups", test_promote_then_link_dedups);
        suite.add("link_size_gate_and_missing_blob", test_link_size_gate_and_missing_blob);
        suite.add("promote_noop_when_already_symlink", test_promote_noop_when_already_symlink);
        suite.add("gc_reclaims_only_orphans", test_gc_reclaims_only_orphans);
        return suite.run(argc, argv);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: uncaught exception: %s\n", e.what());
        return 1;
    } catch (...) {
        std::fprintf(stderr, "FATAL: uncaught unknown exception\n");
        return 1;
    }
}
