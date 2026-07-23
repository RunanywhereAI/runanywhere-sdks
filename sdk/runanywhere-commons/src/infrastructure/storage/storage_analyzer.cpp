/**
 * @file storage_analyzer.cpp
 * @brief Storage Analyzer Implementation
 *
 * Business logic for storage analysis.
 * - Uses rac_model_registry for model listing
 * - Uses rac_model_paths for path calculations
 * - Calls platform callbacks for file operations
 *
 * Edge cases handled:
 *   - Dedup warnings: add_warning_once + seen_warnings set so the same warning
 *     is not emitted twice.
 *   - Model with no model_id / no local_path / missing-on-disk path → per-model
 *     warning, skipped from the delete plan.
 *   - Loaded-model state unavailable → kLoadedStateUnavailableWarning so the
 *     lifecycle layer is told to verify before deleting a loaded model.
 *   - Optional cache inclusion (include_cache).
 *   - Model-not-found by id → warning.
 *   - Empty/malformed request → parse_request_or_empty returns an empty set,
 *     treated as a no-op.
 */

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ranges>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "infrastructure/download/blob_store.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"
#include "rac/infrastructure/storage/storage_event_publisher.h"

#ifdef RAC_HAVE_PROTOBUF
#include "download_service.pb.h"
#include "sdk_events.pb.h"
#include "storage_types.pb.h"
#endif

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_storage_analyzer {
    rac_storage_callbacks_t callbacks;
};

namespace {

constexpr const char* kLoadedStateUnavailableWarning =
    "Loaded model state is unavailable; lifecycle integration should verify models are "
    "unloaded before deleting files.";

int64_t clamp_non_negative(int64_t value) {
    return value < 0 ? 0 : value;
}

float used_percent(int64_t total, int64_t used) {
    if (total <= 0 || used <= 0) {
        return 0.0f;
    }
    double percent = (static_cast<double>(used) / static_cast<double>(total)) * 100.0;
    if (percent < 0.0) {
        percent = 0.0;
    } else if (percent > 100.0) {
        percent = 100.0;
    }
    return static_cast<float>(percent);
}

std::string status_message(rac_result_t status, const char* fallback) {
    char message[160];
    std::snprintf(message, sizeof(message), "%s (status %d)", fallback, static_cast<int>(status));
    return {message};
}

rac_result_t copy_string_to_proto_buffer(const std::string& bytes, rac_proto_buffer_t* out_buffer) {
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_buffer);
}

#ifndef RAC_HAVE_PROTOBUF
rac_result_t storage_proto_unavailable(rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return rac_proto_buffer_set_error(out_buffer, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "Storage proto ABI requires protobuf support.");
}
#else

template <typename ProtoMessage>
rac_result_t serialize_to_buffer(const ProtoMessage& message, rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return rac_proto_buffer_set_error(out_buffer, RAC_ERROR_STORAGE_ERROR,
                                          "Failed to serialize storage proto result.");
    }
    return copy_string_to_proto_buffer(bytes, out_buffer);
}

template <typename Request>
bool parse_request_or_empty(const uint8_t* request_proto_bytes, size_t request_proto_size,
                            Request* out_request) {
    if (!out_request) {
        return false;
    }
    if (request_proto_size == 0) {
        return true;
    }
    if (!request_proto_bytes) {
        return false;
    }
    return out_request->ParseFromArray(request_proto_bytes, static_cast<int>(request_proto_size));
}

bool append_model_ids_from_request(const runanywhere::v1::StorageDeletePlanRequest& request,
                                   std::unordered_set<std::string>* out_ids) {
    if (!out_ids) {
        return false;
    }
    for (const auto& id : request.model_ids()) {
        if (!id.empty()) {
            out_ids->insert(id);
        }
    }
    return !out_ids->empty();
}

std::vector<std::string>
ordered_model_ids_from_request(const runanywhere::v1::StorageDeleteRequest& request) {
    std::vector<std::string> ids;
    std::unordered_set<std::string> seen;
    for (const auto& id : request.model_ids()) {
        if (!id.empty() && seen.insert(id).second) {
            ids.push_back(id);
        }
    }
    return ids;
}

int64_t model_metric_size(rac_storage_analyzer_handle_t handle, const rac_model_info_t* model,
                          const char* path_to_use) {
    if (!handle || !model) {
        return 0;
    }
    if (path_to_use && std::strlen(path_to_use) > 0) {
        return clamp_non_negative(
            handle->callbacks.calculate_dir_size(path_to_use, handle->callbacks.user_data));
    }
    return clamp_non_negative(model->download_size);
}

bool known_loaded_state(rac_storage_analyzer_handle_t handle, const char* model_id,
                        bool* out_is_loaded) {
    if (!handle || !model_id || !out_is_loaded || !handle->callbacks.is_model_loaded) {
        return false;
    }
    rac_bool_t is_loaded = RAC_FALSE;
    rac_result_t result =
        handle->callbacks.is_model_loaded(model_id, &is_loaded, handle->callbacks.user_data);
    if (RAC_FAILED(result)) {
        return false;
    }
    *out_is_loaded = (is_loaded == RAC_TRUE);
    return true;
}

bool path_exists_if_callback_present(rac_storage_analyzer_handle_t handle, const char* path) {
    if (!handle || !path || std::strlen(path) == 0) {
        return false;
    }
    if (!handle->callbacks.path_exists) {
        return true;
    }
    rac_bool_t is_directory = RAC_FALSE;
    return handle->callbacks.path_exists(path, &is_directory, handle->callbacks.user_data) ==
           RAC_TRUE;
}

void add_warning_once(runanywhere::v1::StorageDeletePlan* plan,
                      std::unordered_set<std::string>* seen_warnings, const std::string& warning) {
    if (!plan || warning.empty()) {
        return;
    }
    if (seen_warnings == nullptr || seen_warnings->insert(warning).second) {
        plan->add_warnings(warning);
    }
}

void add_warning_once(runanywhere::v1::StorageDeleteResult* result,
                      std::unordered_set<std::string>* seen_warnings, const std::string& warning) {
    if (!result || warning.empty()) {
        return;
    }
    if (seen_warnings == nullptr || seen_warnings->insert(warning).second) {
        result->add_warnings(warning);
    }
}

