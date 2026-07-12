/**
 * HybridRunAnywhereCore+Registry.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * Bridge classification:
 *   - SDK-facing pass-through: getAvailableModelsProto, getModelInfoProto,
 *     registerModelProto, updateModelProto, removeModelProto,
 *     queryModelsProto, getDownloadedModelsProto. These thunk to the
 *     current `rac_model_registry_*_proto` C ABI directly.
 *   - importModelProto mirrors Swift's RAModelImportRequest route for
 *     platform-normalized local paths after downloads or file-picker flows.
 *   - refreshModelRegistry(includeRemoteCatalog, rescanLocal, pruneOrphans)
 *     hand-encodes the three bool fields into a ModelRegistryRefreshRequest
 *     protobuf message (no protobuf runtime is linked in this bridge) and
 *     routes through the canonical `rac_model_registry_refresh_proto`.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Model Registry
// ============================================================================

namespace {

std::vector<uint8_t>
copyArrayBufferBytes(const std::shared_ptr<ArrayBuffer> &buffer) {
  std::vector<uint8_t> bytes;
  if (!buffer) {
    return bytes;
  }

  uint8_t *data = buffer->data();
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

void freeRegistryProtoBytes(uint8_t *protoBytes) {
  if (!protoBytes) {
    return;
  }
  rac_model_registry_proto_free(protoBytes);
}

rac_result_t registryGetProto(rac_model_registry_handle_t registryHandle,
                              const char *modelId, uint8_t **protoBytes,
                              size_t *protoSize) {
  return rac_model_registry_get_proto(registryHandle, modelId, protoBytes,
                                      protoSize);
}

rac_result_t registryListProto(rac_model_registry_handle_t registryHandle,
                               uint8_t **protoBytes, size_t *protoSize) {
  return rac_model_registry_list_proto(registryHandle, protoBytes, protoSize);
}

using RegistryWriteProtoFn = decltype(&rac_model_registry_register_proto);

rac_result_t registryWriteProto(RegistryWriteProtoFn writeProto,
                                rac_model_registry_handle_t registryHandle,
                                const uint8_t *bytes, size_t size) {
  return writeProto(registryHandle, bytes, size);
}

rac_result_t registryRemoveProto(rac_model_registry_handle_t registryHandle,
                                 const char *modelId) {
  return rac_model_registry_remove_proto(registryHandle, modelId);
}

rac_result_t registryQueryProto(rac_model_registry_handle_t registryHandle,
                                const uint8_t *queryBytes, size_t querySize,
                                uint8_t **protoBytes, size_t *protoSize) {
  return rac_model_registry_query_proto(registryHandle, queryBytes, querySize,
                                        protoBytes, protoSize);
}

rac_result_t
registryListDownloadedProto(rac_model_registry_handle_t registryHandle,
                            uint8_t **protoBytes, size_t *protoSize) {
  return rac_model_registry_list_downloaded_proto(registryHandle, protoBytes,
                                                  protoSize);
}

std::shared_ptr<ArrayBuffer> ownedProtoBuffer(uint8_t *protoBytes,
                                              size_t protoSize) {
  if (!protoBytes || protoSize == 0) {
    freeRegistryProtoBytes(protoBytes);
    return emptyProtoBuffer();
  }

  auto buffer = ArrayBuffer::copy(protoBytes, protoSize);
  freeRegistryProtoBytes(protoBytes);
  return buffer;
}

std::shared_ptr<ArrayBuffer>
ownedRegistryBuffer(const char *operation, rac_proto_buffer_t &protoBuffer) {
  if (protoBuffer.status != RAC_SUCCESS) {
    if (protoBuffer.error_message) {
      LOGE("%s proto error: %s", operation, protoBuffer.error_message);
    }
    rac_proto_buffer_free(&protoBuffer);
    return emptyProtoBuffer();
  }

  if (!protoBuffer.data || protoBuffer.size == 0) {
    rac_proto_buffer_free(&protoBuffer);
    return emptyProtoBuffer();
  }

  auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
  rac_proto_buffer_free(&protoBuffer);
  return buffer;
}

} // namespace

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getAvailableModelsProto() {
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      []() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
          LOGE("getAvailableModelsProto: registry not initialized");
          return emptyProtoBuffer();
        }

        uint8_t *protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc =
            registryListProto(registryHandle, &protoBytes, &protoSize);
        if (rc != RAC_SUCCESS) {
          LOGE("getAvailableModelsProto: rc=%d", rc);
          return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
      });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getModelInfoProto(const std::string &modelId) {
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      [modelId]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
          LOGE("getModelInfoProto: registry not initialized");
          return emptyProtoBuffer();
        }

        uint8_t *protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryGetProto(registryHandle, modelId.c_str(),
                                           &protoBytes, &protoSize);
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
    const std::shared_ptr<ArrayBuffer> &modelInfoBytes) {
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
        rac_model_registry_register_proto, registryHandle, bytes.data(), bytes.size());
    if (rc != RAC_SUCCESS) {
      LOGE("registerModelProto: rc=%d", rc);
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::registerModelFromUrlProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
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
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_register_model_from_url_proto(
            bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS) {
          LOGE("registerModelFromUrlProto: rc=%d", rc);
          rac_proto_buffer_free(&out);
          return emptyProtoBuffer();
        }

        return ownedRegistryBuffer("registerModelFromUrlProto", out);
      });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::registerMultiFileModelProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
  auto bytes = copyArrayBufferBytes(requestBytes);
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      [bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
        // rac_register_multi_file_model_proto resolves the global registry
        // internally; the bridge handle gate just fails fast before init.
        if (!ModelRegistryBridge::shared().getHandle()) {
          LOGE("registerMultiFileModelProto: registry not initialized");
          return emptyProtoBuffer();
        }

        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_register_multi_file_model_proto(
            bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS) {
          LOGE("registerMultiFileModelProto: rc=%d", rc);
          rac_proto_buffer_free(&out);
          return emptyProtoBuffer();
        }

        return ownedRegistryBuffer("registerMultiFileModelProto", out);
      });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::updateModelProto(
    const std::shared_ptr<ArrayBuffer> &modelInfoBytes) {
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
        rac_model_registry_update_proto, registryHandle, bytes.data(), bytes.size());
    if (rc != RAC_SUCCESS) {
      LOGE("updateModelProto: rc=%d", rc);
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::removeModelProto(const std::string &modelId) {
  return Promise<bool>::async([modelId]() -> bool {
    auto registryHandle = ModelRegistryBridge::shared().getHandle();
    if (!registryHandle) {
      LOGE("removeModelProto: registry not initialized");
      return false;
    }

    rac_result_t rc = registryRemoveProto(registryHandle, modelId.c_str());
    if (rc != RAC_SUCCESS) {
      LOGE("removeModelProto: model=%s rc=%d", modelId.c_str(), rc);
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::queryModelsProto(
    const std::shared_ptr<ArrayBuffer> &queryBytes) {
  auto bytes = copyArrayBufferBytes(queryBytes);
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      [bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
          LOGE("queryModelsProto: registry not initialized");
          return emptyProtoBuffer();
        }
        if (bytes.empty()) {
          LOGE("queryModelsProto: empty payload");
          return emptyProtoBuffer();
        }

        uint8_t *protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc =
            registryQueryProto(registryHandle, bytes.data(), bytes.size(),
                               &protoBytes, &protoSize);
        if (rc != RAC_SUCCESS) {
          LOGE("queryModelsProto: rc=%d", rc);
          return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
      });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::getDownloadedModelsProto() {
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      []() -> std::shared_ptr<ArrayBuffer> {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
          LOGE("getDownloadedModelsProto: registry not initialized");
          return emptyProtoBuffer();
        }

        uint8_t *protoBytes = nullptr;
        size_t protoSize = 0;
        rac_result_t rc = registryListDownloadedProto(registryHandle,
                                                      &protoBytes, &protoSize);
        if (rc != RAC_SUCCESS) {
          LOGE("getDownloadedModelsProto: rc=%d", rc);
          return emptyProtoBuffer();
        }

        return ownedProtoBuffer(protoBytes, protoSize);
      });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::importModelProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
  auto bytes = copyArrayBufferBytes(requestBytes);
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      [bytes = std::move(bytes)]() -> std::shared_ptr<ArrayBuffer> {
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
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_model_registry_import_proto(
            registryHandle, bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS) {
          LOGE("importModelProto: rc=%d", rc);
          rac_proto_buffer_free(&out);
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
void appendRefreshBoolField(std::vector<uint8_t> &out, uint32_t fieldNumber,
                            bool value) {
  if (!value) {
    return;
  }
  out.push_back(static_cast<uint8_t>((fieldNumber << 3) | 0x00)); // tag
  out.push_back(0x01);                                            // varint 1
}

// Downloaded-model discovery pre-pass before a rescan refresh.
// Mirrors Swift refreshModelRegistry (RunAnywhere+ModelRegistry.swift:54-63),
// which runs CppBridge.ModelRegistry.discoverDownloadedModels() first with
// its default request: recursive=true (field 2), link_downloaded=true
// (field 3), query{downloaded_only=true} (field 5), include_user_imports=true
// (field 7) — see CppBridge+ModelRegistry.swift defaultDiscoveryRequest().
void discoverDownloadedModelsPrePass(
    rac_model_registry_handle_t registryHandle) {
  // ModelDiscoveryRequest wire bytes.
  std::vector<uint8_t> requestBytes;
  appendRefreshBoolField(requestBytes, 2, true); // recursive
  appendRefreshBoolField(requestBytes, 3, true); // link_downloaded
  // query (field 5, nested ModelQuery{downloaded_only(4)=true}).
  std::vector<uint8_t> queryBytes;
  appendRefreshBoolField(queryBytes, 4, true); // downloaded_only
  requestBytes.push_back(static_cast<uint8_t>((5 << 3) | 0x02)); // LEN tag
  requestBytes.push_back(static_cast<uint8_t>(queryBytes.size()));
  requestBytes.insert(requestBytes.end(), queryBytes.begin(), queryBytes.end());
  appendRefreshBoolField(requestBytes, 7, true); // include_user_imports

  rac_proto_buffer_t out;
  rac_proto_buffer_init(&out);
  rac_result_t rc = rac_model_registry_discover_proto(
      registryHandle, requestBytes.data(), requestBytes.size(), &out);
  if (rc != RAC_SUCCESS) {
    // Non-fatal — Swift logs and proceeds with the refresh.
    LOGE("refreshModelRegistry: discover pre-pass rc=%d", rc);
  }
  rac_proto_buffer_free(&out);
}

} // namespace

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::refreshModelRegistry(
    bool includeRemoteCatalog, bool rescanLocal, bool pruneOrphans) {
  return Promise<bool>::async(
      [includeRemoteCatalog, rescanLocal, pruneOrphans]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
          LOGE("refreshModelRegistry: registry not initialized");
          return false;
        }

        // Swift parity: rescanLocal first runs the downloaded-model
        // discovery pre-pass (RunAnywhere+ModelRegistry.swift:56-58).
        if (rescanLocal) {
          discoverDownloadedModelsPrePass(registryHandle);
        }

        // ModelRegistryRefreshRequest: field 1 include_remote_catalog,
        // field 2 rescan_local, field 3 prune_orphans, field 7
        // include_downloaded_state (always true — Swift parity,
        // RunAnywhere+ModelRegistry.swift:62).
        std::vector<uint8_t> requestBytes;
        appendRefreshBoolField(requestBytes, 1, includeRemoteCatalog);
        appendRefreshBoolField(requestBytes, 2, rescanLocal);
        appendRefreshBoolField(requestBytes, 3, pruneOrphans);
        appendRefreshBoolField(requestBytes, 7, true);

        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_model_registry_refresh_proto(
            registryHandle, requestBytes.data(), requestBytes.size(), &out);
        if (rc != RAC_SUCCESS) {
          LOGE("refreshModelRegistry: rc=%d", rc);
          rac_proto_buffer_free(&out);
          return false;
        }
        // The ModelRegistryRefreshResult bytes carry counts/warnings the RN
        // surface does not consume today; success is signalled by rc.
        rac_proto_buffer_free(&out);
        return true;
      });
}

// ============================================================================
// Model type lookups - sync thunks to the commons model-types C ABI
// (pure table/string lookups, safe on the JS thread). Mirrors Swift
// ModelTypes.swift displayName / RAModelCategory+DefaultFramework.swift /
// RAModelFileRole+Inference.swift.
// ============================================================================

std::string HybridRunAnywhereCore::frameworkDisplayName(double frameworkProto) {
  rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
  const char *name = nullptr;
  rac_inference_framework_from_proto(static_cast<int32_t>(frameworkProto),
                                     &framework);
  if (rac_inference_framework_display_name(framework, &name) != RAC_SUCCESS ||
      !name) {
    return "Unknown";
  }
  // The C ABI returns a statically-allocated literal; copy into std::string.
  return name;
}

double
HybridRunAnywhereCore::modelCategoryDefaultFramework(double categoryProto) {
  // INFERENCE_FRAMEWORK_UNKNOWN proto value — same as the C default branch.
  constexpr double kUnknownFrameworkProto = 22.0;
  rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
  int32_t frameworkProto = 0;
  if (rac_model_category_from_proto(static_cast<int32_t>(categoryProto),
                                    &category) != RAC_SUCCESS) {
    return kUnknownFrameworkProto;
  }
  if (rac_inference_framework_to_proto(
          rac_model_category_default_framework(category), &frameworkProto) !=
      RAC_SUCCESS) {
    return kUnknownFrameworkProto;
  }
  return static_cast<double>(frameworkProto);
}

double HybridRunAnywhereCore::inferModelFileRole(const std::string &filename,
                                                 double modalityProto) {
  // MODEL_FILE_ROLE_PRIMARY_MODEL — same default as the C ABI's no-match
  // branch and Swift's CppBridge+ModelPaths fallback.
  int32_t roleProto = 1;
  rac_infer_model_file_role(filename.c_str(),
                            static_cast<int32_t>(modalityProto), &roleProto);
  return static_cast<double>(roleProto);
}

} // namespace margelo::nitro::runanywhere
