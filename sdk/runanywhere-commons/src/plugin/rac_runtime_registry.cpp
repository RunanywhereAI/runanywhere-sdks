/**
 * @file rac_runtime_registry.cpp
 * @brief Runtime-plugin registry implementation — keyed by `rac_runtime_id_t`.
 *
 * Task T4.1.
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
#include <cstring>
#include <exception>
#include <mutex>
#include <ranges>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

/* The built-in CPU runtime lives in `runtimes/cpu/rac_runtime_cpu.cpp`. We
 * reference its entry-point here so (a) the linker pulls the TU into
 * rac_commons' static archive and (b) we can bootstrap the registry with
 * it deterministically — without relying on RAC_STATIC_RUNTIME_REGISTER's
 * per-platform linker-keep-alive trick. */
extern "C" const rac_runtime_vtable_t* rac_runtime_entry_cpu(void);

#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
#if defined(_WIN32)
#include <windows.h>
using rac_lib_handle_t = HMODULE;
static rac_lib_handle_t rac_runtime_dl_open(const char* p) {
    return LoadLibraryA(p);
}
static void* rac_runtime_dl_sym(rac_lib_handle_t h, const char* s) {
    return reinterpret_cast<void*>(GetProcAddress(h, s));
}
static void rac_runtime_dl_close(rac_lib_handle_t h) {
    FreeLibrary(h);
}
static const char* rac_runtime_dl_error() {
    return "LoadLibrary failed";
}
#else
#include <dlfcn.h>
using rac_lib_handle_t = void*;
static rac_lib_handle_t rac_runtime_dl_open(const char* p) {
    return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}
static void* rac_runtime_dl_sym(rac_lib_handle_t h, const char* s) {
    return dlsym(h, s);
}
static void rac_runtime_dl_close(rac_lib_handle_t h) {
    dlclose(h);
}
static const char* rac_runtime_dl_error() {
    return dlerror();
}
#endif
#endif

namespace {

constexpr const char* LOG_CAT = "RuntimeRegistry";

struct Entry {
    rac_runtime_id_t id;
    int32_t priority;
    const rac_runtime_vtable_t* vtable;
    void* dl_handle;
};

struct State {
    std::mutex mu;
    /** Registered runtimes, descending priority. At most one active entry
     *  per `rac_runtime_id_t`. */
    std::vector<Entry> entries;
};

State& state() {
    static State s;
    return s;
}

/* ===========================================================================
 * Plugin-callback exception barriers.
 *
 * `init`, `destroy`, and the dlsym'd `entry` symbol are all third-party
 * callbacks supplied by a runtime plugin. RAC_RUNTIME_ENTRY_DEF documents
 * them as noexcept-equivalent, but the registry cannot audit a dlopen'd .so
 * (potentially compiled against a different libc++ whose exception class
 * hierarchy doesn't round-trip) — a misbehaving plugin would otherwise abort
 * the entire host. Coerce any throw to a structured error / no-op log, the
 * same shape used by `rac_plugin_registry.cpp`'s capability_check guard.
 * =========================================================================== */

/** Call a plugin callback that returns `rac_result_t`. On exception logs the
 *  failure and returns `on_throw` so the registry can map it to the caller-
 *  appropriate code (PLUGIN_LOAD_FAILED for register-time init, etc.). */
template <typename Fn>
rac_result_t safe_plugin_call(const char* name, const char* op, Fn&& fn,
                              rac_result_t on_throw) noexcept {
    try {
        return fn();
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "'%s' %s threw: %s", name == nullptr ? "?" : name, op, e.what());
        return on_throw;
    } catch (...) {
        RAC_LOG_ERROR(LOG_CAT, "'%s' %s threw non-std exception", name == nullptr ? "?" : name, op);
        return on_throw;
    }
}

/** Call a plugin destroy()-shaped callback (no return value). Swallows any
 *  throw because the unwind path has no plausible recovery — the entry has
 *  already been removed from the registry. */
