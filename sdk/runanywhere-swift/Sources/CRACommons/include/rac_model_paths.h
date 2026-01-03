/**
 * @file rac_model_paths.h
 * @brief Model Path Utilities - Centralized Path Calculation
 *
 * C port of Swift's ModelPathUtils from:
 * Sources/RunAnywhere/Infrastructure/ModelManagement/Utilities/ModelPathUtils.swift
 *
 * Path structure: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_MODEL_PATHS_H
#define RAC_MODEL_PATHS_H

#include <stddef.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief Set the base directory for model storage.
 *
 * This must be called before using any path utilities.
 * On iOS, this would typically be the Documents directory.
 * The Swift platform adapter should call this during initialization.
 *
 * @param base_dir Base directory path (e.g.,
 * "/var/mobile/Containers/Data/Application/.../Documents")
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_set_base_dir(const char* base_dir);

/**
 * @brief Get the configured base directory.
 *
 * @return Base directory path, or NULL if not configured
 */
RAC_API const char* rac_model_paths_get_base_dir(void);

// =============================================================================
// BASE DIRECTORIES - Mirrors ModelPathUtils base directory methods
// =============================================================================

/**
 * @brief Get the base RunAnywhere directory.
 * Mirrors Swift's ModelPathUtils.getBaseDirectory().
 *
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_base_directory(char* out_path, size_t path_size);

/**
 * @brief Get the models directory.
 * Mirrors Swift's ModelPathUtils.getModelsDirectory().
 *
 * Returns: `{base_dir}/RunAnywhere/Models/`
 *
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_models_directory(char* out_path, size_t path_size);

// =============================================================================
// FRAMEWORK-SPECIFIC PATHS - Mirrors ModelPathUtils framework methods
// =============================================================================

/**
 * @brief Get the directory for a specific framework.
 * Mirrors Swift's ModelPathUtils.getFrameworkDirectory(framework:).
 *
 * Returns: `{base_dir}/RunAnywhere/Models/{framework}/`
 *
 * @param framework Inference framework
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_framework_directory(rac_inference_framework_t framework,
                                                             char* out_path, size_t path_size);

/**
 * @brief Get the folder for a specific model.
 * Mirrors Swift's ModelPathUtils.getModelFolder(modelId:framework:).
 *
 * Returns: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
 *
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_model_folder(const char* model_id,
                                                      rac_inference_framework_t framework,
                                                      char* out_path, size_t path_size);

// =============================================================================
// MODEL FILE PATHS - Mirrors ModelPathUtils file path methods
// =============================================================================

/**
 * @brief Get the full path to a model file.
 * Mirrors Swift's ModelPathUtils.getModelFilePath(modelId:framework:format:).
 *
 * Returns: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/{modelId}.{format}`
 *
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param format Model format
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_model_file_path(const char* model_id,
                                                         rac_inference_framework_t framework,
                                                         rac_model_format_t format, char* out_path,
                                                         size_t path_size);

/**
 * @brief Get the expected model path for a model.
 * Mirrors Swift's ModelPathUtils.getExpectedModelPath(modelId:framework:format:).
 *
 * For directory-based frameworks (e.g., ONNX), returns the model folder.
 * For single-file frameworks (e.g., LlamaCpp), returns the model file path.
 *
 * @param model_id Model identifier
 * @param framework Inference framework
 * @param format Model format
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_expected_model_path(const char* model_id,
                                                             rac_inference_framework_t framework,
                                                             rac_model_format_t format,
                                                             char* out_path, size_t path_size);

/**
 * @brief Get the model path from model info.
 * Mirrors Swift's ModelPathUtils.getModelPath(modelInfo:).
 *
 * @param model_info Model information
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_model_path(const rac_model_info_t* model_info,
                                                    char* out_path, size_t path_size);

// =============================================================================
// OTHER DIRECTORIES - Mirrors ModelPathUtils other directory methods
// =============================================================================

/**
 * @brief Get the cache directory.
 * Mirrors Swift's ModelPathUtils.getCacheDirectory().
 *
 * Returns: `{base_dir}/RunAnywhere/Cache/`
 *
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_cache_directory(char* out_path, size_t path_size);

/**
 * @brief Get the temporary files directory.
 * Mirrors Swift's ModelPathUtils.getTempDirectory().
 *
 * Returns: `{base_dir}/RunAnywhere/Temp/`
 *
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_temp_directory(char* out_path, size_t path_size);

/**
 * @brief Get the downloads directory.
 * Mirrors Swift's ModelPathUtils.getDownloadsDirectory().
 *
 * Returns: `{base_dir}/RunAnywhere/Downloads/`
 *
 * @param out_path Output buffer for path
 * @param path_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_model_paths_get_downloads_directory(char* out_path, size_t path_size);

// =============================================================================
// PATH ANALYSIS - Mirrors ModelPathUtils analysis methods
// =============================================================================

/**
 * @brief Extract model ID from a file path.
 * Mirrors Swift's ModelPathUtils.extractModelId(from:).
 *
 * @param path File path
 * @param out_model_id Output buffer for model ID (can be NULL to just check if valid)
 * @param model_id_size Size of output buffer
 * @return RAC_SUCCESS if model ID found, RAC_ERROR_NOT_FOUND otherwise
 */
RAC_API rac_result_t rac_model_paths_extract_model_id(const char* path, char* out_model_id,
                                                      size_t model_id_size);

/**
 * @brief Extract framework from a file path.
 * Mirrors Swift's ModelPathUtils.extractFramework(from:).
 *
 * @param path File path
 * @param out_framework Output: The framework if found
 * @return RAC_SUCCESS if framework found, RAC_ERROR_NOT_FOUND otherwise
 */
RAC_API rac_result_t rac_model_paths_extract_framework(const char* path,
                                                       rac_inference_framework_t* out_framework);

/**
 * @brief Check if a path is within the models directory.
 * Mirrors Swift's ModelPathUtils.isModelPath(_:).
 *
 * @param path File path to check
 * @return RAC_TRUE if path is within models directory, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_model_paths_is_model_path(const char* path);

// =============================================================================
// PATH UTILITIES
// =============================================================================

/**
 * @brief Get file extension string for a model format.
 *
 * @param format Model format
 * @return File extension string (e.g., "gguf", "onnx")
 */
RAC_API const char* rac_model_format_extension(rac_model_format_t format);

/**
 * @brief Get raw value string for a framework.
 *
 * @param framework Inference framework
 * @return Raw value string (e.g., "LlamaCpp", "ONNX")
 */
RAC_API const char* rac_framework_raw_value(rac_inference_framework_t framework);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_PATHS_H */
