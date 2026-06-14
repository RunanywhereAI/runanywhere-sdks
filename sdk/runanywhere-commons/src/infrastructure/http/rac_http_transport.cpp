/**
 * @file rac_http_transport.cpp
 * @brief Platform HTTP transport registry.
 *
 * Holds a process-wide pointer to a platform-provided HTTP transport
 * vtable. The `rac_http_request_*` entry points consult this registry
 * before dispatching. When an adapter is installed, calls are routed
 * through it; otherwise the public HTTP calls report
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE`.
 *
 * Thread-safety: every public entry point takes an internal mutex.
 * The accessor used by the router (`rac_internal::get_http_transport`)
 * takes a snapshot of the current pointers under the same lock so the
 * caller can release the lock before invoking adapter callbacks
 * (avoids cross-library reentrancy deadlocks).
 *
 * Previously the snapshot pattern allowed
 * `prev_ops->destroy(prev_ud)` in `register()` to race with an in-flight
 * `request_send(ud)` on another thread — the caller had a stale pointer
 * to a now-freed `user_data`. The registry now wraps {ops, user_data}
 * in a refcounted slot; callers acquire a reference via
 * `get_http_transport`, which atomically bumps the refcount, and
 * `register()` defers the previous slot's `destroy()` until that
 * slot's refcount drops to zero (i.e. every in-flight caller has
 * `put_http_transport`-d). Each request thus owns the user_data for
 * the entire duration of its adapter call.
 */

#include "rac/infrastructure/http/rac_http_transport.h"

#include "rac_http_transport_ref.h"

#include <cstddef>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace {

constexpr const char* kTag = "rac_http_transport";

/// Refcounted snapshot of a registered transport. The `active` bit owns
/// one reference while this slot is the currently-installed transport;
/// every in-flight caller owns one additional reference. Once both
/// drop to zero, the adapter's `destroy(user_data)` runs.
struct Slot {
    const rac_http_transport_ops_t* ops = nullptr;
    void* user_data = nullptr;
    int refs = 0;
    bool active = false;
};

struct Registry {
    std::mutex mu;
    std::shared_ptr<Slot> active;
};

Registry& registry() {
    static Registry r;
    return r;
}

/// Per-thread stack of slot handles handed out by `get_http_transport`
/// and consumed by `put_http_transport`. Modeling it as a stack means
/// nested acquires (which shouldn't happen but are cheap to permit)
/// stay paired correctly.
std::vector<std::shared_ptr<Slot>>& in_flight_stack() {
    thread_local std::vector<std::shared_ptr<Slot>> s;
    return s;
}

/// Drop a refcount on `slot`. If this was the last reference AND the
/// slot is no longer active, run the adapter's `destroy(user_data)`
/// outside the registry lock so adapter teardown can take its own
/// locks without risking a cross-library deadlock.
void release_slot(const std::shared_ptr<Slot>& slot) {
    if (!slot) {
        return;
    }
    bool run_destroy = false;
    const rac_http_transport_ops_t* dying_ops = nullptr;
    void* dying_ud = nullptr;
    {
        std::lock_guard<std::mutex> lock(registry().mu);
        --slot->refs;
        if (slot->refs == 0 && !slot->active) {
            run_destroy = true;
            dying_ops = slot->ops;
            dying_ud = slot->user_data;
            slot->ops = nullptr;
            slot->user_data = nullptr;
        }
    }
    if (run_destroy && dying_ops && dying_ops->destroy) {
        dying_ops->destroy(dying_ud);
    }
}

}  // namespace

// =============================================================================
// Public C ABI
// =============================================================================

extern "C" rac_result_t rac_http_transport_register(const rac_http_transport_ops_t* ops,
                                                    void* user_data) {
    // Retire the previous slot first. The slot's destroy runs only after
    // every outstanding `get_http_transport` caller has paired its put;
    // an in-flight `request_send(prev_ud)` therefore cannot observe a
    // freed user_data.
    std::shared_ptr<Slot> retiring;
    {
        std::lock_guard<std::mutex> lock(registry().mu);
        retiring = std::move(registry().active);
        registry().active = nullptr;
        if (retiring) {
            retiring->active = false;
        }
    }
    // Drop the "active" reference (may trigger destroy immediately if
    // there are no in-flight callers).
    release_slot(retiring);

    // Registering NULL is the explicit "unregister" path.
    if (ops == nullptr) {
        RAC_LOG_INFO(kTag, "Platform HTTP transport unregistered; no HTTP fallback is installed");
        return RAC_SUCCESS;
    }

    // The send entry point is mandatory — without it the adapter is
    // useless and we refuse to install it.
    if (ops->request_send == nullptr) {
        RAC_LOG_ERROR(kTag, "Platform transport rejected: request_send is NULL");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Give the adapter a chance to initialize before we accept traffic.
    if (ops->init) {
        rac_result_t rc = ops->init(user_data);
        if (rc != RAC_SUCCESS) {
            RAC_LOG_ERROR(kTag, "Platform transport init failed: rc=%d", static_cast<int>(rc));
            if (ops->destroy) {
                ops->destroy(user_data);
            }
            return rc;
        }
    }

    auto slot = std::make_shared<Slot>();
    slot->ops = ops;
    slot->user_data = user_data;
    slot->active = true;
    slot->refs = 1;  // the "active" reference

    {
        std::lock_guard<std::mutex> lock(registry().mu);
        registry().active = std::move(slot);
    }

    RAC_LOG_INFO(kTag, "Platform HTTP transport registered");
    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_http_transport_is_registered(void) {
    std::lock_guard<std::mutex> lock(registry().mu);
    return registry().active ? RAC_TRUE : RAC_FALSE;
}

// =============================================================================
// Internal accessor (not in the public header). Used by
// rac_http_client_default.cpp / rac_http_client_emscripten.cpp to
// dispatch a single HTTP operation while keeping the adapter's
// user_data alive for the call's full duration. Every successful
// `get_http_transport` must be paired with `put_http_transport`;
// dispatch sites acquire the pair through the `rac_internal::TransportRef`
// RAII guard (rac_http_transport_ref.h) so the contract holds on every
// exit path.
// =============================================================================

namespace rac_internal {

bool get_http_transport(const rac_http_transport_ops_t** out_ops, void** out_user_data) {
    std::shared_ptr<Slot> slot;
    {
        std::lock_guard<std::mutex> lock(registry().mu);
        if (!registry().active) {
            return false;
        }
        slot = registry().active;
        ++slot->refs;
    }
    if (out_ops) {
        *out_ops = slot->ops;
    }
    if (out_user_data) {
        *out_user_data = slot->user_data;
    }
    in_flight_stack().push_back(std::move(slot));
    return true;
}

void put_http_transport() {
    auto& stack = in_flight_stack();
    if (stack.empty()) {
        return;
    }
    std::shared_ptr<Slot> slot = std::move(stack.back());
    stack.pop_back();
    release_slot(slot);
}

}  // namespace rac_internal
