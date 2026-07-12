/**
 * @file model_registry_manifest.cpp
 * @brief Model registry — model-folder manifest sidecar (write / restore /
 *        completeness validation).
 *
 * The in-memory registry forgets everything at process exit (see
 * rac_core.cpp persistence contract). Catalog models survive because SDKs
 * re-seed them each launch and reconciliation relinks their folders — but
 * ad-hoc registrations (direct URL pulls, Hugging Face pulls) used to vanish.
 *
 * This TU makes the model folder itself the durable record: whenever a model
 * transitions to downloaded inside the canonical layout, a serialized
 * ModelInfo is written to
 *   {base_dir}/RunAnywhere/Models/{framework}/{modelId}/<manifest>
 * (the private `.rac-manifest.binpb` sidecar). At cold launch the
 * discover/refresh paths read the sidecars back and re-register entries that
 * no consumer re-seeded, after
 * validating the folder is complete. Volatile absolute paths are stripped on
 * write and re-derived on restore, so the sidecar survives iOS
 * container-UUID changes and RUNANYWHERE_HOME moves unchanged.
 *
 * Completeness is delegated to rac_model_paths_resolve_artifact — the single
 * per-artifact-type authority (single-file / multi-file / archive /
 * directory) — so "is this folder a valid, non-corrupt model?" has exactly
 * one implementation for every modality and every consumer.
 */

#include "model_manifest_internal.h"
#include "model_registry_internal.h"

#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "infrastructure/rac_path_safety_internal.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF

namespace fs = std::filesystem;

namespace {

constexpr const char* LOG_CAT = "ModelRegistryManifest";

std::string manifest_path_for_folder(const std::string& folder) {
    return folder + "/" + rac::infra::model_manifest::kFilename;
}

bool read_file_bytes(const std::string& path, std::string* out) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }
    out->assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    return true;
}

bool ends_with_ci(const std::string& value, const char* suffix) {
    if (suffix == nullptr) {
        return false;
    }
    const size_t suffix_len = std::strlen(suffix);
    if (value.size() < suffix_len) {
        return false;
    }
    for (size_t i = 0; i < suffix_len; ++i) {
        char a = value[value.size() - suffix_len + i];
        char b = suffix[i];
        if (a >= 'A' && a <= 'Z')
            a = static_cast<char>(a + ('a' - 'A'));
        if (b >= 'A' && b <= 'Z')
            b = static_cast<char>(b + ('a' - 'A'));
        if (a != b) {
            return false;
        }
    }
    return true;
}

bool should_skip_exact_size_check(const rac_model_info_t* model,
                                  const rac_model_file_descriptor_t& descriptor, const char* name) {
    if (model == nullptr || model->framework != RAC_FRAMEWORK_QHEXRT || name == nullptr) {
        return false;
    }
    if (!ends_with_ci(name, ".json")) {
        return false;
    }
    return true;
}

// Strip volatile absolute paths so the sidecar is location-independent
// (absolute paths change across iOS container UUIDs / RUNANYWHERE_HOME moves;
// restore re-derives them from the folder the sidecar lives in). The
// downloaded flag reflects the LIVE entry: a manifest written at download
// START records registered-not-downloaded so restore offers resume-by-id;
// restore re-validates completeness against the folder either way.
void sanitize_for_manifest(runanywhere::v1::ModelInfo* model, bool downloaded) {
    model->clear_local_path();
    if (model->has_multi_file()) {
        for (runanywhere::v1::ModelFileDescriptor& file :
             *model->mutable_multi_file()->mutable_files()) {
            file.clear_local_path();
        }
    }
    if (model->has_expected_files()) {
        for (runanywhere::v1::ModelFileDescriptor& file :
             *model->mutable_expected_files()->mutable_files()) {
            file.clear_local_path();
        }
    }
    model->set_is_downloaded(downloaded);
    model->set_is_available(downloaded);
    model->set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                          : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    model->clear_sync_pending();
}

}  // namespace

