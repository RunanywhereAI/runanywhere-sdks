/**
 * @file download_orchestrator.cpp
 * @brief Download Orchestrator - High-Level Model Download Lifecycle Management
 *
 * Consolidates download business logic from Swift/Kotlin/RN/Flutter SDKs into C++.
 * Each SDK now only provides the HTTP transport callback and calls rac_download_orchestrate().
 *
 * Full lifecycle:
 *   1. Compute destination path (temp if extraction needed, final if not)
 *   2. Start HTTP download via platform adapter (rac_http_download)
 *   3. On HTTP completion:
 *      a. If extraction needed → rac_extract_archive_native → find model path → cleanup archive
 *      b. Update download manager state
 *   4. Invoke user's complete_callback with final model path
 */

#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include "internal/rac_platform_compat.h"

#ifdef _WIN32
#include <direct.h>  // for _mkdir
#endif

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/download/rac_download.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/extraction/rac_extraction.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

static const char* LOG_TAG = "DownloadOrchestrator";

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

/**
 * Get file extension from a URL/path string (without dot).
 * Handles compound extensions like .tar.gz, .tar.bz2, .tar.xz.
 */
static std::string get_file_extension(const char* url) {
    if (!url) return "";

    std::string path(url);

    // Strip query string and fragment
    auto query_pos = path.find('?');
    if (query_pos != std::string::npos) path = path.substr(0, query_pos);
    auto frag_pos = path.find('#');
    if (frag_pos != std::string::npos) path = path.substr(0, frag_pos);

    // Find the last path component
    auto slash_pos = path.rfind('/');
    std::string filename = (slash_pos != std::string::npos) ? path.substr(slash_pos + 1) : path;

    // Check for compound extensions first
    if (filename.length() > 7) {
        std::string lower = filename;
        for (auto& c : lower) c = static_cast<char>(tolower(c));

        if (lower.rfind(".tar.gz") == lower.length() - 7) return "tar.gz";
        if (lower.rfind(".tar.bz2") == lower.length() - 8) return "tar.bz2";
        if (lower.rfind(".tar.xz") == lower.length() - 7) return "tar.xz";
        if (lower.rfind(".tgz") == lower.length() - 4) return "tar.gz";
        if (lower.rfind(".tbz2") == lower.length() - 5) return "tar.bz2";
        if (lower.rfind(".txz") == lower.length() - 4) return "tar.xz";
    }

    // Simple extension
    auto dot_pos = filename.rfind('.');
    if (dot_pos != std::string::npos && dot_pos < filename.length() - 1) {
        return filename.substr(dot_pos + 1);
    }

    return "";
}

/**
 * Get the filename (without extension) from a URL.
 */
