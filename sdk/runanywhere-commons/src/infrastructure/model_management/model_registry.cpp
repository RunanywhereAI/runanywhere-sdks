/**
 * @file model_registry.cpp
 * @brief RunAnywhere Commons - Model Registry Implementation
 *
 * C++ port of Swift's ModelInfoService.
 * Swift Source: Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelInfoService.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 *
 * This is an in-memory model metadata store.
 */

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <map>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_model_registry {
    // Model storage (model_id -> model_info)
    std::map<std::string, rac_model_info_t*> models;

#ifdef RAC_HAVE_PROTOBUF
    // Optional proto-native snapshots preserve fields not represented by the
    // legacy C struct while existing struct-based call sites are migrated.
    std::map<std::string, std::string> model_proto_bytes;
#endif

    // Thread safety
    std::mutex mutex;
};

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

static rac_model_info_t* deep_copy_model(const rac_model_info_t* src) {
    if (!src)
        return nullptr;

    rac_model_info_t* copy = static_cast<rac_model_info_t*>(calloc(1, sizeof(rac_model_info_t)));
    if (!copy)
        return nullptr;

    copy->id = rac_strdup(src->id);
    copy->name = rac_strdup(src->name);
    copy->category = src->category;
    copy->format = src->format;
    copy->framework = src->framework;
    copy->download_url = rac_strdup(src->download_url);
    copy->local_path = rac_strdup(src->local_path);
    // Copy artifact info struct (shallow copy for basic fields, deep copy for pointers)
    copy->artifact_info.kind = src->artifact_info.kind;
    copy->artifact_info.archive_type = src->artifact_info.archive_type;
    copy->artifact_info.archive_structure = src->artifact_info.archive_structure;
    copy->artifact_info.expected_files = nullptr;  // Complex structure, leave null for now
    copy->artifact_info.file_descriptors = nullptr;
    copy->artifact_info.file_descriptor_count = 0;
    copy->artifact_info.strategy_id = rac_strdup(src->artifact_info.strategy_id);
    copy->download_size = src->download_size;
    copy->memory_required = src->memory_required;
    copy->context_length = src->context_length;
    copy->supports_thinking = src->supports_thinking;
    copy->supports_lora = src->supports_lora;

    // Copy tags
    if (src->tags && src->tag_count > 0) {
        copy->tags = static_cast<char**>(malloc(sizeof(char*) * src->tag_count));
        if (copy->tags) {
            for (size_t i = 0; i < src->tag_count; ++i) {
                copy->tags[i] = rac_strdup(src->tags[i]);
            }
            copy->tag_count = src->tag_count;
        }
    }

    copy->description = rac_strdup(src->description);
    copy->source = src->source;
    copy->created_at = src->created_at;
    copy->updated_at = src->updated_at;
    copy->last_used = src->last_used;
    copy->usage_count = src->usage_count;

    return copy;
}

static void free_model_info(rac_model_info_t* model) {
    if (!model)
        return;

    if (model->id)
        free(model->id);
    if (model->name)
        free(model->name);
    if (model->download_url)
        free(model->download_url);
    if (model->local_path)
        free(model->local_path);
    if (model->description)
        free(model->description);

    // Free artifact info strings
    if (model->artifact_info.strategy_id) {
        free(const_cast<char*>(model->artifact_info.strategy_id));
    }

    if (model->tags) {
        for (size_t i = 0; i < model->tag_count; ++i) {
            if (model->tags[i])
                free(model->tags[i]);
        }
        free(model->tags);
    }

    free(model);
}

#ifdef RAC_HAVE_PROTOBUF

namespace {

using runanywhere::v1::ArchiveArtifact;
using runanywhere::v1::ArchiveStructure;
using runanywhere::v1::ArchiveType;
using runanywhere::v1::InferenceFramework;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::ModelFileDescriptor;
using runanywhere::v1::ModelFormat;
using runanywhere::v1::ModelInfo;
using runanywhere::v1::ModelInfoList;
using runanywhere::v1::ModelQuery;
using runanywhere::v1::ModelQuerySortField;
using runanywhere::v1::ModelSource;
using runanywhere::v1::MultiFileArtifact;
using runanywhere::v1::SingleFileArtifact;

static ModelCategory model_category_to_proto(rac_model_category_t category) {
    switch (category) {
        case RAC_MODEL_CATEGORY_LANGUAGE:
            return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
        case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
        case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case RAC_MODEL_CATEGORY_VISION:
            return runanywhere::v1::MODEL_CATEGORY_VISION;
        case RAC_MODEL_CATEGORY_IMAGE_GENERATION:
            return runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION;
        case RAC_MODEL_CATEGORY_MULTIMODAL:
            return runanywhere::v1::MODEL_CATEGORY_MULTIMODAL;
        case RAC_MODEL_CATEGORY_AUDIO:
            return runanywhere::v1::MODEL_CATEGORY_AUDIO;
        case RAC_MODEL_CATEGORY_EMBEDDING:
            return runanywhere::v1::MODEL_CATEGORY_EMBEDDING;
        case RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
        case RAC_MODEL_CATEGORY_UNKNOWN:
        default:
            return runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
    }
}

static rac_model_category_t model_category_from_proto(ModelCategory category) {
    switch (category) {
        case runanywhere::v1::MODEL_CATEGORY_LANGUAGE:
            return RAC_MODEL_CATEGORY_LANGUAGE;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case runanywhere::v1::MODEL_CATEGORY_VISION:
            return RAC_MODEL_CATEGORY_VISION;
        case runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION:
            return RAC_MODEL_CATEGORY_IMAGE_GENERATION;
        case runanywhere::v1::MODEL_CATEGORY_MULTIMODAL:
            return RAC_MODEL_CATEGORY_MULTIMODAL;
        case runanywhere::v1::MODEL_CATEGORY_AUDIO:
            return RAC_MODEL_CATEGORY_AUDIO;
        case runanywhere::v1::MODEL_CATEGORY_EMBEDDING:
            return RAC_MODEL_CATEGORY_EMBEDDING;
        case runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
        case runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED:
        default:
            return RAC_MODEL_CATEGORY_UNKNOWN;
    }
}

static ModelFormat model_format_to_proto(rac_model_format_t format) {
    switch (format) {
        case RAC_MODEL_FORMAT_ONNX:
            return runanywhere::v1::MODEL_FORMAT_ONNX;
        case RAC_MODEL_FORMAT_ORT:
            return runanywhere::v1::MODEL_FORMAT_ORT;
        case RAC_MODEL_FORMAT_GGUF:
            return runanywhere::v1::MODEL_FORMAT_GGUF;
        case RAC_MODEL_FORMAT_BIN:
            return runanywhere::v1::MODEL_FORMAT_BIN;
        case RAC_MODEL_FORMAT_COREML:
            return runanywhere::v1::MODEL_FORMAT_COREML;
        case RAC_MODEL_FORMAT_QNN_CONTEXT:
            return runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT;
        case RAC_MODEL_FORMAT_UNKNOWN:
        default:
            return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
    }
}

static rac_model_format_t model_format_from_proto(ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_ONNX:
            return RAC_MODEL_FORMAT_ONNX;
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return RAC_MODEL_FORMAT_ORT;
        case runanywhere::v1::MODEL_FORMAT_GGUF:
            return RAC_MODEL_FORMAT_GGUF;
        case runanywhere::v1::MODEL_FORMAT_BIN:
            return RAC_MODEL_FORMAT_BIN;
        case runanywhere::v1::MODEL_FORMAT_COREML:
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return RAC_MODEL_FORMAT_COREML;
        case runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT:
            return RAC_MODEL_FORMAT_QNN_CONTEXT;
        case runanywhere::v1::MODEL_FORMAT_UNSPECIFIED:
        case runanywhere::v1::MODEL_FORMAT_GGML:
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
        case runanywhere::v1::MODEL_FORMAT_SAFETENSORS:
        case runanywhere::v1::MODEL_FORMAT_ZIP:
        case runanywhere::v1::MODEL_FORMAT_FOLDER:
        case runanywhere::v1::MODEL_FORMAT_PROPRIETARY:
        case runanywhere::v1::MODEL_FORMAT_UNKNOWN:
        default:
            return RAC_MODEL_FORMAT_UNKNOWN;
    }
}

