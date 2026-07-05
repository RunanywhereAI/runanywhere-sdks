/**
 * @file model_registry_refresh.cpp
 * @brief Model registry — refresh proto entry + adapter rescan + fetch + infer.
 *
 * SRP split of model_registry.cpp (pure code-motion). Owns the platform-adapter
 * directory rescan (shared with discovery), the rac_model_registry_refresh_proto
 * entry point, artifact-type inference, and the fetch-assignments entry point
 * (see model_registry_internal.h). No behaviour change.
 */

#include "model_registry_internal.h"

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

using namespace rac::infra::model_registry::detail;  // NOLINT(build/namespaces)

// REFRESH HELPERS — file_list_directory adapter rescan
//
// When the proto refresh request asks for `rescan_local` and no platform
// discovery callback is wired, we fall back to the platform adapter's
// file_list_directory callback. This rescans
// {base_dir}/RunAnywhere/Models/{framework}/{model_id}/ folders and links
// registered models to their on-disk folders via
// rac_model_registry_update_download_status.

namespace {

constexpr size_t kRescanMaxEntryCapacity = 4096;

}  // namespace

namespace rac::infra::model_registry::detail {

// List a directory through the platform adapter using the POSIX two-call
// contract documented on `rac_file_list_directory_fn`: first call with
// out_entries=NULL to learn the required entry count, then allocate and call
// again with a buffer of at least that capacity. Header-compliant adapters
// (e.g. the Web TypeScript implementation) never write more than the capacity
// we pass on the second call, so we cannot rely on a "needed more space"
// signal — we must size up-front.
rac_result_t list_directory_via_adapter(const rac_platform_adapter_t* adapter, const char* dir_path,
                                        std::vector<rac_directory_entry_t>* out_entries) {
    if (!adapter || !adapter->file_list_directory || !dir_path || !out_entries) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_entries->clear();

    // Step 1: capacity probe.
    size_t required = 0;
    rac_result_t probe_rc = adapter->file_list_directory(dir_path, /*out_entries=*/nullptr,
                                                         &required, adapter->user_data);
    if (probe_rc != RAC_SUCCESS) {
        return probe_rc;
    }
    if (required == 0) {
        return RAC_SUCCESS;
    }
    if (required > kRescanMaxEntryCapacity) {
        // Defensive cap to keep refresh sweep bounded even on pathological dirs.
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Step 2: allocate and fetch. Use a small headroom in case the directory
    // gained entries between the probe and the read; entries written beyond
    // the probed count are still safe because we resize to the actual count
    // the adapter reports.
    const size_t capacity = required + 4;
    out_entries->resize(capacity);
    size_t count = capacity;
    rac_result_t fill_rc =
        adapter->file_list_directory(dir_path, out_entries->data(), &count, adapter->user_data);
    if (fill_rc != RAC_SUCCESS) {
        out_entries->clear();
        return fill_rc;
    }
    if (count > capacity) {
        // Header forbids this, but guard against a buggy adapter — never
        // expose entries we did not actually receive.
        count = capacity;
    }
    out_entries->resize(count);
    return RAC_SUCCESS;
}

// Walk {models_dir}/{framework}/{model_id}/ and link any registry entry whose
// on-disk folder contains at least one file. Returns the number of models we
// linked.
int32_t rescan_local_via_platform_adapter(rac_model_registry_handle_t handle) {
    if (!handle) {
        return 0;
    }
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter || !adapter->file_list_directory) {
        return 0;
    }

    char models_dir[1024];
    if (rac_model_paths_get_models_directory(models_dir, sizeof(models_dir)) != RAC_SUCCESS) {
        return 0;
    }

    // Scan the framework set covering every backend an SDK can install so the
    // ABI refresh path links downloads regardless of which backend produced them.
    const rac_inference_framework_t frameworks[] = {
        RAC_FRAMEWORK_LLAMACPP,   RAC_FRAMEWORK_ONNX,        RAC_FRAMEWORK_COREML,
        RAC_FRAMEWORK_MLX,        RAC_FRAMEWORK_FLUID_AUDIO, RAC_FRAMEWORK_FOUNDATION_MODELS,
        RAC_FRAMEWORK_SYSTEM_TTS, RAC_FRAMEWORK_METALRT,     RAC_FRAMEWORK_GENIE,
        RAC_FRAMEWORK_SHERPA,     RAC_FRAMEWORK_UNKNOWN};

    int32_t linked = 0;
    std::vector<rac_directory_entry_t> framework_entries;
    std::vector<rac_directory_entry_t> model_entries;

    for (const rac_inference_framework_t framework : frameworks) {
        char framework_dir[1024];
        if (rac_model_paths_get_framework_directory(framework, framework_dir,
                                                    sizeof(framework_dir)) != RAC_SUCCESS) {
            continue;
        }

        rac_result_t list_rc =
            list_directory_via_adapter(adapter, framework_dir, &framework_entries);
        if (list_rc != RAC_SUCCESS) {
            // Missing framework dirs are normal — only one or two backends may
            // have downloads on this device.
            continue;
        }

        for (const rac_directory_entry_t& entry : framework_entries) {
            if (entry.name[0] == '\0' || entry.name[0] == '.') {
                continue;  // skip hidden / empty
            }
            if (entry.is_dir != RAC_TRUE) {
                continue;  // model_id slots are always directories
            }

            const std::string model_id = entry.name;
            const std::string model_path = std::string(framework_dir) + "/" + model_id;

            // Verify the model folder contains at least one regular file —
            // mirrors the Kotlin self-heal heuristic (file existence is enough;
            // we don't filter by extension because each backend defines its own
            // file shape).
            if (list_directory_via_adapter(adapter, model_path.c_str(), &model_entries) !=
                RAC_SUCCESS) {
                continue;
            }
            bool has_regular_file = false;
            for (const rac_directory_entry_t& child : model_entries) {
                if (child.is_dir != RAC_TRUE && child.name[0] != '\0' && child.name[0] != '.') {
                    has_regular_file = true;
                    break;
                }
            }
            if (!has_regular_file) {
                // Allow one level of nested folder (sherpa-onnx archives ship
                // as <name>/<files>).
                for (const rac_directory_entry_t& child : model_entries) {
                    if (child.is_dir != RAC_TRUE || child.name[0] == '.') {
                        continue;
                    }
                    std::vector<rac_directory_entry_t> nested;
                    std::string nested_path = model_path + "/" + child.name;
                    if (list_directory_via_adapter(adapter, nested_path.c_str(), &nested) ==
                        RAC_SUCCESS) {
                        for (const rac_directory_entry_t& leaf : nested) {
                            if (leaf.is_dir != RAC_TRUE && leaf.name[0] != '\0' &&
                                leaf.name[0] != '.') {
                                has_regular_file = true;
                                break;
                            }
                        }
                    }
                    if (has_regular_file) {
                        break;
                    }
                }
            }
            if (!has_regular_file) {
                continue;
            }

            // Only link models that are actually registered.
            bool registered = false;
            {
                std::lock_guard<std::mutex> lock(handle->mutex);
                registered = handle->models.find(model_id) != handle->models.end();
            }
            if (!registered) {
                continue;
            }

            // Entries with explicit artifact descriptors get the strict
            // per-artifact completeness check instead of the "any regular
            // file" heuristic, so a partial or corrupted folder is left
            // unlinked and a re-download can heal it. The resolver walks
            // std::filesystem, so only apply where the folder is visible to
            // it (native + hydrated MEMFS). The snapshot type is a generated
            // proto, so protobuf-less builds (wasm preset) keep the
            // pre-existing "any regular file" heuristic.
#if defined(RAC_HAVE_PROTOBUF)
            {
                ModelInfo snapshot;
                std::error_code fs_ec;
                if (get_model_snapshot_by_id(handle, model_id, &snapshot) &&
                    (snapshot.has_expected_files() || snapshot.has_multi_file()) &&
                    std::filesystem::exists(model_path, fs_ec)) {
                    if (!model_folder_is_complete(snapshot, model_path)) {
                        RAC_LOG_WARNING(
                            "ModelRegistry",
                            "Refresh rescan: '%s' folder is incomplete — leaving unlinked",
                            model_id.c_str());
                        continue;
                    }
                }
            }
#endif  // RAC_HAVE_PROTOBUF

            rac_result_t update_rc = rac_model_registry_update_download_status(
                handle, model_id.c_str(), model_path.c_str());
            if (update_rc == RAC_SUCCESS) {
                ++linked;
                RAC_LOG_INFO("ModelRegistry", "Refresh rescan: linked '%s' to local_path '%s'",
                             model_id.c_str(), model_path.c_str());
            } else {
                RAC_LOG_WARNING("ModelRegistry", "Refresh rescan: failed to update '%s' (rc=%d)",
                                model_id.c_str(), update_rc);
            }
        }
    }

    return linked;
}

}  // namespace rac::infra::model_registry::detail