static std::string get_filename_stem(const char* url) {
    if (!url) return "";

    std::string path(url);
    auto query_pos = path.find('?');
    if (query_pos != std::string::npos) path = path.substr(0, query_pos);

    auto slash_pos = path.rfind('/');
    std::string filename = (slash_pos != std::string::npos) ? path.substr(slash_pos + 1) : path;

    // Strip compound extensions
    std::string lower = filename;
    for (auto& c : lower) c = static_cast<char>(tolower(c));

    const char* compound_exts[] = {".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".txz"};
    for (const auto& ext : compound_exts) {
        size_t ext_len = strlen(ext);
        if (lower.length() > ext_len && lower.rfind(ext) == lower.length() - ext_len) {
            return filename.substr(0, filename.length() - ext_len);
        }
    }

    // Strip simple extension
    auto dot_pos = filename.rfind('.');
    if (dot_pos != std::string::npos) {
        return filename.substr(0, dot_pos);
    }

    return filename;
}

/**
 * Check if a file extension is a known model extension.
 */
static bool is_model_extension(const char* ext) {
    if (!ext) return false;
    // Compare case-insensitively
    std::string lower(ext);
    for (auto& c : lower) c = static_cast<char>(tolower(c));

    return lower == "gguf" || lower == "onnx" || lower == "ort" || lower == "bin" ||
           lower == "mlmodelc" || lower == "mlpackage";
}

/**
 * Check if a directory exists.
 */
static bool dir_exists(const char* path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

/**
 * Create directories recursively (like mkdir -p).
 */
static bool mkdir_p(const char* path) {
    if (dir_exists(path)) return true;

    std::string s(path);
    std::string::size_type pos = 0;

    // Accept both '/' and '\\' as separators on Windows so paths like
    // "C:\foo\bar\baz" get their intermediate dirs created correctly.
#ifdef _WIN32
    const char* kSeparators = "/\\";
#else
    const char* kSeparators = "/";
#endif

    while ((pos = s.find_first_of(kSeparators, pos + 1)) != std::string::npos) {
        std::string sub = s.substr(0, pos);
        if (!sub.empty()) {
#ifdef _WIN32
            _mkdir(sub.c_str());
#else
            mkdir(sub.c_str(), 0755);
#endif
        }
    }
#ifdef _WIN32
    return _mkdir(s.c_str()) == 0 || dir_exists(path);
#else
    return mkdir(s.c_str(), 0755) == 0 || dir_exists(path);
#endif
}

/**
 * Delete a file.
 */
static void delete_file(const char* path) {
    if (path) {
        remove(path);
    }
}

// =============================================================================
// POST-EXTRACTION MODEL PATH FINDING (ported from Swift ExtractionService)
// =============================================================================

/**
 * Find a single model file in a directory, searching recursively up to max_depth levels.
 * Ported from Swift's ExtractionService.findSingleModelFile().
 */
static bool find_single_model_file(const char* directory, int depth, int max_depth, char* out_path,
                                   size_t path_size) {
    if (depth >= max_depth) return false;

    DIR* dir = opendir(directory);
    if (!dir) return false;

    struct dirent* entry;
    std::string found_model;
    std::vector<std::string> subdirs;

    while ((entry = readdir(dir)) != nullptr) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        // Skip hidden files and macOS resource forks
        if (entry->d_name[0] == '.') continue;

        std::string full_path = std::string(directory) + "/" + entry->d_name;

        struct stat st;
        if (stat(full_path.c_str(), &st) != 0) continue;

        if (S_ISREG(st.st_mode)) {
            // Check if this is a model file
            const char* dot = strrchr(entry->d_name, '.');
            if (dot && is_model_extension(dot + 1)) {
                found_model = full_path;
                break;  // Found it
            }
        } else if (S_ISDIR(st.st_mode)) {
            subdirs.push_back(full_path);
        }
    }
    closedir(dir);

    if (!found_model.empty()) {
        snprintf(out_path, path_size, "%s", found_model.c_str());
        return true;
    }

    // Recursively check subdirectories
    for (const auto& subdir : subdirs) {
        if (find_single_model_file(subdir.c_str(), depth + 1, max_depth, out_path, path_size)) {
            return true;
        }
    }

    return false;
}

/**
 * Find the nested directory (single visible subdirectory) in an extracted archive.
 * Ported from Swift's ExtractionService.findNestedDirectory().
 *
 * Common pattern: archive contains one subdirectory with all the files.
 * e.g., sherpa-onnx archives extract to: extractedDir/vits-xxx/
 */
static std::string find_nested_directory(const char* extracted_dir) {
    DIR* dir = opendir(extracted_dir);
    if (!dir) return extracted_dir;

    struct dirent* entry;
    std::vector<std::string> visible_dirs;

    while ((entry = readdir(dir)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        // Skip hidden files and macOS resource forks
        if (entry->d_name[0] == '.') continue;
        if (strncmp(entry->d_name, "._", 2) == 0) continue;

        std::string full_path = std::string(extracted_dir) + "/" + entry->d_name;

        struct stat st;
        if (stat(full_path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
            visible_dirs.push_back(full_path);
        }
    }
    closedir(dir);

    // If there's exactly one visible subdirectory, return it
    if (visible_dirs.size() == 1) {
        return visible_dirs[0];
    }

    if (visible_dirs.size() > 1) {
        RAC_LOG_WARNING(LOG_TAG,
                        "find_nested_directory: found %zu subdirectories in '%s', "
                        "falling back to root (expected exactly 1)",
                        visible_dirs.size(), extracted_dir);
    }

    return extracted_dir;
}

// =============================================================================
// ORCHESTRATION CONTEXT (passed through HTTP callbacks)
// =============================================================================

struct orchestrate_context {
    // Download manager handle
    rac_download_manager_handle_t dm_handle;

    // Model info
    std::string model_id;
    std::string download_url;
    rac_inference_framework_t framework;
    rac_model_format_t format;
    rac_archive_structure_t archive_structure;

    // Paths
    std::string download_dest_path;    // Where HTTP downloads to
    std::string model_folder_path;     // Final model folder
    bool needs_extraction;

    // Task tracking
    std::string task_id;

    // User callbacks
    rac_download_progress_callback_fn user_progress_callback;
    rac_download_complete_callback_fn user_complete_callback;
    void* user_data;
};

/**
 * Prevent double-free of orchestrate_context when async callbacks race with error paths.
 *
 * The context is wrapped in a shared_ptr stored in a shared_ctx_holder.
 * The holder is passed as raw void* to C callbacks.
 * Both the caller and the callback own a reference via the shared_ptr,
 * ensuring the context outlives all users.
 */
struct shared_ctx_holder {
    std::shared_ptr<orchestrate_context> ctx;
};

/**
 * HTTP progress callback — forwards to download manager which recalculates overall progress.
 */
static void orchestrate_http_progress(int64_t bytes_downloaded, int64_t total_bytes,
                                      void* callback_user_data) {
    auto* holder = static_cast<shared_ctx_holder*>(callback_user_data);
    if (!holder || !holder->ctx || !holder->ctx->dm_handle) return;

    auto& ctx = holder->ctx;
    rac_download_manager_update_progress(ctx->dm_handle, ctx->task_id.c_str(), bytes_downloaded,
                                         total_bytes);
}

/**
 * HTTP completion callback — handles post-download extraction and cleanup.
 * Deletes the holder (releasing its shared_ptr reference) when done.
 */
static void orchestrate_http_complete(rac_result_t result, const char* downloaded_path,
                                      void* callback_user_data) {
    auto* holder = static_cast<shared_ctx_holder*>(callback_user_data);
    if (!holder || !holder->ctx) {
        delete holder;
        return;
    }

    // Take ownership — holder is deleted at every exit path below
    auto ctx = holder->ctx;
    delete holder;

    if (result != RAC_SUCCESS) {
        // HTTP download failed
        RAC_LOG_ERROR(LOG_TAG, "HTTP download failed for model: %s", ctx->model_id.c_str());
        rac_download_manager_mark_failed(ctx->dm_handle, ctx->task_id.c_str(), result,
                                         "HTTP download failed");

        if (ctx->user_complete_callback) {
            ctx->user_complete_callback(ctx->task_id.c_str(), result, nullptr, ctx->user_data);
        }
        return;
    }

    std::string final_path;

    if (ctx->needs_extraction) {
        // Mark download as complete (transitions to EXTRACTING state)
        rac_download_manager_mark_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                           downloaded_path ? downloaded_path
                                                          : ctx->download_dest_path.c_str());

        RAC_LOG_INFO(LOG_TAG, "Starting extraction for model: %s", ctx->model_id.c_str());

        // Extract archive using native libarchive
        rac_extraction_result_t extraction_result = {};
        rac_result_t extract_result = rac_extract_archive_native(
            downloaded_path ? downloaded_path : ctx->download_dest_path.c_str(),
            ctx->model_folder_path.c_str(), nullptr /* default options */, nullptr /* no progress */,
            nullptr /* no user data */, &extraction_result);

        if (extract_result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_TAG, "Extraction failed for model: %s", ctx->model_id.c_str());
            rac_download_manager_mark_extraction_failed(ctx->dm_handle, ctx->task_id.c_str(),
                                                        extract_result, "Archive extraction failed");

            if (ctx->user_complete_callback) {
                ctx->user_complete_callback(ctx->task_id.c_str(), extract_result, nullptr,
                                            ctx->user_data);
            }

            // Cleanup temp archive
            delete_file(ctx->download_dest_path.c_str());
            return;
        }

        RAC_LOG_INFO(LOG_TAG, "Extraction complete: %d files, %lld bytes",
                     extraction_result.files_extracted, extraction_result.bytes_extracted);

        // Find the actual model path after extraction
        char model_path[4096];
        rac_result_t find_result = rac_find_model_path_after_extraction(
            ctx->model_folder_path.c_str(), ctx->archive_structure, ctx->framework, ctx->format,
            model_path, sizeof(model_path));

        if (find_result == RAC_SUCCESS) {
            final_path = model_path;
        } else {
            // Fallback to model folder itself
            final_path = ctx->model_folder_path;
            RAC_LOG_WARNING(
                LOG_TAG,
                "Could not find specific model file after extraction, using folder: %s",
                final_path.c_str());
        }

        // Cleanup temp archive file
        delete_file(ctx->download_dest_path.c_str());

        // Mark extraction complete
        rac_download_manager_mark_extraction_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                                      final_path.c_str());
    } else {
        // No extraction needed — file downloaded directly to model folder
        final_path =
            downloaded_path ? std::string(downloaded_path) : ctx->download_dest_path;

        rac_download_manager_mark_complete(ctx->dm_handle, ctx->task_id.c_str(),
                                           final_path.c_str());
    }

    RAC_LOG_INFO(LOG_TAG, "Download orchestration complete for model: %s → %s",
                 ctx->model_id.c_str(), final_path.c_str());

    // Invoke user callback
    if (ctx->user_complete_callback) {
        ctx->user_complete_callback(ctx->task_id.c_str(), RAC_SUCCESS, final_path.c_str(),
                                    ctx->user_data);
    }
}

