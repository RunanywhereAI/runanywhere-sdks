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
#include <filesystem>
#include <limits>
#include <map>
#include <mutex>
#include <new>
#include <ranges>
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
        free(static_cast<void*>(model->tags));
    }

    free(model);
}

#ifdef RAC_HAVE_PROTOBUF

namespace {

using runanywhere::v1::ArchiveArtifact;
using runanywhere::v1::ArchiveStructure;
using runanywhere::v1::ArchiveType;
using runanywhere::v1::DiscoveredModel;
using runanywhere::v1::InferenceFramework;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::ModelDeleteResult;
using runanywhere::v1::ModelDiscoveryRequest;
using runanywhere::v1::ModelDiscoveryResult;
using runanywhere::v1::ModelFileDescriptor;
using runanywhere::v1::ModelFileRole;
using runanywhere::v1::ModelFormat;
using runanywhere::v1::ModelGetRequest;
using runanywhere::v1::ModelGetResult;
using runanywhere::v1::ModelImportRequest;
using runanywhere::v1::ModelImportResult;
using runanywhere::v1::ModelInfo;
using runanywhere::v1::ModelInfoList;
using runanywhere::v1::ModelListRequest;
using runanywhere::v1::ModelListResult;
using runanywhere::v1::ModelQuery;
using runanywhere::v1::ModelQuerySortField;
using runanywhere::v1::ModelRegistryRefreshRequest;
using runanywhere::v1::ModelRegistryRefreshResult;
using runanywhere::v1::ModelRegistryStatus;
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
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<ModelFormat>(value)
                                                       : runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

static rac_model_format_t model_format_from_proto(ModelFormat format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<rac_model_format_t>(value)
                                                       : RAC_MODEL_FORMAT_UNKNOWN;
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

static rac_inference_framework_t inference_framework_from_proto(InferenceFramework framework) {
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

static ModelFileRole model_file_role_to_proto(rac_model_file_role_t role) {
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

static rac_model_file_role_t model_file_role_from_proto(ModelFileRole role) {
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

static char* dup_optional_proto_string(const std::string& value) {
    return value.empty() ? nullptr : rac_strdup(value.c_str());
}

static bool
copy_string_array_from_proto(const google::protobuf::RepeatedPtrField<std::string>& input,
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

static rac_expected_model_files_t*
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

static void add_expected_patterns_to_single_file(const rac_expected_model_files_t* files,
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

static void add_expected_patterns_to_archive(const rac_expected_model_files_t* files,
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

static void add_file_descriptors_to_proto(const rac_model_artifact_info_t* artifact,
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

static bool has_nonempty_local_path(const ModelInfo& model) {
    return !model.local_path().empty();
}

static bool registry_status_is_downloaded(ModelRegistryStatus status) {
    return status == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED ||
           status == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED;
}

static bool model_is_downloaded_from_fields(const ModelInfo& model) {
    if (has_nonempty_local_path(model)) {
        return true;
    }
    if (model.has_is_downloaded()) {
        return model.is_downloaded();
    }
    if (model.has_registry_status()) {
        return registry_status_is_downloaded(model.registry_status());
    }
    return false;
}

static ModelRegistryStatus effective_registry_status(const ModelInfo& model) {
    if (model.has_registry_status()) {
        return model.registry_status();
    }
    return model_is_downloaded_from_fields(model)
               ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
               : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED;
}

static void normalize_model_registry_state(ModelInfo* model) {
    if (!model) {
        return;
    }

    const bool downloaded = model_is_downloaded_from_fields(*model);
    if (!model->has_is_downloaded()) {
        model->set_is_downloaded(downloaded);
    }
    if (!model->has_is_available()) {
        model->set_is_available(downloaded);
    }
    if (!model->has_registry_status()) {
        model->set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                              : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    }
}

static void overwrite_download_state_from_local_path(ModelInfo* model) {
    if (!model) {
        return;
    }

    const bool downloaded = has_nonempty_local_path(*model);
    model->set_is_downloaded(downloaded);
    model->set_is_available(downloaded);

    const ModelRegistryStatus current = effective_registry_status(*model);
    if (downloaded) {
        if (current != runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED &&
            current != runanywhere::v1::MODEL_REGISTRY_STATUS_LOADING &&
            current != runanywhere::v1::MODEL_REGISTRY_STATUS_ERROR) {
            model->set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
        }
    } else if (registry_status_is_downloaded(current) ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADING ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADING ||
               current == runanywhere::v1::MODEL_REGISTRY_STATUS_UNSPECIFIED) {
        model->set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    }
}

static void overlay_struct_runtime_fields_to_proto(const rac_model_info_t* in, ModelInfo* out,
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

static void model_info_to_proto(const rac_model_info_t* in, ModelInfo* out, bool overwrite_artifact,
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

static bool apply_proto_artifact_to_model(const ModelInfo& proto, rac_model_info_t* model) {
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
    model->memory_required = proto.has_memory_required_bytes() ? proto.memory_required_bytes() : 0;
    model->last_used = proto.has_last_used_at_unix_ms() ? proto.last_used_at_unix_ms() : 0;
    model->usage_count = proto.has_usage_count() ? proto.usage_count() : 0;

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

    return rac_proto_buffer_copy_to_raw(reinterpret_cast<const uint8_t*>(bytes.data()),
                                        bytes.size(), proto_bytes_out, proto_size_out);
}

template <typename ProtoMessage>
static rac_result_t serialize_proto_to_buffer(const ProtoMessage& message,
                                              rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return rac_proto_buffer_set_error(out_buffer, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize registry proto result");
    }

    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_buffer);
}

static rac_result_t proto_buffer_error(rac_proto_buffer_t* out_buffer, rac_result_t status,
                                       const char* message) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return rac_proto_buffer_set_error(out_buffer, status,
                                      message ? message : rac_error_message(status));
}

template <typename ProtoMessage>
static rac_result_t parse_proto_message_bytes(const uint8_t* proto_bytes, size_t proto_size,
                                              ProtoMessage* out, const char* message_name,
                                              rac_proto_buffer_t* error_out) {
    if (!out) {
        return proto_buffer_error(error_out, RAC_ERROR_INVALID_ARGUMENT,
                                  "output proto message is required");
    }

    rac_result_t validation = rac_proto_bytes_validate(proto_bytes, proto_size);
    if (validation != RAC_SUCCESS) {
        return proto_buffer_error(error_out, validation, "proto bytes are null or too large");
    }

    if (!out->ParseFromArray(rac_proto_bytes_data_or_empty(proto_bytes, proto_size),
                             static_cast<int>(proto_size))) {
        std::string message = "failed to parse ";
        message += message_name ? message_name : "proto message";
        return proto_buffer_error(error_out, RAC_ERROR_INVALID_FORMAT, message.c_str());
    }
    return RAC_SUCCESS;
}

static rac_result_t parse_model_info_bytes(const uint8_t* proto_bytes, size_t proto_size,
                                           ModelInfo* out) {
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

static rac_result_t parse_model_query_bytes(const uint8_t* query_proto_bytes,
                                            size_t query_proto_size, ModelQuery* out) {
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

// Merge fields the caller left unset from `existing` into `incoming`.
//
// `preserve_empty_local_path` encodes the two distinct caller contracts:
//   - update_proto is a PARTIAL merge: an absent/empty local_path means "leave
//     the existing one alone", so pass true and we carry a non-empty existing
//     path forward. ModelInfo.local_path is a presence-less proto3 string
//     (tag 7, no `optional`), so an unset field and an explicit "" are wire-
//     identical; the partial-merge entry point therefore treats empty as
//     "keep existing".
//   - register_proto is an AUTHORITATIVE replace / explicit reset escape hatch:
//     an empty local_path is a deliberate clear that must win, so pass false
//     and we never overwrite the incoming (possibly empty) path.
static void preserve_absent_proto_fields(const ModelInfo& existing, ModelInfo* incoming,
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

static rac_result_t store_proto_snapshot_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id,
                                                const rac_model_info_t* model,
                                                bool preserve_proto_only_fields,
                                                bool overwrite_registry_state) {
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

    if (parsed_existing) {
        overlay_struct_runtime_fields_to_proto(model, &snapshot, overwrite_registry_state);
    } else {
        model_info_to_proto(model, &snapshot,
                            /*overwrite_artifact=*/true, overwrite_registry_state);
    }
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
    normalize_model_registry_state(&snapshot);
    overlay_struct_runtime_fields_to_proto(it->second, &snapshot,
                                           /*overwrite_registry_state=*/false);
    if (!snapshot.SerializeToString(&handle->model_proto_bytes[model_id])) {
        handle->model_proto_bytes.erase(model_id);
        return RAC_ERROR_UNKNOWN;
    }
    return RAC_SUCCESS;
}

static ModelInfo model_snapshot_locked(rac_model_registry_handle_t handle,
                                       const std::string& model_id, const rac_model_info_t* model) {
    ModelInfo snapshot;
    auto proto_it = handle->model_proto_bytes.find(model_id);
    if (proto_it != handle->model_proto_bytes.end() && snapshot.ParseFromString(proto_it->second)) {
        overlay_struct_runtime_fields_to_proto(model, &snapshot,
                                               /*overwrite_registry_state=*/false);
    } else {
        snapshot.Clear();
        model_info_to_proto(model, &snapshot,
                            /*overwrite_artifact=*/true,
                            /*overwrite_registry_state=*/true);
    }
    return snapshot;
}

static rac_result_t model_to_proto_bytes_locked(rac_model_registry_handle_t handle,
                                                const std::string& model_id,
                                                const rac_model_info_t* model,
                                                uint8_t** proto_bytes_out, size_t* proto_size_out) {
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
    return model_is_downloaded_from_fields(model);
}

static bool model_is_available_proto(const ModelInfo& model) {
    if (model.has_is_available()) {
        return model.is_available();
    }
    return model_is_downloaded_proto(model);
}

static bool model_matches_search_text(const ModelInfo& model, const std::string& needle_lower) {
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
                contains_text_case_insensitive(file.checksum_sha256(), needle_lower)) {
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
    if (query.has_registry_status() &&
        effective_registry_status(model) != query.registry_status()) {
        return false;
    }
    if (query.has_downloaded_only() && query.downloaded_only() &&
        !model_is_downloaded_proto(model)) {
        return false;
    }
    if (query.has_available_only() && query.available_only() && !model_is_available_proto(model)) {
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

static int compare_models_by_sort_field(const ModelInfo& lhs, const ModelInfo& rhs,
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

    std::ranges::sort(*models,
                      [sort_field, descending](const ModelInfo& lhs, const ModelInfo& rhs) {
                          int result = compare_models_by_sort_field(lhs, rhs, sort_field);
                          if (result == 0) {
                              return lhs.id() < rhs.id();
                          }
                          return descending ? result > 0 : result < 0;
                      });
}

static void append_query_results_locked(rac_model_registry_handle_t handle, const ModelQuery& query,
                                        ModelInfoList* out) {
    if (!out) {
        return;
    }

    std::vector<ModelInfo> matches;
    for (const auto& pair : handle->models) {
        ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
        normalize_model_registry_state(&snapshot);
        if (model_matches_query(snapshot, query)) {
            matches.push_back(std::move(snapshot));
        }
    }
    sort_query_results(query, &matches);
    for (ModelInfo& model : matches) {
        out->add_models()->Swap(&model);
    }
}

static std::vector<ModelInfo> collect_model_snapshots_locked(rac_model_registry_handle_t handle) {
    std::vector<ModelInfo> models;
    if (!handle) {
        return models;
    }

    models.reserve(handle->models.size());
    for (const auto& pair : handle->models) {
        ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
        normalize_model_registry_state(&snapshot);
        models.push_back(std::move(snapshot));
    }
    return models;
}

static std::vector<ModelInfo> query_model_snapshots_locked(rac_model_registry_handle_t handle,
                                                           const ModelQuery& query) {
    std::vector<ModelInfo> matches;
    if (!handle) {
        return matches;
    }

    for (ModelInfo& model : collect_model_snapshots_locked(handle)) {
        if (model_matches_query(model, query)) {
            matches.push_back(std::move(model));
        }
    }
    sort_query_results(query, &matches);
    return matches;
}

static void move_models_to_list(std::vector<ModelInfo>* models, ModelInfoList* out) {
    if (!models || !out) {
        return;
    }
    for (ModelInfo& model : *models) {
        out->add_models()->Swap(&model);
    }
}

struct ModelCounts {
    int32_t total{0};
    int32_t downloaded{0};
    int32_t available{0};
    int32_t errors{0};
};

static ModelCounts count_models(const std::vector<ModelInfo>& models) {
    ModelCounts counts;
    counts.total = static_cast<int32_t>(models.size());
    for (const ModelInfo& model : models) {
        if (model_is_downloaded_proto(model)) {
            ++counts.downloaded;
        }
        if (model_is_available_proto(model)) {
            ++counts.available;
        }
        if (effective_registry_status(model) == runanywhere::v1::MODEL_REGISTRY_STATUS_ERROR) {
            ++counts.errors;
        }
    }
    return counts;
}

static bool model_is_built_in(const ModelInfo& model) {
    return (model.has_artifact_type() &&
            model.artifact_type() == runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN) ||
           model.artifact_case() == ModelInfo::kBuiltIn ||
           model.source() == runanywhere::v1::MODEL_SOURCE_BUILT_IN;
}

static bool path_matches_roots(const std::string& path,
                               const google::protobuf::RepeatedPtrField<std::string>& roots) {
    if (roots.empty()) {
        return true;
    }
    for (const std::string& root : roots) {
        if (root.empty() || path.starts_with(root)) {
            return true;
        }
    }
    return false;
}

static std::string basename_from_path(const std::string& path) {
    const size_t slash = path.find_last_of("/\\");
    if (slash == std::string::npos) {
        return path;
    }
    if (slash + 1 >= path.size()) {
        return "";
    }
    return path.substr(slash + 1);
}

static bool ends_with(const std::string& value, const std::string& suffix) {
    return value.ends_with(suffix);
}

static std::string strip_known_model_extension(const std::string& basename) {
    std::string lower = lowercase_copy(basename);
    const char* archive_suffixes[] = {".tar.gz", ".tar.bz2", ".tar.xz"};
    for (const char* suffix : archive_suffixes) {
        if (ends_with(lower, suffix)) {
            return basename.substr(0, basename.size() - std::strlen(suffix));
        }
    }

    const size_t dot = basename.find_last_of('.');
    if (dot == std::string::npos || dot == 0) {
        return basename;
    }
    return basename.substr(0, dot);
}

static ModelFormat infer_format_from_path(const std::string& path) {
    const std::string lower = lowercase_copy(path);
    if (ends_with(lower, ".gguf"))
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    if (ends_with(lower, ".ggml"))
        return runanywhere::v1::MODEL_FORMAT_GGML;
    if (ends_with(lower, ".onnx"))
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    if (ends_with(lower, ".ort"))
        return runanywhere::v1::MODEL_FORMAT_ORT;
    if (ends_with(lower, ".bin"))
        return runanywhere::v1::MODEL_FORMAT_BIN;
    if (ends_with(lower, ".tflite"))
        return runanywhere::v1::MODEL_FORMAT_TFLITE;
    if (ends_with(lower, ".safetensors"))
        return runanywhere::v1::MODEL_FORMAT_SAFETENSORS;
    if (ends_with(lower, ".mlmodel"))
        return runanywhere::v1::MODEL_FORMAT_MLMODEL;
    if (ends_with(lower, ".mlpackage"))
        return runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    if (ends_with(lower, ".zip"))
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    if (ends_with(lower, ".tar.gz") || ends_with(lower, ".tar.bz2") ||
        ends_with(lower, ".tar.xz")) {
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    }
    return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

static InferenceFramework infer_framework_from_format(ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_GGUF:
        case runanywhere::v1::MODEL_FORMAT_GGML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case runanywhere::v1::MODEL_FORMAT_ONNX:
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE;
        case runanywhere::v1::MODEL_FORMAT_COREML:
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

// =============================================================================
// FILESYSTEM RECONCILIATION (cold-launch discovery)
// =============================================================================
// When the SDK process starts, the in-memory registry is empty. Platform SDKs
// re-seed entries via registerModel(url, ...) which only carry download_url,
// never local_path. So even though the user's previously downloaded model
// files still exist under {base_dir}/RunAnywhere/Models/{framework}/{id}/,
// the default discover path skips every entry with an empty local_path.
//
// This helper walks the canonical on-disk layout that rac_model_paths_*
// defines, and for each registry entry whose local_path is still empty, it
// checks whether the matching <framework>/<id>/ directory exists and contains
// at least one recognizable model file. When so, it rewrites local_path onto
// the entry so the existing discover loop reports it as linked.
//
// This mirrors the pre-v2 Swift ModelInfoService.discoverDownloadedModels()
// behavior behind the shared C ABI so every SDK benefits once.

// Forward declaration — defined later in this TU. Reused here so cold-launch
// reconciliation enumerates folders through the platform adapter (works on
// native AND Web/OPFS, where std::filesystem sees nothing).
rac_result_t list_directory_via_adapter(const rac_platform_adapter_t* adapter, const char* dir_path,
                                        std::vector<rac_directory_entry_t>* out_entries);

// Recognize a model file purely by extension (ModelFormat-agnostic).
static bool is_recognizable_model_filename(const std::string& name) {
    const size_t dot = name.find_last_of('.');
    if (dot == std::string::npos) {
        return false;
    }
    const std::string ext = lowercase_copy(name.substr(dot + 1));
    return ext == "gguf" || ext == "ggml" || ext == "onnx" || ext == "ort" || ext == "bin" ||
           ext == "mlmodel" || ext == "mlpackage" || ext == "mlmodelc" || ext == "tflite" ||
           ext == "safetensors";
}

// Does `dir` (one level, plus one nested level for archive-extracted layouts
// like sherpa) contain a recognizable model file? Enumerates through the
// platform adapter so this works identically on native and Web/OPFS —
// std::filesystem cannot see the OPFS virtual filesystem, which is why the Web
// SDK previously needed its own hydrateModelRegistry pass.
static bool directory_contains_recognizable_model_file(const std::string& dir) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter || !adapter->file_list_directory) {
        RAC_LOG_WARNING("ModelRegistry",
                        "file_list_directory adapter slot is NULL — cannot reconcile '%s'",
                        dir.c_str());
        return false;
    }
    std::vector<rac_directory_entry_t> entries;
    if (list_directory_via_adapter(adapter, dir.c_str(), &entries) != RAC_SUCCESS) {
        return false;
    }
    for (const rac_directory_entry_t& entry : entries) {
        if (!entry.is_dir) {
            if (is_recognizable_model_filename(entry.name)) {
                return true;
            }
            continue;
        }
        // One level of recursion for nested model folders.
        std::vector<rac_directory_entry_t> nested;
        const std::string subdir = dir + "/" + entry.name;
        if (list_directory_via_adapter(adapter, subdir.c_str(), &nested) == RAC_SUCCESS) {
            for (const rac_directory_entry_t& sub : nested) {
                if (!sub.is_dir && is_recognizable_model_filename(sub.name)) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Returns the canonical on-disk folder for a model id:
//   {base_dir}/RunAnywhere/Models/{framework_raw_value}/{model_id}
// Returns an empty path if base_dir is not configured. Delegates to
// rac_model_paths_get_model_folder (the single authority for path layout)
// rather than hand-concatenating path components — any future change to the
// canonical layout only needs to happen in one place.
static std::filesystem::path canonical_model_folder_for(const std::string& model_id,
                                                        rac_inference_framework_t framework) {
    namespace fs = std::filesystem;
    if (model_id.empty()) {
        return fs::path{};
    }
    char buffer[4096];
    rac_result_t rc =
        rac_model_paths_get_model_folder(model_id.c_str(), framework, buffer, sizeof(buffer));
    if (rc != RAC_SUCCESS) {
        return fs::path{};
    }
    return {buffer};
}

// Attempt to link a single registry entry to its canonical on-disk folder.
// Preconditions: caller holds the registry mutex. The entry's local_path must
// currently be empty. Returns true when a matching folder exists and local_path
// has been rewritten (legacy struct + proto snapshot). Used by both the
// per-save fast path (rac_model_registry_save below) and the bulk discovery
// sweep (reconcile_registry_with_filesystem_locked) so ordering of
// registerModel() vs rac_model_paths_set_base_dir() no longer matters.
static bool try_reconcile_model_local_path_locked(rac_model_registry_handle_t handle,
                                                  const std::string& model_id,
                                                  rac_model_info_t* model) {
    if (!handle || !model || !model->id) {
        return false;
    }
    if (model->local_path && strlen(model->local_path) > 0) {
        return false;
    }
    const char* base = rac_model_paths_get_base_dir();
    if (!base || *base == '\0') {
        return false;
    }
    const std::filesystem::path folder = canonical_model_folder_for(model->id, model->framework);
    if (folder.empty() || !directory_contains_recognizable_model_file(folder.generic_string())) {
        return false;
    }

    const std::string folder_str = folder.generic_string();

    // Update legacy struct
    if (model->local_path) {
        free(model->local_path);
    }
    model->local_path = rac_strdup(folder_str.c_str());
    model->updated_at = rac_get_current_time_ms() / 1000;

    // Update proto snapshot
    ModelInfo snapshot = model_snapshot_locked(handle, model_id, model);
    snapshot.set_local_path(folder_str);
    overwrite_download_state_from_local_path(&snapshot);
    std::string serialized;
    if (snapshot.SerializeToString(&serialized)) {
        handle->model_proto_bytes[model_id] = std::move(serialized);
    }

    RAC_LOG_DEBUG("ModelRegistry", "Reconciled '%s' with on-disk folder: %s", model->id,
                  folder_str.c_str());
    return true;
}

// Walks the on-disk canonical layout and for every registry entry that
// currently has an empty local_path but has a matching
// {base_dir}/RunAnywhere/Models/{framework}/{id}/ folder containing at least
// one recognizable model file, rewrites local_path back onto the entry. Also
// normalizes download state flags via overwrite_download_state_from_local_path.
// Returns the number of entries that were linked.
static int32_t reconcile_registry_with_filesystem_locked(rac_model_registry_handle_t handle) {
    if (!handle) {
        return 0;
    }
    const char* base = rac_model_paths_get_base_dir();
    if (!base || *base == '\0') {
        return 0;
    }

    int32_t linked = 0;
    for (auto& pair : handle->models) {
        if (try_reconcile_model_local_path_locked(handle, pair.first, pair.second)) {
            ++linked;
        }
    }
    return linked;
}

static int64_t imported_size_for_request(const ModelImportRequest& request,
                                         const ModelInfo& model) {
    int64_t total = 0;
    for (const ModelFileDescriptor& file : request.files()) {
        if (file.has_size_bytes() && file.size_bytes() > 0) {
            total += file.size_bytes();
        }
    }
    if (total > 0) {
        return total;
    }
    return model.download_size_bytes() > 0 ? model.download_size_bytes() : 0;
}

static bool get_model_snapshot_by_id(rac_model_registry_handle_t handle,
                                     const std::string& model_id, ModelInfo* out) {
    if (!handle || !out) {
        return false;
    }
    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->models.find(model_id);
    if (it == handle->models.end()) {
        return false;
    }
    *out = model_snapshot_locked(handle, model_id, it->second);
    normalize_model_registry_state(out);
    return true;
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

// Shared save implementation. `preserve_empty_local_path` controls the
// legacy "registerModel() passes localPath=nil, keep the existing one"
// heuristic: the C struct cannot carry proto field-presence, so for the
// non-proto callers (Swift/Kotlin/etc. registerModel and platform/auto
// registration) an empty incoming local_path is treated as "unset" and the
// existing path is kept. The proto register/update paths set this to false
// because they have already resolved local_path presence-aware in the proto
// domain (preserve_absent_proto_fields), so an empty local_path there is an
// *explicit* reset that must win.
static rac_result_t save_model_info_impl(rac_model_registry_handle_t handle,
                                         const rac_model_info_t* model,
                                         bool preserve_empty_local_path) {
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
        bool should_preserve_path =
            preserve_empty_local_path && (existing_local_path != nullptr) &&
            strlen(existing_local_path) > 0 &&
            (model->local_path == nullptr || strlen(model->local_path) == 0);

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
        rac_result_t proto_rc = store_proto_snapshot_locked(handle, model_id, stored->second,
                                                            /*preserve_proto_only_fields=*/false,
                                                            /*overwrite_registry_state=*/true);
        if (proto_rc != RAC_SUCCESS) {
            return proto_rc;
        }

        // Self-healing reconcile: if the incoming entry has no local_path but
        // the canonical {base_dir}/RunAnywhere/Models/{framework}/{id}/ folder
        // already exists on disk (typical for the 2nd app launch after a
        // previous download), relink local_path immediately. This removes the
        // ordering dependency between registerModel() and the one-shot
        // discoverDownloadedModels() sweep in Phase 2.
        try_reconcile_model_local_path_locked(handle, model_id, stored->second);
    }
#endif

    RAC_LOG_DEBUG("ModelRegistry", "Model saved");

    return RAC_SUCCESS;
}

rac_result_t rac_model_registry_save(rac_model_registry_handle_t handle,
                                     const rac_model_info_t* model) {
    // Legacy / non-proto callers: keep the "empty local_path means unset, so
    // preserve the existing one" behaviour.
    return save_model_info_impl(handle, model, /*preserve_empty_local_path=*/true);
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
            if (search_path.starts_with(model_path) || model_path.starts_with(search_path)) {
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
            free(static_cast<void*>(*out_models));
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
            free(static_cast<void*>(*out_models));
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
                                       /*preserve_proto_only_fields=*/true,
                                       /*overwrite_registry_state=*/false);
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
            free(static_cast<void*>(*out_models));
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
                                       /*preserve_proto_only_fields=*/true,
                                       /*overwrite_registry_state=*/true);
#else
    return RAC_SUCCESS;
#endif
}

// =============================================================================
// PUBLIC API - PROTO-BYTE MODEL INFO
// =============================================================================

rac_result_t rac_model_registry_register_proto(rac_model_registry_handle_t handle,
                                               const uint8_t* proto_bytes, size_t proto_size) {
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

    // Merge-not-replace: when re-registering an existing model_id (catalog
    // re-seed on app launch), preserve runtime fields the caller doesn't set
    // — local_path, is_downloaded, checksum_sha256, expected_files,
    // multi_file.files[*].local_path, etc. Without this, a registerModel()
    // call that only carries factory defaults clobbers download progress and
    // forces the user to re-download on every launch. Same merge contract as
    // rac_model_registry_update_proto (see preserve_absent_proto_fields).
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        auto existing_it = handle->models.find(proto_model.id());
        if (existing_it != handle->models.end()) {
            ModelInfo existing =
                model_snapshot_locked(handle, proto_model.id(), existing_it->second);
            // register_proto is an authoritative replace: an explicit empty
            // local_path is a deliberate reset that must win (override
            // escape hatch), so do NOT preserve an empty path.
            preserve_absent_proto_fields(existing, &proto_model,
                                         /*preserve_empty_local_path=*/false);
        }
    }

    normalize_model_registry_state(&proto_model);

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    // The proto register/update paths carry a caller-authored ModelInfo, so an
    // empty local_path here is an explicit reset that must win. The merge-on-
    // re-seed behaviour lives upstream (rac_register_model_from_url_proto carries
    // the existing runtime fields forward before calling this), so the legacy
    // C-struct "empty means keep the old path" heuristic must NOT fire here.
    rac_result_t save_rc = save_model_info_impl(handle, model,
                                                /*preserve_empty_local_path=*/false);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_update_proto(rac_model_registry_handle_t handle,
                                             const uint8_t* proto_bytes, size_t proto_size) {
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
        // update_proto is a partial merge: a field the caller left unset (or an
        // empty local_path, which is wire-indistinguishable from unset for this
        // presence-less proto3 string) must preserve the existing value.
        preserve_absent_proto_fields(existing, &proto_model,
                                     /*preserve_empty_local_path=*/true);
    }
    normalize_model_registry_state(&proto_model);

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    // The proto register/update paths carry a caller-authored ModelInfo, so an
    // empty local_path here is an explicit reset that must win. The merge-on-
    // re-seed behaviour lives upstream (rac_register_model_from_url_proto carries
    // the existing runtime fields forward before calling this), so the legacy
    // C-struct "empty means keep the old path" heuristic must NOT fire here.
    rac_result_t save_rc = save_model_info_impl(handle, model,
                                                /*preserve_empty_local_path=*/false);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_get_proto(rac_model_registry_handle_t handle, const char* model_id,
                                          uint8_t** proto_bytes_out, size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
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

    return model_to_proto_bytes_locked(handle, model_id, it->second, proto_bytes_out,
                                       proto_size_out);
#endif
}

rac_result_t rac_model_registry_list_proto(rac_model_registry_handle_t handle,
                                           uint8_t** proto_bytes_out, size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
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
                                            size_t query_proto_size, uint8_t** proto_bytes_out,
                                            size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)query_proto_bytes;
    (void)query_proto_size;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelQuery query;
    rac_result_t parse_rc = parse_model_query_bytes(query_proto_bytes, query_proto_size, &query);
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
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
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

rac_result_t rac_model_registry_register_proto_buffer(rac_model_registry_handle_t handle,
                                                      const uint8_t* proto_bytes, size_t proto_size,
                                                      rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfo parsed;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &parsed);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelInfo"
                                      : "ModelInfo.id is required");
    }

    rac_result_t rc = rac_model_registry_register_proto(handle, proto_bytes, proto_size);
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, parsed.id(), &saved)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "registered model was not found");
    }
    return serialize_proto_to_buffer(saved, out_model);
#endif
}

rac_result_t rac_model_registry_update_proto_buffer(rac_model_registry_handle_t handle,
                                                    const uint8_t* proto_bytes, size_t proto_size,
                                                    rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfo parsed;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &parsed);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelInfo"
                                      : "ModelInfo.id is required");
    }

    rac_result_t rc = rac_model_registry_update_proto(handle, proto_bytes, proto_size);
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, parsed.id(), &saved)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "updated model was not found");
    }
    return serialize_proto_to_buffer(saved, out_model);
#endif
}

rac_result_t rac_model_registry_get_proto_buffer(rac_model_registry_handle_t handle,
                                                 const char* model_id,
                                                 rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle || !model_id) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle and model_id are required");
    }

    ModelInfo model;
    if (!get_model_snapshot_by_id(handle, model_id, &model)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "model not found");
    }
    return serialize_proto_to_buffer(model, out_model);
#endif
}

rac_result_t rac_model_registry_list_proto_buffer(rac_model_registry_handle_t handle,
                                                  rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_models, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        std::vector<ModelInfo> models = collect_model_snapshots_locked(handle);
        move_models_to_list(&models, &list);
    }
    return serialize_proto_to_buffer(list, out_models);
#endif
}

