/**
 * HybridRunAnywhereCore+Storage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::vector<uint8_t> copyStorageArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
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

std::shared_ptr<ArrayBuffer> emptyStorageProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

using StorageProtoFn = decltype(&rac_storage_analyzer_info_proto);

std::shared_ptr<ArrayBuffer> copyStorageProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("storage proto error: %s", protoBuffer.error_message);
        }
        rac_proto_buffer_free(&protoBuffer);
        return emptyStorageProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        rac_proto_buffer_free(&protoBuffer);
        return emptyStorageProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    rac_proto_buffer_free(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callStorageProto(const std::vector<uint8_t>& requestBytes,
                                              StorageProtoFn fn,
                                              const char* operation) {
    auto storageHandle = StorageBridge::shared().getHandle();
    auto registryHandle = ModelRegistryBridge::shared().getHandle();
    if (!storageHandle || !registryHandle) {
        LOGE("%s: storage or registry not initialized", operation);
        return emptyStorageProtoBuffer();
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const uint8_t* requestData = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(
        storageHandle,
        registryHandle,
        requestData,
        requestBytes.size(),
        &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        rac_proto_buffer_free(&out);
        return emptyStorageProtoBuffer();
    }

    return copyStorageProtoBuffer(out);
}

} // namespace

// Storage
// ============================================================================
// Storage
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearCache() {
    return Promise<bool>::async([]() {
        LOGI("Clearing cache...");

        // Clear the model assignment cache (in-memory cache for model assignments)
        rac_model_assignment_clear_cache();

        // Cache directory only — temp lives behind cleanTempFiles(), matching
        // Swift's separated clearCache()/cleanTempFiles() entry points.
        FileManagerBridge::shared().clearCache();

        LOGI("Cache cleared successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cleanTempFiles() {
    return Promise<bool>::async([]() {
        LOGI("Clearing temp files...");
        FileManagerBridge::shared().clearTemp();
        LOGI("Temp files cleared successfully");
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageInfoProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            rac_storage_analyzer_info_proto,
            "storageInfoProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageAvailabilityProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            rac_storage_analyzer_availability_proto,
            "storageAvailabilityProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageDeletePlanProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            rac_storage_analyzer_delete_plan_proto,
            "storageDeletePlanProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageDeleteProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            rac_storage_analyzer_delete_proto,
            "storageDeleteProto");
    });
}

} // namespace margelo::nitro::runanywhere
