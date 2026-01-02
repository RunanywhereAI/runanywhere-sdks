/**
 * @file rac_model_types.h
 * @brief Model Types - Comprehensive Type Definitions for Model Management
 *
 * C port of Swift's model type definitions from:
 * - ModelCategory.swift
 * - ModelFormat.swift
 * - ModelArtifactType.swift
 * - InferenceFramework.swift
 * - ModelInfo.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_MODEL_TYPES_H
#define RAC_MODEL_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// ARCHIVE TYPES - From ModelArtifactType.swift
// =============================================================================

/**
 * @brief Supported archive formats for model packaging.
 * Mirrors Swift's ArchiveType enum.
 */
typedef enum rac_archive_type {
    RAC_ARCHIVE_TYPE_NONE = -1,   /**< No archive - direct file */
    RAC_ARCHIVE_TYPE_ZIP = 0,     /**< ZIP archive */
    RAC_ARCHIVE_TYPE_TAR_BZ2 = 1, /**< tar.bz2 archive */
    RAC_ARCHIVE_TYPE_TAR_GZ = 2,  /**< tar.gz archive */
    RAC_ARCHIVE_TYPE_TAR_XZ = 3   /**< tar.xz archive */
} rac_archive_type_t;

/**
 * @brief Internal structure of an archive after extraction.
 * Mirrors Swift's ArchiveStructure enum.
 */
typedef enum rac_archive_structure {
    RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED =
        0, /**< Single model file at root or nested in one directory */
    RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED = 1,  /**< Multiple files in a directory */
    RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY = 2, /**< Subdirectory structure */
    RAC_ARCHIVE_STRUCTURE_UNKNOWN = 99          /**< Unknown - detected after extraction */
} rac_archive_structure_t;

// =============================================================================
// EXPECTED MODEL FILES - From ModelArtifactType.swift
// =============================================================================

/**
 * @brief Expected model files after extraction/download.
 * Mirrors Swift's ExpectedModelFiles struct.
 */
typedef struct rac_expected_model_files {
    /** File patterns that must be present (e.g., "*.onnx", "encoder*.onnx") */
    const char** required_patterns;
    size_t required_pattern_count;

    /** File patterns that may be present but are optional */
    const char** optional_patterns;
    size_t optional_pattern_count;

    /** Description of the model files for documentation */
    const char* description;
} rac_expected_model_files_t;

/**
 * @brief Multi-file model descriptor.
 * Mirrors Swift's ModelFileDescriptor struct.
 */
typedef struct rac_model_file_descriptor {
    /** Relative path from base URL to this file */
    const char* relative_path;

    /** Destination path relative to model folder */
    const char* destination_path;

    /** Whether this file is required (vs optional) */
    rac_bool_t is_required;
} rac_model_file_descriptor_t;

// =============================================================================
// MODEL ARTIFACT TYPE - From ModelArtifactType.swift
// =============================================================================

/**
 * @brief Model artifact type enumeration.
 * Mirrors Swift's ModelArtifactType enum (simplified for C).
 */
typedef enum rac_artifact_type_kind {
    RAC_ARTIFACT_KIND_SINGLE_FILE = 0, /**< Single file download */
    RAC_ARTIFACT_KIND_ARCHIVE = 1,     /**< Archive requiring extraction */
    RAC_ARTIFACT_KIND_MULTI_FILE = 2,  /**< Multiple files */
    RAC_ARTIFACT_KIND_CUSTOM = 3,      /**< Custom download strategy */
    RAC_ARTIFACT_KIND_BUILT_IN = 4     /**< Built-in model (no download) */
} rac_artifact_type_kind_t;

/**
 * @brief Full model artifact type with associated data.
 * Mirrors Swift's ModelArtifactType enum with associated values.
 */