rac_result_t rac_model_registry_query_proto_buffer(rac_model_registry_handle_t handle,
                                                   const uint8_t* query_proto_bytes,
                                                   size_t query_proto_size,
                                                   rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)query_proto_bytes;
    (void)query_proto_size;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_models, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelQuery query;
    rac_result_t parse_rc = parse_model_query_bytes(query_proto_bytes, query_proto_size, &query);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_models, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelQuery"
                                      : "invalid ModelQuery bytes");
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        std::vector<ModelInfo> models = query_model_snapshots_locked(handle, query);
        move_models_to_list(&models, &list);
    }
    return serialize_proto_to_buffer(list, out_models);
#endif
}

rac_result_t rac_model_registry_list_downloaded_proto_buffer(rac_model_registry_handle_t handle,
                                                             rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    ModelQuery query;
    query.set_downloaded_only(true);
    std::string bytes;
    if (!query.SerializeToString(&bytes)) {
        return proto_buffer_error(out_models, RAC_ERROR_ENCODING_ERROR,
                                  "failed to serialize downloaded-only query");
    }
    return rac_model_registry_query_proto_buffer(
        handle, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), out_models);
#endif
}

rac_result_t rac_model_registry_remove_proto_buffer(rac_model_registry_handle_t handle,
                                                    const char* model_id,
                                                    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle || !model_id || model_id[0] == '\0') {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle and model_id are required");
    }

    ModelDeleteResult result;
    result.set_model_id(model_id);
    rac_result_t rc = rac_model_registry_remove(handle, model_id);
    if (rc == RAC_SUCCESS) {
        result.set_success(true);
        result.set_registry_updated(true);
        result.set_files_deleted(false);
    } else {
        result.set_success(false);
        result.set_registry_updated(false);
        result.set_files_deleted(false);
        result.set_error_message(rac_error_message(rc));
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_get_model_proto(rac_model_registry_handle_t handle,
                                                const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelGetRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelGetRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }
    if (request.model_id().empty()) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "ModelGetRequest.model_id is required");
    }

    ModelGetResult result;
    ModelInfo model;
    if (get_model_snapshot_by_id(handle, request.model_id(), &model)) {
        result.set_found(true);
        result.mutable_model()->CopyFrom(model);
    } else {
        result.set_found(false);
        result.set_error_message("model not found");
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_list_models_proto(rac_model_registry_handle_t handle,
                                                  const uint8_t* request_proto_bytes,
                                                  size_t request_proto_size,
                                                  rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelListRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelListRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    std::vector<ModelInfo> all_models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        all_models = collect_model_snapshots_locked(handle);
    }

    std::vector<ModelInfo> filtered;
    if (request.has_query()) {
        for (const ModelInfo& model : all_models) {
            if (model_matches_query(model, request.query())) {
                filtered.push_back(model);
            }
        }
        sort_query_results(request.query(), &filtered);
    } else {
        filtered = all_models;
    }

    const ModelCounts all_counts = count_models(all_models);
    const ModelCounts filtered_counts = count_models(filtered);

    ModelListResult result;
    result.set_success(true);
    move_models_to_list(&filtered, result.mutable_models());
    if (request.include_counts()) {
        result.set_total_count(all_counts.total);
        result.set_downloaded_count(filtered_counts.downloaded);
        result.set_available_count(filtered_counts.available);
        result.set_filtered_count(filtered_counts.total);
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_import_proto(rac_model_registry_handle_t handle,
                                             const uint8_t* request_proto_bytes,
                                             size_t request_proto_size,
                                             rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelImportRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelImportRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    ModelImportResult result;
    ModelInfo model;
    if (request.has_model()) {
        model.CopyFrom(request.model());
    }

    const std::string source_path = request.source_path();
    if (model.id().empty()) {
        const std::string base = strip_known_model_extension(basename_from_path(source_path));
        if (base.empty()) {
            result.set_success(false);
            result.set_error_message("ModelImportRequest.model.id or source_path is required");
            return serialize_proto_to_buffer(result, out_result);
        }
        model.set_id(base);
    }
    if (model.name().empty()) {
        model.set_name(model.id());
    }
    if (!source_path.empty()) {
        model.set_local_path(source_path);
        if (model.source() == runanywhere::v1::MODEL_SOURCE_UNSPECIFIED) {
            model.set_source(runanywhere::v1::MODEL_SOURCE_LOCAL);
        }
    }
    if (model.format() == runanywhere::v1::MODEL_FORMAT_UNSPECIFIED ||
        model.format() == runanywhere::v1::MODEL_FORMAT_UNKNOWN) {
        model.set_format(infer_format_from_path(source_path));
    }
    if (model.framework() == runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED ||
        model.framework() == runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN) {
        model.set_framework(infer_framework_from_format(model.format()));
    }
    if (request.files_size() > 0 && model.artifact_case() == ModelInfo::ARTIFACT_NOT_SET) {
        for (const ModelFileDescriptor& file : request.files()) {
            model.mutable_multi_file()->add_files()->CopyFrom(file);
        }
        model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_MULTI_FILE);
    }
    normalize_model_registry_state(&model);
    if (!source_path.empty()) {
        overwrite_download_state_from_local_path(&model);
    }

    ModelInfo existing;
    const bool exists = get_model_snapshot_by_id(handle, model.id(), &existing);
    if (exists && !request.overwrite_existing()) {
        result.set_success(false);
        result.mutable_model()->CopyFrom(existing);
        result.set_local_path(existing.local_path());
        result.set_error_message("model already exists");
        result.set_registered(false);
        return serialize_proto_to_buffer(result, out_result);
    }

    if (request.copy_into_managed_storage()) {
        result.add_warnings(
            "copy_into_managed_storage is platform-owned and was not executed by commons");
    }
    if (request.validate_before_register()) {
        result.add_warnings(
            "validate_before_register requires platform filesystem facts and was not executed");
    }

    std::string model_bytes;
    if (!model.SerializeToString(&model_bytes)) {
        return proto_buffer_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                  "failed to serialize ModelImportRequest.model");
    }

    rac_result_t rc =
        exists
            ? rac_model_registry_update_proto(
                  handle, reinterpret_cast<const uint8_t*>(model_bytes.data()), model_bytes.size())
            : rac_model_registry_register_proto(
                  handle, reinterpret_cast<const uint8_t*>(model_bytes.data()), model_bytes.size());
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_result, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, model.id(), &saved)) {
        return proto_buffer_error(out_result, RAC_ERROR_NOT_FOUND, "imported model was not found");
    }

    result.set_success(true);
    result.mutable_model()->CopyFrom(saved);
    result.set_local_path(saved.local_path());
    result.set_imported_bytes(imported_size_for_request(request, saved));
    result.set_registered(true);
    result.set_copied_into_managed_storage(false);
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_discover_proto(rac_model_registry_handle_t handle,
                                               const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelDiscoveryRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(
        request_proto_bytes, request_proto_size, &request, "ModelDiscoveryRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    int32_t reconciled = 0;
    std::vector<ModelInfo> models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        // Bridge the in-memory registry with the canonical on-disk layout so
        // entries re-seeded by registerModel() after an app relaunch can be
        // linked back to previously downloaded {base_dir}/RunAnywhere/Models/
        // {framework}/{id}/ folders. Opt-in via link_downloaded (default true
        // from Swift's defaultDiscoveryRequest).
        if (request.link_downloaded()) {
            reconciled = reconcile_registry_with_filesystem_locked(handle);
        }
        models = collect_model_snapshots_locked(handle);
    }

    ModelDiscoveryResult result;
    result.set_success(true);
    int32_t scanned = 0;
    for (const ModelInfo& model : models) {
        if (!request.include_built_in() && model_is_built_in(model)) {
            continue;
        }
        ++scanned;
        if (model.local_path().empty()) {
            continue;
        }
        if (!path_matches_roots(model.local_path(), request.search_roots())) {
            continue;
        }
        if (request.has_query() && !model_matches_query(model, request.query())) {
            continue;
        }

        DiscoveredModel* discovered = result.add_discovered_models();
        discovered->set_model_id(model.id());
        discovered->set_local_path(model.local_path());
        discovered->set_matched_registry(true);
        discovered->mutable_model()->CopyFrom(model);
        discovered->set_size_bytes(model.download_size_bytes());
    }
    (void)reconciled;  // logged via per-entry RAC_LOG_DEBUG above

    if (request.purge_invalid()) {
        result.add_warnings(
            "purge_invalid requires platform filesystem callbacks and was not executed");
    }
    result.set_scanned_count(scanned);
    result.set_linked_count(result.discovered_models_size());
    result.set_purged_count(0);
    result.set_imported_count(0);
    return serialize_proto_to_buffer(result, out_result);
#endif
}