static InferenceFramework inference_framework_to_proto(rac_inference_framework_t framework) {
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case RAC_FRAMEWORK_LLAMACPP:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
        case RAC_FRAMEWORK_BUILTIN:
            return runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN;
        case RAC_FRAMEWORK_NONE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_NONE;
        case RAC_FRAMEWORK_MLX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
        case RAC_FRAMEWORK_COREML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        case RAC_FRAMEWORK_WHISPERKIT_COREML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_WHISPERKIT_COREML;
        case RAC_FRAMEWORK_METALRT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_METALRT;
        case RAC_FRAMEWORK_GENIE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
        case RAC_FRAMEWORK_SHERPA:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
        case RAC_FRAMEWORK_UNKNOWN:
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

static rac_inference_framework_t inference_framework_from_proto(
    InferenceFramework framework) {
    switch (framework) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            return RAC_FRAMEWORK_ONNX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return RAC_FRAMEWORK_LLAMACPP;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return RAC_FRAMEWORK_FOUNDATION_MODELS;
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return RAC_FRAMEWORK_SYSTEM_TTS;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
            return RAC_FRAMEWORK_FLUID_AUDIO;
        case runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN:
            return RAC_FRAMEWORK_BUILTIN;
        case runanywhere::v1::INFERENCE_FRAMEWORK_NONE:
            return RAC_FRAMEWORK_NONE;
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLX:
            return RAC_FRAMEWORK_MLX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
            return RAC_FRAMEWORK_COREML;
        case runanywhere::v1::INFERENCE_FRAMEWORK_WHISPERKIT_COREML:
            return RAC_FRAMEWORK_WHISPERKIT_COREML;
        case runanywhere::v1::INFERENCE_FRAMEWORK_METALRT:
            return RAC_FRAMEWORK_METALRT;
        case runanywhere::v1::INFERENCE_FRAMEWORK_GENIE:
            return RAC_FRAMEWORK_GENIE;
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return RAC_FRAMEWORK_SHERPA;
        case runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED:
        default:
            return RAC_FRAMEWORK_UNKNOWN;
    }
}

static ModelSource model_source_to_proto(rac_model_source_t source) {
    switch (source) {
        case RAC_MODEL_SOURCE_LOCAL:
            return runanywhere::v1::MODEL_SOURCE_LOCAL;
        case RAC_MODEL_SOURCE_REMOTE:
        default:
            return runanywhere::v1::MODEL_SOURCE_REMOTE;
    }
}

static rac_model_source_t model_source_from_proto(ModelSource source) {
    switch (source) {
        case runanywhere::v1::MODEL_SOURCE_LOCAL:
            return RAC_MODEL_SOURCE_LOCAL;
        case runanywhere::v1::MODEL_SOURCE_REMOTE:
        case runanywhere::v1::MODEL_SOURCE_UNSPECIFIED:
        default:
            return RAC_MODEL_SOURCE_REMOTE;
    }
}

static ArchiveType archive_type_to_proto(rac_archive_type_t type) {
    switch (type) {
        case RAC_ARCHIVE_TYPE_ZIP:
            return runanywhere::v1::ARCHIVE_TYPE_ZIP;
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_BZ2;
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_GZ;
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            return runanywhere::v1::ARCHIVE_TYPE_TAR_XZ;
        case RAC_ARCHIVE_TYPE_NONE:
        default:
            return runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED;
    }
}

static rac_archive_type_t archive_type_from_proto(ArchiveType type) {
    switch (type) {
        case runanywhere::v1::ARCHIVE_TYPE_ZIP:
            return RAC_ARCHIVE_TYPE_ZIP;
        case runanywhere::v1::ARCHIVE_TYPE_TAR_BZ2:
            return RAC_ARCHIVE_TYPE_TAR_BZ2;
        case runanywhere::v1::ARCHIVE_TYPE_TAR_GZ:
            return RAC_ARCHIVE_TYPE_TAR_GZ;
        case runanywhere::v1::ARCHIVE_TYPE_TAR_XZ:
            return RAC_ARCHIVE_TYPE_TAR_XZ;
        case runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED:
        default:
            return RAC_ARCHIVE_TYPE_NONE;
    }
}

static ArchiveStructure archive_structure_to_proto(rac_archive_structure_t structure) {
    switch (structure) {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED:
            return runanywhere::v1::ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:
            return runanywhere::v1::ARCHIVE_STRUCTURE_DIRECTORY_BASED;
        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY:
            return runanywhere::v1::ARCHIVE_STRUCTURE_NESTED_DIRECTORY;
        case RAC_ARCHIVE_STRUCTURE_UNKNOWN:
        default:
            return runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN;
    }
}

static rac_archive_structure_t archive_structure_from_proto(ArchiveStructure structure) {
    switch (structure) {
        case runanywhere::v1::ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED:
            return RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED;
        case runanywhere::v1::ARCHIVE_STRUCTURE_DIRECTORY_BASED:
            return RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED;
        case runanywhere::v1::ARCHIVE_STRUCTURE_NESTED_DIRECTORY:
            return RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY;
        case runanywhere::v1::ARCHIVE_STRUCTURE_UNSPECIFIED:
        case runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN:
        default:
            return RAC_ARCHIVE_STRUCTURE_UNKNOWN;
    }
}

static char* dup_optional_proto_string(const std::string& value) {
    return value.empty() ? nullptr : rac_strdup(value.c_str());
}

static bool copy_string_array_from_proto(
    const google::protobuf::RepeatedPtrField<std::string>& input,
    const char*** out_values,
    size_t* out_count) {
    *out_values = nullptr;
    *out_count = 0;
    if (input.empty()) {
        return true;
    }

    const size_t count = static_cast<size_t>(input.size());
    const char** values = static_cast<const char**>(calloc(count, sizeof(char*)));
    if (!values) {
        return false;
    }

    for (size_t i = 0; i < count; ++i) {
        values[i] = rac_strdup(input.Get(static_cast<int>(i)).c_str());
        if (!values[i]) {
            for (size_t j = 0; j < i; ++j) {
                free(const_cast<char*>(values[j]));
            }
            free(values);
            return false;
        }
    }

    *out_values = values;
    *out_count = count;
    return true;
}

static rac_expected_model_files_t* expected_files_from_patterns(
    const google::protobuf::RepeatedPtrField<std::string>& required,
    const google::protobuf::RepeatedPtrField<std::string>& optional) {
    if (required.empty() && optional.empty()) {
        return nullptr;
    }

    rac_expected_model_files_t* files = rac_expected_model_files_alloc();
    if (!files) {
        return nullptr;
    }

    if (!copy_string_array_from_proto(required, &files->required_patterns,
                                      &files->required_pattern_count) ||
        !copy_string_array_from_proto(optional, &files->optional_patterns,
                                      &files->optional_pattern_count)) {
        rac_expected_model_files_free(files);
        return nullptr;
    }

    return files;
}

static void add_expected_patterns_to_single_file(const rac_expected_model_files_t* files,
                                                 SingleFileArtifact* out) {
    if (!files || !out) {
        return;
    }
    for (size_t i = 0; i < files->required_pattern_count; ++i) {
        if (files->required_patterns[i]) out->add_required_patterns(files->required_patterns[i]);
    }
    for (size_t i = 0; i < files->optional_pattern_count; ++i) {
        if (files->optional_patterns[i]) out->add_optional_patterns(files->optional_patterns[i]);
    }
}

