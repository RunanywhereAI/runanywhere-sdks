/**
 * @file qhexrt_session.cpp
 * @brief Process-wide QHexRT runtime + session lifecycle (see qhexrt_session.h).
 *
 * The path handed to session_open() is whatever the commons resolver produced
 * for the model. Because QHexRT is a directory-bundle framework, that is the
 * bundle directory (not a file); a published bundle is laid out with a per-arch
 * subdirectory holding `<model>.json` plus the `.bin` graphs. session_open()
 * therefore selects the manifest in the subdirectory matching the device's arch
 * (v75+), falling back to a flat layout, and accepts a direct manifest path.
 */

#include "qhexrt_session.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <dlfcn.h>

#include <cstdlib>
#endif

#include "qhexrt_bundle_policy.h"

#include "rac/core/rac_logger.h"

namespace fs = std::filesystem;

namespace qhexrt_engine {
namespace {

const char* LOG_CAT = "QHexRT";

std::mutex g_rt_mutex;
qhx_runtime* g_rt = nullptr;
std::size_t g_rt_refs = 0;

#if defined(__ANDROID__)
const char* kAdspLibraryPathEnv = "ADSP_LIBRARY_PATH";
const char* kQhexrtSkelDirEnv = "RUNANYWHERE_QHEXRT_SKEL_DIR";

bool contains_zip_separator(const std::string& path) {
    return path.find("!/") != std::string::npos;
}

bool directory_contains_qnn_skel(const std::string& path) {
    if (path.empty() || contains_zip_separator(path)) {
        return false;
    }
    std::error_code ec;
    if (!fs::is_directory(path, ec)) {
        return false;
    }
    static const char* kSkels[] = {
        "libQnnHtpV75Skel.so",
        "libQnnHtpV79Skel.so",
        "libQnnHtpV81Skel.so",
    };
    for (const char* skel : kSkels) {
        if (fs::is_regular_file(fs::path(path) / skel, ec)) {
            return true;
        }
    }
    return false;
}

bool append_path(std::vector<std::string>& paths, const std::string& path, bool require_skel) {
    if (path.empty() || contains_zip_separator(path)) {
        return false;
    }
    if (require_skel && !directory_contains_qnn_skel(path)) {
        return false;
    }
    for (const std::string& existing : paths) {
        if (existing == path) {
            return true;
        }
    }
    paths.push_back(path);
    return true;
}

void append_existing_adsp_paths(std::vector<std::string>& paths, const char* existing) {
    if (existing == nullptr || existing[0] == '\0') {
        return;
    }
    std::string value(existing);
    size_t start = 0;
    while (start <= value.size()) {
        const size_t end = value.find(';', start);
        const std::string segment =
            value.substr(start, end == std::string::npos ? std::string::npos : end - start);
        append_path(paths, segment, false);
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
}

// QNN's HTP stub dlopens libcdsprpc.so and the per-arch DSP skel
// (for example, libQnnHtpV75/V79/V81Skel.so) via ADSP_LIBRARY_PATH; this must be set before
// the first qhx_runtime_create in every host (Kotlin/Flutter/RN). Modern Android
// packaging can load JNI libraries from base.apk!/..., which is valid for the
// app linker but not for FastRPC's DSP file loader. Prefer a real skel directory
// supplied by the SDK and only fall back to dladdr() when it points at a real
// extracted native library directory.
void configure_adsp_library_path() {
    std::vector<std::string> paths;
    const char* skel_dir = std::getenv(kQhexrtSkelDirEnv);
    if (skel_dir != nullptr && skel_dir[0] != '\0' && !append_path(paths, skel_dir, true)) {
        RAC_LOG_WARNING(LOG_CAT, "Ignoring invalid QHexRT skel directory: %s", skel_dir);
    }

    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(&configure_adsp_library_path), &info) != 0 &&
        info.dli_fname != nullptr) {
        std::string lib_path(info.dli_fname);
        auto slash = lib_path.find_last_of('/');
        if (slash != std::string::npos) {
            append_path(paths, lib_path.substr(0, slash), true);
        }
    }

    append_existing_adsp_paths(paths, std::getenv(kAdspLibraryPathEnv));
    append_path(paths, "/vendor/dsp/cdsp", false);
    append_path(paths, "/vendor/lib/rfsa/adsp", false);

