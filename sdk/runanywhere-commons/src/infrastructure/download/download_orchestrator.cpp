/**
 * @file download_orchestrator.cpp
 * @brief Download Orchestrator - High-Level Model Download Lifecycle Management
 *
 * Consolidates download business logic from Swift/Kotlin/RN/Flutter/Web SDKs into C++.
 * Each SDK provides an HTTP transport adapter (rac_http_transport_register) and
 * drives the workflow through the proto-byte ABI: rac_download_plan_proto →
 * rac_download_start_proto → rac_download_cancel_proto / rac_download_resume_proto /
 * rac_download_progress_poll_proto / rac_download_cleanup_terminal_tasks_proto.
 *
 * Full lifecycle:
 *   1. Plan: rac_download_plan_proto validates the model + storage and emits a
 *      DownloadPlanResult with per-file destinations rooted under the per-model
 *      folder (path-traversal hardened via safe_descriptor_path_under).
 *   2. Start: rac_download_start_proto registers a proto_download_task and
 *      spawns a worker thread (run_proto_download_worker) that drives the
 *      transfer via rac::http::execute_stream.
 *   3. Worker: for each file → execute_stream → optional extraction →
 *      post-finalize size guard → update progress / model registry.
 *   4. Cancel/resume/progress flow through the proto-byte entry points and
 *      observe per-task atomics on proto_download_task.
 *
 * Edge cases handled:
 *   - Zip-slip / path traversal: is_safe_relative_descriptor_path +
 *     safe_descriptor_path_under reject ../absolute/backslash/empty components,
 *     canonicalize, and enforce containment under the model folder.
 *   - Resume: is_resume_candidate / resume_token / make_resume_token — a
 *     re-issued download with a matching token resumes the partial transfer.
 *   - Cancel: per-task cancel_requested atomic + delete_partial_on_cancel decides
 *     whether the .part file is removed.
 *   - Task lookup collision: dedupe by task_id → resume_token → model_id,
 *     preferring active over stale terminal tasks.
 *   - Insufficient storage: pre-flight gate returns "insufficient storage".
 *   - Post-finalize size guard: verifies the downloaded file size against the
 *     expected descriptor size; a mismatch fails the file.
 *   - Archive members: optional extraction step after stream finalize.
 *   - Terminal-task cleanup: rac_download_cleanup_terminal_tasks_proto.
 */

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "core/internal/platform_compat.h"
#include "infrastructure/model_management/model_manifest_internal.h"
#include "infrastructure/rac_path_safety_internal.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

#ifdef _WIN32
#include <direct.h>  // for _mkdir
#endif

#include "../http/rac_http_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/events/rac_sdk_emit.h"
#include "rac/infrastructure/extraction/rac_extraction.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef RAC_HAVE_PROTOBUF
#include "download_service.pb.h"
#endif

static const char* LOG_TAG = "DownloadOrchestrator";

namespace fs = std::filesystem;

namespace {

// ───────────────────────── disk-space pre-flight helpers ─────────────────────
// Shared by the planner (pre-flight gate) and the per-file worker (runtime
// safety net) so a download is refused — with a clear message — before it can
// fill the device and leave a stuck partial.

// Human-readable size, e.g. "6.2 GB" / "850 MB".
std::string human_size(int64_t bytes) {
    char buf[32];
    if (bytes >= 1000000000LL) {
        snprintf(buf, sizeof(buf), "%.1f GB", static_cast<double>(bytes) / 1e9);
    } else {
        snprintf(buf, sizeof(buf), "%.0f MB", static_cast<double>(bytes) / 1e6);
    }
    return std::string(buf);
}

// Free bytes on the filesystem that will hold `path`. The per-model folder may
// not exist yet, so walk up to the nearest existing ancestor. Returns -1 when
// it cannot be determined (e.g. WASM/MEMFS), so callers can skip the gate.
int64_t filesystem_available_bytes(const std::string& path) {
    std::error_code ec;
    fs::path probe(path);
    while (!probe.empty()) {
        if (fs::exists(probe, ec)) break;
        fs::path parent = probe.parent_path();
        if (parent == probe) break;
        probe = parent;
    }
    if (probe.empty()) return -1;
    fs::space_info si = fs::space(probe, ec);
    if (ec) return -1;
    if (si.available == static_cast<uintmax_t>(-1)) return -1;
    if (si.available > static_cast<uintmax_t>(INT64_MAX)) return INT64_MAX;
    return static_cast<int64_t>(si.available);
}

// Synchronous HTTP HEAD to learn a remote file's Content-Length. Returns the
// byte length, or -1 when unknown (no transport, non-2xx, or missing header).
// Used at plan time to size multi-file bundles whose catalog entries carry no
// per-file size, so the pre-flight storage gate can fire before any bytes land.
int64_t http_head_content_length(const std::string& url) {
    if (rac_http_transport_is_registered() != RAC_TRUE) return -1;
    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS || client == nullptr) return -1;
    rac_http_request_t req{};
    req.method = "HEAD";
    req.url = url.c_str();
    req.timeout_ms = 15000;
    req.follow_redirects = RAC_TRUE;
    rac_http_response_t resp{};
    int64_t len = -1;
    rac_result_t rc = rac_http_request_send(client, &req, &resp);
    if (rc == RAC_SUCCESS && resp.status >= 200 && resp.status < 300 && resp.headers != nullptr) {
        for (size_t i = 0; i < resp.header_count; ++i) {
            const char* name = resp.headers[i].name;
            const char* value = resp.headers[i].value;
            if (name == nullptr || value == nullptr) continue;
            static const char* kWant = "content-length";
            const size_t n = std::strlen(kWant);
            if (std::strlen(name) != n) continue;
            bool match = true;
            for (size_t k = 0; k < n; ++k) {
                char c = name[k];
                if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
                if (c != kWant[k]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                long long v = std::strtoll(value, nullptr, 10);
                if (v > 0) len = static_cast<int64_t>(v);
                break;
            }
        }
    }
    rac_http_response_free(&resp);
    rac_http_client_destroy(client);
    return len;
}

}  // namespace

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

        if (lower.ends_with(".tar.gz"))
            return "tar.gz";
        if (lower.ends_with(".tar.bz2"))
            return "tar.bz2";
        if (lower.ends_with(".tar.xz"))
            return "tar.xz";
        if (lower.ends_with(".tgz"))
            return "tar.gz";
        if (lower.ends_with(".tbz2"))
            return "tar.bz2";
        if (lower.ends_with(".txz"))
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

static std::string safe_filename_stem(std::string value) {
    for (char& c : value) {
        const bool alpha_num = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                               (c >= '0' && c <= '9');
        if (!alpha_num && c != '-' && c != '_' && c != '.') {
            c = '_';
        }
    }
    while (!value.empty() && (value.front() == '.' || value.front() == '_')) {
        value.erase(value.begin());
    }
    return value.empty() ? "model" : value;
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
    std::string filename;
    int64_t expected_bytes = 0;
    bool requires_extraction = false;
    bool is_resume_candidate = false;
};

struct proto_download_task {
    std::mutex mutex;
    std::condition_variable cv;
    std::string task_id;
    std::string model_id;
    std::string model_folder_path;
    std::string resume_token;
    std::vector<proto_plan_file> files;
    std::vector<int64_t> parallel_file_bytes;
    std::vector<int64_t> parallel_file_totals;
    std::vector<bool> parallel_file_done;
    rav1::DownloadProgress progress;
    std::atomic<bool> cancel_requested{false};
    bool running = false;
    bool delete_partial_on_cancel = false;
    int64_t last_partial_bytes = 0;
    int64_t last_deleted_bytes = 0;
    int64_t started_at_unix_ms = 0;
    bool download_telemetry_started = false;  // model.download.started emitted once
    bool download_telemetry_finished = false;  // terminal model.download.* emitted once
    // Framework + archive structure preserved from the registry at task
    // creation so the worker can (a) extract into the canonical per-model
    // folder and (b) resolve the post-extraction nested subdirectory for
    // archives whose top-level entry is a single directory (sherpa-onnx
    // Piper TTS, Whisper STT — both ship as `<name>/<files>`).
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    rac_archive_structure_t archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
    rac_model_format_t format = RAC_MODEL_FORMAT_UNKNOWN;
    // Mirrors DownloadStartRequest.update_registry_on_completion. When set,
    // the worker calls rac_model_registry_update_download_status() after the
    // download + extraction succeed so the registry observes is_downloaded
    // = true + local_path = <resolved path> without an SDK-side self-heal.
    bool update_registry_on_completion = false;
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
    // Ring of recently emitted DownloadProgress byte buffers.
    //
    // Some bindings (Flutter Dart `NativeCallable.listener`, React Native
    // NitroModules async dispatch) process the callback on a different
    // thread/isolate than the one that invoked it. A stack- or emission-
    // scoped `std::string bytes` would be freed by the time those bindings
    // finally read the pointer — producing `InvalidProtocolBufferException:
    // invalid tag (zero)` (BUG-FLT-ANDROID-001 / BUG-STREAMING-005) when the
    // decoder reads reused memory.
    //
    // Keeping the last N serializations alive guarantees each emitted pointer
    // remains valid long enough for the slowest async binding to copy it out.
    //
    // Bumped from 32 → 128. The original 32 was sized for the
    // ~64 KiB reporting interval the platform HTTP stacks use, but
    // `rac_http_download` actually emits progress on every transport-delivered
    // chunk (no time-based throttling), which on a 5 GB GGUF with 8 KiB
    // OkHttp chunks produces ~600 k events. Async bindings (Flutter Dart
    // `NativeCallable.listener`, React Native NitroModules) can lag the
    // emission thread by tens of milliseconds while decoding on a different
    // isolate; at 32 slots the ring rotated in ~5 ms, leaving a small but
    // non-zero window where the slowest binding could read freed memory.
    // 128 widens the window to ~20 ms — still O(KB) of resident memory while
    // covering steady-state async-decode latencies. (Further headroom would
    // require coalescing progress in commons.)
    static constexpr size_t kRingSize = 128;
    std::array<std::string, kRingSize> bytes_ring;
    size_t ring_index = 0;
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

// security-privacy-storage-network-001: descriptor-supplied path components
// (ModelFileDescriptor.relative_path / .destination_path / .filename and the
// model_id used to build per-model folders) flow from app or remote catalog
// metadata into the download writer with no inherent trust. We treat them as
// untrusted strings and reject any value that could cause the writer to
// escape the RunAnywhere model storage root.
//
// Rejection rules (applied per component):
//   - empty, ".", ".."           → traversal / no-op
//   - contains '/' or '\\'       → embedded separators (only the joiner is
//                                  allowed to introduce separators)
// Top-level rules for relative paths:
//   - empty                      → nothing to write
//   - is_absolute_path(path)     → absolute paths are policy decisions, not
//                                  data; the C++ writer must not be steered
//                                  by descriptor data into arbitrary roots.
//                                  EXCEPTION: platform-trusted mount roots
//                                  (see is_platform_trusted_absolute_prefix)
//                                  are sandboxed by the platform itself.
//
// `is_safe_model_id_component` is the strictest of the three because the
// model_id is concatenated into the per-model folder root and then used as
// a fallback filename; allowing separators or '..' lets a malicious id pivot
// the storage root before any descriptor path is even applied.
using rac::path::is_safe_path_segment;

// Whitelist platform-trusted absolute path prefixes that the C++ writer is
// allowed to honor verbatim from descriptor metadata.
//
// `/opfs/` — Emscripten OPFS mount root on Web. The browser-owned Origin
// Private File System is sandboxed: every path under `/opfs/` is rooted in
// the origin's private storage and cannot reach files outside that root.
// Path-traversal segments (`..`) are still validated separately by
// `path_has_unsafe_components` / per-segment `is_safe_path_segment` so a
// malicious `/opfs/../etc/passwd` is still rejected — the prefix check only
// gates which absolute roots are admissible at all.
bool is_platform_trusted_absolute_prefix(const std::string& path) {
#if defined(__EMSCRIPTEN__)
    return path.rfind("/opfs/", 0) == 0;
#else
    (void)path;
    return false;
#endif
}

bool is_safe_relative_descriptor_path(const std::string& path) {
    if (path.empty())
        return false;
    if (is_absolute_path(path)) {
        // Absolute paths are accepted at this segment-validation layer when
        // every component is non-empty / not "." / not ".." so traversal
        // segments embedded inside an absolute path are rejected. The
        // containment policy (must be under model_folder OR under a
        // platform-trusted mount root such as Emscripten OPFS) is enforced
        // in safe_descriptor_path_under — this function is purely a
        // per-component sanity check.
        //
        // Historical context: the previous policy treated ALL non-OPFS
        // absolute paths as a hard reject, but the trusted planner emits
        // absolute paths rooted under the per-model folder
        // (rac_download_compute_destination → rac_model_paths_get_*),
        // which means a hard reject corrupted every download on platforms
        // whose per-model folders are not under a platform-trusted prefix
        // (iOS `<App>/Documents/...`, Android `/data/user/0/...`). The
        // containment check in safe_descriptor_path_under is what gates
        // policy now; per-segment validation remains here.
        size_t start = 1;  // skip the leading '/'
        while (start <= path.size()) {
            size_t end = path.find_first_of("/\\", start);
            if (end == std::string::npos)
                end = path.size();
            if (end > start) {
                std::string component = path.substr(start, end - start);
                if (!is_safe_path_segment(component))
                    return false;
            }
            if (end == path.size())
                break;
            start = end + 1;
        }
        return true;
    }

    size_t start = 0;
    while (start <= path.size()) {
        size_t end = path.find_first_of("/\\", start);
        if (end == std::string::npos)
            end = path.size();
        std::string component = path.substr(start, end - start);
        if (!is_safe_path_segment(component))
            return false;
        if (end == path.size())
            break;
        start = end + 1;
    }
    return true;
}

// Joins `model_folder` and `relative_path` using join_path, then lexically
// normalizes the result and verifies the canonical form is still rooted
// under the lexically-normalized canonical model_folder. Returns nullopt
// when the result escapes the root or the inputs fail the safety checks.
// `model_folder` is trusted (built from rac_model_paths_get_*); only
// `relative_path` is treated as untrusted.
//
// Accepts three input shapes for `relative_path`:
//   1. Relative path. Joined with model_folder; result must be lexically
//      contained under the normalized model_folder.
//   2. Absolute path under a platform-trusted mount root (e.g. Emscripten
//      `/opfs/`). Returned verbatim — the platform mount IS the sandbox.
//   3. Absolute path that is lexically contained under model_folder once
//      both are canonicalized (best-effort via fs::weakly_canonical, which
//      resolves any symlinks present and is well-defined for paths that
//      don't yet exist). This is the trusted-planner shape: the planner
//      builds destinations by joining a per-model folder (computed via
//      rac_model_paths_get_model_folder + rac_download_compute_destination)
//      onto a filename, which yields an absolute path on platforms whose
//      per-model folders live outside any platform-trusted mount prefix
//      (iOS `<App>/Documents/RunAnywhere/Models/...`, Android
//      `/data/user/0/com.<pkg>/files/RunAnywhere/Models/...`).
//
// Per-component validation in is_safe_relative_descriptor_path has already
// rejected '.' / '..' / empty / backslash-containing components.
std::optional<std::string> safe_descriptor_path_under(const std::string& model_folder,
                                                      const std::string& relative_path) {
    if (!is_safe_relative_descriptor_path(relative_path))
        return std::nullopt;

    // Platform-trusted absolute paths are not joined with model_folder —
    // the platform mount root (e.g. /opfs/) is itself a sandbox boundary.
    if (is_absolute_path(relative_path) && is_platform_trusted_absolute_prefix(relative_path)) {
        return fs::path(relative_path).lexically_normal().string();
    }

    if (model_folder.empty())
        return std::nullopt;

    // Best-effort canonicalization. fs::weakly_canonical() is the C++17
    // counterpart of POSIX realpath() that tolerates non-existent leaves;
    // both root and candidate are run through it so symlink-traversed and
    // lexical forms compare cleanly. On any std::error_code we fall back
    // to lexically_normal so a failure doesn't degrade the security check
    // into a permissive pass-through.
    auto canonicalize = [](const fs::path& in) {
        std::error_code ec;
        fs::path canon = fs::weakly_canonical(in, ec);
        if (ec || canon.empty()) {
            return in.lexically_normal();
        }
        return canon.lexically_normal();
    };

    fs::path root = canonicalize(fs::path(model_folder));

    if (is_absolute_path(relative_path)) {
        // Absolute candidate: must be lexically contained under canonical
        // model_folder. Per-segment validation has already rejected '..'
        // segments so canonicalization can only collapse to the input or
        // deeper, never escape — but we still verify containment defensively.
        fs::path candidate = canonicalize(fs::path(relative_path));

        auto root_it = root.begin();
        auto cand_it = candidate.begin();
        for (; root_it != root.end() && cand_it != candidate.end(); ++root_it, ++cand_it) {
            if (*root_it != *cand_it)
                return std::nullopt;
        }
        if (root_it != root.end())
            return std::nullopt;

        return candidate.string();
    }

    fs::path joined = canonicalize(fs::path(model_folder) / relative_path);

    // Verify joined still has root as a prefix (lexical containment check).
    auto root_it = root.begin();
    auto joined_it = joined.begin();
    for (; root_it != root.end() && joined_it != joined.end(); ++root_it, ++joined_it) {
        if (*root_it != *joined_it)
            return std::nullopt;
    }
    if (root_it != root.end())
        return std::nullopt;

    return joined.string();
}

bool looks_like_http_url(const std::string& url) {
    return url.starts_with("http://") || url.starts_with("https://");
}

int64_t now_unix_ms() {
    return rac_get_current_time_ms();
}

std::string make_resume_token(const std::string& task_id, const std::string& model_id) {
    const std::string& identity = !task_id.empty() ? task_id : model_id;
    return identity.empty() ? std::string() : ("racdl:" + identity);
}

std::string checksum_from_descriptor(const rav1::ModelFileDescriptor& file) {
    if (file.has_checksum_sha256() && !file.checksum_sha256().empty()) {
        return file.checksum_sha256();
    }
    return "";
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
        case rav1::INFERENCE_FRAMEWORK_SHERPA:
            return RAC_FRAMEWORK_SHERPA;
        case rav1::INFERENCE_FRAMEWORK_QHEXRT:
            return RAC_FRAMEWORK_QHEXRT;
        case rav1::INFERENCE_FRAMEWORK_NONE:
            return RAC_FRAMEWORK_NONE;
        default:
            return RAC_FRAMEWORK_UNKNOWN;
    }
}