// Cancel any in-flight download for `model_id` before its files are deleted so
// the download worker does not race the deleter and re-create partials under a
// freshly removed folder (A18). delete_partial_bytes=true tells the orchestrator
// to reclaim the "<final>.part" file it was streaming into. The call is a no-op
// (RAC_ERROR_NOT_FOUND / non-running task) when no download is active, so it is
// safe to invoke unconditionally on the delete path.
void cancel_inflight_download(const std::string& model_id) {
    if (model_id.empty()) {
        return;
    }
    runanywhere::v1::DownloadCancelRequest cancel_request;
    cancel_request.set_model_id(model_id);
    cancel_request.set_delete_partial_bytes(true);
    std::string cancel_bytes;
    if (!cancel_request.SerializeToString(&cancel_bytes)) {
        return;
    }
    rac_proto_buffer_t cancel_out;
    rac_proto_buffer_init(&cancel_out);
    rac_download_cancel_proto(reinterpret_cast<const uint8_t*>(cancel_bytes.data()),
                              cancel_bytes.size(), &cancel_out);
    rac_proto_buffer_free(&cancel_out);
}

// Resolve the per-model folder `{base}/RunAnywhere/Models/{framework}/{model_id}/`.
// Deleting the whole folder (rather than the single registry local_path file)
// reclaims interrupted-download partials ("<final>.part") and the folder itself,
// and works even when local_path is empty (A8). Returns empty on failure.
std::string model_folder_path(const std::string& model_id, rac_inference_framework_t framework) {
    if (model_id.empty()) {
        return {};
    }
    char folder[1024];
    if (rac_model_paths_get_model_folder(model_id.c_str(), framework, folder, sizeof(folder)) !=
        RAC_SUCCESS) {
        return {};
    }
    return folder;
}

struct DeleteCandidateRow {
    std::string model_id;
    std::string local_path;
    std::string storage_key;
    int64_t reclaimable_bytes = 0;
    int64_t last_used = 0;
    bool has_last_used = false;
    bool is_loaded = false;
    bool requires_unload = false;
    bool requires_platform_delete = false;
    int priority = 10;
};

struct DeletePlanOptions {
    int64_t required_bytes = 0;
    bool include_cache = false;
    bool include_download_partials = false;
    bool allow_loaded_models = false;
    bool oldest_first = false;
};

using DirectoryPathFn = rac_result_t (*)(char*, size_t);

bool resolve_storage_directory(DirectoryPathFn path_fn, const char* label, std::string* out_path,
                               runanywhere::v1::StorageDeletePlan* plan,
                               std::unordered_set<std::string>* seen_warnings) {
    if (!path_fn || !out_path) {
        return false;
    }
    char path[1024];
    rac_result_t result = path_fn(path, sizeof(path));
    if (RAC_FAILED(result)) {
        std::string message =
            std::string("Unable to resolve ") + (label ? label : "storage") + " directory";
        add_warning_once(plan, seen_warnings, status_message(result, message.c_str()));
        return false;
    }
    *out_path = path;
    return true;
}

void add_directory_candidate(rac_storage_analyzer_handle_t handle, DirectoryPathFn path_fn,
                             const char* storage_key, const char* label, int priority,
                             std::vector<DeleteCandidateRow>* rows,
                             runanywhere::v1::StorageDeletePlan* plan,
                             std::unordered_set<std::string>* seen_warnings) {
    if (!handle || !rows || !storage_key || !label) {
        return;
    }

    std::string path;
    if (!resolve_storage_directory(path_fn, label, &path, plan, seen_warnings)) {
        return;
    }
    if (!path_exists_if_callback_present(handle, path.c_str())) {
        add_warning_once(plan, seen_warnings,
                         std::string(label) + " directory is unavailable: " + path);
        return;
    }

    int64_t bytes = clamp_non_negative(
        handle->callbacks.calculate_dir_size(path.c_str(), handle->callbacks.user_data));
    if (bytes <= 0) {
        return;
    }

    DeleteCandidateRow row;
    row.local_path = path;
    row.storage_key = storage_key;
    row.reclaimable_bytes = bytes;
    row.requires_platform_delete = true;
    row.priority = priority;
    rows->push_back(row);
}

void add_model_candidate_from_info(rac_storage_analyzer_handle_t handle,
                                   const rac_model_info_t* current, const std::string& requested_id,
                                   bool allow_loaded_models, std::vector<DeleteCandidateRow>* rows,
                                   runanywhere::v1::StorageDeletePlan* plan,
                                   std::unordered_set<std::string>* seen_warnings) {
    if (!handle || !current || !rows) {
        return;
    }

    const std::string id = current->id && current->id[0] != '\0' ? current->id : requested_id;
    if (id.empty()) {
        add_warning_once(plan, seen_warnings, "Model candidate has no model_id.");
        return;
    }

    if (!current->local_path || std::strlen(current->local_path) == 0) {
        add_warning_once(plan, seen_warnings, "Model has no local path: " + id);
        return;
    }

    bool is_loaded = false;
    bool has_loaded_state = known_loaded_state(handle, current->id, &is_loaded);
    if (!has_loaded_state) {
        add_warning_once(plan, seen_warnings, kLoadedStateUnavailableWarning);
    }
    if (is_loaded && !allow_loaded_models) {
        add_warning_once(plan, seen_warnings,
                         "Model is loaded and cannot be safely deleted: " + id);
        return;
    }

    if (!path_exists_if_callback_present(handle, current->local_path)) {
        add_warning_once(plan, seen_warnings, "Model path is missing: " + id);
        return;
    }

    DeleteCandidateRow row;
    row.model_id = id;
    row.local_path = current->local_path;
    row.storage_key = "model:" + id;
    row.reclaimable_bytes = model_metric_size(handle, current, current->local_path);
    row.last_used = current->last_used;
    row.has_last_used = current->last_used > 0;
    row.is_loaded = is_loaded;
    row.requires_unload = is_loaded;
    row.requires_platform_delete = true;
    row.priority = 10;
    rows->push_back(row);
}

