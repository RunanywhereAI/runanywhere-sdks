/**
 * @file model_lifecycle_download.cpp
 * @brief Auto-download orchestration helpers for model lifecycle.
 *
 * commons-core-infra-010: extracted from the original `model_lifecycle.cpp`
 * SRP split. Owns the `rac_model_lifecycle_load_proto` opt-in path that
 * drives the canonical download orchestrator and waits for completion
 * before letting the load continue.
 */

#include "model_lifecycle_internal.h"

#include <chrono>
#include <string>
#include <thread>
#include <vector>

#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/http/rac_http_transport.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "download_service.pb.h"
#endif

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

// Detect models whose registry entry has not yet resolved into a local
// artifact. Both classic single-file and multi-file/expected-files entries
// surface "missing" the same way: `is_downloaded` flips to true only after
// the orchestrator landed the bytes, and `local_path` is set to the
// resolved primary artifact at the same time. Built-in models are
// considered always-available.
bool model_artifact_present(const runanywhere::v1::ModelInfo& model) {
    if (model.has_built_in() && model.built_in()) {
        return true;
    }
    if (model.is_downloaded()) {
        return true;
    }
    if (!model.local_path().empty()) {
        return true;
    }
    return false;
}

bool model_has_download_source(const runanywhere::v1::ModelInfo& model) {
    if (!model.download_url().empty()) {
        return true;
    }
    if (model.has_multi_file()) {
        for (const runanywhere::v1::ModelFileDescriptor& file : model.multi_file().files()) {
            if (!file.url().empty()) {
                return true;
            }
        }
    }
    if (model.has_expected_files()) {
        for (const runanywhere::v1::ModelFileDescriptor& file : model.expected_files().files()) {
            if (!file.url().empty()) {
                return true;
            }
        }
    }
    // ArchiveArtifact carries extraction metadata; the canonical download
    // URL still lives on ModelInfo.download_url. has_archive() alone is
    // not a download signal — only the top-level download_url field plus
    // the per-file URLs in multi_file/expected_files indicate a fetchable
    // source.
    return false;
}

