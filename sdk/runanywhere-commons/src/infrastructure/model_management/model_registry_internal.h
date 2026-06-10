/**
 * @file model_registry_internal.h
 * @brief Internal layout shared between model-registry implementation TUs.
 *
 * NOT part of the public C ABI; only files under
 * `src/infrastructure/model_management/` may include this header. Public
 * callers go through the `rac_model_registry.h` C entry points.
 *
 * SRP split: the original `model_registry.cpp` mixed proto<->C conversion,
 * the struct-based CRUD core, the proto-byte ABI surface, filesystem
 * discovery/reconciliation, and refresh/fetch in a single ~3.3 KLoC TU. This
 * header is the contract through which the new per-responsibility TUs share
 * the registry layout + cross-TU helpers without re-exporting anything
 * publicly:
 *   - model_registry.cpp           : slim core (lifecycle + struct CRUD +
 *                                    download-state normalization + snapshot
 *                                    helpers)
 *   - model_registry_convert.cpp   : proto<->C mappers + (de)serialization +
 *                                    parse helpers
 *   - model_registry_proto.cpp     : proto-byte + proto_buffer C ABI surface +
 *                                    query/sort helpers
 *   - model_registry_discovery.cpp : filesystem reconciliation + path inference
 *   - model_registry_refresh.cpp   : refresh proto entry + adapter rescan +
 *                                    fetch-assignments + artifact-type inference
 *
 * Pure code-motion: no behaviour change. Helpers used by more than one TU are
 * promoted out of the original anonymous namespace into the named namespace
 * below and declared here (defined exactly once in their home TU); templates
 * are defined inline here so each TU can instantiate them. Helpers used by a
 * single TU stay `static` in that TU.
 */

#ifndef RAC_INFRA_MODEL_MANAGEMENT_MODEL_REGISTRY_INTERNAL_H
#define RAC_INFRA_MODEL_MANAGEMENT_MODEL_REGISTRY_INTERNAL_H

#include <cstdint>
#include <filesystem>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

// =============================================================================
// Registry handle layout (shared by every TU that locks handle->mutex)
// =============================================================================

struct rac_model_registry {
    // Model storage (model_id -> model_info)
    std::map<std::string, rac_model_info_t*> models;

#ifdef RAC_HAVE_PROTOBUF
    // Optional proto-native snapshots preserve fields not represented by the
    // legacy C struct while existing struct-based call sites are migrated.
    std::map<std::string, std::string> model_proto_bytes;
#endif

    // Thread safety
    std::mutex mutex;
};

