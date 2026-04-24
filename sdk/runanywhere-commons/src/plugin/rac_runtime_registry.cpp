/**
 * @file rac_runtime_registry.cpp
 * @brief Runtime-plugin registry implementation — keyed by `rac_runtime_id_t`.
 *
 * Task T4.1 — see `docs/RUNTIME_VTABLE_DESIGN.md`.
 *
 * Mirrors `rac_plugin_registry.cpp` but scoped to the L1 compute runtime
 * layer (CPU / Metal / CoreML / CUDA / …). The two registries are
 * deliberately independent so that:
 *   - An engine vtable change never invalidates runtime plugins (and
 *     vice-versa), letting ABI versions evolve separately.
 *   - A host can query "is CUDA available?" with `rac_runtime_is_available`
 *     without walking the engine registry.
 */

#include "rac/plugin/rac_runtime_registry.h"

#include <algorithm>
#include <mutex>
#include <vector>

#include "rac/core/rac_logger.h"

/* The built-in CPU runtime lives in `runtimes/cpu/rac_runtime_cpu.cpp`. We
 * reference its entry-point here so (a) the linker pulls the TU into
 * rac_commons' static archive and (b) we can bootstrap the registry with
 * it deterministically — without relying on RAC_STATIC_RUNTIME_REGISTER's
 * per-platform linker-keep-alive trick. */
extern "C" const rac_runtime_vtable_t* rac_runtime_entry_cpu(void);

namespace {

constexpr const char* LOG_CAT = "RuntimeRegistry";

struct Entry {
    rac_runtime_id_t             id;
    int32_t                      priority;
    const rac_runtime_vtable_t*  vtable;
};

struct State {
    std::mutex         mu;
    /** Registered runtimes, descending priority. At most one active entry
     *  per `rac_runtime_id_t`. */
    std::vector<Entry> entries;
};

State& state() {
    static State s;
    return s;
}

/** Flag that gates the one-time bootstrap of built-in runtimes. We want the
 *  CPU runtime registered on first registry touch, without re-entering the
 *  public register/unregister surface (which would deadlock on our mutex).
 *  A raw flag + a helper suffice — `std::once_flag` is avoided to keep the
 *  hot path branch-predictor-friendly and because we only ever flip this
 *  once per process. */
bool                        g_builtins_ready    = false;
std::mutex                  g_builtins_mu;

/** Insert a vtable straight into the state (no lock held by caller; we grab
 *  the registry's mutex internally). Used only by bootstrap, because bypass
 *  of the public `rac_runtime_register` skips its init()/validation — which
 *  is exactly what we want for in-process built-ins we control. */
void insert_builtin(const rac_runtime_vtable_t* v, State& s) {
    std::lock_guard<std::mutex> lock(s.mu);
    /* Don't double-insert: a caller may have already registered a higher-
     * priority CPU runtime (e.g. a plug-in test fixture). */
    for (const Entry& e : s.entries) {
        if (e.id == v->metadata.id) return;
    }
    Entry entry{v->metadata.id, v->metadata.priority, v};
    auto pos = std::lower_bound(s.entries.begin(), s.entries.end(), entry,
                                [](const Entry& a, const Entry& b) {
                                    return a.priority > b.priority;
                                });
    s.entries.insert(pos, entry);
}

void ensure_builtins_registered() {
    /* Fast path: already done. `bool` reads are atomic on all supported
     * archs + the flag is only ever written while holding g_builtins_mu. */
    if (g_builtins_ready) return;
    std::lock_guard<std::mutex> lock(g_builtins_mu);
    if (g_builtins_ready) return;
    const rac_runtime_vtable_t* cpu = rac_runtime_entry_cpu();
    if (cpu != nullptr && cpu->init != nullptr) {
        rac_result_t rc = cpu->init();
        if (rc == RAC_SUCCESS) {
            insert_builtin(cpu, state());
            RAC_LOG_DEBUG(LOG_CAT, "bootstrap: built-in CPU runtime registered");
        } else {
            RAC_LOG_ERROR(LOG_CAT,
                          "bootstrap: CPU runtime init returned %d — skipping",
                          (int)rc);
        }
    }
    g_builtins_ready = true;
}

bool has_required_ops(const rac_runtime_vtable_t* v) {
    return v->init != nullptr && v->destroy != nullptr;
}

/** Remove the entry matching `id` (if any); returns the erased vtable so
 *  the caller can invoke `destroy()` outside the lock. */
const rac_runtime_vtable_t* take_entry_locked(State& s, rac_runtime_id_t id) {
    auto it = std::find_if(s.entries.begin(), s.entries.end(),
                           [&](const Entry& e) { return e.id == id; });
    if (it == s.entries.end()) return nullptr;
    const rac_runtime_vtable_t* v = it->vtable;
    s.entries.erase(it);
    return v;
}

/** Insert preserving descending priority order. */
void insert_locked(State& s, Entry e) {
    auto pos = std::lower_bound(s.entries.begin(), s.entries.end(), e,
                                [](const Entry& a, const Entry& b) {
                                    return a.priority > b.priority;
                                });
    s.entries.insert(pos, e);
}

}  // namespace