typedef struct rac_model_artifact_info {
    /** The kind of artifact */
    rac_artifact_type_kind_t kind;

    /** For archive type: the archive format */
    rac_archive_type_t archive_type;

    /** For archive type: the internal structure */
    rac_archive_structure_t archive_structure;

    /** Expected files after extraction (can be NULL) */
    rac_expected_model_files_t* expected_files;

    /** For multi-file: descriptors array (can be NULL) */
    rac_model_file_descriptor_t* file_descriptors;
    size_t file_descriptor_count;

    /** For custom: strategy identifier */
    const char* strategy_id;
} rac_model_artifact_info_t;

// =============================================================================
// MODEL CATEGORY - From ModelCategory.swift
// =============================================================================

/**
 * @brief Model category based on input/output modality.
 * Mirrors Swift's ModelCategory enum.
 */
typedef enum rac_model_category {
    RAC_MODEL_CATEGORY_LANGUAGE = 0,           /**< Text-to-text models (LLMs) */
    RAC_MODEL_CATEGORY_SPEECH_RECOGNITION = 1, /**< Voice-to-text models (ASR/STT) */
    RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS = 2,   /**< Text-to-voice models (TTS) */
    RAC_MODEL_CATEGORY_VISION = 3,             /**< Image understanding models */
    RAC_MODEL_CATEGORY_IMAGE_GENERATION = 4,   /**< Text-to-image models */
    RAC_MODEL_CATEGORY_MULTIMODAL = 5,         /**< Multi-modality models */
    RAC_MODEL_CATEGORY_AUDIO = 6,              /**< Audio processing (diarization, etc.) */
    RAC_MODEL_CATEGORY_UNKNOWN = 99            /**< Unknown category */
} rac_model_category_t;

// =============================================================================
// MODEL FORMAT - From ModelFormat.swift
// =============================================================================

/**
 * @brief Supported model file formats.
 * Mirrors Swift's ModelFormat enum.
 */
typedef enum rac_model_format {
    RAC_MODEL_FORMAT_ONNX = 0,    /**< ONNX format */
    RAC_MODEL_FORMAT_ORT = 1,     /**< ONNX Runtime format */
    RAC_MODEL_FORMAT_GGUF = 2,    /**< GGUF format (llama.cpp) */
    RAC_MODEL_FORMAT_BIN = 3,     /**< Binary format */
    RAC_MODEL_FORMAT_UNKNOWN = 99 /**< Unknown format */
} rac_model_format_t;

// =============================================================================
// INFERENCE FRAMEWORK - From InferenceFramework.swift
// =============================================================================

/**
 * @brief Supported inference frameworks/runtimes.
 * Mirrors Swift's InferenceFramework enum.
 */
typedef enum rac_inference_framework {
    RAC_FRAMEWORK_ONNX = 0,              /**< ONNX Runtime */
    RAC_FRAMEWORK_LLAMACPP = 1,          /**< llama.cpp */
    RAC_FRAMEWORK_FOUNDATION_MODELS = 2, /**< Apple Foundation Models */
    RAC_FRAMEWORK_SYSTEM_TTS = 3,        /**< System TTS */
    RAC_FRAMEWORK_FLUID_AUDIO = 4,       /**< FluidAudio */
    RAC_FRAMEWORK_BUILTIN = 5,           /**< Built-in (e.g., energy VAD) */
    RAC_FRAMEWORK_NONE = 6,              /**< No framework needed */
    RAC_FRAMEWORK_UNKNOWN = 99           /**< Unknown framework */
} rac_inference_framework_t;

// =============================================================================
// MODEL SOURCE
// =============================================================================

/**
 * @brief Model source enumeration.
 * Mirrors Swift's ModelSource enum.
 */
typedef enum rac_model_source {
    RAC_MODEL_SOURCE_REMOTE = 0, /**< Model from remote API/catalog */
    RAC_MODEL_SOURCE_LOCAL = 1   /**< Model provided locally */
} rac_model_source_t;

// =============================================================================
// MODEL INFO - From ModelInfo.swift
// =============================================================================

/**
 * @brief Complete model information structure.
 * Mirrors Swift's ModelInfo struct.
 */