rac_model_format_t proto_format_to_c(rav1::ModelFormat format) {
    const int value = static_cast<int>(format);
    return rav1::ModelFormat_IsValid(value) ? static_cast<rac_model_format_t>(value)
                                            : RAC_MODEL_FORMAT_UNKNOWN;
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
                                               const std::string& model_id,
                                               const std::string& resume_token = "") {
    std::lock_guard<std::mutex> lock(proto_state().mutex);
    if (!task_id.empty()) {
        auto it = proto_state().tasks.find(task_id);
        if (it != proto_state().tasks.end()) {
            return it->second;
        }
    }
    if (!resume_token.empty()) {
        for (auto& pair : proto_state().tasks) {
            if (pair.second && pair.second->resume_token == resume_token) {
                return pair.second;
            }
        }
    }
    if (!model_id.empty()) {
        // When looking up by model_id only, prefer non-terminal
        // (active) tasks over terminal ones. `proto_state().tasks` is sorted
        // by task_id, so the older (likely terminal) entry would be returned
        // first if we did a single-pass scan — cancel(model_id=X) and
        // pollProgress(model_id=X) would then act on the stale task instead
        // of the running one. Two-pass: first scan returns any active match;
        // second pass falls back to any terminal match (preserves the
        // historical behaviour for callers that legitimately look up a
        // completed task by model id).
        for (auto& pair : proto_state().tasks) {
            if (!pair.second || pair.second->model_id != model_id) {
                continue;
            }
            std::lock_guard<std::mutex> tlock(pair.second->mutex);
            const auto state = pair.second->progress.state();
            const bool active = state == rav1::DOWNLOAD_STATE_PENDING ||
                                state == rav1::DOWNLOAD_STATE_DOWNLOADING ||
                                state == rav1::DOWNLOAD_STATE_EXTRACTING ||
                                state == rav1::DOWNLOAD_STATE_RESUMING;
            if (active) {
                return pair.second;
            }
        }
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

    // Serialize into a persistent ring slot so the pointer passed to the
    // async SDK binding (Flutter Dart `NativeCallable.listener`, React
    // Native NitroModules) remains valid until enough subsequent emissions
    // rotate the slot. This prevents `InvalidProtocolBufferException:
    // invalid tag (zero)` caused by the binding reading freed memory after
    // the emission returns.
    std::lock_guard<std::mutex> lock(progress_sink().mutex);
    auto& sink = progress_sink();
    if (!sink.callback) {
        return;
    }
    std::string& slot = sink.bytes_ring[sink.ring_index];
    sink.ring_index = (sink.ring_index + 1) % proto_progress_sink::kRingSize;
    if (!progress.SerializeToString(&slot)) {
        return;
    }
    sink.callback(reinterpret_cast<const uint8_t*>(slot.data()), slot.size(), sink.user_data);
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

void mark_task_stopped(const std::shared_ptr<proto_download_task>& task) {
    if (!task) {
        return;
    }
    // Snapshot the terminal state under the lock; emit telemetry after releasing
    // it (the emit feeds the event bus / telemetry sink, never the task mutex).
    rav1::DownloadState final_state = rav1::DOWNLOAD_STATE_UNSPECIFIED;
    std::string model_id;
    std::string error_message;
    int64_t bytes = 0;
    double duration_ms = 0.0;
    bool emit_terminal = false;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = false;
        final_state = task->progress.state();
        if (!task->download_telemetry_finished &&
            (final_state == rav1::DOWNLOAD_STATE_COMPLETED ||
             final_state == rav1::DOWNLOAD_STATE_FAILED ||
             final_state == rav1::DOWNLOAD_STATE_CANCELLED)) {
            task->download_telemetry_finished = true;
            emit_terminal = true;
            model_id = task->model_id;
            error_message = task->progress.error_message();
            bytes = task->progress.bytes_downloaded();
            if (task->started_at_unix_ms > 0) {
                duration_ms = static_cast<double>(now_unix_ms() - task->started_at_unix_ms);
            }
        }
    }
    task->cv.notify_all();
    if (emit_terminal) {
        switch (final_state) {
            case rav1::DOWNLOAD_STATE_COMPLETED:
                rac::events::emit_model_download_completed(model_id.c_str(), bytes, duration_ms,
                                                           nullptr);
                break;
            case rav1::DOWNLOAD_STATE_FAILED:
                rac::events::emit_model_download_failed(
                    model_id.c_str(), RAC_ERROR_DOWNLOAD_FAILED,
                    error_message.empty() ? "download failed" : error_message.c_str());
                break;
            case rav1::DOWNLOAD_STATE_CANCELLED:
                rac::events::emit_model_download_cancelled(model_id.c_str());
                break;
            default:
                break;
        }
    }
}

// `overall_override` (>= 0) lets a caller supply the whole-download fraction
// directly, for the case where it cannot be derived from bytes. Multi-file
// bundles without per-file sizes (total_bytes is then a single file's length,
// not the plan total) would otherwise mix a cumulative numerator with a
// single-file denominator and pin overall_progress to ~100% after the first
// (tiny) file. Callers pass a monotonic file-count fraction instead. Default
// (-1) keeps the byte-derived behavior for single-file / known-total plans.
void set_task_progress(const std::shared_ptr<proto_download_task>& task, rav1::DownloadState state,
                       rav1::DownloadStage stage, int64_t bytes_downloaded, int64_t total_bytes,
                       int32_t file_index, const std::string& storage_key,
                       const std::string& local_path, const std::string& error_message,
                       float overall_override = -1.0f) {
    if (!task) {
        return;
    }
    std::lock_guard<std::mutex> lock(task->mutex);
    rav1::DownloadProgress* progress = &task->progress;
    int64_t now_ms = now_unix_ms();
    if (task->started_at_unix_ms <= 0) {
        task->started_at_unix_ms = now_ms;
    }
    progress->set_model_id(task->model_id);
    progress->set_task_id(task->task_id);
    progress->set_state(state);
    progress->set_stage(stage);
    progress->set_bytes_downloaded(bytes_downloaded);
    progress->set_total_bytes(total_bytes);
    progress->set_current_file_index(file_index);
    progress->set_total_files(static_cast<int32_t>(task->files.size()));
    progress->set_storage_key(storage_key);
    progress->set_resume_token(task->resume_token);
    progress->set_started_at_unix_ms(task->started_at_unix_ms);
    progress->set_updated_at_unix_ms(now_ms);
    if (file_index >= 0 && static_cast<size_t>(file_index) < task->files.size()) {
        progress->set_current_file_name(task->files[static_cast<size_t>(file_index)].filename);
    }
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
        stage_progress = static_cast<float>(std::min<double>(
            1.0, static_cast<double>(bytes_downloaded) / static_cast<double>(total_bytes)));
    } else if (state == rav1::DOWNLOAD_STATE_COMPLETED) {
        stage_progress = 1.0f;
    }
    progress->set_stage_progress(stage_progress);
    float overall_progress;
    if (state == rav1::DOWNLOAD_STATE_COMPLETED) {
        overall_progress = 1.0f;
    } else if (overall_override >= 0.0f) {
        overall_progress = std::min(1.0f, std::max(0.0f, overall_override));
    } else {
        overall_progress = stage_progress;
    }
    progress->set_overall_progress(overall_progress);
    int64_t elapsed_ms = now_ms - task->started_at_unix_ms;
    if (elapsed_ms > 0 && bytes_downloaded > 0) {
        float speed = static_cast<float>(static_cast<double>(bytes_downloaded) /
                                         (static_cast<double>(elapsed_ms) / 1000.0));
        progress->set_overall_speed_bps(speed);
        if (total_bytes > bytes_downloaded && speed > 0.0f) {
            progress->set_eta_seconds(
                static_cast<int64_t>(static_cast<double>(total_bytes - bytes_downloaded) / speed));
        } else {
            progress->set_eta_seconds(-1);
        }
    } else {
        progress->set_overall_speed_bps(0.0f);
        progress->set_eta_seconds(-1);
    }
}

struct proto_download_callback_ctx {
    std::shared_ptr<proto_download_task> task;
    int file_index = 0;
    int64_t completed_before_file = 0;
    int64_t total_expected = 0;
    std::string storage_key;
    std::string destination_path;
    bool aggregate_parallel_files = false;
    std::atomic<bool>* abort_requested = nullptr;
};

struct parallel_progress_snapshot {
    int64_t bytes_downloaded = 0;
    int64_t total_bytes = 0;
    float overall_override = -1.0f;
};

