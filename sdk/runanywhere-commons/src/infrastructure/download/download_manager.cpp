/**
 * @file download_manager.cpp
 * @brief RunAnywhere Commons - Download Manager Implementation
 *
 * C++ port of Swift's DownloadService orchestration logic.
 * Swift Source: Sources/RunAnywhere/Infrastructure/Download/
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 *
 * NOTE: The actual HTTP download is delegated to the platform adapter (Swift/Kotlin).
 * This C layer handles orchestration: progress tracking, state management, retry logic.
 */

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/infrastructure/download/rac_download.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct download_task_internal {
    std::string task_id;
    std::string model_id;
    std::string url;
    std::string destination_path;
    bool requires_extraction;
    rac_download_progress_t progress;

    // Callbacks
    rac_download_progress_callback_fn progress_callback;
    rac_download_complete_callback_fn complete_callback;
    void* user_data;

    // Internal state
    std::string downloaded_file_path;
    std::string error_message;
    int64_t start_time_ms;
};

struct rac_download_manager {
    // Configuration
    rac_download_config_t config;

    // Task storage
    std::map<std::string, download_task_internal> tasks;

    // Task ID counter
    std::atomic<uint64_t> task_counter;

    // Thread safety
    std::mutex mutex;

    // Health state
    bool is_healthy;
    bool is_paused;
};

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

static std::string generate_task_id(rac_download_manager* mgr) {
    uint64_t id = mgr->task_counter.fetch_add(1);
    return "download-task-" + std::to_string(id);
}

static double calculate_overall_progress(rac_download_stage_t stage, double stage_progress) {
    // Progress ranges: Download: 0-80%, Extraction: 80-95%, Validation: 95-99%, Complete: 100%
    double start = 0.0;
    double end = 0.0;

    switch (stage) {
        case RAC_DOWNLOAD_STAGE_DOWNLOADING:
            start = 0.0;
            end = 0.80;
            break;
        case RAC_DOWNLOAD_STAGE_EXTRACTING:
            start = 0.80;
            end = 0.95;
            break;
        case RAC_DOWNLOAD_STAGE_VALIDATING:
            start = 0.95;
            end = 0.99;
            break;
        case RAC_DOWNLOAD_STAGE_COMPLETED:
            return 1.0;
    }

    return start + (stage_progress * (end - start));
}

static void notify_progress(download_task_internal& task) {
    if (task.progress_callback) {
        task.progress_callback(&task.progress, task.user_data);
    }
}

static void notify_complete(download_task_internal& task, rac_result_t result,
                            const char* final_path) {
    if (task.complete_callback) {
        task.complete_callback(task.task_id.c_str(), result, final_path, task.user_data);
    }
}

// =============================================================================
// PUBLIC API - LIFECYCLE
// =============================================================================

rac_result_t rac_download_manager_create(const rac_download_config_t* config,
                                         rac_download_manager_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_download_manager* mgr = new (std::nothrow) rac_download_manager();
    if (!mgr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Initialize config
    if (config) {
        mgr->config = *config;
    } else {
        mgr->config = RAC_DOWNLOAD_CONFIG_DEFAULT;
    }

    mgr->task_counter = 1;
    mgr->is_healthy = true;
    mgr->is_paused = false;

    RAC_LOG_INFO("DownloadManager", "Download manager created");

    *out_handle = mgr;
    return RAC_SUCCESS;
}

void rac_download_manager_destroy(rac_download_manager_handle_t handle) {
    if (!handle) {
        return;
    }

    // Cancel any active downloads
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        for (auto& pair : handle->tasks) {
            download_task_internal& task = pair.second;
            if (task.progress.state == RAC_DOWNLOAD_STATE_DOWNLOADING ||
                task.progress.state == RAC_DOWNLOAD_STATE_EXTRACTING) {
                task.progress.state = RAC_DOWNLOAD_STATE_CANCELLED;
                notify_complete(task, RAC_ERROR_CANCELLED, nullptr);
            }
        }
    }

    delete handle;
    RAC_LOG_DEBUG("DownloadManager", "Download manager destroyed");
}

// =============================================================================
// PUBLIC API - DOWNLOAD OPERATIONS
// =============================================================================