rac_result_t rac_model_registry_refresh_proto(rac_model_registry_handle_t handle,
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

    ModelRegistryRefreshRequest request;
    rac_result_t parse_rc =
        parse_proto_message_bytes(request_proto_bytes, request_proto_size, &request,
                                  "ModelRegistryRefreshRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    // Remote catalog fetch (inlined — the former rac_model_registry_refresh
    // struct-opts entry point did only this; rescan_local / prune_orphans were
    // already no-ops there and the actual filesystem rescan runs below via the
    // platform adapter). The assignment manager delegates HTTP to whatever
    // transport the SDK wired up.
    rac_result_t refresh_rc = RAC_SUCCESS;
    if (request.include_remote_catalog()) {
        rac_model_info_t** remote_models = nullptr;
        size_t remote_count = 0;
        rac_result_t remote_rc =
            rac_model_assignment_fetch(RAC_TRUE, &remote_models, &remote_count);
        if (remote_rc == RAC_SUCCESS) {
            RAC_LOG_INFO("ModelRegistry", "Remote catalog refreshed (%zu models)", remote_count);
            if (remote_models) {
                rac_model_info_array_free(remote_models, remote_count);
            }
        } else {
            RAC_LOG_WARNING("ModelRegistry", "Remote catalog refresh failed: %d", remote_rc);
            refresh_rc = remote_rc;
        }
    }

    // Platform-adapter-backed local rescan: when the request asked for
    // rescan_local and the SDK has wired up file_list_directory on the
    // platform adapter, walk the canonical model folders and link registered
    // entries to their downloads. Falls back to the legacy warning when the
    // callback is NULL so older SDK builds keep working without changes.
    int32_t adapter_rescan_linked = 0;
    int32_t manifest_restored = 0;
    bool adapter_rescan_ran = false;
    if (request.rescan_local()) {
        const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
        if (adapter && adapter->file_list_directory) {
            // First restore un-seeded models from durable folder manifests
            // (ad-hoc URL / HF pulls from previous runs), then relink the
            // re-seeded catalog entries.
            manifest_restored = restore_models_from_folder_manifests(handle);
            adapter_rescan_linked = rescan_local_via_platform_adapter(handle);
            adapter_rescan_ran = true;
        }
    }

    std::vector<ModelInfo> models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        models = collect_model_snapshots_locked(handle);
    }
    if (request.has_query()) {
        std::vector<ModelInfo> filtered;
        for (const ModelInfo& model : models) {
            if (model_matches_query(model, request.query())) {
                filtered.push_back(model);
            }
        }
        sort_query_results(request.query(), &filtered);
        models = std::move(filtered);
    }
    const ModelCounts counts = count_models(models);

    ModelRegistryRefreshResult result;
    result.set_success(refresh_rc == RAC_SUCCESS);
    result.set_registered_count(counts.total);
    result.set_updated_count(adapter_rescan_linked);
    result.set_discovered_count(adapter_rescan_linked + manifest_restored);
    result.set_pruned_count(0);
    result.set_refreshed_at_unix_ms(rac_get_current_time_ms());
    result.set_downloaded_count(counts.downloaded);
    result.set_available_count(counts.available);
    result.set_error_count(counts.errors);
    if (refresh_rc != RAC_SUCCESS) {
        result.set_error_message(rac_error_message(refresh_rc));
    }
    if (request.rescan_local() && !adapter_rescan_ran) {
        result.add_warnings(
            "rescan_local requires platform filesystem callbacks in the C ABI refresh path");
    }
    if (request.prune_orphans()) {
        result.add_warnings(
            "prune_orphans requires platform filesystem callbacks in the C ABI refresh path");
    }
    if (!request.catalog_uri().empty()) {
        result.add_warnings(
            "catalog_uri transport is platform-owned and was not executed by commons");
    }
    move_models_to_list(&models, result.mutable_models());
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_artifact_type_kind_t rac_model_infer_artifact_type(const char* url, rac_model_format_t format) {
    // Infer from URL extension
    if (url) {
        size_t len = strlen(url);

        if (len > 4 && strcmp(url + len - 4, ".zip") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tar") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 7 && strcmp(url + len - 7, ".tar.gz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tgz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
    }

    // Default to single file for most formats
    switch (format) {
        case RAC_MODEL_FORMAT_GGUF:
        case RAC_MODEL_FORMAT_ONNX:
        case RAC_MODEL_FORMAT_BIN:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
        default:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
    }
}

// FETCH ASSIGNMENTS — Unified cross-SDK entry point (Web WASM)

rac_result_t rac_model_registry_fetch_assignments(rac_bool_t force_refresh,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    // Initialise caller outputs to safe defaults.
    if (out_models)
        *out_models = nullptr;
    if (out_count)
        *out_count = 0;

    // Delegate to the model assignment layer which handles caching, HTTP, and
    // JSON parsing.  If callbacks have not been set yet (e.g. offline WASM),
    // rac_model_assignment_fetch returns RAC_SUCCESS with zero models — that
    // is the correct behaviour for the Web SDK's offline path.
    rac_model_info_t** models = nullptr;
    size_t count = 0;

    rac_result_t rc = rac_model_assignment_fetch(force_refresh, &models, &count);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_WARNING("ModelRegistry", "rac_model_registry_fetch_assignments: fetch returned %d",
                        rc);
        return rc;
    }

    if (out_models)
        *out_models = models;
    else
        rac_model_info_array_free(models, count);  // caller doesn't want the array

    if (out_count)
        *out_count = count;

    RAC_LOG_INFO("ModelRegistry", "rac_model_registry_fetch_assignments: fetched %zu models",
                 count);
    return RAC_SUCCESS;
}