extern "C" {

rac_result_t rac_runtime_register(const rac_runtime_vtable_t* vtable) {
    ensure_builtins_registered();
    if (vtable == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_register: NULL vtable");
        return RAC_ERROR_NULL_POINTER;
    }
    if (vtable->metadata.name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_register: metadata.name is NULL");
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!has_required_ops(vtable)) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_runtime_register: '%s' missing init/destroy op",
                      vtable->metadata.name);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (vtable->metadata.abi_version != RAC_RUNTIME_ABI_VERSION) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_runtime_register: '%s' ABI mismatch (plugin=%u host=%u)",
                      vtable->metadata.name,
                      vtable->metadata.abi_version,
                      RAC_RUNTIME_ABI_VERSION);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    /* Call init() OUTSIDE the registry lock so a slow probe never blocks
     * unrelated lookups. If init returns non-zero the runtime is silently
     * rejected (e.g. Metal on Linux, CUDA on a CPU-only host). */
    rac_result_t rc = vtable->init();
    if (rc != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT,
                      "rac_runtime_register: '%s' init rejected (%d) — not loading",
                      vtable->metadata.name, (int)rc);
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }

    auto& s = state();
    std::unique_lock<std::mutex> lock(s.mu);

    auto existing = std::find_if(s.entries.begin(), s.entries.end(),
                                 [&](const Entry& e) {
                                     return e.id == vtable->metadata.id;
                                 });
    if (existing != s.entries.end()) {
        if (vtable->metadata.priority < existing->priority) {
            RAC_LOG_DEBUG(LOG_CAT,
                          "rac_runtime_register: '%s' rejected (priority %d < existing %d)",
                          vtable->metadata.name,
                          (int)vtable->metadata.priority,
                          (int)existing->priority);
            lock.unlock();
            /* Unwind the init() we just performed. The existing runtime
             * keeps its registration. */
            vtable->destroy();
            return RAC_ERROR_PLUGIN_DUPLICATE;
        }
        /* Tear down the evicted vtable with its own destroy(), still outside
         * the registry mutex. */
        const rac_runtime_vtable_t* evicted = existing->vtable;
        s.entries.erase(existing);
        lock.unlock();
        evicted->destroy();
        lock.lock();
    }

    insert_locked(s, Entry{vtable->metadata.id,
                           vtable->metadata.priority,
                           vtable});

    RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_register: '%s' (id=%d) ok",
                  vtable->metadata.name, (int)vtable->metadata.id);
    return RAC_SUCCESS;
}

rac_result_t rac_runtime_unregister(rac_runtime_id_t id) {
    ensure_builtins_registered();
    auto& s = state();
    std::unique_lock<std::mutex> lock(s.mu);
    const rac_runtime_vtable_t* erased = take_entry_locked(s, id);
    if (erased == nullptr) {
        return RAC_ERROR_NOT_FOUND;
    }
    lock.unlock();
    erased->destroy();
    RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_unregister: id=%d ok", (int)id);
    return RAC_SUCCESS;
}

const rac_runtime_vtable_t* rac_runtime_get_by_id(rac_runtime_id_t id) {
    ensure_builtins_registered();
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    for (const Entry& e : s.entries) {
        if (e.id == id) return e.vtable;
    }
    return nullptr;
}

rac_result_t rac_runtime_list(const rac_runtime_vtable_t** out_runtimes,
                              size_t max,
                              size_t* out_count) {
    if (out_runtimes == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    ensure_builtins_registered();
    *out_count = 0;
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    size_t n = std::min(s.entries.size(), max);
    for (size_t i = 0; i < n; ++i) {
        out_runtimes[i] = s.entries[i].vtable;
    }
    *out_count = n;
    return RAC_SUCCESS;
}

size_t rac_runtime_count(void) {
    ensure_builtins_registered();
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    return s.entries.size();
}

int rac_runtime_is_available(rac_runtime_id_t id) {
    return rac_runtime_get_by_id(id) != nullptr ? 1 : 0;
}

}  // extern "C"