parallel_progress_snapshot update_parallel_progress(
    const std::shared_ptr<proto_download_task>& task, size_t file_index, int64_t bytes_written,
    int64_t total_bytes, int64_t total_expected, bool mark_done) {
    parallel_progress_snapshot snapshot;
    if (!task) {
        return snapshot;
    }

    std::lock_guard<std::mutex> lock(task->mutex);
    const size_t file_count = task->files.size();
    if (task->parallel_file_bytes.size() != file_count) {
        task->parallel_file_bytes.assign(file_count, 0);
    }
    if (task->parallel_file_totals.size() != file_count) {
        task->parallel_file_totals.assign(file_count, 0);
    }
    if (task->parallel_file_done.size() != file_count) {
        task->parallel_file_done.assign(file_count, false);
    }
    if (file_index < file_count) {
        task->parallel_file_bytes[file_index] = std::max<int64_t>(bytes_written, 0);
        if (total_bytes > 0) {
            task->parallel_file_totals[file_index] = total_bytes;
        } else if (task->files[file_index].expected_bytes > 0) {
            task->parallel_file_totals[file_index] = task->files[file_index].expected_bytes;
        }
        if (mark_done) {
            task->parallel_file_done[file_index] = true;
        }
    }

    double file_fraction_sum = 0.0;
    int64_t known_total_sum = 0;
    for (size_t i = 0; i < file_count; ++i) {
        snapshot.bytes_downloaded += std::max<int64_t>(task->parallel_file_bytes[i], 0);
        known_total_sum += std::max<int64_t>(task->parallel_file_totals[i], 0);
        if (task->parallel_file_done[i]) {
            file_fraction_sum += 1.0;
        } else if (task->parallel_file_totals[i] > 0) {
            file_fraction_sum += std::min(
                1.0, static_cast<double>(std::max<int64_t>(task->parallel_file_bytes[i], 0)) /
                         static_cast<double>(task->parallel_file_totals[i]));
        }
    }
    snapshot.total_bytes = total_expected > 0 ? total_expected : known_total_sum;
    if (total_expected <= 0 && file_count > 0) {
        snapshot.overall_override =
            static_cast<float>(std::min(1.0, file_fraction_sum / static_cast<double>(file_count)));
    }
    task->last_partial_bytes = snapshot.bytes_downloaded;
    return snapshot;
}

rac_bool_t proto_http_progress(uint64_t bytes_written, uint64_t total_bytes, void* user_data) {
    auto* ctx = static_cast<proto_download_callback_ctx*>(user_data);
    if (!ctx || !ctx->task) {
        return RAC_TRUE;
    }
    if (ctx->task->cancel_requested.load() ||
        (ctx->abort_requested && ctx->abort_requested->load())) {
        return RAC_FALSE;
    }

    if (ctx->aggregate_parallel_files) {
        parallel_progress_snapshot snapshot = update_parallel_progress(
            ctx->task, static_cast<size_t>(std::max(ctx->file_index, 0)),
            static_cast<int64_t>(bytes_written), static_cast<int64_t>(total_bytes),
            ctx->total_expected, false);
        set_task_progress(ctx->task, rav1::DOWNLOAD_STATE_DOWNLOADING,
                          rav1::DOWNLOAD_STAGE_DOWNLOADING, snapshot.bytes_downloaded,
                          snapshot.total_bytes, ctx->file_index, ctx->storage_key, "", "",
                          snapshot.overall_override);
        emit_progress(ctx->task);
        return RAC_TRUE;
    }

    int64_t total = ctx->total_expected > 0
                        ? ctx->total_expected
                        : (total_bytes > 0 ? static_cast<int64_t>(total_bytes) : 0);
    int64_t downloaded = ctx->completed_before_file + static_cast<int64_t>(bytes_written);

    {
        std::lock_guard<std::mutex> lock(ctx->task->mutex);
        ctx->task->last_partial_bytes = downloaded;
    }
    // For multi-file bundles whose per-file sizes are unknown (total_expected
    // == 0, e.g. HuggingFace NPU bundles), derive a monotonic overall fraction
    // from file count + current file's own fraction, so the bar doesn't pin to
    // 100% after the first (tiny manifest) file.
    float overall_override = -1.0f;
    const size_t num_files = ctx->task->files.size();
    if (ctx->total_expected <= 0 && num_files > 1) {
        double file_fraction =
            total_bytes > 0
                ? std::min(1.0, static_cast<double>(bytes_written) / static_cast<double>(total_bytes))
                : 0.0;
        overall_override = static_cast<float>(
            (static_cast<double>(ctx->file_index) + file_fraction) / static_cast<double>(num_files));
    }
    set_task_progress(ctx->task, rav1::DOWNLOAD_STATE_DOWNLOADING, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                      downloaded, total, ctx->file_index, ctx->storage_key, "", "", overall_override);
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

bool validate_resume_offset(const proto_plan_file& file, int64_t requested_resume_from,
                            bool require_exact_size, int64_t* out_actual_size,
                            std::string* out_error) {
    int64_t actual_size = file_size_or_zero(file.destination_path);
    if (out_actual_size) {
        *out_actual_size = actual_size;
    }

    if (requested_resume_from <= 0) {
        return true;
    }
    if (actual_size <= 0) {
        if (out_error) {
            *out_error = "cannot resume without partial bytes";
        }
        return false;
    }
    if (file.expected_bytes > 0 && requested_resume_from > file.expected_bytes) {
        if (out_error) {
            *out_error = "resume offset exceeds expected byte count";
        }
        return false;
    }
    if (actual_size < requested_resume_from) {
        if (out_error) {
            *out_error = "partial file is smaller than requested resume offset";
        }
        return false;
    }
    if (require_exact_size && actual_size != requested_resume_from) {
        if (out_error) {
            *out_error = "partial byte count changed before resume";
        }
        return false;
    }
    return true;
}

// Result of processing one planned file. STOP means a terminal
// (CANCELLED/FAILED) progress event was already emitted and the worker should
// return; CONTINUE means proceed to the next file.
enum class plan_file_step { CONTINUE, STOP };

// Download (and optionally extract) one planned file. On cancel / HTTP failure
// / extraction failure it emits the terminal progress event, stops the task and
// returns STOP. On success it sets `final_path` for this file and advances
// `completed_before_file`, returning CONTINUE.
plan_file_step process_plan_file(const std::shared_ptr<proto_download_task>& task,
                                 const proto_plan_file& file, size_t i, int64_t total_expected,
                                 uint64_t file_resume_from, int64_t& completed_before_file,
                                 std::string& final_path) {
    // Ensure the file's parent directory exists. Most bundles write straight
    // into the per-model folder (already created), but a descriptor may carry a
    // multi-segment subpath (e.g. VLM host-weight fixtures under "vlm/…") whose
    // intermediate directory the HTTP writer will not create on its own.
    {
        fs::path dest_path(file.destination_path);
        if (dest_path.has_parent_path())
            mkdir_p(dest_path.parent_path().string().c_str());
    }

    // A previous attempt may already have landed this file completely (e.g. a
    // size-guard refusal caused by a stale catalog size estimate, or a re-pull
    // after an interrupted finalize). Re-fetching would resume from EOF and
    // draw HTTP 416 from range-aware servers, failing a download whose bytes
    // are already correct. When the on-disk size matches the plan's expected
    // size exactly, skip the network and fall through to extraction/finalize.
    const bool already_complete =
        file.expected_bytes > 0 && file_size_or_zero(file.destination_path) == file.expected_bytes;
    if (already_complete) {
        RAC_LOG_INFO(LOG_TAG,
                     "File %zu (%s) already complete on disk (%lld bytes) — skipping fetch", i,
                     file.storage_key.c_str(), static_cast<long long>(file.expected_bytes));
    }

    if (!already_complete) {
        // Runtime free-space safety net. The planner gate runs once up front,
        // but free space can shrink between planning and this file's turn (other
        // downloads, the bytes already written by earlier files in this bundle),
        // and the planner can't size files the server won't HEAD. Refuse before
        // streaming so we never fill the disk and strand a half-written model.
        if (file.expected_bytes > 0) {
            int64_t still_needed =
                file.expected_bytes - static_cast<int64_t>(file_resume_from);
            if (still_needed > 0) {
                int64_t available = filesystem_available_bytes(file.destination_path);
                const int64_t margin = 32LL * 1024 * 1024;  // 32 MiB headroom
                if (available >= 0 && available < still_needed + margin) {
                    std::string error =
                        "Not enough storage to finish downloading this model: " + file.filename +
                        " needs about " + human_size(still_needed) + " more but only " +
                        human_size(available) + " is free. Free up space and try again.";
                    int64_t partial =
                        completed_before_file + file_size_or_zero(file.destination_path);
                    {
                        std::lock_guard<std::mutex> lock(task->mutex);
                        task->last_partial_bytes = partial;
                    }
                    set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED,
                                      rav1::DOWNLOAD_STAGE_DOWNLOADING, partial, total_expected,
                                      static_cast<int32_t>(i), file.storage_key, "", error);
                    mark_task_stopped(task);
                    emit_progress(task);
                    return plan_file_step::STOP;
                }
            }
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
            int64_t file_partial = file_size_or_zero(file.destination_path);
            int64_t deleted = 0;
            bool delete_partial = false;
            {
                std::lock_guard<std::mutex> lock(task->mutex);
                delete_partial = task->delete_partial_on_cancel;
            }
            if (delete_partial) {
                deleted = delete_partial_file(file.destination_path);
                file_partial = 0;
            }
            {
                std::lock_guard<std::mutex> lock(task->mutex);
                task->last_deleted_bytes = deleted;
                task->last_partial_bytes = completed_before_file + file_partial;
            }
            set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED,
                              rav1::DOWNLOAD_STAGE_DOWNLOADING,
                              completed_before_file + file_partial, total_expected,
                              static_cast<int32_t>(i), file.storage_key, "", "download cancelled");
            mark_task_stopped(task);
            emit_progress(task);
            return plan_file_step::STOP;
        }

        if (status != RAC_HTTP_DL_OK) {
            std::string error = http_status_message(status, http_status);
            int64_t partial = completed_before_file + file_size_or_zero(file.destination_path);
            {
                std::lock_guard<std::mutex> lock(task->mutex);
                task->last_partial_bytes = partial;
            }
            set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                              partial, total_expected, static_cast<int32_t>(i), file.storage_key,
                              "", error);
            mark_task_stopped(task);
            emit_progress(task);
            return plan_file_step::STOP;
        }
    }

    if (file.requires_extraction) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_EXTRACTING, rav1::DOWNLOAD_STAGE_EXTRACTING,
                          total_expected > 0 ? completed_before_file + file.expected_bytes : 0,
                          total_expected, static_cast<int32_t>(i), file.storage_key, "", "");
        emit_progress(task);

        // Ensure the per-model folder exists. When `rac_download_start_proto`
        // resolved `model_folder_path` via `rac_model_paths_get_model_folder`
        // (archive flow) the folder does not exist yet — libarchive's native
        // extractor silently degrades if the output directory is missing.
        mkdir_p(task->model_folder_path.c_str());

        rac_extraction_result_t extraction_result{};
        rac_result_t extract_rc = rac_extract_archive_native(
            file.destination_path.c_str(), task->model_folder_path.c_str(), nullptr, nullptr,
            nullptr, &extraction_result);
        if (extract_rc != RAC_SUCCESS) {
            set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_EXTRACTING,
                              total_expected > 0 ? completed_before_file + file.expected_bytes : 0,
                              total_expected, static_cast<int32_t>(i), file.storage_key, "",
                              "archive extraction failed");
            mark_task_stopped(task);
            emit_progress(task);
            return plan_file_step::STOP;
        }

        delete_file(file.destination_path.c_str());

        // Sherpa-ONNX archives (Piper TTS VITS, Whisper STT) ship as
        // `<name>/<files>` — a single top-level nested directory. When
        // we extract into `Models/Sherpa/<model_id>/` we therefore end
        // up with `Models/Sherpa/<model_id>/<nested>/<files>`. Collapse
        // to the nested path so the backend's `load_model()` sees the
        // directory that actually contains `model.onnx`/`tokens.txt`/
        // `espeak-ng-data/`.
        char resolved_path[4096];
        rac_result_t find_rc = rac_find_model_path_after_extraction(
            task->model_folder_path.c_str(), task->archive_structure, task->framework, task->format,
            resolved_path, sizeof(resolved_path));
        if (find_rc == RAC_SUCCESS && resolved_path[0] != '\0') {
            final_path = resolved_path;
        } else {
            final_path = task->model_folder_path;
        }
    } else {
        final_path = file.destination_path;
    }

    if (total_expected > 0) {
        completed_before_file += std::max<int64_t>(file.expected_bytes, 0);
    } else {
        completed_before_file += file_size_or_zero(final_path);
    }
    return plan_file_step::CONTINUE;
}

