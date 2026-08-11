/**
 * @file rac_cloud_stt_provider.cpp
 * @brief Atomic storage for the cross-SDK named cloud STT provider table.
 *
 * Mirrors rac_hybrid_custom_filter.cpp's atomic-swap/retire discipline. The
 * active table lives behind a std::atomic<const Snapshot*>. Each
 * register/unregister builds a FRESH immutable Snapshot (copy-on-write of the
 * entry vector with the one entry added / replaced / removed), swaps the
 * pointer atomically, and parks the previous snapshot in g_retired so the NEXT
 * mutation frees it — giving in-flight readers a one-generation reprieve.
 *
 * Memory ordering: acquire/release on the pointer swap suffices because a
 * published Snapshot is never mutated after publication. Readers
 * (rac_cloud_invoke_stt_provider / rac_cloud_has_stt_provider) load the pointer
 * once with acquire and scan that immutable copy.
 */

#include "rac/cloud/rac_cloud_stt_provider.h"

#include <atomic>
#include <cstring>
#include <new>
#include <string>
#include <vector>

namespace {

struct Entry {
    std::string name;
    rac_cloud_stt_transcribe_fn_t transcribe = nullptr;
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
// replaced (transcribe != nullptr) or removed (transcribe == nullptr). Returns
// nullptr only on allocation failure.
const Snapshot* build_next(const char* name, rac_cloud_stt_transcribe_fn_t transcribe,
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
                if (transcribe != nullptr) {
                    next->entries.push_back(Entry{e.name, transcribe, user_data});
                    replaced = true;
                }
                // transcribe == nullptr → drop this entry (unregister).
                continue;
            }
            next->entries.push_back(e);
        }
    }
    if (transcribe != nullptr && !replaced) {
        next->entries.push_back(Entry{std::string(name), transcribe, user_data});
    }
    return next;
}

}  // namespace

extern "C" {

rac_result_t rac_cloud_register_stt_provider(const char* name,
                                             rac_cloud_stt_transcribe_fn_t transcribe,
                                             void* user_data) {
    if (name == nullptr || name[0] == '\0' || transcribe == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (std::strlen(name) >= RAC_CLOUD_STT_PROVIDER_NAME_MAX) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const Snapshot* next = build_next(name, transcribe, user_data);
    if (next == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    publish(next);
    return RAC_SUCCESS;
}

rac_result_t rac_cloud_unregister_stt_provider(const char* name) {
    if (name == nullptr || name[0] == '\0') {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const Snapshot* next = build_next(name, /*transcribe=*/nullptr, /*user_data=*/nullptr);
    if (next == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    publish(next);
    return RAC_SUCCESS;
}

rac_bool_t rac_cloud_has_stt_provider(const char* name) {
    if (name == nullptr || name[0] == '\0') {
        return RAC_FALSE;
    }
    const Snapshot* snap = g_active.load(std::memory_order_acquire);
    if (snap != nullptr) {
        for (const auto& e : snap->entries) {
            if (e.name == name) {
                return RAC_TRUE;
            }
        }
    }
    return RAC_FALSE;
}

rac_result_t rac_cloud_invoke_stt_provider(const char* name, const char* config_json,
                                           const uint8_t* audio, size_t audio_len,
                                           int32_t audio_format, char** out_result_json) {
    if (name == nullptr || out_result_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_result_json = nullptr;
    const Snapshot* snap = g_active.load(std::memory_order_acquire);
    if (snap != nullptr) {
        for (const auto& e : snap->entries) {
            if (e.name == name) {
                return e.transcribe(config_json, audio, audio_len, audio_format, out_result_json,
                                    e.user_data);
            }
        }
    }
    return RAC_ERROR_NOT_FOUND;
}

void rac_cloud_stt_result_free(char* result_json) {
    std::free(result_json);
}

}  // extern "C"