typedef struct rac_model_info {
    /** Unique model identifier */
    char* id;

    /** Human-readable model name */
    char* name;

    /** Model category */
    rac_model_category_t category;

    /** Model format */
    rac_model_format_t format;

    /** Inference framework */
    rac_inference_framework_t framework;

    /** Download URL (can be NULL) */
    char* download_url;

    /** Local path (can be NULL) */
    char* local_path;

    /** Artifact information */
    rac_model_artifact_info_t artifact_info;

    /** Download size in bytes (0 if unknown) */
    int64_t download_size;

    /** Memory required in bytes (0 if unknown) */
    int64_t memory_required;

    /** Context length (for language models, 0 if not applicable) */
    int32_t context_length;

    /** Whether model supports thinking/reasoning */
    rac_bool_t supports_thinking;

    /** Tags (NULL-terminated array of strings, can be NULL) */
    char** tags;
    size_t tag_count;

    /** Description (can be NULL) */
    char* description;

    /** Model source */
    rac_model_source_t source;

    /** Created timestamp (Unix timestamp) */
    int64_t created_at;

    /** Updated timestamp (Unix timestamp) */
    int64_t updated_at;

    /** Last used timestamp (0 if never used) */
    int64_t last_used;

    /** Usage count */
    int32_t usage_count;
} rac_model_info_t;

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * @brief Get file extension for archive type.
 * Mirrors Swift's ArchiveType.fileExtension.
 *
 * @param type Archive type
 * @return File extension string (e.g., "zip", "tar.bz2")
 */
RAC_API const char* rac_archive_type_extension(rac_archive_type_t type);

/**
 * @brief Detect archive type from URL path.
 * Mirrors Swift's ArchiveType.from(url:).
 *
 * @param url_path URL path string
 * @param out_type Output: Detected archive type
 * @return RAC_TRUE if archive detected, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_archive_type_from_path(const char* url_path, rac_archive_type_t* out_type);

/**
 * @brief Check if model category requires context length.
 * Mirrors Swift's ModelCategory.requiresContextLength.
 *
 * @param category Model category
 * @return RAC_TRUE if requires context length
 */
RAC_API rac_bool_t rac_model_category_requires_context_length(rac_model_category_t category);

/**
 * @brief Check if model category supports thinking/reasoning.
 * Mirrors Swift's ModelCategory.supportsThinking.
 *
 * @param category Model category
 * @return RAC_TRUE if supports thinking
 */
RAC_API rac_bool_t rac_model_category_supports_thinking(rac_model_category_t category);

/**
 * @brief Get model category from framework.
 * Mirrors Swift's ModelCategory.from(framework:).
 *
 * @param framework Inference framework
 * @return Model category
 */
RAC_API rac_model_category_t rac_model_category_from_framework(rac_inference_framework_t framework);

/**
 * @brief Get supported formats for a framework.
 * Mirrors Swift's InferenceFramework.supportedFormats.
 *
 * @param framework Inference framework
 * @param out_formats Output: Array of supported formats
 * @param out_count Output: Number of formats
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_framework_get_supported_formats(rac_inference_framework_t framework,
                                                         rac_model_format_t** out_formats,
                                                         size_t* out_count);

/**
 * @brief Check if framework supports a format.
 * Mirrors Swift's InferenceFramework.supports(format:).
 *
 * @param framework Inference framework
 * @param format Model format
 * @return RAC_TRUE if supported
 */
RAC_API rac_bool_t rac_framework_supports_format(rac_inference_framework_t framework,
                                                 rac_model_format_t format);

/**
 * @brief Check if framework uses directory-based models.
 * Mirrors Swift's InferenceFramework.usesDirectoryBasedModels.
 *
 * @param framework Inference framework
 * @return RAC_TRUE if uses directory-based models
 */
RAC_API rac_bool_t rac_framework_uses_directory_based_models(rac_inference_framework_t framework);

/**
 * @brief Check if framework supports LLM.
 * Mirrors Swift's InferenceFramework.supportsLLM.
 *
 * @param framework Inference framework
 * @return RAC_TRUE if supports LLM
 */
RAC_API rac_bool_t rac_framework_supports_llm(rac_inference_framework_t framework);

