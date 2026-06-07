/**
 * @file rac_plugin_registry.cpp
 * @brief Unified engine plugin registry — keyed by `rac_primitive_t`.
 *
 * This is the SOLE plugin registration path. The legacy
 * `service_registry.cpp` / `rac_service_register_provider()` path was
 * removed. All engine backends (llamacpp, onnx, sherpa, metalrt,
 * platform) register via
 * `rac_plugin_register(rac_plugin_entry_<name>())`, and commons consumers
 * route through `rac_plugin_route` + `vt->ops->create`.
 */

#include "plugin_registry_internal.h"

#include <algorithm>
#include <atomic>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <exception>
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

/* Portable string duplicator from src/core/rac_memory.cpp — replaces POSIX
 * `strdup` so MSVC `/W4 /WX` builds stay green and so this TU shares the
 * single OOM-tolerant allocation path used by the rest of commons. */
extern "C" char* rac_strdup(const char* str);

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
    /** Name → dlopen handle for plugins loaded via
     *  `rac_registry_load_plugin()`. Statically-registered plugins have no
     *  entry here. Populated by the loader, drained by `rac_plugin_unregister`. */
    std::unordered_map<std::string, void*> dl_handles;
    /** Manifest attached by an engine entry before the vtable is registered. */
    std::unordered_map<const rac_engine_vtable_t*, const rac_engine_manifest_t*>
        manifests_by_vtable;
    /** Accepted manifest by engine name. Values are plugin-owned .rodata. */
    std::unordered_map<std::string, const rac_engine_manifest_t*> manifests_by_name;
    /** Process-wide count of routers that have snapshotted vtable
     *  pointers from `rac_plugin_list` and are still dereferencing them.
     *  `rac_registry_unload_plugin` spin-waits this to zero AFTER the plugin
     *  is unregistered but BEFORE the OS library mapping is `dlclose`d, so
     *  any router that observed a vtable can finish reading its `.rodata`
     *  before that memory is unmapped. Sequentially consistent so the
     *  enter-from-router and the unload-side observe each other's
     *  monotonic transitions without surprises. */
    std::atomic<size_t> router_inflight{0};
};

State& state() {
    // Meyers singleton; thread-safe initialization since C++11.
    static State s;
    return s;
}

/** Which primitive slots (in declaration order) the vtable fills.
 *  Generated from RAC_PRIMITIVE_TABLE (rac_engine_vtable.h) — the single
 *  source of truth for the primitive↔slot mapping. RERANK is absent from the
 *  table, so it is never reported as served. */
