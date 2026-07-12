/**
 * @file lora_import.cpp
 * @brief Canonical user-file LoRA adapter import — commons-owned placement.
 *
 * One entry point (rac_lora_adapter_import_proto) owns everything past the
 * platform-readable source path, so no SDK or example app ever constructs an
 * adapter location again:
 *
 *   1. Deterministic catalog match: an exact local-path match wins, else a
 *      filename match only when it is unambiguous — generic adapter filenames
 *      (adapter_model.gguf) recur across base models, and completing an
 *      arbitrary entry would corrupt unrelated catalog state.
 *   2. Placement into the canonical layout the download path uses for the
 *      same adapter: {Models}/{framework}/lora-adapter:{id}/{filename}
 *      (rac_model_paths_get_model_folder, RAC_FRAMEWORK_UNKNOWN).
 *   3. Artifact model-registry record via rac_model_registry_register_proto —
 *      this is what makes the bytes visible to storage accounting / delete
 *      and what persists the durable folder manifest for cross-session
 *      restore. The imported file is authoritative: its real size is
 *      recorded and no catalog checksum is carried over.
 *   4. Catalog completion (imported=true) for matched entries, through the
 *      same path the download flow uses.
 *
 * Built on the public proto ABI only (catalog list, mark-completed, registry
 * register) so it stays decoupled from lora_registry.cpp internals.
 */

#include <cstdint>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

#include "infrastructure/rac_path_safety_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "lora_options.pb.h"
#include "model_types.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

#ifdef RAC_HAVE_PROTOBUF