/**
 * @brief Check if framework supports STT.
 * Mirrors Swift's InferenceFramework.supportsSTT.
 *
 * @param framework Inference framework
 * @return RAC_TRUE if supports STT
 */
RAC_API rac_bool_t rac_framework_supports_stt(rac_inference_framework_t framework);

/**
 * @brief Check if framework supports TTS.
 * Mirrors Swift's InferenceFramework.supportsTTS.
 *
 * @param framework Inference framework
 * @return RAC_TRUE if supports TTS
 */
RAC_API rac_bool_t rac_framework_supports_tts(rac_inference_framework_t framework);

/**
 * @brief Get framework display name.
 * Mirrors Swift's InferenceFramework.displayName.
 *
 * @param framework Inference framework
 * @return Display name string
 */
RAC_API const char* rac_framework_display_name(rac_inference_framework_t framework);

/**
 * @brief Get framework analytics key.
 * Mirrors Swift's InferenceFramework.analyticsKey.
 *
 * @param framework Inference framework
 * @return Analytics key string (snake_case)
 */
RAC_API const char* rac_framework_analytics_key(rac_inference_framework_t framework);

/**
 * @brief Check if artifact requires extraction.
 * Mirrors Swift's ModelArtifactType.requiresExtraction.
 *
 * @param artifact Artifact info
 * @return RAC_TRUE if requires extraction
 */
RAC_API rac_bool_t rac_artifact_requires_extraction(const rac_model_artifact_info_t* artifact);

/**
 * @brief Check if artifact requires download.
 * Mirrors Swift's ModelArtifactType.requiresDownload.
 *
 * @param artifact Artifact info
 * @return RAC_TRUE if requires download
 */
RAC_API rac_bool_t rac_artifact_requires_download(const rac_model_artifact_info_t* artifact);

/**
 * @brief Infer artifact type from URL.
 * Mirrors Swift's ModelArtifactType.infer(from:format:).
 *
 * @param url Download URL (can be NULL)
 * @param format Model format
 * @param out_artifact Output: Inferred artifact info
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_artifact_infer_from_url(const char* url, rac_model_format_t format,
                                                 rac_model_artifact_info_t* out_artifact);

/**
 * @brief Check if model is downloaded and available.
 * Mirrors Swift's ModelInfo.isDownloaded.
 *
 * @param model Model info
 * @return RAC_TRUE if downloaded
 */
RAC_API rac_bool_t rac_model_info_is_downloaded(const rac_model_info_t* model);

// =============================================================================
// FORMAT DETECTION - From RegistryService.swift
// =============================================================================

/**
 * @brief Detect model format from file extension.
 * Ported from Swift RegistryService.detectFormatFromExtension() (lines 330-338)
 *
 * @param extension File extension (without dot, e.g., "onnx", "gguf")
 * @param out_format Output: Detected format
 * @return RAC_TRUE if format detected, RAC_FALSE if unknown
 */
RAC_API rac_bool_t rac_model_detect_format_from_extension(const char* extension,
                                                          rac_model_format_t* out_format);

/**
 * @brief Detect framework from model format.
 * Ported from Swift RegistryService.detectFramework(for:) (lines 340-343)
 *
 * @param format Model format
 * @param out_framework Output: Detected framework
 * @return RAC_TRUE if framework detected, RAC_FALSE if unknown
 */
RAC_API rac_bool_t rac_model_detect_framework_from_format(rac_model_format_t format,
                                                          rac_inference_framework_t* out_framework);

/**
 * @brief Get file extension string for a model format.
 * Mirrors Swift's ModelFormat.fileExtension.
 *
 * @param format Model format
 * @return Extension string (e.g., "onnx", "gguf") or NULL if unknown
 */
RAC_API const char* rac_model_format_extension(rac_model_format_t format);

// =============================================================================
// MODEL ID/NAME GENERATION - From RegistryService.swift
// =============================================================================