    std::string path;
    for (const std::string& segment : paths) {
        if (!path.empty()) {
            path += ";";
        }
        path += segment;
    }
    if (path.empty()) {
        return;
    }
    setenv("ADSP_LIBRARY_PATH", path.c_str(), 1);
    RAC_LOG_INFO(LOG_CAT, "ADSP_LIBRARY_PATH set to %s", path.c_str());
}

// Append a single skel directory into the live ADSP_LIBRARY_PATH. Used when the
// runtime is already created and configure_adsp_library_path() has already run
// once (its std::call_once cannot fire again): a later skel-dir change would
// otherwise be silently ignored until a process restart, so a re-register after
// a first failed one could never pick up a corrected directory. Appends (rather
// than replaces) so the paths the one-time setup discovered — dladdr, existing
// value, /vendor/... — stay intact; skips no-op duplicates.
void append_skel_dir_to_live_adsp_path(const char* dir) {
    if (dir == nullptr || dir[0] == '\0' || !directory_contains_qnn_skel(dir)) {
        return;
    }
    std::vector<std::string> paths;
    append_existing_adsp_paths(paths, std::getenv(kAdspLibraryPathEnv));
    const size_t before = paths.size();
    if (!append_path(paths, dir, false) || paths.size() == before) {
        return;  // already present — nothing to re-apply
    }
    std::string value;
    for (const std::string& segment : paths) {
        if (!value.empty()) {
            value += ";";
        }
        value += segment;
    }
    setenv(kAdspLibraryPathEnv, value.c_str(), 1);
    RAC_LOG_INFO(LOG_CAT, "ADSP_LIBRARY_PATH updated to %s", value.c_str());
}

extern "C" __attribute__((visibility("default"))) void
rac_qhexrt_set_skel_directory(const char* path) {
    if (path == nullptr || path[0] == '\0') {
        unsetenv(kQhexrtSkelDirEnv);
        return;
    }
    setenv(kQhexrtSkelDirEnv, path, 1);
    // If the runtime is already up, the one-time ADSP setup has run and cannot
    // re-run; fold the new skel dir into the live env so a re-register after a
    // failed one works without a process restart.
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt != nullptr) {
        append_skel_dir_to_live_adsp_path(path);
    }
}
#endif

qhx_runtime* runtime_acquire() {
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt == nullptr) {
#if defined(__ANDROID__)
        static std::once_flag adsp_once;
        std::call_once(adsp_once, configure_adsp_library_path);
#endif
        g_rt = qhx_runtime_create(nullptr, nullptr);  // default libQnnHtp.so / libQnnSystem.so
        if (g_rt == nullptr) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_runtime_create failed (QNN libs unavailable?)");
            return nullptr;
        }
        char arch[32] = {0};
        qhx_runtime_device(g_rt, arch, sizeof(arch), nullptr, nullptr);
        RAC_LOG_INFO(LOG_CAT, "QHexRT runtime up (arch=%s, %s)", arch, qhx_version());
    }
    ++g_rt_refs;
    return g_rt;
}

void runtime_release() {
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt_refs == 0) {
        return;
    }
    if (--g_rt_refs == 0) {
        qhx_runtime_free(g_rt);
        g_rt = nullptr;
    }
}

bool ends_with_ci(const std::string& s, const char* suffix) {
    size_t n = std::strlen(suffix);
    if (s.size() < n) {
        return false;
    }
    for (size_t i = 0; i < n; ++i) {
        char a = s[s.size() - n + i];
        if (a >= 'A' && a <= 'Z')
            a = static_cast<char>(a + ('a' - 'A'));
        if (a != suffix[i]) {
            return false;
        }
    }
    return true;
}

// Aux JSON files that live next to a manifest but are not the manifest
// itself. Single source of truth: qhexrt_bundle_policy.h, shared with the
// commons-side bundle resolution so remote and on-disk selection agree.
bool is_aux_json(const std::string& name) {
    return qhexrt_is_aux_json(name.c_str()) != 0;
}

// A QHexRT manifest carries a "plan"/"schema_version"/"dsp_arch" key. Sniff the
// head of the file to disambiguate it from arbitrary JSON sidecars.
bool looks_like_manifest(const fs::path& file) {
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        return false;
    }
    char buf[8192];
    in.read(buf, sizeof(buf) - 1);
    buf[in.gcount() > 0 ? static_cast<size_t>(in.gcount()) : 0] = '\0';
    std::string head(buf);
    return head.find("schema_version") != std::string::npos ||
           head.find("\"plan\"") != std::string::npos || head.find("dsp_arch") != std::string::npos;
}

// Returns the manifest .json inside `dir`, or empty. Candidate order matches
// the remote bundle policy: alphabetically first after excluding aux files.
std::string find_manifest_in_dir(const fs::path& dir) {
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) {
        return {};
    }
    std::vector<fs::path> candidates;
    for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
         it != end && !ec; it.increment(ec)) {
        if (!it->is_regular_file(ec)) {
            continue;
        }
        const fs::path& p = it->path();
        std::string name = p.filename().generic_string();
        if (!ends_with_ci(name, ".json") || is_aux_json(name)) {
            continue;
        }
        candidates.push_back(p);
    }
    std::sort(candidates.begin(), candidates.end());
    for (const fs::path& candidate : candidates) {
        if (looks_like_manifest(candidate)) {
            return candidate.generic_string();
        }
    }
    if (candidates.size() == 1) {
        return candidates.front().generic_string();
    }
    return {};
}

