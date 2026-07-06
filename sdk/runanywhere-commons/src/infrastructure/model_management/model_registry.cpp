/**
 * @file model_registry.cpp
 * @brief RunAnywhere Commons - Model Registry Implementation (slim core)
 *
 * C++ port of Swift's ModelInfoService.
 * Swift Source: Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelInfoService.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 *
 * This is an in-memory model metadata store. This TU is the slim core after the
 * SRP split: registry lifecycle, struct-based CRUD, download-state
 * normalization, and the proto snapshot helpers. The proto<->C conversion, the
 * proto-byte ABI surface, filesystem discovery, and refresh/fetch live in the
 * sibling model_registry_{convert,proto,discovery,refresh}.cpp TUs, all sharing
 * model_registry_internal.h.
 *
 * Edge cases handled:
 *   - Re-seeded entry after app relaunch: reconcile_registry_with_filesystem_locked
 *     relinks local_path to the canonical
 *     {base}/RunAnywhere/Models/{framework}/{id}/ folder via
 *     canonical_model_folder_for + directory_contains_recognizable_model_file.
 *   - Download-state normalization: normalize_model_registry_state +
 *     overwrite_download_state_from_local_path derive is_downloaded/status from
 *     local_path presence.
 *   - Partial-update preservation: preserve_absent_proto_fields — an update proto
 *     with empty local_path/artifact does not clobber existing values (avoids
 *     wiping download state on metadata-only updates).
 *   - Built-in vs user models: model_is_built_in entries are excluded from
 *     discovery unless include_built_in is set.
 *   - Path-root filtering in discover: path_matches_roots.
 *   - Proto/struct dual storage: model_proto_bytes snapshot preserves fields the
 *     legacy C struct cannot represent.
 *   - Empty/duplicate model_id, missing handle, protobuf-unavailable build →
 *     structured errors.
 */

#include "model_registry_internal.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

using namespace rac::infra::model_registry::detail;  // NOLINT(build/namespaces)

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp
// Note: the rac_model_registry struct definition lives in model_registry_internal.h.

#ifdef RAC_HAVE_PROTOBUF

namespace rac::infra::model_registry::detail {

// -----------------------------------------------------------------------------
// Download-state normalization
// -----------------------------------------------------------------------------

bool has_nonempty_local_path(const ModelInfo& model) {
    return !model.local_path().empty();
}

bool registry_status_is_downloaded(ModelRegistryStatus status) {
    return status == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED ||
           status == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED;
}

bool model_is_downloaded_from_fields(const ModelInfo& model) {
    if (has_nonempty_local_path(model)) {
        return true;
    }
    if (model.has_is_downloaded()) {
        return model.is_downloaded();
    }
    if (model.has_registry_status()) {
        return registry_status_is_downloaded(model.registry_status());
    }
    return false;
}

ModelRegistryStatus effective_registry_status(const ModelInfo& model) {
    if (model.has_registry_status()) {
        return model.registry_status();
    }
    return model_is_downloaded_from_fields(model)
               ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
               : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED;
}

void normalize_model_registry_state(ModelInfo* model) {
    if (!model) {
        return;
    }

    if (has_nonempty_local_path(*model)) {
        overwrite_download_state_from_local_path(model);
        return;
    }

    const bool downloaded = model_is_downloaded_from_fields(*model);
    if (!model->has_is_downloaded()) {
        model->set_is_downloaded(downloaded);
    }
    if (!model->has_is_available()) {
        model->set_is_available(downloaded);
    }
    if (!model->has_registry_status()) {
        model->set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                              : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    }
}

void overwrite_download_state_from_local_path(ModelInfo* model) {
    if (!model) {
        return;
    }

    const bool downloaded = has_nonempty_local_path(*model);
    model->set_is_downloaded(downloaded);
    model->set_is_available(downloaded);

    const ModelRegistryStatus current = effective_registry_status(*model);
    if (downloaded) {
        if (current != runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED &&
            current != runanywhere::v1::MODEL_REGISTRY_STATUS_LOADING &&
            current != runanywhere::v1::MODEL_REGISTRY_STATUS_ERROR) {
            model->set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
        }
    } else if (registry_status_is_downloaded(current) ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADING ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADING ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_UNSPECIFIED) {
        model->set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    }
}

// -----------------------------------------------------------------------------
// Proto snapshot helpers
// -----------------------------------------------------------------------------

rac_result_t store_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                         const std::string& model_id, const rac_model_info_t* model,
                                         bool preserve_proto_only_fields,
                                         bool overwrite_registry_state) {
    ModelInfo snapshot;
    bool parsed_existing = false;
    if (preserve_proto_only_fields) {
        auto proto_it = handle->model_proto_bytes.find(model_id);
        if (proto_it != handle->model_proto_bytes.end()) {
            parsed_existing = snapshot.ParseFromString(proto_it->second);
        }
    }
    if (!parsed_existing) {
        snapshot.Clear();
    }

    if (parsed_existing) {
        overlay_struct_runtime_fields_to_proto(model, &snapshot, overwrite_registry_state);
    } else {
        model_info_to_proto(model, &snapshot,
                            /*overwrite_artifact=*/true, overwrite_registry_state);
    }
    if (!snapshot.SerializeToString(&handle->model_proto_bytes[model_id])) {
        handle->model_proto_bytes.erase(model_id);
        return RAC_ERROR_UNKNOWN;
    }
    return RAC_SUCCESS;
}