namespace rac::infra::model_registry::detail {

// -----------------------------------------------------------------------------
// Conversion / memory helpers (defined in model_registry_convert.cpp)
// -----------------------------------------------------------------------------

rac_model_info_t* deep_copy_model(const rac_model_info_t* src);
void free_model_info(rac_model_info_t* model);

// Shared save implementation (defined in model_registry.cpp slim core). Declared
// outside the protobuf guard because its signature is proto-free and the
// non-proto struct CRUD entry points call it.
rac_result_t save_model_info_impl(rac_model_registry_handle_t handle, const rac_model_info_t* model,
                                  bool preserve_empty_local_path);

#ifdef RAC_HAVE_PROTOBUF

using runanywhere::v1::ArchiveArtifact;
using runanywhere::v1::ArchiveStructure;
using runanywhere::v1::ArchiveType;
using runanywhere::v1::DiscoveredModel;
using runanywhere::v1::InferenceFramework;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::ModelDeleteResult;
using runanywhere::v1::ModelDiscoveryRequest;
using runanywhere::v1::ModelDiscoveryResult;
using runanywhere::v1::ModelFileDescriptor;
using runanywhere::v1::ModelFileRole;
using runanywhere::v1::ModelFormat;
using runanywhere::v1::ModelGetRequest;
using runanywhere::v1::ModelGetResult;
using runanywhere::v1::ModelImportRequest;
using runanywhere::v1::ModelImportResult;
using runanywhere::v1::ModelInfo;
using runanywhere::v1::ModelInfoList;
using runanywhere::v1::ModelListRequest;
using runanywhere::v1::ModelListResult;
using runanywhere::v1::ModelQuery;
using runanywhere::v1::ModelQuerySortField;
using runanywhere::v1::ModelRegistryRefreshRequest;
using runanywhere::v1::ModelRegistryRefreshResult;
using runanywhere::v1::ModelRegistryStatus;
using runanywhere::v1::ModelSource;
using runanywhere::v1::MultiFileArtifact;
using runanywhere::v1::SingleFileArtifact;

// Aggregate counts emitted by list/refresh entry points.
struct ModelCounts {
    int32_t total{0};
    int32_t downloaded{0};
    int32_t available{0};
    int32_t errors{0};
};

// proto<->C conversion + (de)serialization + parse helpers.
char* dup_optional_proto_string(const std::string& value);
void model_info_to_proto(const rac_model_info_t* in, ModelInfo* out, bool overwrite_artifact,
                         bool overwrite_registry_state);
void overlay_struct_runtime_fields_to_proto(const rac_model_info_t* in, ModelInfo* out,
                                            bool overwrite_registry_state);
bool apply_proto_artifact_to_model(const ModelInfo& proto, rac_model_info_t* model);
rac_model_info_t* model_info_from_proto(const ModelInfo& proto);

rac_result_t proto_buffer_error(rac_proto_buffer_t* out_buffer, rac_result_t status,
                                const char* message);
rac_result_t parse_model_info_bytes(const uint8_t* proto_bytes, size_t proto_size, ModelInfo* out);
rac_result_t parse_model_query_bytes(const uint8_t* query_proto_bytes, size_t query_proto_size,
                                     ModelQuery* out);
void preserve_absent_proto_fields(const ModelInfo& existing, ModelInfo* incoming,
                                  bool preserve_empty_local_path);

// Serialization templates — defined inline so every TU can instantiate them.
template <typename ProtoMessage>
rac_result_t serialize_proto_to_owned_buffer(const ProtoMessage& message, uint8_t** proto_bytes_out,
                                             size_t* proto_size_out) {
    if (!proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return RAC_ERROR_UNKNOWN;
    }

    return rac_proto_buffer_copy_to_raw(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                        proto_bytes_out, proto_size_out);
}

template <typename ProtoMessage>
rac_result_t serialize_proto_to_buffer(const ProtoMessage& message, rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return rac_proto_buffer_set_error(out_buffer, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize registry proto result");
    }

    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_buffer);
}

template <typename ProtoMessage>
rac_result_t parse_proto_message_bytes(const uint8_t* proto_bytes, size_t proto_size,
                                       ProtoMessage* out, const char* message_name,
                                       rac_proto_buffer_t* error_out) {
    if (!out) {
        return proto_buffer_error(error_out, RAC_ERROR_INVALID_ARGUMENT,
                                  "output proto message is required");
    }

    rac_result_t validation = rac_proto_bytes_validate(proto_bytes, proto_size);
    if (validation != RAC_SUCCESS) {
        return proto_buffer_error(error_out, validation, "proto bytes are null or too large");
    }

    if (!out->ParseFromArray(rac_proto_bytes_data_or_empty(proto_bytes, proto_size),
                             static_cast<int>(proto_size))) {
        std::string message = "failed to parse ";
        message += message_name ? message_name : "proto message";
        return proto_buffer_error(error_out, RAC_ERROR_INVALID_FORMAT, message.c_str());
    }
    return RAC_SUCCESS;
}

// -----------------------------------------------------------------------------
// Download-state normalization (defined in model_registry.cpp slim core)
// -----------------------------------------------------------------------------

bool has_nonempty_local_path(const ModelInfo& model);
bool registry_status_is_downloaded(ModelRegistryStatus status);
bool model_is_downloaded_from_fields(const ModelInfo& model);
ModelRegistryStatus effective_registry_status(const ModelInfo& model);
void normalize_model_registry_state(ModelInfo* model);
void overwrite_download_state_from_local_path(ModelInfo* model);

