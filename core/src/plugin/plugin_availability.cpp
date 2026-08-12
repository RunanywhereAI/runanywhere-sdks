/**
 * @file plugin_availability.cpp
 * @brief Process-wide ledger of backends that asked to join the plugin
 *        registry and were refused.
 *
 * Why this exists: a backend can fail to register for reasons that are entirely
 * about packaging (a stub library built without its engine, an ABI-stale
 * plugin, a `capability_check` that declines on this hardware). None of those
 * are reasons to take the whole SDK down, but a caller that only sees a
 * `rac_result_t` from a load call has nowhere to put the fact — so it either
 * swallows it silently or escalates it into an initialization failure. Both
 * are wrong. This ledger is the third option: the failure is remembered,
 * queryable, and reportable through each SDK's capability surface, while the
 * backends that DID load keep serving.
 *
 * Keyed by engine name so the last word wins: a retry that succeeds clears the
 * entry (`forget`), and a second failure of the same backend replaces rather
 * than duplicates. Separate TU from the loader because both the loader
 * (dlopen/dlsym failures) and the registry (ABI / capability / manifest
 * failures) write to it, and the loader has two mutually exclusive compile
 * paths (static vs shared) that this bookkeeping must outlive.
 */

#include "plugin_registry_internal.h"

#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_loader.h"

namespace {

constexpr const char* LOG_CAT = "PluginAvailability";

struct Entry {
    std::string name;
    std::string path;
    rac_result_t status;
};

struct Ledger {
    std::mutex mu;
    std::vector<Entry> entries;
};

/* Meyers singleton — same rationale as the registry's own state(): avoids the
 * static initialization order fiasco when a plugin's static constructor
 * registers before main(). */
Ledger& ledger() {
    static Ledger instance;
    return instance;
}

/** Drop the entry for `name`, if any. Caller holds the lock. */
void forget_locked(Ledger& l, const std::string& name) {
    for (auto it = l.entries.begin(); it != l.entries.end(); ++it) {
        if (it->name == name) {
            l.entries.erase(it);
            return;
        }
    }
}

}  // namespace

extern "C" {

void rac_registry_record_plugin_unavailable(const char* name, const char* path,
                                            rac_result_t status) {
    /* C ABI boundary: noexcept in effect. std::string / std::vector below can
     * throw std::bad_alloc; a bookkeeping allocation failure must never
     * propagate into a caller that is already handling a plugin failure. */
    try {
        if (name == nullptr || name[0] == '\0')
            return;
        std::string key(name);
        auto& l = ledger();
        std::lock_guard<std::mutex> lock(l.mu);
        if (status == RAC_SUCCESS) {
            forget_locked(l, key);
            return;
        }
        for (auto& e : l.entries) {
            if (e.name == key) {
                e.path = path != nullptr ? path : "";
                e.status = status;
                return;
            }
        }
        l.entries.push_back(Entry{std::move(key), path != nullptr ? path : "", status});
        RAC_LOG_WARNING(LOG_CAT, "backend '%s' is unavailable (%d) — other backends keep serving",
                        name, static_cast<int>(status));
    } catch (...) {
        /* Ledger is best-effort telemetry; never let it fail a load path. */
    }
}

void rac_plugin_availability_forget(const char* name) RAC_PLUGIN_REGISTRY_NOEXCEPT {
    try {
        if (name == nullptr || name[0] == '\0')
            return;
        auto& l = ledger();
        std::lock_guard<std::mutex> lock(l.mu);
        forget_locked(l, std::string(name));
    } catch (...) {}
}

rac_result_t rac_registry_list_unavailable_plugins(rac_plugin_unavailable_t** out_items,
                                                   size_t* out_count) {
    try {
        if (out_items == nullptr || out_count == nullptr)
            return RAC_ERROR_NULL_POINTER;
        *out_items = nullptr;
        *out_count = 0;

        std::vector<Entry> snapshot;
        {
            auto& l = ledger();
            std::lock_guard<std::mutex> lock(l.mu);
            snapshot = l.entries;
        }
        if (snapshot.empty())
            return RAC_SUCCESS;

        /* Each entry owns its strings so the caller can outlive a concurrent
         * forget(). Allocated with new[]/strdup-style copies and released by
         * rac_registry_free_unavailable_plugins. */
        auto* items = new (std::nothrow) rac_plugin_unavailable_t[snapshot.size()];
        if (items == nullptr)
            return RAC_ERROR_OUT_OF_MEMORY;

        size_t filled = 0;
        for (const auto& e : snapshot) {
            char* name = new (std::nothrow) char[e.name.size() + 1];
            if (name == nullptr)
                break;
            std::char_traits<char>::copy(name, e.name.c_str(), e.name.size() + 1);

            char* path = nullptr;
            if (!e.path.empty()) {
                path = new (std::nothrow) char[e.path.size() + 1];
                if (path == nullptr) {
                    delete[] name;
                    break;
                }
                std::char_traits<char>::copy(path, e.path.c_str(), e.path.size() + 1);
            }
            items[filled].name = name;
            items[filled].path = path;
            items[filled].status = e.status;
            ++filled;
        }
        if (filled != snapshot.size()) {
            rac_registry_free_unavailable_plugins(items, filled);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        *out_items = items;
        *out_count = filled;
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

void rac_registry_free_unavailable_plugins(rac_plugin_unavailable_t* items, size_t count) {
    if (items == nullptr)
        return;
    for (size_t i = 0; i < count; ++i) {
        delete[] items[i].name;
        delete[] items[i].path;
    }
    delete[] items;
}

}  // extern "C"
