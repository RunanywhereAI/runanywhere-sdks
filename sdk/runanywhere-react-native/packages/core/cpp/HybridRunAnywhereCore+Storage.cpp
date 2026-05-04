/**
 * HybridRunAnywhereCore+Storage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

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

std::shared_ptr<ArrayBuffer> copyStorageProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("storage proto error: %s", protoBuffer.error_message);
        }
        proto_compat::freeBuffer(&protoBuffer);
        return emptyStorageProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyStorageProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callStorageProto(const std::vector<uint8_t>& requestBytes,
                                              const char* symbolName,
                                              const char* operation) {
    auto storageHandle = StorageBridge::shared().getHandle();
    auto registryHandle = ModelRegistryBridge::shared().getHandle();
    if (!storageHandle || !registryHandle) {
        LOGE("%s: storage or registry not initialized", operation);
        return emptyStorageProtoBuffer();
    }

    auto fn = proto_compat::symbol<proto_compat::StorageProtoFn>(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyStorageProtoBuffer();
    }

    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* requestData = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(
        storageHandle,
        registryHandle,
        requestData,
        requestBytes.size(),
        &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyStorageProtoBuffer();
    }

    return copyStorageProtoBuffer(out);
}

} // namespace

// Storage
// ============================================================================
// Storage
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getStorageInfo() {
    return Promise<std::string>::async([]() {
        // Accurate device + app storage comes from FileManagerBridge (POSIX).
        // Always works once initialize() has been called.
        auto fmInfo = FileManagerBridge::shared().getStorageInfo();

        // Model count is a best-effort lookup from the registry. If the registry
        // isn't initialized yet (e.g. SDK.initialize() hasn't finished), fall
        // back to 0 rather than failing the whole call — device storage still
        // needs to render in the UI.
        size_t modelCount = 0;
        try {
            auto registryHandle = ModelRegistryBridge::shared().getHandle();
            if (registryHandle != nullptr) {
                auto storageInfo = StorageBridge::shared().analyzeStorage(registryHandle);
                modelCount = storageInfo.models.size();
            }
        } catch (...) {
            // Registry unavailable — device storage still returned below.
        }

        return buildJsonObject({
            {"totalDeviceSpace", std::to_string(fmInfo.device_total)},
            {"freeDeviceSpace", std::to_string(fmInfo.device_free)},
            {"usedDeviceSpace", std::to_string(fmInfo.device_total - fmInfo.device_free)},
            {"documentsSize", std::to_string(fmInfo.models_size)},
            {"cacheSize", std::to_string(fmInfo.cache_size)},
            {"appSupportSize", std::to_string(fmInfo.temp_size)},
            {"totalAppSize", std::to_string(fmInfo.total_app_size)},
            {"totalModelsSize", std::to_string(fmInfo.models_size)},
            {"modelCount", std::to_string(modelCount)}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearCache() {
    return Promise<bool>::async([]() {
        LOGI("Clearing cache...");

        // Clear the model assignment cache (in-memory cache for model assignments)
        rac_model_assignment_clear_cache();

        // Clear file cache and temp directories via C++ file manager
        FileManagerBridge::shared().clearCache();
        FileManagerBridge::shared().clearTemp();

        LOGI("Cache cleared successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::deleteModel(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() {
        LOGI("Deleting model: %s", modelId.c_str());

        // Get framework from registry before removing, so we can delete files
        auto modelInfo = ModelRegistryBridge::shared().getModel(modelId);
        int framework = modelInfo ? static_cast<int>(modelInfo->framework) : -1;

        // Remove from registry
        rac_result_t result = ModelRegistryBridge::shared().removeModel(modelId);

        // Delete files from disk
        if (framework >= 0) {
            FileManagerBridge::shared().deleteModel(modelId, framework);
        }

        return result == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageInfoProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            "rac_storage_analyzer_info_proto",
            "storageInfoProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageAvailabilityProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            "rac_storage_analyzer_availability_proto",
            "storageAvailabilityProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageDeletePlanProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            "rac_storage_analyzer_delete_plan_proto",
            "storageDeletePlanProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::storageDeleteProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyStorageArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callStorageProto(
            bytes,
            "rac_storage_analyzer_delete_proto",
            "storageDeleteProto");
    });
}

} // namespace margelo::nitro::runanywhere
