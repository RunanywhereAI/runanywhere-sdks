/**
 * @file rac_plugin_registry.cpp
 * @brief Unified engine plugin registry — keyed by `rac_primitive_t`.
 *
 * GAP 02 Phase 7 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Coexists with the pre-existing `service_registry.cpp` without any behavior
 * change to legacy callers: legacy `rac_service_register_provider()` callers
 * continue to work; new plugins registered here go into a parallel table.
 * Tests in GAP 02 Phase 10 verify the two paths compose cleanly.
 */

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"
#include "plugin_registry_internal.h"

namespace {

constexpr const char* LOG_CAT = "PluginRegistry";

/** One entry in the primitive table. */
struct Entry {
    std::string               name;      ///< copy of metadata.name for dedup lookup
    int32_t                   priority;  ///< metadata.priority at register time
    const rac_engine_vtable_t* vtable;   ///< plugin-owned .rodata pointer
};

struct State {
    std::mutex                                          mu;
    /** Primitive → descending-priority list of plugins. */
    std::unordered_map<rac_primitive_t, std::vector<Entry>> by_primitive;
    /** Name → vtable, used for dedup + unregister. */
    std::unordered_map<std::string, const rac_engine_vtable_t*> by_name;
    /** GAP 03: name → dlopen handle for plugins loaded via
     *  `rac_registry_load_plugin()`. Statically-registered plugins have no
     *  entry here. Populated by the loader, drained by `rac_plugin_unregister`. */
    std::unordered_map<std::string, void*> dl_handles;
};

State& state() {
    // Meyers singleton; thread-safe initialization since C++11.
    static State s;
    return s;
}

/** Which primitive slots (in declaration order) the vtable fills. */
void each_served_primitive(const rac_engine_vtable_t* v,
                           const std::function<void(rac_primitive_t)>& fn) {
    if (v->llm_ops)       fn(RAC_PRIMITIVE_GENERATE_TEXT);
    if (v->stt_ops)       fn(RAC_PRIMITIVE_TRANSCRIBE);
    if (v->tts_ops)       fn(RAC_PRIMITIVE_SYNTHESIZE);
    if (v->vad_ops)       fn(RAC_PRIMITIVE_DETECT_VOICE);
    if (v->embedding_ops) fn(RAC_PRIMITIVE_EMBED);
    if (v->rerank_ops)    fn(RAC_PRIMITIVE_RERANK);
    if (v->vlm_ops)       fn(RAC_PRIMITIVE_VLM);
    if (v->diffusion_ops) fn(RAC_PRIMITIVE_DIFFUSION);
}

/** Insert `e` into `bucket` preserving descending priority. */
void insert_by_priority(std::vector<Entry>& bucket, Entry e) {
    auto pos = std::lower_bound(bucket.begin(), bucket.end(), e,
                                [](const Entry& a, const Entry& b) {
                                    return a.priority > b.priority;
                                });
    bucket.insert(pos, std::move(e));
}

}  // namespace

// =============================================================================
// Public ABI
// =============================================================================

