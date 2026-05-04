/**
 * @file rac_http_transport.cpp
 * @brief Platform HTTP transport registry (v2 close-out Phase H2).
 *
 * Holds a process-wide pointer to a platform-provided HTTP transport
 * vtable. The `rac_http_request_*` entry points consult this registry
 * before dispatching to libcurl — when an adapter is installed, calls
 * are routed through it; otherwise the libcurl default runs.
 *
 * Thread-safety: every public entry point takes an internal mutex.
 * The accessor used by the router (`rac_internal::get_http_transport`)
 * takes a snapshot of the current pointers under the same lock so the
 * caller can release the lock before invoking adapter callbacks
 * (avoids cross-library reentrancy deadlocks).
 */

#include "rac/infrastructure/http/rac_http_transport.h"

#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace {

constexpr const char* kTag = "rac_http_transport";

struct State {
    std::mutex mu;
    const rac_http_transport_ops_t* ops = nullptr;
    void* user_data = nullptr;
};

State& state() {
    static State s;
    return s;
}

}  // namespace

// =============================================================================
// Public C ABI
// =============================================================================

extern "C" rac_result_t rac_http_transport_register(const rac_http_transport_ops_t* ops,
                                                    void* user_data) {
    // Capture the previous adapter so we can run `destroy` *outside* the
    // registration lock. Adapters might acquire their own locks during
    // teardown — holding ours while calling them would deadlock.
    const rac_http_transport_ops_t* prev_ops = nullptr;
    void* prev_ud = nullptr;

    {
        std::lock_guard<std::mutex> lock(state().mu);
        prev_ops = state().ops;
        prev_ud = state().user_data;
        state().ops = nullptr;
        state().user_data = nullptr;
    }

    if (prev_ops && prev_ops->destroy) {
        prev_ops->destroy(prev_ud);
    }

    // Registering NULL is the explicit "unregister" path.
    if (ops == nullptr) {
        RAC_LOG_INFO(kTag, "Platform HTTP transport unregistered; falling back to libcurl");
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

    {
        std::lock_guard<std::mutex> lock(state().mu);
        state().ops = ops;
        state().user_data = user_data;
    }

    RAC_LOG_INFO(kTag, "Platform HTTP transport registered");
    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_http_transport_is_registered(void) {
    std::lock_guard<std::mutex> lock(state().mu);
    return state().ops != nullptr ? RAC_TRUE : RAC_FALSE;
}

// =============================================================================
// Internal accessor (not in the public header). Used by
// rac_http_client_curl.cpp to decide whether to route through the
// registered platform transport or fall through to libcurl.
// =============================================================================

namespace rac_internal {

bool get_http_transport(const rac_http_transport_ops_t** out_ops, void** out_user_data) {
    std::lock_guard<std::mutex> lock(state().mu);
    if (!state().ops) {
        return false;
    }
    if (out_ops) {
        *out_ops = state().ops;
    }
    if (out_user_data) {
        *out_user_data = state().user_data;
    }
    return true;
}

}  // namespace rac_internal