namespace {

namespace fs = std::filesystem;

constexpr const char* LOG_CAT = "LoraImport";

// Canonical artifact-model id prefix for adapter bytes. Mirrored (not
// duplicated as logic) by the SDK download helpers' registerArtifact flows so
// imported and downloaded copies of the same adapter share one folder.
constexpr const char* kLoraArtifactModelIdPrefix = "lora-adapter:";

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

rac_result_t typed_failure(rac_proto_buffer_t* out, const std::string& message) {
    runanywhere::v1::LoraAdapterImportResult result;
    result.set_success(false);
    result.set_error_message(message);
    return copy_proto(result, out);
}

std::string basename_of(const std::string& path) {
    const size_t slash = path.find_last_of("/\\");
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string stem_of(const std::string& filename) {
    const size_t dot = filename.rfind('.');
    return (dot == std::string::npos || dot == 0) ? filename : filename.substr(0, dot);
}

std::string artifact_model_id_for(const std::string& entry_id) {
    return entry_id.starts_with(kLoraArtifactModelIdPrefix) ? entry_id
                                                            : kLoraArtifactModelIdPrefix + entry_id;
}

// Snapshot the catalog through the public list ABI. Best-effort: an unhealthy
// catalog must not block a plain file import — it just means no entry match.
std::vector<runanywhere::v1::LoraAdapterCatalogEntry>
catalog_entries(rac_lora_registry_handle_t registry) {
    runanywhere::v1::LoraAdapterCatalogListRequest request;
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return {};
    }
    rac_proto_buffer_t out = {};
    const rac_result_t rc = rac_lora_catalog_list_proto(
        registry, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
        &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        return {};
    }
    runanywhere::v1::LoraAdapterCatalogListResult list_result;
    const bool parsed =
        out.size > 0 && list_result.ParseFromArray(out.data, static_cast<int>(out.size));
    rac_proto_buffer_free(&out);
    if (!parsed || !list_result.success()) {
        return {};
    }
    return {list_result.entries().begin(), list_result.entries().end()};
}

// Build the artifact registry record for the placed bytes — the import
// counterpart of the SDKs' download-time registerArtifact. The registry save
// also persists the durable folder manifest, so the import survives cold
// launches like a downloaded model does.
runanywhere::v1::ModelInfo
make_artifact_record(const std::string& artifact_id, const std::string& display_name,
                     const std::string& filename, const std::string& local_path, int64_t size_bytes,
                     const runanywhere::v1::LoraAdapterCatalogEntry* matched) {
    runanywhere::v1::ModelInfo artifact;
    artifact.set_id(artifact_id);
    artifact.set_name(display_name);
    artifact.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    artifact.set_local_path(local_path);
    artifact.set_source(runanywhere::v1::MODEL_SOURCE_LOCAL);
    artifact.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    artifact.set_is_downloaded(true);
    artifact.set_is_available(true);
    if (size_bytes > 0) {
        artifact.set_download_size_bytes(size_bytes);
    }

    runanywhere::v1::ExpectedModelFiles expected;
    runanywhere::v1::ModelFileDescriptor* file = expected.add_files();
    file->set_filename(filename);
    file->set_is_required(true);
    file->set_role(runanywhere::v1::MODEL_FILE_ROLE_COMPANION);
    if (size_bytes > 0) {
        file->set_size_bytes(size_bytes);
    }
    expected.add_required_patterns(filename);
    expected.set_description("LoRA adapter artifact");

    runanywhere::v1::SingleFileArtifact* single = artifact.mutable_single_file();
    single->add_required_patterns(filename);
    *single->mutable_expected_files() = expected;
    *artifact.mutable_expected_files() = expected;

    runanywhere::v1::ModelInfoMetadata* metadata = artifact.mutable_metadata();
    metadata->add_tags("lora-adapter");
    if (matched != nullptr) {
        for (const std::string& base_model : matched->compatible_models()) {
            metadata->add_tags("base-model:" + base_model);
        }
        for (const std::string& tag : matched->tags()) {
            metadata->add_tags(tag);
        }
    }
    return artifact;
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

extern "C" RAC_API rac_result_t rac_lora_adapter_import_proto(rac_lora_registry_handle_t registry,
                                                              const uint8_t* request_proto_bytes,
                                                              size_t request_proto_size,
                                                              rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    const rac_result_t validation =
        rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "LoraAdapterImportRequest bytes are invalid");
    }
    runanywhere::v1::LoraAdapterImportRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse LoraAdapterImportRequest");
    }
    if (request.source_path().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "LoraAdapterImportRequest.source_path is required");
    }

    const std::string filename = request.has_filename() && !request.filename().empty()
                                     ? request.filename()
                                     : basename_of(request.source_path());
    if (!rac::path::is_safe_path_segment(filename)) {
        return typed_failure(out_result,
                             "import filename is not a safe single path segment: " + filename);
    }

    std::error_code ec;
    if (!fs::exists(request.source_path(), ec) || ec) {
        return typed_failure(out_result, "source file does not exist: " + request.source_path());
    }

    // Deterministic match: exact path, else unambiguous filename.
    const std::vector<runanywhere::v1::LoraAdapterCatalogEntry> entries = catalog_entries(registry);
    const runanywhere::v1::LoraAdapterCatalogEntry* matched = nullptr;
    const runanywhere::v1::LoraAdapterCatalogEntry* name_match = nullptr;
    int name_match_count = 0;
    for (const runanywhere::v1::LoraAdapterCatalogEntry& entry : entries) {
        if (entry.has_local_path() && !entry.local_path().empty() &&
            entry.local_path() == request.source_path()) {
            matched = &entry;
            break;
        }
        if (entry.filename() == filename) {
            name_match = &entry;
            ++name_match_count;
        }
    }
    if (matched == nullptr && name_match_count == 1) {
        matched = name_match;
    }

    const std::string entry_id = matched != nullptr ? matched->id() : stem_of(filename);
    const std::string display_name =
        matched != nullptr && !matched->name().empty() ? matched->name() : entry_id;
    const std::string artifact_id = artifact_model_id_for(entry_id);

    char folder_buffer[4096];
    if (rac_model_paths_get_model_folder(artifact_id.c_str(), RAC_FRAMEWORK_UNKNOWN, folder_buffer,
                                         sizeof(folder_buffer)) != RAC_SUCCESS) {
        return typed_failure(out_result,
                             "cannot resolve adapter folder (base directory not configured "
                             "or unsafe adapter id: " +
                                 artifact_id + ")");
    }
    const std::string folder = folder_buffer;
    fs::create_directories(folder, ec);
    if (ec) {
        return typed_failure(out_result,
                             "cannot create adapter folder '" + folder + "': " + ec.message());
    }
    const std::string destination = folder + "/" + filename;
    // Re-import of the already-placed file (callers may pass back the
    // local_path a previous import returned) must be an idempotent no-op:
    // fs::copy_file errors on source==destination even with
    // overwrite_existing.
    std::error_code equivalent_ec;
    const bool source_is_destination =
        fs::equivalent(request.source_path(), destination, equivalent_ec) && !equivalent_ec;
    if (!source_is_destination) {
        if (fs::exists(destination, ec) && !ec) {
            RAC_LOG_WARNING(LOG_CAT,
                            "Overwriting existing adapter bytes at '%s' (re-import or "
                            "filename collision on artifact id '%s')",
                            destination.c_str(), artifact_id.c_str());
        }
        fs::copy_file(request.source_path(), destination, fs::copy_options::overwrite_existing, ec);
        if (ec) {
            return typed_failure(out_result, "failed to copy adapter file into '" + destination +
                                                 "': " + ec.message());
        }
    }
    const std::uintmax_t copied_size = fs::file_size(destination, ec);
    const int64_t size_bytes = ec ? 0 : static_cast<int64_t>(copied_size);

    // Register the placed bytes so deleteModel/storage accounting observe them
    // and the folder manifest persists across sessions.
    rac_model_registry_handle_t model_registry = rac_get_model_registry();
    if (model_registry == nullptr) {
        return typed_failure(out_result, "model registry is not initialized");
    }
    const runanywhere::v1::ModelInfo artifact =
        make_artifact_record(artifact_id, display_name, filename, destination, size_bytes, matched);
    std::string artifact_bytes;
    if (!artifact.SerializeToString(&artifact_bytes)) {
        return typed_failure(out_result, "failed to serialize adapter artifact record");
    }
    const rac_result_t save_rc = rac_model_registry_register_proto(
        model_registry, reinterpret_cast<const uint8_t*>(artifact_bytes.data()),
        artifact_bytes.size());
    if (save_rc != RAC_SUCCESS) {
        return typed_failure(out_result, std::string("failed to register adapter artifact: ") +
                                             rac_error_message(save_rc));
    }

    runanywhere::v1::LoraAdapterImportResult result;
    result.set_local_path(destination);

    if (matched != nullptr) {
        runanywhere::v1::LoraAdapterDownloadCompletedRequest completed;
        completed.set_adapter_id(matched->id());
        completed.set_local_path(destination);
        completed.set_imported(true);
        if (size_bytes > 0) {
            completed.set_size_bytes(size_bytes);
        }
        std::string completed_bytes;
        if (!completed.SerializeToString(&completed_bytes)) {
            return typed_failure(out_result, "failed to serialize import completion request");
        }
        rac_proto_buffer_t completed_out = {};
        const rac_result_t mark_rc = rac_lora_catalog_mark_download_completed_proto(
            registry, reinterpret_cast<const uint8_t*>(completed_bytes.data()),
            completed_bytes.size(), &completed_out);
        runanywhere::v1::LoraAdapterDownloadCompletedResult completed_result;
        const bool parsed = mark_rc == RAC_SUCCESS && completed_out.size > 0 &&
                            completed_result.ParseFromArray(completed_out.data,
                                                            static_cast<int>(completed_out.size));
        std::string mark_error;
        if (!parsed) {
            // Structural failure: the buffer envelope carries the cause.
            mark_error = (completed_out.error_message && completed_out.error_message[0] != '\0')
                             ? completed_out.error_message
                             : "LoRA adapter import completion was not persisted";
        } else if (!completed_result.success()) {
            mark_error = completed_result.error_message().empty()
                             ? "LoRA adapter import completion was not persisted"
                             : completed_result.error_message();
        }
        rac_proto_buffer_free(&completed_out);
        if (!mark_error.empty()) {
            return typed_failure(out_result, mark_error);
        }
        result.set_matched(true);
        *result.mutable_entry() = completed_result.entry();
    }

    result.set_success(true);
    RAC_LOG_INFO(LOG_CAT, "Imported LoRA adapter '%s' to '%s'%s", filename.c_str(),
                 destination.c_str(), matched != nullptr ? " (catalog matched)" : "");
    return copy_proto(result, out_result);
#endif  // RAC_HAVE_PROTOBUF
}