template <typename Fn>
void safe_plugin_call_void(const char* name, const char* op, Fn&& fn) noexcept {
    try {
        fn();
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_CAT, "'%s' %s threw: %s", name == nullptr ? "?" : name, op, e.what());
    } catch (...) {
        RAC_LOG_ERROR(LOG_CAT, "'%s' %s threw non-std exception", name == nullptr ? "?" : name, op);
    }
}

/** Gates the one-time bootstrap of built-in runtimes. We want the CPU
 *  runtime registered on first registry touch, without re-entering the
 *  public register/unregister surface (which would deadlock on our mutex).
 *
 *  `std::once_flag` + `std::call_once` is the only race-free implementation
 *  of double-checked initialization in standard C++ — a plain bool read on
 *  the fast path racing with a mutex-protected store is undefined behavior
 *  under the C++ memory model (data race), even though the load happens to
 *  be naturally atomic on every supported architecture. `call_once` carries
 *  the necessary acquire/release synchronization with the slow path, removes
 *  the custom DCL pattern entirely, and is the well-trodden answer to TSan
 *  reports against `ensure_builtins_registered()`. */
std::once_flag g_builtins_once;

/** Construct + ordered-insert an Entry into `s.entries` under `s.mu`. The
 *  caller MUST own `s.mu`. Skips when an entry with the same id already
 *  exists, so a higher-priority pre-registered runtime (e.g. test fixture)
 *  wins. Pure container manipulation — never re-enters any plugin callback. */
void insert_builtin_locked(const rac_runtime_vtable_t* v, State& s) {
    for (const Entry& e : s.entries) {
        if (e.id == v->metadata.id)
            return;
    }
    Entry entry{
        .id = v->metadata.id, .priority = v->metadata.priority, .vtable = v, .dl_handle = nullptr};
    auto pos = std::ranges::lower_bound(
        s.entries, entry, [](const Entry& a, const Entry& b) { return a.priority > b.priority; });
    s.entries.insert(pos, entry);
}

void ensure_builtins_registered() {
    std::call_once(g_builtins_once, [] {
        const rac_runtime_vtable_t* cpu = rac_runtime_entry_cpu();
        if (cpu == nullptr || cpu->init == nullptr) {
            return;
        }
        /* init() is plugin-supplied. Per commons-064 wrap it so a rogue
         * built-in (e.g. a test fixture that subs in a misbehaving CPU
         * runtime) cannot abort SDK bootstrap. */
        const char* nm = cpu->metadata.name;
        rac_result_t rc = safe_plugin_call(
            nm, "init", [&]() -> rac_result_t { return cpu->init(); }, RAC_ERROR_PLUGIN_LOAD_FAILED);
        if (rc != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "bootstrap: CPU runtime init returned %d — skipping", (int)rc);
            return;
        }
        /* Take the registry mutex exactly once here, NOT inside
         * `insert_builtin_locked`. Per commons-159 this keeps the
         * lock-acquisition surface explicit: the only path that ever
         * acquires `state().mu` from within this lambda is this single
         * `lock_guard` — there is no nested call back into a helper that
         * re-takes the same mutex. */
        std::lock_guard<std::mutex> lock(state().mu);
        insert_builtin_locked(cpu, state());
        RAC_LOG_DEBUG(LOG_CAT, "bootstrap: built-in CPU runtime registered");
    });
}

bool has_required_ops(const rac_runtime_vtable_t* v) {
    return v->init != nullptr && v->destroy != nullptr;
}

bool abi_version_supported(uint32_t abi_version) {
    return abi_version == RAC_RUNTIME_ABI_VERSION;
}