// =============================================================================
// REFRESH HELPERS — file_list_directory adapter rescan
// =============================================================================
//
// When the proto refresh request asks for `rescan_local` but the legacy
// rac_discovery_callbacks_t struct is unavailable (most SDKs have moved off
// it), we fall back to the platform adapter's file_list_directory callback.
// This rescans {base_dir}/RunAnywhere/Models/{framework}/{model_id}/ folders
// and links registered models to their on-disk folders via
// rac_model_registry_update_download_status.

namespace {

constexpr size_t kRescanMaxEntryCapacity = 4096;

// List a directory through the platform adapter using the POSIX two-call
// contract documented on `rac_file_list_directory_fn`: first call with
// out_entries=NULL to learn the required entry count, then allocate and call
// again with a buffer of at least that capacity. Header-compliant adapters
// (e.g. the Web TypeScript implementation) never write more than the capacity
// we pass on the second call, so we cannot rely on a "needed more space"
// signal — we must size up-front.
rac_result_t list_directory_via_adapter(const rac_platform_adapter_t* adapter, const char* dir_path,
                                        std::vector<rac_directory_entry_t>* out_entries) {
    if (!adapter || !adapter->file_list_directory || !dir_path || !out_entries) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_entries->clear();

    // Step 1: capacity probe.
    size_t required = 0;
    rac_result_t probe_rc = adapter->file_list_directory(dir_path, /*out_entries=*/nullptr,
                                                         &required, adapter->user_data);
    if (probe_rc != RAC_SUCCESS) {
        return probe_rc;
    }
    if (required == 0) {
        return RAC_SUCCESS;
    }
    if (required > kRescanMaxEntryCapacity) {
        // Defensive cap to keep refresh sweep bounded even on pathological dirs.
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Step 2: allocate and fetch. Use a small headroom in case the directory
    // gained entries between the probe and the read; entries written beyond
    // the probed count are still safe because we resize to the actual count
    // the adapter reports.
    const size_t capacity = required + 4;
    out_entries->resize(capacity);
    size_t count = capacity;
    rac_result_t fill_rc =
        adapter->file_list_directory(dir_path, out_entries->data(), &count, adapter->user_data);
    if (fill_rc != RAC_SUCCESS) {
        out_entries->clear();
        return fill_rc;
    }
    if (count > capacity) {
        // Header forbids this, but guard against a buggy adapter — never
        // expose entries we did not actually receive.
        count = capacity;
    }
    out_entries->resize(count);
    return RAC_SUCCESS;
}

// Walk {models_dir}/{framework}/{model_id}/ and link any registry entry whose
// on-disk folder contains at least one file. Returns the number of models we
// linked.
int32_t rescan_local_via_platform_adapter(rac_model_registry_handle_t handle) {
    if (!handle) {
        return 0;
    }
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (!adapter || !adapter->file_list_directory) {
        return 0;
    }

    char models_dir[1024];
    if (rac_model_paths_get_models_directory(models_dir, sizeof(models_dir)) != RAC_SUCCESS) {
        return 0;
    }

    // Same framework set used by rac_model_registry_discover_downloaded so the
    // ABI refresh path covers every backend an SDK can install.
    const rac_inference_framework_t frameworks[] = {
        RAC_FRAMEWORK_LLAMACPP,    RAC_FRAMEWORK_ONNX,
        RAC_FRAMEWORK_COREML,      RAC_FRAMEWORK_MLX,
        RAC_FRAMEWORK_FLUID_AUDIO, RAC_FRAMEWORK_FOUNDATION_MODELS,
        RAC_FRAMEWORK_SYSTEM_TTS,  RAC_FRAMEWORK_METALRT,
        RAC_FRAMEWORK_GENIE,       RAC_FRAMEWORK_SHERPA,
        RAC_FRAMEWORK_UNKNOWN};

    int32_t linked = 0;
    std::vector<rac_directory_entry_t> framework_entries;
    std::vector<rac_directory_entry_t> model_entries;

    for (const rac_inference_framework_t framework : frameworks) {
        char framework_dir[1024];
        if (rac_model_paths_get_framework_directory(framework, framework_dir,
                                                    sizeof(framework_dir)) != RAC_SUCCESS) {
            continue;
        }

        rac_result_t list_rc =
            list_directory_via_adapter(adapter, framework_dir, &framework_entries);
        if (list_rc != RAC_SUCCESS) {
            // Missing framework dirs are normal — only one or two backends may
            // have downloads on this device.
            continue;
        }

        for (const rac_directory_entry_t& entry : framework_entries) {
            if (entry.name[0] == '\0' || entry.name[0] == '.') {
                continue;  // skip hidden / empty
            }
            if (entry.is_dir != RAC_TRUE) {
                continue;  // model_id slots are always directories
            }

            const std::string model_id = entry.name;
            const std::string model_path = std::string(framework_dir) + "/" + model_id;

            // Verify the model folder contains at least one regular file —
            // mirrors the Kotlin self-heal heuristic and the legacy
            // is_valid_model_folder() shape (file existence is enough; we
            // don't filter by extension because each backend defines its own
            // file shape and platform `is_model_file` callback is optional).
            if (list_directory_via_adapter(adapter, model_path.c_str(), &model_entries) !=
                RAC_SUCCESS) {
                continue;
            }
            bool has_regular_file = false;
            for (const rac_directory_entry_t& child : model_entries) {
                if (child.is_dir != RAC_TRUE && child.name[0] != '\0' && child.name[0] != '.') {
                    has_regular_file = true;
                    break;
                }
            }
            if (!has_regular_file) {
                // Allow one level of nested folder (sherpa-onnx archives ship
                // as <name>/<files>) — match is_valid_model_folder semantics.
                for (const rac_directory_entry_t& child : model_entries) {
                    if (child.is_dir != RAC_TRUE || child.name[0] == '.') {
                        continue;
                    }
                    std::vector<rac_directory_entry_t> nested;
                    std::string nested_path = model_path + "/" + child.name;
                    if (list_directory_via_adapter(adapter, nested_path.c_str(), &nested) ==
                        RAC_SUCCESS) {
                        for (const rac_directory_entry_t& leaf : nested) {
                            if (leaf.is_dir != RAC_TRUE && leaf.name[0] != '\0' &&
                                leaf.name[0] != '.') {
                                has_regular_file = true;
                                break;
                            }
                        }
                    }
                    if (has_regular_file) {
                        break;
                    }
                }
            }
            if (!has_regular_file) {
                continue;
            }

            // Only link models that are actually registered.
            bool registered = false;
            {
                std::lock_guard<std::mutex> lock(handle->mutex);
                registered = handle->models.find(model_id) != handle->models.end();
            }
            if (!registered) {
                continue;
            }

            rac_result_t update_rc = rac_model_registry_update_download_status(
                handle, model_id.c_str(), model_path.c_str());
            if (update_rc == RAC_SUCCESS) {
                ++linked;
                RAC_LOG_INFO("ModelRegistry", "Refresh rescan: linked '%s' to local_path '%s'",
                             model_id.c_str(), model_path.c_str());
            } else {
                RAC_LOG_WARNING("ModelRegistry", "Refresh rescan: failed to update '%s' (rc=%d)",
                                model_id.c_str(), update_rc);
            }
        }
    }

    return linked;
}

}  // namespace

rac_result_t rac_model_registry_refresh_proto(rac_model_registry_handle_t handle,
                                              const uint8_t* request_proto_bytes,
                                              size_t request_proto_size,
                                              rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelRegistryRefreshRequest request;
    rac_result_t parse_rc =
        parse_proto_message_bytes(request_proto_bytes, request_proto_size, &request,
                                  "ModelRegistryRefreshRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    rac_model_registry_refresh_opts_t opts = {};
    opts.include_remote_catalog = request.include_remote_catalog() ? RAC_TRUE : RAC_FALSE;
    opts.rescan_local = request.rescan_local() ? RAC_TRUE : RAC_FALSE;
    opts.prune_orphans = request.prune_orphans() ? RAC_TRUE : RAC_FALSE;
    opts.discovery_callbacks = nullptr;

    rac_result_t refresh_rc = RAC_SUCCESS;
    if (opts.include_remote_catalog == RAC_TRUE || opts.rescan_local == RAC_TRUE ||
        opts.prune_orphans == RAC_TRUE) {
        refresh_rc = rac_model_registry_refresh(handle, opts);
    }

    // Platform-adapter-backed local rescan: when the request asked for
    // rescan_local and the SDK has wired up file_list_directory on the
    // platform adapter, walk the canonical model folders and link registered
    // entries to their downloads. Falls back to the legacy warning when the
    // callback is NULL so older SDK builds keep working without changes.
    int32_t adapter_rescan_linked = 0;
    bool adapter_rescan_ran = false;
    if (request.rescan_local()) {
        const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
        if (adapter && adapter->file_list_directory) {
            adapter_rescan_linked = rescan_local_via_platform_adapter(handle);
            adapter_rescan_ran = true;
        }
    }

    std::vector<ModelInfo> models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        models = collect_model_snapshots_locked(handle);
    }
    if (request.has_query()) {
        std::vector<ModelInfo> filtered;
        for (const ModelInfo& model : models) {
            if (model_matches_query(model, request.query())) {
                filtered.push_back(model);
            }
        }
        sort_query_results(request.query(), &filtered);
        models = std::move(filtered);
    }
    const ModelCounts counts = count_models(models);

    ModelRegistryRefreshResult result;
    result.set_success(refresh_rc == RAC_SUCCESS);
    result.set_registered_count(counts.total);
    result.set_updated_count(adapter_rescan_linked);
    result.set_discovered_count(adapter_rescan_linked);
    result.set_pruned_count(0);
    result.set_refreshed_at_unix_ms(rac_get_current_time_ms());
    result.set_downloaded_count(counts.downloaded);
    result.set_available_count(counts.available);
    result.set_error_count(counts.errors);
    if (refresh_rc != RAC_SUCCESS) {
        result.set_error_message(rac_error_message(refresh_rc));
    }
    if (request.rescan_local() && !adapter_rescan_ran) {
        result.add_warnings(
            "rescan_local requires platform filesystem callbacks in the C ABI refresh path");
    }
    if (request.prune_orphans()) {
        result.add_warnings(
            "prune_orphans requires platform filesystem callbacks in the C ABI refresh path");
    }
    if (!request.catalog_uri().empty()) {
        result.add_warnings(
            "catalog_uri transport is platform-owned and was not executed by commons");
    }
    move_models_to_list(&models, result.mutable_models());
    return serialize_proto_to_buffer(result, out_result);
#endif
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

// Helper: extract a lower-cased file extension from a path or filename.
// Returns "" if the basename has no '.' or starts with '.' (hidden file).
static std::string extension_from_path(const char* path) {
    if (!path)
        return {};
    std::string s(path);
    size_t slash = s.find_last_of('/');
    std::string base = (slash == std::string::npos) ? s : s.substr(slash + 1);
    if (base.empty() || base.front() == '.')
        return {};
    size_t dot = base.find_last_of('.');
    if (dot == std::string::npos || dot + 1 >= base.size())
        return {};
    std::string ext = base.substr(dot + 1);
    std::ranges::transform(ext, ext.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return ext;
}

// Helper: ask the canonical commons mapping whether a path is a model file
// for a given framework, replacing the legacy
// rac_discovery_callbacks_t.is_model_file callback that each SDK had to
// wire up previously.
static bool path_is_model_file(const char* path, rac_inference_framework_t framework) {
    std::string ext = extension_from_path(path);
    rac_bool_t out = RAC_FALSE;
    rac_result_t rc = rac_model_format_for_framework(framework, ext.c_str(), &out);
    return rc == RAC_SUCCESS && out == RAC_TRUE;
}

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

        // Check if it's a model file for this framework via the canonical
        // commons mapping (replaces the legacy is_model_file callback).
        if (path_is_model_file(full_path.c_str(), framework)) {
            found_model_file = true;
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
                        if (path_is_model_file(sub_path.c_str(), framework)) {
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
        RAC_FRAMEWORK_SYSTEM_TTS,  RAC_FRAMEWORK_METALRT,
        RAC_FRAMEWORK_GENIE,       RAC_FRAMEWORK_SHERPA,
        RAC_FRAMEWORK_UNKNOWN};
    size_t framework_count = sizeof(frameworks) / sizeof(frameworks[0]);

    // Lock-copy-dispatch: snapshot the registered ids (and which ones already
    // have a local_path) under the lock, then drop it for the entire
    // filesystem scan. Platform callbacks (Swift FileManager, Kotlin
    // Files.exists, dart_ffi) MUST NOT be invoked while holding handle->mutex
    // — they can stall on cold OS caches and may re-enter registry APIs via
    // SDK glue, which would deadlock. Matches the event publisher's
    // lock-copy-dispatch pattern documented in commons AGENTS.md.
    std::map<std::string, bool> needs_link_by_id;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        for (const auto& pair : handle->models) {
            const rac_model_info_t* model = pair.second;
            const bool needs_link = !model || !model->local_path || model->local_path[0] == '\0';
            needs_link_by_id.emplace(pair.first, needs_link);
        }
    }

    // Collect discovered models (unlocked phase — no handle->mutex held).
    std::vector<rac_discovered_model_t> discovered;
    size_t unregistered = 0;

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
            // Defensive guard. The list_directory
            // contract says "no allocation on failure"; the C ABI is
            // implemented by every platform SDK and a future regression
            // could leave a partial allocation here. If callers DID populate
            // model_folders before returning non-success, free it through
            // their canonical entry point so we don't leak.
            if (model_folders && callbacks->free_entries) {
                callbacks->free_entries(model_folders, folder_count, callbacks->user_data);
            }
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

            // Check if this model is registered (using snapshot taken above)
            auto snap_it = needs_link_by_id.find(model_id);
            if (snap_it == needs_link_by_id.end()) {
                // Model folder exists but not registered
                unregistered++;
                RAC_LOG_DEBUG("ModelRegistry", "Found unregistered model folder");
                continue;
            }
            if (!snap_it->second) {
                // Already linked at snapshot time — nothing to do.
                continue;
            }

            // Apply the link under the registry's own lock via the canonical
            // update entry point (it takes/releases handle->mutex briefly).
            rac_result_t link_rc =
                rac_model_registry_update_download_status(handle, model_id, model_path.c_str());
            if (link_rc != RAC_SUCCESS) {
                RAC_LOG_WARNING("ModelRegistry", "Discovery: failed to link '%s' (rc=%d)", model_id,
                                static_cast<int>(link_rc));
                continue;
            }

            // Add to discovered list
            rac_discovered_model_t disc;
            disc.model_id = rac_strdup(model_id);
            disc.local_path = rac_strdup(model_path.c_str());
            disc.framework = framework;
            discovered.push_back(disc);

            RAC_LOG_INFO("ModelRegistry", "Discovered downloaded model");
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
// PUBLIC API - REFRESH
// =============================================================================

rac_result_t rac_model_registry_refresh(rac_model_registry_handle_t handle,
                                        rac_model_registry_refresh_opts_t opts) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("ModelRegistry", "Refresh requested: remote=%d, rescan_local=%d, prune_orphans=%d",
                 static_cast<int>(opts.include_remote_catalog), static_cast<int>(opts.rescan_local),
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
            if (first_error == RAC_SUCCESS)
                first_error = remote_rc;
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
                if (first_error == RAC_SUCCESS)
                    first_error = rescan_rc;
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
                                                /*preserve_proto_only_fields=*/true,
                                                /*overwrite_registry_state=*/true);
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
// FETCH ASSIGNMENTS — Unified cross-SDK entry point (Web WASM)
// =============================================================================

rac_result_t rac_model_registry_fetch_assignments(rac_bool_t force_refresh,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    // Initialise caller outputs to safe defaults.
    if (out_models)
        *out_models = nullptr;
    if (out_count)
        *out_count = 0;

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

    if (out_models)
        *out_models = models;
    else
        rac_model_info_array_free(models, count);  // caller doesn't want the array

    if (out_count)
        *out_count = count;

    RAC_LOG_INFO("ModelRegistry", "rac_model_registry_fetch_assignments: fetched %zu models",
                 count);
    return RAC_SUCCESS;
}
