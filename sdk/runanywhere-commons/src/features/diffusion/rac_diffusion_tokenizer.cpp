/**
 * @file rac_diffusion_tokenizer.cpp
 * @brief RunAnywhere Commons - Diffusion Tokenizer Utilities Implementation
 *
 * Implementation of tokenizer file management utilities for diffusion models.
 */

#include "rac/features/diffusion/rac_diffusion_tokenizer.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <mutex>
#include <condition_variable>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

// Platform-specific file existence check
#ifdef _WIN32
#include <io.h>
#define access _access
#define F_OK 0
#else
#include <unistd.h>
#endif

// =============================================================================
// CONSTANTS - Tokenizer base URLs for Apple Stable Diffusion models
// =============================================================================
// Used when ensuring tokenizer files (vocab.json, merges.txt) for text encoding.
// Built-in Apple models: SD 1.5 CoreML and SD 2.1 CoreML use SD_1_5 and SD_2_X.

// Apple SD 1.5 (same tokenizer as runwayml/stable-diffusion-v1-5)
static const char* TOKENIZER_URL_SD_1_5 =
    "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer";

// Apple SD 2.1 (same tokenizer as stabilityai/stable-diffusion-2-1)
static const char* TOKENIZER_URL_SD_2_X =
    "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer";

// SDXL (reserved for future use; built-in app models are SD 1.5 and SD 2.1 only)
static const char* TOKENIZER_URL_SDXL =
    "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer";

// =============================================================================
// URL RESOLUTION
// =============================================================================

extern "C" const char* rac_diffusion_tokenizer_get_base_url(rac_diffusion_tokenizer_source_t source,
                                                            const char* custom_url) {
    switch (source) {
        case RAC_DIFFUSION_TOKENIZER_SD_1_5:
            return TOKENIZER_URL_SD_1_5;
        case RAC_DIFFUSION_TOKENIZER_SD_2_X:
            return TOKENIZER_URL_SD_2_X;
        case RAC_DIFFUSION_TOKENIZER_SDXL:
            return TOKENIZER_URL_SDXL;
        case RAC_DIFFUSION_TOKENIZER_CUSTOM:
            return custom_url;
        default:
            return nullptr;
    }
}