rac_result_t validate_v2_extension(const rac_runtime_vtable_t* v) {
    if (v->reserved_slot_0 == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_register: '%s' missing required v2 extension",
                      v->metadata.name);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const auto* v2 = reinterpret_cast<const rac_runtime_vtable_v2_t*>(v->reserved_slot_0);
    if (v2->abi_version != RAC_RUNTIME_ABI_VERSION_V2) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_runtime_register: '%s' v2 extension ABI mismatch "
                      "(plugin=%u host=%u)",
                      v->metadata.name, v2->abi_version, RAC_RUNTIME_ABI_VERSION_V2);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    if (v2->struct_size < RAC_RUNTIME_VTABLE_V2_MIN_SIZE) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_runtime_register: '%s' v2 extension too small "
                      "(plugin=%u minimum=%u)",
                      v->metadata.name, v2->struct_size, RAC_RUNTIME_VTABLE_V2_MIN_SIZE);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    return RAC_SUCCESS;
}

void close_dynamic_handle(void* handle) {
#if !defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC
    if (handle != nullptr) {
        rac_runtime_dl_close(static_cast<rac_lib_handle_t>(handle));
    }
#else
    (void)handle;
#endif
}

/** Remove the entry matching `id` (if any); returns the erased vtable so
 *  the caller can invoke `destroy()` outside the lock. */
Entry take_entry_locked(State& s, rac_runtime_id_t id) {
    auto it = std::ranges::find_if(s.entries, [&](const Entry& e) { return e.id == id; });
    if (it == s.entries.end())
        return Entry{
            .id = RAC_RUNTIME_UNSPECIFIED, .priority = 0, .vtable = nullptr, .dl_handle = nullptr};
    Entry entry = *it;
    s.entries.erase(it);
    return entry;
}

/** Insert preserving descending priority order. */
void insert_locked(State& s, Entry e) {
    auto pos = std::ranges::lower_bound(
        s.entries, e, [](const Entry& a, const Entry& b) { return a.priority > b.priority; });
    s.entries.insert(pos, e);
}

bool attach_handle_locked(State& s, rac_runtime_id_t id, void* handle) {
    for (Entry& e : s.entries) {
        if (e.id == id) {
            if (e.dl_handle != nullptr && e.dl_handle != handle) {
                close_dynamic_handle(e.dl_handle);
            }
            e.dl_handle = handle;
            return true;
        }
    }
    return false;
}

