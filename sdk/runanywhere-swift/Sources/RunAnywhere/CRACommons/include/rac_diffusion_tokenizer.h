/**
 * @file rac_diffusion_tokenizer.h
 * @brief RunAnywhere Commons - Diffusion Tokenizer Utilities
 *
 * Utilities for managing diffusion model tokenizer files.
 * Apple's compiled CoreML models don't include tokenizer files (vocab.json, merges.txt),
 * so they must be downloaded from HuggingFace.
 *
 * This API provides:
 * - URL resolution for predefined tokenizer sources
 * - Automatic download of missing tokenizer files
 * - Support for custom tokenizer URLs
 */

#ifndef RAC_DIFFUSION_TOKENIZER_H
#define RAC_DIFFUSION_TOKENIZER_H

// Flattened includes for Swift SDK
#include "rac_types.h"
#include "rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TOKENIZER FILE NAMES
// =============================================================================

/** Vocabulary file name */
#define RAC_DIFFUSION_TOKENIZER_VOCAB_FILE "vocab.json"

/** Merge rules file name */
#define RAC_DIFFUSION_TOKENIZER_MERGES_FILE "merges.txt"

// =============================================================================
// URL RESOLUTION
// =============================================================================

/**
 * @brief Get the base URL for a tokenizer source
 *
 * Returns the HuggingFace URL for the specified tokenizer source.
 * For custom sources, returns the custom_base_url from config.
 *
 * @param source Tokenizer source preset
 * @param custom_url Custom URL (only used when source == RAC_DIFFUSION_TOKENIZER_CUSTOM)
 * @return Base URL string (static, do not free), or NULL if invalid
 *
 * @note URLs returned are HuggingFace raw file URLs (resolve/main/tokenizer)
 *
 * Example return values:
 * - SD_1_5: "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
 * - SD_2_X: "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
 * - SDXL:   "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
 * - CUSTOM: Returns custom_url parameter
 */
RAC_API const char* rac_diffusion_tokenizer_get_base_url(rac_diffusion_tokenizer_source_t source,
                                                         const char* custom_url);

/**
 * @brief Get the full URL for a tokenizer file
 *
 * Constructs the full URL for downloading a specific tokenizer file.
 *
 * @param source Tokenizer source preset
 * @param custom_url Custom URL (only used when source == RAC_DIFFUSION_TOKENIZER_CUSTOM)
 * @param filename File name to append (e.g., "vocab.json" or "merges.txt")
 * @param out_url Output buffer for the full URL
 * @param out_url_size Size of output buffer
 * @return RAC_SUCCESS or error code
 *
 * Example:
 * @code
 * char url[512];
 * rac_diffusion_tokenizer_get_file_url(
 *     RAC_DIFFUSION_TOKENIZER_SD_1_5,
 *     NULL,
 *     "vocab.json",
 *     url,
 *     sizeof(url)
 * );
 * // url = "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer/vocab.json"
 * @endcode
 */
RAC_API rac_result_t rac_diffusion_tokenizer_get_file_url(rac_diffusion_tokenizer_source_t source,
                                                          const char* custom_url,
                                                          const char* filename, char* out_url,
                                                          size_t out_url_size);

// =============================================================================
// FILE MANAGEMENT
// =============================================================================

/**
 * @brief Check if tokenizer files exist in a directory
 *
 * @param model_dir Path to the model directory
 * @param out_has_vocab Output: true if vocab.json exists
 * @param out_has_merges Output: true if merges.txt exists
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_tokenizer_check_files(const char* model_dir,
                                                         rac_bool_t* out_has_vocab,
                                                         rac_bool_t* out_has_merges);

/**
 * @brief Ensure tokenizer files exist, downloading if necessary
 *
 * Checks for vocab.json and merges.txt in the model directory.
 * If missing and auto_download is enabled, downloads from the configured source.
 *
 * @param model_dir Path to the model directory
 * @param config Tokenizer configuration (source, custom URL, auto_download)
 * @return RAC_SUCCESS if files exist or were downloaded successfully
 *         RAC_ERROR_FILE_NOT_FOUND if files missing and auto_download disabled
 *         RAC_ERROR_NETWORK if download failed
 *
 * Example:
 * @code
 * rac_diffusion_tokenizer_config_t config = {
 *     .source = RAC_DIFFUSION_TOKENIZER_SD_1_5,
 *     .custom_base_url = NULL,
 *     .auto_download = RAC_TRUE
 * };
 * rac_result_t result = rac_diffusion_tokenizer_ensure_files("/path/to/model", &config);
 * @endcode
 */
RAC_API rac_result_t
rac_diffusion_tokenizer_ensure_files(const char* model_dir,
                                     const rac_diffusion_tokenizer_config_t* config);

/**
 * @brief Download a tokenizer file
 *
 * Downloads a specific tokenizer file from the configured source.
 *
 * @param source Tokenizer source preset
 * @param custom_url Custom URL (only used when source == RAC_DIFFUSION_TOKENIZER_CUSTOM)
 * @param filename File name to download (e.g., "vocab.json")
 * @param output_path Full path where the file should be saved
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_diffusion_tokenizer_download_file(rac_diffusion_tokenizer_source_t source,
                                                           const char* custom_url,
                                                           const char* filename,
                                                           const char* output_path);

// =============================================================================
// DEFAULT TOKENIZER SOURCE FOR MODEL VARIANT
// =============================================================================

/**
 * @brief Get the default tokenizer source for a model variant
 *
 * Returns the recommended tokenizer source for a given model variant.
 *
 * @param model_variant Model variant (SD 1.5, SD 2.1, SDXL, etc.)
 * @return Default tokenizer source
 */
RAC_API rac_diffusion_tokenizer_source_t
rac_diffusion_tokenizer_default_for_variant(rac_diffusion_model_variant_t model_variant);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_TOKENIZER_H */
