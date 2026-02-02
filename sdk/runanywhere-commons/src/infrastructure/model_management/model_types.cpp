/**
 * @file model_types.cpp
 * @brief Model Types Implementation
 *
 * C port of Swift's model type helper functions.
 * Swift Source: ModelCategory.swift, ModelFormat.swift, ModelArtifactType.swift,
 * InferenceFramework.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// =============================================================================
// ARCHIVE TYPE FUNCTIONS
// =============================================================================

const char* rac_archive_type_extension(rac_archive_type_t type) {
    switch (type) {
        case RAC_ARCHIVE_TYPE_ZIP:
            return "zip";
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            return "tar.bz2";
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            return "tar.gz";
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            return "tar.xz";
        default:
            return "unknown";
    }
}

rac_bool_t rac_archive_type_from_path(const char* url_path, rac_archive_type_t* out_type) {
    if (!url_path || !out_type) {
        return RAC_FALSE;
    }

    // Convert to lowercase for comparison
    std::string path(url_path);
    std::transform(path.begin(), path.end(), path.begin(), ::tolower);

    // Check suffixes (mirrors Swift's ArchiveType.from(url:))
    if (path.rfind(".tar.bz2") != std::string::npos || path.rfind(".tbz2") != std::string::npos) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_BZ2;
        return RAC_TRUE;
    }
    if (path.rfind(".tar.gz") != std::string::npos || path.rfind(".tgz") != std::string::npos) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_GZ;
        return RAC_TRUE;
    }
    if (path.rfind(".tar.xz") != std::string::npos || path.rfind(".txz") != std::string::npos) {
        *out_type = RAC_ARCHIVE_TYPE_TAR_XZ;
        return RAC_TRUE;
    }
    if (path.rfind(".zip") != std::string::npos) {
        *out_type = RAC_ARCHIVE_TYPE_ZIP;
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

// =============================================================================
// MODEL CATEGORY FUNCTIONS
// =============================================================================

rac_bool_t rac_model_category_requires_context_length(rac_model_category_t category) {
    // Mirrors Swift's ModelCategory.requiresContextLength
    switch (category) {
        case RAC_MODEL_CATEGORY_LANGUAGE:
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_model_category_supports_thinking(rac_model_category_t category) {
    // Mirrors Swift's ModelCategory.supportsThinking
    switch (category) {
        case RAC_MODEL_CATEGORY_LANGUAGE:
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

rac_model_category_t rac_model_category_from_framework(rac_inference_framework_t framework) {
    // Mirrors Swift's ModelCategory.from(framework:)
    switch (framework) {
        case RAC_FRAMEWORK_LLAMACPP:
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return RAC_MODEL_CATEGORY_LANGUAGE;
        case RAC_FRAMEWORK_ONNX:
            return RAC_MODEL_CATEGORY_MULTIMODAL;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return RAC_MODEL_CATEGORY_AUDIO;
        default:
            return RAC_MODEL_CATEGORY_AUDIO;
    }
}

// =============================================================================
// INFERENCE FRAMEWORK FUNCTIONS
// =============================================================================

rac_result_t rac_framework_get_supported_formats(rac_inference_framework_t framework,
                                                 rac_model_format_t** out_formats,
                                                 size_t* out_count) {
    if (!out_formats || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Mirrors Swift's InferenceFramework.supportedFormats
    switch (framework) {
        case RAC_FRAMEWORK_ONNX: {
            *out_count = 2;
            *out_formats = (rac_model_format_t*)malloc(2 * sizeof(rac_model_format_t));
            if (!*out_formats)
                return RAC_ERROR_OUT_OF_MEMORY;
            (*out_formats)[0] = RAC_MODEL_FORMAT_ONNX;
            (*out_formats)[1] = RAC_MODEL_FORMAT_ORT;
            return RAC_SUCCESS;
        }
        case RAC_FRAMEWORK_LLAMACPP: {
            *out_count = 1;
            *out_formats = (rac_model_format_t*)malloc(sizeof(rac_model_format_t));
            if (!*out_formats)
                return RAC_ERROR_OUT_OF_MEMORY;
            (*out_formats)[0] = RAC_MODEL_FORMAT_GGUF;
            return RAC_SUCCESS;
        }
        case RAC_FRAMEWORK_FLUID_AUDIO: {
            *out_count = 1;
            *out_formats = (rac_model_format_t*)malloc(sizeof(rac_model_format_t));
            if (!*out_formats)
                return RAC_ERROR_OUT_OF_MEMORY;
            (*out_formats)[0] = RAC_MODEL_FORMAT_BIN;
            return RAC_SUCCESS;
        }
        default:
            *out_count = 0;
            *out_formats = nullptr;
            return RAC_SUCCESS;
    }
}

rac_bool_t rac_framework_supports_format(rac_inference_framework_t framework,
                                         rac_model_format_t format) {
    // Mirrors Swift's InferenceFramework.supports(format:)
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return (format == RAC_MODEL_FORMAT_ONNX || format == RAC_MODEL_FORMAT_ORT) ? RAC_TRUE
                                                                                       : RAC_FALSE;
        case RAC_FRAMEWORK_LLAMACPP:
            return (format == RAC_MODEL_FORMAT_GGUF) ? RAC_TRUE : RAC_FALSE;
        case RAC_FRAMEWORK_COREML:
            return (format == RAC_MODEL_FORMAT_COREML) ? RAC_TRUE : RAC_FALSE;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return (format == RAC_MODEL_FORMAT_BIN) ? RAC_TRUE : RAC_FALSE;
        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_framework_uses_directory_based_models(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.usesDirectoryBasedModels
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
        case RAC_FRAMEWORK_COREML:  // CoreML compiled models (.mlmodelc) are directories
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_framework_supports_llm(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.supportsLLM
    switch (framework) {
        case RAC_FRAMEWORK_LLAMACPP:
        case RAC_FRAMEWORK_ONNX:
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_framework_supports_stt(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.supportsSTT
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_framework_supports_tts(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.supportsTTS
    switch (framework) {
        case RAC_FRAMEWORK_SYSTEM_TTS:
        case RAC_FRAMEWORK_ONNX:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

const char* rac_framework_display_name(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.displayName
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return "ONNX Runtime";
        case RAC_FRAMEWORK_LLAMACPP:
            return "llama.cpp";
        case RAC_FRAMEWORK_COREML:
            return "Core ML";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "Foundation Models";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "System TTS";
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return "FluidAudio";
        case RAC_FRAMEWORK_BUILTIN:
            return "Built-in";
        case RAC_FRAMEWORK_NONE:
            return "None";
        case RAC_FRAMEWORK_UNKNOWN:
            return "Unknown";
        default:
            return "Unknown";
    }
}

const char* rac_framework_analytics_key(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.analyticsKey
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return "onnx";
        case RAC_FRAMEWORK_LLAMACPP:
            return "llama_cpp";
        case RAC_FRAMEWORK_COREML:
            return "coreml";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "foundation_models";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "system_tts";
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return "fluid_audio";
        case RAC_FRAMEWORK_BUILTIN:
            return "built_in";
        case RAC_FRAMEWORK_NONE:
            return "none";
        case RAC_FRAMEWORK_UNKNOWN:
            return "unknown";
        default:
            return "unknown";
    }
}

// =============================================================================
// ARTIFACT FUNCTIONS
// =============================================================================

rac_bool_t rac_artifact_requires_extraction(const rac_model_artifact_info_t* artifact) {
    if (!artifact)
        return RAC_FALSE;
    // Mirrors Swift's ModelArtifactType.requiresExtraction
    return (artifact->kind == RAC_ARTIFACT_KIND_ARCHIVE) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_artifact_requires_download(const rac_model_artifact_info_t* artifact) {
    if (!artifact)
        return RAC_FALSE;
    // Mirrors Swift's ModelArtifactType.requiresDownload
    return (artifact->kind == RAC_ARTIFACT_KIND_BUILT_IN) ? RAC_FALSE : RAC_TRUE;
}

rac_result_t rac_artifact_infer_from_url(const char* url, rac_model_format_t format,
                                         rac_model_artifact_info_t* out_artifact) {
    (void)format;  // Currently unused but matches Swift signature

    if (!out_artifact) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize to defaults
    memset(out_artifact, 0, sizeof(rac_model_artifact_info_t));

    if (!url) {
        out_artifact->kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
        return RAC_SUCCESS;
    }

    // Check if URL indicates an archive
    rac_archive_type_t archive_type =
        RAC_ARCHIVE_TYPE_ZIP;  // Default value, will be set by function
    if (rac_archive_type_from_path(url, &archive_type) == RAC_TRUE) {
        out_artifact->kind = RAC_ARTIFACT_KIND_ARCHIVE;
        out_artifact->archive_type = archive_type;
        out_artifact->archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
        return RAC_SUCCESS;
    }

    // Default to single file
    out_artifact->kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
    return RAC_SUCCESS;
}

rac_bool_t rac_model_info_is_downloaded(const rac_model_info_t* model) {
    if (!model)
        return RAC_FALSE;
    // Mirrors Swift's ModelInfo.isDownloaded
    return (model->local_path && strlen(model->local_path) > 0) ? RAC_TRUE : RAC_FALSE;
}

// =============================================================================
// FORMAT DETECTION - Ported from Swift RegistryService.swift
// =============================================================================

rac_bool_t rac_model_detect_format_from_extension(const char* extension,
                                                  rac_model_format_t* out_format) {
    if (!extension || !out_format) {
        return RAC_FALSE;
    }

    // Convert to lowercase for comparison
    std::string ext(extension);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    // Ported from Swift RegistryService.detectFormatFromExtension() (lines 330-338)
    if (ext == "onnx") {
        *out_format = RAC_MODEL_FORMAT_ONNX;
        return RAC_TRUE;
    }
    if (ext == "ort") {
        *out_format = RAC_MODEL_FORMAT_ORT;
        return RAC_TRUE;
    }
    if (ext == "gguf") {
        *out_format = RAC_MODEL_FORMAT_GGUF;
        return RAC_TRUE;
    }
    if (ext == "bin") {
        *out_format = RAC_MODEL_FORMAT_BIN;
        return RAC_TRUE;
    }

    return RAC_FALSE;
}

rac_bool_t rac_model_detect_framework_from_format(rac_model_format_t format,
                                                  rac_inference_framework_t* out_framework) {
    if (!out_framework) {
        return RAC_FALSE;
    }

    // Ported from Swift RegistryService.detectFramework(for:) (lines 340-343)
    // Uses InferenceFramework.framework(for:) which checks supported formats
    switch (format) {
        case RAC_MODEL_FORMAT_ONNX:
        case RAC_MODEL_FORMAT_ORT:
            *out_framework = RAC_FRAMEWORK_ONNX;
            return RAC_TRUE;
        case RAC_MODEL_FORMAT_GGUF:
            *out_framework = RAC_FRAMEWORK_LLAMACPP;
            return RAC_TRUE;
        case RAC_MODEL_FORMAT_BIN:
            *out_framework = RAC_FRAMEWORK_FLUID_AUDIO;
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

const char* rac_model_format_extension(rac_model_format_t format) {
    // Mirrors Swift's ModelFormat.fileExtension
    switch (format) {
        case RAC_MODEL_FORMAT_ONNX:
            return "onnx";
        case RAC_MODEL_FORMAT_ORT:
            return "ort";
        case RAC_MODEL_FORMAT_GGUF:
            return "gguf";
        case RAC_MODEL_FORMAT_BIN:
            return "bin";
        default:
            return nullptr;
    }
}

// =============================================================================
// MODEL ID/NAME GENERATION - Ported from Swift RegistryService.swift
// =============================================================================

void rac_model_generate_id(const char* url, char* out_id, size_t max_len) {
    // Ported from Swift RegistryService.generateModelId(from:) (lines 311-318)
    if (!url || !out_id || max_len == 0) {
        if (out_id && max_len > 0) {
            out_id[0] = '\0';
        }
        return;
    }

    // Get last path component (filename)
    std::string path(url);
    size_t last_slash = path.rfind('/');
    std::string filename = (last_slash != std::string::npos) ? path.substr(last_slash + 1) : path;

    // Known extensions to strip (from Swift lines 313)
    const char* known_extensions[] = {"gz", "bz2", "tar", "zip", "gguf", "onnx", "ort", "bin"};

    // Strip known extensions from the end (Swift lines 314-316)
    bool found = true;
    while (found && !filename.empty()) {
        found = false;
        size_t dot_pos = filename.rfind('.');
        if (dot_pos != std::string::npos && dot_pos < filename.size() - 1) {
            std::string ext = filename.substr(dot_pos + 1);
            std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

            for (const auto& known_extension : known_extensions) {
                if (ext == known_extension) {
                    filename = filename.substr(0, dot_pos);
                    found = true;
                    break;
                }
            }
        }
    }

    // Copy result to output buffer
    size_t copy_len = std::min(filename.size(), max_len - 1);
    memcpy(out_id, filename.c_str(), copy_len);
    out_id[copy_len] = '\0';
}

void rac_model_generate_name(const char* url, char* out_name, size_t max_len) {
    // Ported from Swift RegistryService.generateModelName(from:) (lines 320-324)
    if (!url || !out_name || max_len == 0) {
        if (out_name && max_len > 0) {
            out_name[0] = '\0';
        }
        return;
    }

    // Get last path component and strip single extension (Swift's deletingPathExtension())
    std::string path(url);
    size_t last_slash = path.rfind('/');
    std::string filename = (last_slash != std::string::npos) ? path.substr(last_slash + 1) : path;

    // Delete path extension (last .xxx)
    size_t dot_pos = filename.rfind('.');
    if (dot_pos != std::string::npos) {
        filename = filename.substr(0, dot_pos);
    }

    // Replace underscores and dashes with spaces (Swift lines 322-323)
    for (size_t i = 0; i < filename.size(); i++) {
        if (filename[i] == '_' || filename[i] == '-') {
            filename[i] = ' ';
        }
    }

    // Copy result to output buffer
    size_t copy_len = std::min(filename.size(), max_len - 1);
    memcpy(out_name, filename.c_str(), copy_len);
    out_name[copy_len] = '\0';
}

// =============================================================================
// MODEL FILTERING - Ported from Swift RegistryService.swift
// =============================================================================

// Helper to check if string contains substring (case-insensitive)
static bool contains_case_insensitive(const char* haystack, const char* needle) {
    if (!haystack || !needle)
        return false;

    std::string h(haystack);
    std::string n(needle);
    std::transform(h.begin(), h.end(), h.begin(), ::tolower);
    std::transform(n.begin(), n.end(), n.begin(), ::tolower);

    return h.find(n) != std::string::npos;
}

rac_bool_t rac_model_matches_filter(const rac_model_info_t* model,
                                    const rac_model_filter_t* filter) {
    // Ported from Swift RegistryService.filterModels(by:) filter closure (lines 106-124)
    if (!model) {
        return RAC_FALSE;
    }

    // No filter = matches all
    if (!filter) {
        return RAC_TRUE;
    }

    // Framework filter (Swift lines 107-109)
    if (filter->framework != RAC_FRAMEWORK_UNKNOWN && model->framework != filter->framework) {
        return RAC_FALSE;
    }

    // Format filter (Swift lines 110-112)
    if (filter->format != RAC_MODEL_FORMAT_UNKNOWN && model->format != filter->format) {
        return RAC_FALSE;
    }

    // Max size filter (Swift lines 113-115)
    if (filter->max_size > 0 && model->download_size > 0 &&
        model->download_size > filter->max_size) {
        return RAC_FALSE;
    }

    // Search query filter (Swift lines 116-122)
    if (filter->search_query && strlen(filter->search_query) > 0) {
        bool matches = contains_case_insensitive(model->name, filter->search_query) ||
                       contains_case_insensitive(model->id, filter->search_query) ||
                       contains_case_insensitive(model->description, filter->search_query);
        if (!matches) {
            return RAC_FALSE;
        }
    }

    return RAC_TRUE;
}

size_t rac_model_filter_models(const rac_model_info_t* models, size_t models_count,
                               const rac_model_filter_t* filter, rac_model_info_t* out_models,
                               size_t out_capacity) {
    // Ported from Swift RegistryService.filterModels(by:) (lines 104-126)
    if (!models || models_count == 0) {
        return 0;
    }

    size_t matched_count = 0;

    for (size_t i = 0; i < models_count; i++) {
        if (rac_model_matches_filter(&models[i], filter) == RAC_TRUE) {
            // Copy to output if we have space
            if (out_models && matched_count < out_capacity) {
                out_models[matched_count] = models[i];
            }
            matched_count++;
        }
    }

    return matched_count;
}

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

rac_expected_model_files_t* rac_expected_model_files_alloc(void) {
    auto* files = (rac_expected_model_files_t*)calloc(1, sizeof(rac_expected_model_files_t));
    return files;
}

void rac_expected_model_files_free(rac_expected_model_files_t* files) {
    if (!files)
        return;

    if (files->required_patterns) {
        for (size_t i = 0; i < files->required_pattern_count; i++) {
            free((void*)files->required_patterns[i]);
        }
        free((void*)files->required_patterns);
    }

    if (files->optional_patterns) {
        for (size_t i = 0; i < files->optional_pattern_count; i++) {
            free((void*)files->optional_patterns[i]);
        }
        free((void*)files->optional_patterns);
    }

    free((void*)files->description);
    free(files);
}

rac_model_file_descriptor_t* rac_model_file_descriptors_alloc(size_t count) {
    if (count == 0)
        return nullptr;
    return (rac_model_file_descriptor_t*)calloc(count, sizeof(rac_model_file_descriptor_t));
}

void rac_model_file_descriptors_free(rac_model_file_descriptor_t* descriptors, size_t count) {
    if (!descriptors)
        return;
    for (size_t i = 0; i < count; i++) {
        free((void*)descriptors[i].relative_path);
        free((void*)descriptors[i].destination_path);
    }
    free(descriptors);
}

rac_model_info_t* rac_model_info_alloc(void) {
    return (rac_model_info_t*)calloc(1, sizeof(rac_model_info_t));
}

void rac_model_info_free(rac_model_info_t* model) {
    if (!model)
        return;

    free(model->id);
    free(model->name);
    free(model->download_url);
    free(model->local_path);
    free(model->description);

    // Free artifact info
    if (model->artifact_info.expected_files) {
        rac_expected_model_files_free(model->artifact_info.expected_files);
    }
    if (model->artifact_info.file_descriptors) {
        rac_model_file_descriptors_free(model->artifact_info.file_descriptors,
                                        model->artifact_info.file_descriptor_count);
    }
    free((void*)model->artifact_info.strategy_id);

    // Free tags
    if (model->tags) {
        for (size_t i = 0; i < model->tag_count; i++) {
            free(model->tags[i]);
        }
        free(model->tags);
    }

    free(model);
}

void rac_model_info_array_free(rac_model_info_t** models, size_t count) {
    if (!models)
        return;
    for (size_t i = 0; i < count; i++) {
        rac_model_info_free(models[i]);
    }
    free(models);
}

rac_model_info_t* rac_model_info_copy(const rac_model_info_t* model) {
    if (!model)
        return nullptr;

    rac_model_info_t* copy = rac_model_info_alloc();
    if (!copy)
        return nullptr;

    // Copy scalar fields
    copy->category = model->category;
    copy->format = model->format;
    copy->framework = model->framework;
    copy->download_size = model->download_size;
    copy->memory_required = model->memory_required;
    copy->context_length = model->context_length;
    copy->supports_thinking = model->supports_thinking;
    copy->source = model->source;
    copy->created_at = model->created_at;
    copy->updated_at = model->updated_at;
    copy->last_used = model->last_used;
    copy->usage_count = model->usage_count;

    // Copy strings
    copy->id = rac_strdup(model->id);
    copy->name = rac_strdup(model->name);
    copy->download_url = rac_strdup(model->download_url);
    copy->local_path = rac_strdup(model->local_path);
    copy->description = rac_strdup(model->description);

    // Copy artifact info (shallow for now - TODO: deep copy if needed)
    copy->artifact_info = model->artifact_info;
    copy->artifact_info.expected_files = nullptr;
    copy->artifact_info.file_descriptors = nullptr;
    copy->artifact_info.strategy_id = rac_strdup(model->artifact_info.strategy_id);

    // Copy tags
    if (model->tags && model->tag_count > 0) {
        copy->tags = (char**)malloc(model->tag_count * sizeof(char*));
        if (copy->tags) {
            copy->tag_count = model->tag_count;
            for (size_t i = 0; i < model->tag_count; i++) {
                copy->tags[i] = rac_strdup(model->tags[i]);
            }
        }
    }

    return copy;
}
