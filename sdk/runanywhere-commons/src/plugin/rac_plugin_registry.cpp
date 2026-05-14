/**
 * @file rac_plugin_registry.cpp
 * @brief Unified engine plugin registry — keyed by `rac_primitive_t`.
 *
 * GAP 02 Phase 7 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * v3.0.0: this is the SOLE plugin registration path. The legacy
 * `service_registry.cpp` / `rac_service_register_provider()` path was
 * removed in Phase C1. All engine backends (llamacpp, onnx, whispercpp,
 * whisperkit_coreml, metalrt, platform) register via
 * `rac_plugin_register(rac_plugin_entry_<name>())`, and commons consumers
 * route through `rac_plugin_route` + `vt->ops->create`.
 */

#include "plugin_registry_internal.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <ranges>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* LOG_CAT = "PluginRegistry";

/** One entry in the primitive table. */
struct Entry {
    std::string name;                   ///< copy of metadata.name for dedup lookup
    int32_t priority;                   ///< metadata.priority at register time
    const rac_engine_vtable_t* vtable;  ///< plugin-owned .rodata pointer
};

struct State {
    std::mutex mu;
    /** Primitive → descending-priority list of plugins. */
    std::unordered_map<rac_primitive_t, std::vector<Entry>> by_primitive;
    /** Name → vtable, used for dedup + unregister. */
    std::unordered_map<std::string, const rac_engine_vtable_t*> by_name;
    /** GAP 03: name → dlopen handle for plugins loaded via
     *  `rac_registry_load_plugin()`. Statically-registered plugins have no
     *  entry here. Populated by the loader, drained by `rac_plugin_unregister`. */
    std::unordered_map<std::string, void*> dl_handles;
    /** Manifest attached by an engine entry before the vtable is registered. */
    std::unordered_map<const rac_engine_vtable_t*, const rac_engine_manifest_t*>
        manifests_by_vtable;
    /** Accepted manifest by engine name. Values are plugin-owned .rodata. */
    std::unordered_map<std::string, const rac_engine_manifest_t*> manifests_by_name;
};

State& state() {
    // Meyers singleton; thread-safe initialization since C++11.
    static State s;
    return s;
}

/** Which primitive slots (in declaration order) the vtable fills. */
void each_served_primitive(const rac_engine_vtable_t* v,
                           const std::function<void(rac_primitive_t)>& fn) {
    if (v->llm_ops)
        fn(RAC_PRIMITIVE_GENERATE_TEXT);
    if (v->stt_ops)
        fn(RAC_PRIMITIVE_TRANSCRIBE);
    if (v->tts_ops)
        fn(RAC_PRIMITIVE_SYNTHESIZE);
    if (v->vad_ops)
        fn(RAC_PRIMITIVE_DETECT_VOICE);
    if (v->embedding_ops)
        fn(RAC_PRIMITIVE_EMBED);
    if (v->vlm_ops)
        fn(RAC_PRIMITIVE_VLM);
    if (v->diffusion_ops)
        fn(RAC_PRIMITIVE_DIFFUSION);
}

/** Insert `e` into `bucket` preserving descending priority. */
void insert_by_priority(std::vector<Entry>& bucket, Entry e) {
    auto pos = std::ranges::lower_bound(
        bucket, e, [](const Entry& a, const Entry& b) { return a.priority > b.priority; });
    bucket.insert(pos, std::move(e));
}

template <typename T>
bool arrays_equal(const T* lhs, size_t lhs_count, const T* rhs, size_t rhs_count) {
    if (lhs_count != rhs_count)
        return false;
    if (lhs_count == 0)
        return true;
    if (lhs == nullptr || rhs == nullptr)
        return false;
    for (size_t i = 0; i < lhs_count; ++i) {
        if (lhs[i] != rhs[i])
            return false;
    }
    return true;
}

bool strings_equal(const char* lhs, const char* rhs) {
    if (lhs == nullptr && rhs == nullptr)
        return true;
    if (lhs == nullptr || rhs == nullptr)
        return false;
    return std::strcmp(lhs, rhs) == 0;
}