std::vector<DeleteCandidateRow> collect_model_delete_candidates(
    rac_storage_analyzer_handle_t handle, rac_model_registry_handle_t registry_handle,
    const std::unordered_set<std::string>& requested_ids, bool has_requested_ids,
    const DeletePlanOptions& options, runanywhere::v1::StorageDeletePlan* plan,
    std::unordered_set<std::string>* seen_warnings) {
    std::vector<DeleteCandidateRow> rows;

    if (!registry_handle) {
        add_warning_once(plan, seen_warnings,
                         "Registry handle is unavailable; model storage candidates were not "
                         "inspected.");
        return rows;
    }

    rac_model_info_t** models = nullptr;
    size_t model_count = 0;
    rac_result_t result = RAC_SUCCESS;

    if (has_requested_ids) {
        for (const auto& id : requested_ids) {
            rac_model_info_t* model = nullptr;
            result = rac_model_registry_get(registry_handle, id.c_str(), &model);
            if (RAC_FAILED(result) || !model) {
                add_warning_once(plan, seen_warnings, "Model not found: " + id);
                continue;
            }
            add_model_candidate_from_info(handle, model, id, options.allow_loaded_models, &rows,
                                          plan, seen_warnings);
            rac_model_info_free(model);
        }
    } else {
        result = rac_model_registry_get_downloaded(registry_handle, &models, &model_count);
        if (RAC_FAILED(result)) {
            add_warning_once(plan, seen_warnings,
                             status_message(result, "Unable to list downloaded models"));
            return rows;
        }
        for (size_t i = 0; i < model_count; ++i) {
            const rac_model_info_t* current = models[i];
            if (!current || !current->id || !current->local_path ||
                std::strlen(current->local_path) == 0) {
                continue;
            }
            add_model_candidate_from_info(handle, current, current->id, options.allow_loaded_models,
                                          &rows, plan, seen_warnings);
        }
        rac_model_info_array_free(models, model_count);
    }

    if (options.oldest_first) {
        std::ranges::sort(rows, [](const DeleteCandidateRow& lhs, const DeleteCandidateRow& rhs) {
            if (lhs.last_used != rhs.last_used) {
                return lhs.last_used < rhs.last_used;
            }
            return lhs.model_id < rhs.model_id;
        });
    } else {
        std::ranges::sort(rows, [](const DeleteCandidateRow& lhs, const DeleteCandidateRow& rhs) {
            if (lhs.reclaimable_bytes != rhs.reclaimable_bytes) {
                return lhs.reclaimable_bytes > rhs.reclaimable_bytes;
            }
            return lhs.model_id < rhs.model_id;
        });
    }

    return rows;
}

runanywhere::v1::StorageDeletePlan
build_delete_plan(rac_storage_analyzer_handle_t handle, rac_model_registry_handle_t registry_handle,
                  const std::unordered_set<std::string>& requested_ids, bool has_requested_ids,
                  const DeletePlanOptions& options) {
    runanywhere::v1::StorageDeletePlan plan;
    plan.set_required_bytes(clamp_non_negative(options.required_bytes));

    std::unordered_set<std::string> warnings;
    std::vector<DeleteCandidateRow> rows;
    if (!handle) {
        plan.set_error_message("Storage analyzer handle is required.");
        return plan;
    }

    if (options.include_cache) {
        add_directory_candidate(handle, rac_model_paths_get_cache_directory, "cache", "Cache", 0,
                                &rows, &plan, &warnings);
    }
    if (options.include_download_partials) {
        add_directory_candidate(handle, rac_model_paths_get_temp_directory, "temp", "Temp", 1,
                                &rows, &plan, &warnings);
        add_directory_candidate(handle, rac_model_paths_get_downloads_directory,
                                "download_partials", "Download partials", 2, &rows, &plan,
                                &warnings);
    }

    std::vector<DeleteCandidateRow> model_rows = collect_model_delete_candidates(
        handle, registry_handle, requested_ids, has_requested_ids, options, &plan, &warnings);
    rows.insert(rows.end(), model_rows.begin(), model_rows.end());

    int64_t reclaimable = 0;
    bool requires_unload = false;
    bool requires_platform_delete = false;
    for (const auto& row : rows) {
        if (plan.required_bytes() > 0 && reclaimable >= plan.required_bytes() &&
            !has_requested_ids) {
            break;
        }
        auto* candidate = plan.add_candidates();
        candidate->set_model_id(row.model_id);
        candidate->set_reclaimable_bytes(clamp_non_negative(row.reclaimable_bytes));
        if (row.has_last_used) {
            candidate->set_last_used_ms(row.last_used);
        }
        candidate->set_is_loaded(row.is_loaded);
        candidate->set_local_path(row.local_path);
        candidate->set_requires_unload(row.requires_unload);
        candidate->set_requires_platform_delete(row.requires_platform_delete);
        candidate->set_storage_key(row.storage_key);
        reclaimable += clamp_non_negative(row.reclaimable_bytes);
        requires_unload = requires_unload || row.requires_unload;
        requires_platform_delete = requires_platform_delete || row.requires_platform_delete;
    }

    plan.set_reclaimable_bytes(reclaimable);
    plan.set_candidate_count(plan.candidates_size());
    plan.set_requires_unload(requires_unload);
    plan.set_requires_platform_delete(requires_platform_delete);
    plan.set_can_reclaim_required_bytes(plan.required_bytes() <= 0 ||
                                        reclaimable >= plan.required_bytes());
    if (!plan.can_reclaim_required_bytes() && plan.error_message().empty()) {
        plan.set_error_message("Not enough safe reclaimable storage is available.");
    }
    return plan;
}

rac_result_t finish_info_result(const runanywhere::v1::StorageInfoResult& result,
                                rac_result_t error_code, rac_proto_buffer_t* out_buffer) {
    rac::storage::publish_storage_info_event(result, error_code);
    return serialize_to_buffer(result, out_buffer);
}

rac_result_t finish_availability_result(const runanywhere::v1::StorageAvailabilityResult& result,
                                        rac_result_t error_code, rac_proto_buffer_t* out_buffer) {
    rac::storage::publish_storage_availability_event(result, error_code);
    return serialize_to_buffer(result, out_buffer);
}

rac_result_t finish_delete_plan(const runanywhere::v1::StorageDeletePlan& plan,
                                rac_result_t error_code, rac_proto_buffer_t* out_buffer) {
    rac::storage::publish_storage_delete_plan_event(plan, error_code);
    return serialize_to_buffer(plan, out_buffer);
}

rac_result_t finish_delete_result(const runanywhere::v1::StorageDeleteResult& result,
                                  rac_result_t error_code, rac_proto_buffer_t* out_buffer) {
    rac::storage::publish_storage_delete_result_event(result, error_code);
    return serialize_to_buffer(result, out_buffer);
}