// Post-finalize size guard.
//
// The per-file HTTP runner already enforces a strict body-validation gate
// for tiny error-stub responses (in rac_http_download.cpp), but a download
// orchestration can still finish with a file that is structurally smaller than
// the expected payload — e.g. when the server streams 200 with a short body
// that doesn't match the descriptor's expected_bytes, or when an extraction
// step silently produces a smaller artifact than the archive headers claimed.
// Before registering `is_downloaded = true`, verify each file's on-disk size
// against the descriptor's expected size. If any file is < 80% of its expected
// payload, return false so the task is marked FAILED and callers retry.
//
// 80% (not 100%) because real-world deltas exist: descriptors sometimes round
// expected_bytes from CDN HEAD probes, archive extraction emits files whose
// summed size doesn't equal the archive size, and a few gguf quants ship with a
// smaller-than-declared payload. 20% slack catches the catastrophic case (49 B
// HTML stub for a 386 MB gguf) without false-positives on the slop.
//
// On failure, `failing_index` is set to the offending file so the FAILED event
// reports the actual offender instead of the last file of the plan.
bool validate_downloaded_sizes(const std::shared_ptr<proto_download_task>& task,
                               size_t& failing_index, std::string& sanity_error) {
    if (task->files.empty()) {
        return true;
    }
    for (size_t i = 0; i < task->files.size(); ++i) {
        const auto& file = task->files[i];
        if (file.expected_bytes <= 0) {
            // No expected size declared (e.g. some archives w/ unknown
            // payloads). Skip — we have no ground truth to compare to.
            continue;
        }
        if (file.requires_extraction) {
            // Archive entries were extracted into model_folder_path and the raw
            // archive was deleted. Comparing against expected_bytes would
            // require summing the extracted tree; treat the extraction step as
            // authoritative and skip the per-file size guard for it.
            continue;
        }
        int64_t actual = file_size_or_zero(file.destination_path);
        // 80% threshold via integer math (actual * 5 >= expected * 4) to avoid
        // the floating-point round-trip and stay overflow-safe for 64-bit sizes.
        if (actual * 5 < file.expected_bytes * 4) {
            failing_index = i;
            sanity_error = "post-finalize size guard tripped: file " + file.filename + " is " +
                           std::to_string(actual) + " bytes on disk but expected " +
                           std::to_string(file.expected_bytes) + " bytes (< 80% threshold)";
            RAC_LOG_ERROR(LOG_TAG,
                          "Post-finalize size guard FAILED for task %s file %zu: actual=%lld "
                          "expected=%lld (< 80%% threshold; refusing to register downloaded:true)",
                          task->task_id.c_str(), i, static_cast<long long>(actual),
                          static_cast<long long>(file.expected_bytes));
            return false;
        }
    }
    return true;
}

// For multi-file downloads (e.g. VLM primary .gguf + mmproj, MiniLM model.onnx +
// vocab.txt) report the model *folder* as the resolved local_path instead of the
// last file's destination path. Downstream path resolution scans the folder to
// discover every role (primary_model, vision_projector, tokenizer, ...); a
// last-file local_path made it scan a single file (often the mmproj) and the VLM
// load failed with "primary model not found". Single-file archive extracts must
// do the same so self-heal records the folder, not a discovered sub-file.
std::string resolve_completion_local_path(const std::shared_ptr<proto_download_task>& task,
                                          const std::string& final_path) {
    std::string completion_local_path = final_path;
    if (!task->model_folder_path.empty() && task->model_folder_path != ".") {
        const bool multi_file_plan = task->files.size() > 1;
        const bool archive_extracted =
            task->files.size() == 1 && !task->files.empty() && task->files[0].requires_extraction;
        if (multi_file_plan || archive_extracted) {
            completion_local_path = task->model_folder_path;
        }
    }
    return completion_local_path;
}

// Registry self-heal: when the SDK requested update_registry_on_completion, mark
// the model downloaded and write its resolved local_path back into the registry.
// Replaces the per-SDK self-heal (e.g. Kotlin's markModelDownloadedInRegistry()).
void self_heal_registry(const std::shared_ptr<proto_download_task>& task,
                        const std::string& completion_local_path) {
    if (task->update_registry_on_completion && !completion_local_path.empty()) {
        rac_result_t update_rc = rac_model_registry_update_download_status(
            rac_get_model_registry(), task->model_id.c_str(), completion_local_path.c_str());
        if (update_rc == RAC_SUCCESS) {
            RAC_LOG_INFO(LOG_TAG, "Registry self-heal: marked '%s' downloaded with local_path '%s'",
                         task->model_id.c_str(), completion_local_path.c_str());
            RAC_LOG_INFO(LOG_TAG, "Registered downloaded model %s", task->model_id.c_str());
        } else {
            RAC_LOG_WARNING(LOG_TAG,
                            "Registry self-heal failed for '%s' (rc=%d); SDK fallback may apply",
                            task->model_id.c_str(), update_rc);
        }
    }
}

bool can_download_files_in_parallel(const std::shared_ptr<proto_download_task>& task,
                                    int64_t resume_from) {
    if (!task || task->files.size() <= 1 || resume_from > 0) {
        return false;
    }
    for (const auto& file : task->files) {
        if (file.requires_extraction) {
            return false;
        }
    }
    return true;
}

bool run_parallel_direct_download_worker(const std::shared_ptr<proto_download_task>& task,
                                         int64_t total_expected, int64_t resume_from) {
    if (!task || !can_download_files_in_parallel(task, resume_from)) {
        return false;
    }

    constexpr size_t kMaxParallelFiles = 3;
    const size_t file_count = task->files.size();
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->parallel_file_bytes.assign(file_count, 0);
        task->parallel_file_totals.assign(file_count, 0);
        task->parallel_file_done.assign(file_count, false);
        for (size_t i = 0; i < file_count; ++i) {
            if (task->files[i].expected_bytes > 0) {
                task->parallel_file_totals[i] = task->files[i].expected_bytes;
            }
        }
    }

    RAC_LOG_INFO(LOG_TAG, "Downloading %zu files for model %s with parallelism=%zu", file_count,
                 task->model_id.c_str(), std::min(kMaxParallelFiles, file_count));

    std::atomic<size_t> next_index{0};
    std::atomic<bool> abort_requested{false};
    std::atomic<bool> saw_failure{false};
    std::mutex result_mutex;
    size_t terminal_index = 0;
    std::string terminal_error;
    bool terminal_cancelled = false;

    auto record_terminal = [&](size_t index, bool cancelled, const std::string& error) {
        bool expected = false;
        if (!saw_failure.compare_exchange_strong(expected, true)) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(result_mutex);
            terminal_index = index;
            terminal_cancelled = cancelled;
            terminal_error = error;
        }
        abort_requested.store(true);
    };

    auto worker = [&]() {
        while (!abort_requested.load() && !task->cancel_requested.load()) {
            size_t i = next_index.fetch_add(1);
            if (i >= file_count) {
                return;
            }
            const proto_plan_file file = task->files[i];

            {
                fs::path dest_path(file.destination_path);
                if (dest_path.has_parent_path())
                    mkdir_p(dest_path.parent_path().string().c_str());
            }

            const bool already_complete =
                file.expected_bytes > 0 &&
                file_size_or_zero(file.destination_path) == file.expected_bytes;
            if (already_complete) {
                update_parallel_progress(task, i, file.expected_bytes, file.expected_bytes,
                                         total_expected, true);
                continue;
            }

            if (file.expected_bytes > 0) {
                int64_t available = filesystem_available_bytes(file.destination_path);
                const int64_t margin = 32LL * 1024 * 1024;  // 32 MiB headroom
                if (available >= 0 && available < file.expected_bytes + margin) {
                    record_terminal(
                        i, false,
                        "Not enough storage to finish downloading this model: " + file.filename +
                            " needs about " + human_size(file.expected_bytes) + " but only " +
                            human_size(available) + " is free. Free up space and try again.");
                    return;
                }
            }

            proto_download_callback_ctx cb_ctx;
            cb_ctx.task = task;
            cb_ctx.file_index = static_cast<int>(i);
            cb_ctx.total_expected = total_expected;
            cb_ctx.storage_key = file.storage_key;
            cb_ctx.destination_path = file.destination_path;
            cb_ctx.aggregate_parallel_files = true;
            cb_ctx.abort_requested = &abort_requested;

            rac_http_download_request_t req{};
            req.url = file.url.c_str();
            req.destination_path = file.destination_path.c_str();
            req.timeout_ms = 0;
            req.follow_redirects = RAC_TRUE;
            req.resume_from_byte = 0;
            req.expected_sha256_hex =
                file.checksum_sha256.empty() ? nullptr : file.checksum_sha256.c_str();

            int32_t http_status = 0;
            rac_http_download_status_t status =
                rac::http::execute_stream(req, proto_http_progress, &cb_ctx, &http_status);

            if (task->cancel_requested.load() || status == RAC_HTTP_DL_CANCELLED) {
                int64_t deleted = 0;
                bool delete_partial = false;
                {
                    std::lock_guard<std::mutex> lock(task->mutex);
                    delete_partial = task->delete_partial_on_cancel;
                }
                if (delete_partial) {
                    deleted = delete_partial_file(file.destination_path);
                }
                {
                    std::lock_guard<std::mutex> lock(task->mutex);
                    task->last_deleted_bytes += deleted;
                }
                record_terminal(i, true, "download cancelled");
                return;
            }

            if (status != RAC_HTTP_DL_OK) {
                record_terminal(i, false, http_status_message(status, http_status));
                return;
            }

            const int64_t final_size = file_size_or_zero(file.destination_path);
            update_parallel_progress(task, i, final_size,
                                     file.expected_bytes > 0 ? file.expected_bytes : final_size,
                                     total_expected, true);
        }
    };

    std::vector<std::thread> workers;
    workers.reserve(std::min(kMaxParallelFiles, file_count));
    for (size_t i = 0; i < std::min(kMaxParallelFiles, file_count); ++i) {
        workers.emplace_back(worker);
    }
    for (auto& thread : workers) {
        if (thread.joinable()) {
            thread.join();
        }
    }

    parallel_progress_snapshot snapshot =
        update_parallel_progress(task, file_count - 1, task->parallel_file_bytes[file_count - 1],
                                 task->parallel_file_totals[file_count - 1], total_expected, false);

    if (saw_failure.load()) {
        std::lock_guard<std::mutex> lock(result_mutex);
        const rav1::DownloadState state =
            terminal_cancelled ? rav1::DOWNLOAD_STATE_CANCELLED : rav1::DOWNLOAD_STATE_FAILED;
        set_task_progress(task, state, rav1::DOWNLOAD_STAGE_DOWNLOADING, snapshot.bytes_downloaded,
                          snapshot.total_bytes, static_cast<int32_t>(terminal_index),
                          terminal_index < task->files.size() ? task->files[terminal_index].storage_key
                                                              : "",
                          "", terminal_error);
        mark_task_stopped(task);
        emit_progress(task);
        return true;
    }

    if (task->cancel_requested.load()) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          snapshot.bytes_downloaded, snapshot.total_bytes, 0, "", "",
                          "download cancelled");
        mark_task_stopped(task);
        emit_progress(task);
        return true;
    }

    size_t failing_index = 0;
    std::string sanity_error;
    if (!validate_downloaded_sizes(task, failing_index, sanity_error)) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          snapshot.bytes_downloaded, snapshot.total_bytes,
                          static_cast<int32_t>(failing_index), task->files[failing_index].storage_key,
                          "", sanity_error);
        mark_task_stopped(task);
        emit_progress(task);
        return true;
    }

    const int64_t completed_bytes = total_expected > 0 ? total_expected : snapshot.bytes_downloaded;
    std::string completion_local_path =
        resolve_completion_local_path(task, task->files.back().destination_path);
    set_task_progress(task, rav1::DOWNLOAD_STATE_COMPLETED, rav1::DOWNLOAD_STAGE_COMPLETED,
                      completed_bytes, total_expected, static_cast<int32_t>(task->files.size() - 1),
                      task->files.back().storage_key, completion_local_path, "");
    mark_task_stopped(task);
    emit_progress(task);
    self_heal_registry(task, completion_local_path);
    return true;
}

void run_proto_download_worker(const std::shared_ptr<proto_download_task>& task,
                               int64_t resume_from) {
    if (!task) {
        return;
    }

    std::string started_model_id;
    int64_t started_total_bytes = 0;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = true;
        if (!task->download_telemetry_started) {
            task->download_telemetry_started = true;
            started_model_id = task->model_id;
            started_total_bytes = task->progress.total_bytes();
        }
    }
    if (!started_model_id.empty()) {
        rac::events::emit_model_download_started(started_model_id.c_str(), started_total_bytes,
                                                 nullptr);
    }

    const int64_t total_expected = plan_total_expected(task->files);
    if (run_parallel_direct_download_worker(task, total_expected, resume_from)) {
        return;
    }

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

        if (process_plan_file(task, file, i, total_expected, file_resume_from,
                              completed_before_file, final_path) == plan_file_step::STOP) {
            return;
        }
    }

    if (task->cancel_requested.load()) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          completed_before_file, total_expected, 0, "", "", "download cancelled");
        mark_task_stopped(task);
        emit_progress(task);
        return;
    }

    int64_t completed_bytes = total_expected > 0 ? total_expected : completed_before_file;

    // Post-finalize size guard: refuse to register if any non-extracted file is
    // < 80% of its declared expected_bytes (see validate_downloaded_sizes).
    size_t failing_index = 0;
    std::string sanity_error;
    if (!validate_downloaded_sizes(task, failing_index, sanity_error)) {
        int64_t failed_bytes = total_expected > 0 ? completed_before_file : 0;
        set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          failed_bytes, total_expected, static_cast<int32_t>(failing_index),
                          task->files[failing_index].storage_key, "", sanity_error);
        mark_task_stopped(task);
        emit_progress(task);
        return;
    }

    std::string completion_local_path = resolve_completion_local_path(task, final_path);
    set_task_progress(task, rav1::DOWNLOAD_STATE_COMPLETED, rav1::DOWNLOAD_STAGE_COMPLETED,
                      completed_bytes, total_expected, static_cast<int32_t>(task->files.size() - 1),
                      task->files.empty() ? "" : task->files.back().storage_key,
                      completion_local_path, "");
    mark_task_stopped(task);
    emit_progress(task);

    self_heal_registry(task, completion_local_path);
}