static void add_expected_patterns_to_archive(const rac_expected_model_files_t* files,
                                             ArchiveArtifact* out) {
    if (!files || !out) {
        return;
    }
    for (size_t i = 0; i < files->required_pattern_count; ++i) {
        if (files->required_patterns[i]) out->add_required_patterns(files->required_patterns[i]);
    }
    for (size_t i = 0; i < files->optional_pattern_count; ++i) {
        if (files->optional_patterns[i]) out->add_optional_patterns(files->optional_patterns[i]);
    }
}

static void add_file_descriptors_to_proto(const rac_model_artifact_info_t* artifact,
                                          MultiFileArtifact* out) {
    if (!artifact || !out || !artifact->file_descriptors) {
        return;
    }
    for (size_t i = 0; i < artifact->file_descriptor_count; ++i) {
        const rac_model_file_descriptor_t& in = artifact->file_descriptors[i];
        ModelFileDescriptor* file = out->add_files();
        if (in.relative_path) file->set_url(in.relative_path);
        if (in.destination_path) file->set_filename(in.destination_path);
        file->set_is_required(in.is_required == RAC_TRUE);
    }
}

static void model_info_to_proto(const rac_model_info_t* in,
                                ModelInfo* out,
                                bool overwrite_artifact) {
    if (!in || !out) {
        return;
    }

    out->set_id(in->id ? in->id : "");
    out->set_name(in->name ? in->name : "");
    out->set_category(model_category_to_proto(in->category));
    out->set_format(model_format_to_proto(in->format));
    out->set_framework(inference_framework_to_proto(in->framework));
    out->set_download_url(in->download_url ? in->download_url : "");
    out->set_local_path(in->local_path ? in->local_path : "");
    out->set_download_size_bytes(in->download_size);
    out->set_context_length(in->context_length);
    out->set_supports_thinking(in->supports_thinking == RAC_TRUE);
    out->set_supports_lora(in->supports_lora == RAC_TRUE);
    out->set_description(in->description ? in->description : "");
    out->set_source(model_source_to_proto(in->source));
    out->set_created_at_unix_ms(in->created_at);
    out->set_updated_at_unix_ms(in->updated_at);
    if (in->memory_required > 0) {
        out->set_memory_required_bytes(in->memory_required);
    }
    if (in->last_used > 0) {
        out->set_last_used_at_unix_ms(in->last_used);
    }
    if (in->usage_count > 0) {
        out->set_usage_count(in->usage_count);
    }

    if (!overwrite_artifact) {
        return;
    }

    out->clear_artifact();
    switch (in->artifact_info.kind) {
        case RAC_ARTIFACT_KIND_ARCHIVE: {
            ArchiveArtifact* artifact = out->mutable_archive();
            artifact->set_type(archive_type_to_proto(in->artifact_info.archive_type));
            artifact->set_structure(
                archive_structure_to_proto(in->artifact_info.archive_structure));
            add_expected_patterns_to_archive(in->artifact_info.expected_files, artifact);
            if (in->artifact_info.archive_type == RAC_ARCHIVE_TYPE_ZIP) {
                out->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE);
            } else if (in->artifact_info.archive_type == RAC_ARCHIVE_TYPE_TAR_GZ) {
                out->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE);
            }
            break;
        }
        case RAC_ARTIFACT_KIND_MULTI_FILE: {
            MultiFileArtifact* artifact = out->mutable_multi_file();
            add_file_descriptors_to_proto(&in->artifact_info, artifact);
            out->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_DIRECTORY);
            break;
        }
        case RAC_ARTIFACT_KIND_CUSTOM:
            out->set_custom_strategy_id(in->artifact_info.strategy_id
                                            ? in->artifact_info.strategy_id
                                            : "");
            out->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_CUSTOM);
            break;
        case RAC_ARTIFACT_KIND_BUILT_IN:
            out->set_built_in(true);
            break;
        case RAC_ARTIFACT_KIND_SINGLE_FILE:
        default: {
            SingleFileArtifact* artifact = out->mutable_single_file();
            add_expected_patterns_to_single_file(in->artifact_info.expected_files, artifact);
            out->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
            break;
        }
    }
}

static bool apply_proto_artifact_to_model(const ModelInfo& proto, rac_model_info_t* model) {
    switch (proto.artifact_case()) {
        case ModelInfo::kSingleFile:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
            model->artifact_info.expected_files = expected_files_from_patterns(
                proto.single_file().required_patterns(),
                proto.single_file().optional_patterns());
            break;
        case ModelInfo::kArchive:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
            model->artifact_info.archive_type = archive_type_from_proto(proto.archive().type());
            model->artifact_info.archive_structure =
                archive_structure_from_proto(proto.archive().structure());
            model->artifact_info.expected_files = expected_files_from_patterns(
                proto.archive().required_patterns(),
                proto.archive().optional_patterns());
            break;
        case ModelInfo::kMultiFile: {
            model->artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
            const int file_count = proto.multi_file().files_size();
            if (file_count > 0) {
                model->artifact_info.file_descriptors =
                    rac_model_file_descriptors_alloc(static_cast<size_t>(file_count));
                if (!model->artifact_info.file_descriptors) {
                    return false;
                }
                model->artifact_info.file_descriptor_count = static_cast<size_t>(file_count);
                for (int i = 0; i < file_count; ++i) {
                    const ModelFileDescriptor& file = proto.multi_file().files(i);
                    rac_model_file_descriptor_t& out =
                        model->artifact_info.file_descriptors[static_cast<size_t>(i)];
                    out.relative_path = dup_optional_proto_string(file.url());
                    out.destination_path = dup_optional_proto_string(file.filename());
                    out.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                }
            }
            break;
        }
        case ModelInfo::kCustomStrategyId:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_CUSTOM;
            model->artifact_info.strategy_id =
                dup_optional_proto_string(proto.custom_strategy_id());
            break;
        case ModelInfo::kBuiltIn:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_BUILT_IN;
            break;
        case ModelInfo::ARTIFACT_NOT_SET:
        default:
            if (proto.has_artifact_type()) {
                switch (proto.artifact_type()) {
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
                        model->artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
                        break;
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_DIRECTORY:
                        model->artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
                        break;
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_CUSTOM:
                        model->artifact_info.kind = RAC_ARTIFACT_KIND_CUSTOM;
                        break;
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE:
                    case runanywhere::v1::MODEL_ARTIFACT_TYPE_UNSPECIFIED:
                    default:
                        model->artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
                        break;
                }
            } else {
                model->artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
            }
            break;
    }
    return true;
}

static rac_model_info_t* model_info_from_proto(const ModelInfo& proto) {
    if (proto.id().empty()) {
        return nullptr;
    }

    rac_model_info_t* model = rac_model_info_alloc();
    if (!model) {
        return nullptr;
    }

    model->id = rac_strdup(proto.id().c_str());
    model->name = dup_optional_proto_string(proto.name());
    model->category = model_category_from_proto(proto.category());
    model->format = model_format_from_proto(proto.format());
    model->framework = inference_framework_from_proto(proto.framework());
    model->download_url = dup_optional_proto_string(proto.download_url());
    model->local_path = dup_optional_proto_string(proto.local_path());
    model->download_size = proto.download_size_bytes();
    model->context_length = proto.context_length();
    model->supports_thinking = proto.supports_thinking() ? RAC_TRUE : RAC_FALSE;
    model->supports_lora = proto.supports_lora() ? RAC_TRUE : RAC_FALSE;
    model->description = dup_optional_proto_string(proto.description());
    model->source = model_source_from_proto(proto.source());
    model->created_at = proto.created_at_unix_ms();
    model->updated_at = proto.updated_at_unix_ms();
    model->memory_required = proto.has_memory_required_bytes()
                                 ? proto.memory_required_bytes()
                                 : 0;
    model->last_used = proto.has_last_used_at_unix_ms()
                           ? proto.last_used_at_unix_ms()
                           : 0;
    model->usage_count = proto.has_usage_count()
                             ? proto.usage_count()
                             : 0;

    if (!model->id || !apply_proto_artifact_to_model(proto, model)) {
        rac_model_info_free(model);
        return nullptr;
    }

    return model;
}

