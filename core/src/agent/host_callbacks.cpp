// SPDX-License-Identifier: Apache-2.0

#include "host_callbacks.h"

#include <cstring>
#include <mutex>

namespace rac::agent {
namespace {

struct State {
    std::mutex mutex;
    rac_agent_host_callbacks_t callbacks{};
};

State& state() {
    static State instance;
    return instance;
}

}  // namespace

rac_result_t set_host_callbacks(const rac_agent_host_callbacks_t* callbacks) {
    State& s = state();
    std::lock_guard<std::mutex> lock(s.mutex);

    if (callbacks == nullptr) {
        s.callbacks = rac_agent_host_callbacks_t{};
        return RAC_SUCCESS;
    }

    if (callbacks->abi_version != RAC_AGENT_HOST_CALLBACKS_ABI_VERSION ||
        callbacks->struct_size != sizeof(rac_agent_host_callbacks_t)) {
        rac_error_set_details("rac_agent_host_callbacks_t abi_version or struct_size mismatch");
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    s.callbacks = *callbacks;
    return RAC_SUCCESS;
}

rac_agent_host_callbacks_t host_callbacks() {
    State& s = state();
    std::lock_guard<std::mutex> lock(s.mutex);
    return s.callbacks;
}

}  // namespace rac::agent