#ifdef __EMSCRIPTEN__
struct emscripten_proto_download_args {
    std::shared_ptr<proto_download_task> task;
    int64_t resume_from = 0;
};

void run_proto_download_worker_async(void* user_data) {
    std::unique_ptr<emscripten_proto_download_args> args(
        static_cast<emscripten_proto_download_args*>(user_data));
    if (!args) {
        return;
    }
    run_proto_download_worker(args->task, args->resume_from);
}

// =============================================================================
// EVENT-DRIVEN ASYNC DOWNLOAD DRIVER (Emscripten / Web)
// =============================================================================
// The synchronous worker above cannot provide live main-thread progress. When
// the platform supplies the async `http_download` adapter slot (the Web SDK
// implements it with streaming fetch + ReadableStream), drive the plan
// event-driven instead: start a file, report each chunk via the progress
// callback, and on completion advance to the next file or finalize. Nothing
// blocks the main thread, so progress is live.
//
// This path reuses every leaf helper the synchronous worker uses
// (set_task_progress / emit_progress / extraction / validate_downloaded_sizes /
// resolve_completion_local_path / self_heal_registry). Only the *sequencing*
// differs (callback continuation vs a blocking loop). The synchronous worker
// and all native code are left untouched and remain the fallback when the slot
// is absent.
//
// Integrity: the slot delivers bytes to the platform (MEMFS), never to C++, so
// the streaming SHA-256 the synchronous path computes cannot run here. The
// post-download size guard (validate_downloaded_sizes) plus HTTPS transport
// integrity cover truncation/stub responses; per-byte checksum is a Web-path
// tradeoff (the native path keeps full SHA-256).
struct web_download_driver {
    std::shared_ptr<proto_download_task> task;
    int64_t total_expected = 0;
    int64_t completed_before_file = 0;
    size_t file_index = 0;
    std::string final_path;
    char* current_task_id = nullptr;  // owned C string from http_download out_task_id
    bool cancel_abort_sent = false;
};

// Keeps each driver alive across the async callbacks (the callbacks carry only a
// raw driver* as user_data). Erasing drops the last owner and frees the driver.
std::map<web_download_driver*, std::shared_ptr<web_download_driver>>& web_download_registry() {
    static std::map<web_download_driver*, std::shared_ptr<web_download_driver>> registry;
    return registry;
}

void web_download_start_file(web_download_driver* drv);
void web_download_finalize_all(web_download_driver* drv);

// MUST be the final action on a driver in any terminal branch — frees the
// driver, so nothing may touch `drv` afterwards.
void web_download_finish(web_download_driver* drv) {
    if (!drv) {
        return;
    }
    if (drv->current_task_id) {
        free(drv->current_task_id);
        drv->current_task_id = nullptr;
    }
    web_download_registry().erase(drv);
}

// rac_http_progress_callback_fn: void (int64 bytes, int64 total, void* user_data).
void web_download_on_progress(int64_t bytes_downloaded, int64_t total_bytes, void* user_data) {
    auto* drv = static_cast<web_download_driver*>(user_data);
    if (!drv) {
        return;
    }
    const std::shared_ptr<proto_download_task>& task = drv->task;

    // Cooperative cancel: abort the in-flight fetch once; on_complete then fires
    // with RAC_ERROR_CANCELLED and emits the terminal event.
    if (task->cancel_requested.load() && !drv->cancel_abort_sent) {
        drv->cancel_abort_sent = true;
        const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
        if (adapter && adapter->http_download_cancel && drv->current_task_id) {
            adapter->http_download_cancel(drv->current_task_id, adapter->user_data);
        }
        return;
    }

    const int64_t downloaded = drv->completed_before_file + bytes_downloaded;
    const proto_plan_file& file = task->files[drv->file_index];
    // See proto_http_progress: multi-file bundles without per-file sizes need a
    // monotonic file-count overall fraction (a byte ratio against an unknown
    // plan total would otherwise stay at 0 the whole download, then snap to 1).
    float overall_override = -1.0f;
    const size_t num_files = task->files.size();
    if (drv->total_expected <= 0 && num_files > 1) {
        double file_fraction = total_bytes > 0
                                   ? std::min(1.0, static_cast<double>(bytes_downloaded) /
                                                       static_cast<double>(total_bytes))
                                   : 0.0;
        overall_override = static_cast<float>(
            (static_cast<double>(drv->file_index) + file_fraction) / static_cast<double>(num_files));
    }
    set_task_progress(task, rav1::DOWNLOAD_STATE_DOWNLOADING, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                      downloaded, drv->total_expected, static_cast<int32_t>(drv->file_index),
                      file.storage_key, "", "", overall_override);
    emit_progress(task);
}

// rac_http_complete_callback_fn: void (rac_result_t, const char* path, void* user_data).
void web_download_on_complete(rac_result_t result, const char* /*downloaded_path*/, void* user_data) {
    auto* drv = static_cast<web_download_driver*>(user_data);
    if (!drv) {
        return;
    }
    // Keep the task alive independently of the driver (web_download_finish frees
    // the driver at the end of the terminal branches).
    std::shared_ptr<proto_download_task> task = drv->task;
    if (drv->current_task_id) {
        free(drv->current_task_id);
        drv->current_task_id = nullptr;
    }

    const size_t i = drv->file_index;
    const proto_plan_file& file = task->files[i];

    const bool cancelled = task->cancel_requested.load() || result == RAC_ERROR_CANCELLED;
    if (cancelled) {
        int64_t file_partial = file_size_or_zero(file.destination_path);
        int64_t deleted = 0;
        bool delete_partial = false;
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            delete_partial = task->delete_partial_on_cancel;
        }
        if (delete_partial) {
            deleted = delete_partial_file(file.destination_path);
            file_partial = 0;
        }
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            task->last_deleted_bytes = deleted;
            task->last_partial_bytes = drv->completed_before_file + file_partial;
        }
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          drv->completed_before_file + file_partial, drv->total_expected,
                          static_cast<int32_t>(i), file.storage_key, "", "download cancelled");
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
        return;
    }

    if (result != RAC_SUCCESS) {
        int64_t partial = drv->completed_before_file + file_size_or_zero(file.destination_path);
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            task->last_partial_bytes = partial;
        }
        set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          partial, drv->total_expected, static_cast<int32_t>(i), file.storage_key,
                          "", "download failed");
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
        return;
    }

    // Success: extract (if archive) and advance the cumulative counter — mirrors
    // the post-download tail of process_plan_file.
    if (file.requires_extraction) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_EXTRACTING, rav1::DOWNLOAD_STAGE_EXTRACTING,
                          drv->total_expected > 0 ? drv->completed_before_file + file.expected_bytes
                                                  : 0,
                          drv->total_expected, static_cast<int32_t>(i), file.storage_key, "", "");
        emit_progress(task);

        mkdir_p(task->model_folder_path.c_str());

        rac_extraction_result_t extraction_result{};
        rac_result_t extract_rc = rac_extract_archive_native(
            file.destination_path.c_str(), task->model_folder_path.c_str(), nullptr, nullptr,
            nullptr, &extraction_result);
        if (extract_rc != RAC_SUCCESS) {
            set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_EXTRACTING,
                              drv->total_expected > 0
                                  ? drv->completed_before_file + file.expected_bytes
                                  : 0,
                              drv->total_expected, static_cast<int32_t>(i), file.storage_key, "",
                              "archive extraction failed");
            mark_task_stopped(task);
            emit_progress(task);
            web_download_finish(drv);
            return;
        }

        delete_file(file.destination_path.c_str());

        char resolved_path[4096];
        rac_result_t find_rc = rac_find_model_path_after_extraction(
            task->model_folder_path.c_str(), task->archive_structure, task->framework, task->format,
            resolved_path, sizeof(resolved_path));
        drv->final_path = (find_rc == RAC_SUCCESS && resolved_path[0] != '\0')
                              ? std::string(resolved_path)
                              : task->model_folder_path;
    } else {
        drv->final_path = file.destination_path;
    }

    if (drv->total_expected > 0) {
        drv->completed_before_file += std::max<int64_t>(file.expected_bytes, 0);
    } else {
        drv->completed_before_file += file_size_or_zero(drv->final_path);
    }

    drv->file_index += 1;
    if (drv->file_index < task->files.size()) {
        web_download_start_file(drv);
    } else {
        web_download_finalize_all(drv);
    }
}

void web_download_start_file(web_download_driver* drv) {
    const std::shared_ptr<proto_download_task>& task = drv->task;
    const size_t i = drv->file_index;
    const proto_plan_file& file = task->files[i];

    if (task->cancel_requested.load()) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          drv->completed_before_file, drv->total_expected, static_cast<int32_t>(i),
                          file.storage_key, "", "download cancelled");
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
        return;
    }

    // Ensure the file's parent directory exists (multi-segment subpaths such as
    // VLM host-weight fixtures under "vlm/…" need their intermediate dir).
    {
        fs::path dest_path(file.destination_path);
        if (dest_path.has_parent_path())
            mkdir_p(dest_path.parent_path().string().c_str());
    }

    // A previous attempt may already have landed this file completely; skip the
    // fetch and run the success tail directly (extraction + advance).
    const bool already_complete =
        file.expected_bytes > 0 && file_size_or_zero(file.destination_path) == file.expected_bytes;
    if (already_complete) {
        web_download_on_complete(RAC_SUCCESS, file.destination_path.c_str(), drv);
        return;
    }

    set_task_progress(task, rav1::DOWNLOAD_STATE_DOWNLOADING, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                      drv->completed_before_file, drv->total_expected, static_cast<int32_t>(i),
                      file.storage_key, "", "");
    emit_progress(task);

    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    char* task_id = nullptr;
    rac_result_t rc = adapter->http_download(file.url.c_str(), file.destination_path.c_str(),
                                             web_download_on_progress, web_download_on_complete, drv,
                                             &task_id, adapter->user_data);
    drv->current_task_id = task_id;
    if (rc != RAC_SUCCESS) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          drv->completed_before_file, drv->total_expected, static_cast<int32_t>(i),
                          file.storage_key, "", "failed to start download");
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
    }
}

void web_download_finalize_all(web_download_driver* drv) {
    const std::shared_ptr<proto_download_task>& task = drv->task;

    if (task->cancel_requested.load()) {
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          drv->completed_before_file, drv->total_expected, 0, "", "",
                          "download cancelled");
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
        return;
    }

    const int64_t completed_bytes =
        drv->total_expected > 0 ? drv->total_expected : drv->completed_before_file;

    size_t failing_index = 0;
    std::string sanity_error;
    if (!validate_downloaded_sizes(task, failing_index, sanity_error)) {
        int64_t failed_bytes = drv->total_expected > 0 ? drv->completed_before_file : 0;
        set_task_progress(task, rav1::DOWNLOAD_STATE_FAILED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          failed_bytes, drv->total_expected, static_cast<int32_t>(failing_index),
                          task->files[failing_index].storage_key, "", sanity_error);
        mark_task_stopped(task);
        emit_progress(task);
        web_download_finish(drv);
        return;
    }

    std::string completion_local_path = resolve_completion_local_path(task, drv->final_path);
    set_task_progress(task, rav1::DOWNLOAD_STATE_COMPLETED, rav1::DOWNLOAD_STAGE_COMPLETED,
                      completed_bytes, drv->total_expected,
                      static_cast<int32_t>(task->files.size() - 1),
                      task->files.empty() ? "" : task->files.back().storage_key,
                      completion_local_path, "");
    mark_task_stopped(task);
    emit_progress(task);
    self_heal_registry(task, completion_local_path);
    web_download_finish(drv);
}

// Non-blocking entry: kick off file 0; the adapter's async callbacks drive the
// rest. Mirrors run_proto_download_worker's telemetry-start preamble.
void web_download_start(const std::shared_ptr<proto_download_task>& task, int64_t /*resume_from*/) {
    auto drv = std::make_shared<web_download_driver>();
    drv->task = task;
    drv->total_expected = plan_total_expected(task->files);
    web_download_registry()[drv.get()] = drv;

    std::string started_model_id;
    int64_t started_total_bytes = 0;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->running = true;
        if (!task->download_telemetry_started) {
            task->download_telemetry_started = true;
            started_model_id = task->model_id;
            started_total_bytes = task->progress.total_bytes();
        }
    }
    if (!started_model_id.empty()) {
        rac::events::emit_model_download_started(started_model_id.c_str(), started_total_bytes,
                                                 nullptr);
    }

    if (task->files.empty()) {
        web_download_finalize_all(drv.get());
        return;
    }
    web_download_start_file(drv.get());
}

void start_proto_download_worker(const std::shared_ptr<proto_download_task>& task,
                                 int64_t resume_from) {
    // Prefer the async streaming slot when the platform supplies it (Web): it
    // reports progress per chunk without blocking the main thread. Otherwise
    // fall back to the synchronous worker on a deferred tick.
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter && adapter->http_download) {
        web_download_start(task, resume_from);
        return;
    }
    auto* args = new emscripten_proto_download_args{task, resume_from};
    emscripten_async_call(run_proto_download_worker_async, args, 0);
}
#else
void start_proto_download_worker(const std::shared_ptr<proto_download_task>& task,
                                 int64_t resume_from) {
    std::thread([task, resume_from]() { run_proto_download_worker(task, resume_from); }).detach();
}
#endif