rac_result_t store_parsed_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id,
                                                const ModelInfo& parsed_proto) {
    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    ModelInfo snapshot(parsed_proto);
    normalize_model_registry_state(&snapshot);
    overlay_struct_runtime_fields_to_proto(it->second, &snapshot,
                                           /*overwrite_registry_state=*/false);
    if (!snapshot.SerializeToString(&handle->model_proto_bytes[model_id])) {
        handle->model_proto_bytes.erase(model_id);
        return RAC_ERROR_UNKNOWN;
    }
    return RAC_SUCCESS;
}

ModelInfo model_snapshot_locked(rac_model_registry_handle_t handle, const std::string& model_id,
                                const rac_model_info_t* model) {
    ModelInfo snapshot;
    auto proto_it = handle->model_proto_bytes.find(model_id);
    if (proto_it != handle->model_proto_bytes.end() && snapshot.ParseFromString(proto_it->second)) {
        overlay_struct_runtime_fields_to_proto(model, &snapshot,
                                               /*overwrite_registry_state=*/false);
    } else {
        snapshot.Clear();
        model_info_to_proto(model, &snapshot,
                            /*overwrite_artifact=*/true,
                            /*overwrite_registry_state=*/true);
    }
    normalize_model_registry_state(&snapshot);
    return snapshot;
}

rac_result_t model_to_proto_bytes_locked(rac_model_registry_handle_t handle,
                                         const std::string& model_id, const rac_model_info_t* model,
                                         uint8_t** proto_bytes_out, size_t* proto_size_out) {
    ModelInfo snapshot = model_snapshot_locked(handle, model_id, model);
    return serialize_proto_to_owned_buffer(snapshot, proto_bytes_out, proto_size_out);
}

int64_t imported_size_for_request(const ModelImportRequest& request, const ModelInfo& model) {
    int64_t total = 0;
    for (const ModelFileDescriptor& file : request.files()) {
        if (file.has_size_bytes() && file.size_bytes() > 0) {
            total += file.size_bytes();
        }
    }
    if (total > 0) {
        return total;
    }
    return model.download_size_bytes() > 0 ? model.download_size_bytes() : 0;
}

bool get_model_snapshot_by_id(rac_model_registry_handle_t handle, const std::string& model_id,
                              ModelInfo* out) {
    if (!handle || !out) {
        return false;
    }
    for (int attempt = 0; attempt < 2; ++attempt) {
        {
            std::lock_guard<std::mutex> lock(handle->mutex);
            auto it = handle->models.find(model_id);
            if (it != handle->models.end()) {
                *out = model_snapshot_locked(handle, model_id, it->second);
                normalize_model_registry_state(out);
                return true;
            }
        }
        // Lookup miss: an ad-hoc pull from a previous run may exist on disk
        // with a manifest sidecar but no re-seeded entry. Restore once, retry.
        if (attempt > 0 || !try_restore_model_manifest_by_id(handle, model_id)) {
            break;
        }
    }
    return false;
}

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// PUBLIC API - LIFECYCLE
// =============================================================================

rac_result_t rac_model_registry_create(rac_model_registry_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_model_registry* registry = new (std::nothrow) rac_model_registry();
    if (!registry) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    RAC_LOG_INFO("ModelRegistry", "Model registry created");

    *out_handle = registry;
    return RAC_SUCCESS;
}

void rac_model_registry_destroy(rac_model_registry_handle_t handle) {
    if (!handle) {
        return;
    }

    // Free all stored models
    for (auto& pair : handle->models) {
        free_model_info(pair.second);
    }
    handle->models.clear();

    delete handle;
    RAC_LOG_DEBUG("ModelRegistry", "Model registry destroyed");
}