// Snapshot helpers (defined in model_registry.cpp slim core).
rac_result_t store_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                         const std::string& model_id, const rac_model_info_t* model,
                                         bool preserve_proto_only_fields,
                                         bool overwrite_registry_state);
rac_result_t store_parsed_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id, const ModelInfo& parsed);
ModelInfo model_snapshot_locked(rac_model_registry_handle_t handle, const std::string& model_id,
                                const rac_model_info_t* model);
rac_result_t model_to_proto_bytes_locked(rac_model_registry_handle_t handle,
                                         const std::string& model_id, const rac_model_info_t* model,
                                         uint8_t** proto_bytes_out, size_t* proto_size_out);
bool get_model_snapshot_by_id(rac_model_registry_handle_t handle, const std::string& model_id,
                              ModelInfo* out);
int64_t imported_size_for_request(const ModelImportRequest& request, const ModelInfo& model);

// -----------------------------------------------------------------------------
// Query / sort helpers (defined in model_registry_proto.cpp)
// -----------------------------------------------------------------------------

bool model_is_downloaded_proto(const ModelInfo& model);
bool model_is_available_proto(const ModelInfo& model);
bool model_matches_query(const ModelInfo& model, const ModelQuery& query);
void sort_query_results(const ModelQuery& query, std::vector<ModelInfo>* models);
void append_query_results_locked(rac_model_registry_handle_t handle, const ModelQuery& query,
                                 ModelInfoList* out);
std::vector<ModelInfo> collect_model_snapshots_locked(rac_model_registry_handle_t handle);
std::vector<ModelInfo> query_model_snapshots_locked(rac_model_registry_handle_t handle,
                                                    const ModelQuery& query);
void move_models_to_list(std::vector<ModelInfo>* models, ModelInfoList* out);
ModelCounts count_models(const std::vector<ModelInfo>& models);

// -----------------------------------------------------------------------------
// Filesystem discovery / reconciliation (defined in model_registry_discovery.cpp)
// -----------------------------------------------------------------------------

bool model_is_built_in(const ModelInfo& model);
bool path_matches_roots(const std::string& path,
                        const google::protobuf::RepeatedPtrField<std::string>& roots);
std::string basename_from_path(const std::string& path);
ModelFormat infer_format_from_path(const std::string& path);
InferenceFramework infer_framework_from_format(ModelFormat format);
std::string strip_known_model_extension(const std::string& basename);
int32_t reconcile_registry_with_filesystem_locked(rac_model_registry_handle_t handle);
bool try_reconcile_model_local_path_locked(rac_model_registry_handle_t handle,
                                           const std::string& model_id, rac_model_info_t* model);

// -----------------------------------------------------------------------------
// Adapter directory listing (defined in model_registry_refresh.cpp)
// -----------------------------------------------------------------------------

// Enumerate a directory through the platform adapter using the POSIX two-call
// contract. Shared by the discovery reconcile path and the refresh rescan path.
rac_result_t list_directory_via_adapter(const rac_platform_adapter_t* adapter, const char* dir_path,
                                        std::vector<rac_directory_entry_t>* out_entries);
int32_t rescan_local_via_platform_adapter(rac_model_registry_handle_t handle);

// -----------------------------------------------------------------------------
// Disk persistence (defined in model_registry.cpp). The registry is otherwise
// in-memory only, so download/registry state would not survive a process
// restart. Both write and read the serialized ModelInfoList snapshot through the
// platform adapter (never std::filesystem) so they work on native and Web/OPFS.
// Callers must hold handle->mutex.
// -----------------------------------------------------------------------------

// Write the current registry snapshot to {models_dir}/.registry.pb. No-op when
// base_dir is unset or the adapter has no file_write slot.
void persist_registry_locked(rac_model_registry_handle_t handle);

// Load persisted entries into the registry, skipping ids already present (never
// clobbers a live in-memory entry). No-op when the file/adapter/base_dir is
// absent. Does not itself persist.
void load_registry_from_disk_locked(rac_model_registry_handle_t handle);

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_INFRA_MODEL_MANAGEMENT_MODEL_REGISTRY_INTERNAL_H
