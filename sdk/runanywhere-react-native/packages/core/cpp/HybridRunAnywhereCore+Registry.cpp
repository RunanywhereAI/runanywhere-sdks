/**
 * HybridRunAnywhereCore+Registry.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * Bridge classification:
 *   - SDK-facing pass-through: getAvailableModelsProto, getModelInfoProto,
 *     registerModelProto, updateModelProto, removeModelProto,
 *     queryModelsProto, getDownloadedModelsProto. These thunk to the
 *     `rac_model_registry_*_proto` C ABI; the per-platform symbol
 *     resolution (`#if defined(__APPLE__)` direct call vs proto_compat
 *     dlsym lookup on Android) is the only logic and is required because
 *     Apple links commons statically.
 *   - importModelProto mirrors Swift's RAModelImportRequest route for
 *     platform-normalized local paths after downloads or file-picker flows.
 *   - refreshModelRegistry(includeRemoteCatalog, rescanLocal, pruneOrphans)
 *     hand-encodes the three bool fields into a ModelRegistryRefreshRequest
 *     protobuf message (no protobuf runtime is linked in this bridge) and
 *     routes through the canonical `rac_model_registry_refresh_proto`. The
 *     legacy struct-opts `rac_model_registry_refresh` entry point has been
 *     removed from commons.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Model Registry and Compatibility
// ============================================================================
// Model Registry
// ============================================================================

namespace {

std::vector<uint8_t> copyArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
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

std::shared_ptr<ArrayBuffer> emptyProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

void freeRegistryProtoBytes(uint8_t* protoBytes) {
    if (!protoBytes) {
        return;
    }

#if defined(__APPLE__)
    // iOS links RACommons as a static xcframework. Its symbols are available
    // to the linker, but not reliably discoverable through dlsym(RTLD_DEFAULT).
    rac_model_registry_proto_free(protoBytes);
#else
    if (auto freeFn =
            proto_compat::symbol<proto_compat::RegistryProtoFreeFn>(
                "rac_model_registry_proto_free")) {
        freeFn(protoBytes);
    } else {
        std::free(protoBytes);
    }
#endif
}

rac_result_t registryGetProto(
    rac_model_registry_handle_t registryHandle,
    const char* modelId,
    uint8_t** protoBytes,
    size_t* protoSize) {
#if defined(__APPLE__)
    return rac_model_registry_get_proto(
        registryHandle,
        modelId,
        protoBytes,
        protoSize);
#else
    auto getProto =
        proto_compat::symbol<proto_compat::RegistryGetProtoFn>(
            "rac_model_registry_get_proto");
    if (!getProto) {
        LOGE("getModelInfoProto: rac_model_registry_get_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return getProto(registryHandle, modelId, protoBytes, protoSize);
#endif
}

rac_result_t registryListProto(
    rac_model_registry_handle_t registryHandle,
    uint8_t** protoBytes,
    size_t* protoSize) {
#if defined(__APPLE__)
    return rac_model_registry_list_proto(registryHandle, protoBytes, protoSize);
#else
    auto listProto =
        proto_compat::symbol<proto_compat::RegistryListProtoFn>(
            "rac_model_registry_list_proto");
    if (!listProto) {
        LOGE("getAvailableModelsProto: rac_model_registry_list_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return listProto(registryHandle, protoBytes, protoSize);
#endif
}

rac_result_t registryWriteProto(
    const char* operation,
    const char* symbolName,
    rac_model_registry_handle_t registryHandle,
    const uint8_t* bytes,
    size_t size) {
#if defined(__APPLE__)
    if (std::strcmp(symbolName, "rac_model_registry_register_proto") == 0) {
        return rac_model_registry_register_proto(registryHandle, bytes, size);
    }
    return rac_model_registry_update_proto(registryHandle, bytes, size);
#else
    auto writeProto =
        proto_compat::symbol<proto_compat::RegistryWriteProtoFn>(symbolName);
    if (!writeProto) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return writeProto(registryHandle, bytes, size);
#endif
}

rac_result_t registryRemoveProto(
    rac_model_registry_handle_t registryHandle,
    const char* modelId) {
#if defined(__APPLE__)
    return rac_model_registry_remove_proto(registryHandle, modelId);
#else
    auto removeProto =
        proto_compat::symbol<proto_compat::RegistryRemoveProtoFn>(
            "rac_model_registry_remove_proto");
    if (!removeProto) {
        LOGE("removeModelProto: rac_model_registry_remove_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return removeProto(registryHandle, modelId);
#endif
}

rac_result_t registryQueryProto(
    rac_model_registry_handle_t registryHandle,
    const uint8_t* queryBytes,
    size_t querySize,
    uint8_t** protoBytes,
    size_t* protoSize) {
#if defined(__APPLE__)
    return rac_model_registry_query_proto(
        registryHandle,
        queryBytes,
        querySize,
        protoBytes,
        protoSize);
#else
    auto queryProto =
        proto_compat::symbol<proto_compat::RegistryQueryProtoFn>(
            "rac_model_registry_query_proto");
    if (!queryProto) {
        LOGE("queryModelsProto: rac_model_registry_query_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return queryProto(
        registryHandle,
        queryBytes,
        querySize,
        protoBytes,
        protoSize);
#endif
}

rac_result_t registryListDownloadedProto(
    rac_model_registry_handle_t registryHandle,
    uint8_t** protoBytes,
    size_t* protoSize) {
#if defined(__APPLE__)
    return rac_model_registry_list_downloaded_proto(
        registryHandle,
        protoBytes,
        protoSize);
#else
    auto listDownloadedProto =
        proto_compat::symbol<proto_compat::RegistryListProtoFn>(
            "rac_model_registry_list_downloaded_proto");
    if (!listDownloadedProto) {
        LOGE("getDownloadedModelsProto: rac_model_registry_list_downloaded_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return listDownloadedProto(registryHandle, protoBytes, protoSize);
#endif
}

rac_result_t registryRequestProto(
    const char* operation,
    const char* symbolName,
    rac_model_registry_handle_t registryHandle,
    const uint8_t* bytes,
    size_t size,
    rac_proto_buffer_t* outResult) {
#if defined(__APPLE__)
    if (std::strcmp(symbolName, "rac_model_registry_import_proto") == 0) {
        return rac_model_registry_import_proto(
            registryHandle,
            bytes,
            size,
            outResult);
    }
    LOGE("%s: unsupported Apple registry request symbol %s",
         operation,
         symbolName);
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    auto requestProto =
        proto_compat::symbol<proto_compat::RegistryRequestProtoFn>(symbolName);
    if (!requestProto) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return requestProto(registryHandle, bytes, size, outResult);
#endif
}

rac_result_t registerFromUrlProto(
    const uint8_t* bytes,
    size_t size,
    rac_proto_buffer_t* outResult) {
#if defined(__APPLE__)
    return rac_register_model_from_url_proto(bytes, size, outResult);
#else
    auto registerProto =
        proto_compat::symbol<proto_compat::RegisterModelFromUrlProtoFn>(
            "rac_register_model_from_url_proto");
    if (!registerProto) {
        LOGE("registerModelFromUrlProto: rac_register_model_from_url_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return registerProto(bytes, size, outResult);
#endif
}

std::shared_ptr<ArrayBuffer> ownedProtoBuffer(uint8_t* protoBytes, size_t protoSize) {
    if (!protoBytes || protoSize == 0) {
        freeRegistryProtoBytes(protoBytes);
        return emptyProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBytes, protoSize);
    freeRegistryProtoBytes(protoBytes);
    return buffer;
}

std::shared_ptr<ArrayBuffer> ownedRegistryBuffer(
    const char* operation,
    rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("%s proto error: %s", operation, protoBuffer.error_message);
        }
        proto_compat::freeBuffer(&protoBuffer);
        return emptyProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

} // namespace

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getAvailableModelsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("getAvailableModelsProto: registry not initialized");
            return emptyProtoBuffer();
        }

        uint8_t* protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryListProto(
            registryHandle,
            &protoBytes,
            &protoSize);
        if (rc != RAC_SUCCESS) {
            LOGE("getAvailableModelsProto: rc=%d", rc);
            return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getModelInfoProto(const std::string& modelId) {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([modelId]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("getModelInfoProto: registry not initialized");
            return emptyProtoBuffer();
        }

        uint8_t* protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryGetProto(
            registryHandle,
            modelId.c_str(),
            &protoBytes,
            &protoSize);
        if (rc != RAC_SUCCESS) {
            if (rc != RAC_ERROR_NOT_FOUND) {
                LOGE("getModelInfoProto: model=%s rc=%d", modelId.c_str(), rc);
            }
            return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerModelProto(
    const std::shared_ptr<ArrayBuffer>& modelInfoBytes) {
    auto bytes = copyArrayBufferBytes(modelInfoBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("registerModelProto: registry not initialized");
            return false;
        }
        if (bytes.empty()) {
            LOGE("registerModelProto: empty payload");
            return false;
        }

        rac_result_t rc = registryWriteProto(
            "registerModelProto",
            "rac_model_registry_register_proto",
            registryHandle,
            bytes.data(),
            bytes.size());
        if (rc != RAC_SUCCESS) {
            LOGE("registerModelProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::registerModelFromUrlProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
        // rac_register_model_from_url_proto resolves the global registry
        // (rac_get_model_registry()) internally; the bridge handle gate just
        // fails fast before init, matching the other registry thunks.
        if (!ModelRegistryBridge::shared().getHandle()) {
            LOGE("registerModelFromUrlProto: registry not initialized");
            return emptyProtoBuffer();
        }

        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = registerFromUrlProto(bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS) {
            LOGE("registerModelFromUrlProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyProtoBuffer();
        }

        return ownedRegistryBuffer("registerModelFromUrlProto", out);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::updateModelProto(
    const std::shared_ptr<ArrayBuffer>& modelInfoBytes) {
    auto bytes = copyArrayBufferBytes(modelInfoBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("updateModelProto: registry not initialized");
            return false;
        }
        if (bytes.empty()) {
            LOGE("updateModelProto: empty payload");
            return false;
        }

        rac_result_t rc = registryWriteProto(
            "updateModelProto",
            "rac_model_registry_update_proto",
            registryHandle,
            bytes.data(),
            bytes.size());
        if (rc != RAC_SUCCESS) {
            LOGE("updateModelProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::removeModelProto(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("removeModelProto: registry not initialized");
            return false;
        }

        rac_result_t rc = registryRemoveProto(
            registryHandle,
            modelId.c_str());
        if (rc != RAC_SUCCESS) {
            LOGE("removeModelProto: model=%s rc=%d", modelId.c_str(), rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::queryModelsProto(const std::shared_ptr<ArrayBuffer>& queryBytes) {
    auto bytes = copyArrayBufferBytes(queryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("queryModelsProto: registry not initialized");
            return emptyProtoBuffer();
        }
        if (bytes.empty()) {
            LOGE("queryModelsProto: empty payload");
            return emptyProtoBuffer();
        }

        uint8_t* protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryQueryProto(
            registryHandle,
            bytes.data(),
            bytes.size(),
            &protoBytes,
            &protoSize);
        if (rc != RAC_SUCCESS) {
            LOGE("queryModelsProto: rc=%d", rc);
            return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getDownloadedModelsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("getDownloadedModelsProto: registry not initialized");
            return emptyProtoBuffer();
        }

        uint8_t* protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryListDownloadedProto(
            registryHandle,
            &protoBytes,
            &protoSize);
        if (rc != RAC_SUCCESS) {
            LOGE("getDownloadedModelsProto: rc=%d", rc);
            return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::importModelProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("importModelProto: registry not initialized");
            return emptyProtoBuffer();
        }
        if (bytes.empty()) {
            LOGE("importModelProto: empty payload");
            return emptyProtoBuffer();
        }

        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = registryRequestProto(
            "importModelProto",
            "rac_model_registry_import_proto",
            registryHandle,
            bytes.data(),
            bytes.size(),
            &out);
        if (rc != RAC_SUCCESS) {
            LOGE("importModelProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyProtoBuffer();
        }

        return ownedRegistryBuffer("importModelProto", out);
    });
}

// ============================================================================
// Refresh — delegates to rac_model_registry_refresh_proto in commons.
//
// The RN C++ bridge has no protobuf runtime linked, so we hand-encode the
// minimal ModelRegistryRefreshRequest (three bool fields) into protobuf wire
// format and pass the bytes through the proto entry point. proto3 omits
// default-valued (false) fields, so an all-false request serializes to zero
// bytes, which is a valid empty message. rescan_local / prune_orphans are
// honoured at the C ABI layer (commons runs the adapter rescan when the
// file_list_directory slot is populated).
// ============================================================================

namespace {

// Encode field `fieldNumber` (a proto bool, wire type 0/varint) as `true`.
// Skipped entirely when the value is false per proto3 default-field omission.
void appendRefreshBoolField(std::vector<uint8_t>& out, uint32_t fieldNumber,
                            bool value) {
    if (!value) {
        return;
    }
    out.push_back(static_cast<uint8_t>((fieldNumber << 3) | 0x00));  // tag
    out.push_back(0x01);                                             // varint 1
}

#if !defined(__APPLE__)
rac_result_t refreshProtoViaSymbol(
    rac_model_registry_handle_t registryHandle,
    const uint8_t* bytes,
    size_t size,
    rac_proto_buffer_t* outResult) {
    auto refreshProto =
        proto_compat::symbol<proto_compat::RegistryRequestProtoFn>(
            "rac_model_registry_refresh_proto");
    if (!refreshProto) {
        LOGE("refreshModelRegistry: rac_model_registry_refresh_proto unavailable");
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return refreshProto(registryHandle, bytes, size, outResult);
}
#endif

} // namespace

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::refreshModelRegistry(
    bool includeRemoteCatalog, bool rescanLocal, bool pruneOrphans) {
    return Promise<bool>::async([includeRemoteCatalog, rescanLocal,
                                 pruneOrphans]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("refreshModelRegistry: registry not initialized");
            return false;
        }

        // ModelRegistryRefreshRequest: field 1 include_remote_catalog,
        // field 2 rescan_local, field 3 prune_orphans (all bool).
        std::vector<uint8_t> requestBytes;
        appendRefreshBoolField(requestBytes, 1, includeRemoteCatalog);
        appendRefreshBoolField(requestBytes, 2, rescanLocal);
        appendRefreshBoolField(requestBytes, 3, pruneOrphans);

        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
#if defined(__APPLE__)
        rac_result_t rc = rac_model_registry_refresh_proto(
            registryHandle, requestBytes.data(), requestBytes.size(), &out);
#else
        rac_result_t rc = refreshProtoViaSymbol(
            registryHandle, requestBytes.data(), requestBytes.size(), &out);
#endif
        if (rc != RAC_SUCCESS) {
            LOGE("refreshModelRegistry: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return false;
        }
        // The ModelRegistryRefreshResult bytes carry counts/warnings the RN
        // surface does not consume today; success is signalled by rc.
        proto_compat::freeBuffer(&out);
        return true;
    });
}

} // namespace margelo::nitro::runanywhere