extern "C" rac_result_t rac_diffusion_tokenizer_get_file_url(rac_diffusion_tokenizer_source_t source,
                                                             const char* custom_url,
                                                             const char* filename, char* out_url,
                                                             size_t out_url_size) {
    if (!filename || !out_url || out_url_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* base_url = rac_diffusion_tokenizer_get_base_url(source, custom_url);
    if (!base_url) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Construct full URL: base_url + "/" + filename
    int written = snprintf(out_url, out_url_size, "%s/%s", base_url, filename);
    if (written < 0 || static_cast<size_t>(written) >= out_url_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    return RAC_SUCCESS;
}

// =============================================================================
// FILE MANAGEMENT
// =============================================================================

extern "C" rac_result_t rac_diffusion_tokenizer_check_files(const char* model_dir,
                                                            rac_bool_t* out_has_vocab,
                                                            rac_bool_t* out_has_merges) {
    if (!model_dir) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string vocab_path = std::string(model_dir) + "/" + RAC_DIFFUSION_TOKENIZER_VOCAB_FILE;
    std::string merges_path = std::string(model_dir) + "/" + RAC_DIFFUSION_TOKENIZER_MERGES_FILE;

    if (out_has_vocab) {
        *out_has_vocab = (access(vocab_path.c_str(), F_OK) == 0) ? RAC_TRUE : RAC_FALSE;
    }

    if (out_has_merges) {
        *out_has_merges = (access(merges_path.c_str(), F_OK) == 0) ? RAC_TRUE : RAC_FALSE;
    }

    return RAC_SUCCESS;
}

extern "C" rac_result_t
rac_diffusion_tokenizer_ensure_files(const char* model_dir,
                                     const rac_diffusion_tokenizer_config_t* config) {
    if (!model_dir || !config) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto resolve_tokenizer_dir = [](const char* base_dir) -> std::string {
        std::string root_dir = base_dir ? base_dir : "";
        if (root_dir.empty()) {
            return root_dir;
        }

        std::string root_vocab = root_dir + "/" + RAC_DIFFUSION_TOKENIZER_VOCAB_FILE;
        std::string root_merges = root_dir + "/" + RAC_DIFFUSION_TOKENIZER_MERGES_FILE;
        std::string tokenizer_dir = root_dir + "/tokenizer";
        std::string tokenizer_vocab = tokenizer_dir + "/" + RAC_DIFFUSION_TOKENIZER_VOCAB_FILE;
        std::string tokenizer_merges = tokenizer_dir + "/" + RAC_DIFFUSION_TOKENIZER_MERGES_FILE;

        bool root_has_files =
            (access(root_vocab.c_str(), F_OK) == 0) || (access(root_merges.c_str(), F_OK) == 0);
        bool tokenizer_has_files =
            (access(tokenizer_vocab.c_str(), F_OK) == 0) ||
            (access(tokenizer_merges.c_str(), F_OK) == 0);
        bool tokenizer_exists = access(tokenizer_dir.c_str(), F_OK) == 0;

        if (tokenizer_has_files || (!root_has_files && tokenizer_exists)) {
            return tokenizer_dir;
        }

        return root_dir;
    };

    std::string tokenizer_dir = resolve_tokenizer_dir(model_dir);
    if (tokenizer_dir.empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_bool_t has_vocab = RAC_FALSE;
    rac_bool_t has_merges = RAC_FALSE;

    rac_result_t result =
        rac_diffusion_tokenizer_check_files(tokenizer_dir.c_str(), &has_vocab, &has_merges);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // If both files exist, we're done
    if (has_vocab == RAC_TRUE && has_merges == RAC_TRUE) {
        RAC_LOG_DEBUG("Diffusion.Tokenizer", "Tokenizer files already exist in %s",
                      tokenizer_dir.c_str());
        return RAC_SUCCESS;
    }

    // If auto_download is disabled and files are missing, return error
    if (config->auto_download != RAC_TRUE) {
        if (has_vocab != RAC_TRUE) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Missing %s in %s (auto_download disabled)",
                          RAC_DIFFUSION_TOKENIZER_VOCAB_FILE, tokenizer_dir.c_str());
        }
        if (has_merges != RAC_TRUE) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Missing %s in %s (auto_download disabled)",
                          RAC_DIFFUSION_TOKENIZER_MERGES_FILE, tokenizer_dir.c_str());
        }
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Download missing files
    const char* custom_url = config->custom_base_url;

    if (has_vocab != RAC_TRUE) {
        std::string vocab_path = tokenizer_dir + "/" + RAC_DIFFUSION_TOKENIZER_VOCAB_FILE;
        result = rac_diffusion_tokenizer_download_file(config->source, custom_url,
                                                       RAC_DIFFUSION_TOKENIZER_VOCAB_FILE,
                                                       vocab_path.c_str());
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Failed to download %s: %d",
                          RAC_DIFFUSION_TOKENIZER_VOCAB_FILE, result);
            return result;
        }
    }

    if (has_merges != RAC_TRUE) {
        std::string merges_path = tokenizer_dir + "/" + RAC_DIFFUSION_TOKENIZER_MERGES_FILE;
        result = rac_diffusion_tokenizer_download_file(config->source, custom_url,
                                                       RAC_DIFFUSION_TOKENIZER_MERGES_FILE,
                                                       merges_path.c_str());
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Failed to download %s: %d",
                          RAC_DIFFUSION_TOKENIZER_MERGES_FILE, result);
            return result;
        }
    }

    RAC_LOG_INFO("Diffusion.Tokenizer", "Tokenizer files ensured in %s", tokenizer_dir.c_str());
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_diffusion_tokenizer_download_file(rac_diffusion_tokenizer_source_t source,
                                                              const char* custom_url,
                                                              const char* filename,
                                                              const char* output_path) {
    if (!filename || !output_path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Get full URL
    char url[1024];
    rac_result_t result =
        rac_diffusion_tokenizer_get_file_url(source, custom_url, filename, url, sizeof(url));
    if (result != RAC_SUCCESS) {
        return result;
    }

    RAC_LOG_INFO("Diffusion.Tokenizer", "Downloading %s from %s", filename, url);

    struct download_context {
        std::mutex mutex;
        std::condition_variable cv;
        bool completed = false;
        rac_result_t result = RAC_ERROR_DOWNLOAD_FAILED;
    };

    auto progress_cb = [](int64_t /*downloaded*/, int64_t /*total*/, void* /*user_data*/) {};

    auto complete_cb = [](rac_result_t result, const char* /*downloaded_path*/,
                          void* user_data) {
        auto* ctx = static_cast<download_context*>(user_data);
        if (!ctx) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(ctx->mutex);
            ctx->result = result;
            ctx->completed = true;
        }
        ctx->cv.notify_one();
    };

    download_context ctx;
    char* task_id = nullptr;

    rac_result_t start_result = rac_http_download(url, output_path, progress_cb, complete_cb,
                                                  &ctx, &task_id);
    if (start_result != RAC_SUCCESS) {
        if (task_id) {
            rac_free(task_id);
        }
        RAC_LOG_ERROR("Diffusion.Tokenizer", "HTTP download start failed: %d", start_result);
        return start_result;
    }

    std::unique_lock<std::mutex> lock(ctx.mutex);
    ctx.cv.wait(lock, [&ctx]() { return ctx.completed; });

    if (task_id) {
        rac_free(task_id);
    }

    if (ctx.result != RAC_SUCCESS) {
        RAC_LOG_ERROR("Diffusion.Tokenizer", "HTTP download failed: %d", ctx.result);
    }

    return ctx.result;
}

// =============================================================================
// DEFAULT TOKENIZER SOURCE
// =============================================================================

extern "C" rac_diffusion_tokenizer_source_t
rac_diffusion_tokenizer_default_for_variant(rac_diffusion_model_variant_t model_variant) {
    switch (model_variant) {
        case RAC_DIFFUSION_MODEL_SD_1_5:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5;
        case RAC_DIFFUSION_MODEL_SD_2_1:
            return RAC_DIFFUSION_TOKENIZER_SD_2_X;
        case RAC_DIFFUSION_MODEL_SDXL:
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            return RAC_DIFFUSION_TOKENIZER_SDXL;
        default:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5;
    }
}