void each_served_primitive(const rac_engine_vtable_t* v,
                           const std::function<void(rac_primitive_t)>& fn) {
#define X(ENUM, FIELD, NAME) \
    if (v->FIELD)            \
        fn(ENUM);
    RAC_PRIMITIVE_TABLE(X)
#undef X
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

/** Erase `name` from every `by_primitive` bucket. Caller must hold `s.mu`. */
void erase_from_buckets_locked(State& s, const std::string& name) {
    for (auto& kv : s.by_primitive) {
        auto& vec = kv.second;
        const auto removed =
            std::ranges::remove_if(vec, [&](const Entry& e) { return e.name == name; });
        vec.erase(removed.begin(), removed.end());
    }
}

/** Pop the dl_handle (if any) associated with `name` from `s.dl_handles`.
 *  Caller must hold `s.mu`. Returns the popped handle or `nullptr`. Mirrors
 *  `rac_plugin_registry_take_dl_handle` but skips the public-API lock since
 *  the caller already holds it. */
void* take_dl_handle_locked(State& s, const std::string& name) {
    auto it = s.dl_handles.find(name);
    if (it == s.dl_handles.end()) {
        return nullptr;
    }
    void* handle = it->second;
    s.dl_handles.erase(it);
    return handle;
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

    /* A declared manifest primitive is valid iff it is a live routable
     * primitive (a RAC_PRIMITIVE_TABLE row) whose vtable slot is non-null.
     * `rac_engine_vtable_slot` returns NULL for everything absent from the
     * table — RERANK, the reserved slots, UNSPECIFIED, and out-of-range
     * values — so this single check also rejects them, with no magic range
     * bound to keep in sync. */
    for (size_t i = 0; i < manifest->primitives_count; ++i) {
        rac_primitive_t primitive = manifest->primitives[i];
        if (rac_engine_vtable_slot(vtable, primitive) == nullptr) {
            return RAC_ERROR_INVALID_PARAMETER;
        }
    }

    /* Every non-null routable slot the vtable fills must be declared in the
     * manifest. Iterate the table directly so RERANK / reserved slots are
     * excluded by construction. */
#define X(ENUM, FIELD, NAME)                          \
    if (rac_engine_vtable_slot(vtable, ENUM) != nullptr && \
        !manifest_declares_primitive(manifest, ENUM)) {    \
        return RAC_ERROR_INVALID_PARAMETER;           \
    }
    RAC_PRIMITIVE_TABLE(X)
#undef X

    return RAC_SUCCESS;
}

rac_result_t rac_engine_manifest_attach_vtable(const rac_engine_manifest_t* manifest,
                                               const rac_engine_vtable_t* vtable) noexcept {
    /* C ABI boundary: noexcept. unordered_map::operator[] can throw
     * std::bad_alloc on bucket resize under memory pressure. */
    try {
        rac_result_t rc = rac_engine_manifest_validate_vtable(manifest, vtable);
        if (rc != RAC_SUCCESS)
            return rc;

        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        s.manifests_by_vtable[vtable] = manifest;
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

rac_result_t rac_engine_manifest_detach_vtable(const rac_engine_vtable_t* vtable) noexcept {
    /* C ABI boundary: noexcept. */
    try {
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
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

const rac_engine_manifest_t* rac_engine_manifest_find(const char* name) noexcept {
    /* C ABI boundary: noexcept. */
    try {
        if (name == nullptr)
            return nullptr;
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        auto it = s.manifests_by_name.find(name);
        return it == s.manifests_by_name.end() ? nullptr : it->second;
    } catch (...) {
        return nullptr;
    }
}

size_t rac_engine_manifest_count(void) noexcept {
    /* C ABI boundary: noexcept. */
    try {
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        return s.manifests_by_name.size();
    } catch (...) {
        return 0;
    }
}

rac_result_t rac_plugin_register(const rac_engine_vtable_t* vtable) noexcept {
    /* C ABI boundary: noexcept. Propagating a C++ exception past this
     * boundary is undefined behavior per ISO C++ [except.handle]/9 — every
     * SDK (Swift, Kotlin/JNI, Dart/FFI, NitroModules, WASM) calls this from
     * a non-C++ stack unwinder. std::string / std::unordered_map /
     * std::vector ops below can throw std::bad_alloc, and the third-party
     * `capability_check` callback can throw anything; both are coerced to
     * structured rac_result_t error codes. */
    try {
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
                          vtable->metadata.name, vtable->metadata.abi_version,
                          RAC_PLUGIN_API_VERSION);
            return RAC_ERROR_ABI_VERSION_MISMATCH;
        }

        if (vtable->capability_check != nullptr) {
            /* Third-party callback. A throw here would corrupt the JVM /
             * Hermes / Dart exception state and crash the host SDK at
             * registration time; coerce to a load failure instead. */
            rac_result_t cap;
            try {
                cap = vtable->capability_check();
            } catch (...) {
                RAC_LOG_ERROR(LOG_CAT,
                              "rac_plugin_register: '%s' capability_check threw — refusing load",
                              vtable->metadata.name);
                detach_pending_manifest(vtable);
                return RAC_ERROR_PLUGIN_LOAD_FAILED;
            }
            if (cap != RAC_SUCCESS) {
                RAC_LOG_DEBUG(
                    LOG_CAT,
                    "rac_plugin_register: '%s' capability_check rejected (%d) — not loading",
                    vtable->metadata.name, (int)cap);
                // Return the registry-level code; capability_check's raw status
                // is visible in the log above for debugging.
                detach_pending_manifest(vtable);
                return RAC_ERROR_CAPABILITY_UNSUPPORTED;
            }
        }

        auto& s = state();

        /* Eviction + manifest lookup + manifest validate + insertion are a
         * SINGLE critical section, mirroring rac_runtime_registry.cpp lines
         * 264-322. Doing the attached-manifest lookup under one lock and
         * the validate() call under another previously created a TOCTOU
         * window in which a concurrent rac_engine_manifest_detach_vtable
         * could invalidate the accepted manifest. validate() is pure (no
         * I/O, no callbacks) so holding the lock across it is safe. */
        const rac_engine_vtable_t* evicted_vtable = nullptr;

        {
            std::lock_guard<std::mutex> lock(s.mu);

            const rac_engine_manifest_t* manifest = attached_manifest_locked(s, vtable);
            if (manifest != nullptr) {
                rac_result_t manifest_rc = rac_engine_manifest_validate_vtable(manifest, vtable);
                if (manifest_rc != RAC_SUCCESS) {
                    RAC_LOG_ERROR(LOG_CAT,
                                  "rac_plugin_register: '%s' manifest validation failed (%d)",
                                  vtable->metadata.name, (int)manifest_rc);
                    s.manifests_by_vtable.erase(vtable);
                    return manifest_rc;
                }
            }

            std::string name(vtable->metadata.name);
            auto dup = s.by_name.find(name);
            const bool replacing_existing = dup != s.by_name.end();
            if (replacing_existing) {
                // Duplicate by name: replace only if incoming priority >= existing.
                int32_t existing_prio = dup->second->metadata.priority;
                if (vtable->metadata.priority < existing_prio) {
                    RAC_LOG_DEBUG(LOG_CAT,
                                  "rac_plugin_register: '%s' rejected (priority %d < existing %d)",
                                  name.c_str(), (int)vtable->metadata.priority, (int)existing_prio);
                    s.manifests_by_vtable.erase(vtable);
                    return RAC_ERROR_PLUGIN_DUPLICATE;
                }
                // Steal the evicted vtable into a local so `on_unload` runs
                // AFTER the lock is released: the evicted plugin's teardown
                // is then free to call back into rac_plugin_find /
                // rac_plugin_count without self-deadlock, AND engine-global
                // resources owned by the previous instance finally get
                // their teardown notification (no more silent leak on
                // duplicate-replace). NOTE: `dl_handles` is deliberately
                // NOT touched here — the loader's rac_registry_load_plugin
                // takes the prior handle and dlcloses it AFTER this
                // function returns (plugin_loader.cpp:188), balancing its
                // own redundant dlopen of the same library. Disturbing the
                // dl_handles entry here would break that balance and leak
                // the OS mapping (regression covered by
                // test_plugin_loader_double_load).
                evicted_vtable = dup->second;
                s.manifests_by_vtable.erase(evicted_vtable);
                erase_from_buckets_locked(s, name);
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
        }

        // Lock released. Tear down the evicted entry (only if we replaced
        // one). The evicted vtable is no longer reachable from the registry
        // so on_unload races with nothing.
        if (evicted_vtable != nullptr && evicted_vtable->on_unload != nullptr) {
            try {
                evicted_vtable->on_unload();
            } catch (...) {
                RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: evicted '%s' on_unload threw",
                              vtable->metadata.name);
            }
        }

        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: out of memory");
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        RAC_LOG_ERROR(LOG_CAT, "rac_plugin_register: unexpected exception");
        return RAC_ERROR_INTERNAL;
    }
}

rac_result_t rac_plugin_unregister(const char* name) noexcept {
    /* C ABI boundary: noexcept. std::string / unordered_map ops may throw
     * std::bad_alloc, and the plugin-supplied `on_unload` is third-party
     * code that may also throw. */
    try {
        if (name == nullptr) {
            return RAC_ERROR_NULL_POINTER;
        }

        auto& s = state();

        /* Take the entry under the lock, then release BEFORE calling
         * on_unload so the unloading plugin can re-enter the public
         * registry surface (rac_plugin_find / rac_plugin_count) without
         * self-deadlocking. Mirrors rac_runtime_registry.cpp:343-356.
         *
         * Also drains `dl_handles`, honouring the contract documented in
         * plugin_registry_internal.h ("drained by rac_plugin_unregister").
         * The loader's `rac_registry_unload_plugin` takes the handle
         * BEFORE calling this function (plugin_loader.cpp:209), so for the
         * loader path our take returns nullptr and no behavioural change
         * occurs. For direct callers that bypass the loader (tests, future
         * Kotlin/Swift hot-swap helpers) draining here prevents the stale
         * `void*` from haunting a later same-name reload via
         * `rac_registry_load_plugin` → `take_dl_handle` → dlclose-on-
         * unmapped-handle → SIGSEGV. The registry has no dlclose hook so
         * the OS mapping is leaked in that direct-caller case; we log a
         * warning so the inconsistency is observable. */
        const rac_engine_vtable_t* v = nullptr;
        void* stale_dl_handle = nullptr;
        std::string key(name);

        {
            std::lock_guard<std::mutex> lock(s.mu);

            auto it = s.by_name.find(key);
            if (it == s.by_name.end()) {
                return RAC_ERROR_NOT_FOUND;
            }
            v = it->second;
            stale_dl_handle = take_dl_handle_locked(s, key);

            s.by_name.erase(it);
            s.manifests_by_name.erase(key);
            s.manifests_by_vtable.erase(v);
            erase_from_buckets_locked(s, key);
        }

        if (v != nullptr && v->on_unload != nullptr) {
            try {
                v->on_unload();
            } catch (...) {
                RAC_LOG_ERROR(LOG_CAT, "rac_plugin_unregister: '%s' on_unload threw", name);
            }
        }
        if (stale_dl_handle != nullptr) {
            RAC_LOG_WARNING(LOG_CAT,
                            "rac_plugin_unregister: '%s' had a tracked dlopen handle but the "
                            "caller bypassed rac_registry_unload_plugin; OS handle leaked.",
                            name);
        }

        RAC_LOG_DEBUG(LOG_CAT, "rac_plugin_unregister: '%s' ok", name);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

const rac_engine_vtable_t* rac_plugin_find(rac_primitive_t primitive) noexcept {
    /* C ABI boundary: noexcept. unordered_map::find can throw std::bad_alloc
     * on hash bucket resize under memory pressure; swallow and return null. */
    try {
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        auto it = s.by_primitive.find(primitive);
        if (it == s.by_primitive.end() || it->second.empty()) {
            return nullptr;
        }
        // Descending priority — first is best.
        return it->second.front().vtable;
    } catch (...) {
        return nullptr;
    }
}

const rac_engine_vtable_t* rac_plugin_find_for_engine(rac_primitive_t primitive,
                                                      const char* engine_name) noexcept {
    /* C ABI boundary: noexcept. Returns the plugin registered under
     * `engine_name` IFF it serves `primitive`, else nullptr. Lets the hybrid
     * STT router pin a specific engine where priority order cannot distinguish
     * two plugins serving one primitive. */
    if (engine_name == nullptr || engine_name[0] == '\0') {
        return nullptr;
    }
    try {
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        auto it = s.by_primitive.find(primitive);
        if (it == s.by_primitive.end()) {
            return nullptr;
        }
        for (const auto& entry : it->second) {
            if (entry.name == engine_name) {
                return entry.vtable;
            }
        }
        return nullptr;
    } catch (...) {
        return nullptr;
    }
}

rac_result_t rac_plugin_list(rac_primitive_t primitive, const rac_engine_vtable_t** out_plugins,
                             size_t max, size_t* out_count) noexcept {
    /* C ABI boundary: noexcept. */
    try {
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
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

size_t rac_plugin_count(void) noexcept {
    /* C ABI boundary: noexcept. */
    try {
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        return s.by_name.size();
    } catch (...) {
        return 0;
    }
}

// =============================================================================
// Internal: dl_handle bookkeeping (plugin_registry_internal.h)
// =============================================================================

void rac_plugin_registry_set_dl_handle(const char* name, void* handle) noexcept {
    /* C ABI boundary: noexcept. */
    try {
        if (name == nullptr)
            return;
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        if (handle == nullptr) {
            s.dl_handles.erase(name);
        } else {
            s.dl_handles[name] = handle;
        }
    } catch (...) {
        // Best-effort bookkeeping; swallow allocator failures to keep the
        // C ABI exception-safe.
    }
}

void* rac_plugin_registry_take_dl_handle(const char* name) noexcept {
    /* C ABI boundary: noexcept. */
    try {
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
    } catch (...) {
        return nullptr;
    }
}

size_t rac_plugin_registry_snapshot_names(const char*** out_names) noexcept {
    /* C ABI boundary: noexcept. Guards against a leak on partial allocation
     * failure and against POSIX `strdup` (not MSVC-portable + silent
     * truncation on NULL slots): use the portable rac_strdup helper, roll
     * back every previously-allocated entry on any NULL return, reject sizes
     * that would overflow size_t multiplication. */
    try {
        if (out_names == nullptr)
            return 0;
        auto& s = state();
        std::lock_guard<std::mutex> lock(s.mu);
        size_t n = s.by_name.size();
        if (n == 0) {
            *out_names = nullptr;
            return 0;
        }
        // Reject sizes that would overflow the array byte count. The cap
        // matches std::malloc's untyped contract and prevents a wrap-then-
        // undersized-malloc footgun.
        if (n > SIZE_MAX / sizeof(const char*)) {
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
            char* dup = rac_strdup(kv.first.c_str());
            if (dup == nullptr) {
                // Roll back every successful dup AND the array itself; the
                // caller must be able to treat (0, nullptr) as a clean
                // failure rather than chase NULL slots in a partial array.
                for (size_t j = 0; j < i; ++j) {
                    std::free(const_cast<char*>(arr[j]));
                }
                std::free(arr);
                *out_names = nullptr;
                return 0;
            }
            arr[i++] = dup;
        }
        *out_names = arr;
        return n;
    } catch (...) {
        if (out_names != nullptr) {
            *out_names = nullptr;
        }
        return 0;
    }
}

// =============================================================================
// Router in-flight bookkeeping (plugin_registry_internal.h)
// =============================================================================
//
// EngineRouter::route brackets its snapshot/score/sort window with
// router_enter()/router_exit(). rac_registry_unload_plugin spin-waits the
// in-flight counter to zero AFTER `rac_plugin_unregister` returns (so no new
// router can observe the unregistered vtable through `rac_plugin_list`) but
// BEFORE `dlclose` unmaps the plugin's `.rodata`. That drains any router
// already holding a raw vtable pointer.

void rac_plugin_registry_router_enter(void) noexcept {
    auto& s = state();
    s.router_inflight.fetch_add(1, std::memory_order_seq_cst);
}

void rac_plugin_registry_router_exit(void) noexcept {
    auto& s = state();
    s.router_inflight.fetch_sub(1, std::memory_order_seq_cst);
}

size_t rac_plugin_registry_router_inflight(void) noexcept {
    auto& s = state();
    return s.router_inflight.load(std::memory_order_seq_cst);
}

// =============================================================================
// Helpers from rac_primitive.h / rac_engine_vtable.h
// =============================================================================

const char* rac_primitive_name(rac_primitive_t p) {
    switch (p) {
        /* Live routable primitives generated from RAC_PRIMITIVE_TABLE
         * (rac_engine_vtable.h). */
#define X(ENUM, FIELD, NAME) \
    case ENUM:               \
        return NAME;
        RAC_PRIMITIVE_TABLE(X)
#undef X
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
    /* Cases generated from RAC_PRIMITIVE_TABLE (rac_engine_vtable.h). The
     * `default` covers everything absent from the table — RERANK (dormant),
     * the reserved slots, and UNSPECIFIED — all of which are non-routable and
     * return NULL. */
    switch (primitive) {
#define X(ENUM, FIELD, NAME) \
    case ENUM:               \
        return vt->FIELD;
        RAC_PRIMITIVE_TABLE(X)
#undef X
        default:
            return nullptr;
    }
}

// =============================================================================
// Legacy ABI shim — rac_service_register_provider
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