// =============================================================================
// PUBLIC API - MODEL INFO
// =============================================================================

namespace rac::infra::model_registry::detail {

// Shared save implementation. `preserve_empty_local_path` controls the
// legacy "registerModel() passes localPath=nil, keep the existing one"
// heuristic: the C struct cannot carry proto field-presence, so for the
// non-proto callers (Swift/Kotlin/etc. registerModel and platform/auto
// registration) an empty incoming local_path is treated as "unset" and the
// existing path is kept. The proto register/update paths set this to false
// because they have already resolved local_path presence-aware in the proto
// domain (preserve_absent_proto_fields), so an empty local_path there is an
// *explicit* reset that must win.
rac_result_t save_model_info_impl(rac_model_registry_handle_t handle, const rac_model_info_t* model,
                                  bool preserve_empty_local_path) {
    if (!handle || !model || !model->id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string model_id = model->id;

    auto it = handle->models.find(model_id);
    if (it != handle->models.end()) {
        // Preserve existing local_path if the incoming model doesn't have one.
        // This prevents registerModel() (which always passes localPath=nil) from
        // overwriting a localPath that was set by download completion or discovery.
        const char* existing_local_path = it->second->local_path;
        bool should_preserve_path =
            preserve_empty_local_path && (existing_local_path != nullptr) &&
            strlen(existing_local_path) > 0 &&
            (model->local_path == nullptr || strlen(model->local_path) == 0);

        // Store a deep copy of the incoming model
        rac_model_info_t* copy = deep_copy_model(model);
        if (!copy) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        if (should_preserve_path) {
            if (copy->local_path)
                free(copy->local_path);
            copy->local_path = rac_strdup(existing_local_path);
        }

        free_model_info(it->second);
        handle->models[model_id] = copy;
    } else {
        // New model — store a deep copy
        rac_model_info_t* copy = deep_copy_model(model);
        if (!copy) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        handle->models[model_id] = copy;
    }

#ifdef RAC_HAVE_PROTOBUF
    auto stored = handle->models.find(model_id);
    if (stored != handle->models.end()) {
        rac_result_t proto_rc = store_proto_snapshot_locked(handle, model_id, stored->second,
                                                            /*preserve_proto_only_fields=*/false,
                                                            /*overwrite_registry_state=*/true);
        if (proto_rc != RAC_SUCCESS) {
            return proto_rc;
        }

        // Self-healing reconcile: if the incoming entry has no local_path but
        // the canonical {base_dir}/RunAnywhere/Models/{framework}/{id}/ folder
        // already exists on disk (typical for the 2nd app launch after a
        // previous download), relink local_path immediately. This removes the
        // ordering dependency between registerModel() and the one-shot
        // discoverDownloadedModels() sweep in Phase 2.
        try_reconcile_model_local_path_locked(handle, model_id, stored->second);

        // Keep the durable model-folder manifest in sync (no-op unless the
        // entry is downloaded inside the canonical layout, and skipped when
        // the on-disk bytes already match).
        maybe_write_model_folder_manifest_locked(handle, model_id);
    }
#endif

    RAC_LOG_DEBUG("ModelRegistry", "Model saved");

    return RAC_SUCCESS;
}

}  // namespace rac::infra::model_registry::detail

rac_result_t rac_model_registry_save(rac_model_registry_handle_t handle,
                                     const rac_model_info_t* model) {
    // Legacy / non-proto callers: keep the "empty local_path means unset, so
    // preserve the existing one" behaviour.
    return save_model_info_impl(handle, model, /*preserve_empty_local_path=*/true);
}

rac_result_t rac_model_registry_get(rac_model_registry_handle_t handle, const char* model_id,
                                    rac_model_info_t** out_model) {
    if (!handle || !model_id || !out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    for (int attempt = 0; attempt < 2; ++attempt) {
        {
            std::lock_guard<std::mutex> lock(handle->mutex);
            auto it = handle->models.find(model_id);
            if (it != handle->models.end()) {
                *out_model = deep_copy_model(it->second);
                return *out_model ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
            }
        }
#ifdef RAC_HAVE_PROTOBUF
        // Lookup miss: an ad-hoc pull from a previous run may exist on disk
        // with a manifest sidecar but no re-seeded entry. Restore once, retry.
        if (attempt > 0 || !try_restore_model_manifest_by_id(handle, model_id)) {
            break;
        }
#else
        break;
#endif
    }
    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_model_registry_get_by_path(rac_model_registry_handle_t handle,
                                            const char* local_path, rac_model_info_t** out_model) {
    if (!handle || !local_path || !out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Search through all models for matching local_path
    for (const auto& pair : handle->models) {
        const rac_model_info_t* model = pair.second;
        if (model->local_path && strcmp(model->local_path, local_path) == 0) {
            *out_model = deep_copy_model(model);
            if (!*out_model) {
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            RAC_LOG_DEBUG("ModelRegistry", "Found model by path: %s -> %s", local_path, model->id);
            return RAC_SUCCESS;
        }
    }

    // Also check if the path starts with or contains the local_path
    // This handles cases where the input path has extra components
    std::string search_path(local_path);
    for (const auto& pair : handle->models) {
        const rac_model_info_t* model = pair.second;
        if (model->local_path) {
            std::string model_path(model->local_path);
            // Check if search path starts with model's local_path
            if (search_path.starts_with(model_path) || model_path.starts_with(search_path)) {
                *out_model = deep_copy_model(model);
                if (!*out_model) {
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
                RAC_LOG_DEBUG("ModelRegistry", "Found model by partial path match: %s -> %s",
                              local_path, model->id);
                return RAC_SUCCESS;
            }
        }
    }

    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_model_registry_get_all(rac_model_registry_handle_t handle,
                                        rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    *out_count = handle->models.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    size_t i = 0;
    for (const auto& pair : handle->models) {
        (*out_models)[i] = deep_copy_model(pair.second);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(static_cast<void*>(*out_models));
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        ++i;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_by_frameworks(rac_model_registry_handle_t handle,
                                                  const rac_inference_framework_t* frameworks,
                                                  size_t framework_count,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    if (!handle || !frameworks || framework_count == 0 || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect matching models
    std::vector<rac_model_info_t*> matches;

    for (const auto& pair : handle->models) {
        for (size_t i = 0; i < framework_count; ++i) {
            if (pair.second->framework == frameworks[i]) {
                matches.push_back(pair.second);
                break;
            }
        }
    }

    *out_count = matches.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < matches.size(); ++i) {
        (*out_models)[i] = deep_copy_model(matches[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(static_cast<void*>(*out_models));
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_last_used(rac_model_registry_handle_t handle,
                                                 const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;
    model->last_used = rac_get_current_time_ms() / 1000;  // Convert to seconds
    model->usage_count++;

#ifdef RAC_HAVE_PROTOBUF
    return store_proto_snapshot_locked(handle, model_id, model,
                                       /*preserve_proto_only_fields=*/true,
                                       /*overwrite_registry_state=*/false);
#else
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_model_registry_remove(rac_model_registry_handle_t handle, const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    free_model_info(it->second);
    handle->models.erase(it);
#ifdef RAC_HAVE_PROTOBUF
    handle->model_proto_bytes.erase(model_id);
#endif

    RAC_LOG_DEBUG("ModelRegistry", "Model removed");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_downloaded(rac_model_registry_handle_t handle,
                                               rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect downloaded models
    std::vector<rac_model_info_t*> downloaded;

    for (const auto& pair : handle->models) {
        if (pair.second->local_path && strlen(pair.second->local_path) > 0) {
            downloaded.push_back(pair.second);
        }
    }

    *out_count = downloaded.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < downloaded.size(); ++i) {
        (*out_models)[i] = deep_copy_model(downloaded[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(static_cast<void*>(*out_models));
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_download_status(rac_model_registry_handle_t handle,
                                                       const char* model_id,
                                                       const char* local_path) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;

    // Free old local path
    if (model->local_path) {
        free(model->local_path);
    }

    // Set new local path
    model->local_path = rac_strdup(local_path);
    model->updated_at = rac_get_current_time_ms() / 1000;

#ifdef RAC_HAVE_PROTOBUF
    const rac_result_t snapshot_rc =
        store_proto_snapshot_locked(handle, model_id, model,
                                    /*preserve_proto_only_fields=*/true,
                                    /*overwrite_registry_state=*/true);
    if (snapshot_rc == RAC_SUCCESS && local_path && local_path[0] != '\0') {
        // Download landed (orchestrator completion / refresh relink): persist
        // the durable model-folder manifest beside the artifacts.
        maybe_write_model_folder_manifest_locked(handle, model_id);
    }
    return snapshot_rc;
#else
    return RAC_SUCCESS;
#endif
}