template <typename ProtoMessage>
static rac_result_t serialize_proto_to_owned_buffer(const ProtoMessage& message,
                                                    uint8_t** proto_bytes_out,
                                                    size_t* proto_size_out) {
    if (!proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return RAC_ERROR_UNKNOWN;
    }

    return rac_proto_buffer_copy_to_raw(
        reinterpret_cast<const uint8_t*>(bytes.data()),
        bytes.size(),
        proto_bytes_out,
        proto_size_out);
}

static rac_result_t parse_model_info_bytes(const uint8_t* proto_bytes,
                                           size_t proto_size,
                                           ModelInfo* out) {
    if (!proto_bytes || proto_size == 0 || !out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (proto_size > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!out->ParseFromArray(proto_bytes, static_cast<int>(proto_size))) {
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (out->id().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

static rac_result_t parse_model_query_bytes(const uint8_t* query_proto_bytes,
                                            size_t query_proto_size,
                                            ModelQuery* out) {
    if (!query_proto_bytes || query_proto_size == 0 || !out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (query_proto_size > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!out->ParseFromArray(query_proto_bytes, static_cast<int>(query_proto_size))) {
        return RAC_ERROR_INVALID_FORMAT;
    }
    return RAC_SUCCESS;
}

static void preserve_absent_proto_fields(const ModelInfo& existing, ModelInfo* incoming) {
    if (!incoming) {
        return;
    }

    if (!incoming->has_memory_required_bytes() && existing.has_memory_required_bytes()) {
        incoming->set_memory_required_bytes(existing.memory_required_bytes());
    }
    if (!incoming->has_checksum_sha256() && existing.has_checksum_sha256()) {
        incoming->set_checksum_sha256(existing.checksum_sha256());
    }
    if (!incoming->has_thinking_pattern() && existing.has_thinking_pattern()) {
        incoming->mutable_thinking_pattern()->CopyFrom(existing.thinking_pattern());
    }
    if (!incoming->has_metadata() && existing.has_metadata()) {
        incoming->mutable_metadata()->CopyFrom(existing.metadata());
    }
    if (!incoming->has_expected_files() && existing.has_expected_files()) {
        incoming->mutable_expected_files()->CopyFrom(existing.expected_files());
    }
    if (!incoming->has_compatibility() && existing.has_compatibility()) {
        incoming->mutable_compatibility()->CopyFrom(existing.compatibility());
    }
    if (!incoming->has_artifact_type() && existing.has_artifact_type()) {
        incoming->set_artifact_type(existing.artifact_type());
    }
    if (!incoming->has_acceleration_preference() && existing.has_acceleration_preference()) {
        incoming->set_acceleration_preference(existing.acceleration_preference());
    }
    if (!incoming->has_routing_policy() && existing.has_routing_policy()) {
        incoming->set_routing_policy(existing.routing_policy());
    }
    if (!incoming->has_preferred_framework() && existing.has_preferred_framework()) {
        incoming->set_preferred_framework(existing.preferred_framework());
    }
    if (!incoming->has_registry_status() && existing.has_registry_status()) {
        incoming->set_registry_status(existing.registry_status());
    }
    if (!incoming->has_is_downloaded() && existing.has_is_downloaded()) {
        incoming->set_is_downloaded(existing.is_downloaded());
    }
    if (!incoming->has_is_available() && existing.has_is_available()) {
        incoming->set_is_available(existing.is_available());
    }
    if (!incoming->has_last_used_at_unix_ms() && existing.has_last_used_at_unix_ms()) {
        incoming->set_last_used_at_unix_ms(existing.last_used_at_unix_ms());
    }
    if (!incoming->has_usage_count() && existing.has_usage_count()) {
        incoming->set_usage_count(existing.usage_count());
    }
    if (!incoming->has_sync_pending() && existing.has_sync_pending()) {
        incoming->set_sync_pending(existing.sync_pending());
    }
    if (!incoming->has_status_message() && existing.has_status_message()) {
        incoming->set_status_message(existing.status_message());
    }

    if (incoming->artifact_case() == ModelInfo::ARTIFACT_NOT_SET) {
        switch (existing.artifact_case()) {
            case ModelInfo::kSingleFile:
                incoming->mutable_single_file()->CopyFrom(existing.single_file());
                break;
            case ModelInfo::kArchive:
                incoming->mutable_archive()->CopyFrom(existing.archive());
                break;
            case ModelInfo::kMultiFile:
                incoming->mutable_multi_file()->CopyFrom(existing.multi_file());
                break;
            case ModelInfo::kCustomStrategyId:
                incoming->set_custom_strategy_id(existing.custom_strategy_id());
                break;
            case ModelInfo::kBuiltIn:
                incoming->set_built_in(existing.built_in());
                break;
            case ModelInfo::ARTIFACT_NOT_SET:
            default:
                break;
        }
    }
}

static rac_result_t store_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id,
                                                const rac_model_info_t* model,
                                                bool preserve_proto_only_fields) {
    ModelInfo snapshot;
    bool parsed_existing = false;
    if (preserve_proto_only_fields) {
        auto proto_it = handle->model_proto_bytes.find(model_id);
        if (proto_it != handle->model_proto_bytes.end()) {
            parsed_existing = snapshot.ParseFromString(proto_it->second);
        }
    }
    if (!parsed_existing) {
        snapshot.Clear();
    }

    model_info_to_proto(model, &snapshot, /*overwrite_artifact=*/!parsed_existing);
    if (!snapshot.SerializeToString(&handle->model_proto_bytes[model_id])) {
        handle->model_proto_bytes.erase(model_id);
        return RAC_ERROR_UNKNOWN;
    }
    return RAC_SUCCESS;
}

static rac_result_t store_parsed_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                                       const std::string& model_id,
                                                       const ModelInfo& parsed_proto) {
    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    ModelInfo snapshot(parsed_proto);
    model_info_to_proto(it->second, &snapshot, /*overwrite_artifact=*/false);
    if (!snapshot.SerializeToString(&handle->model_proto_bytes[model_id])) {
        handle->model_proto_bytes.erase(model_id);
        return RAC_ERROR_UNKNOWN;
    }
    return RAC_SUCCESS;
}

static ModelInfo model_snapshot_locked(rac_model_registry_handle_t handle,
                                       const std::string& model_id,
                                       const rac_model_info_t* model) {
    ModelInfo snapshot;
    auto proto_it = handle->model_proto_bytes.find(model_id);
    if (proto_it != handle->model_proto_bytes.end() &&
        snapshot.ParseFromString(proto_it->second)) {
        model_info_to_proto(model, &snapshot, /*overwrite_artifact=*/false);
    } else {
        snapshot.Clear();
        model_info_to_proto(model, &snapshot, /*overwrite_artifact=*/true);
    }
    return snapshot;
}

static rac_result_t model_to_proto_bytes_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id,
                                                const rac_model_info_t* model,
                                                uint8_t** proto_bytes_out,
                                                size_t* proto_size_out) {
    ModelInfo snapshot = model_snapshot_locked(handle, model_id, model);
    return serialize_proto_to_owned_buffer(snapshot, proto_bytes_out, proto_size_out);
}

static std::string lowercase_copy(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    for (unsigned char ch : input) {
        out.push_back(static_cast<char>(std::tolower(ch)));
    }
    return out;
}

static bool contains_text_case_insensitive(const std::string& value,
                                           const std::string& needle_lower) {
    return lowercase_copy(value).find(needle_lower) != std::string::npos;
}

static bool model_is_downloaded_proto(const ModelInfo& model) {
    if (model.has_is_downloaded()) {
        return model.is_downloaded();
    }
    if (!model.local_path().empty()) {
        return true;
    }
    if (model.has_registry_status()) {
        return model.registry_status() == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED ||
               model.registry_status() == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED;
    }
    return false;
}

static bool model_is_available_proto(const ModelInfo& model) {
    if (model.has_is_available()) {
        return model.is_available();
    }
    return model_is_downloaded_proto(model);
}

static bool model_matches_search_text(const ModelInfo& model,
                                      const std::string& needle_lower) {
    if (needle_lower.empty()) {
        return true;
    }

    if (contains_text_case_insensitive(model.id(), needle_lower) ||
        contains_text_case_insensitive(model.name(), needle_lower) ||
        contains_text_case_insensitive(model.description(), needle_lower) ||
        contains_text_case_insensitive(model.download_url(), needle_lower) ||
        contains_text_case_insensitive(model.local_path(), needle_lower) ||
        contains_text_case_insensitive(model.checksum_sha256(), needle_lower) ||
        contains_text_case_insensitive(model.status_message(), needle_lower)) {
        return true;
    }

    if (model.has_metadata()) {
        const auto& metadata = model.metadata();
        if (contains_text_case_insensitive(metadata.description(), needle_lower) ||
            contains_text_case_insensitive(metadata.author(), needle_lower) ||
            contains_text_case_insensitive(metadata.license(), needle_lower) ||
            contains_text_case_insensitive(metadata.version(), needle_lower)) {
            return true;
        }
        for (const auto& tag : metadata.tags()) {
            if (contains_text_case_insensitive(tag, needle_lower)) {
                return true;
            }
        }
    }

    if (model.has_expected_files()) {
        const auto& expected = model.expected_files();
        if (contains_text_case_insensitive(expected.root_directory(), needle_lower) ||
            contains_text_case_insensitive(expected.description(), needle_lower)) {
            return true;
        }
        for (const auto& pattern : expected.required_patterns()) {
            if (contains_text_case_insensitive(pattern, needle_lower)) {
                return true;
            }
        }
        for (const auto& pattern : expected.optional_patterns()) {
            if (contains_text_case_insensitive(pattern, needle_lower)) {
                return true;
            }
        }
        for (const auto& file : expected.files()) {
            if (contains_text_case_insensitive(file.url(), needle_lower) ||
                contains_text_case_insensitive(file.filename(), needle_lower) ||
                contains_text_case_insensitive(file.relative_path(), needle_lower) ||
                contains_text_case_insensitive(file.destination_path(), needle_lower) ||
                contains_text_case_insensitive(file.local_path(), needle_lower) ||
                contains_text_case_insensitive(file.checksum(), needle_lower)) {
                return true;
            }
        }
    }

    return false;
}

static bool model_matches_query(const ModelInfo& model, const ModelQuery& query) {
    if (query.has_framework() && model.framework() != query.framework()) {
        return false;
    }
    if (query.has_category() && model.category() != query.category()) {
        return false;
    }
    if (query.has_format() && model.format() != query.format()) {
        return false;
    }
    if (query.has_source() && model.source() != query.source()) {
        return false;
    }
    if (query.has_downloaded_only() && query.downloaded_only() &&
        !model_is_downloaded_proto(model)) {
        return false;
    }
    if (query.has_available_only() && query.available_only() &&
        !model_is_available_proto(model)) {
        return false;
    }
    if (query.has_max_size_bytes() && query.max_size_bytes() >= 0 &&
        model.download_size_bytes() > query.max_size_bytes()) {
        return false;
    }

    const std::string needle_lower = lowercase_copy(query.search_query());
    return model_matches_search_text(model, needle_lower);
}

static int compare_strings(const std::string& lhs, const std::string& rhs) {
    if (lhs < rhs) {
        return -1;
    }
    if (rhs < lhs) {
        return 1;
    }
    return 0;
}

template <typename T>
static int compare_values(T lhs, T rhs) {
    if (lhs < rhs) {
        return -1;
    }
    if (rhs < lhs) {
        return 1;
    }
    return 0;
}

static int compare_models_by_sort_field(const ModelInfo& lhs,
                                        const ModelInfo& rhs,
                                        ModelQuerySortField sort_field) {
    switch (sort_field) {
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_NAME:
            return compare_strings(lhs.name(), rhs.name());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS:
            return compare_values(lhs.created_at_unix_ms(), rhs.created_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS:
            return compare_values(lhs.updated_at_unix_ms(), rhs.updated_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES:
            return compare_values(lhs.download_size_bytes(), rhs.download_size_bytes());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS:
            return compare_values(lhs.last_used_at_unix_ms(), rhs.last_used_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_USAGE_COUNT:
            return compare_values(lhs.usage_count(), rhs.usage_count());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_UNSPECIFIED:
        default:
            return 0;
    }
}

static bool query_has_supported_sort_field(const ModelQuery& query) {
    return query.has_sort_field() &&
           query.sort_field() != runanywhere::v1::MODEL_QUERY_SORT_FIELD_UNSPECIFIED;
}

static void sort_query_results(const ModelQuery& query, std::vector<ModelInfo>* models) {
    if (!models || !query_has_supported_sort_field(query)) {
        return;
    }

    const ModelQuerySortField sort_field = query.sort_field();
    const bool descending =
        query.has_sort_order() &&
        query.sort_order() == runanywhere::v1::MODEL_QUERY_SORT_ORDER_DESCENDING;

    std::sort(models->begin(), models->end(), [sort_field, descending](const ModelInfo& lhs,
                                                                       const ModelInfo& rhs) {
        int result = compare_models_by_sort_field(lhs, rhs, sort_field);
        if (result == 0) {
            return lhs.id() < rhs.id();
        }
        return descending ? result > 0 : result < 0;
    });
}

static void append_query_results_locked(rac_model_registry_handle_t handle,
                                        const ModelQuery& query,
                                        ModelInfoList* out) {
    std::vector<ModelInfo> matches;
    for (const auto& pair : handle->models) {
        ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
        if (model_matches_query(snapshot, query)) {
            matches.push_back(std::move(snapshot));
        }
    }
    sort_query_results(query, &matches);
    for (ModelInfo& model : matches) {
        out->add_models()->Swap(&model);
    }
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// PUBLIC API - LIFECYCLE
// =============================================================================

rac_result_t rac_model_registry_create(rac_model_registry_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_model_registry* registry = new (std::nothrow) rac_model_registry();
    if (!registry) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    RAC_LOG_INFO("ModelRegistry", "Model registry created");

    *out_handle = registry;
    return RAC_SUCCESS;
}

void rac_model_registry_destroy(rac_model_registry_handle_t handle) {
    if (!handle) {
        return;
    }

    // Free all stored models
    for (auto& pair : handle->models) {
        free_model_info(pair.second);
    }
    handle->models.clear();

    delete handle;
    RAC_LOG_DEBUG("ModelRegistry", "Model registry destroyed");
}

// =============================================================================
// PUBLIC API - MODEL INFO
// =============================================================================

rac_result_t rac_model_registry_save(rac_model_registry_handle_t handle,
                                     const rac_model_info_t* model) {
    if (!handle || !model || !model->id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    std::string model_id = model->id;

    auto it = handle->models.find(model_id);
    if (it != handle->models.end()) {
        // Preserve existing local_path if the incoming model doesn't have one.
        // This prevents registerModel() (which always passes localPath=nil) from
        // overwriting a localPath that was set by download completion or discovery.
        const char* existing_local_path = it->second->local_path;
        bool should_preserve_path = existing_local_path && strlen(existing_local_path) > 0 &&
                                    (!model->local_path || strlen(model->local_path) == 0);

        // Store a deep copy of the incoming model
        rac_model_info_t* copy = deep_copy_model(model);
        if (!copy) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        if (should_preserve_path) {
            if (copy->local_path)
                free(copy->local_path);
            copy->local_path = rac_strdup(existing_local_path);
        }

        free_model_info(it->second);
        handle->models[model_id] = copy;
    } else {
        // New model — store a deep copy
        rac_model_info_t* copy = deep_copy_model(model);
        if (!copy) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        handle->models[model_id] = copy;
    }

#ifdef RAC_HAVE_PROTOBUF
    auto stored = handle->models.find(model_id);
    if (stored != handle->models.end()) {
        rac_result_t proto_rc =
            store_proto_snapshot_locked(handle, model_id, stored->second,
                                        /*preserve_proto_only_fields=*/false);
        if (proto_rc != RAC_SUCCESS) {
            return proto_rc;
        }
    }
#endif

    RAC_LOG_DEBUG("ModelRegistry", "Model saved");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get(rac_model_registry_handle_t handle, const char* model_id,
                                    rac_model_info_t** out_model) {
    if (!handle || !model_id || !out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    *out_model = deep_copy_model(it->second);
    if (!*out_model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_by_path(rac_model_registry_handle_t handle,
                                            const char* local_path, rac_model_info_t** out_model) {
    if (!handle || !local_path || !out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Search through all models for matching local_path
    for (const auto& pair : handle->models) {
        const rac_model_info_t* model = pair.second;
        if (model->local_path && strcmp(model->local_path, local_path) == 0) {
            *out_model = deep_copy_model(model);
            if (!*out_model) {
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            RAC_LOG_DEBUG("ModelRegistry", "Found model by path: %s -> %s", local_path, model->id);
            return RAC_SUCCESS;
        }
    }

    // Also check if the path starts with or contains the local_path
    // This handles cases where the input path has extra components
    std::string search_path(local_path);
    for (const auto& pair : handle->models) {
        const rac_model_info_t* model = pair.second;
        if (model->local_path) {
            std::string model_path(model->local_path);
            // Check if search path starts with model's local_path
            if (search_path.find(model_path) == 0 || model_path.find(search_path) == 0) {
                *out_model = deep_copy_model(model);
                if (!*out_model) {
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
                RAC_LOG_DEBUG("ModelRegistry", "Found model by partial path match: %s -> %s",
                              local_path, model->id);
                return RAC_SUCCESS;
            }
        }
    }

    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_model_registry_get_all(rac_model_registry_handle_t handle,
                                        rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    *out_count = handle->models.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    size_t i = 0;
    for (const auto& pair : handle->models) {
        (*out_models)[i] = deep_copy_model(pair.second);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        ++i;
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_by_frameworks(rac_model_registry_handle_t handle,
                                                  const rac_inference_framework_t* frameworks,
                                                  size_t framework_count,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    if (!handle || !frameworks || framework_count == 0 || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect matching models
    std::vector<rac_model_info_t*> matches;

    for (const auto& pair : handle->models) {
        for (size_t i = 0; i < framework_count; ++i) {
            if (pair.second->framework == frameworks[i]) {
                matches.push_back(pair.second);
                break;
            }
        }
    }

    *out_count = matches.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < matches.size(); ++i) {
        (*out_models)[i] = deep_copy_model(matches[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_last_used(rac_model_registry_handle_t handle,
                                                 const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;
    model->last_used = rac_get_current_time_ms() / 1000;  // Convert to seconds
    model->usage_count++;

#ifdef RAC_HAVE_PROTOBUF
    return store_proto_snapshot_locked(handle, model_id, model,
                                       /*preserve_proto_only_fields=*/true);
#else
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_model_registry_remove(rac_model_registry_handle_t handle, const char* model_id) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    free_model_info(it->second);
    handle->models.erase(it);
#ifdef RAC_HAVE_PROTOBUF
    handle->model_proto_bytes.erase(model_id);
#endif

    RAC_LOG_DEBUG("ModelRegistry", "Model removed");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_get_downloaded(rac_model_registry_handle_t handle,
                                               rac_model_info_t*** out_models, size_t* out_count) {
    if (!handle || !out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Collect downloaded models
    std::vector<rac_model_info_t*> downloaded;

    for (const auto& pair : handle->models) {
        if (pair.second->local_path && strlen(pair.second->local_path) > 0) {
            downloaded.push_back(pair.second);
        }
    }

    *out_count = downloaded.size();
    if (*out_count == 0) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models = static_cast<rac_model_info_t**>(malloc(sizeof(rac_model_info_t*) * *out_count));
    if (!*out_models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < downloaded.size(); ++i) {
        (*out_models)[i] = deep_copy_model(downloaded[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; ++j) {
                free_model_info((*out_models)[j]);
            }
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_update_download_status(rac_model_registry_handle_t handle,
                                                       const char* model_id,
                                                       const char* local_path) {
    if (!handle || !model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    rac_model_info_t* model = it->second;

    // Free old local path
    if (model->local_path) {
        free(model->local_path);
    }

    // Set new local path
    model->local_path = rac_strdup(local_path);
    model->updated_at = rac_get_current_time_ms() / 1000;

#ifdef RAC_HAVE_PROTOBUF
    return store_proto_snapshot_locked(handle, model_id, model,
                                       /*preserve_proto_only_fields=*/true);
#else
    return RAC_SUCCESS;
#endif
}

// =============================================================================
// PUBLIC API - PROTO-BYTE MODEL INFO
// =============================================================================

rac_result_t rac_model_registry_register_proto(rac_model_registry_handle_t handle,
                                               const uint8_t* proto_bytes,
                                               size_t proto_size) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    ModelInfo proto_model;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &proto_model);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    rac_result_t save_rc = rac_model_registry_save(handle, model);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_update_proto(rac_model_registry_handle_t handle,
                                             const uint8_t* proto_bytes,
                                             size_t proto_size) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    ModelInfo proto_model;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &proto_model);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        auto model_it = handle->models.find(proto_model.id());
        if (model_it == handle->models.end()) {
            return RAC_ERROR_NOT_FOUND;
        }
        ModelInfo existing = model_snapshot_locked(handle, proto_model.id(), model_it->second);
        preserve_absent_proto_fields(existing, &proto_model);
    }

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    rac_result_t save_rc = rac_model_registry_save(handle, model);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_get_proto(rac_model_registry_handle_t handle,
                                          const char* model_id,
                                          uint8_t** proto_bytes_out,
                                          size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    if (proto_bytes_out) *proto_bytes_out = nullptr;
    if (proto_size_out) *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !model_id || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    return model_to_proto_bytes_locked(handle, model_id, it->second,
                                       proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_list_proto(rac_model_registry_handle_t handle,
                                           uint8_t** proto_bytes_out,
                                           size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    if (proto_bytes_out) *proto_bytes_out = nullptr;
    if (proto_size_out) *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        for (const auto& pair : handle->models) {
            ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
            list.add_models()->Swap(&snapshot);
        }
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_query_proto(rac_model_registry_handle_t handle,
                                            const uint8_t* query_proto_bytes,
                                            size_t query_proto_size,
                                            uint8_t** proto_bytes_out,
                                            size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)query_proto_bytes;
    (void)query_proto_size;
    if (proto_bytes_out) *proto_bytes_out = nullptr;
    if (proto_size_out) *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelQuery query;
    rac_result_t parse_rc =
        parse_model_query_bytes(query_proto_bytes, query_proto_size, &query);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        append_query_results_locked(handle, query, &list);
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_list_downloaded_proto(rac_model_registry_handle_t handle,
                                                      uint8_t** proto_bytes_out,
                                                      size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    if (proto_bytes_out) *proto_bytes_out = nullptr;
    if (proto_size_out) *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelQuery query;
    query.set_downloaded_only(true);

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        append_query_results_locked(handle, query, &list);
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_remove_proto(rac_model_registry_handle_t handle,
                                             const char* model_id) {
    return rac_model_registry_remove(handle, model_id);
}

void rac_model_registry_proto_free(uint8_t* proto_bytes) {
    rac_proto_buffer_free_data(proto_bytes);
}

// =============================================================================
// PUBLIC API - QUERY HELPERS
// =============================================================================

// NOTE: rac_model_info_is_downloaded, rac_model_category_requires_context_length,
// and rac_model_category_supports_thinking are defined in model_types.cpp

rac_artifact_type_kind_t rac_model_infer_artifact_type(const char* url, rac_model_format_t format) {
    // Infer from URL extension
    if (url) {
        size_t len = strlen(url);

        if (len > 4 && strcmp(url + len - 4, ".zip") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tar") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 7 && strcmp(url + len - 7, ".tar.gz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
        if (len > 4 && strcmp(url + len - 4, ".tgz") == 0) {
            return RAC_ARTIFACT_KIND_ARCHIVE;
        }
    }

    // Default to single file for most formats
    switch (format) {
        case RAC_MODEL_FORMAT_GGUF:
        case RAC_MODEL_FORMAT_ONNX:
        case RAC_MODEL_FORMAT_BIN:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
        default:
            return RAC_ARTIFACT_KIND_SINGLE_FILE;
    }
}

// =============================================================================
// PUBLIC API - MODEL DISCOVERY
// =============================================================================

// Helper to check if a folder contains valid model files for a framework
static bool is_valid_model_folder(const rac_discovery_callbacks_t* callbacks,
                                  const char* folder_path, rac_inference_framework_t framework) {
    if (!callbacks || !callbacks->list_directory || !folder_path) {
        return false;
    }

    char** entries = nullptr;
    size_t count = 0;

    // List directory contents
    if (callbacks->list_directory(folder_path, &entries, &count, callbacks->user_data) !=
        RAC_SUCCESS) {
        return false;
    }

    bool found_model_file = false;

    for (size_t i = 0; i < count && !found_model_file; i++) {
        if (!entries[i])
            continue;

        // Build full path
        std::string full_path = std::string(folder_path) + "/" + entries[i];

        // Check if it's a model file for this framework
        if (callbacks->is_model_file) {
            if (callbacks->is_model_file(full_path.c_str(), framework, callbacks->user_data) ==
                RAC_TRUE) {
                found_model_file = true;
            }
        }

        // For nested directories, recursively check (one level deep)
        if (!found_model_file && callbacks->is_directory) {
            if (callbacks->is_directory(full_path.c_str(), callbacks->user_data) == RAC_TRUE) {
                // Check subdirectory for model files
                char** sub_entries = nullptr;
                size_t sub_count = 0;
                if (callbacks->list_directory(full_path.c_str(), &sub_entries, &sub_count,
                                              callbacks->user_data) == RAC_SUCCESS) {
                    for (size_t j = 0; j < sub_count && !found_model_file; j++) {
                        if (!sub_entries[j])
                            continue;
                        std::string sub_path = full_path + "/" + sub_entries[j];
                        if (callbacks->is_model_file &&
                            callbacks->is_model_file(sub_path.c_str(), framework,
                                                     callbacks->user_data) == RAC_TRUE) {
                            found_model_file = true;
                        }
                    }
                    if (callbacks->free_entries) {
                        callbacks->free_entries(sub_entries, sub_count, callbacks->user_data);
                    }
                }
            }
        }
    }

    if (callbacks->free_entries) {
        callbacks->free_entries(entries, count, callbacks->user_data);
    }

    return found_model_file;
}

rac_result_t rac_model_registry_discover_downloaded(rac_model_registry_handle_t handle,
                                                    const rac_discovery_callbacks_t* callbacks,
                                                    rac_discovery_result_t* out_result) {
    if (!handle || !callbacks || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize result
    out_result->discovered_count = 0;
    out_result->discovered_models = nullptr;
    out_result->unregistered_count = 0;

    // Check required callbacks
    if (!callbacks->list_directory || !callbacks->path_exists || !callbacks->is_directory) {
        RAC_LOG_WARNING("ModelRegistry", "Discovery: Missing required callbacks");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("ModelRegistry", "Starting model discovery scan...");

    // Get models directory path
    char models_dir[1024];
    if (rac_model_paths_get_models_directory(models_dir, sizeof(models_dir)) != RAC_SUCCESS) {
        RAC_LOG_WARNING("ModelRegistry", "Discovery: Base directory not configured");
        return RAC_SUCCESS;  // Not an error, just nothing to discover
    }

    // Check if models directory exists
    if (callbacks->path_exists(models_dir, callbacks->user_data) != RAC_TRUE) {
        RAC_LOG_DEBUG("ModelRegistry", "Discovery: Models directory does not exist yet");
        return RAC_SUCCESS;
    }

    // Frameworks to scan - include all frameworks that can have downloaded models
    // Note: RAC_FRAMEWORK_UNKNOWN is included to recover models that were incorrectly
    // stored in the "Unknown" directory due to missing framework mappings
    rac_inference_framework_t frameworks[] = {
        RAC_FRAMEWORK_LLAMACPP,    RAC_FRAMEWORK_ONNX,
        RAC_FRAMEWORK_COREML,      RAC_FRAMEWORK_MLX,
        RAC_FRAMEWORK_FLUID_AUDIO, RAC_FRAMEWORK_FOUNDATION_MODELS,
        RAC_FRAMEWORK_SYSTEM_TTS,  RAC_FRAMEWORK_WHISPERKIT_COREML,
        RAC_FRAMEWORK_METALRT,     RAC_FRAMEWORK_GENIE,
        RAC_FRAMEWORK_SHERPA,      RAC_FRAMEWORK_UNKNOWN};
    size_t framework_count = sizeof(frameworks) / sizeof(frameworks[0]);

    // Collect discovered models
    std::vector<rac_discovered_model_t> discovered;
    size_t unregistered = 0;

    std::lock_guard<std::mutex> lock(handle->mutex);

    for (size_t f = 0; f < framework_count; f++) {
        rac_inference_framework_t framework = frameworks[f];

        // Get framework directory path
        char framework_dir[1024];
        if (rac_model_paths_get_framework_directory(framework, framework_dir,
                                                    sizeof(framework_dir)) != RAC_SUCCESS) {
            continue;
        }

        // Check if framework directory exists
        if (callbacks->path_exists(framework_dir, callbacks->user_data) != RAC_TRUE) {
            continue;
        }

        // List model folders in this framework directory
        char** model_folders = nullptr;
        size_t folder_count = 0;

        if (callbacks->list_directory(framework_dir, &model_folders, &folder_count,
                                      callbacks->user_data) != RAC_SUCCESS) {
            continue;
        }

        for (size_t i = 0; i < folder_count; i++) {
            if (!model_folders[i])
                continue;

            // Skip hidden files
            if (model_folders[i][0] == '.')
                continue;

            const char* model_id = model_folders[i];

            // Build full path to model folder
            std::string model_path = std::string(framework_dir) + "/" + model_id;

            // Check if it's a directory
            if (callbacks->is_directory(model_path.c_str(), callbacks->user_data) != RAC_TRUE) {
                continue;
            }

            // Check if it contains valid model files
            if (!is_valid_model_folder(callbacks, model_path.c_str(), framework)) {
                continue;
            }

            // Check if this model is registered
            auto it = handle->models.find(model_id);
            if (it != handle->models.end()) {
                // Model is registered - check if it needs update
                rac_model_info_t* model = it->second;

                if (!model->local_path || strlen(model->local_path) == 0) {
                    // Update the local path
                    if (model->local_path) {
                        free(model->local_path);
                    }
                    model->local_path = rac_strdup(model_path.c_str());
                    model->updated_at = rac_get_current_time_ms() / 1000;
#ifdef RAC_HAVE_PROTOBUF
                    store_proto_snapshot_locked(handle, model_id, model,
                                                /*preserve_proto_only_fields=*/true);
#endif

                    // Add to discovered list
                    rac_discovered_model_t disc;
                    disc.model_id = rac_strdup(model_id);
                    disc.local_path = rac_strdup(model_path.c_str());
                    disc.framework = framework;
                    discovered.push_back(disc);

                    RAC_LOG_INFO("ModelRegistry", "Discovered downloaded model");
                }
            } else {
                // Model folder exists but not registered
                unregistered++;
                RAC_LOG_DEBUG("ModelRegistry", "Found unregistered model folder");
            }
        }

        if (callbacks->free_entries) {
            callbacks->free_entries(model_folders, folder_count, callbacks->user_data);
        }
    }

    // Build result
    out_result->discovered_count = discovered.size();
    out_result->unregistered_count = unregistered;

    if (!discovered.empty()) {
        out_result->discovered_models = static_cast<rac_discovered_model_t*>(
            malloc(sizeof(rac_discovered_model_t) * discovered.size()));
        if (out_result->discovered_models) {
            for (size_t i = 0; i < discovered.size(); i++) {
                out_result->discovered_models[i] = discovered[i];
            }
        }
    }

    RAC_LOG_INFO("ModelRegistry", "Model discovery complete");

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API - REFRESH (T4.9)
// =============================================================================

rac_result_t rac_model_registry_refresh(rac_model_registry_handle_t handle,
                                        rac_model_registry_refresh_opts_t opts) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("ModelRegistry",
                 "Refresh requested: remote=%d, rescan_local=%d, prune_orphans=%d",
                 static_cast<int>(opts.include_remote_catalog),
                 static_cast<int>(opts.rescan_local),
                 static_cast<int>(opts.prune_orphans));

    rac_result_t first_error = RAC_SUCCESS;

    // Step 1: Remote catalog refresh via model assignment manager.
    // The assignment manager delegates HTTP to whatever transport the SDK
    // wired up (libcurl in native builds, platform HTTP in WASM/JS).
    if (opts.include_remote_catalog == RAC_TRUE) {
        rac_model_info_t** remote_models = nullptr;
        size_t remote_count = 0;
        rac_result_t remote_rc =
            rac_model_assignment_fetch(RAC_TRUE, &remote_models, &remote_count);
        if (remote_rc == RAC_SUCCESS) {
            RAC_LOG_INFO("ModelRegistry", "Remote catalog refreshed (%zu models)", remote_count);
            if (remote_models) {
                rac_model_info_array_free(remote_models, remote_count);
            }
        } else {
            RAC_LOG_WARNING("ModelRegistry", "Remote catalog refresh failed: %d", remote_rc);
            if (first_error == RAC_SUCCESS) first_error = remote_rc;
        }
    }

    // Step 2: Rescan local filesystem and link discovered downloads.
    if (opts.rescan_local == RAC_TRUE) {
        if (opts.discovery_callbacks) {
            rac_discovery_result_t disc = {};
            rac_result_t rescan_rc =
                rac_model_registry_discover_downloaded(handle, opts.discovery_callbacks, &disc);
            if (rescan_rc == RAC_SUCCESS) {
                RAC_LOG_INFO("ModelRegistry",
                             "Local rescan complete (%zu discovered, %zu unregistered)",
                             disc.discovered_count, disc.unregistered_count);
            } else {
                RAC_LOG_WARNING("ModelRegistry", "Local rescan failed: %d", rescan_rc);
                if (first_error == RAC_SUCCESS) first_error = rescan_rc;
            }
            rac_discovery_result_free(&disc);
        } else {
            RAC_LOG_DEBUG("ModelRegistry",
                          "Rescan local requested but discovery_callbacks is NULL; skipping");
        }
    }

    // Step 3: Prune orphaned local_path entries.
    if (opts.prune_orphans == RAC_TRUE) {
        if (opts.discovery_callbacks && opts.discovery_callbacks->path_exists) {
            std::lock_guard<std::mutex> lock(handle->mutex);
            size_t pruned = 0;
            for (auto& pair : handle->models) {
                rac_model_info_t* model = pair.second;
                if (!model || !model->local_path || strlen(model->local_path) == 0) {
                    continue;
                }
                rac_bool_t exists = opts.discovery_callbacks->path_exists(
                    model->local_path, opts.discovery_callbacks->user_data);
                if (exists != RAC_TRUE) {
                    free(model->local_path);
                    model->local_path = nullptr;
                    model->updated_at = rac_get_current_time_ms() / 1000;
#ifdef RAC_HAVE_PROTOBUF
                    store_proto_snapshot_locked(handle, pair.first, model,
                                                /*preserve_proto_only_fields=*/true);
#endif
                    ++pruned;
                }
            }
            RAC_LOG_INFO("ModelRegistry", "Pruned %zu orphaned local_path entries", pruned);
        } else {
            RAC_LOG_DEBUG(
                "ModelRegistry",
                "Prune orphans requested but discovery_callbacks/path_exists is NULL; skipping");
        }
    }

    return first_error;
}

void rac_discovery_result_free(rac_discovery_result_t* result) {
    if (!result)
        return;

    if (result->discovered_models) {
        for (size_t i = 0; i < result->discovered_count; i++) {
            if (result->discovered_models[i].model_id) {
                free(const_cast<char*>(result->discovered_models[i].model_id));
            }
            if (result->discovered_models[i].local_path) {
                free(const_cast<char*>(result->discovered_models[i].local_path));
            }
        }
        free(result->discovered_models);
    }

    result->discovered_models = nullptr;
    result->discovered_count = 0;
    result->unregistered_count = 0;
}

// =============================================================================
// FETCH ASSIGNMENTS — Unified cross-SDK entry point (Task 5 / Web WASM)
// =============================================================================

rac_result_t rac_model_registry_fetch_assignments(rac_bool_t force_refresh,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    // Initialise caller outputs to safe defaults.
    if (out_models) *out_models = nullptr;
    if (out_count)  *out_count  = 0;

    // Delegate to the model assignment layer which handles caching, HTTP, and
    // JSON parsing.  If callbacks have not been set yet (e.g. offline WASM),
    // rac_model_assignment_fetch returns RAC_SUCCESS with zero models — that
    // is the correct behaviour for the Web SDK's offline path.
    rac_model_info_t** models = nullptr;
    size_t count = 0;

    rac_result_t rc = rac_model_assignment_fetch(force_refresh, &models, &count);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_WARNING("ModelRegistry", "rac_model_registry_fetch_assignments: fetch returned %d",
                        rc);
        return rc;
    }

    if (out_models) *out_models = models;
    else            rac_model_info_array_free(models, count);  // caller doesn't want the array

    if (out_count) *out_count = count;

    RAC_LOG_INFO("ModelRegistry", "rac_model_registry_fetch_assignments: fetched %zu models",
                 count);
    return RAC_SUCCESS;
}