// =============================================================================
// PUBLIC API — DOWNLOAD ORCHESTRATION
// =============================================================================

rac_result_t rac_download_orchestrate(rac_download_manager_handle_t dm_handle,
                                       const char* model_id, const char* download_url,
                                       rac_inference_framework_t framework,
                                       rac_model_format_t format,
                                       rac_archive_structure_t archive_structure,
                                       rac_download_progress_callback_fn progress_callback,
                                       rac_download_complete_callback_fn complete_callback,
                                       void* user_data, char** out_task_id) {
    if (!dm_handle || !model_id || !download_url || !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // 1. Compute model folder path
    char model_folder[4096];
    rac_result_t path_result =
        rac_model_paths_get_model_folder(model_id, framework, model_folder, sizeof(model_folder));
    if (path_result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to compute model folder path for: %s", model_id);
        return path_result;
    }

    // Ensure model folder exists
    mkdir_p(model_folder);

    // 2. Determine if extraction is needed
    rac_archive_type_t archive_type;
    bool needs_extraction = rac_archive_type_from_path(download_url, &archive_type) == RAC_TRUE;

    // 3. Compute download destination
    std::string download_dest;
    if (needs_extraction) {
        // Download to temp path — will be extracted to model folder
        char downloads_dir[4096];
        rac_result_t dl_result =
            rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir));
        if (dl_result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_TAG, "Failed to get downloads directory");
            return dl_result;
        }
        mkdir_p(downloads_dir);

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty()) stem = model_id;

        download_dest =
            std::string(downloads_dir) + "/" + stem + (ext.empty() ? "" : "." + ext);
    } else {
        // Download directly to model folder
        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty()) stem = model_id;

        download_dest =
            std::string(model_folder) + "/" + stem + (ext.empty() ? "" : "." + ext);
    }

    // 4. Register with download manager (creates task tracking state)
    char* task_id = nullptr;
    rac_result_t start_result = rac_download_manager_start(
        dm_handle, model_id, download_url, download_dest.c_str(),
        needs_extraction ? RAC_TRUE : RAC_FALSE, progress_callback, nullptr /* we handle complete */,
        user_data, &task_id);

    if (start_result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to register download task for: %s", model_id);
        return start_result;
    }

    // 5. Create orchestration context for callbacks (shared_ptr for safe async lifetime)
    auto ctx = std::make_shared<orchestrate_context>();
    ctx->dm_handle = dm_handle;
    ctx->model_id = model_id;
    ctx->download_url = download_url;
    ctx->framework = framework;
    ctx->format = format;
    ctx->archive_structure = archive_structure;
    ctx->download_dest_path = download_dest;
    ctx->model_folder_path = model_folder;
    ctx->needs_extraction = needs_extraction;
    ctx->task_id = task_id;
    ctx->user_progress_callback = progress_callback;
    ctx->user_complete_callback = complete_callback;
    ctx->user_data = user_data;

    // Wrap in holder for C callback void* — callback takes ownership and deletes holder
    auto* holder = new shared_ctx_holder{ctx};

    // 6. Start HTTP download via platform adapter
    char* http_task_id = nullptr;
    rac_result_t http_result =
        rac_http_download(download_url, download_dest.c_str(), orchestrate_http_progress,
                          orchestrate_http_complete, holder, &http_task_id);

    if (http_result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to start HTTP download for: %s", model_id);
        rac_download_manager_mark_failed(dm_handle, task_id, http_result,
                                         "Failed to start HTTP download");
        delete holder;  // Safe — ctx shared_ptr ref still alive until scope exit
        rac_free(task_id);
        return http_result;
    }

    if (http_task_id) {
        rac_free(http_task_id);  // We track via download manager task_id instead
    }

    *out_task_id = task_id;

    RAC_LOG_INFO(LOG_TAG, "Download orchestration started: model=%s, extraction=%s", model_id,
                 needs_extraction ? "yes" : "no");

    return RAC_SUCCESS;
}

