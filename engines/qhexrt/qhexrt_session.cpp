/**
 * @file qhexrt_session.cpp
 * @brief Process-wide QHexRT runtime + session lifecycle (see qhexrt_session.h).
 *
 * The path handed to session_open() is whatever the commons resolver produced
 * for the model. Because QHexRT is a directory-bundle framework, that is the
 * bundle directory (not a file); a published bundle is laid out with a per-arch
 * subdirectory holding `<model>.json` plus the `.bin` graphs. session_open()
 * therefore selects the manifest in the subdirectory matching the device's arch
 * (v79/v81), falling back to a flat layout, and accepts a direct manifest path.
 */

#include "qhexrt_session.h"

#include <cstddef>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

namespace fs = std::filesystem;

namespace qhexrt_engine {
namespace {

const char* LOG_CAT = "QHexRT";

std::mutex g_rt_mutex;
qhx_runtime* g_rt = nullptr;
std::size_t g_rt_refs = 0;

qhx_runtime* runtime_acquire() {
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt == nullptr) {
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
        if (a >= 'A' && a <= 'Z') a = static_cast<char>(a + ('a' - 'A'));
        if (a != suffix[i]) {
            return false;
        }
    }
    return true;
}

// Aux JSON files that live next to a manifest but are not the manifest itself.
bool is_aux_json(const std::string& name) {
    return name == "tokenizer.json" || name == "tokenizer_config.json" ||
           name == "config.json" || name == "generation_config.json" ||
           name == "preprocessor_config.json";
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
           head.find("\"plan\"") != std::string::npos ||
           head.find("dsp_arch") != std::string::npos;
}

// Returns the manifest .json inside `dir`, or empty. Prefers a file that sniffs
// as a QHexRT manifest; otherwise the single non-aux .json.
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
        if (looks_like_manifest(p)) {
            return p.generic_string();
        }
        candidates.push_back(p);
    }
    if (candidates.size() == 1) {
        return candidates.front().generic_string();
    }
    return {};
}

// Extract the manifest's `model.tokenizer_pre` value with a minimal scan (the
// engine deliberately avoids a JSON dependency). Returns "" if absent. The
// manifest is a small, well-formed RunAnywhere file, so a quoted-value lookup
// is sufficient and robust here.
std::string read_tokenizer_pre(const fs::path& manifest) {
    std::ifstream in(manifest, std::ios::binary);
    if (!in) {
        return {};
    }
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    const std::string key = "\"tokenizer_pre\"";
    size_t k = content.find(key);
    if (k == std::string::npos) {
        return {};
    }
    size_t colon = content.find(':', k + key.size());
    if (colon == std::string::npos) {
        return {};
    }
    size_t q1 = content.find('"', colon + 1);
    if (q1 == std::string::npos) {
        return {};
    }
    size_t q2 = content.find('"', q1 + 1);
    if (q2 == std::string::npos) {
        return {};
    }
    return content.substr(q1 + 1, q2 - q1 - 1);
}

// Resolve the model reference (a bundle dir or a manifest file) to a manifest
// path, preferring the subdirectory matching `arch` (e.g. "v79").
std::string resolve_manifest(const char* path, const char* arch) {
    std::error_code ec;
    fs::path p(path);
    if (fs::is_regular_file(p, ec)) {
        return p.generic_string();  // a manifest file was passed directly
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
    return find_manifest_in_dir(p);  // flat-layout fallback
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
    s->tokenizer_pre = read_tokenizer_pre(manifest);
    RAC_LOG_INFO(LOG_CAT, "QHexRT session ready (tokenizer_pre=%s)",
                 s->tokenizer_pre.empty() ? "<none>" : s->tokenizer_pre.c_str());
    return s;
}

void session_close(Session* s) {
    if (s == nullptr) {
        return;
    }
    if (s->sess != nullptr) {
        qhx_session_free(s->sess);
    }
    if (s->model != nullptr) {
        qhx_model_free(s->model);
    }
    delete s;
    runtime_release();
}

}  // namespace qhexrt_engine
