/**
 * HybridRunAnywhereCore+Lifecycle.cpp
 *
 * Proto-byte model lifecycle bindings backed by runanywhere-commons.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

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

std::shared_ptr<ArrayBuffer> copyLifecycleProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("lifecycle proto error: %s", protoBuffer.error_message);
        }
        proto_compat::freeBuffer(&protoBuffer);
        return emptyLifecycleProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyLifecycleProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callLifecycleProto(const std::vector<uint8_t>& requestBytes,
                                                const char* symbolName,
                                                const char* operation) {
    auto fn = proto_compat::symbol<proto_compat::ProtoBufferCallFn>(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyLifecycleProtoBuffer();
    }

    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* requestData = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(requestData, requestBytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
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
        proto_compat::initBuffer(&out);
        const uint8_t* requestData = bytes.empty() ? nullptr : bytes.data();
        auto loadProto =
            proto_compat::symbol<proto_compat::ModelLifecycleLoadProtoFn>(
                "rac_model_lifecycle_load_proto");
        if (!loadProto) {
            LOGE("modelLifecycleLoadProto: rac_model_lifecycle_load_proto unavailable");
            return emptyLifecycleProtoBuffer();
        }

        rac_result_t rc = loadProto(
            registryHandle,
            requestData,
            bytes.size(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("modelLifecycleLoadProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
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
            "rac_model_lifecycle_unload_proto",
            "modelLifecycleUnloadProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::currentModelProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyLifecycleArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLifecycleProto(
            bytes,
            "rac_model_lifecycle_current_model_proto",
            "currentModelProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::componentLifecycleSnapshotProto(double component) {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([component]() {
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        auto snapshotProto =
            proto_compat::symbol<proto_compat::ComponentLifecycleSnapshotProtoFn>(
                "rac_component_lifecycle_snapshot_proto");
        if (!snapshotProto) {
            LOGE("componentLifecycleSnapshotProto: rac_component_lifecycle_snapshot_proto unavailable");
            return emptyLifecycleProtoBuffer();
        }

        rac_result_t rc = snapshotProto(
            static_cast<uint32_t>(component),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("componentLifecycleSnapshotProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyLifecycleProtoBuffer();
        }
        return copyLifecycleProtoBuffer(out);
    });
}

} // namespace margelo::nitro::runanywhere