rac_result_t rac_download_manager_start(rac_download_manager_handle_t handle, const char* model_id,
                                        const char* url, const char* destination_path,
                                        rac_bool_t requires_extraction,
                                        rac_download_progress_callback_fn progress_callback,
                                        rac_download_complete_callback_fn complete_callback,
                                        void* user_data, char** out_task_id) {
    if (!handle || !model_id || !url || !destination_path || !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (handle->is_paused) {
        RAC_LOG_WARNING("DownloadManager", "Download manager is paused");
        return RAC_ERROR_INVALID_STATE;
    }

    // Create task
    std::string task_id = generate_task_id(handle);

    download_task_internal task;
    task.task_id = task_id;
    task.model_id = model_id;
    task.url = url;
    task.destination_path = destination_path;
    task.requires_extraction = requires_extraction == RAC_TRUE;
    task.progress = RAC_DOWNLOAD_PROGRESS_DEFAULT;
    task.progress.state = RAC_DOWNLOAD_STATE_PENDING;
    task.progress_callback = progress_callback;
    task.complete_callback = complete_callback;
    task.user_data = user_data;
    task.start_time_ms = rac_get_current_time_ms();

    handle->tasks[task_id] = std::move(task);

    *out_task_id = rac_strdup(task_id.c_str());

    RAC_LOG_INFO("DownloadManager", "Started download task");

    // Notify initial progress
    download_task_internal& stored_task = handle->tasks[task_id];
    notify_progress(stored_task);

    // Note: Actual HTTP download is triggered by platform adapter
    // This function just creates the tracking state

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_cancel(rac_download_manager_handle_t handle,
                                         const char* task_id) {
    if (!handle || !task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->tasks.find(task_id);
    if (it == handle->tasks.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    download_task_internal& task = it->second;

    if (task.progress.state == RAC_DOWNLOAD_STATE_COMPLETED ||
        task.progress.state == RAC_DOWNLOAD_STATE_FAILED ||
        task.progress.state == RAC_DOWNLOAD_STATE_CANCELLED) {
        // Already in terminal state
        return RAC_SUCCESS;
    }

    task.progress.state = RAC_DOWNLOAD_STATE_CANCELLED;
    notify_progress(task);
    notify_complete(task, RAC_ERROR_CANCELLED, nullptr);

    RAC_LOG_INFO("DownloadManager", "Cancelled download task");

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_pause_all(rac_download_manager_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->is_paused = true;

    RAC_LOG_INFO("DownloadManager", "Paused all downloads");

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_resume_all(rac_download_manager_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->is_paused = false;

    RAC_LOG_INFO("DownloadManager", "Resumed all downloads");

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API - STATUS
// =============================================================================

rac_result_t rac_download_manager_get_progress(rac_download_manager_handle_t handle,
                                               const char* task_id,
                                               rac_download_progress_t* out_progress) {
    if (!handle || !task_id || !out_progress) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->tasks.find(task_id);
    if (it == handle->tasks.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    *out_progress = it->second.progress;
    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_get_active_tasks(rac_download_manager_handle_t handle,
                                                   char*** out_task_ids, size_t* out_count) {
    if (!handle || !out_task_ids || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::vector<std::string> active_ids;
    for (const auto& pair : handle->tasks) {
        const download_task_internal& task = pair.second;
        if (task.progress.state == RAC_DOWNLOAD_STATE_PENDING ||
            task.progress.state == RAC_DOWNLOAD_STATE_DOWNLOADING ||
            task.progress.state == RAC_DOWNLOAD_STATE_EXTRACTING ||
            task.progress.state == RAC_DOWNLOAD_STATE_RETRYING) {
            active_ids.push_back(task.task_id);
        }
    }

    *out_count = active_ids.size();
    if (active_ids.empty()) {
        *out_task_ids = nullptr;
        return RAC_SUCCESS;
    }

    *out_task_ids = static_cast<char**>(malloc(sizeof(char*) * active_ids.size()));
    for (size_t i = 0; i < active_ids.size(); ++i) {
        (*out_task_ids)[i] = rac_strdup(active_ids[i].c_str());
    }

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_is_healthy(rac_download_manager_handle_t handle,
                                             rac_bool_t* out_is_healthy) {
    if (!handle || !out_is_healthy) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_is_healthy = handle->is_healthy ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API - PROGRESS HELPERS (called by platform adapter)
// =============================================================================

rac_result_t rac_download_manager_update_progress(rac_download_manager_handle_t handle,
                                                  const char* task_id, int64_t bytes_downloaded,
                                                  int64_t total_bytes) {
    if (!handle || !task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->tasks.find(task_id);
    if (it == handle->tasks.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    download_task_internal& task = it->second;

    // Update progress
    task.progress.state = RAC_DOWNLOAD_STATE_DOWNLOADING;
    task.progress.stage = RAC_DOWNLOAD_STAGE_DOWNLOADING;
    task.progress.bytes_downloaded = bytes_downloaded;
    task.progress.total_bytes = total_bytes;

    if (total_bytes > 0) {
        task.progress.stage_progress =
            static_cast<double>(bytes_downloaded) / static_cast<double>(total_bytes);
    } else {
        task.progress.stage_progress = 0.0;
    }

    task.progress.overall_progress =
        calculate_overall_progress(task.progress.stage, task.progress.stage_progress);

    // Calculate speed
    int64_t elapsed_ms = rac_get_current_time_ms() - task.start_time_ms;
    if (elapsed_ms > 0) {
        task.progress.speed =
            static_cast<double>(bytes_downloaded) / (static_cast<double>(elapsed_ms) / 1000.0);

        // Calculate ETA
        if (task.progress.speed > 0 && total_bytes > bytes_downloaded) {
            int64_t remaining_bytes = total_bytes - bytes_downloaded;
            task.progress.estimated_time_remaining =
                static_cast<double>(remaining_bytes) / task.progress.speed;
        }
    }

    notify_progress(task);

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_mark_complete(rac_download_manager_handle_t handle,
                                                const char* task_id, const char* downloaded_path) {
    if (!handle || !task_id || !downloaded_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->tasks.find(task_id);
    if (it == handle->tasks.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    download_task_internal& task = it->second;
    task.downloaded_file_path = downloaded_path;

    if (task.requires_extraction) {
        // Move to extraction stage
        task.progress.state = RAC_DOWNLOAD_STATE_EXTRACTING;
        task.progress.stage = RAC_DOWNLOAD_STAGE_EXTRACTING;
        task.progress.stage_progress = 0.0;
        task.progress.overall_progress =
            calculate_overall_progress(RAC_DOWNLOAD_STAGE_EXTRACTING, 0.0);
        notify_progress(task);

        // Note: Platform adapter should call extract_archive and then call
        // rac_download_manager_mark_extraction_complete
    } else {
        // No extraction needed, mark as complete
        task.progress.state = RAC_DOWNLOAD_STATE_COMPLETED;
        task.progress.stage = RAC_DOWNLOAD_STAGE_COMPLETED;
        task.progress.stage_progress = 1.0;
        task.progress.overall_progress = 1.0;
        notify_progress(task);
        notify_complete(task, RAC_SUCCESS, downloaded_path);
    }

    RAC_LOG_INFO("DownloadManager", "Download completed");

    return RAC_SUCCESS;
}

rac_result_t rac_download_manager_mark_failed(rac_download_manager_handle_t handle,
                                              const char* task_id, rac_result_t error_code,
                                              const char* error_message) {
    if (!handle || !task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->tasks.find(task_id);
    if (it == handle->tasks.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    download_task_internal& task = it->second;

    // Check if we should retry
    if (task.progress.retry_attempt < handle->config.max_retry_attempts) {
        task.progress.retry_attempt++;
        task.progress.state = RAC_DOWNLOAD_STATE_RETRYING;
        task.progress.error_code = error_code;
        if (error_message) {
            task.error_message = error_message;
            task.progress.error_message = task.error_message.c_str();
        }
        notify_progress(task);

        RAC_LOG_WARNING("DownloadManager", "Download failed, will retry");

        // Note: Platform adapter should retry after delay
    } else {
        // Max retries reached, mark as failed
        task.progress.state = RAC_DOWNLOAD_STATE_FAILED;
        task.progress.error_code = error_code;
        if (error_message) {
            task.error_message = error_message;
            task.progress.error_message = task.error_message.c_str();
        }
        notify_progress(task);
        notify_complete(task, error_code, nullptr);

        RAC_LOG_ERROR("DownloadManager", "Download failed after all retries");
    }

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API - STAGE INFO
// =============================================================================

const char* rac_download_stage_display_name(rac_download_stage_t stage) {
    switch (stage) {
        case RAC_DOWNLOAD_STAGE_DOWNLOADING:
            return "Downloading";
        case RAC_DOWNLOAD_STAGE_EXTRACTING:
            return "Extracting";
        case RAC_DOWNLOAD_STAGE_VALIDATING:
            return "Validating";
        case RAC_DOWNLOAD_STAGE_COMPLETED:
            return "Completed";
        default:
            return "Unknown";
    }
}

void rac_download_stage_progress_range(rac_download_stage_t stage, double* out_start,
                                       double* out_end) {
    if (!out_start || !out_end) {
        return;
    }

    switch (stage) {
        case RAC_DOWNLOAD_STAGE_DOWNLOADING:
            *out_start = 0.0;
            *out_end = 0.80;
            break;
        case RAC_DOWNLOAD_STAGE_EXTRACTING:
            *out_start = 0.80;
            *out_end = 0.95;
            break;
        case RAC_DOWNLOAD_STAGE_VALIDATING:
            *out_start = 0.95;
            *out_end = 0.99;
            break;
        case RAC_DOWNLOAD_STAGE_COMPLETED:
            *out_start = 1.0;
            *out_end = 1.0;
            break;
        default:
            *out_start = 0.0;
            *out_end = 0.0;
            break;
    }
}

// =============================================================================
// PUBLIC API - MEMORY MANAGEMENT
// =============================================================================

void rac_download_task_free(rac_download_task_t* task) {
    if (!task) {
        return;
    }

    if (task->task_id) {
        free(task->task_id);
        task->task_id = nullptr;
    }
    if (task->model_id) {
        free(task->model_id);
        task->model_id = nullptr;
    }
    if (task->url) {
        free(task->url);
        task->url = nullptr;
    }
    if (task->destination_path) {
        free(task->destination_path);
        task->destination_path = nullptr;
    }
}

void rac_download_task_ids_free(char** task_ids, size_t count) {
    if (!task_ids) {
        return;
    }

    for (size_t i = 0; i < count; ++i) {
        if (task_ids[i]) {
            free(task_ids[i]);
        }
    }
    free(task_ids);
}
