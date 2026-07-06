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
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_model_format_ids.h"

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
 * @brief Role of a file inside a model artifact.
 *
 * Values mirror runanywhere.v1.ModelFileRole.
 */
typedef enum rac_model_file_role {
    RAC_MODEL_FILE_ROLE_UNSPECIFIED = 0,
    RAC_MODEL_FILE_ROLE_PRIMARY_MODEL = 1,
    RAC_MODEL_FILE_ROLE_COMPANION = 2,
    RAC_MODEL_FILE_ROLE_VISION_PROJECTOR = 3,
    RAC_MODEL_FILE_ROLE_TOKENIZER = 4,
    RAC_MODEL_FILE_ROLE_CONFIG = 5,
    RAC_MODEL_FILE_ROLE_VOCABULARY = 6,
    RAC_MODEL_FILE_ROLE_MERGES = 7,
    RAC_MODEL_FILE_ROLE_LABELS = 8
} rac_model_file_role_t;

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

    /** Semantic role for this file in the artifact */
    rac_model_file_role_t role;

    /**
     * Absolute download URL for this file (can be NULL when the caller
     * derives the URL by joining a base download URL with relative_path).
     * Preserved through proto serialization so registry round-trips do not
     * drop the URL set by SDK callers via registerMultiFileModel.
     */
    const char* url;

    /**
     * Exact expected size in bytes (0 = unknown). Preserved through registry
     * round-trips so completeness validation can reject partial files.
     */
    int64_t size_bytes;

    /**
     * Lowercase hex SHA-256 for this file (can be NULL). Preserved through
     * registry round-trips; recorded automatically for Hugging Face pulls.
     */
    const char* checksum_sha256;
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
    RAC_MODEL_CATEGORY_LANGUAGE = 0,                 /**< Text-to-text models (LLMs) */
    RAC_MODEL_CATEGORY_SPEECH_RECOGNITION = 1,       /**< Voice-to-text models (ASR/STT) */
    RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS = 2,         /**< Text-to-voice models (TTS) */
    RAC_MODEL_CATEGORY_VISION = 3,                   /**< Image understanding models */
    RAC_MODEL_CATEGORY_IMAGE_GENERATION = 4,         /**< Text-to-image models */
    RAC_MODEL_CATEGORY_MULTIMODAL = 5,               /**< Multi-modality models */
    RAC_MODEL_CATEGORY_AUDIO = 6,                    /**< Audio processing (diarization, etc.) */
    RAC_MODEL_CATEGORY_EMBEDDING = 7,                /**< Embedding models (RAG, semantic search) */
    RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION = 8, /**< VAD models (Silero, etc.) */
    RAC_MODEL_CATEGORY_UNKNOWN = 99                  /**< Unknown category */
} rac_model_category_t;

// =============================================================================
// MODEL FORMAT
// =============================================================================

/**
 * @brief Supported model file formats.
 * Values mirror runanywhere.v1.ModelFormat and RAC_MODEL_FORMAT_ID_*.
 */