rac_result_t rac_download_orchestrate_multi(
    rac_download_manager_handle_t dm_handle, const char* model_id,
    const rac_model_file_descriptor_t* files, size_t file_count, const char* base_download_url,
    rac_inference_framework_t framework, rac_model_format_t format,
    rac_download_progress_callback_fn progress_callback,
    rac_download_complete_callback_fn complete_callback, void* user_data, char** out_task_id) {
    if (!dm_handle || !model_id || !files || file_count == 0 || !base_download_url ||
        !out_task_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Compute model folder
    char model_folder[4096];
    rac_result_t path_result =
        rac_model_paths_get_model_folder(model_id, framework, model_folder, sizeof(model_folder));
    if (path_result != RAC_SUCCESS) {
        return path_result;
    }
    mkdir_p(model_folder);

    // Register a single task for the multi-file download
    std::string composite_url = std::string(base_download_url) + " [" +
                                std::to_string(file_count) + " files]";
    char* task_id = nullptr;
    rac_result_t start_result = rac_download_manager_start(
        dm_handle, model_id, composite_url.c_str(), model_folder, RAC_FALSE /* no extraction */,
        progress_callback, complete_callback, user_data, &task_id);

    if (start_result != RAC_SUCCESS) {
        return start_result;
    }

    // Shared state for async completion barrier across all file downloads.
    // Each launched download increments pending; its callback decrements and notifies.
    // After the loop we wait until all in-flight downloads have reported back.
    struct multi_download_barrier {
        std::mutex mtx;
        std::condition_variable cv;
        int pending{0};
        bool any_required_failed{false};
    };
    auto barrier = std::make_shared<multi_download_barrier>();

    // Per-file context passed through the C callback void*.
    struct multi_file_holder {
        std::shared_ptr<multi_download_barrier> barrier;
        bool is_required;
    };

    bool launch_failed = false;
    for (size_t i = 0; i < file_count; ++i) {
        const rac_model_file_descriptor_t& file = files[i];

        // Build full download URL
        std::string file_url = std::string(base_download_url);
        if (!file_url.empty() && file_url.back() != '/') file_url += "/";
        file_url += file.relative_path;

        // Build destination path
        std::string dest_path = std::string(model_folder);
        if (file.destination_path && file.destination_path[0] != '\0') {
            dest_path += "/" + std::string(file.destination_path);
        } else {
            dest_path += "/" + std::string(file.relative_path);
        }

        // Ensure parent directory exists
        auto last_slash = dest_path.rfind('/');
        if (last_slash != std::string::npos) {
            mkdir_p(dest_path.substr(0, last_slash).c_str());
        }

        // Update download manager with file-level progress
        int64_t fake_downloaded = static_cast<int64_t>(
            static_cast<double>(i) / static_cast<double>(file_count) * 100);
        rac_download_manager_update_progress(dm_handle, task_id, fake_downloaded, 100);

        // Increment pending count *before* launching so the barrier is always ahead of callbacks
        {
            std::lock_guard<std::mutex> lk(barrier->mtx);
            barrier->pending++;
        }

        auto* file_holder = new multi_file_holder{barrier, file.is_required == RAC_TRUE};

        auto file_complete = [](rac_result_t result, const char* /*path*/, void* ud) {
            auto* holder = static_cast<multi_file_holder*>(ud);
            if (!holder) return;

            auto b = holder->barrier;
            bool required = holder->is_required;
            delete holder;

            std::lock_guard<std::mutex> lk(b->mtx);
            if (result != RAC_SUCCESS && required) {
                b->any_required_failed = true;
            }
            b->pending--;
            b->cv.notify_all();
        };

        char* http_task_id = nullptr;
        rac_result_t http_result = rac_http_download(
            file_url.c_str(), dest_path.c_str(), nullptr /* no per-file progress */, file_complete,
            file_holder, &http_task_id);

        if (http_task_id) rac_free(http_task_id);

        if (http_result != RAC_SUCCESS) {
            // Download never started — callback won't fire, so clean up manually
            delete file_holder;
            {
                std::lock_guard<std::mutex> lk(barrier->mtx);
                barrier->pending--;  // undo the pre-increment
            }

            if (file.is_required == RAC_TRUE) {
                RAC_LOG_ERROR(LOG_TAG, "Required file download failed to start: %s",
                              file.relative_path);
                launch_failed = true;
                break;
            }
            RAC_LOG_WARNING(LOG_TAG, "Optional file download failed to start: %s",
                            file.relative_path);
            continue;
        }

        // Download started — async callback owns file_holder
    }

    // Wait for all in-flight downloads to complete before reporting final status
    {
        std::unique_lock<std::mutex> lk(barrier->mtx);
        barrier->cv.wait(lk, [&barrier] { return barrier->pending == 0; });
    }

    bool any_failed = launch_failed || barrier->any_required_failed;

    if (any_failed) {
        rac_download_manager_mark_failed(dm_handle, task_id, RAC_ERROR_DOWNLOAD_FAILED,
                                         "One or more required files failed to download");
        *out_task_id = task_id;
        return RAC_ERROR_DOWNLOAD_FAILED;
    } else {
        // Update final progress
        rac_download_manager_update_progress(dm_handle, task_id, 100, 100);
        rac_download_manager_mark_complete(dm_handle, task_id, model_folder);
    }

    *out_task_id = task_id;
    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API — POST-EXTRACTION MODEL PATH FINDING
// =============================================================================

rac_result_t rac_find_model_path_after_extraction(const char* extracted_dir,
                                                    rac_archive_structure_t structure,
                                                    rac_inference_framework_t framework,
                                                    rac_model_format_t format, char* out_path,
                                                    size_t path_size) {
    if (!extracted_dir || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // For directory-based frameworks (ONNX), the directory itself is the model path
    if (rac_framework_uses_directory_based_models(framework) == RAC_TRUE) {
        // Check for nested directory pattern
        std::string nested = find_nested_directory(extracted_dir);
        snprintf(out_path, path_size, "%s", nested.c_str());
        return RAC_SUCCESS;
    }

    // Handle based on archive structure
    switch (structure) {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED: {
            // Look for a single model file, possibly in a subdirectory (up to 2 levels deep)
            if (find_single_model_file(extracted_dir, 0, 2, out_path, path_size)) {
                return RAC_SUCCESS;
            }
            // Fallback: return extracted dir
            snprintf(out_path, path_size, "%s", extracted_dir);
            return RAC_SUCCESS;
        }

        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY: {
            // Common pattern: archive contains one subdirectory with all the files
            std::string nested = find_nested_directory(extracted_dir);
            snprintf(out_path, path_size, "%s", nested.c_str());
            return RAC_SUCCESS;
        }

        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:
        case RAC_ARCHIVE_STRUCTURE_UNKNOWN:
        default: {
            // Try to find a model file first
            if (find_single_model_file(extracted_dir, 0, 2, out_path, path_size)) {
                return RAC_SUCCESS;
            }
            // Check for nested directory
            std::string nested = find_nested_directory(extracted_dir);
            snprintf(out_path, path_size, "%s", nested.c_str());
            return RAC_SUCCESS;
        }
    }
}

// =============================================================================
// PUBLIC API — UTILITY FUNCTIONS
// =============================================================================

rac_result_t rac_download_compute_destination(const char* model_id, const char* download_url,
                                               rac_inference_framework_t framework,
                                               rac_model_format_t format, char* out_path,
                                               size_t path_size,
                                               rac_bool_t* out_needs_extraction) {
    if (!model_id || !download_url || !out_path || path_size == 0 || !out_needs_extraction) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if extraction is needed
    rac_archive_type_t archive_type;
    bool needs_extraction = rac_archive_type_from_path(download_url, &archive_type) == RAC_TRUE;
    *out_needs_extraction = needs_extraction ? RAC_TRUE : RAC_FALSE;

    if (needs_extraction) {
        // Temp path in downloads directory
        char downloads_dir[4096];
        rac_result_t result =
            rac_model_paths_get_downloads_directory(downloads_dir, sizeof(downloads_dir));
        if (result != RAC_SUCCESS) return result;

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty()) stem = model_id;

        snprintf(out_path, path_size, "%s/%s%s%s", downloads_dir, stem.c_str(),
                 ext.empty() ? "" : ".", ext.empty() ? "" : ext.c_str());
    } else {
        // Direct to model folder
        char model_folder[4096];
        rac_result_t result =
            rac_model_paths_get_model_folder(model_id, framework, model_folder, sizeof(model_folder));
        if (result != RAC_SUCCESS) return result;

        std::string ext = get_file_extension(download_url);
        std::string stem = get_filename_stem(download_url);
        if (stem.empty()) stem = model_id;

        snprintf(out_path, path_size, "%s/%s%s%s", model_folder, stem.c_str(),
                 ext.empty() ? "" : ".", ext.empty() ? "" : ext.c_str());
    }

    return RAC_SUCCESS;
}

rac_bool_t rac_download_requires_extraction(const char* download_url) {
    if (!download_url) return RAC_FALSE;

    rac_archive_type_t type;
    return rac_archive_type_from_path(download_url, &type);
}