// Extract the manifest's "dsp_arch" value (e.g. "v79") from the head of the
// file, or empty if absent/unparsable. Lightweight sniff in the same spirit as
// looks_like_manifest — avoids pulling a JSON parser into the resolver.
std::string manifest_dsp_arch(const fs::path& file) {
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        return {};
    }
    char buf[8192];
    in.read(buf, sizeof(buf) - 1);
    buf[in.gcount() > 0 ? static_cast<size_t>(in.gcount()) : 0] = '\0';
    std::string head(buf);
    size_t key = head.find("dsp_arch");
    if (key == std::string::npos) {
        return {};
    }
    size_t colon = head.find(':', key);
    if (colon == std::string::npos) {
        return {};
    }
    size_t open = head.find('"', colon);
    if (open == std::string::npos) {
        return {};
    }
    size_t close = head.find('"', open + 1);
    if (close == std::string::npos) {
        return {};
    }
    return head.substr(open + 1, close - open - 1);
}

// Resolve the model reference (a bundle dir or a manifest file) to a manifest
// path, preferring the subdirectory matching `arch` (e.g. "v79").
std::string resolve_manifest(const char* path, const char* arch) {
    std::error_code ec;
    fs::path p(path);
    if (fs::is_regular_file(p, ec)) {
        // A real manifest .json was passed directly — use it.
        std::string name = p.filename().generic_string();
        if (ends_with_ci(name, ".json") && !is_aux_json(name) && looks_like_manifest(p)) {
            return p.generic_string();
        }
        // Otherwise commons handed us a non-manifest bundle file. This happens for
        // a directory-based framework whose model carries multi_file descriptors:
        // rac_model_paths_resolve_artifact scans the folder and returns the first
        // QNN_CONTEXT `.bin` (e.g. the fp16 embedding blob) as the primary path,
        // which synthesize_artifact_resolution_from_descriptors then cannot
        // override. Recover by resolving the manifest from the file's own bundle
        // directory (the layout below handles the arch-subdir and flat cases).
        p = p.parent_path();
    }
    if (!fs::is_directory(p, ec)) {
        return {};
    }
    if (arch != nullptr && arch[0] != '\0') {
        std::string m = find_manifest_in_dir(p / arch);
        if (!m.empty()) {
            return m;
        }
    }
    // Flat-layout fallback: no per-arch subdirectory. Unlike the arch-subdir
    // path (correct by construction), a flat bundle may target a different DSP
    // (e.g. a v81 bundle on a v79 device). Reject an arch mismatch here with a
    // clear message instead of trusting qhx_model_load to fail deep in QNN with
    // an opaque error (A21).
    std::string flat = find_manifest_in_dir(p);
    if (flat.empty() || arch == nullptr || arch[0] == '\0') {
        return flat;
    }
    std::string manifest_arch = manifest_dsp_arch(flat);
    if (!manifest_arch.empty() && manifest_arch != arch) {
        RAC_LOG_ERROR(LOG_CAT,
                      "QHexRT manifest dsp_arch '%s' does not match device arch '%s': %s",
                      manifest_arch.c_str(), arch, flat.c_str());
        return {};
    }
    return flat;
}

}  // namespace

Session* session_open(const char* manifest_path) {
    if (manifest_path == nullptr || manifest_path[0] == '\0') {
        return nullptr;
    }
    qhx_runtime* rt = runtime_acquire();
    if (rt == nullptr) {
        return nullptr;
    }

    char arch[32] = {0};
    qhx_runtime_device(rt, arch, sizeof(arch), nullptr, nullptr);
    std::string manifest = resolve_manifest(manifest_path, arch);
    if (manifest.empty()) {
        RAC_LOG_ERROR(LOG_CAT, "no QHexRT manifest found under: %s (arch=%s)", manifest_path, arch);
        runtime_release();
        return nullptr;
    }

    Session* s = new (std::nothrow) Session();
    if (s == nullptr) {
        runtime_release();
        return nullptr;
    }
    s->model_ref = manifest_path;
    s->manifest_path = manifest;
    s->scratch_dir = fs::path(manifest).parent_path().generic_string();
    // artifacts_dir = NULL -> manifest-relative paths resolve against its own dir.
    s->model = qhx_model_load(rt, manifest.c_str(), nullptr);
    if (s->model == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "qhx_model_load failed: %s", manifest.c_str());
        delete s;
        runtime_release();
        return nullptr;
    }
    s->sess = qhx_session_create(s->model);
    if (s->sess == nullptr) {
        qhx_model_free(s->model);
        delete s;
        runtime_release();
        return nullptr;
    }
    return s;
}

void session_close(Session* s) {
    if (s == nullptr) {
        return;
    }
    {
        // Wait for an in-flight generate/reset/copy operation before releasing
        // session-owned buffers. Lifecycle ownership prevents new operations
        // once destroy begins; this mutex closes the remaining execution race.
        std::lock_guard<std::mutex> operation_lock(s->operation_mutex);
        if (s->sess != nullptr) {
            qhx_session_free(s->sess);
            s->sess = nullptr;
        }
        if (s->model != nullptr) {
            qhx_model_free(s->model);
            s->model = nullptr;
        }
    }
    delete s;
    runtime_release();
}

}  // namespace qhexrt_engine