std::string entry_symbol_from_path(const char* path) {
    if (path == nullptr)
        return {};
    std::string s(path);
    auto last_sep = s.find_last_of("/\\");
    if (last_sep != std::string::npos)
        s.erase(0, last_sep + 1);
    if (s.starts_with("lib"))
        s.erase(0, 3);
    auto dot = s.find('.');
    if (dot != std::string::npos)
        s.erase(dot);
    if (s.starts_with("runanywhere_")) {
        s.erase(0, std::strlen("runanywhere_"));
    }
    return std::string("rac_runtime_entry_") + s;
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
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_register: '%s' missing init/destroy op",
                      vtable->metadata.name);
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!abi_version_supported(vtable->metadata.abi_version)) {
        RAC_LOG_ERROR(LOG_CAT,
                      "rac_runtime_register: '%s' ABI mismatch (plugin=%u "
                      "host_min=%u host_max=%u)",
                      vtable->metadata.name, vtable->metadata.abi_version,
                      RAC_RUNTIME_ABI_VERSION_MIN, RAC_RUNTIME_ABI_VERSION);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    rac_result_t rc = validate_v2_extension(vtable);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    /* Call init() OUTSIDE the registry lock so a slow probe never blocks
     * unrelated lookups. If init returns non-zero the runtime is silently
     * rejected (e.g. Metal on Linux, CUDA on a CPU-only host).
     *
     * init() is plugin-supplied. A throw here from a dlopen'd runtime would
     * cross a libc++ boundary and crash the host; wrap in safe_plugin_call
     * so any exception is logged + coerced to PLUGIN_LOAD_FAILED. */
    rc = safe_plugin_call(
        vtable->metadata.name, "init", [&]() -> rac_result_t { return vtable->init(); },
        RAC_ERROR_PLUGIN_LOAD_FAILED);
    if (rc != RAC_SUCCESS) {
        if (rc == RAC_ERROR_PLUGIN_LOAD_FAILED) {
            return rc;
        }
        RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_register: '%s' init rejected (%d) — not loading",
                      vtable->metadata.name, (int)rc);
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }

    auto& s = state();
    /* Eviction-and-insertion is a SINGLE critical section. The registry
     * mutex MUST NOT be dropped between erasing the existing entry and
     * inserting the replacement: a concurrent rac_runtime_register for
     * the same id could otherwise observe an empty slot and insert its
     * own entry, leaving the registry with two entries sharing one id
     * (one silently leaked — unreachable from rac_runtime_unregister
     * / rac_runtime_get_by_id, which only return the first match).
     *
     * Pattern: under the lock, steal the evicted entry into a local
     * (removing it from `s.entries`) AND insert the replacement in the
     * same critical section. Only AFTER lock release do we call
     * destroy() + close_dynamic_handle on the locally-stolen entry —
     * by then it is no longer reachable from the registry, so other
     * threads cannot race with the tear-down. */
    Entry evicted{
        .id = RAC_RUNTIME_UNSPECIFIED, .priority = 0, .vtable = nullptr, .dl_handle = nullptr};
    bool has_evicted = false;
    bool rejected_duplicate = false;
    {
        std::lock_guard<std::mutex> lock(s.mu);

        auto existing = std::ranges::find_if(
            s.entries, [&](const Entry& e) { return e.id == vtable->metadata.id; });
        if (existing != s.entries.end()) {
            if (vtable->metadata.priority < existing->priority) {
                RAC_LOG_DEBUG(
                    LOG_CAT, "rac_runtime_register: '%s' rejected (priority %d < existing %d)",
                    vtable->metadata.name, (int)vtable->metadata.priority, (int)existing->priority);
                /* Existing entry stays registered. We defer destroy() of
                 * the rejected vtable until after lock release. */
                rejected_duplicate = true;
            } else {
                /* Steal the evicted entry into a local AND insert the
                 * replacement, atomically, under the same lock. There is
                 * no observable gap in which another thread could see an
                 * empty slot for this id. */
                evicted = *existing;
                has_evicted = true;
                s.entries.erase(existing);
            }
        }

        if (!rejected_duplicate) {
            insert_locked(s, Entry{.id = vtable->metadata.id,
                                   .priority = vtable->metadata.priority,
                                   .vtable = vtable,
                                   .dl_handle = nullptr});
        }
    }

    /* Lock released. The evicted entry (if any) is now unreachable from
     * the registry; destroy + dlclose are safe to run without holding the
     * registry mutex. Likewise the rejected vtable was never installed,
     * so its destroy() races with nothing. Plugin-supplied destroy() is
     * wrapped per commons-064 so a third-party throw cannot abort the host. */
    if (rejected_duplicate) {
        safe_plugin_call_void(vtable->metadata.name, "destroy", [&]() { vtable->destroy(); });
        return RAC_ERROR_PLUGIN_DUPLICATE;
    }
    if (has_evicted) {
        safe_plugin_call_void(evicted.vtable->metadata.name, "destroy",
                              [&]() { evicted.vtable->destroy(); });
        close_dynamic_handle(evicted.dl_handle);
    }

    RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_register: '%s' (id=%d) ok", vtable->metadata.name,
                  (int)vtable->metadata.id);
    return RAC_SUCCESS;
}

rac_result_t rac_runtime_unregister(rac_runtime_id_t id) {
    ensure_builtins_registered();
    auto& s = state();
    std::unique_lock<std::mutex> lock(s.mu);
    Entry erased = take_entry_locked(s, id);
    if (erased.vtable == nullptr) {
        return RAC_ERROR_NOT_FOUND;
    }
    lock.unlock();
    /* destroy() is plugin-supplied; wrap per commons-064. */
    safe_plugin_call_void(erased.vtable->metadata.name, "destroy",
                          [&]() { erased.vtable->destroy(); });
    close_dynamic_handle(erased.dl_handle);
    RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_unregister: id=%d ok", (int)id);
    return RAC_SUCCESS;
}