namespace rac::infra::model_registry::detail {

bool model_has_artifact_descriptors(const rac_model_info_t* model) {
    if (!model) {
        return false;
    }
    return model->artifact_info.expected_files != nullptr ||
           model->artifact_info.file_descriptor_count > 0;
}

// One completeness authority for every artifact shape: delegate to
// rac_model_paths_resolve_artifact and require is_complete. RAC_SUCCESS with
// is_complete covers single-file, multi-file (all required descriptors
// present), archive (post-extraction layout incl. nested sherpa dirs), and
// directory-based frameworks.
bool model_folder_is_complete_struct(const rac_model_info_t* model, const std::string& folder) {
    if (!model || folder.empty()) {
        return false;
    }
    rac_model_path_resolution_t resolution{};
    const rac_result_t rc =
        rac_model_paths_resolve_artifact(model, folder.c_str(), nullptr, &resolution);
    bool complete = (rc == RAC_SUCCESS) && resolution.is_complete == RAC_TRUE;
    if (!complete && resolution.missing_required_file_count > 0 &&
        resolution.missing_required_files && resolution.missing_required_files[0]) {
        RAC_LOG_WARNING(LOG_CAT, "Folder '%s' incomplete for model '%s' (first missing: %s)",
                        folder.c_str(), model->id ? model->id : "?",
                        resolution.missing_required_files[0]);
    }
    rac_model_path_resolution_free(&resolution);

    // Exact-size verification for descriptors that declare sizes (Hugging
    // Face pulls record lfs sizes): existence alone must never bless a file
    // that was killed mid-download.
    if (complete) {
        for (size_t i = 0; i < model->artifact_info.file_descriptor_count; ++i) {
            const rac_model_file_descriptor_t& descriptor =
                model->artifact_info.file_descriptors[i];
            if (descriptor.size_bytes <= 0) {
                continue;
            }
            const char* name = descriptor.destination_path && descriptor.destination_path[0] != '\0'
                                   ? descriptor.destination_path
                                   : descriptor.relative_path;
            if (!name || name[0] == '\0') {
                continue;
            }
            std::error_code ec;
            const fs::path on_disk = fs::path(folder) / name;
            if (!fs::exists(on_disk, ec)) {
                continue;  // absence is the resolver's call (required vs optional)
            }
            if (should_skip_exact_size_check(model, descriptor, name)) {
                continue;
            }
            const auto actual = fs::file_size(on_disk, ec);
            if (!ec && static_cast<int64_t>(actual) != descriptor.size_bytes) {
                RAC_LOG_WARNING(LOG_CAT,
                                "File '%s' in '%s' is %lld bytes but the descriptor declares "
                                "%lld — treating folder as incomplete",
                                name, folder.c_str(), static_cast<long long>(actual),
                                static_cast<long long>(descriptor.size_bytes));
                complete = false;
                break;
            }
        }
    }
    return complete;
}

bool model_folder_is_complete(const ModelInfo& model, const std::string& folder) {
    rac_model_info_t* temp = model_info_from_proto(model);
    if (!temp) {
        return false;
    }
    const bool complete = model_folder_is_complete_struct(temp, folder);
    free_model_info(temp);
    return complete;
}

// Persist the durable sidecar for a model whose canonical folder exists on
// disk (downloaded, or download-in-progress). Best-effort: a metadata write
// must never fail the download/registration that triggered it. Caller holds
// the registry mutex.
void maybe_write_model_folder_manifest_locked(rac_model_registry_handle_t handle,
                                              const std::string& model_id) {
    if (!handle) {
        return;
    }
    auto it = handle->models.find(model_id);
    if (it == handle->models.end() || it->second == nullptr) {
        return;
    }
    const rac_model_info_t* model = it->second;

    // Only manage sidecars inside the canonical per-model folder; externally
    // imported paths (user-supplied literal files) are not ours to annotate.
    char folder_buffer[4096];
    if (rac_model_paths_get_model_folder(model_id.c_str(), model->framework, folder_buffer,
                                         sizeof(folder_buffer)) != RAC_SUCCESS) {
        return;
    }
    const std::string folder = folder_buffer;
    if (model->local_path && model->local_path[0] != '\0') {
        const std::string local_path = model->local_path;
        if (local_path != folder && !local_path.starts_with(folder + "/")) {
            return;
        }
    }
    std::error_code exists_ec;
    if (!fs::exists(folder, exists_ec)) {
        // Folder not created yet (never-downloaded catalog entry) or not
        // visible to std::filesystem (un-hydrated OPFS) — nothing to anchor
        // a sidecar to.
        return;
    }

    ModelInfo snapshot = model_snapshot_locked(handle, model_id, model);
    sanitize_for_manifest(&snapshot, model_is_downloaded_from_fields(snapshot));

    std::string serialized;
    if (!snapshot.SerializeToString(&serialized)) {
        RAC_LOG_WARNING(LOG_CAT, "Failed to serialize manifest for '%s'", model_id.c_str());
        return;
    }

    const std::string manifest_path = manifest_path_for_folder(folder);
    std::string existing;
    if (read_file_bytes(manifest_path, &existing) && existing == serialized) {
        return;  // up to date — avoid filesystem churn on every catalog re-seed
    }

    std::error_code ec;
    const std::string tmp_path = manifest_path + ".tmp";
    {
        std::ofstream out(tmp_path, std::ios::binary | std::ios::trunc);
        if (!out.is_open()) {
            RAC_LOG_WARNING(LOG_CAT, "Cannot open manifest tmp file at '%s'", tmp_path.c_str());
            return;
        }
        out.write(serialized.data(), static_cast<std::streamsize>(serialized.size()));
        if (!out.good()) {
            RAC_LOG_WARNING(LOG_CAT, "Short write for manifest tmp file at '%s'", tmp_path.c_str());
            out.close();
            fs::remove(tmp_path, ec);
            return;
        }
    }
    fs::rename(tmp_path, manifest_path, ec);
    if (ec) {
        RAC_LOG_WARNING(LOG_CAT, "Failed to move manifest into place at '%s': %s",
                        manifest_path.c_str(), ec.message().c_str());
        fs::remove(tmp_path, ec);
        return;
    }
    RAC_LOG_DEBUG(LOG_CAT, "Wrote model-folder manifest for '%s' (%zu bytes)", model_id.c_str(),
                  serialized.size());
}

// Restore one model folder from its manifest sidecar. Shared by the bulk
// cold-launch sweep and the by-id lookup-miss path. Takes the registry mutex
// internally — do NOT call while holding it. Returns true when an entry was
// (re-)registered.
static bool restore_manifest_folder(rac_model_registry_handle_t handle, const std::string& folder,
                                    const std::string& model_id) {
    std::string manifest_bytes;
    if (!read_file_bytes(manifest_path_for_folder(folder), &manifest_bytes) ||
        manifest_bytes.empty()) {
        return false;
    }

    ModelInfo parsed;
    if (!parsed.ParseFromArray(manifest_bytes.data(), static_cast<int>(manifest_bytes.size()))) {
        RAC_LOG_WARNING(LOG_CAT, "Corrupt manifest in '%s' — ignoring", folder.c_str());
        return false;
    }
    if (parsed.id() != model_id) {
        RAC_LOG_WARNING(LOG_CAT, "Manifest id '%s' does not match folder '%s' — ignoring",
                        parsed.id().c_str(), folder.c_str());
        return false;
    }

    const bool complete = model_folder_is_complete(parsed, folder);
    parsed.set_local_path(complete ? folder : "");
    overwrite_download_state_from_local_path(&parsed);

    rac_model_info_t* temp = model_info_from_proto(parsed);
    if (!temp) {
        return false;
    }
    const rac_result_t save_rc =
        save_model_info_impl(handle, temp, /*preserve_empty_local_path=*/false);
    free_model_info(temp);
    if (save_rc != RAC_SUCCESS) {
        RAC_LOG_WARNING(LOG_CAT, "Failed to restore '%s' from manifest (rc=%d)", model_id.c_str(),
                        save_rc);
        return false;
    }
    {
        // Carry proto-only fields (metadata, thinking pattern, artifact
        // descriptors) that the C-struct round trip above cannot.
        std::lock_guard<std::mutex> lock(handle->mutex);
        store_parsed_proto_snapshot_locked(handle, model_id, parsed);
    }
    RAC_LOG_INFO(LOG_CAT, "Restored '%s' from model-folder manifest (%s)", model_id.c_str(),
                 complete ? "downloaded" : "incomplete — needs re-pull");
    return true;
}

// Targeted lookup-miss restore: a consumer asked for an id the in-memory
// registry does not know (typical right after relaunch, before any Phase-2
// discovery sweep, for an ad-hoc URL/HF pull no catalog re-seeds). Probe the
// canonical layout for a folder named after the id carrying a manifest and
// restore just that entry. Cheap: one directory iteration over Models/ plus
// an existence check per framework dir. Walks std::filesystem directly —
// platforms whose storage is not std::filesystem-visible (un-hydrated OPFS)
// simply fall through to NOT_FOUND as before.
// Takes the registry mutex internally — do NOT call while holding it.
bool try_restore_model_manifest_by_id(rac_model_registry_handle_t handle,
                                      const std::string& model_id) {
    if (!handle || model_id.empty()) {
        return false;
    }
    if (!rac::path::is_safe_path_segment(model_id)) {
        return false;
    }
    char models_dir_buffer[4096];
    if (rac_model_paths_get_models_directory(models_dir_buffer, sizeof(models_dir_buffer)) !=
        RAC_SUCCESS) {
        return false;
    }
    std::error_code ec;
    fs::directory_iterator frameworks(models_dir_buffer, ec);
    if (ec) {
        return false;
    }
    for (const fs::directory_entry& framework_dir : frameworks) {
        if (!framework_dir.is_directory(ec)) {
            continue;
        }
        const fs::path folder = framework_dir.path() / model_id;
        if (!fs::exists(folder / rac::infra::model_manifest::kFilename, ec)) {
            continue;
        }
        return restore_manifest_folder(handle, folder.generic_string(), model_id);
    }
    return false;
}

// Cold-launch restore: walk {Models}/{framework}/{modelId}/ through the
// platform adapter and re-register any folder that carries a manifest but has
// no registry entry (i.e. nothing re-seeded it this launch). Complete folders
// come back as downloaded with a re-derived local_path; incomplete folders
// come back as registered-but-not-downloaded so a re-pull heals them.
// Takes the registry mutex internally per entry — do NOT call while holding it.
int32_t restore_models_from_folder_manifests(rac_model_registry_handle_t handle) {
    if (!handle) {
        return 0;
    }
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter || !adapter->file_list_directory) {
        return 0;
    }
    char models_dir_buffer[4096];
    if (rac_model_paths_get_models_directory(models_dir_buffer, sizeof(models_dir_buffer)) !=
        RAC_SUCCESS) {
        return 0;
    }
    const std::string models_dir = models_dir_buffer;