std::string destination_from_model_file(const std::string& model_folder,
                                        const rav1::ModelFileDescriptor& file,
                                        const std::string& url,
                                        const std::string& fallback_model_id) {
    // security-privacy-storage-network-001: descriptor.destination_path is
    // app/catalog metadata, not a trusted filesystem policy. Reject absolute
    // paths and any relative path that lexically escapes model_folder before
    // the worker can hand it to rac_http_download_execute.
    if (file.has_destination_path() && !file.destination_path().empty()) {
        if (auto safe = safe_descriptor_path_under(model_folder, file.destination_path())) {
            return *safe;
        }
        RAC_LOG_WARNING(
            LOG_TAG,
            "Rejecting unsafe descriptor destination_path '%s' for model_folder '%s' "
            "(security-privacy-storage-network-001); falling back to filename-only path.",
            file.destination_path().c_str(), model_folder.c_str());
        // Intentionally fall through to the filename-based path below so the
        // download still completes safely instead of aborting the whole plan.
    }

    // A descriptor may declare a multi-segment relative subpath (in
    // relative_path, or carried inline in filename) so a bundle preserves its
    // on-disk directory layout — e.g. InternVL VLM host-weight fixtures staged
    // under "vlm/pe_w.bin" that the QHexRT runtime resolves via fixture_dir.
    // A plain `filename` is a single segment (is_safe_path_segment forbids
    // separators); only route through the subdir-aware joiner when separators
    // are actually present, so the common single-file case is unchanged.
    // safe_descriptor_path_under validates every segment ('.'/'..'/empty/
    // backslash are rejected) and enforces containment under model_folder, so
    // this preserves the path-traversal hardening while allowing legit subdirs.
    auto subpath_destination = [&](const std::string& rel) -> std::optional<std::string> {
        if (rel.empty() || (rel.find('/') == std::string::npos && rel.find('\\') == std::string::npos))
            return std::nullopt;
        return safe_descriptor_path_under(model_folder, rel);
    };
    if (file.has_relative_path()) {
        if (auto safe = subpath_destination(file.relative_path()))
            return *safe;
    }
    if (auto safe = subpath_destination(file.filename()))
        return *safe;

    std::string filename = file.filename();
    if (!filename.empty() && !is_safe_path_segment(filename)) {
        RAC_LOG_WARNING(LOG_TAG,
                        "Rejecting unsafe descriptor filename '%s' "
                        "(security-privacy-storage-network-001); deriving from URL.",
                        filename.c_str());
        filename.clear();
    }
    if (filename.empty()) {
        filename = get_filename(url.c_str());
        if (!filename.empty() && !is_safe_path_segment(filename)) {
            RAC_LOG_WARNING(LOG_TAG,
                            "Rejecting unsafe URL-derived filename '%s' "
                            "(security-privacy-storage-network-001); using model_id fallback.",
                            filename.c_str());
            filename.clear();
        }
    }
    if (filename.empty()) {
        filename = fallback_model_id;
    }
    if (!is_safe_path_segment(filename)) {
        // Last-ditch sanitization: if every input collapsed to an unsafe
        // value, return model_folder unchanged so the writer fails cleanly
        // (it will reject an attempt to open a directory for write) rather
        // than silently writing outside the root.
        return model_folder;
    }
    return join_path(model_folder, filename);
}