const rac_runtime_vtable_t* rac_runtime_get_by_id(rac_runtime_id_t id) {
    ensure_builtins_registered();
    auto& s = state();
    std::lock_guard<std::mutex> lock(s.mu);
    for (const Entry& e : s.entries) {
        if (e.id == id)
            return e.vtable;
    }
    return nullptr;
}

rac_result_t rac_runtime_list(const rac_runtime_vtable_t** out_runtimes, size_t max,
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

int rac_runtime_is_registered(rac_runtime_id_t id) {
    /* Behaviorally identical to rac_runtime_is_available — exposed under a
     * second name so the engine router's pre-flight check reads as
     * "is the runtime registered?" rather than "is it available?". The two
     * are the same predicate by construction: a runtime is registered iff
     * it survived `init()` + dedup and is currently in the entries list. */
    return rac_runtime_is_available(id);
}

uint32_t rac_runtime_abi_version(void) {
    return RAC_RUNTIME_ABI_VERSION;
}

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC

rac_result_t rac_runtime_load(const char* path) {
    if (path == nullptr)
        return RAC_ERROR_NULL_POINTER;
    RAC_LOG_DEBUG(LOG_CAT,
                  "rac_runtime_load('%s'): host built with "
                  "RAC_STATIC_PLUGINS=ON; dynamic runtime loading is disabled.",
                  path);
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

#else

rac_result_t rac_runtime_load(const char* path) {
    if (path == nullptr)
        return RAC_ERROR_NULL_POINTER;

    rac_lib_handle_t handle = rac_runtime_dl_open(path);
    if (handle == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_load('%s'): dlopen failed (%s)", path,
                      rac_runtime_dl_error());
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    const std::string sym = entry_symbol_from_path(path);
    void* entry_sym = rac_runtime_dl_sym(handle, sym.c_str());
    if (entry_sym == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_load('%s'): dlsym('%s') failed (%s)", path, sym.c_str(),
                      rac_runtime_dl_error());
        rac_runtime_dl_close(handle);
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    auto entry = reinterpret_cast<rac_runtime_entry_fn>(entry_sym);
    /* `entry` is dlsym'd from a foreign shared library. Per commons-064 the
     * exception class hierarchy of the loaded .so may not round-trip through
     * the host's libc++, so a throw here can crash the SDK before we even
     * see the vtable. Wrap and coerce to PLUGIN_LOAD_FAILED. */
    const rac_runtime_vtable_t* vt = nullptr;
    rac_result_t entry_rc = safe_plugin_call(
        sym.c_str(), "entry",
        [&]() -> rac_result_t {
            vt = entry();
            return RAC_SUCCESS;
        },
        RAC_ERROR_PLUGIN_LOAD_FAILED);
    if (entry_rc != RAC_SUCCESS) {
        rac_runtime_dl_close(handle);
        return entry_rc;
    }
    if (vt == nullptr || vt->metadata.name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_load('%s'): entry '%s' returned NULL or unnamed vtable",
                      path, sym.c_str());
        rac_runtime_dl_close(handle);
        return RAC_ERROR_PLUGIN_LOAD_FAILED;
    }

    rac_result_t rc = rac_runtime_register(vt);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "rac_runtime_load('%s'): rac_runtime_register('%s') -> %d", path,
                      vt->metadata.name, static_cast<int>(rc));
        rac_runtime_dl_close(handle);
        return rc;
    }

    auto& s = state();
    {
        std::lock_guard<std::mutex> lock(s.mu);
        if (!attach_handle_locked(s, vt->metadata.id, handle)) {
            rc = RAC_ERROR_NOT_FOUND;
        }
    }
    if (rc != RAC_SUCCESS) {
        rac_runtime_unregister(vt->metadata.id);
        rac_runtime_dl_close(handle);
        return rc;
    }

    RAC_LOG_DEBUG(LOG_CAT, "rac_runtime_load('%s'): registered '%s' from '%s'", path,
                  vt->metadata.name, sym.c_str());
    return RAC_SUCCESS;
}

#endif

rac_result_t rac_runtime_unload(rac_runtime_id_t id) {
    return rac_runtime_unregister(id);
}

}  // extern "C"
