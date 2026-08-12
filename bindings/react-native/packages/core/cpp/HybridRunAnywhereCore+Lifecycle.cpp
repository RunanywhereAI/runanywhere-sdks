/**
 * HybridRunAnywhereCore+Lifecycle.cpp
 *
 * Proto-byte model lifecycle bindings backed by runanywhere-commons.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::vector<uint8_t> copyLifecycleArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }

    uint8_t* data = buffer->data();
    size_t size = buffer->size();
    if (!data || size == 0) {
        return bytes;
    }

    bytes.assign(data, data + size);
    return bytes;
}

std::shared_ptr<ArrayBuffer> emptyLifecycleProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

using LifecycleProtoFn = decltype(&rac_model_lifecycle_unload_proto);

std::shared_ptr<ArrayBuffer> copyLifecycleProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("lifecycle proto error: %s", protoBuffer.error_message);
        }
        rac_proto_buffer_free(&protoBuffer);
        return emptyLifecycleProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        rac_proto_buffer_free(&protoBuffer);
        return emptyLifecycleProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    rac_proto_buffer_free(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callLifecycleProto(const std::vector<uint8_t>& requestBytes,
                                                LifecycleProtoFn fn,
                                                const char* operation) {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const uint8_t* requestData = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(requestData, requestBytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        rac_proto_buffer_free(&out);
        return emptyLifecycleProtoBuffer();
    }
    return copyLifecycleProtoBuffer(out);
}

} // namespace

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::modelLifecycleLoadProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyLifecycleArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("modelLifecycleLoadProto: registry not initialized");
            return emptyLifecycleProtoBuffer();
        }

        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const uint8_t* requestData = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = rac_model_lifecycle_load_proto(
            registryHandle,
            requestData,
            bytes.size(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("modelLifecycleLoadProto: rc=%d", rc);
            rac_proto_buffer_free(&out);
            return emptyLifecycleProtoBuffer();
        }
        return copyLifecycleProtoBuffer(out);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::modelLifecycleUnloadProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyLifecycleArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLifecycleProto(
            bytes,
            rac_model_lifecycle_unload_proto,
            "modelLifecycleUnloadProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::currentModelProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyLifecycleArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLifecycleProto(
            bytes,
            rac_model_lifecycle_current_model_proto,
            "currentModelProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::componentLifecycleSnapshotProto(double component) {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([component]() {
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_component_lifecycle_snapshot_proto(
            static_cast<uint32_t>(component),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("componentLifecycleSnapshotProto: rc=%d", rc);
            rac_proto_buffer_free(&out);
            return emptyLifecycleProtoBuffer();
        }
        return copyLifecycleProtoBuffer(out);
    });
}

} // namespace margelo::nitro::runanywhere
