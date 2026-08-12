/**
 * @file rac_hybrid_custom_filter.cpp
 * @brief Atomic storage for the cross-SDK named custom-filter table.
 *
 * Mirrors rac_hybrid_device_state.cpp's atomic-swap/retire discipline. The
 * active table lives behind a std::atomic<const Snapshot*>. Each
 * register/unregister builds a FRESH immutable Snapshot (copy-on-write of the
 * entry vector with the one entry added / replaced / removed), swaps the
 * pointer atomically, and parks the previous snapshot in g_retired so the
 * NEXT mutation frees it — giving in-flight readers a one-generation reprieve
 * exactly like the device-state vtable.
 *
 * Where device-state publishes ONE ops struct, this publishes a whole entry
 * list because a policy may carry several distinct named custom filters; the
 * memory-ordering and lifetime rules are otherwise identical.
 *
 * Memory ordering: acquire/release on the pointer swap suffices because a
 * published Snapshot is never mutated after publication — mutations always
 * allocate a new one. Readers (rac_hybrid_invoke_custom_filter) load the
 * pointer once with acquire and scan that immutable copy.
 */

#include "rac/router/hybrid/rac_hybrid_custom_filter.h"

#include <atomic>
#include <cstring>
#include <new>
#include <string>
#include <vector>

namespace {

struct Entry {
    std::string name;
    rac_hybrid_custom_filter_predicate_t predicate = nullptr;
    void* user_data = nullptr;
};

// Immutable once published. Mutations allocate a fresh Snapshot rather than
// editing a live one, so concurrent readers always observe a consistent list.
struct Snapshot {
    std::vector<Entry> entries;
};

std::atomic<const Snapshot*> g_active{nullptr};
std::atomic<const Snapshot*> g_retired{nullptr};

// Swap in `next`, parking the previous active snapshot for one generation
// before freeing it (in-flight readers may still hold the prior pointer).
void publish(const Snapshot* next) {
    const Snapshot* prev = g_active.exchange(next, std::memory_order_acq_rel);
    const Snapshot* old_retired = g_retired.exchange(prev, std::memory_order_acq_rel);
    delete old_retired;
}

// Build the next snapshot from the current one with `name`'s entry inserted or
// replaced (predicate != nullptr) or removed (predicate == nullptr). Returns
// nullptr only on allocation failure.
const Snapshot* build_next(const char* name, rac_hybrid_custom_filter_predicate_t predicate,
                           void* user_data) {
    auto* next = new (std::nothrow) Snapshot();
    if (next == nullptr) {
        return nullptr;
    }
    const Snapshot* cur = g_active.load(std::memory_order_acquire);
    bool replaced = false;
    if (cur != nullptr) {
        next->entries.reserve(cur->entries.size() + 1);
        for (const auto& e : cur->entries) {
            if (e.name == name) {
                if (predicate != nullptr) {
                    next->entries.push_back(Entry{e.name, predicate, user_data});
                    replaced = true;
                }
                // predicate == nullptr → drop this entry (unregister).
                continue;
            }
            next->entries.push_back(e);
        }
    }
    if (predicate != nullptr && !replaced) {
        next->entries.push_back(Entry{std::string(name), predicate, user_data});
    }
    return next;
}

}  // namespace

extern "C" {

rac_result_t rac_hybrid_register_custom_filter(const char* name,
                                               rac_hybrid_custom_filter_predicate_t predicate,
                                               void* user_data) {
    if (name == nullptr || name[0] == '\0' || predicate == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (std::strlen(name) >= RAC_HYBRID_CUSTOM_FILTER_NAME_MAX) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const Snapshot* next = build_next(name, predicate, user_data);
    if (next == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    publish(next);
    return RAC_SUCCESS;
}

rac_result_t rac_hybrid_unregister_custom_filter(const char* name) {
    if (name == nullptr || name[0] == '\0') {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const Snapshot* next = build_next(name, /*predicate=*/nullptr, /*user_data=*/nullptr);
    if (next == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    publish(next);
    return RAC_SUCCESS;
}

rac_result_t rac_hybrid_invoke_custom_filter(const char* name,
                                             const rac_hybrid_routing_context_t* ctx,
                                             rac_bool_t* out_pass) {
    if (name == nullptr || ctx == nullptr || out_pass == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    const Snapshot* snap = g_active.load(std::memory_order_acquire);
    if (snap != nullptr) {
        for (const auto& e : snap->entries) {
            if (e.name == name) {
                *out_pass = e.predicate(ctx, e.user_data);
                return RAC_SUCCESS;
            }
        }
    }
    return RAC_ERROR_NOT_FOUND;
}

}  // extern "C"