extern "C" {

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
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_plugin_register: '%s' ABI mismatch (plugin=%u host=%u)",
                      vtable->metadata.name,
                      vtable->metadata.abi_version,
                      RAC_PLUGIN_API_VERSION);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    if (vtable->capability_check != nullptr) {
        rac_result_t cap = vtable->capability_check();
        if (cap != RAC_SUCCESS) {
            RAC_LOG_DEBUG(LOG_CAT,
                          "rac_plugin_register: '%s' capability_check rejected (%d) — not loading",
                          vtable->metadata.name,
                          (int)cap);
            // Return the registry-level code; capability_check's raw status
            // is visible in the log above for debugging.
            return RAC_ERROR_CAPABILITY_UNSUPPORTED;
        }
    }

    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);

    std::string name(vtable->metadata.name);
    auto dup = s.by_name.find(name);
    if (dup != s.by_name.end()) {
        // Duplicate by name: replace only if incoming priority >= existing.
        int32_t existing_prio = dup->second->metadata.priority;
        if (vtable->metadata.priority < existing_prio) {
            RAC_LOG_DEBUG(LOG_CAT,
                          "rac_plugin_register: '%s' rejected (priority %d < existing %d)",
                          name.c_str(),
                          (int)vtable->metadata.priority,
                          (int)existing_prio);
            return RAC_ERROR_PLUGIN_DUPLICATE;
        }
        // Evict the existing one from every primitive bucket.
        for (auto& kv : s.by_primitive) {
            auto& vec = kv.second;
            vec.erase(std::remove_if(vec.begin(), vec.end(),
                                     [&](const Entry& e) { return e.name == name; }),
                      vec.end());
        }
    }

    s.by_name[name] = vtable;

    each_served_primitive(vtable, [&](rac_primitive_t p) {
        Entry e{name, vtable->metadata.priority, vtable};
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
    for (auto& kv : s.by_primitive) {
        auto& vec = kv.second;
        vec.erase(std::remove_if(vec.begin(), vec.end(),
                                 [&](const Entry& e) { return e.name == key; }),
                  vec.end());
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

rac_result_t rac_plugin_list(rac_primitive_t primitive,
                             const rac_engine_vtable_t** out_plugins,
                             size_t max,
                             size_t* out_count) {
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
    if (name == nullptr) return;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    if (handle == nullptr) {
        s.dl_handles.erase(name);
    } else {
        s.dl_handles[name] = handle;
    }
}

void* rac_plugin_registry_take_dl_handle(const char* name) {
    if (name == nullptr) return nullptr;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    auto it = s.dl_handles.find(name);
    if (it == s.dl_handles.end()) return nullptr;
    void* h = it->second;
    s.dl_handles.erase(it);
    return h;
}

size_t rac_plugin_registry_snapshot_names(const char*** out_names) {
    if (out_names == nullptr) return 0;
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
        case RAC_PRIMITIVE_GENERATE_TEXT: return "generate_text";
        case RAC_PRIMITIVE_TRANSCRIBE:    return "transcribe";
        case RAC_PRIMITIVE_SYNTHESIZE:    return "synthesize";
        case RAC_PRIMITIVE_DETECT_VOICE:  return "detect_voice";
        case RAC_PRIMITIVE_EMBED:         return "embed";
        case RAC_PRIMITIVE_RERANK:        return "rerank";
        case RAC_PRIMITIVE_VLM:           return "vlm";
        case RAC_PRIMITIVE_DIFFUSION:     return "diffusion";
        case RAC_PRIMITIVE_UNSPECIFIED:   return "unspecified";
        default:                          return "unknown";
    }
}

const char* rac_runtime_name(rac_runtime_id_t r) {
    switch (r) {
        case RAC_RUNTIME_CPU:         return "cpu";
        case RAC_RUNTIME_METAL:       return "metal";
        case RAC_RUNTIME_COREML:      return "coreml";
        case RAC_RUNTIME_ANE:         return "ane";
        case RAC_RUNTIME_CUDA:        return "cuda";
        case RAC_RUNTIME_VULKAN:      return "vulkan";
        case RAC_RUNTIME_OPENCL:      return "opencl";
        case RAC_RUNTIME_HIPBLAS:     return "hipblas";
        case RAC_RUNTIME_QNN:         return "qnn";
        case RAC_RUNTIME_NNAPI:       return "nnapi";
        case RAC_RUNTIME_WEBGPU:      return "webgpu";
        case RAC_RUNTIME_WASM_SIMD:   return "wasm_simd";
        case RAC_RUNTIME_UNSPECIFIED: return "unspecified";
        default:                      return "unknown";
    }
}

const void* rac_engine_vtable_slot(const rac_engine_vtable_t* vt,
                                   rac_primitive_t primitive) {
    if (vt == nullptr) return nullptr;
    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT: return vt->llm_ops;
        case RAC_PRIMITIVE_TRANSCRIBE:    return vt->stt_ops;
        case RAC_PRIMITIVE_SYNTHESIZE:    return vt->tts_ops;
        case RAC_PRIMITIVE_DETECT_VOICE:  return vt->vad_ops;
        case RAC_PRIMITIVE_EMBED:         return vt->embedding_ops;
        case RAC_PRIMITIVE_RERANK:        return vt->rerank_ops;
        case RAC_PRIMITIVE_VLM:           return vt->vlm_ops;
        case RAC_PRIMITIVE_DIFFUSION:     return vt->diffusion_ops;
        default:                           return nullptr;
    }
}

}  // extern "C"
