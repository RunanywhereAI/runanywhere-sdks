/**
 * @file model_registry_discovery.cpp
 * @brief Model registry — filesystem reconciliation + path inference.
 *
 * SRP split of model_registry.cpp (pure code-motion). Owns the cold-launch
 * filesystem reconciliation (relink registry entries to their canonical on-disk
 * folders), the format/framework path inference helpers, and the
 * rac_model_registry_discover_proto entry point (see model_registry_internal.h).
 * No behaviour change.
 */

#include <cctype>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "model_registry_internal.h"

using namespace rac::infra::model_registry::detail;  // NOLINT(build/namespaces)

#ifdef RAC_HAVE_PROTOBUF

// -----------------------------------------------------------------------------
// Single-TU path / filesystem helpers (internal linkage).
// -----------------------------------------------------------------------------

namespace {

std::string lowercase_copy(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    for (unsigned char ch : input) {
        out.push_back(static_cast<char>(std::tolower(ch)));
    }
    return out;
}

bool ends_with(const std::string& value, const std::string& suffix) {
    return value.ends_with(suffix);
}

// Recognize a model file purely by extension (ModelFormat-agnostic).
bool is_recognizable_model_filename(const std::string& name) {
    const size_t dot = name.find_last_of('.');
    if (dot == std::string::npos) {
        return false;
    }
    const std::string ext = lowercase_copy(name.substr(dot + 1));
    return ext == "gguf" || ext == "ggml" || ext == "onnx" || ext == "ort" || ext == "bin" ||
           ext == "mlmodel" || ext == "mlpackage" || ext == "mlmodelc" || ext == "tflite" ||
           ext == "safetensors";
}

// Does `dir` (one level, plus one nested level for archive-extracted layouts
// like sherpa) contain a recognizable model file? Enumerates through the
// platform adapter so this works identically on native and Web/OPFS —
// std::filesystem cannot see the OPFS virtual filesystem, which is why the Web
// SDK previously needed its own hydrateModelRegistry pass.
bool directory_contains_recognizable_model_file(const std::string& dir) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter || !adapter->file_list_directory) {
        RAC_LOG_WARNING("ModelRegistry",
                        "file_list_directory adapter slot is NULL — cannot reconcile '%s'",
                        dir.c_str());
        return false;
    }
    std::vector<rac_directory_entry_t> entries;
    if (list_directory_via_adapter(adapter, dir.c_str(), &entries) != RAC_SUCCESS) {
        return false;
    }
    for (const rac_directory_entry_t& entry : entries) {
        if (!entry.is_dir) {
            if (is_recognizable_model_filename(entry.name)) {
                return true;
            }
            continue;
        }
        // One level of recursion for nested model folders.
        std::vector<rac_directory_entry_t> nested;
        const std::string subdir = dir + "/" + entry.name;
        if (list_directory_via_adapter(adapter, subdir.c_str(), &nested) == RAC_SUCCESS) {
            for (const rac_directory_entry_t& sub : nested) {
                if (!sub.is_dir && is_recognizable_model_filename(sub.name)) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Returns the canonical on-disk folder for a model id:
//   {base_dir}/RunAnywhere/Models/{framework_raw_value}/{model_id}
// Returns an empty path if base_dir is not configured. Delegates to
// rac_model_paths_get_model_folder (the single authority for path layout)
// rather than hand-concatenating path components — any future change to the
// canonical layout only needs to happen in one place.
std::filesystem::path canonical_model_folder_for(const std::string& model_id,
                                                 rac_inference_framework_t framework) {
    namespace fs = std::filesystem;
    if (model_id.empty()) {
        return fs::path{};
    }
    char buffer[4096];
    rac_result_t rc =
        rac_model_paths_get_model_folder(model_id.c_str(), framework, buffer, sizeof(buffer));
    if (rc != RAC_SUCCESS) {
        return fs::path{};
    }
    return {buffer};
}

}  // namespace

// -----------------------------------------------------------------------------
// Cross-TU path inference + reconciliation (declared in model_registry_internal.h).
// -----------------------------------------------------------------------------

namespace rac::infra::model_registry::detail {

bool model_is_built_in(const ModelInfo& model) {
    return (model.has_artifact_type() &&
            model.artifact_type() == runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN) ||
           model.artifact_case() == ModelInfo::kBuiltIn ||
           model.source() == runanywhere::v1::MODEL_SOURCE_BUILT_IN;
}

bool path_matches_roots(const std::string& path,
                        const google::protobuf::RepeatedPtrField<std::string>& roots) {
    if (roots.empty()) {
        return true;
    }
    for (const std::string& root : roots) {
        if (root.empty() || path.starts_with(root)) {
            return true;
        }
    }
    return false;
}

std::string basename_from_path(const std::string& path) {
    const size_t slash = path.find_last_of("/\\");
    if (slash == std::string::npos) {
        return path;
    }
    if (slash + 1 >= path.size()) {
        return "";
    }
    return path.substr(slash + 1);
}

std::string strip_known_model_extension(const std::string& basename) {
    std::string lower = lowercase_copy(basename);
    const char* archive_suffixes[] = {".tar.gz", ".tar.bz2", ".tar.xz"};
    for (const char* suffix : archive_suffixes) {
        if (ends_with(lower, suffix)) {
            return basename.substr(0, basename.size() - std::strlen(suffix));
        }
    }

    const size_t dot = basename.find_last_of('.');
    if (dot == std::string::npos || dot == 0) {
        return basename;
    }
    return basename.substr(0, dot);
}

ModelFormat infer_format_from_path(const std::string& path) {
    const std::string lower = lowercase_copy(path);
    if (ends_with(lower, ".gguf"))
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    if (ends_with(lower, ".ggml"))
        return runanywhere::v1::MODEL_FORMAT_GGML;
    if (ends_with(lower, ".onnx"))
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    if (ends_with(lower, ".ort"))
        return runanywhere::v1::MODEL_FORMAT_ORT;
    if (ends_with(lower, ".bin"))
        return runanywhere::v1::MODEL_FORMAT_BIN;
    if (ends_with(lower, ".tflite"))
        return runanywhere::v1::MODEL_FORMAT_TFLITE;
    if (ends_with(lower, ".safetensors"))
        return runanywhere::v1::MODEL_FORMAT_SAFETENSORS;
    if (ends_with(lower, ".mlmodel"))
        return runanywhere::v1::MODEL_FORMAT_MLMODEL;
    if (ends_with(lower, ".mlpackage"))
        return runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    if (ends_with(lower, ".zip"))
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    if (ends_with(lower, ".tar.gz") || ends_with(lower, ".tar.bz2") ||
        ends_with(lower, ".tar.xz")) {
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    }
    return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

InferenceFramework infer_framework_from_format(ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_GGUF:
        case runanywhere::v1::MODEL_FORMAT_GGML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case runanywhere::v1::MODEL_FORMAT_ONNX:
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE;
        case runanywhere::v1::MODEL_FORMAT_COREML:
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

// =============================================================================
// FILESYSTEM RECONCILIATION (cold-launch discovery)
// =============================================================================
// When the SDK process starts, the in-memory registry is empty. Platform SDKs
// re-seed entries via registerModel(url, ...) which only carry download_url,
// never local_path. So even though the user's previously downloaded model
// files still exist under {base_dir}/RunAnywhere/Models/{framework}/{id}/,
// the default discover path skips every entry with an empty local_path.
//
// This helper walks the canonical on-disk layout that rac_model_paths_*
// defines, and for each registry entry whose local_path is still empty, it
// checks whether the matching <framework>/<id>/ directory exists and contains
// at least one recognizable model file. When so, it rewrites local_path onto
// the entry so the existing discover loop reports it as linked.
//
// This mirrors the pre-v2 Swift ModelInfoService.discoverDownloadedModels()
// behavior behind the shared C ABI so every SDK benefits once.

// Attempt to link a single registry entry to its canonical on-disk folder.
// Preconditions: caller holds the registry mutex. The entry's local_path must
// currently be empty. Returns true when a matching folder exists and local_path
// has been rewritten (legacy struct + proto snapshot). Used by both the
// per-save fast path (rac_model_registry_save) and the bulk discovery
// sweep (reconcile_registry_with_filesystem_locked) so ordering of
// registerModel() vs rac_model_paths_set_base_dir() no longer matters.
bool try_reconcile_model_local_path_locked(rac_model_registry_handle_t handle,
                                           const std::string& model_id, rac_model_info_t* model) {
    if (!handle || !model || !model->id) {
        return false;
    }
    if (model->local_path && strlen(model->local_path) > 0) {
        return false;
    }
    const char* base = rac_model_paths_get_base_dir();
    if (!base || *base == '\0') {
        return false;
    }
    const std::filesystem::path folder = canonical_model_folder_for(model->id, model->framework);
    if (folder.empty() || !directory_contains_recognizable_model_file(folder.generic_string())) {
        return false;
    }

    const std::string folder_str = folder.generic_string();

    // Update legacy struct
    if (model->local_path) {
        free(model->local_path);
    }
    model->local_path = rac_strdup(folder_str.c_str());
    model->updated_at = rac_get_current_time_ms() / 1000;

    // Update proto snapshot
    ModelInfo snapshot = model_snapshot_locked(handle, model_id, model);
    snapshot.set_local_path(folder_str);
    overwrite_download_state_from_local_path(&snapshot);
    std::string serialized;
    if (snapshot.SerializeToString(&serialized)) {
        handle->model_proto_bytes[model_id] = std::move(serialized);
    }

    RAC_LOG_DEBUG("ModelRegistry", "Reconciled '%s' with on-disk folder: %s", model->id,
                  folder_str.c_str());
    return true;
}

// Walks the on-disk canonical layout and for every registry entry that
// currently has an empty local_path but has a matching
// {base_dir}/RunAnywhere/Models/{framework}/{id}/ folder containing at least
// one recognizable model file, rewrites local_path back onto the entry. Also
// normalizes download state flags via overwrite_download_state_from_local_path.
// Returns the number of entries that were linked.
int32_t reconcile_registry_with_filesystem_locked(rac_model_registry_handle_t handle) {
    if (!handle) {
        return 0;
    }
    const char* base = rac_model_paths_get_base_dir();
    if (!base || *base == '\0') {
        return 0;
    }

    int32_t linked = 0;
    for (auto& pair : handle->models) {
        if (try_reconcile_model_local_path_locked(handle, pair.first, pair.second)) {
            ++linked;
        }
    }
    return linked;
}

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_HAVE_PROTOBUF

rac_result_t rac_model_registry_discover_proto(rac_model_registry_handle_t handle,
                                               const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelDiscoveryRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(
        request_proto_bytes, request_proto_size, &request, "ModelDiscoveryRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    int32_t reconciled = 0;
    std::vector<ModelInfo> models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        // Bridge the in-memory registry with the canonical on-disk layout so
        // entries re-seeded by registerModel() after an app relaunch can be
        // linked back to previously downloaded {base_dir}/RunAnywhere/Models/
        // {framework}/{id}/ folders. Opt-in via link_downloaded (default true
        // from Swift's defaultDiscoveryRequest).
        if (request.link_downloaded()) {
            reconciled = reconcile_registry_with_filesystem_locked(handle);
        }
        models = collect_model_snapshots_locked(handle);
    }

    ModelDiscoveryResult result;
    result.set_success(true);
    int32_t scanned = 0;
    for (const ModelInfo& model : models) {
        if (!request.include_built_in() && model_is_built_in(model)) {
            continue;
        }
        ++scanned;
        if (model.local_path().empty()) {
            continue;
        }
        if (!path_matches_roots(model.local_path(), request.search_roots())) {
            continue;
        }
        if (request.has_query() && !model_matches_query(model, request.query())) {
            continue;
        }

        DiscoveredModel* discovered = result.add_discovered_models();
        discovered->set_model_id(model.id());
        discovered->set_local_path(model.local_path());
        discovered->set_matched_registry(true);
        discovered->mutable_model()->CopyFrom(model);
        discovered->set_size_bytes(model.download_size_bytes());
    }
    (void)reconciled;  // logged via per-entry RAC_LOG_DEBUG above

    if (request.purge_invalid()) {
        result.add_warnings(
            "purge_invalid requires platform filesystem callbacks and was not executed");
    }
    result.set_scanned_count(scanned);
    result.set_linked_count(result.discovered_models_size());
    result.set_purged_count(0);
    result.set_imported_count(0);
    return serialize_proto_to_buffer(result, out_result);
#endif
}