void append_planned_file(rav1::DownloadPlanResult* result,
                         const rav1::ModelFileDescriptor& descriptor,
                         const std::string& model_folder, const std::string& model_id,
                         const std::string& url, int64_t expected_bytes,
                         const std::string& checksum_sha256, bool requires_extraction,
                         bool is_resume_candidate) {
    rav1::DownloadFilePlan* out_file = result->add_files();
    copy_file_descriptor_plan(descriptor, out_file);
    if (out_file->file().url().empty()) {
        out_file->mutable_file()->set_url(url);
    }
    std::string destination =
        destination_from_model_file(model_folder, out_file->file(), url, model_id);

    if (requires_extraction) {
        // Archive downloads stage the raw archive under the shared
        // `{base}/RunAnywhere/Downloads/` temp dir before extraction. The
        // framework parameter is IGNORED by rac_download_compute_destination
        // on the archive branch (it only computes a per-framework path for
        // direct/non-archive files), so passing RAC_FRAMEWORK_UNKNOWN here is
        // both correct and self-documenting — the final per-model location is
        // resolved later via rac_model_paths_get_model_folder() in the
        // download worker, keyed off the registry entry's framework.
        char computed[4096];
        rac_bool_t ignored = RAC_FALSE;
        if (rac_download_compute_destination(model_id.c_str(), url.c_str(), RAC_FRAMEWORK_UNKNOWN,
                                             RAC_MODEL_FORMAT_UNKNOWN, computed, sizeof(computed),
                                             &ignored) == RAC_SUCCESS) {
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
    out_file->set_is_resume_candidate(is_resume_candidate);
}

// Seed is_resume_candidate on a just-appended plan entry from on-disk partial
// bytes. Oversized partials (existing > declared expected size) are
// SELF-HEALED here when validate_existing_bytes was requested: the stale
// partial is deleted and the entry replanned as a fresh download. This used
// to be per-SDK filesystem logic (Swift/Kotlin/Flutter each carried an
// identical delete-and-replan loop); planning owns it now so every consumer
// gets the heal for free. Returns true only when an oversized partial could
// NOT be removed (caller fails the plan with OVERSIZE_PARTIAL_BYTES).
bool seed_resume_candidate(rav1::DownloadFilePlan* planned, int64_t expected_bytes,
                           bool resume_existing, bool validate_existing_bytes) {
    if (!resume_existing)
        return false;
    int64_t existing_bytes = file_size_or_zero(planned->destination_path());
    if (validate_existing_bytes && expected_bytes > 0 && existing_bytes > expected_bytes) {
        RAC_LOG_WARNING(LOG_TAG,
                        "Existing partial '%s' is %lld bytes but %lld are expected — deleting "
                        "the stale partial and replanning as a fresh download",
                        planned->destination_path().c_str(), static_cast<long long>(existing_bytes),
                        static_cast<long long>(expected_bytes));
        std::error_code ec;
        fs::remove(planned->destination_path(), ec);
        existing_bytes = file_size_or_zero(planned->destination_path());
        if (existing_bytes > expected_bytes) {
            planned->set_is_resume_candidate(false);
            return true;  // deletion failed — surface OVERSIZE_PARTIAL_BYTES
        }
    }
    bool candidate =
        existing_bytes > 0 && (expected_bytes <= 0 || existing_bytes <= expected_bytes);
    planned->set_is_resume_candidate(candidate);
    return false;
}

// security-privacy-storage-network-001: defensive check
// applied to plan entries flowing in via rac_download_start_proto (which
// lets callers skip the trusted planner). The trusted planner always emits
// absolute paths rooted under either the per-model folder
// (rac_model_paths_get_model_folder) or the shared archive-staging
// downloads dir (rac_model_paths_get_downloads_directory), so we accept
// absolute paths but require lexical containment under one of those known
// roots. Reject any '..' / '.' / empty / backslash path components — those
// are the traversal vectors that allow a malicious plan to escape the
// storage root even when the path looks rooted. Without the containment
// check, well-formed absolute paths outside model_folder (e.g.
// `/etc/passwd`, `/Users/victim/.ssh/authorized_keys`) would pass.
bool path_has_unsafe_components(const std::string& path) {
    if (path.empty())
        return true;
    size_t start = 0;
    while (start < path.size()) {
        size_t end = path.find_first_of("/\\", start);
        if (end == std::string::npos)
            end = path.size();
        // Tolerate the leading '/' on POSIX absolute paths and the
        // leading '\\' on UNC-style Windows paths by allowing exactly one
        // empty segment at position 0.
        if (end == start) {
            if (start == 0) {
                start = end + 1;
                continue;
            }
            return true;  // double separator inside the path
        }
        std::string component = path.substr(start, end - start);
        if (component == "." || component == "..")
            return true;
        if (end == path.size())
            break;
        start = end + 1;
    }
    return false;
}

// Returns true if `path` is rooted under `root` after both have been
// normalized AND symlink-resolved for their existing prefixes
// (weakly_canonical). Pure lexical comparison breaks on macOS where /tmp is a
// symlink to /private/tmp: a resume plan whose existing partial file
// canonicalized to /private/tmp/... must still count as contained under a
// /tmp/... root (and canonicalizing both sides also closes symlink-escape
// holes the lexical check could not see). Empty `root` is vacuously false (we
// never accept a bypass-plan path when we couldn't resolve a containment
// root).
bool path_is_under_root(const std::string& path, const std::string& root) {
    if (path.empty() || root.empty())
        return false;
    std::error_code path_ec;
    std::error_code root_ec;
    fs::path norm_path = fs::weakly_canonical(path, path_ec);
    fs::path norm_root = fs::weakly_canonical(root, root_ec);
    if (path_ec || norm_path.empty())
        norm_path = fs::path(path).lexically_normal();
    if (root_ec || norm_root.empty())
        norm_root = fs::path(root).lexically_normal();
    auto root_it = norm_root.begin();
    auto path_it = norm_path.begin();
    for (; root_it != norm_root.end() && path_it != norm_path.end(); ++root_it, ++path_it) {
        if (*root_it != *path_it)
            return false;
    }
    return root_it == norm_root.end();
}

bool is_traversal_safe_destination(const std::string& path, const std::string& model_folder,
                                   const std::string& downloads_dir) {
    if (path_has_unsafe_components(path))
        return false;
    // Platform-trusted absolute mount roots (e.g. Emscripten /opfs/) are
    // sandboxed by the platform itself — accept verbatim once unsafe
    // components have been ruled out above. This is the bypass-planner
    // analog of the planner-side exception in safe_descriptor_path_under.
    if (is_platform_trusted_absolute_prefix(path))
        return true;
    // Require lexical containment under at least one known-safe root:
    // either the per-model folder (direct-write destinations) or the
    // shared archive-staging downloads dir (extraction-bearing files).
    if (path_is_under_root(path, model_folder))
        return true;
    if (path_is_under_root(path, downloads_dir))
        return true;
    return false;
}

std::vector<proto_plan_file> files_from_plan(const rav1::DownloadPlanResult& plan,
                                             const std::string& model_folder,
                                             const std::string& downloads_dir) {
    std::vector<proto_plan_file> files;
    files.reserve(static_cast<size_t>(plan.files_size()));
    for (const auto& input : plan.files()) {
        // security-privacy-storage-network-001:
        // DownloadPlanResult.files can originate from rac_download_plan_proto
        // (trusted, already validated by destination_from_model_file) OR from
        // a caller-supplied DownloadStartRequest.plan_files that bypasses
        // planning. The traversal-safe check defends the bypass path by
        // requiring containment under model_folder or the downloads staging
        // dir, in addition to rejecting '..'/'.'/empty components.
        const std::string& destination = input.destination_path();
        if (!is_traversal_safe_destination(destination, model_folder, downloads_dir)) {
            RAC_LOG_WARNING(LOG_TAG,
                            "Skipping plan entry with unsafe destination_path '%s' "
                            "(not contained under model_folder='%s' or downloads_dir='%s'; "
                            "security-privacy-storage-network-001).",
                            destination.c_str(), model_folder.c_str(), downloads_dir.c_str());
            continue;
        }

        proto_plan_file file;
        file.url = input.file().url();
        file.destination_path = destination;
        file.storage_key = input.storage_key();
        file.expected_bytes = input.expected_bytes();
        file.checksum_sha256 = input.checksum_sha256();
        file.requires_extraction = input.requires_extraction();
        file.is_resume_candidate = input.is_resume_candidate();
        file.filename = input.file().filename();
        if (!file.filename.empty() && !is_safe_path_segment(file.filename)) {
            RAC_LOG_WARNING(LOG_TAG,
                            "Replacing unsafe plan filename '%s' with URL-derived basename "
                            "(security-privacy-storage-network-001).",
                            file.filename.c_str());
            file.filename.clear();
        }
        if (file.filename.empty()) {
            file.filename = get_filename(file.url.c_str());
        }
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
// PUBLIC API — DOWNLOAD ORCHESTRATION
// =============================================================================

#ifdef RAC_HAVE_PROTOBUF
extern "C" rac_result_t
rac_download_set_progress_proto_callback(rac_download_proto_progress_callback_fn callback,
                                         void* user_data) {
    std::lock_guard<std::mutex> lock(progress_sink().mutex);
    auto& sink = progress_sink();
    sink.callback = callback;
    sink.user_data = user_data;
    if (!callback) {
        // Free ring memory once no subscriber remains. Leaving the ring
        // allocated on clear would otherwise pin up to 32 serialized
        // DownloadProgress buffers for the lifetime of the process.
        for (auto& slot : sink.bytes_ring) {
            std::string().swap(slot);
        }
        sink.ring_index = 0;
    }
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_download_plan_proto(const uint8_t* request_bytes, size_t request_size,
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
    result.set_storage_namespace(request.storage_namespace());
    result.set_required_free_bytes_after_download(request.required_free_bytes_after_download());

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

    // Seed expected_files from multi_file when only multi_file
    // is set so the per-descriptor download loop below picks up the real
    // URLs each ModelFileDescriptor carries. Without this, multi-file VLM
    // registrations (LFM2-VL, Qwen2-VL via registerMultiFileModel) fall
    // through to the else branch and are rejected with
    // "model.download_url must be an http(s) URL".
    //
    // Mirrors the resolution order in
    // sdk/runanywhere-commons/src/infrastructure/model_management/
    // artifact_expected_files_proto.cpp (Swift parity:
    // RAModelInfo.expectedArtifactFiles + OneOf_Artifact.expectedFiles).
    rav1::ModelInfo seeded_model;
    const rav1::ModelInfo* model_ptr = &request.model();
    if (!model_ptr->has_expected_files() && model_ptr->has_multi_file() &&
        model_ptr->multi_file().files_size() > 0) {
        seeded_model = *model_ptr;
        seeded_model.mutable_expected_files()->mutable_files()->CopyFrom(
            seeded_model.multi_file().files());
        model_ptr = &seeded_model;
    }
    const rav1::ModelInfo& model = *model_ptr;

    // A model can be registered as an archive artifact (ZIP/TAR) whose download
    // URL carries no archive file extension — e.g. a Google Drive / CDN link
    // that ends in a query string ("...&export=download&confirm=t"). The URL
    // sniff (rac_archive_type_from_path) only catches the extension case, so
    // consult the registered artifact metadata as the authoritative signal and
    // fall back to it below when the URL itself is opaque.
    const rac_archive_type_t registered_archive_type = [&]() -> rac_archive_type_t {
        switch (model.artifact_type()) {
            case rav1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
                return RAC_ARCHIVE_TYPE_ZIP;
            case rav1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
                return RAC_ARCHIVE_TYPE_TAR_GZ;
            case rav1::MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
                return RAC_ARCHIVE_TYPE_TAR_BZ2;
            case rav1::MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
                return RAC_ARCHIVE_TYPE_TAR_XZ;
            default:
                break;
        }
        if (model.has_archive()) {
            switch (model.archive().type()) {
                case rav1::ARCHIVE_TYPE_ZIP:
                    return RAC_ARCHIVE_TYPE_ZIP;
                case rav1::ARCHIVE_TYPE_TAR_GZ:
                    return RAC_ARCHIVE_TYPE_TAR_GZ;
                case rav1::ARCHIVE_TYPE_TAR_BZ2:
                    return RAC_ARCHIVE_TYPE_TAR_BZ2;
                case rav1::ARCHIVE_TYPE_TAR_XZ:
                    return RAC_ARCHIVE_TYPE_TAR_XZ;
                default:
                    break;
            }
        }
        return RAC_ARCHIVE_TYPE_NONE;
    }();

    rac_inference_framework_t framework = proto_framework_to_c(model.framework());
    if (framework == RAC_FRAMEWORK_UNKNOWN) {
        framework = RAC_FRAMEWORK_LLAMACPP;
        result.add_warnings("unknown framework; using llama.cpp storage path");
    }
    rac_model_format_t format = proto_format_to_c(model.format());

    char model_folder[4096];
    rac_result_t path_rc = rac_model_paths_get_model_folder(model_id.c_str(), framework,
                                                            model_folder, sizeof(model_folder));
    if (path_rc != RAC_SUCCESS) {
        result.set_can_start(false);
        result.set_error_message("failed to compute model storage path");
        return serialize_proto_to_buffer(result, out_result);
    }

    int64_t total_bytes = 0;
    bool all_sizes_known = true;
    bool any_extraction = false;
    bool invalid_existing_bytes = false;
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
            bool requires_extraction =
                rac_archive_type_from_path(url.c_str(), &archive_type) == RAC_TRUE;
            any_extraction = any_extraction || requires_extraction;

            int64_t expected_bytes = file.has_size_bytes() ? file.size_bytes() : 0;
            if (expected_bytes <= 0 && !requires_extraction) {
                // Multi-file NPU/VLM bundles register without per-file sizes.
                // Probe the server (HEAD → Content-Length) so the pre-flight
                // storage gate can size the bundle before any bytes land.
                int64_t probed = http_head_content_length(url);
                if (probed > 0) {
                    expected_bytes = probed;
                }
            }
            if (expected_bytes > 0) {
                total_bytes += expected_bytes;
            } else {
                all_sizes_known = false;
            }
            std::string checksum = checksum_from_descriptor(file);
            if (request.verify_checksums() && checksum.empty()) {
                result.add_warnings(
                    "checksum verification requested but a file checksum is missing");
            }
            append_planned_file(&result, file, model_folder, model_id, url, expected_bytes,
                                checksum, requires_extraction, false);
            rav1::DownloadFilePlan* planned = result.mutable_files(result.files_size() - 1);
            if (seed_resume_candidate(planned, expected_bytes, request.resume_existing(),
                                      request.validate_existing_bytes())) {
                invalid_existing_bytes = true;
            }
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
        rac_result_t dest_rc =
            rac_download_compute_destination(model_id.c_str(), url.c_str(), framework, format,
                                             destination, sizeof(destination), &needs_extraction);
        if (dest_rc != RAC_SUCCESS) {
            result.set_can_start(false);
            result.set_error_message("failed to compute download destination");
            return serialize_proto_to_buffer(result, out_result);
        }

        // The URL carried no archive extension (rac_download_compute_destination
        // resolved a direct-to-model-folder path) but the model is registered as
        // an archive artifact. Re-stage to the shared downloads temp dir and force
        // extraction so the bundle is unpacked into the per-model folder — mirrors
        // the archive branch of rac_download_compute_destination.
        if (needs_extraction == RAC_FALSE && registered_archive_type != RAC_ARCHIVE_TYPE_NONE) {
            char downloads_dir[4096];
            if (rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir)) ==
                RAC_SUCCESS) {
                std::string stem = get_filename_stem(url.c_str());
                if (stem.empty()) {
                    stem = model_id;
                }
                const std::string model_stem = safe_filename_stem(model_id);
                const std::string archive_stem = safe_filename_stem(stem);
                snprintf(destination, sizeof(destination), "%s/%s-%s.%s", downloads_dir,
                         model_stem.c_str(), archive_stem.c_str(),
                         rac_archive_type_extension(registered_archive_type));
                needs_extraction = RAC_TRUE;
            }
        }

        rav1::ModelFileDescriptor descriptor;
        descriptor.set_url(url);
        descriptor.set_filename(get_filename(url.c_str()));
        descriptor.set_destination_path(destination);

        int64_t expected_bytes = model.download_size_bytes();
        if (expected_bytes <= 0 && needs_extraction == RAC_FALSE) {
            // Catalog carries no size — probe the server so the pre-flight
            // storage gate can fire before any bytes land.
            int64_t probed = http_head_content_length(url);
            if (probed > 0) {
                expected_bytes = probed;
            }
        }
        if (expected_bytes > 0) {
            descriptor.set_size_bytes(expected_bytes);
            total_bytes += expected_bytes;
        } else {
            all_sizes_known = false;
        }
        descriptor.set_is_required(true);
        any_extraction = needs_extraction == RAC_TRUE;
        if (request.verify_checksums() && model_checksum.empty()) {
            result.add_warnings("checksum verification requested but model checksum is missing");
        }
        append_planned_file(&result, descriptor, model_folder, model_id, url, expected_bytes,
                            model_checksum, any_extraction, false);
        result.mutable_files(0)->set_destination_path(destination);
        if (seed_resume_candidate(result.mutable_files(0), expected_bytes,
                                  request.resume_existing(), request.validate_existing_bytes())) {
            invalid_existing_bytes = true;
        }
    }

    if (!all_sizes_known) {
        total_bytes = 0;
        result.add_warnings("one or more file sizes are unknown");
    }

    int64_t resume_from = 0;
    if (request.resume_existing() && result.files_size() > 0) {
        resume_from = file_size_or_zero(result.files(0).destination_path());
        if (result.files(0).expected_bytes() > 0 &&
            resume_from > result.files(0).expected_bytes()) {
            resume_from = 0;
        }
    }

    // Free space: prefer the value the SDK supplied; otherwise query the
    // device filesystem directly so the gate works even when the app passes
    // nothing (the common case for the NPU bundles).
    int64_t available_bytes = request.available_storage_bytes();
    if (available_bytes <= 0) {
        available_bytes = filesystem_available_bytes(model_folder);
    }

    // Resumable bytes already on disk don't need to be re-downloaded, so they
    // count toward the space we still have to find.
    int64_t required_bytes = total_bytes;
    if (required_bytes > 0) {
        if (resume_from > 0 && resume_from < required_bytes) {
            required_bytes -= resume_from;
        }
        // Headroom so we never fill the disk to the last byte (FS metadata,
        // extraction temp space, other writers): max(128 MiB, 3% of payload).
        int64_t margin = std::max<int64_t>(128LL * 1024 * 1024, required_bytes / 33);
        required_bytes += margin;
        if (request.required_free_bytes_after_download() > 0) {
            required_bytes += request.required_free_bytes_after_download();
        }
    }

    if (invalid_existing_bytes) {
        result.set_can_start(false);
        result.set_error_message("existing partial bytes exceed expected byte count");
        result.set_failure_reason(runanywhere::v1::DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES);
    } else if (available_bytes > 0 && required_bytes > 0 && required_bytes > available_bytes) {
        result.set_can_start(false);
        result.set_error_message("Not enough storage to download this model: it needs about " +
                                 human_size(total_bytes) + " but only " +
                                 human_size(available_bytes) +
                                 " is free on the device. Free up space and try again.");
        result.set_failure_reason(runanywhere::v1::DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE);
    } else {
        result.set_can_start(result.files_size() > 0);
    }
    result.set_total_bytes(total_bytes);
    result.set_requires_extraction(any_extraction);
    result.set_can_resume(resume_from > 0);
    result.set_resume_from_bytes(resume_from);
    if (resume_from > 0) {
        result.set_resume_token(make_resume_token("", model_id));
    }

    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_start_proto(const uint8_t* request_bytes, size_t request_size,
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
    std::string model_id =
        request.model_id().empty() ? request.plan().model_id() : request.model_id();
    result.set_model_id(model_id);

    if (model_id.empty() || !request.has_plan() || request.plan().files_size() == 0 ||
        !request.plan().can_start()) {
        result.set_accepted(false);
        result.set_error_message("start request requires a startable plan");
        return serialize_proto_to_buffer(result, out_result);
    }
    if (rac_http_transport_is_registered() == RAC_FALSE) {
        result.set_accepted(false);
        result.set_error_message("no HTTP transport adapter registered");
        return serialize_proto_to_buffer(result, out_result);
    }

    // Idempotent start: if a non-terminal task already exists for this
    // model_id, return the in-flight task instead of spawning a duplicate
    // worker. Fixes SWIFT-IOS-001 (double-tap of Get cancelling the first
    // download) at the commons layer so every SDK gets the same guarantee.
    //
    // The dedup must also fire when the caller passes
    // resume=true. Swift/Kotlin/Flutter/RN all set resume to plan.canResume,
    // so two concurrent start(resume=true) for the same model_id used to
    // spawn two workers writing to the same destination file — data
    // corruption. Only allow resume=true to spawn a fresh worker when the
    // previous task is already in a terminal state (handled implicitly: the
    // loop only short-circuits on active states).
    {
        std::lock_guard<std::mutex> lock(proto_state().mutex);
        for (const auto& entry : proto_state().tasks) {
            const auto& existing = entry.second;
            if (!existing || existing->model_id != model_id)
                continue;
            std::lock_guard<std::mutex> task_lock(existing->mutex);
            const auto state = existing->progress.state();
            const bool active = state == rav1::DOWNLOAD_STATE_PENDING ||
                                state == rav1::DOWNLOAD_STATE_DOWNLOADING ||
                                state == rav1::DOWNLOAD_STATE_EXTRACTING ||
                                state == rav1::DOWNLOAD_STATE_RESUMING;
            if (active) {
                result.set_accepted(true);
                result.set_task_id(existing->task_id);
                result.set_resume_token(existing->resume_token);
                *result.mutable_initial_progress() = existing->progress;
                return serialize_proto_to_buffer(result, out_result);
            }
        }
    }

    auto task = std::make_shared<proto_download_task>();
    task->model_id = model_id;

    // Resolve the canonical per-model folder + archive structure from the
    // registry. The download plan stages archive-bearing files under the
    // shared `Downloads/` temp dir (so HTTP completion can write + verify
    // the raw archive before extraction), which makes `parent_path(first
    // file)` the shared `Downloads/` dir — NOT the per-model destination.
    //
    // Without this lookup, extraction target + reported `local_path`
    // collapse to `Downloads/` (shared) and the backend later tries to
    // load e.g. `Downloads/model.onnx` — fine for the first extracted
    // model (only one nested subdir in `Downloads/`), broken as soon as
    // two archive models have been extracted (`find_nested_directory`
    // falls back to the root because it sees multiple subdirs).
    //
    // Also drives the per-file destination-path containment
    // check performed by files_from_plan() below — must run BEFORE
    // files_from_plan() so the bypass-planner path validation has known-
    // safe roots to assert containment against.
    rac_model_info_t* model_registry_info = nullptr;
    if (rac_get_model(model_id.c_str(), &model_registry_info) == RAC_SUCCESS &&
        model_registry_info) {
        task->framework = model_registry_info->framework;
        task->format = model_registry_info->format;
        task->archive_structure = model_registry_info->artifact_info.archive_structure;
        rac_model_info_free(model_registry_info);
        model_registry_info = nullptr;
    }

    // Resolve the two known-safe roots BEFORE validating the
    // bypass-planner plan entries. files_from_plan() requires each
    // destination_path to be lexically rooted under model_folder OR under
    // downloads_dir (archive staging), in addition to rejecting '..'/'.'
    // components. The trusted planner always emits paths under one of
    // these roots, so any plan entry whose path falls outside both is a
    // bypass-planner attempt to write to an arbitrary filesystem location.
    //
    // When the framework cannot be resolved (model not registered yet, as
    // in the plan-then-start happy path), fall back to the parent
    // `{base}/RunAnywhere/Models/` root which is the lexical parent of
    // every per-framework model folder — this still rejects /etc/passwd
    // while admitting the trusted planner's outputs.
    std::string containment_model_folder;
    std::string containment_downloads_dir;
    std::string canonical_model_folder;
    if (task->framework != RAC_FRAMEWORK_UNKNOWN) {
        char model_folder_buf[4096];
        if (rac_model_paths_get_model_folder(model_id.c_str(), task->framework, model_folder_buf,
                                             sizeof(model_folder_buf)) == RAC_SUCCESS) {
            containment_model_folder = model_folder_buf;
            canonical_model_folder = model_folder_buf;
        }
    }
    if (containment_model_folder.empty()) {
        char models_dir_buf[4096];
        if (rac_model_paths_get_models_directory(models_dir_buf, sizeof(models_dir_buf)) ==
            RAC_SUCCESS) {
            containment_model_folder = models_dir_buf;
        }
    }
    {
        char downloads_dir_buf[4096];
        if (rac_model_paths_get_downloads_directory(downloads_dir_buf, sizeof(downloads_dir_buf)) ==
            RAC_SUCCESS) {
            containment_downloads_dir = downloads_dir_buf;
        }
    }
    if (containment_model_folder.empty() && containment_downloads_dir.empty()) {
        // Without any resolved root we cannot safely admit caller-supplied
        // absolute paths; reject the start request rather than fall back
        // to the syntactic-only check (which accepted /etc/passwd).
        result.set_accepted(false);
        result.set_error_message(
            "start request rejected: cannot resolve a model-folder or downloads-dir root "
            "to validate plan destination paths against (security-privacy-storage-network-001)");
        return serialize_proto_to_buffer(result, out_result);
    }

    task->files =
        files_from_plan(request.plan(), containment_model_folder, containment_downloads_dir);
    // files_from_plan() defensively skips entries with traversal-unsafe
    // destination paths (security-privacy-storage-network-001). If every
    // entry in the plan was skipped, reject the start request rather than
    // proceeding into UB on the empty task->files vector below.
    if (task->files.empty()) {
        result.set_accepted(false);
        result.set_error_message(
            "start request rejected: every plan entry has a traversal-unsafe destination path");
        return serialize_proto_to_buffer(result, out_result);
    }
    task->task_id = "download-proto-" + std::to_string(proto_state().next_task_id.fetch_add(1));
    task->resume_token =
        !request.resume_token().empty()
            ? request.resume_token()
            : (!request.plan().resume_token().empty() ? request.plan().resume_token()
                                                      : make_resume_token(task->task_id, model_id));

    if (!canonical_model_folder.empty()) {
        // Keep the canonical per-model root even when the first descriptor is
        // nested (for example context/model.bin plus a root manifest). Using
        // first_dest.parent_path() in that case publishes the nested directory
        // as local_path and makes the root manifest invisible to loaders.
        task->model_folder_path = canonical_model_folder;
    }

    if (task->model_folder_path.empty()) {
        // Unregistered/bypass-planner fallback: use the first file's parent.
        fs::path first_dest(task->files.front().destination_path);
        if (first_dest.has_parent_path()) {
            task->model_folder_path = first_dest.parent_path().string();
        }
    }
    if (task->model_folder_path.empty()) {
        task->model_folder_path = ".";
    }

    int64_t resume_from = request.resume() ? request.plan().resume_from_bytes() : 0;
    if (request.resume()) {
        int64_t actual_size = 0;
        if (resume_from <= 0) {
            resume_from = file_size_or_zero(task->files.front().destination_path);
        }
        std::string resume_error;
        if (!validate_resume_offset(task->files.front(), resume_from, false, &actual_size,
                                    &resume_error)) {
            result.set_accepted(false);
            result.set_error_message(resume_error);
            result.set_resume_token(task->resume_token);
            return serialize_proto_to_buffer(result, out_result);
        }
        if (actual_size > resume_from) {
            if (task->files.front().expected_bytes > 0 &&
                actual_size > task->files.front().expected_bytes) {
                result.set_accepted(false);
                result.set_error_message("existing partial bytes exceed expected byte count");
                result.set_failure_reason(
                    runanywhere::v1::DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES);
                result.set_resume_token(task->resume_token);
                return serialize_proto_to_buffer(result, out_result);
            }
            resume_from = actual_size;
        }
    }

    task->update_registry_on_completion = request.update_registry_on_completion();

    set_task_progress(
        task, request.resume() ? rav1::DOWNLOAD_STATE_RESUMING : rav1::DOWNLOAD_STATE_PENDING,
        rav1::DOWNLOAD_STAGE_DOWNLOADING, resume_from, request.plan().total_bytes(), 0,
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
    result.set_resume_token(task->resume_token);
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        *result.mutable_initial_progress() = task->progress;
    }

    // Persist the durable folder manifest BEFORE bytes flow so a process
    // death mid-download still leaves a restorable identity on disk: the
    // cold-launch / lookup-miss restore re-registers the entry as incomplete
    // and a pull/download by id resumes from the partial bytes. Best-effort —
    // a metadata write must never block the download itself.
    (void)rac::infra::model_manifest::persist(rac_get_model_registry(), task->model_id.c_str());

    start_proto_download_worker(task, resume_from);

    emit_progress(task);
    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_cancel_proto(const uint8_t* request_bytes, size_t request_size,
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
    int64_t preserved_bytes = 0;
    bool was_running = false;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        if (!task->running && task->progress.state() == rav1::DOWNLOAD_STATE_COMPLETED) {
            result.set_success(false);
            result.set_task_id(task->task_id);
            result.set_model_id(task->model_id);
            result.set_resume_token(task->resume_token);
            result.set_error_message("download task already completed");
            return serialize_proto_to_buffer(result, out_result);
        }
        task->cancel_requested.store(true);
        task->delete_partial_on_cancel = request.delete_partial_bytes();
        was_running = task->running;
        result.set_task_id(task->task_id);
        result.set_model_id(task->model_id);
        result.set_resume_token(task->resume_token);
    }

    bool worker_observed_stop = !was_running;
    if (was_running) {
        std::unique_lock<std::mutex> lock(task->mutex);
        // Honor the cv.wait_for return value. If the worker
        // doesn't drain within the timeout, the partial_bytes_*/deleted
        // fields below would be stale (initial 0 or a pre-cancel snapshot)
        // and the worker may still race ahead to delete the partial file
        // after we returned `partial_bytes_preserved=true`. Surface the
        // failure to the caller instead of lying about a clean cancel.
        worker_observed_stop =
            task->cv.wait_for(lock, std::chrono::seconds(2), [&task] { return !task->running; });
        if (worker_observed_stop) {
            deleted = task->last_deleted_bytes;
            preserved_bytes = task->last_partial_bytes;
        }
    } else {
        int64_t total_bytes = 0;
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            total_bytes = task->progress.total_bytes();
        }
        if (!task->files.empty()) {
            preserved_bytes = file_size_or_zero(task->files.front().destination_path);
            if (request.delete_partial_bytes()) {
                deleted = delete_partial_file(task->files.front().destination_path);
                preserved_bytes = 0;
            }
        }
        {
            std::lock_guard<std::mutex> lock(task->mutex);
            task->last_deleted_bytes = deleted;
            task->last_partial_bytes = preserved_bytes;
        }
        set_task_progress(task, rav1::DOWNLOAD_STATE_CANCELLED, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                          preserved_bytes, total_bytes, 0,
                          task->files.empty() ? "" : task->files.front().storage_key, "",
                          "download cancelled");
        emit_progress(task);
    }

    if (!worker_observed_stop) {
        result.set_success(false);
        result.set_was_running(true);
        result.set_partial_bytes_deleted(0);
        result.set_partial_bytes_preserved(false);
        result.set_error_message("cancel timed out waiting for worker to drain");
        return serialize_proto_to_buffer(result, out_result);
    }

    result.set_success(true);
    result.set_was_running(was_running);
    result.set_partial_bytes_deleted(deleted);
    result.set_partial_bytes_preserved(!request.delete_partial_bytes() && preserved_bytes > 0);
    return serialize_proto_to_buffer(result, out_result);
}

extern "C" rac_result_t rac_download_resume_proto(const uint8_t* request_bytes, size_t request_size,
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

    auto task = find_task(request.task_id(), request.model_id(), request.resume_token());
    if (!task) {
        result.set_accepted(false);
        result.set_error_message("download task not found");
        return serialize_proto_to_buffer(result, out_result);
    }
    if (rac_http_transport_is_registered() == RAC_FALSE) {
        result.set_accepted(false);
        result.set_error_message("no HTTP transport adapter registered");
        return serialize_proto_to_buffer(result, out_result);
    }

    int64_t resume_from = request.resume_from_bytes();
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        if (!request.resume_token().empty() && !task->resume_token.empty() &&
            request.resume_token() != task->resume_token) {
            result.set_accepted(false);
            result.set_error_message("resume token does not match task");
            return serialize_proto_to_buffer(result, out_result);
        }
        if (task->running) {
            result.set_accepted(false);
            result.set_error_message("download task is already running");
            return serialize_proto_to_buffer(result, out_result);
        }
    }

    if (resume_from <= 0 && !task->files.empty()) {
        resume_from = file_size_or_zero(task->files.front().destination_path);
    }
    if (task->files.empty()) {
        result.set_accepted(false);
        result.set_error_message("download task has no planned files");
        return serialize_proto_to_buffer(result, out_result);
    }
    int64_t actual_size = 0;
    std::string resume_error;
    if (!validate_resume_offset(task->files.front(), resume_from, request.validate_partial_bytes(),
                                &actual_size, &resume_error)) {
        result.set_accepted(false);
        result.set_task_id(task->task_id);
        result.set_model_id(task->model_id);
        result.set_resume_token(task->resume_token);
        result.set_error_message(resume_error);
        return serialize_proto_to_buffer(result, out_result);
    }
    if (!request.validate_partial_bytes() && actual_size > resume_from) {
        if (task->files.front().expected_bytes > 0 &&
            actual_size > task->files.front().expected_bytes) {
            result.set_accepted(false);
            result.set_task_id(task->task_id);
            result.set_model_id(task->model_id);
            result.set_resume_token(task->resume_token);
            result.set_error_message("existing partial bytes exceed expected byte count");
            result.set_failure_reason(
                runanywhere::v1::DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES);
            return serialize_proto_to_buffer(result, out_result);
        }
        resume_from = actual_size;
    }

    int64_t total_bytes = 0;
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        total_bytes = task->progress.total_bytes();
    }
    set_task_progress(task, rav1::DOWNLOAD_STATE_RESUMING, rav1::DOWNLOAD_STAGE_DOWNLOADING,
                      resume_from, total_bytes, 0, task->files.front().storage_key, "", "");
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        task->cancel_requested.store(false);
        task->delete_partial_on_cancel = false;
        task->last_deleted_bytes = 0;
        task->last_partial_bytes = resume_from;
        task->running = true;
    }

    result.set_accepted(true);
    result.set_task_id(task->task_id);
    result.set_model_id(task->model_id);
    result.set_resume_token(task->resume_token);
    {
        std::lock_guard<std::mutex> lock(task->mutex);
        *result.mutable_initial_progress() = task->progress;
    }

    start_proto_download_worker(task, resume_from);

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