    std::vector<rac_directory_entry_t> framework_entries;
    if (list_directory_via_adapter(adapter, models_dir.c_str(), &framework_entries) !=
        RAC_SUCCESS) {
        return 0;
    }

    int32_t restored = 0;
    std::vector<rac_directory_entry_t> model_entries;
    for (const rac_directory_entry_t& framework_entry : framework_entries) {
        if (framework_entry.is_dir != RAC_TRUE || framework_entry.name[0] == '\0' ||
            framework_entry.name[0] == '.') {
            continue;
        }
        const std::string framework_dir = models_dir + "/" + framework_entry.name;
        if (list_directory_via_adapter(adapter, framework_dir.c_str(), &model_entries) !=
            RAC_SUCCESS) {
            continue;
        }
        for (const rac_directory_entry_t& model_entry : model_entries) {
            if (model_entry.is_dir != RAC_TRUE || model_entry.name[0] == '\0' ||
                model_entry.name[0] == '.') {
                continue;
            }
            const std::string model_id = model_entry.name;
            {
                std::lock_guard<std::mutex> lock(handle->mutex);
                if (handle->models.find(model_id) != handle->models.end()) {
                    continue;  // already re-seeded by a catalog this launch
                }
            }

            const std::string folder = framework_dir + "/" + model_id;
            if (restore_manifest_folder(handle, folder, model_id)) {
                ++restored;
            }
        }
    }
    return restored;
}

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// PRIVATE CROSS-TU API
// =============================================================================