#endif

}  // namespace

// =============================================================================
// LIFECYCLE
// =============================================================================

rac_result_t rac_storage_analyzer_create(const rac_storage_callbacks_t* callbacks,
                                         rac_storage_analyzer_handle_t* out_handle) {
    if (!callbacks || !out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Validate required callbacks
    if (!callbacks->calculate_dir_size || !callbacks->get_available_space ||
        !callbacks->get_total_space) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* analyzer = new (std::nothrow) rac_storage_analyzer();
    if (!analyzer) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    analyzer->callbacks = *callbacks;
    *out_handle = analyzer;
    return RAC_SUCCESS;
}

void rac_storage_analyzer_destroy(rac_storage_analyzer_handle_t handle) {
    delete handle;
}

// =============================================================================
// STORAGE ANALYSIS
// =============================================================================

rac_result_t rac_storage_analyzer_analyze(rac_storage_analyzer_handle_t handle,
                                          rac_model_registry_handle_t registry_handle,
                                          rac_storage_info_t* out_info) {
    if (!handle || !registry_handle || !out_info) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    memset(out_info, 0, sizeof(rac_storage_info_t));

    // Get device storage via callbacks
    out_info->device_storage.free_space =
        handle->callbacks.get_available_space(handle->callbacks.user_data);
    out_info->device_storage.total_space =
        handle->callbacks.get_total_space(handle->callbacks.user_data);
    out_info->device_storage.used_space =
        out_info->device_storage.total_space - out_info->device_storage.free_space;

    // Get app storage - calculate base directory size
    char base_dir[1024];
    if (rac_model_paths_get_base_directory(base_dir, sizeof(base_dir)) == RAC_SUCCESS) {
        out_info->app_storage.documents_size =
            handle->callbacks.calculate_dir_size(base_dir, handle->callbacks.user_data);
    }
    char cache_dir[1024];
    if (rac_model_paths_get_cache_directory(cache_dir, sizeof(cache_dir)) == RAC_SUCCESS) {
        out_info->app_storage.cache_size =
            handle->callbacks.calculate_dir_size(cache_dir, handle->callbacks.user_data);
    }
    char temp_dir[1024];
    if (rac_model_paths_get_temp_directory(temp_dir, sizeof(temp_dir)) == RAC_SUCCESS) {
        out_info->app_storage.app_support_size =
            handle->callbacks.calculate_dir_size(temp_dir, handle->callbacks.user_data);
    }
    out_info->app_storage.total_size = out_info->app_storage.documents_size +
                                       out_info->app_storage.cache_size +
                                       out_info->app_storage.app_support_size;

    // Get downloaded models from registry
    rac_model_info_t** models = nullptr;
    size_t model_count = 0;

    rac_result_t result = rac_model_registry_get_downloaded(registry_handle, &models, &model_count);
    if (result != RAC_SUCCESS) {
        // No models is okay, just return empty
        out_info->models = nullptr;
        out_info->model_count = 0;
        return RAC_SUCCESS;
    }

    // Allocate model metrics array
    if (model_count > 0) {
        out_info->models = static_cast<rac_model_storage_metrics_t*>(
            calloc(model_count, sizeof(rac_model_storage_metrics_t)));
        if (!out_info->models) {
            rac_model_info_array_free(models, model_count);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    out_info->model_count = model_count;
    out_info->total_models_size = 0;

    // Calculate metrics for each model
    for (size_t i = 0; i < model_count; i++) {
        const rac_model_info_t* model = models[i];
        rac_model_storage_metrics_t* metrics = &out_info->models[i];

        // Copy model info
        metrics->model_id = model->id ? strdup(model->id) : nullptr;
        metrics->model_name = model->name ? strdup(model->name) : nullptr;
        if ((model->id && !metrics->model_id) || (model->name && !metrics->model_name)) {
            free(const_cast<char*>(metrics->model_id));
            free(const_cast<char*>(metrics->model_name));
            memset(metrics, 0, sizeof(rac_model_storage_metrics_t));
            continue;
        }
        metrics->framework = model->framework;
        metrics->format = model->format;
        metrics->artifact_info = model->artifact_info;

        // Get path - either from model or calculate from model_paths
        char path_buffer[1024];
        const char* path_to_use = nullptr;

        if (model->local_path && strlen(model->local_path) > 0) {
            path_to_use = model->local_path;
            metrics->local_path = strdup(model->local_path);
        } else if (model->id) {
            // Calculate path using rac_model_paths
            if (rac_model_paths_get_model_folder(model->id, model->framework, path_buffer,
                                                 sizeof(path_buffer)) == RAC_SUCCESS) {
                path_to_use = path_buffer;
                metrics->local_path = strdup(path_buffer);
            }
        }

        // Calculate size via callback
        if (path_to_use) {
            metrics->size_on_disk =
                handle->callbacks.calculate_dir_size(path_to_use, handle->callbacks.user_data);
        } else {
            // Fallback to download size if we can't calculate
            metrics->size_on_disk = model->download_size;
        }

        out_info->total_models_size += metrics->size_on_disk;
    }

    // Free the models array from registry
    rac_model_info_array_free(models, model_count);

    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_get_model_metrics(rac_storage_analyzer_handle_t handle,
                                                    rac_model_registry_handle_t registry_handle,
                                                    const char* model_id,
                                                    rac_inference_framework_t framework,
                                                    rac_model_storage_metrics_t* out_metrics) {
    if (!handle || !registry_handle || !model_id || !out_metrics) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Get model from registry
    rac_model_info_t* model = nullptr;
    rac_result_t result = rac_model_registry_get(registry_handle, model_id, &model);
    if (result != RAC_SUCCESS || !model) {
        return RAC_ERROR_NOT_FOUND;
    }

    // Initialize output
    memset(out_metrics, 0, sizeof(rac_model_storage_metrics_t));

    // Copy model info
    out_metrics->model_id = model->id ? strdup(model->id) : nullptr;
    out_metrics->model_name = model->name ? strdup(model->name) : nullptr;
    if ((model->id && !out_metrics->model_id) || (model->name && !out_metrics->model_name)) {
        free(const_cast<char*>(out_metrics->model_id));
        free(const_cast<char*>(out_metrics->model_name));
        memset(out_metrics, 0, sizeof(rac_model_storage_metrics_t));
        rac_model_info_free(model);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_metrics->framework = model->framework;
    out_metrics->format = model->format;
    out_metrics->artifact_info = model->artifact_info;

    // Get path
    char path_buffer[1024];
    const char* path_to_use = nullptr;

    if (model->local_path && strlen(model->local_path) > 0) {
        path_to_use = model->local_path;
        out_metrics->local_path = strdup(model->local_path);
    } else {
        if (rac_model_paths_get_model_folder(model_id, framework, path_buffer,
                                             sizeof(path_buffer)) == RAC_SUCCESS) {
            path_to_use = path_buffer;
            out_metrics->local_path = strdup(path_buffer);
        }
    }

    // Calculate size
    if (path_to_use) {
        out_metrics->size_on_disk =
            handle->callbacks.calculate_dir_size(path_to_use, handle->callbacks.user_data);
    } else {
        out_metrics->size_on_disk = model->download_size;
    }

    rac_model_info_free(model);
    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_check_available(rac_storage_analyzer_handle_t handle,
                                                  int64_t model_size, double safety_margin,
                                                  rac_storage_availability_t* out_availability) {
    if (!handle || !out_availability) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    memset(out_availability, 0, sizeof(rac_storage_availability_t));

    // Get available space via callback
    int64_t available = handle->callbacks.get_available_space(handle->callbacks.user_data);
    int64_t required =
        static_cast<int64_t>(static_cast<double>(model_size) * (1.0 + safety_margin));

    out_availability->available_space = available;
    out_availability->required_space = required;
    out_availability->is_available = available > required ? RAC_TRUE : RAC_FALSE;
    out_availability->has_warning = available < required * 2 ? RAC_TRUE : RAC_FALSE;

    // Generate recommendation message (NULL recommendation is acceptable on OOM)
    if (out_availability->is_available == RAC_FALSE) {
        int64_t shortfall = required - available;
        // Simple message - platform can format with locale-specific formatter
        char msg[256];
        snprintf(msg, sizeof(msg), "Need %lld more bytes of space.", (long long)shortfall);
        out_availability->recommendation = strdup(msg);
        if (!out_availability->recommendation) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    } else if (out_availability->has_warning == RAC_TRUE) {
        out_availability->recommendation = strdup("Storage space is getting low.");
        if (!out_availability->recommendation) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_storage_analyzer_info_proto(rac_storage_analyzer_handle_t handle,
                                             rac_model_registry_handle_t registry_handle,
                                             const uint8_t* request_proto_bytes,
                                             size_t request_proto_size,
                                             rac_proto_buffer_t* out_buffer) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)registry_handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return storage_proto_unavailable(out_buffer);
#else
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::v1::StorageInfoRequest request;
    runanywhere::v1::StorageInfoResult result_proto;
    if (!parse_request_or_empty(request_proto_bytes, request_proto_size, &request)) {
        result_proto.set_success(false);
        result_proto.set_error_message("Invalid StorageInfoRequest proto bytes.");
        return finish_info_result(result_proto, RAC_ERROR_DECODING_ERROR, out_buffer);
    }

    if (!handle || !registry_handle) {
        result_proto.set_success(false);
        result_proto.set_error_message("Storage analyzer and registry handles are required.");
        return finish_info_result(result_proto, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    bool include_device = request.include_device();
    bool include_app = request.include_app();
    bool include_models = request.include_models();
    bool include_cache = request.include_cache();
    if (request_proto_size == 0) {
        include_device = true;
        include_app = true;
        include_models = true;
        include_cache = true;
    }

    rac_storage_info_t info;
    rac_result_t result = rac_storage_analyzer_analyze(handle, registry_handle, &info);
    if (RAC_FAILED(result)) {
        result_proto.set_success(false);
        result_proto.set_error_message(status_message(result, "Storage analysis failed"));
        return finish_info_result(result_proto, result, out_buffer);
    }

    result_proto.set_success(true);
    runanywhere::v1::StorageInfo* storage = result_proto.mutable_info();

    if (include_device) {
        auto* device = storage->mutable_device();
        device->set_total_bytes(clamp_non_negative(info.device_storage.total_space));
        device->set_free_bytes(clamp_non_negative(info.device_storage.free_space));
        device->set_used_bytes(clamp_non_negative(info.device_storage.used_space));
        device->set_used_percent(
            used_percent(info.device_storage.total_space, info.device_storage.used_space));
    }

    if (include_app) {
        auto* app = storage->mutable_app();
        app->set_documents_bytes(clamp_non_negative(info.app_storage.documents_size));
        app->set_cache_bytes(include_cache ? clamp_non_negative(info.app_storage.cache_size) : 0);
        app->set_app_support_bytes(clamp_non_negative(info.app_storage.app_support_size));
        app->set_total_bytes(clamp_non_negative(info.app_storage.documents_size) +
                             app->cache_bytes() +
                             clamp_non_negative(info.app_storage.app_support_size));
    }

    if (include_models) {
        for (size_t i = 0; i < info.model_count; ++i) {
            const rac_model_storage_metrics_t& model = info.models[i];
            auto* metrics = storage->add_models();
            metrics->set_model_id(model.model_id ? model.model_id : "");
            metrics->set_size_on_disk_bytes(clamp_non_negative(model.size_on_disk));
            if (model.model_id && model.model_id[0] != '\0') {
                rac_model_info_t* registry_model = nullptr;
                if (RAC_SUCCEEDED(
                        rac_model_registry_get(registry_handle, model.model_id, &registry_model)) &&
                    registry_model) {
                    if (registry_model->last_used > 0) {
                        metrics->set_last_used_ms(registry_model->last_used);
                    }
                    rac_model_info_free(registry_model);
                }
            }
        }
        storage->set_total_models(static_cast<int32_t>(info.model_count));
        storage->set_total_models_bytes(clamp_non_negative(info.total_models_size));
    }

    rac_storage_info_free(&info);
    return finish_info_result(result_proto, RAC_SUCCESS, out_buffer);
#endif
}

rac_result_t rac_storage_analyzer_availability_proto(rac_storage_analyzer_handle_t handle,
                                                     rac_model_registry_handle_t registry_handle,
                                                     const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_buffer) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)registry_handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return storage_proto_unavailable(out_buffer);
#else
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::v1::StorageAvailabilityRequest request;
    runanywhere::v1::StorageAvailabilityResult result_proto;
    if (!parse_request_or_empty(request_proto_bytes, request_proto_size, &request)) {
        result_proto.set_success(false);
        result_proto.set_error_message("Invalid StorageAvailabilityRequest proto bytes.");
        return finish_availability_result(result_proto, RAC_ERROR_DECODING_ERROR, out_buffer);
    }

    if (!handle) {
        result_proto.set_success(false);
        result_proto.set_error_message("Storage analyzer handle is required.");
        return finish_availability_result(result_proto, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    int64_t required = clamp_non_negative(request.required_bytes());
    if (request.safety_margin() > 0.0) {
        required =
            static_cast<int64_t>(static_cast<double>(required) * (1.0 + request.safety_margin()));
    }

    if (request.include_existing_model_bytes() && !request.model_id().empty()) {
        if (!registry_handle) {
            result_proto.add_warnings(
                "Existing model bytes requested but registry handle is unavailable.");
        } else {
            rac_model_storage_metrics_t metrics;
            rac_result_t metric_result = rac_storage_analyzer_get_model_metrics(
                handle, registry_handle, request.model_id().c_str(), RAC_FRAMEWORK_UNKNOWN,
                &metrics);
            if (RAC_SUCCEEDED(metric_result)) {
                required -= clamp_non_negative(metrics.size_on_disk);
                if (required < 0) {
                    required = 0;
                }
                free(const_cast<char*>(metrics.model_id));
                free(const_cast<char*>(metrics.model_name));
                free(const_cast<char*>(metrics.local_path));
            } else if (metric_result != RAC_ERROR_NOT_FOUND) {
                result_proto.add_warnings(
                    status_message(metric_result, "Unable to inspect existing model bytes"));
            }
        }
    }

    int64_t available =
        clamp_non_negative(handle->callbacks.get_available_space(handle->callbacks.user_data));
    auto* availability = result_proto.mutable_availability();
    availability->set_required_bytes(required);
    availability->set_available_bytes(available);
    availability->set_is_available(available >= required);
    const int64_t shortfall = required > available ? required - available : 0;
    availability->set_shortfall_bytes(shortfall);
    availability->set_required_to_available_ratio(
        available > 0
            ? static_cast<float>(static_cast<double>(required) / static_cast<double>(available))
            : (required > 0 ? 1.0f : 0.0f));
    result_proto.set_success(true);

    if (available < required) {
        char message[192];
        std::snprintf(message, sizeof(message), "Need %lld more bytes of storage.",
                      static_cast<long long>(shortfall));
        availability->set_warning_message(message);
        availability->set_recommendation("Delete unused local models or clear cache.");
        result_proto.add_warnings(message);
    } else if (available < required * 2) {
        availability->set_warning_message("Storage space is getting low.");
        availability->set_recommendation("Keep extra free space before downloading large models.");
        result_proto.add_warnings("Storage space is getting low.");
    }

    if (request.include_delete_plan()) {
        DeletePlanOptions options;
        options.required_bytes = shortfall;
        options.include_cache = request.allow_cache_reclamation();
        options.include_download_partials = request.allow_cache_reclamation();
        options.allow_loaded_models = false;
        options.oldest_first = true;
        std::unordered_set<std::string> requested_ids;
        runanywhere::v1::StorageDeletePlan plan =
            build_delete_plan(handle, registry_handle, requested_ids, false, options);
        result_proto.mutable_delete_plan()->CopyFrom(plan);
        for (const auto& warning : plan.warnings()) {
            result_proto.add_warnings(warning);
        }
        if (shortfall > 0 && plan.can_reclaim_required_bytes()) {
            availability->set_recommendation(
                "Apply the attached delete plan through the platform adapter before download.");
        }
    }

    return finish_availability_result(result_proto, RAC_SUCCESS, out_buffer);
#endif
}

rac_result_t rac_storage_analyzer_delete_plan_proto(rac_storage_analyzer_handle_t handle,
                                                    rac_model_registry_handle_t registry_handle,
                                                    const uint8_t* request_proto_bytes,
                                                    size_t request_proto_size,
                                                    rac_proto_buffer_t* out_buffer) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)registry_handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return storage_proto_unavailable(out_buffer);
#else
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::v1::StorageDeletePlanRequest request;
    runanywhere::v1::StorageDeletePlan plan;
    if (!parse_request_or_empty(request_proto_bytes, request_proto_size, &request)) {
        plan.set_error_message("Invalid StorageDeletePlanRequest proto bytes.");
        return finish_delete_plan(plan, RAC_ERROR_DECODING_ERROR, out_buffer);
    }

    if (!handle) {
        plan.set_error_message("Storage analyzer handle is required.");
        return finish_delete_plan(plan, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    std::unordered_set<std::string> requested_ids;
    bool has_requested_ids = append_model_ids_from_request(request, &requested_ids);
    DeletePlanOptions options;
    options.required_bytes = request.required_bytes();
    options.include_cache = request.include_cache();
    options.include_download_partials = request.include_download_partials();
    options.allow_loaded_models = request.allow_loaded_models();
    options.oldest_first = request.oldest_first();
    plan = build_delete_plan(handle, registry_handle, requested_ids, has_requested_ids, options);

    rac_result_t error_code = RAC_SUCCESS;
    if (!plan.error_message().empty()) {
        error_code = plan.can_reclaim_required_bytes() ? RAC_ERROR_STORAGE_ERROR
                                                       : RAC_ERROR_INSUFFICIENT_STORAGE;
    }
    return finish_delete_plan(plan, error_code, out_buffer);
#endif
}

rac_result_t rac_storage_analyzer_delete_proto(rac_storage_analyzer_handle_t handle,
                                               rac_model_registry_handle_t registry_handle,
                                               const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_buffer) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)registry_handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return storage_proto_unavailable(out_buffer);
#else
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    runanywhere::v1::StorageDeleteRequest request;
    runanywhere::v1::StorageDeleteResult result_proto;
    if (!parse_request_or_empty(request_proto_bytes, request_proto_size, &request)) {
        result_proto.set_success(false);
        result_proto.set_error_message("Invalid StorageDeleteRequest proto bytes.");
        return finish_delete_result(result_proto, RAC_ERROR_DECODING_ERROR, out_buffer);
    }

    result_proto.set_dry_run(request.dry_run());
    if (!handle || !registry_handle) {
        result_proto.set_success(false);
        result_proto.set_error_message("Storage analyzer and registry handles are required.");
        return finish_delete_result(result_proto, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    std::vector<std::string> requested_ids = ordered_model_ids_from_request(request);
    std::unordered_set<std::string> seen_requested_ids(requested_ids.begin(), requested_ids.end());
    if (requested_ids.empty() && request.has_plan()) {
        for (const auto& candidate : request.plan().candidates()) {
            if (!candidate.model_id().empty() &&
                seen_requested_ids.insert(candidate.model_id()).second) {
                requested_ids.push_back(candidate.model_id());
            }
        }
    }

    std::unordered_set<std::string> warnings;
    if (requested_ids.empty()) {
        result_proto.set_success(false);
        result_proto.set_error_message("StorageDeleteRequest.model_ids is empty.");
        if (request.has_plan() && request.plan().candidates_size() > 0) {
            add_warning_once(&result_proto, &warnings,
                             "Delete plans for cache/temp storage require platform adapter "
                             "execution; StorageDeleteRequest can only apply model ids.");
        }
        return finish_delete_result(result_proto, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    std::unordered_map<std::string, const runanywhere::v1::StorageDeleteCandidate*> plan_candidates;
    if (request.has_plan()) {
        for (const auto& candidate : request.plan().candidates()) {
            if (!candidate.model_id().empty()) {
                plan_candidates[candidate.model_id()] = &candidate;
            }
        }
    }
    if (request.require_plan_match() && !request.has_plan()) {
        result_proto.set_success(false);
        result_proto.set_error_message("StorageDeleteRequest.require_plan_match requires plan.");
        return finish_delete_result(result_proto, RAC_ERROR_INVALID_ARGUMENT, out_buffer);
    }

    int64_t deleted_bytes = 0;
    bool had_failure = false;
    bool had_skipped = false;
    bool files_deleted = false;
    bool registry_updated = false;
    rac_result_t first_error = RAC_SUCCESS;
    auto remember_error = [&first_error](rac_result_t code) {
        if (first_error == RAC_SUCCESS) {
            first_error = code;
        }
    };

    for (const auto& id : requested_ids) {
        const runanywhere::v1::StorageDeleteCandidate* plan_candidate = nullptr;
        auto plan_it = plan_candidates.find(id);
        if (plan_it != plan_candidates.end()) {
            plan_candidate = plan_it->second;
        } else if (request.require_plan_match()) {
            result_proto.add_skipped_model_ids(id);
            add_warning_once(&result_proto, &warnings,
                             "Model is not present in the attached delete plan: " + id);
            had_skipped = true;
            remember_error(RAC_ERROR_STORAGE_ERROR);
            continue;
        }

        rac_model_info_t* model = nullptr;
        rac_result_t get_result = rac_model_registry_get(registry_handle, id.c_str(), &model);
        if (RAC_FAILED(get_result) || !model) {
            result_proto.add_failed_model_ids(id);
            add_warning_once(&result_proto, &warnings, "Model not found: " + id);
            had_failure = true;
            remember_error(RAC_ERROR_MODEL_NOT_FOUND);
            continue;
        }

        const bool has_local_path = model->local_path && std::strlen(model->local_path) > 0;

        // Delete the whole per-model folder (A8): removing only the registry
        // local_path file orphaned the folder and left interrupted-download
        // "<final>.part" partials unreclaimable. The folder also lets an
        // interrupted download (empty local_path) still be cleaned up. Fall back
        // to local_path only when the folder cannot be computed.
        const std::string model_folder = model_folder_path(id, model->framework);
        const std::string delete_target =
            !model_folder.empty() ? model_folder : (has_local_path ? model->local_path : "");
        if (delete_target.empty()) {
            result_proto.add_failed_model_ids(id);
            add_warning_once(&result_proto, &warnings, "Model has no local path: " + id);
            had_failure = true;
            remember_error(RAC_ERROR_INVALID_PATH);
            rac_model_info_free(model);
            continue;
        }

        if (plan_candidate && !plan_candidate->local_path().empty() && has_local_path &&
            plan_candidate->local_path() != model->local_path) {
            result_proto.add_skipped_model_ids(id);
            add_warning_once(&result_proto, &warnings,
                             "Attached delete plan local path is stale for model: " + id);
            had_skipped = true;
            remember_error(RAC_ERROR_STORAGE_ERROR);
            rac_model_info_free(model);
            continue;
        }

        // A missing target is only a hard failure when there is nothing to
        // reclaim. An interrupted download leaves a folder with just a ".part"
        // partial (and an empty local_path), so absence of the exact file is not
        // fatal — the recursive folder delete below removes whatever is present.
        if (request.delete_files() && has_local_path && model_folder.empty() &&
            !path_exists_if_callback_present(handle, delete_target.c_str())) {
            result_proto.add_failed_model_ids(id);
            add_warning_once(&result_proto, &warnings, "Model path is missing: " + id);
            had_failure = true;
            remember_error(RAC_ERROR_FILE_NOT_FOUND);
            rac_model_info_free(model);
            continue;
        }

        int64_t model_size = model_metric_size(handle, model, delete_target.c_str());
        if (request.delete_files() && !request.dry_run() && !request.allow_platform_delete()) {
            result_proto.add_skipped_model_ids(id);
            add_warning_once(&result_proto, &warnings,
                             "Model file deletion requires platform adapter execution: " + id);
            had_skipped = true;
            remember_error(RAC_ERROR_PERMISSION_DENIED);
            rac_model_info_free(model);
            continue;
        }

        bool is_loaded = false;
        bool has_loaded_state = known_loaded_state(handle, model->id, &is_loaded);
        if (!has_loaded_state) {
            add_warning_once(&result_proto, &warnings, kLoadedStateUnavailableWarning);
        }
        if (is_loaded) {
            if (!request.unload_if_loaded()) {
                result_proto.add_failed_model_ids(id);
                add_warning_once(&result_proto, &warnings,
                                 "Model is loaded and unload_if_loaded is false: " + id);
                had_failure = true;
                remember_error(RAC_ERROR_MODEL_NOT_LOADED);
                rac_model_info_free(model);
                continue;
            }
            if (!handle->callbacks.unload_model && !request.dry_run()) {
                result_proto.add_failed_model_ids(id);
                add_warning_once(&result_proto, &warnings,
                                 "Model is loaded but no unload callback is set: " + id);
                had_failure = true;
                remember_error(RAC_ERROR_MODEL_NOT_LOADED);
                rac_model_info_free(model);
                continue;
            }
            if (!handle->callbacks.unload_model && request.dry_run()) {
                add_warning_once(&result_proto, &warnings,
                                 "Dry run would require a platform unload before delete: " + id);
            }
            if (!request.dry_run()) {
                rac_result_t unload_result =
                    handle->callbacks.unload_model(model->id, handle->callbacks.user_data);
                if (RAC_FAILED(unload_result)) {
                    result_proto.add_failed_model_ids(id);
                    add_warning_once(&result_proto, &warnings,
                                     status_message(unload_result, "Failed to unload model"));
                    had_failure = true;
                    remember_error(unload_result);
                    rac_model_info_free(model);
                    continue;
                }
            }
        }

        bool file_delete_succeeded = false;
        if (request.delete_files() && !request.dry_run()) {
            if (!handle->callbacks.delete_path) {
                result_proto.add_failed_model_ids(id);
                add_warning_once(&result_proto, &warnings,
                                 std::string("allow_platform_delete is true but no delete_path "
                                             "callback is set: ") +
                                     id);
                had_failure = true;
                remember_error(RAC_ERROR_DELETE_FAILED);
                rac_model_info_free(model);
                continue;
            }
            // Cancel any in-flight download before deleting so the writer does
            // not race the deleter and re-create the partial we just removed
            // (A18). No-op when nothing is downloading for this id.
            cancel_inflight_download(id);
            // Delete the whole per-model folder recursively (A8): reclaims the
            // model file, any "<final>.part" partial, and the folder itself.
            rac_result_t delete_result =
                handle->callbacks.delete_path(delete_target.c_str(), 1, handle->callbacks.user_data);
            if (RAC_FAILED(delete_result)) {
                result_proto.add_failed_model_ids(id);
                add_warning_once(&result_proto, &warnings,
                                 status_message(delete_result, "Failed to delete model files"));
                had_failure = true;
                remember_error(delete_result);
                rac_model_info_free(model);
                continue;
            }
            file_delete_succeeded = true;
            files_deleted = true;
        }

        bool registry_updated_for_model = false;
        if (request.clear_registry_paths() && !request.dry_run()) {
            rac_result_t clear_result =
                rac_model_registry_update_download_status(registry_handle, id.c_str(), nullptr);
            if (RAC_FAILED(clear_result)) {
                result_proto.add_failed_model_ids(id);
                add_warning_once(&result_proto, &warnings,
                                 status_message(clear_result, "Failed to clear registry path"));
                had_failure = true;
                remember_error(clear_result);
                rac_model_info_free(model);
                continue;
            }
            registry_updated_for_model = true;
            registry_updated = true;
        }

        const bool requested_action = request.delete_files() || request.clear_registry_paths();
        if (request.dry_run() && requested_action) {
            result_proto.add_deleted_model_ids(id);
            if (request.delete_files()) {
                deleted_bytes += model_size;
            }
        } else if (file_delete_succeeded || registry_updated_for_model) {
            result_proto.add_deleted_model_ids(id);
            if (request.delete_files()) {
                deleted_bytes += model_size;
            }
        } else {
            result_proto.add_skipped_model_ids(id);
            add_warning_once(&result_proto, &warnings,
                             "No delete_files or clear_registry_paths action requested: " + id);
            had_skipped = true;
            remember_error(RAC_ERROR_INVALID_ARGUMENT);
        }
        rac_model_info_free(model);
    }

    // Deleting model folders removed their symlinks into the content-addressed blob
    // store; reclaim any shared blob no surviving model still references. Run once
    // after the whole batch (the GC mark-sweeps the model tree). No-op when disabled.
    if (files_deleted && !request.dry_run()) {
        rac::download::blob_store::gc_orphans();
    }

    if (request.dry_run()) {
        add_warning_once(&result_proto, &warnings,
                         "Dry run only; no files or registry paths were changed.");
    }
    result_proto.set_deleted_bytes(deleted_bytes);
    result_proto.set_files_deleted(files_deleted);
    result_proto.set_registry_updated(registry_updated);
    result_proto.set_success(!had_failure && !had_skipped);
    if (had_failure) {
        result_proto.set_error_message("One or more requested models could not be deleted.");
    } else if (had_skipped) {
        result_proto.set_error_message("One or more requested models were skipped.");
    }
    return finish_delete_result(result_proto, first_error, out_buffer);
#endif
}

rac_result_t rac_storage_analyzer_calculate_size(rac_storage_analyzer_handle_t handle,
                                                 const char* path, int64_t* out_size) {
    if (!handle || !path || !out_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if path exists and is directory
    rac_bool_t is_directory = RAC_FALSE;
    if (handle->callbacks.path_exists) {
        rac_bool_t exists =
            handle->callbacks.path_exists(path, &is_directory, handle->callbacks.user_data);
        if (exists == RAC_FALSE) {
            return RAC_ERROR_NOT_FOUND;
        }
    }

    // Calculate size based on type
    if (is_directory == RAC_TRUE) {
        *out_size = handle->callbacks.calculate_dir_size(path, handle->callbacks.user_data);
    } else if (handle->callbacks.get_file_size) {
        *out_size = handle->callbacks.get_file_size(path, handle->callbacks.user_data);
    } else {
        // Fallback to dir size calculator for files too
        *out_size = handle->callbacks.calculate_dir_size(path, handle->callbacks.user_data);
    }

    return RAC_SUCCESS;
}

// =============================================================================
// CLEANUP
// =============================================================================

void rac_storage_info_free(rac_storage_info_t* info) {
    if (!info)
        return;

    if (info->models) {
        for (size_t i = 0; i < info->model_count; i++) {
            free(const_cast<char*>(info->models[i].model_id));
            free(const_cast<char*>(info->models[i].model_name));
            free(const_cast<char*>(info->models[i].local_path));
        }
        free(info->models);
    }

    memset(info, 0, sizeof(rac_storage_info_t));
}

void rac_storage_availability_free(rac_storage_availability_t* availability) {
    if (!availability)
        return;

    free(const_cast<char*>(availability->recommendation));
    memset(availability, 0, sizeof(rac_storage_availability_t));
}
