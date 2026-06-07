/**
 * @file model_registry_convert.cpp
 * @brief Model registry — proto<->C conversion, (de)serialization, parse helpers.
 *
 * SRP split of model_registry.cpp (pure code-motion). Owns the proto<->C
 * struct/enum mappers, the partial-update field-preservation merge, and the
 * proto parse/serialize helpers shared across the registry TUs (see
 * model_registry_internal.h). No behaviour change.
 */

#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_structured_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#include "model_registry_internal.h"

// Note: rac_strdup is declared in rac_types.h and implemented in rac_memory.cpp

namespace rac::infra::model_registry::detail {

rac_model_info_t* deep_copy_model(const rac_model_info_t* src) {
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

void free_model_info(rac_model_info_t* model) {
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
        free(static_cast<void*>(model->tags));
    }

    free(model);
}

}  // namespace rac::infra::model_registry::detail

#ifdef RAC_HAVE_PROTOBUF

namespace rac::infra::model_registry::detail {

// -----------------------------------------------------------------------------
// Single-TU enum / pattern mappers (internal linkage, used only by the proto<->C
// conversion functions below).
// -----------------------------------------------------------------------------

namespace {

ModelCategory model_category_to_proto(rac_model_category_t category) {
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

rac_model_category_t model_category_from_proto(ModelCategory category) {
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

ModelFormat model_format_to_proto(rac_model_format_t format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<ModelFormat>(value)
                                                       : runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

rac_model_format_t model_format_from_proto(ModelFormat format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<rac_model_format_t>(value)
                                                       : RAC_MODEL_FORMAT_UNKNOWN;
}

InferenceFramework inference_framework_to_proto(rac_inference_framework_t framework) {
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

rac_inference_framework_t inference_framework_from_proto(InferenceFramework framework) {
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

ModelSource model_source_to_proto(rac_model_source_t source) {
    switch (source) {
        case RAC_MODEL_SOURCE_LOCAL:
            return runanywhere::v1::MODEL_SOURCE_LOCAL;
        case RAC_MODEL_SOURCE_REMOTE:
        default:
            return runanywhere::v1::MODEL_SOURCE_REMOTE;
    }
}

rac_model_source_t model_source_from_proto(ModelSource source) {
    switch (source) {
        case runanywhere::v1::MODEL_SOURCE_LOCAL:
            return RAC_MODEL_SOURCE_LOCAL;
        case runanywhere::v1::MODEL_SOURCE_REMOTE:
        case runanywhere::v1::MODEL_SOURCE_UNSPECIFIED:
        default:
            return RAC_MODEL_SOURCE_REMOTE;
    }
}

ArchiveType archive_type_to_proto(rac_archive_type_t type) {
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

rac_archive_type_t archive_type_from_proto(ArchiveType type) {
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

ArchiveStructure archive_structure_to_proto(rac_archive_structure_t structure) {
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

rac_archive_structure_t archive_structure_from_proto(ArchiveStructure structure) {
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

ModelFileRole model_file_role_to_proto(rac_model_file_role_t role) {
    switch (role) {
        case RAC_MODEL_FILE_ROLE_PRIMARY_MODEL:
            return runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL;
        case RAC_MODEL_FILE_ROLE_COMPANION:
            return runanywhere::v1::MODEL_FILE_ROLE_COMPANION;
        case RAC_MODEL_FILE_ROLE_VISION_PROJECTOR:
            return runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR;
        case RAC_MODEL_FILE_ROLE_TOKENIZER:
            return runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER;
        case RAC_MODEL_FILE_ROLE_CONFIG:
            return runanywhere::v1::MODEL_FILE_ROLE_CONFIG;
        case RAC_MODEL_FILE_ROLE_VOCABULARY:
            return runanywhere::v1::MODEL_FILE_ROLE_VOCABULARY;
        case RAC_MODEL_FILE_ROLE_MERGES:
            return runanywhere::v1::MODEL_FILE_ROLE_MERGES;
        case RAC_MODEL_FILE_ROLE_LABELS:
            return runanywhere::v1::MODEL_FILE_ROLE_LABELS;
        case RAC_MODEL_FILE_ROLE_UNSPECIFIED:
        default:
            return runanywhere::v1::MODEL_FILE_ROLE_UNSPECIFIED;
    }
}

rac_model_file_role_t model_file_role_from_proto(ModelFileRole role) {
    switch (role) {
        case runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL:
            return RAC_MODEL_FILE_ROLE_PRIMARY_MODEL;
        case runanywhere::v1::MODEL_FILE_ROLE_COMPANION:
            return RAC_MODEL_FILE_ROLE_COMPANION;
        case runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR:
            return RAC_MODEL_FILE_ROLE_VISION_PROJECTOR;
        case runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER:
            return RAC_MODEL_FILE_ROLE_TOKENIZER;
        case runanywhere::v1::MODEL_FILE_ROLE_CONFIG:
            return RAC_MODEL_FILE_ROLE_CONFIG;
        case runanywhere::v1::MODEL_FILE_ROLE_VOCABULARY:
            return RAC_MODEL_FILE_ROLE_VOCABULARY;
        case runanywhere::v1::MODEL_FILE_ROLE_MERGES:
            return RAC_MODEL_FILE_ROLE_MERGES;
        case runanywhere::v1::MODEL_FILE_ROLE_LABELS:
            return RAC_MODEL_FILE_ROLE_LABELS;
        case runanywhere::v1::MODEL_FILE_ROLE_UNSPECIFIED:
        default:
            return RAC_MODEL_FILE_ROLE_UNSPECIFIED;
    }
}

bool copy_string_array_from_proto(const google::protobuf::RepeatedPtrField<std::string>& input,
                                  const char*** out_values, size_t* out_count) {
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
            free(static_cast<void*>(values));
            return false;
        }
    }

    *out_values = values;
    *out_count = count;
    return true;
}

rac_expected_model_files_t*
expected_files_from_patterns(const google::protobuf::RepeatedPtrField<std::string>& required,
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

void add_expected_patterns_to_single_file(const rac_expected_model_files_t* files,
                                          SingleFileArtifact* out) {
    if (!files || !out) {
        return;
    }
    for (size_t i = 0; i < files->required_pattern_count; ++i) {
        if (files->required_patterns[i])
            out->add_required_patterns(files->required_patterns[i]);
    }
    for (size_t i = 0; i < files->optional_pattern_count; ++i) {
        if (files->optional_patterns[i])
            out->add_optional_patterns(files->optional_patterns[i]);
    }
}

void add_expected_patterns_to_archive(const rac_expected_model_files_t* files,
                                      ArchiveArtifact* out) {
    if (!files || !out) {
        return;
    }
    for (size_t i = 0; i < files->required_pattern_count; ++i) {
        if (files->required_patterns[i])
            out->add_required_patterns(files->required_patterns[i]);
    }
    for (size_t i = 0; i < files->optional_pattern_count; ++i) {
        if (files->optional_patterns[i])
            out->add_optional_patterns(files->optional_patterns[i]);
    }
}

void add_file_descriptors_to_proto(const rac_model_artifact_info_t* artifact,
                                   MultiFileArtifact* out) {
    if (!artifact || !out || !artifact->file_descriptors) {
        return;
    }
    for (size_t i = 0; i < artifact->file_descriptor_count; ++i) {
        const rac_model_file_descriptor_t& in = artifact->file_descriptors[i];
        ModelFileDescriptor* file = out->add_files();
        // Emit the real URL when the descriptor carries one.
        // Previously this always emitted relative_path as the URL, so a
        // local filename like "lfm2-vl-1.2b-q4_k_m.gguf" was serialized as
        // ModelFileDescriptor.url and the planner downstream rejected it as
        // not http(s). Fall back to relative_path only when url is unset to
        // preserve legacy behaviour for callers that have not been updated.
        if (in.url && in.url[0] != '\0') {
            file->set_url(in.url);
        } else if (in.relative_path) {
            file->set_url(in.relative_path);
        }
        if (in.relative_path)
            file->set_relative_path(in.relative_path);
        if (in.destination_path) {
            file->set_filename(in.destination_path);
            file->set_destination_path(in.destination_path);
        }
        file->set_is_required(in.is_required == RAC_TRUE);
        file->set_role(model_file_role_to_proto(in.role));
    }
}

}  // namespace

// -----------------------------------------------------------------------------
// Cross-TU conversion / parse helpers (declared in model_registry_internal.h).
// -----------------------------------------------------------------------------

char* dup_optional_proto_string(const std::string& value) {
    return value.empty() ? nullptr : rac_strdup(value.c_str());
}

void overlay_struct_runtime_fields_to_proto(const rac_model_info_t* in, ModelInfo* out,
                                            bool overwrite_registry_state) {
    if (!in || !out) {
        return;
    }

    out->set_local_path(in->local_path ? in->local_path : "");
    out->set_updated_at_unix_ms(in->updated_at);
    if (in->last_used > 0) {
        out->set_last_used_at_unix_ms(in->last_used);
    }
    if (in->usage_count > 0) {
        out->set_usage_count(in->usage_count);
    }
    if (overwrite_registry_state) {
        overwrite_download_state_from_local_path(out);
    }
}

void model_info_to_proto(const rac_model_info_t* in, ModelInfo* out, bool overwrite_artifact,
                         bool overwrite_registry_state) {
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
    if (overwrite_registry_state) {
        overwrite_download_state_from_local_path(out);
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
            out->set_custom_strategy_id(
                in->artifact_info.strategy_id ? in->artifact_info.strategy_id : "");
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

bool apply_proto_artifact_to_model(const ModelInfo& proto, rac_model_info_t* model) {
    switch (proto.artifact_case()) {
        case ModelInfo::kSingleFile:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
            model->artifact_info.expected_files = expected_files_from_patterns(
                proto.single_file().required_patterns(), proto.single_file().optional_patterns());
            break;
        case ModelInfo::kArchive:
            model->artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
            model->artifact_info.archive_type = archive_type_from_proto(proto.archive().type());
            model->artifact_info.archive_structure =
                archive_structure_from_proto(proto.archive().structure());
            model->artifact_info.expected_files = expected_files_from_patterns(
                proto.archive().required_patterns(), proto.archive().optional_patterns());
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
                    const std::string relative =
                        file.has_relative_path() && !file.relative_path().empty()
                            ? file.relative_path()
                            : (!file.url().empty() ? file.url() : file.filename());
                    const std::string destination =
                        file.has_destination_path() && !file.destination_path().empty()
                            ? file.destination_path()
                            : file.filename();
                    out.relative_path = dup_optional_proto_string(relative);
                    out.destination_path = dup_optional_proto_string(destination);
                    out.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                    out.role = model_file_role_from_proto(file.role());
                    // Preserve ModelFileDescriptor.url through the
                    // registry round-trip. Previously this field was dropped,
                    // which caused the round-trip serializer to emit
                    // relative_path as the URL (i.e. a local filename pretending
                    // to be an http(s) URL), then the download planner's
                    // expected_files fallback rejected the model with
                    // "model.download_url must be an http(s) URL".
                    out.url = dup_optional_proto_string(file.url());
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

rac_model_info_t* model_info_from_proto(const ModelInfo& proto) {
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
    model->memory_required = proto.has_memory_required_bytes() ? proto.memory_required_bytes() : 0;
    model->last_used = proto.has_last_used_at_unix_ms() ? proto.last_used_at_unix_ms() : 0;
    model->usage_count = proto.has_usage_count() ? proto.usage_count() : 0;

    if (!model->id || !apply_proto_artifact_to_model(proto, model)) {
        rac_model_info_free(model);
        return nullptr;
    }

    return model;
}

rac_result_t proto_buffer_error(rac_proto_buffer_t* out_buffer, rac_result_t status,
                                const char* message) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return rac_proto_buffer_set_error(out_buffer, status,
                                      message ? message : rac_error_message(status));
}

rac_result_t parse_model_info_bytes(const uint8_t* proto_bytes, size_t proto_size, ModelInfo* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_result_t validation = rac_proto_bytes_validate(proto_bytes, proto_size);
    if (validation != RAC_SUCCESS) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!out->ParseFromArray(rac_proto_bytes_data_or_empty(proto_bytes, proto_size),
                             static_cast<int>(proto_size))) {
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (out->id().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

rac_result_t parse_model_query_bytes(const uint8_t* query_proto_bytes, size_t query_proto_size,
                                     ModelQuery* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_result_t validation = rac_proto_bytes_validate(query_proto_bytes, query_proto_size);
    if (validation != RAC_SUCCESS) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!out->ParseFromArray(rac_proto_bytes_data_or_empty(query_proto_bytes, query_proto_size),
                             static_cast<int>(query_proto_size))) {
        return RAC_ERROR_INVALID_FORMAT;
    }
    return RAC_SUCCESS;
}

void preserve_absent_proto_fields(const ModelInfo& existing, ModelInfo* incoming,
                                  bool preserve_empty_local_path) {
    if (!incoming) {
        return;
    }

    if (preserve_empty_local_path && incoming->local_path().empty() &&
        !existing.local_path().empty()) {
        incoming->set_local_path(existing.local_path());
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
    } else if (incoming->artifact_case() == ModelInfo::kMultiFile &&
               existing.artifact_case() == ModelInfo::kMultiFile) {
        // Per-descriptor merge for multi-file artifacts: re-registering a
        // catalog seed rebuilds the file descriptors from URL/filename but
        // does not carry the per-file local_path or checksum_sha256 that the
        // downloader populated. Match descriptors by URL and preserve those
        // runtime fields so the next launch finds the files on disk.
        const auto& existing_files = existing.multi_file().files();
        auto* incoming_files = incoming->mutable_multi_file()->mutable_files();
        for (int i = 0; i < incoming_files->size(); ++i) {
            ModelFileDescriptor* file = incoming_files->Mutable(i);
            if (file->url().empty()) {
                continue;
            }
            for (const ModelFileDescriptor& prior : existing_files) {
                if (prior.url() != file->url()) {
                    continue;
                }
                if (!file->has_local_path() && prior.has_local_path()) {
                    file->set_local_path(prior.local_path());
                }
                if (!file->has_checksum_sha256() && prior.has_checksum_sha256()) {
                    file->set_checksum_sha256(prior.checksum_sha256());
                }
                if (!file->has_size_bytes() && prior.has_size_bytes()) {
                    file->set_size_bytes(prior.size_bytes());
                }
                break;
            }
        }
    }
}

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_HAVE_PROTOBUF