namespace rac::infra::model_manifest {

rac_result_t persist(rac_model_registry_handle_t handle, const char* model_id) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    using namespace rac::infra::model_registry::detail;  // NOLINT(build/namespaces)
    if (!handle || !model_id || model_id[0] == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_inference_framework_t framework;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        auto it = handle->models.find(model_id);
        if (it == handle->models.end() || it->second == nullptr) {
            return RAC_ERROR_NOT_FOUND;
        }
        framework = it->second->framework;
    }

    // Ensure the canonical folder exists so the started-manifest has a home
    // (the writer requires folder presence as its anchor).
    char folder_buffer[4096];
    if (rac_model_paths_get_model_folder(model_id, framework, folder_buffer,
                                         sizeof(folder_buffer)) != RAC_SUCCESS) {
        return RAC_ERROR_INVALID_STATE;
    }
    std::error_code ec;
    fs::create_directories(folder_buffer, ec);
    if (ec) {
        RAC_LOG_WARNING(LOG_CAT, "Cannot create model folder '%s': %s", folder_buffer,
                        ec.message().c_str());
        return RAC_ERROR_FILE_WRITE_FAILED;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    maybe_write_model_folder_manifest_locked(handle, model_id);
    return RAC_SUCCESS;
#endif
}

}  // namespace rac::infra::model_manifest
