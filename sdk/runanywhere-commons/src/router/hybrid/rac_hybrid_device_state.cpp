/**
 * @file rac_hybrid_device_state.cpp
 * @brief Atomic storage for the cross-SDK device-state vtable.
 *
 * The active vtable pointer lives behind a std::atomic. Set copies the
 * caller's ops into a heap allocation, swaps the pointer atomically,
 * and retires the previous heap slot. Unset swaps back to the static
 * default vtable and retires the previous heap slot.
 *
 * Get-snapshot loads the active pointer once, invokes the three
 * callbacks against it, and packs the result into a value struct so
 * the caller never holds a raw vtable pointer past the snapshot scope.
 *
 * Memory ordering: acquire/release on the pointer swap is sufficient
 * because the ops struct contents are constants once published —
 * bindings never mutate a published struct. Subsequent setters publish
 * a fresh heap allocation rather than editing the live one.
 *
 * Lifecycle: when set/unset is called while a request thread is
 * mid-callback, that thread holds a pointer copy from a prior atomic
 * load — we can't free the previous slot immediately. The previous
 * slot is parked in g_retired; the NEXT set/unset call frees it. This
 * gives in-flight readers a one-generation reprieve. Bindings that
 * need stricter quiescence MUST pair their unset with their own
 * synchronization before releasing the binding-owned user_data (see
 * the @warning in the header).
 */

#include "rac/routing/rac_hybrid_device_state.h"

#include <atomic>
#include <new>

namespace {

bool default_is_online(void*) {
    return true;
}

int32_t default_battery_percent(void*) {
    return 100;
}

bool default_is_thermal_throttled(void*) {
    return false;
}

const rac_hybrid_device_state_ops_t kDefaultOps = {
    /* is_online            */ default_is_online,
    /* battery_percent      */ default_battery_percent,
    /* is_thermal_throttled */ default_is_thermal_throttled,
    /* user_data            */ nullptr,
};

std::atomic<const rac_hybrid_device_state_ops_t*> g_active{&kDefaultOps};
std::atomic<const rac_hybrid_device_state_ops_t*> g_retired{nullptr};

void publish(const rac_hybrid_device_state_ops_t* next) {
    const auto* prev = g_active.exchange(next, std::memory_order_acq_rel);
    const auto* heap_prev = (prev == &kDefaultOps) ? nullptr : prev;
    const auto* old_retired = g_retired.exchange(heap_prev, std::memory_order_acq_rel);
    delete old_retired;
}

}  // namespace

extern "C" {

rac_result_t rac_hybrid_set_device_state(const rac_hybrid_device_state_ops_t* ops) {
    if (ops == nullptr) {
        publish(&kDefaultOps);
        return RAC_SUCCESS;
    }
    if (ops->is_online == nullptr || ops->battery_percent == nullptr ||
        ops->is_thermal_throttled == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    auto* copy = new (std::nothrow) rac_hybrid_device_state_ops_t(*ops);
    if (copy == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    publish(copy);
    return RAC_SUCCESS;
}

rac_result_t rac_hybrid_get_device_state_snapshot(rac_hybrid_device_state_snapshot_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const auto* ops = g_active.load(std::memory_order_acquire);
    if (ops == nullptr) {
        ops = &kDefaultOps;
    }
    out->is_online = ops->is_online(ops->user_data);
    out->battery_percent = ops->battery_percent(ops->user_data);
    // Reserved for future thermal-aware routing; not yet consumed by any filter.
    // rac_hybrid_routing_context_t has no thermal field, so no routing decision
    // reads this today — it is collected ahead of a planned thermal filter.
    out->thermal_throttled = ops->is_thermal_throttled(ops->user_data);
    return RAC_SUCCESS;
}

}  // extern "C"