typedef enum rac_model_format {
    RAC_MODEL_FORMAT_UNSPECIFIED = RAC_MODEL_FORMAT_ID_UNSPECIFIED,
    RAC_MODEL_FORMAT_GGUF = RAC_MODEL_FORMAT_ID_GGUF,               /**< GGUF format */
    RAC_MODEL_FORMAT_GGML = RAC_MODEL_FORMAT_ID_GGML,               /**< GGML format */
    RAC_MODEL_FORMAT_ONNX = RAC_MODEL_FORMAT_ID_ONNX,               /**< ONNX format */
    RAC_MODEL_FORMAT_ORT = RAC_MODEL_FORMAT_ID_ORT,                 /**< ONNX Runtime format */
    RAC_MODEL_FORMAT_BIN = RAC_MODEL_FORMAT_ID_BIN,                 /**< Binary format */
    RAC_MODEL_FORMAT_COREML = RAC_MODEL_FORMAT_ID_COREML,           /**< Core ML compiled format */
    RAC_MODEL_FORMAT_MLMODEL = RAC_MODEL_FORMAT_ID_MLMODEL,         /**< Core ML .mlmodel */
    RAC_MODEL_FORMAT_MLPACKAGE = RAC_MODEL_FORMAT_ID_MLPACKAGE,     /**< Core ML .mlpackage */
    RAC_MODEL_FORMAT_TFLITE = RAC_MODEL_FORMAT_ID_TFLITE,           /**< TensorFlow Lite */
    RAC_MODEL_FORMAT_SAFETENSORS = RAC_MODEL_FORMAT_ID_SAFETENSORS, /**< Safetensors */
    RAC_MODEL_FORMAT_QNN_CONTEXT = RAC_MODEL_FORMAT_ID_QNN_CONTEXT, /**< QNN context binary */
    RAC_MODEL_FORMAT_ZIP = RAC_MODEL_FORMAT_ID_ZIP,                 /**< Archive wrapping a model */
    RAC_MODEL_FORMAT_FOLDER = RAC_MODEL_FORMAT_ID_FOLDER,           /**< Folder-backed model */
    RAC_MODEL_FORMAT_PROPRIETARY = RAC_MODEL_FORMAT_ID_PROPRIETARY, /**< Built-in system model */
    RAC_MODEL_FORMAT_UNKNOWN = RAC_MODEL_FORMAT_ID_UNKNOWN          /**< Unknown format */
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
    RAC_FRAMEWORK_MLX = 7,               /**< MLX C++ (Apple Silicon VLM) */
    RAC_FRAMEWORK_COREML = 8,            /**< Core ML (Apple Neural Engine) */
    // Values 9-11 intentionally retired — leave the gaps stable.
    RAC_FRAMEWORK_SHERPA = 12,  /**< Sherpa-ONNX speech engine (STT/TTS/VAD/wakeword) */
    RAC_FRAMEWORK_QHEXRT = 13,  /**< QHexRT (Qualcomm Hexagon NPU runtime) */
    RAC_FRAMEWORK_UNKNOWN = 99  /**< Unknown framework */
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

    /** Whether model supports LoRA adapters */
    rac_bool_t supports_lora;

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
 * @brief Get the default inference framework for a model category.
 * Mirrors Swift's RAModelCategory.defaultFramework — the framework the SDK
 * falls back to when a category has no explicit model framework resolved
 * (e.g. a pending UI selection that has not yet matched a catalogued model).
 *
 * @param category Model category
 * @return RAC_FRAMEWORK_LLAMACPP for language/multimodal, RAC_FRAMEWORK_ONNX
 *         for speech recognition / synthesis / embedding / VAD, otherwise
 *         RAC_FRAMEWORK_UNKNOWN.
 */
RAC_API rac_inference_framework_t
rac_model_category_default_framework(rac_model_category_t category);

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

// =============================================================================
// CANONICAL WIRE-STRING / DISPLAY / ANALYTICS ACCESSORS
// =============================================================================
//
// Result-code-returning accessors that expose the canonical maps used by
// platform SDKs. The Swift typealiases over RAModelFormat / RAInferenceFramework
// previously hand-wrote ~400 LOC of switch tables to compute wireString,
// displayName, and analyticsKey strings and to parse string inputs back into
// enum values. These accessors centralize the source-of-truth in commons so
// the per-SDK switch tables can be deleted.
//
// Wire strings are the proto enum names (matches what swift-protobuf produces
// during JSON encoding): MODEL_FORMAT_GGUF, INFERENCE_FRAMEWORK_LLAMA_CPP, etc.
// Display names and analytics keys mirror the existing Swift tables in
// `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift`.
//
// All returned strings are statically allocated literals — callers MUST NOT
// free them.

/**
 * @brief Canonical wire string for a model format.
 *
 * Returns the proto enum name (e.g. "MODEL_FORMAT_GGUF") which matches what
 * swift-protobuf emits during JSON encoding/decoding. Unknown / unrecognized
 * values are mapped to "MODEL_FORMAT_UNKNOWN".
 *
 * @param f Model format
 * @param out Output: pointer to a statically-allocated literal. Caller must
 *            NOT free. Set to NULL on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_format_wire_string(rac_model_format_t f, const char** out);

/**
 * @brief Canonical wire string for an inference framework.
 *
 * Returns the proto enum name (e.g. "INFERENCE_FRAMEWORK_LLAMA_CPP") which
 * matches what swift-protobuf emits during JSON encoding/decoding. Unknown /
 * unrecognized values are mapped to "INFERENCE_FRAMEWORK_UNKNOWN".
 *
 * @param f Inference framework
 * @param out Output: pointer to a statically-allocated literal. Caller must
 *            NOT free. Set to NULL on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_inference_framework_wire_string(rac_inference_framework_t f,
                                                         const char** out);

/**
 * @brief Human-readable display name for an inference framework.
 *
 * Mirrors the Swift `InferenceFramework.displayName` table in
 * `ModelTypes.swift` (e.g. RAC_FRAMEWORK_LLAMACPP → "llama.cpp",
 * RAC_FRAMEWORK_FOUNDATION_MODELS → "Foundation Models"). Unknown values
 * yield "Unknown".
 *
 * @param f Inference framework
 * @param out Output: pointer to a statically-allocated literal. Caller must
 *            NOT free. Set to NULL on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_inference_framework_display_name(rac_inference_framework_t f,
                                                          const char** out);

/**
 * @brief Snake_case analytics key for an inference framework.
 *
 * Mirrors the Swift `InferenceFramework.analyticsKey` table in
 * `ModelTypes.swift` (e.g. RAC_FRAMEWORK_LLAMACPP → "llama_cpp",
 * RAC_FRAMEWORK_FOUNDATION_MODELS → "foundation_models"). Unknown values
 * yield "unknown".
 *
 * @param f Inference framework
 * @param out Output: pointer to a statically-allocated literal. Caller must
 *            NOT free. Set to NULL on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_inference_framework_analytics_key(rac_inference_framework_t f,
                                                           const char** out);

/**
 * @brief Parse an inference framework from a string.
 *
 * Mirrors Swift's `RAInferenceFramework.init?(caseInsensitive:)` — accepts
 * the canonical wire string, the analytics key, or the display name in any
 * letter case. Returns RAC_ERROR_NOT_FOUND when the string does not match
 * any known framework.
 *
 * @param s    Input string (NUL-terminated). Compared case-insensitively
 *             against wire_string / display_name / analytics_key for every
 *             known framework value.
 * @param out  Output: parsed inference framework. Set to RAC_FRAMEWORK_UNKNOWN
 *             on failure.
 * @return RAC_SUCCESS on match, RAC_ERROR_NOT_FOUND if no known framework
 *         matches, RAC_ERROR_NULL_POINTER if either argument is NULL.
 */
RAC_API rac_result_t rac_inference_framework_from_string(const char* s,
                                                         rac_inference_framework_t* out);

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

/**
 * @brief Check whether a file extension identifies a model file for the
 *        given inference framework.
 *
 * Canonical commons-owned replacement for the per-SDK `is_model_file`
 * callbacks (e.g. Swift's `racIsModelFile`, previously wired through a
 * platform discovery-callback struct). The mapping mirrors the
 * Swift reference table:
 *   - LLAMACPP             : .gguf, .bin
 *   - ONNX, SHERPA         : .onnx, .ort
 *   - COREML               : .mlmodelc, .mlpackage, .mlmodel
 *   - FOUNDATION_MODELS,
 *     SYSTEM_TTS           : (always RAC_TRUE — builtin:// models)
 *   - default              : .gguf, .onnx, .bin, .ort, .mlmodelc
 *
 * The extension may be passed with or without a leading dot
 * ("gguf" or ".gguf") and is matched case-insensitively.
 *
 * @param framework  Target inference framework
 * @param extension  File extension; may include leading dot. NULL is
 *                   treated as no extension (returns RAC_FALSE for
 *                   frameworks that require one).
 * @param out        Output: RAC_TRUE if the extension is a model file for
 *                   the framework, RAC_FALSE otherwise.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_format_for_framework(rac_inference_framework_t framework,
                                                    const char* extension, rac_bool_t* out);

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
 * @brief Derive a canonical model id from a URL by extension-stripping.
 *
 * Source-of-truth port of Swift's
 * `RunAnywhere.generateModelId(fromURL:)`
 * (`Public/Extensions/Storage/RunAnywhere+Storage.swift`). Used by every
 * platform SDK to derive a stable, cross-SDK model id from a download URL
 * when the caller did not supply one explicitly.
 *
 * Algorithm (byte-exact parity with Swift):
 *   1. Strip URL query string (`?...`) and fragment (`#...`).
 *   2. Take the trailing path component (everything after the last `/`).
 *      If the URL has no `/`, the whole URL is treated as the filename
 *      (matches Swift's `url.split("/").last ?? url` fallback).
 *   3. Iteratively strip a known archive/model extension (case-insensitive):
 *        `gz, bz2, tar, zip, gguf, onnx, ort, bin`.
 *      The loop continues so chained extensions like `.tar.gz` collapse to
 *      the bare base id.
 *
 * Caller-provided buffer (no malloc/free dance). Recommend at least 256 bytes.
 *
 * @param url       URL or filename (UTF-8). May be NULL → RAC_ERROR_NULL_POINTER.
 * @param out       Caller-provided output buffer. Always NUL-terminated on
 *                  success. Set to empty string on RAC_ERROR_BUFFER_TOO_SMALL
 *                  when @p out_size > 0.
 * @param out_size  Capacity of @p out in bytes (must be > 0). The derived id
 *                  plus its NUL terminator must fit, otherwise the function
 *                  returns RAC_ERROR_BUFFER_TOO_SMALL without truncating.
 *
 * @retval RAC_SUCCESS                Id written to @p out.
 * @retval RAC_ERROR_NULL_POINTER     @p url or @p out is NULL.
 * @retval RAC_ERROR_BUFFER_TOO_SMALL @p out_size is 0 or insufficient for the
 *                                    derived id + NUL terminator.
 */
RAC_API rac_result_t rac_model_id_from_url(const char* url, char* out, size_t out_size);

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

    /** Filter by format (RAC_MODEL_FORMAT_UNSPECIFIED or RAC_MODEL_FORMAT_UNKNOWN = any) */
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

// =============================================================================
// CANONICAL RAModelInfo FACTORY
// =============================================================================
//
// Commons-owned implementation of Swift's RAModelInfo.make(...). Consumes a
// serialized runanywhere.v1.ModelInfoMakeRequest and produces a fully
// populated runanywhere.v1.ModelInfo with 18 fields filled in:
//
//   id, name, category, format, framework, download_url, download_size_bytes,
//   context_length (with category-aware default 2048), supports_thinking
//   (gated by category), thinking_pattern (default <think>/</think> when
//   thinking is on), description, source, created_at_unix_ms,
//   updated_at_unix_ms, artifact (single_file or archive — inferred from URL),
//   artifact_type, expected_files, is_downloaded (probed via the platform
//   adapter's is_non_empty_directory or file_list_directory fallback).
//
// Field semantics mirror the Swift implementation in
//   sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/
//     ModelTypes+Artifacts.swift::RAModelInfo.make
// 1:1 so it can be deleted in P3-T3.

/**
 * @brief Build a fully-populated ModelInfo from a ModelInfoMakeRequest.
 *
 * Consumes serialized runanywhere.v1.ModelInfoMakeRequest bytes and returns
 * serialized runanywhere.v1.ModelInfo bytes in out_proto.
 *
 * Defaults applied:
 *   - id: rac_model_generate_id() applied to the URL.
 *   - name: request.name when non-empty, else rac_model_generate_name(url).
 *   - format: detected from URL extension (rac_model_detect_format_from_extension).
 *   - framework: request.framework when non-UNSPECIFIED, else
 *     rac_model_detect_framework_from_format(format).
 *   - category: request.category when non-UNSPECIFIED, else
 *     rac_model_category_from_framework(framework).
 *   - source: request.source when non-UNSPECIFIED, else MODEL_SOURCE_REMOTE.
 *   - context_length: 2048 when category requires context length, else 0.
 *   - supports_thinking: false (the make() entry sets the gating boolean
 *     from category; per-call thinking flag is not part of the request).
 *   - thinking_pattern: <think>/</think> when supports_thinking is true.
 *   - artifact: archive when ArchiveType.from(url) yields a known type
 *     (.zip / .tar.gz / .tgz / .tar.bz2 / .tbz2 / .tar.xz / .txz),
 *     else single_file.
 *   - artifact_type: matches the artifact branch (ZIP_ARCHIVE, TAR_GZ_ARCHIVE,
 *     TAR_BZ2_ARCHIVE, TAR_XZ_ARCHIVE, or SINGLE_FILE).
 *   - is_downloaded: false (no local_path is supplied via this make request;
 *     the disk probe runs only when local_path is non-empty, which the
 *     factory leaves empty by default).
 *
 * @param in_request_bytes Serialized ModelInfoMakeRequest bytes (may be empty).
 * @param in_request_size  Byte count.
 * @param out_proto Receives serialized runanywhere.v1.ModelInfo bytes on
 *                  success or an error status on failure.
 * @return RAC_SUCCESS on success, or a negative rac_result_t on encode/
 *         decode failure / NULL out pointer.
 */
RAC_API rac_result_t rac_model_info_make_proto(const uint8_t* in_request_bytes,
                                               size_t in_request_size,
                                               rac_proto_buffer_t* out_proto);

/**
 * @brief Probe whether a path is a directory containing at least one entry.
 *
 * Mirrors Swift's `FileOperationsUtilities.isNonEmptyDirectory(at:)`. Used
 * internally by rac_model_info_make_proto and exposed as a helper so SDK
 * callers can share the same probe semantics. NULL-safe.
 *
 * Uses the platform adapter in priority order:
 *   1. is_non_empty_directory callback when available.
 *   2. file_list_directory two-call enumeration (capacity query) when
 *      callback (1) is NULL — RAC_TRUE iff the directory contains at least
 *      one entry.
 *   3. RAC_FALSE when neither callback is set.
 *
 * @param path Absolute directory path (UTF-8). NULL or empty → RAC_FALSE.
 * @return RAC_TRUE if path is a non-empty directory, RAC_FALSE otherwise.
 */
RAC_API rac_bool_t rac_path_is_non_empty_directory(const char* path);

// =============================================================================
// CANONICAL ARTIFACT EXPECTED-FILES HELPER
// =============================================================================
//
// Commons-owned port of Swift's RAModelInfo.expectedArtifactFiles and the
// underlying RAModelInfo.OneOf_Artifact.expectedFiles computed property
// (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/
// ModelTypes+Artifacts.swift). The Swift logic walks the artifact `oneof`,
// preferring the artifact-attached `expected_files` manifest when present,
// then falling back to the `required_patterns`/`optional_patterns` shorthand,
// then synthesising a manifest from a `multi_file` descriptor list.
//
// Exposed as proto-byte ABI so platform SDKs can call it without rebuilding
// the C-struct mirror of `rac_model_artifact_info_t` from a serialized
// runanywhere.v1.ModelInfo. Output is the same `runanywhere.v1.ExpectedModelFiles`
// shape every SDK already consumes.

// =============================================================================
// PROTO ENUM ↔ C ENUM MAPPERS
// =============================================================================
//
// Bidirectional mappers between the proto-wire `int32` enum values declared in
// `idl/model_types.proto` and the corresponding `rac_*_t` C enum values.
//
// Background: Pre-IDL, every platform SDK hand-wrote a per-language switch
// table to convert between proto enum cases and the SDK's own enum
// representation. Most C enums in `rac_model_types.h` were defined long before
// the proto schema, so their numeric values DO NOT match the proto integers
// 1:1 (proto reserves 0 for UNSPECIFIED; some C enums skip UNSPECIFIED, others
// use 99 for UNKNOWN, etc.). These mappers centralize the translation so SDKs
// can call a single C ABI rather than re-implement the switch table per
// language.
//
// Mapping conventions:
//   - proto.UNSPECIFIED → C "UNKNOWN" (or first defined value when no UNKNOWN
//     exists). All mappers accept UNSPECIFIED as a valid input that round-trips
//     back to UNSPECIFIED via `_to_proto`.
//   - Unknown / out-of-range proto values → RAC_ERROR_INVALID_ARGUMENT.
//   - Unknown / out-of-range C values → RAC_ERROR_INVALID_ARGUMENT.
//   - NULL `out` → RAC_ERROR_NULL_POINTER.
//
// Note on `rac_model_format_t`: the C enum values are already 1:1 with
// `runanywhere.v1.ModelFormat` (via the shared `RAC_MODEL_FORMAT_ID_*`
// constants in `rac_model_format_ids.h`). The mapper is still provided for
// type safety so callers cannot accidentally mix `int32_t` proto values and
// `rac_model_format_t` values without going through a validated entry point.

/**
 * @brief Convert a proto `runanywhere.v1.InferenceFramework` int32 value to a
 *        `rac_inference_framework_t` value.
 *
 * @param proto_value Proto enum integer (0..23).
 * @param out         Output: parsed inference framework. Set to
 *                    RAC_FRAMEWORK_UNKNOWN on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_inference_framework_from_proto(int32_t proto_value,
                                                        rac_inference_framework_t* out);

/**
 * @brief Convert a `rac_inference_framework_t` value to the proto
 *        `runanywhere.v1.InferenceFramework` int32 value.
 *
 * @param value Inference framework.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_inference_framework_to_proto(rac_inference_framework_t value,
                                                      int32_t* out);

/**
 * @brief Convert a proto `runanywhere.v1.ModelCategory` int32 value to a
 *        `rac_model_category_t` value.
 *
 * @param proto_value Proto enum integer (0..9).
 * @param out         Output: parsed model category. Set to
 *                    RAC_MODEL_CATEGORY_UNKNOWN on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_category_from_proto(int32_t proto_value, rac_model_category_t* out);

/**
 * @brief Convert a `rac_model_category_t` value to the proto
 *        `runanywhere.v1.ModelCategory` int32 value.
 *
 * @param value Model category.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_category_to_proto(rac_model_category_t value, int32_t* out);

/**
 * @brief Convert a proto `runanywhere.v1.ModelFormat` int32 value to a
 *        `rac_model_format_t` value.
 *
 * Note: `rac_model_format_t` values are already 1:1 with the proto
 * integers via `RAC_MODEL_FORMAT_ID_*` so the mapping is the identity for
 * known values; this wrapper is provided for type safety / validation.
 *
 * @param proto_value Proto enum integer (0..15).
 * @param out         Output: parsed model format. Set to
 *                    RAC_MODEL_FORMAT_UNSPECIFIED on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_format_from_proto(int32_t proto_value, rac_model_format_t* out);

/**
 * @brief Convert a `rac_model_format_t` value to the proto
 *        `runanywhere.v1.ModelFormat` int32 value.
 *
 * @param value Model format.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_format_to_proto(rac_model_format_t value, int32_t* out);

/**
 * @brief Convert a proto `runanywhere.v1.ModelSource` int32 value to a
 *        `rac_model_source_t` value.
 *
 * Note: `rac_model_source_t` only has REMOTE and LOCAL today; proto's
 * BUILT_IN (=3) is mapped to RAC_MODEL_SOURCE_LOCAL to match commons'
 * Apple platform handling (built-in models are surfaced as local on the
 * C-struct path; the proto envelope keeps the original BUILT_IN value).
 *
 * @param proto_value Proto enum integer (0..3).
 * @param out         Output: parsed model source. Set to
 *                    RAC_MODEL_SOURCE_REMOTE on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_source_from_proto(int32_t proto_value, rac_model_source_t* out);

/**
 * @brief Convert a `rac_model_source_t` value to the proto
 *        `runanywhere.v1.ModelSource` int32 value.
 *
 * @param value Model source.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_model_source_to_proto(rac_model_source_t value, int32_t* out);

/**
 * @brief Convert a proto `runanywhere.v1.ArchiveType` int32 value to a
 *        `rac_archive_type_t` value.
 *
 * Note: proto's ARCHIVE_TYPE_UNSPECIFIED (=0) maps to the C
 * RAC_ARCHIVE_TYPE_NONE (=-1) which represents the "no archive / direct
 * file" sentinel.
 *
 * @param proto_value Proto enum integer (0..4).
 * @param out         Output: parsed archive type. Set to
 *                    RAC_ARCHIVE_TYPE_NONE on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_archive_type_from_proto(int32_t proto_value, rac_archive_type_t* out);

/**
 * @brief Convert a `rac_archive_type_t` value to the proto
 *        `runanywhere.v1.ArchiveType` int32 value.
 *
 * @param value Archive type.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_archive_type_to_proto(rac_archive_type_t value, int32_t* out);

/**
 * @brief Convert a proto `runanywhere.v1.ArchiveStructure` int32 value to a
 *        `rac_archive_structure_t` value.
 *
 * Note: proto's ARCHIVE_STRUCTURE_UNSPECIFIED (=0) maps to the C
 * RAC_ARCHIVE_STRUCTURE_UNKNOWN (=99) since both represent "no structure
 * information known". The remaining proto values 1..4 map 1:1 onto the
 * corresponding C structure enums.
 *
 * @param proto_value Proto enum integer (0..4).
 * @param out         Output: parsed archive structure. Set to
 *                    RAC_ARCHIVE_STRUCTURE_UNKNOWN on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the proto
 *         value is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_archive_structure_from_proto(int32_t proto_value,
                                                      rac_archive_structure_t* out);

/**
 * @brief Convert a `rac_archive_structure_t` value to the proto
 *        `runanywhere.v1.ArchiveStructure` int32 value.
 *
 * @param value Archive structure.
 * @param out   Output: proto enum integer. Set to 0 (UNSPECIFIED) on failure.
 * @return RAC_SUCCESS on success, RAC_ERROR_INVALID_ARGUMENT if the C value
 *         is unrecognized, RAC_ERROR_NULL_POINTER if `out` is NULL.
 */
RAC_API rac_result_t rac_archive_structure_to_proto(rac_archive_structure_t value, int32_t* out);

/**
 * @brief Compute the canonical ExpectedModelFiles manifest for a ModelInfo.
 *
 * Consumes serialized runanywhere.v1.ModelInfo bytes and returns serialized
 * runanywhere.v1.ExpectedModelFiles bytes in out_proto.
 *
 * Resolution order mirrors Swift's RAModelInfo.expectedArtifactFiles +
 * OneOf_Artifact.expectedFiles:
 *
 *   1. Top-level `model.expected_files` when present (Swift's
 *      `hasExpectedFiles` short-circuit).
 *   2. Per-artifact branch:
 *      - SINGLE_FILE: artifact.expected_files when present, else a manifest
 *        synthesized from artifact.required_patterns / optional_patterns.
 *      - ARCHIVE: artifact.expected_files when present, else a manifest
 *        synthesized from artifact.required_patterns / optional_patterns.
 *      - MULTI_FILE: an ExpectedModelFiles whose `files` field copies the
 *        artifact's ModelFileDescriptor list (the commons download planner
 *        only walks `model.expected_files.files` for per-descriptor
 *        downloads, so seeding it from the multi-file artifact ensures the
 *        per-file loop runs and every URL actually downloads).
 *      - Other (custom_strategy_id, built_in, no artifact set): empty
 *        manifest (matches Swift's `.none` fallback).
 *
 * On encode/decode failure the error envelope is set on out_proto via the
 * canonical rac_proto_buffer_set_error() convention.
 *
 * @param in_model_bytes Serialized runanywhere.v1.ModelInfo bytes (may be
 *                       empty — treated as a default-zeroed ModelInfo, which
 *                       yields an empty ExpectedModelFiles).
 * @param in_model_size  Byte count.
 * @param out_proto      Receives serialized runanywhere.v1.ExpectedModelFiles
 *                       bytes on success or an error status on failure.
 * @return RAC_SUCCESS on success, or a negative rac_result_t on
 *         encode/decode/null-pointer failure.
 */
RAC_API rac_result_t rac_artifact_expected_files_proto(const uint8_t* in_model_bytes,
                                                       size_t in_model_size,
                                                       rac_proto_buffer_t* out_proto);

// =============================================================================
// MODEL HEURISTICS — DERIVED FROM RAModelInfo
// =============================================================================
//
// Commons-owned accessors that derive cross-SDK display state from a
// serialized `runanywhere.v1.ModelInfo`. Centralizes the model-naming
// heuristics that examples-flutter, examples-ios, examples-android, and
// examples-react-native were each duplicating. Companion tool-call accessor lives in
// `rac/features/llm/rac_tool_calling.h` (`rac_tool_call_format_from_model_info_proto`).

/**
 * @brief Estimate the parameter count (in billions) of a model from its
 *        catalog metadata.
 *
 * Scans the `name` / `id` / `description` fields of the supplied ModelInfo
 * proto for canonical `<N>B` / `<N>M` size tokens (e.g. "1.2B", "350M",
 * "Qwen2.5 0.5B-Instruct"). The first token found wins and millions are
 * converted to billions (`<N>M` ⇒ `<N>/1000`). When no recognisable token is
 * present the helper reports a sentinel of -1.0f so callers can distinguish
 * "unknown" from "very small".
 *
 * @param model_info_proto_bytes Borrowed runanywhere.v1.ModelInfo bytes (may
 *                               be NULL when @p size is 0).
 * @param size                   Byte count of @p model_info_proto_bytes.
 * @param out_parameter_count_b  Output: parameter count in billions, or -1.0f
 *                               when no size token is found. Must not be NULL.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER when @p
 *         out_parameter_count_b is NULL, RAC_ERROR_DECODING_ERROR when the
 *         supplied bytes do not parse as runanywhere.v1.ModelInfo.
 */
RAC_API rac_result_t rac_model_info_parameter_count_b_proto(const uint8_t* model_info_proto_bytes,
                                                            size_t size,
                                                            float* out_parameter_count_b);

/**
 * @brief Decide whether a model qualifies as "small" (≤500M params) for
 *        cross-SDK reliability banners (e.g. Flutter B-FL-6-003 tool-calling
 *        banner that warns when small models attempt tool calls).
 *
 * Implementation: derives `parameter_count_b` via
 * @ref rac_model_info_parameter_count_b_proto and reports `RAC_TRUE` when the
 * value is in `(0, 1.0)` — covers the 350M, 360M, 500M, 0.3B, 0.5B, 0.6B
 * cases the reviewer enumerated while keeping LFM2-1.2B-Tool above the
 * threshold. Unknown parameter counts (sentinel -1.0f) report `RAC_FALSE` to
 * avoid spurious banners.
 *
 * @param model_info_proto_bytes Borrowed runanywhere.v1.ModelInfo bytes (may
 *                               be NULL when @p size is 0).
 * @param size                   Byte count of @p model_info_proto_bytes.
 * @param out_is_small           Output: RAC_TRUE when the model is below the
 *                               1.0B threshold, RAC_FALSE otherwise.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER when @p out_is_small
 *         is NULL, RAC_ERROR_DECODING_ERROR when the supplied bytes do not
 *         parse as runanywhere.v1.ModelInfo.
 */
RAC_API rac_result_t rac_model_info_is_small_model_proto(const uint8_t* model_info_proto_bytes,
                                                         size_t size, rac_bool_t* out_is_small);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_TYPES_H */