/**
 * @brief Generate model ID from URL by stripping known extensions.
 * Ported from Swift RegistryService.generateModelId(from:) (lines 311-318)
 *
 * @param url URL path string (e.g., "model.tar.gz", "llama-7b.gguf")
 * @param out_id Output buffer for model ID
 * @param max_len Maximum length of output buffer
 */
RAC_API void rac_model_generate_id(const char* url, char* out_id, size_t max_len);

/**
 * @brief Generate human-readable model name from URL.
 * Ported from Swift RegistryService.generateModelName(from:) (lines 320-324)
 * Replaces underscores and dashes with spaces.
 *
 * @param url URL path string
 * @param out_name Output buffer for model name
 * @param max_len Maximum length of output buffer
 */
RAC_API void rac_model_generate_name(const char* url, char* out_name, size_t max_len);

// =============================================================================
// MODEL FILTERING - From RegistryService.swift
// =============================================================================

/**
 * @brief Model filtering criteria.
 * Mirrors Swift's ModelCriteria struct.
 */
typedef struct rac_model_filter {
    /** Filter by framework (RAC_FRAMEWORK_UNKNOWN = any) */
    rac_inference_framework_t framework;

    /** Filter by format (RAC_MODEL_FORMAT_UNKNOWN = any) */
    rac_model_format_t format;

    /** Maximum download size in bytes (0 = no limit) */
    int64_t max_size;

    /** Search query for name/id/description (NULL = no search filter) */
    const char* search_query;
} rac_model_filter_t;

/**
 * @brief Filter models by criteria.
 * Ported from Swift RegistryService.filterModels(by:) (lines 104-126)
 *
 * @param models Array of models to filter
 * @param models_count Number of models in input array
 * @param filter Filter criteria (NULL = no filtering, return all)
 * @param out_models Output array for filtered models (caller allocates)
 * @param out_capacity Maximum capacity of output array
 * @return Number of models that passed the filter (may exceed out_capacity)
 */
RAC_API size_t rac_model_filter_models(const rac_model_info_t* models, size_t models_count,
                                       const rac_model_filter_t* filter,
                                       rac_model_info_t* out_models, size_t out_capacity);

/**
 * @brief Check if a model matches filter criteria.
 * Helper function for filtering.
 *
 * @param model Model to check
 * @param filter Filter criteria
 * @return RAC_TRUE if model matches, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_model_matches_filter(const rac_model_info_t* model,
                                            const rac_model_filter_t* filter);

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Allocate expected model files structure.
 *
 * @return Allocated structure (must be freed with rac_expected_model_files_free)
 */
RAC_API rac_expected_model_files_t* rac_expected_model_files_alloc(void);

/**
 * @brief Free expected model files structure.
 *
 * @param files Structure to free
 */
RAC_API void rac_expected_model_files_free(rac_expected_model_files_t* files);

/**
 * @brief Allocate model file descriptor array.
 *
 * @param count Number of descriptors
 * @return Allocated array (must be freed with rac_model_file_descriptors_free)
 */
RAC_API rac_model_file_descriptor_t* rac_model_file_descriptors_alloc(size_t count);

/**
 * @brief Free model file descriptor array.
 *
 * @param descriptors Array to free
 * @param count Number of descriptors
 */
RAC_API void rac_model_file_descriptors_free(rac_model_file_descriptor_t* descriptors,
                                             size_t count);

/**
 * @brief Allocate model info structure.
 *
 * @return Allocated structure (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t* rac_model_info_alloc(void);

/**
 * @brief Free model info structure.
 *
 * @param model Model info to free
 */
RAC_API void rac_model_info_free(rac_model_info_t* model);

/**
 * @brief Free array of model info pointers.
 *
 * @param models Array of model info pointers
 * @param count Number of models
 */
RAC_API void rac_model_info_array_free(rac_model_info_t** models, size_t count);

/**
 * @brief Deep copy model info structure.
 *
 * @param model Model info to copy
 * @return Deep copy (must be freed with rac_model_info_free)
 */
RAC_API rac_model_info_t* rac_model_info_copy(const rac_model_info_t* model);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_TYPES_H */