bool manifest_declares_primitive(const rac_engine_manifest_t* manifest, rac_primitive_t primitive) {
    if (manifest == nullptr || manifest->primitives == nullptr)
        return false;
    for (size_t i = 0; i < manifest->primitives_count; ++i) {
        if (manifest->primitives[i] == primitive)
            return true;
    }
    return false;
}

bool valid_manifest_availability(rac_engine_availability_t availability) {
    return availability == RAC_ENGINE_AVAILABILITY_PUBLIC ||
           availability == RAC_ENGINE_AVAILABILITY_PRIVATE;
}

const rac_engine_manifest_t* attached_manifest_locked(const State& s,
                                                      const rac_engine_vtable_t* vtable) {
    auto it = s.manifests_by_vtable.find(vtable);
    return it == s.manifests_by_vtable.end() ? nullptr : it->second;
}

void detach_pending_manifest(const rac_engine_vtable_t* vtable) {
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    s.manifests_by_vtable.erase(vtable);
}

}  // namespace

// =============================================================================
// Public ABI
// =============================================================================

extern "C" {

const char* rac_engine_availability_name(rac_engine_availability_t availability) {
    switch (availability) {
        case RAC_ENGINE_AVAILABILITY_PUBLIC:
            return "public";
        case RAC_ENGINE_AVAILABILITY_PRIVATE:
            return "private";
        case RAC_ENGINE_AVAILABILITY_UNSPECIFIED:
            return "unspecified";
        default:
            return "unknown";
    }
}

rac_result_t rac_engine_manifest_validate_vtable(const rac_engine_manifest_t* manifest,
                                                 const rac_engine_vtable_t* vtable) {
    if (manifest == nullptr || vtable == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (manifest->name == nullptr || manifest->package_owner == nullptr ||
        manifest->package_name == nullptr || vtable->metadata.name == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!valid_manifest_availability(manifest->availability)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (vtable->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    if (!strings_equal(manifest->name, vtable->metadata.name) ||
        !strings_equal(manifest->display_name, vtable->metadata.display_name) ||
        !strings_equal(manifest->version, vtable->metadata.engine_version) ||
        manifest->priority != vtable->metadata.priority ||
        manifest->capability_flags != vtable->metadata.capability_flags) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if ((manifest->primitives_count > 0 && manifest->primitives == nullptr) ||
        (manifest->runtimes_count > 0 && manifest->runtimes == nullptr) ||
        (manifest->formats_count > 0 && manifest->formats == nullptr)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!arrays_equal(manifest->runtimes, manifest->runtimes_count, vtable->metadata.runtimes,
                      vtable->metadata.runtimes_count) ||
        !arrays_equal(manifest->formats, manifest->formats_count, vtable->metadata.formats,
                      vtable->metadata.formats_count)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    for (size_t i = 0; i < manifest->primitives_count; ++i) {
        rac_primitive_t primitive = manifest->primitives[i];
        if (primitive <= RAC_PRIMITIVE_UNSPECIFIED || primitive > RAC_PRIMITIVE_DIFFUSION ||
            rac_engine_vtable_slot(vtable, primitive) == nullptr) {
            return RAC_ERROR_INVALID_PARAMETER;
        }
    }

    for (int p = RAC_PRIMITIVE_GENERATE_TEXT; p <= RAC_PRIMITIVE_DIFFUSION; ++p) {
        rac_primitive_t primitive = static_cast<rac_primitive_t>(p);
        if (rac_engine_vtable_slot(vtable, primitive) != nullptr &&
            !manifest_declares_primitive(manifest, primitive)) {
            return RAC_ERROR_INVALID_PARAMETER;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_engine_manifest_attach_vtable(const rac_engine_manifest_t* manifest,
                                               const rac_engine_vtable_t* vtable) {
    rac_result_t rc = rac_engine_manifest_validate_vtable(manifest, vtable);
    if (rc != RAC_SUCCESS)
        return rc;

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    s.manifests_by_vtable[vtable] = manifest;
    return RAC_SUCCESS;
}

rac_result_t rac_engine_manifest_detach_vtable(const rac_engine_vtable_t* vtable) {
    if (vtable == nullptr)
        return RAC_ERROR_NULL_POINTER;

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    const rac_engine_manifest_t* manifest = nullptr;
    auto it = s.manifests_by_vtable.find(vtable);
    if (it != s.manifests_by_vtable.end()) {
        manifest = it->second;
        s.manifests_by_vtable.erase(it);
    }
    if (manifest != nullptr && vtable->metadata.name != nullptr) {
        auto accepted = s.manifests_by_name.find(vtable->metadata.name);
        if (accepted != s.manifests_by_name.end() && accepted->second == manifest) {
            s.manifests_by_name.erase(accepted);
        }
    }
    return RAC_SUCCESS;
}

const rac_engine_manifest_t* rac_engine_manifest_find(const char* name) {
    if (name == nullptr)
        return nullptr;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    auto it = s.manifests_by_name.find(name);
    return it == s.manifests_by_name.end() ? nullptr : it->second;
}

size_t rac_engine_manifest_count(void) {
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    return s.manifests_by_name.size();
}

rac_result_t rac_plugin_register(const rac_engine_vtable_t* vtable) {
    if (vtable == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: NULL vtable");
        return RAC_ERROR_NULL_POINTER;
    }
    if (vtable->metadata.name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: metadata.name is NULL");
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (vtable->metadata.abi_version != RAC_PLUGIN_API_VERSION) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: '%s' ABI mismatch (plugin=%u host=%u)",
                      vtable->metadata.name, vtable->metadata.abi_version, RAC_PLUGIN_API_VERSION);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    const rac_engine_manifest_t* manifest = nullptr;
    {
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        manifest = attached_manifest_locked(s, vtable);
    }
    if (manifest != nullptr) {
        rac_result_t manifest_rc = rac_engine_manifest_validate_vtable(manifest, vtable);
        if (manifest_rc != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: '%s' manifest validation failed (%d)",
                          vtable->metadata.name, (int)manifest_rc);
            detach_pending_manifest(vtable);
            return manifest_rc;
        }
    }

    if (vtable->capability_check != nullptr) {
        rac_result_t cap = vtable->capability_check();
        if (cap != RAC_SUCCESS) {
            RAC_LOG_DEBUG(LOG_CAT,
                          "rac_plugin_register: '%s' capability_check rejected (%d) — not loading",
                          vtable->metadata.name, (int)cap);
            // Return the registry-level code; capability_check's raw status
            // is visible in the log above for debugging.
            detach_pending_manifest(vtable);
            return RAC_ERROR_CAPABILITY_UNSUPPORTED;
        }
    }

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);

    std::string name(vtable->metadata.name);
    auto dup = s.by_name.find(name);
    const bool replacing_existing = dup != s.by_name.end();
    if (dup != s.by_name.end()) {
        // Duplicate by name: replace only if incoming priority >= existing.
        int32_t existing_prio = dup->second->metadata.priority;
        if (vtable->metadata.priority < existing_prio) {
            RAC_LOG_DEBUG(LOG_CAT, "rac_plugin_register: '%s' rejected (priority %d < existing %d)",
                          name.c_str(), (int)vtable->metadata.priority, (int)existing_prio);
            s.manifests_by_vtable.erase(vtable);
            return RAC_ERROR_PLUGIN_DUPLICATE;
        }
        // Evict the existing one from every primitive bucket.
        for (auto& kv : s.by_primitive) {
            auto& vec = kv.second;
            const auto removed =
                std::ranges::remove_if(vec, [&](const Entry& e) { return e.name == name; });
            vec.erase(removed.begin(), removed.end());
        }
    }

    s.by_name[name] = vtable;
    if (manifest != nullptr) {
        s.manifests_by_name[name] = manifest;
    } else if (replacing_existing) {
        s.manifests_by_name.erase(name);
    }

    each_served_primitive(vtable, [&](rac_primitive_t p) {
        Entry e{.name = name, .priority = vtable->metadata.priority, .vtable = vtable};
        insert_by_priority(s.by_primitive[p], std::move(e));
    });

    RAC_LOG_DEBUG(LOG_CAT, "rac_plugin_register: '%s' ok", name.c_str());
    return RAC_SUCCESS;
}

rac_result_t rac_plugin_unregister(const char* name) {
    if (name == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);

    std::string key(name);
    auto it = s.by_name.find(key);
    if (it == s.by_name.end()) {
        return RAC_ERROR_NOT_FOUND;
    }
    const rac_engine_vtable_t* v = it->second;
    if (v->on_unload) {
        v->on_unload();
    }

    s.by_name.erase(it);
    s.manifests_by_name.erase(key);
    s.manifests_by_vtable.erase(v);
    for (auto& kv : s.by_primitive) {
        auto& vec = kv.second;
        const auto removed =
            std::ranges::remove_if(vec, [&](const Entry& e) { return e.name == key; });
        vec.erase(removed.begin(), removed.end());
    }
    RAC_LOG_DEBUG(LOG_CAT, "rac_plugin_unregister: '%s' ok", name);
    return RAC_SUCCESS;
}

const rac_engine_vtable_t* rac_plugin_find(rac_primitive_t primitive) {
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    auto it = s.by_primitive.find(primitive);
    if (it == s.by_primitive.end() || it->second.empty()) {
        return nullptr;
    }
    // Descending priority — first is best.
    return it->second.front().vtable;
}

rac_result_t rac_plugin_list(rac_primitive_t primitive, const rac_engine_vtable_t** out_plugins,
                             size_t max, size_t* out_count) {
    if (out_plugins == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_count = 0;

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    auto it = s.by_primitive.find(primitive);
    if (it == s.by_primitive.end()) {
        return RAC_SUCCESS;
    }
    size_t n = std::min(it->second.size(), max);
    for (size_t i = 0; i < n; ++i) {
        out_plugins[i] = it->second[i].vtable;
    }
    *out_count = n;
    return RAC_SUCCESS;
}

size_t rac_plugin_count(void) {
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    return s.by_name.size();
}

// =============================================================================
// GAP 03 internal: dl_handle bookkeeping (plugin_registry_internal.h)
// =============================================================================

void rac_plugin_registry_set_dl_handle(const char* name, void* handle) {
    if (name == nullptr)
        return;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    if (handle == nullptr) {
        s.dl_handles.erase(name);
    } else {
        s.dl_handles[name] = handle;
    }
}

void* rac_plugin_registry_take_dl_handle(const char* name) {
    if (name == nullptr)
        return nullptr;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    auto it = s.dl_handles.find(name);
    if (it == s.dl_handles.end())
        return nullptr;
    void* h = it->second;
    s.dl_handles.erase(it);
    return h;
}

size_t rac_plugin_registry_snapshot_names(const char*** out_names) {
    if (out_names == nullptr)
        return 0;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    size_t n = s.by_name.size();
    if (n == 0) {
        *out_names = nullptr;
        return 0;
    }
    auto* arr = static_cast<const char**>(std::malloc(n * sizeof(const char*)));
    if (arr == nullptr) {
        *out_names = nullptr;
        return 0;
    }
    size_t i = 0;
    for (auto& kv : s.by_name) {
        arr[i++] = strdup(kv.first.c_str());
    }
    *out_names = arr;
    return n;
}

// =============================================================================
// Helpers from rac_primitive.h / rac_engine_vtable.h
// =============================================================================

const char* rac_primitive_name(rac_primitive_t p) {
    switch (p) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            return "generate_text";
        case RAC_PRIMITIVE_TRANSCRIBE:
            return "transcribe";
        case RAC_PRIMITIVE_SYNTHESIZE:
            return "synthesize";
        case RAC_PRIMITIVE_DETECT_VOICE:
            return "detect_voice";
        case RAC_PRIMITIVE_EMBED:
            return "embed";
        case RAC_PRIMITIVE_RERANK:
            return "reserved_6";
        case RAC_PRIMITIVE_VLM:
            return "vlm";
        case RAC_PRIMITIVE_DIFFUSION:
            return "diffusion";
        case RAC_PRIMITIVE_UNSPECIFIED:
            return "unspecified";
        default:
            return "unknown";
    }
}

const char* rac_runtime_name(rac_runtime_id_t r) {
    switch (r) {
        case RAC_RUNTIME_CPU:
            return "cpu";
        case RAC_RUNTIME_METAL:
            return "metal";
        case RAC_RUNTIME_COREML:
            return "coreml";
        case RAC_RUNTIME_ANE:
            return "ane";
        case RAC_RUNTIME_CUDA:
            return "cuda";
        case RAC_RUNTIME_VULKAN:
            return "vulkan";
        case RAC_RUNTIME_OPENCL:
            return "opencl";
        case RAC_RUNTIME_HIPBLAS:
            return "hipblas";
        case RAC_RUNTIME_QNN:
            return "qnn";
        case RAC_RUNTIME_NNAPI:
            return "nnapi";
        case RAC_RUNTIME_WEBGPU:
            return "webgpu";
        case RAC_RUNTIME_WASM_SIMD:
            return "wasm_simd";
        case RAC_RUNTIME_ONNXRT:
            return "onnxrt";
        case RAC_RUNTIME_UNSPECIFIED:
            return "unspecified";
        default:
            return "unknown";
    }
}

const void* rac_engine_vtable_slot(const rac_engine_vtable_t* vt, rac_primitive_t primitive) {
    if (vt == nullptr)
        return nullptr;
    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            return vt->llm_ops;
        case RAC_PRIMITIVE_TRANSCRIBE:
            return vt->stt_ops;
        case RAC_PRIMITIVE_SYNTHESIZE:
            return vt->tts_ops;
        case RAC_PRIMITIVE_DETECT_VOICE:
            return vt->vad_ops;
        case RAC_PRIMITIVE_EMBED:
            return vt->embedding_ops;
        case RAC_PRIMITIVE_RERANK:
            return nullptr;
        case RAC_PRIMITIVE_VLM:
            return vt->vlm_ops;
        case RAC_PRIMITIVE_DIFFUSION:
            return vt->diffusion_ops;
        default:
            return nullptr;
    }
}

// =============================================================================
// Legacy ABI shim — rac_service_register_provider (B-RN-Genie-002)
// =============================================================================
//
// The unified plugin registry above replaces per-service provider
// registration. However, older binaries (notably some Genie .so builds
// shipped with the React Native and Flutter examples) still reference
// the symbol `rac_service_register_provider`. Without this symbol they
// fail to dlopen with "undefined reference" and the entire backend goes
// dark — even features that don't actually need Genie.
//
// To keep those binaries loadable we provide a no-op shim that simply
// returns success. New code must register engines via
// rac_plugin_register(); this shim only exists so dlopen of a stale
// librac_backend_genie.so continues to resolve.
rac_result_t rac_service_register_provider(int /*service_type*/, void* /*ops*/,
                                           void* /*user_data*/) {
    RAC_LOG_WARNING(LOG_CAT,
                    "rac_service_register_provider() is a deprecated shim — "
                    "unified plugin registry has replaced per-service "
                    "registration; caller should migrate to rac_plugin_register().");
    return RAC_SUCCESS;
}

// Symmetric unregister shim. Stale Genie .so files emitted before the
// unified plugin registry land call this on backend teardown; without
// the symbol, dlopen fails outright with "cannot locate symbol
// rac_service_unregister_provider" and the entire Genie engine is
// skipped on Android — masking unrelated logs in every example app.
// New code must use rac_plugin_unregister().
rac_result_t rac_service_unregister_provider(int /*service_type*/, void* /*ops*/) {
    RAC_LOG_WARNING(LOG_CAT,
                    "rac_service_unregister_provider() is a deprecated shim — "
                    "unified plugin registry has replaced per-service "
                    "registration; caller should migrate to rac_plugin_unregister().");
    return RAC_SUCCESS;
}

}  // extern "C"