// pass3-syn-cluster19: orchestrate plan→start→poll for a single model. Used
// by `rac_model_lifecycle_load_proto` when the caller opts into
// `validate_availability=true` and the registry entry has no resolved
// artifact yet, so SDK callers can collapse the legacy
// `getModel → downloadModel(asyncIterator) → loadModel` chain into a
// single `loadModel(id)` round-trip.
//
// Returns RAC_SUCCESS only after the download manager reports
// DOWNLOAD_STATE_COMPLETED for the spawned task; any FAILED / CANCELLED
// terminal state surfaces a structured error message in @p out_error.
// A `timeout_seconds` ceiling guards against indefinite hang when an HTTP
// transport stalls — five minutes mirrors the default per-file budget the
// orchestrator already enforces internally.
rac_result_t download_and_wait_for_model(const std::string& model_id,
                                         const runanywhere::v1::ModelInfo& registered_model,
                                         std::string* out_error, int timeout_seconds) {
    if (out_error) {
        out_error->clear();
    }
    if (rac_http_transport_is_registered() == RAC_FALSE) {
        if (out_error) {
            *out_error =
                "model is not downloaded and no HTTP transport is registered for auto-download";
        }
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Step 1 — produce a download plan from the registered ModelInfo. The
    // plan service handles per-platform path resolution and capability
    // checks; we forward the registry's view of the model so the planner
    // sees the same artifact descriptors the lifecycle path will use.
    runanywhere::v1::DownloadPlanRequest plan_request;
    plan_request.set_model_id(model_id);
    plan_request.mutable_model()->CopyFrom(registered_model);
    plan_request.set_validate_existing_bytes(true);
    std::vector<uint8_t> plan_bytes(plan_request.ByteSizeLong());
    if (!plan_bytes.empty() &&
        !plan_request.SerializeToArray(plan_bytes.data(), static_cast<int>(plan_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadPlanRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }
    rac_proto_buffer_t plan_out = {};
    rac_proto_buffer_init(&plan_out);
    rac_result_t rc = rac_download_plan_proto(plan_bytes.empty() ? nullptr : plan_bytes.data(),
                                              plan_bytes.size(), &plan_out);
    if (rc != RAC_SUCCESS) {
        if (out_error) {
            *out_error =
                plan_out.error_message ? plan_out.error_message : "rac_download_plan_proto failed";
        }
        rac_proto_buffer_free(&plan_out);
        return rc;
    }
    runanywhere::v1::DownloadPlanResult plan_result;
    const bool plan_parsed =
        plan_result.ParseFromArray(plan_out.data, static_cast<int>(plan_out.size));
    rac_proto_buffer_free(&plan_out);
    if (!plan_parsed) {
        if (out_error) {
            *out_error = "failed to parse DownloadPlanResult";
        }
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!plan_result.can_start()) {
        if (out_error) {
            *out_error = plan_result.error_message().empty()
                             ? "download plan reports can_start=false"
                             : plan_result.error_message();
        }
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }

    // Step 2 — start the download. update_registry_on_completion=true so the
    // worker updates the registry entry with the resolved local_path; the
    // subsequent get_proto reread (in the outer load path) will then see
    // the populated artifact.
    runanywhere::v1::DownloadStartRequest start_request;
    start_request.set_model_id(model_id);
    start_request.mutable_plan()->CopyFrom(plan_result);
    start_request.set_update_registry_on_completion(true);
    std::vector<uint8_t> start_bytes(start_request.ByteSizeLong());
    if (!start_bytes.empty() &&
        !start_request.SerializeToArray(start_bytes.data(), static_cast<int>(start_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadStartRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }
    rac_proto_buffer_t start_out = {};
    rac_proto_buffer_init(&start_out);
    rc = rac_download_start_proto(start_bytes.empty() ? nullptr : start_bytes.data(),
                                  start_bytes.size(), &start_out);
    if (rc != RAC_SUCCESS) {
        if (out_error) {
            *out_error = start_out.error_message ? start_out.error_message
                                                 : "rac_download_start_proto failed";
        }
        rac_proto_buffer_free(&start_out);
        return rc;
    }
    runanywhere::v1::DownloadStartResult start_result;
    const bool start_parsed =
        start_result.ParseFromArray(start_out.data, static_cast<int>(start_out.size));
    rac_proto_buffer_free(&start_out);
    if (!start_parsed) {
        if (out_error) {
            *out_error = "failed to parse DownloadStartResult";
        }
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!start_result.accepted() || start_result.task_id().empty()) {
        if (out_error) {
            *out_error = start_result.error_message().empty()
                             ? "download orchestrator rejected start request"
                             : start_result.error_message();
        }
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }

    const std::string task_id = start_result.task_id();
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(timeout_seconds);

    // Step 3 — poll DownloadSubscribeRequest until the task reaches a
    // terminal state. The orchestrator's progress poll is a cheap read of
    // the latest snapshot, so a 100 ms cadence keeps the wait responsive
    // without burning CPU; HTTP completion is already async inside the
    // orchestrator worker.
    runanywhere::v1::DownloadSubscribeRequest subscribe_request;
    subscribe_request.set_model_id(model_id);
    subscribe_request.set_task_id(task_id);
    std::vector<uint8_t> subscribe_bytes(subscribe_request.ByteSizeLong());
    if (!subscribe_bytes.empty() &&
        !subscribe_request.SerializeToArray(subscribe_bytes.data(),
                                            static_cast<int>(subscribe_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadSubscribeRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }

    while (true) {
        if (std::chrono::steady_clock::now() >= deadline) {
            if (out_error) {
                *out_error = "auto-download timeout while loading model";
            }
            return RAC_ERROR_TIMEOUT;
        }

        rac_proto_buffer_t progress_out = {};
        rac_proto_buffer_init(&progress_out);
        rc = rac_download_progress_poll_proto(subscribe_bytes.empty() ? nullptr
                                                                      : subscribe_bytes.data(),
                                              subscribe_bytes.size(), &progress_out);
        if (rc != RAC_SUCCESS) {
            if (out_error) {
                *out_error = progress_out.error_message ? progress_out.error_message
                                                        : "rac_download_progress_poll_proto failed";
            }
            rac_proto_buffer_free(&progress_out);
            return rc;
        }
        runanywhere::v1::DownloadProgress progress;
        const bool progress_parsed =
            progress.ParseFromArray(progress_out.data, static_cast<int>(progress_out.size));
        rac_proto_buffer_free(&progress_out);
        if (!progress_parsed) {
            if (out_error) {
                *out_error = "failed to parse DownloadProgress";
            }
            return RAC_ERROR_DECODING_ERROR;
        }

        const auto state = progress.state();
        if (state == runanywhere::v1::DOWNLOAD_STATE_COMPLETED) {
            return RAC_SUCCESS;
        }
        if (state == runanywhere::v1::DOWNLOAD_STATE_FAILED) {
            if (out_error) {
                *out_error = progress.error_message().empty() ? "auto-download failed"
                                                              : progress.error_message();
            }
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        if (state == runanywhere::v1::DOWNLOAD_STATE_CANCELLED) {
            if (out_error) {
                *out_error = "auto-download cancelled";
            }
            return RAC_ERROR_CANCELLED;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::core::model_lifecycle::detail
