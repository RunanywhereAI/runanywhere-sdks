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
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

// Platform-specific file existence check
#ifdef _WIN32
#include <io.h>
#define access _access
#define F_OK 0
#else
#include <unistd.h>
#endif

// =============================================================================
// CONSTANTS - HuggingFace tokenizer URLs
// =============================================================================

// Stable Diffusion 1.5 (runwayml/stable-diffusion-v1-5)
static const char* TOKENIZER_URL_SD_1_5 =
    "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer";

// Stable Diffusion 2.x (stabilityai/stable-diffusion-2-1)
static const char* TOKENIZER_URL_SD_2_X =
    "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer";

// Stable Diffusion XL (stabilityai/stable-diffusion-xl-base-1.0)
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

    rac_bool_t has_vocab = RAC_FALSE;
    rac_bool_t has_merges = RAC_FALSE;

    rac_result_t result = rac_diffusion_tokenizer_check_files(model_dir, &has_vocab, &has_merges);
    if (result != RAC_SUCCESS) {
        return result;
    }

    // If both files exist, we're done
    if (has_vocab == RAC_TRUE && has_merges == RAC_TRUE) {
        RAC_LOG_DEBUG("Diffusion.Tokenizer", "Tokenizer files already exist in %s", model_dir);
        return RAC_SUCCESS;
    }

    // If auto_download is disabled and files are missing, return error
    if (config->auto_download != RAC_TRUE) {
        if (has_vocab != RAC_TRUE) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Missing %s in %s (auto_download disabled)",
                          RAC_DIFFUSION_TOKENIZER_VOCAB_FILE, model_dir);
        }
        if (has_merges != RAC_TRUE) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Missing %s in %s (auto_download disabled)",
                          RAC_DIFFUSION_TOKENIZER_MERGES_FILE, model_dir);
        }
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Download missing files
    const char* custom_url = config->custom_base_url;

    if (has_vocab != RAC_TRUE) {
        std::string vocab_path =
            std::string(model_dir) + "/" + RAC_DIFFUSION_TOKENIZER_VOCAB_FILE;
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
        std::string merges_path =
            std::string(model_dir) + "/" + RAC_DIFFUSION_TOKENIZER_MERGES_FILE;
        result = rac_diffusion_tokenizer_download_file(config->source, custom_url,
                                                       RAC_DIFFUSION_TOKENIZER_MERGES_FILE,
                                                       merges_path.c_str());
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("Diffusion.Tokenizer", "Failed to download %s: %d",
                          RAC_DIFFUSION_TOKENIZER_MERGES_FILE, result);
            return result;
        }
    }

    RAC_LOG_INFO("Diffusion.Tokenizer", "Tokenizer files ensured in %s", model_dir);
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

    // TODO: Implement HTTP download using platform HTTP client
    // For now, this is a placeholder that will be implemented when the ONNX backend is added.
    // The actual download will use:
    // - NSURLSession on iOS/macOS
    // - OkHttp/HttpURLConnection on Android
    // - libcurl or platform HTTP on desktop
    //
    // The platform SDKs can also implement this callback via the platform adapter pattern
    // (similar to how we do platform callbacks for LLM/TTS/Diffusion).

    RAC_LOG_WARNING("Diffusion.Tokenizer",
                    "HTTP download not yet implemented in C++ - use platform SDK download");

    // For now, return success if the file path would be valid
    // Platform SDKs should handle the actual download
    return RAC_ERROR_NOT_IMPLEMENTED;
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
