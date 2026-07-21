/**
 * @file rac_connect_transport.cpp
 * @brief Registry and dispatch for platform-provided Connect channels.
 */

#include "rac/connect/rac_connect_transport.h"

#include <memory>
#include <mutex>
#include <utility>

#include "rac/core/rac_logger.h"

namespace {

constexpr const char* kTag = "rac_connect_transport";

struct TransportSlot {
    rac_connect_transport_ops_t ops{};
    void* user_data = nullptr;

    ~TransportSlot() {
        if (ops.destroy != nullptr) {
            ops.destroy(user_data);
        }
    }
};

struct TransportRegistry {
    std::mutex mutex;
    std::shared_ptr<TransportSlot> active;
};

TransportRegistry& registry() {
    static TransportRegistry instance;
    return instance;
}

std::shared_ptr<TransportSlot> acquire_transport() {
    std::lock_guard<std::mutex> lock(registry().mutex);
    return registry().active;
}

rac_result_t validate_ops(const rac_connect_transport_ops_t* ops) {
    if (ops->abi_version != RAC_CONNECT_TRANSPORT_ABI_VERSION ||
        ops->struct_size < sizeof(rac_connect_transport_ops_t)) {
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    if (ops->open == nullptr || ops->send == nullptr || ops->receive == nullptr ||
        ops->close == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

}  // namespace

extern "C" {

rac_result_t rac_connect_transport_register(const rac_connect_transport_ops_t* ops,
                                            void* user_data) {
    if (ops == nullptr) {
        std::shared_ptr<TransportSlot> retiring;
        {
            std::lock_guard<std::mutex> lock(registry().mutex);
            retiring = std::move(registry().active);
        }
        retiring.reset();
        RAC_LOG_INFO(kTag, "Connect transport unregistered");
        return RAC_SUCCESS;
    }

    const rac_result_t validation = validate_ops(ops);
    if (validation != RAC_SUCCESS) {
        RAC_LOG_ERROR(kTag, "Connect transport rejected: invalid ABI or mandatory operation");
        return validation;
    }

    auto replacement = std::make_shared<TransportSlot>();
    replacement->ops = *ops;
    replacement->user_data = user_data;

    if (replacement->ops.init != nullptr) {
        const rac_result_t init_result = replacement->ops.init(user_data);
        if (init_result != RAC_SUCCESS) {
            RAC_LOG_ERROR(kTag, "Connect transport init failed: rc=%d",
                          static_cast<int>(init_result));
            return init_result;
        }
    }

    std::shared_ptr<TransportSlot> retiring;
    {
        std::lock_guard<std::mutex> lock(registry().mutex);
        retiring = std::move(registry().active);
        registry().active = replacement;
    }
    retiring.reset();

    RAC_LOG_INFO(kTag, "Connect transport registered");
    return RAC_SUCCESS;
}

rac_bool_t rac_connect_transport_is_registered(void) {
    std::lock_guard<std::mutex> lock(registry().mutex);
    return registry().active != nullptr ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_connect_transport_open(const rac_connect_endpoint_t* endpoint,
                                        rac_connect_channel_t* out_channel) {
    if (endpoint == nullptr || out_channel == nullptr ||
        (endpoint->data == nullptr && endpoint->size > 0)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_channel = RAC_CONNECT_INVALID_CHANNEL;

    const std::shared_ptr<TransportSlot> slot = acquire_transport();
    if (slot == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    const rac_result_t result = slot->ops.open(slot->user_data, endpoint, out_channel);
    if (result == RAC_SUCCESS && *out_channel == RAC_CONNECT_INVALID_CHANNEL) {
        return RAC_ERROR_PROCESSING_FAILED;
    }
    return result;
}

rac_result_t rac_connect_transport_send(rac_connect_channel_t channel, const uint8_t* payload,
                                        size_t payload_size) {
    if (channel == RAC_CONNECT_INVALID_CHANNEL || payload == nullptr || payload_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::shared_ptr<TransportSlot> slot = acquire_transport();
    if (slot == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }
    return slot->ops.send(slot->user_data, channel, payload, payload_size);
}

rac_result_t rac_connect_transport_receive(rac_connect_channel_t channel,
                                           rac_proto_buffer_t* out_payload) {
    if (channel == RAC_CONNECT_INVALID_CHANNEL || out_payload == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_proto_buffer_init(out_payload);

    const std::shared_ptr<TransportSlot> slot = acquire_transport();
    if (slot == nullptr) {
        rac_proto_buffer_set_error(out_payload, RAC_ERROR_ADAPTER_NOT_SET,
                                   "Connect transport adapter is not registered");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    const rac_result_t result = slot->ops.receive(slot->user_data, channel, out_payload);
    if (result != RAC_SUCCESS && out_payload->status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(out_payload, result, "Connect transport receive failed");
    }
    return result;
}

rac_result_t rac_connect_transport_close(rac_connect_channel_t channel) {
    if (channel == RAC_CONNECT_INVALID_CHANNEL) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::shared_ptr<TransportSlot> slot = acquire_transport();
    if (slot == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }
    return slot->ops.close(slot->user_data, channel);
}

}  // extern "C"