// Erase proto_state().tasks entries whose worker has
// reached a terminal state. Without this hook the map grows for every
// successful, cancelled, or failed download — the SDK has no other way to
// release the per-task slot since rac_download_cancel_proto / _resume_proto
// must continue to resolve a task by id after its worker exits.
extern "C" rac_result_t rac_download_cleanup_terminal_tasks_proto(size_t* out_purged_count) {
    size_t purged = 0;
    {
        std::lock_guard<std::mutex> lock(proto_state().mutex);
        for (auto it = proto_state().tasks.begin(); it != proto_state().tasks.end();) {
            const auto& task = it->second;
            bool terminal = false;
            if (task) {
                std::lock_guard<std::mutex> tlock(task->mutex);
                const auto state = task->progress.state();
                terminal = !task->running && (state == rav1::DOWNLOAD_STATE_COMPLETED ||
                                              state == rav1::DOWNLOAD_STATE_FAILED ||
                                              state == rav1::DOWNLOAD_STATE_CANCELLED);
            } else {
                terminal = true;  // null shared_ptr — drop the slot
            }
            if (terminal) {
                it = proto_state().tasks.erase(it);
                ++purged;
            } else {
                ++it;
            }
        }
    }
    if (out_purged_count) {
        *out_purged_count = purged;
    }
    return RAC_SUCCESS;
}
#else
extern "C" rac_result_t
rac_download_set_progress_proto_callback(rac_download_proto_progress_callback_fn, void*) {
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

extern "C" rac_result_t rac_download_cleanup_terminal_tasks_proto(size_t* out_purged_count) {
    if (out_purged_count) {
        *out_purged_count = 0;
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}
#endif

// =============================================================================
// PUBLIC API — POST-EXTRACTION MODEL PATH FINDING
// =============================================================================

rac_result_t rac_find_model_path_after_extraction(const char* extracted_dir,
                                                  rac_archive_structure_t structure,
                                                  rac_inference_framework_t framework,
                                                  [[maybe_unused]] rac_model_format_t format,
                                                  char* out_path, size_t path_size) {
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

        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED: {
            // Directory-based archives (SmolVLM tarball, multi-file ONNX bundles)
            // contain several artifacts at the extraction root. Register the
            // folder so `rac_model_paths_resolve_artifact` can assign primary
            // vs mmproj roles. Picking the first .gguf here often selects
            // mmproj and breaks VLM load ("primary model not found").
            snprintf(out_path, path_size, "%s", extracted_dir);
            return RAC_SUCCESS;
        }

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
                                              [[maybe_unused]] rac_model_format_t format,
                                              char* out_path, size_t path_size,
                                              rac_bool_t* out_needs_extraction) {
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
