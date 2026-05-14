/**
 * @file model_lifecycle.cpp
 * @brief Canonical model lifecycle C ABI over generated proto bytes.
 */

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "features/vlm/rac_vlm_lifecycle_bridge.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#include "sdk_events.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

using runanywhere::v1::ComponentLifecycleSnapshot;
using runanywhere::v1::ComponentLifecycleState;
using runanywhere::v1::CurrentModelRequest;
using runanywhere::v1::CurrentModelResult;
using runanywhere::v1::ErrorSeverity;
using runanywhere::v1::EventCategory;
using runanywhere::v1::InferenceFramework;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::ModelFileDescriptor;
using runanywhere::v1::ModelFileRole;
using runanywhere::v1::ModelFormat;
using runanywhere::v1::ModelInfo;
using runanywhere::v1::ModelLoadRequest;
using runanywhere::v1::ModelLoadResult;
using runanywhere::v1::ModelUnloadRequest;
using runanywhere::v1::ModelUnloadResult;
using runanywhere::v1::SDKComponent;
using runanywhere::v1::SDKEvent;

struct LoadedModel {
    SDKComponent component{runanywhere::v1::SDK_COMPONENT_UNSPECIFIED};
    ComponentLifecycleState state{runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED};
    std::string model_id;
    std::string resolved_path;
    std::string mmproj_path;
    std::vector<ModelFileDescriptor> resolved_artifacts;
    InferenceFramework framework{runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED};
    std::string framework_name;
    ModelCategory category{runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED};
    ModelInfo model;
    int64_t loaded_at_ms{0};
    int64_t updated_at_ms{0};
    std::string error_message;
    rac_primitive_t primitive{RAC_PRIMITIVE_UNSPECIFIED};
    const rac_llm_service_ops_t* llm_ops{nullptr};
    const rac_stt_service_ops_t* stt_ops{nullptr};
    const rac_tts_service_ops_t* tts_ops{nullptr};
    const rac_vad_service_ops_t* vad_ops{nullptr};
    const rac_embeddings_service_ops_t* embeddings_ops{nullptr};
    const rac_vlm_service_ops_t* vlm_ops{nullptr};
    const rac_diffusion_service_ops_t* diffusion_ops{nullptr};
    void* impl{nullptr};
    int active_refs{0};
    std::atomic<bool> cancel_requested{false};
    std::function<void()> destroy;
};

std::mutex g_lifecycle_mutex;
std::condition_variable g_lifecycle_cv;
std::map<SDKComponent, std::shared_ptr<LoadedModel>> g_loaded;

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string generate_event_id() {
    static std::atomic<uint64_t> counter{0};
    const uint64_t c = counter.fetch_add(1);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(c));
    return buffer;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

void destroy_loaded_model(const std::shared_ptr<LoadedModel>& model) {
    if (!model) {
        return;
    }
    {
        std::unique_lock<std::mutex> lock(g_lifecycle_mutex);
        g_lifecycle_cv.wait(lock, [&model] { return model->active_refs == 0; });
    }
    if (model->destroy) {
        model->destroy();
        model->destroy = {};
    }
    model->impl = nullptr;
    model->llm_ops = nullptr;
    model->stt_ops = nullptr;
    model->tts_ops = nullptr;
    model->vad_ops = nullptr;
    model->embeddings_ops = nullptr;
    model->vlm_ops = nullptr;
    model->diffusion_ops = nullptr;
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes) && size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_event_envelope(SDKEvent* event, EventCategory category, ErrorSeverity severity,
                             SDKComponent component) {
    event->set_id(generate_event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(component);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

rac_result_t publish_event(const SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    return rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
}

void publish_component_event(SDKComponent component, ComponentLifecycleState previous,
                             ComponentLifecycleState current, const std::string& model_id,
                             const ModelLoadResult* load_result,
                             const ModelUnloadResult* unload_result, const char* error_message) {
    SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_COMPONENT,
                            error_message && error_message[0]
                                ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                : runanywhere::v1::ERROR_SEVERITY_INFO,
                            component);
    auto* lifecycle = event.mutable_component_lifecycle();
    lifecycle->set_component(component);
    lifecycle->set_previous_state(previous);
    lifecycle->set_current_state(current);
    lifecycle->set_model_id(model_id);
    lifecycle->set_timestamp_ms(now_ms());
    if (load_result) {
        lifecycle->mutable_model_load_result()->CopyFrom(*load_result);
    }
    if (unload_result) {
        lifecycle->mutable_model_unload_result()->CopyFrom(*unload_result);
    }
    if (error_message && error_message[0]) {
        event.mutable_error()->set_message(error_message);
        event.mutable_error()->set_c_abi_code(static_cast<int32_t>(RAC_ERROR_MODEL_LOAD_FAILED));
        event.mutable_error()->set_timestamp_ms(now_ms());
        event.mutable_error()->set_component(runanywhere::v1::SDKComponent_Name(component));
        event.mutable_error()->set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
        event.mutable_error()->set_retryable(false);
    }
    (void)publish_event(event);
}

void publish_current_model_event(const CurrentModelResult& result, SDKComponent component) {
    SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_MODEL,
                            runanywhere::v1::ERROR_SEVERITY_INFO, component);
    auto* registry = event.mutable_model_registry();
    registry->set_kind(runanywhere::v1::MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED);
    registry->set_model_id(result.model_id());
    registry->set_assigned_component(component);
    registry->mutable_current_model_result()->CopyFrom(result);
    (void)publish_event(event);
}

SDKComponent component_for_category(ModelCategory category) {
    switch (category) {
        case runanywhere::v1::MODEL_CATEGORY_LANGUAGE:
            return runanywhere::v1::SDK_COMPONENT_LLM;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            return runanywhere::v1::SDK_COMPONENT_STT;
        case runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return runanywhere::v1::SDK_COMPONENT_TTS;
        case runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        case runanywhere::v1::MODEL_CATEGORY_AUDIO:
            return runanywhere::v1::SDK_COMPONENT_VAD;
        case runanywhere::v1::MODEL_CATEGORY_EMBEDDING:
            return runanywhere::v1::SDK_COMPONENT_EMBEDDINGS;
        case runanywhere::v1::MODEL_CATEGORY_MULTIMODAL:
        case runanywhere::v1::MODEL_CATEGORY_VISION:
            return runanywhere::v1::SDK_COMPONENT_VLM;
        case runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION:
            return runanywhere::v1::SDK_COMPONENT_DIFFUSION;
        default:
            return runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
    }
}

rac_primitive_t primitive_for_component(SDKComponent component) {
    switch (component) {
        case runanywhere::v1::SDK_COMPONENT_LLM:
            return RAC_PRIMITIVE_GENERATE_TEXT;
        case runanywhere::v1::SDK_COMPONENT_STT:
            return RAC_PRIMITIVE_TRANSCRIBE;
        case runanywhere::v1::SDK_COMPONENT_TTS:
            return RAC_PRIMITIVE_SYNTHESIZE;
        case runanywhere::v1::SDK_COMPONENT_VAD:
            return RAC_PRIMITIVE_DETECT_VOICE;
        case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS:
            return RAC_PRIMITIVE_EMBED;
        case runanywhere::v1::SDK_COMPONENT_VLM:
            return RAC_PRIMITIVE_VLM;
        case runanywhere::v1::SDK_COMPONENT_DIFFUSION:
            return RAC_PRIMITIVE_DIFFUSION;
        default:
            return RAC_PRIMITIVE_UNSPECIFIED;
    }
}

const char* framework_to_plugin_name(InferenceFramework framework, rac_primitive_t primitive) {
    switch (framework) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            if (primitive == RAC_PRIMITIVE_VLM) {
                return "llamacpp_vlm";
            }
            return "llamacpp";
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            if (primitive == RAC_PRIMITIVE_DETECT_VOICE || primitive == RAC_PRIMITIVE_TRANSCRIBE ||
                primitive == RAC_PRIMITIVE_SYNTHESIZE) {
                return "sherpa";
            }
            return "onnx";
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return "sherpa";
        case runanywhere::v1::INFERENCE_FRAMEWORK_WHISPERKIT_COREML:
            return "whisperkit_coreml";
        case runanywhere::v1::INFERENCE_FRAMEWORK_METALRT:
            return "metalrt";
        case runanywhere::v1::INFERENCE_FRAMEWORK_GENIE:
            return "genie";
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
            return "platform";
        default:
            return nullptr;
    }
}

rac_model_category_t c_category_from_proto(ModelCategory category) {
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

rac_model_format_t c_format_from_proto(ModelFormat format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<rac_model_format_t>(value)
                                                       : RAC_MODEL_FORMAT_UNKNOWN;
}

rac_inference_framework_t c_framework_from_proto(InferenceFramework framework) {
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

rac_model_file_role_t c_file_role_from_proto(ModelFileRole role) {
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

ModelFileRole proto_file_role_from_resolved(rac_resolved_model_file_role_t role) {
    switch (role) {
        case RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY:
            return runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL;
        case RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR:
            return runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR;
        case RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER:
            return runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER;
        case RAC_RESOLVED_MODEL_FILE_ROLE_CONFIG:
            return runanywhere::v1::MODEL_FILE_ROLE_CONFIG;
        case RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY:
            return runanywhere::v1::MODEL_FILE_ROLE_VOCABULARY;
        case RAC_RESOLVED_MODEL_FILE_ROLE_MERGES:
            return runanywhere::v1::MODEL_FILE_ROLE_MERGES;
        case RAC_RESOLVED_MODEL_FILE_ROLE_LABELS:
            return runanywhere::v1::MODEL_FILE_ROLE_LABELS;
        case RAC_RESOLVED_MODEL_FILE_ROLE_COMPANION:
            return runanywhere::v1::MODEL_FILE_ROLE_COMPANION;
        case RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN:
        default:
            return runanywhere::v1::MODEL_FILE_ROLE_UNSPECIFIED;
    }
}

std::string resolved_path_for_model(const ModelInfo& model) {
    if (!model.local_path().empty()) {
        return model.local_path();
    }
    return model.id();
}

std::string basename_of_path(const std::string& path) {
    const size_t pos = path.find_last_of("/\\");
    return pos == std::string::npos ? path : path.substr(pos + 1);
}

std::string json_escape(const std::string& value) {
    std::string out;
    out.reserve(value.size());
    for (char c : value) {
        switch (c) {
            case '\\':
                out += "\\\\";
                break;
            case '"':
                out += "\\\"";
                break;
            case '\n':
                out += "\\n";
                break;
            case '\r':
                out += "\\r";
                break;
            case '\t':
                out += "\\t";
                break;
            default:
                out.push_back(c);
                break;
        }
    }
    return out;
}

std::string vlm_config_json(const std::string& mmproj_path) {
    if (mmproj_path.empty()) {
        return "";
    }
    return "{\"mmproj_path\":\"" + json_escape(mmproj_path) + "\"}";
}

struct ProtoModelPathBridge {
    rac_model_info_t model{};
    rac_expected_model_files_t expected_files{};
    rac_model_artifact_info_t artifact{};
    std::vector<std::string> required_patterns;
    std::vector<std::string> optional_patterns;
    std::vector<const char*> required_pattern_ptrs;
    std::vector<const char*> optional_pattern_ptrs;
    std::vector<std::string> descriptor_relative_paths;
    std::vector<std::string> descriptor_destination_paths;
    std::vector<rac_model_file_descriptor_t> descriptors;

    explicit ProtoModelPathBridge(const ModelInfo& proto) {
        model.id = const_cast<char*>(proto.id().c_str());
        model.name = const_cast<char*>(proto.name().c_str());
        model.category = c_category_from_proto(proto.category());
        model.format = c_format_from_proto(proto.format());
        model.framework = c_framework_from_proto(proto.framework());
        model.local_path = const_cast<char*>(proto.local_path().c_str());
        model.download_url = const_cast<char*>(proto.download_url().c_str());
        model.artifact_info = {};
        model.artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;

        populate_expected_files(proto);
        populate_descriptors(proto);
        populate_artifact_kind(proto);
    }

   private:
    void add_pattern(std::vector<std::string>* storage, const std::string& pattern) {
        if (!storage || pattern.empty()) {
            return;
        }
        storage->push_back(pattern);
    }

    void finalize_patterns() {
        required_pattern_ptrs.clear();
        optional_pattern_ptrs.clear();
        required_pattern_ptrs.reserve(required_patterns.size());
        optional_pattern_ptrs.reserve(optional_patterns.size());
        for (const std::string& pattern : required_patterns) {
            required_pattern_ptrs.push_back(pattern.c_str());
        }
        for (const std::string& pattern : optional_patterns) {
            optional_pattern_ptrs.push_back(pattern.c_str());
        }
        if (!required_pattern_ptrs.empty() || !optional_pattern_ptrs.empty()) {
            expected_files.required_patterns = required_pattern_ptrs.data();
            expected_files.required_pattern_count = required_pattern_ptrs.size();
            expected_files.optional_patterns = optional_pattern_ptrs.data();
            expected_files.optional_pattern_count = optional_pattern_ptrs.size();
            model.artifact_info.expected_files = &expected_files;
        }
    }

    void add_expected_from_message(const runanywhere::v1::ExpectedModelFiles& expected) {
        for (const std::string& pattern : expected.required_patterns()) {
            add_pattern(&required_patterns, pattern);
        }
        for (const std::string& pattern : expected.optional_patterns()) {
            add_pattern(&optional_patterns, pattern);
        }
    }

    void populate_expected_files(const ModelInfo& proto) {
        if (proto.has_expected_files()) {
            add_expected_from_message(proto.expected_files());
        } else if (proto.has_single_file() && proto.single_file().has_expected_files()) {
            add_expected_from_message(proto.single_file().expected_files());
        } else if (proto.has_archive() && proto.archive().has_expected_files()) {
            add_expected_from_message(proto.archive().expected_files());
        } else if (proto.has_single_file()) {
            for (const std::string& pattern : proto.single_file().required_patterns()) {
                add_pattern(&required_patterns, pattern);
            }
            for (const std::string& pattern : proto.single_file().optional_patterns()) {
                add_pattern(&optional_patterns, pattern);
            }
        } else if (proto.has_archive()) {
            for (const std::string& pattern : proto.archive().required_patterns()) {
                add_pattern(&required_patterns, pattern);
            }
            for (const std::string& pattern : proto.archive().optional_patterns()) {
                add_pattern(&optional_patterns, pattern);
            }
        }
        finalize_patterns();
    }

    void add_descriptor(const ModelFileDescriptor& file) {
        std::string relative = file.has_relative_path() && !file.relative_path().empty()
                                   ? file.relative_path()
                                   : (!file.url().empty() ? file.url() : file.filename());
        std::string destination = file.has_destination_path() && !file.destination_path().empty()
                                      ? file.destination_path()
                                      : file.filename();
        if (relative.empty()) {
            relative = destination;
        }
        if (destination.empty()) {
            destination = relative;
        }
        descriptor_relative_paths.push_back(relative);
        descriptor_destination_paths.push_back(destination);
    }

    void populate_descriptors(const ModelInfo& proto) {
        int descriptor_count = proto.has_multi_file() ? proto.multi_file().files_size() : 0;
        if (proto.has_expected_files()) {
            descriptor_count += proto.expected_files().files_size();
        }
        descriptor_relative_paths.reserve(static_cast<size_t>(descriptor_count));
        descriptor_destination_paths.reserve(static_cast<size_t>(descriptor_count));
        descriptors.reserve(static_cast<size_t>(descriptor_count));

        if (proto.has_multi_file()) {
            for (const ModelFileDescriptor& file : proto.multi_file().files()) {
                add_descriptor(file);
                rac_model_file_descriptor_t descriptor{};
                descriptor.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                descriptor.role = c_file_role_from_proto(file.role());
                descriptors.push_back(descriptor);
            }
        }
        if (proto.has_expected_files()) {
            for (const ModelFileDescriptor& file : proto.expected_files().files()) {
                add_descriptor(file);
                rac_model_file_descriptor_t descriptor{};
                descriptor.is_required = file.is_required() ? RAC_TRUE : RAC_FALSE;
                descriptor.role = c_file_role_from_proto(file.role());
                descriptors.push_back(descriptor);
            }
        }
        for (size_t i = 0; i < descriptors.size(); ++i) {
            descriptors[i].relative_path = descriptor_relative_paths[i].empty()
                                               ? nullptr
                                               : descriptor_relative_paths[i].c_str();
            descriptors[i].destination_path = descriptor_destination_paths[i].empty()
                                                  ? nullptr
                                                  : descriptor_destination_paths[i].c_str();
        }
        if (!descriptors.empty()) {
            artifact.file_descriptors = descriptors.data();
            artifact.file_descriptor_count = descriptors.size();
            model.artifact_info.file_descriptors = descriptors.data();
            model.artifact_info.file_descriptor_count = descriptors.size();
        }
    }

    void populate_artifact_kind(const ModelInfo& proto) {
        if (proto.has_archive()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_ARCHIVE;
        } else if (proto.has_multi_file() || !descriptors.empty()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
        } else if (proto.has_custom_strategy_id()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_CUSTOM;
        } else if (proto.has_built_in() && proto.built_in()) {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_BUILT_IN;
        } else {
            model.artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;
        }
    }
};

struct ModelArtifactResolution {
    std::string resolved_path;
    std::string mmproj_path;
    std::vector<ModelFileDescriptor> artifacts;
};

ModelFileDescriptor descriptor_from_resolved_file(const rac_resolved_model_file_t& file) {
    ModelFileDescriptor descriptor;
    if (file.relative_path) {
        descriptor.set_relative_path(file.relative_path);
        descriptor.set_destination_path(file.relative_path);
    }
    if (file.path) {
        descriptor.set_local_path(file.path);
        descriptor.set_filename(basename_of_path(file.path));
    }
    descriptor.set_is_required(file.is_required == RAC_TRUE);
    descriptor.set_role(proto_file_role_from_resolved(file.role));
    return descriptor;
}

void add_artifacts_to_result(const std::vector<ModelFileDescriptor>& artifacts,
                             google::protobuf::RepeatedPtrField<ModelFileDescriptor>* out) {
    if (!out) {
        return;
    }
    for (const ModelFileDescriptor& artifact : artifacts) {
        out->Add()->CopyFrom(artifact);
    }
}

ModelArtifactResolution resolve_model_artifacts(const ModelInfo& model) {
    ModelArtifactResolution out;
    out.resolved_path = resolved_path_for_model(model);
    if (out.resolved_path.empty()) {
        return out;
    }

    ProtoModelPathBridge bridge(model);
    rac_model_path_resolution_t resolution = {};
    const char* checksum = model.has_checksum_sha256() && !model.checksum_sha256().empty()
                               ? model.checksum_sha256().c_str()
                               : nullptr;
    const rac_result_t rc = rac_model_paths_resolve_artifact(
        &bridge.model, out.resolved_path.c_str(), checksum, &resolution);
    if ((rc == RAC_SUCCESS || resolution.primary_model_path || resolution.file_count > 0) &&
        resolution.primary_model_path) {
        out.resolved_path = resolution.primary_model_path;
    }
    if (resolution.mmproj_path) {
        out.mmproj_path = resolution.mmproj_path;
    }
    for (size_t i = 0; i < resolution.file_count; ++i) {
        out.artifacts.push_back(descriptor_from_resolved_file(resolution.files[i]));
    }
    rac_model_path_resolution_free(&resolution);
    return out;
}

InferenceFramework preferred_framework_for(const ModelLoadRequest& request,
                                           const ModelInfo& model) {
    if (request.has_framework()) {
        return request.framework();
    }
    if (model.has_preferred_framework()) {
        return model.preferred_framework();
    }
    return model.framework();
}

ModelCategory preferred_category_for(const ModelLoadRequest& request, const ModelInfo& model) {
    if (request.has_category()) {
        return request.category();
    }
    return model.category();
}

rac_result_t create_backend_impl(const rac_engine_vtable_t* vt, rac_primitive_t primitive,
                                 const std::string& resolved_path, const std::string& mmproj_path,
                                 void** out_impl, std::function<void()>* out_destroy) {
    if (!vt || !out_impl || !out_destroy) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    *out_destroy = {};

    void* impl = nullptr;
    rac_result_t rc = RAC_ERROR_BACKEND_NOT_FOUND;

    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            if (!vt->llm_ops || !vt->llm_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->llm_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->llm_ops->initialize) {
                rc = vt->llm_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->llm_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_TRANSCRIBE:
            if (!vt->stt_ops || !vt->stt_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->stt_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->stt_ops->initialize) {
                rc = vt->stt_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->stt_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_SYNTHESIZE:
            if (!vt->tts_ops || !vt->tts_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->tts_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->tts_ops->initialize) {
                rc = vt->tts_ops->initialize(impl);
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->tts_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_DETECT_VOICE:
            if (!vt->vad_ops || !vt->vad_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->vad_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->vad_ops->initialize) {
                rc = vt->vad_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->vad_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_EMBED:
            if (!vt->embedding_ops || !vt->embedding_ops->create) {
                return RAC_ERROR_BACKEND_NOT_FOUND;
            }
            rc = vt->embedding_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->embedding_ops->initialize) {
                rc = vt->embedding_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->embedding_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_VLM:
            if (!vt->vlm_ops || !vt->vlm_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            {
                const std::string config_json = vlm_config_json(mmproj_path);
                rc =
                    vt->vlm_ops->create(resolved_path.c_str(),
                                        config_json.empty() ? nullptr : config_json.c_str(), &impl);
            }
            if (rc == RAC_SUCCESS && impl && vt->vlm_ops->initialize) {
                rc = vt->vlm_ops->initialize(impl, resolved_path.c_str(),
                                             mmproj_path.empty() ? nullptr : mmproj_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->vlm_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_DIFFUSION:
            if (!vt->diffusion_ops || !vt->diffusion_ops->create) {
                return RAC_ERROR_BACKEND_NOT_FOUND;
            }
            rc = vt->diffusion_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->diffusion_ops->initialize) {
                rc = vt->diffusion_ops->initialize(impl, resolved_path.c_str(), nullptr);
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->diffusion_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        default:
            return RAC_ERROR_UNSUPPORTED_MODALITY;
    }

    if (rc != RAC_SUCCESS) {
        if (impl) {
            switch (primitive) {
                case RAC_PRIMITIVE_GENERATE_TEXT:
                    if (vt->llm_ops && vt->llm_ops->destroy)
                        vt->llm_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_TRANSCRIBE:
                    if (vt->stt_ops && vt->stt_ops->destroy)
                        vt->stt_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_SYNTHESIZE:
                    if (vt->tts_ops && vt->tts_ops->destroy)
                        vt->tts_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_DETECT_VOICE:
                    if (vt->vad_ops && vt->vad_ops->destroy)
                        vt->vad_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_EMBED:
                    if (vt->embedding_ops && vt->embedding_ops->destroy) {
                        vt->embedding_ops->destroy(impl);
                    }
                    break;
                case RAC_PRIMITIVE_VLM:
                    if (vt->vlm_ops && vt->vlm_ops->destroy)
                        vt->vlm_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_DIFFUSION:
                    if (vt->diffusion_ops && vt->diffusion_ops->destroy) {
                        vt->diffusion_ops->destroy(impl);
                    }
                    break;
                default:
                    break;
            }
        }
        return rc;
    }

    if (!impl || !*out_destroy) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_impl = impl;
    return RAC_SUCCESS;
}

ModelLoadResult make_load_result(bool success, const std::string& model_id, ModelCategory category,
                                 InferenceFramework framework, const std::string& resolved_path,
                                 const std::vector<ModelFileDescriptor>& artifacts,
                                 int64_t loaded_at_ms, const std::string& error) {
    ModelLoadResult result;
    result.set_success(success);
    result.set_model_id(model_id);
    result.set_category(category);
    result.set_framework(framework);
    result.set_resolved_path(resolved_path);
    add_artifacts_to_result(artifacts, result.mutable_resolved_artifacts());
    result.set_loaded_at_unix_ms(loaded_at_ms);
    result.set_error_message(error);
    return result;
}

bool matches_current_filter(const LoadedModel& loaded, bool has_category, ModelCategory category,
                            bool has_framework, InferenceFramework framework) {
    if (has_category && loaded.category != category) {
        return false;
    }
    if (has_framework && loaded.framework != framework) {
        return false;
    }
    return loaded.state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
}

void fill_snapshot(const LoadedModel* loaded, SDKComponent component,
                   ComponentLifecycleSnapshot* out) {
    out->set_component(component);
    out->set_updated_at_ms(now_ms());
    if (!loaded) {
        out->set_state(runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED);
        return;
    }
    out->set_state(loaded->state);
    out->set_model_id(loaded->model_id);
    out->set_updated_at_ms(loaded->updated_at_ms);
    out->set_error_message(loaded->error_message);
    out->set_category(loaded->category);
    out->set_framework(loaded->framework);
    out->set_resolved_path(loaded->resolved_path);
    out->set_loaded_at_unix_ms(loaded->loaded_at_ms);
    out->mutable_model()->CopyFrom(loaded->model);
}

#endif  // RAC_HAVE_PROTOBUF

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

}  // namespace

namespace rac::llm {

rac_result_t acquire_lifecycle_llm(LifecycleLlmRef* out_ref) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};
#if !defined(RAC_HAVE_PROTOBUF)
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(runanywhere::v1::SDK_COMPONENT_LLM);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        if (!it->second->impl || !it->second->llm_ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = (*token)->llm_ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
#endif
}

void release_lifecycle_llm(LifecycleLlmRef* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
#if defined(RAC_HAVE_PROTOBUF)
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
#endif
    *ref = {};
}

void clear_lifecycle_llm_cancel(LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(false, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

void request_lifecycle_llm_cancel(LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(true, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

bool lifecycle_llm_cancel_requested(const LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return false;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    return *token && (*token)->cancel_requested.load(std::memory_order_relaxed);
#else
    (void)ref;
    return false;
#endif
}

}  // namespace rac::llm

namespace rac::vlm {

rac_result_t acquire_lifecycle_vlm(LifecycleVlmRef* out_ref) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};
#if !defined(RAC_HAVE_PROTOBUF)
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(runanywhere::v1::SDK_COMPONENT_VLM);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        if (!it->second->impl || !it->second->vlm_ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = (*token)->vlm_ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
#endif
}

void release_lifecycle_vlm(LifecycleVlmRef* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
#if defined(RAC_HAVE_PROTOBUF)
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
#endif
    *ref = {};
}

void clear_lifecycle_vlm_cancel(LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(false, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

void request_lifecycle_vlm_cancel(LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(true, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

bool lifecycle_vlm_cancel_requested(const LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return false;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    return *token && (*token)->cancel_requested.load(std::memory_order_relaxed);
#else
    (void)ref;
    return false;
#endif
}

}  // namespace rac::vlm

namespace rac::lifecycle {

#if defined(RAC_HAVE_PROTOBUF)
template <typename Ref, typename OpsPtr>
rac_result_t acquire_component(runanywhere::v1::SDKComponent component, Ref* out_ref,
                               OpsPtr LoadedModel::* ops_field) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};

    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(component);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        const auto* ops = it->second.get()->*ops_field;
        if (!it->second->impl || !ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
}

template <typename Ref>
void release_component(Ref* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
    *ref = {};
}
#endif

rac_result_t acquire_lifecycle_stt(LifecycleSttRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_STT, out_ref, &LoadedModel::stt_ops);
#endif
}

void release_lifecycle_stt(LifecycleSttRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_tts(LifecycleTtsRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_TTS, out_ref, &LoadedModel::tts_ops);
#endif
}

void release_lifecycle_tts(LifecycleTtsRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_vad(LifecycleVadRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_VAD, out_ref, &LoadedModel::vad_ops);
#endif
}

void release_lifecycle_vad(LifecycleVadRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_embeddings(LifecycleEmbeddingsRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS, out_ref,
                             &LoadedModel::embeddings_ops);
#endif
}

void release_lifecycle_embeddings(LifecycleEmbeddingsRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_diffusion(LifecycleDiffusionRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION, out_ref,
                             &LoadedModel::diffusion_ops);
#endif
}

void release_lifecycle_diffusion(LifecycleDiffusionRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

}  // namespace rac::lifecycle

extern "C" {

rac_result_t rac_model_lifecycle_load_proto(rac_model_registry_handle_t registry,
                                            const uint8_t* request_proto_bytes,
                                            size_t request_proto_size,
                                            rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "registry handle is required");
    }
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "ModelLoadRequest bytes are empty or too large");
    }

    ModelLoadRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse ModelLoadRequest");
    }
    if (request.model_id().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "ModelLoadRequest.model_id is required");
    }

    uint8_t* model_bytes = nullptr;
    size_t model_size = 0;
    rac_result_t rc = rac_model_registry_get_proto(registry, request.model_id().c_str(),
                                                   &model_bytes, &model_size);
    if (rc != RAC_SUCCESS) {
        ModelLoadResult result = make_load_result(
            false, request.model_id(),
            request.has_category() ? request.category()
                                   : runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED,
            request.has_framework() ? request.framework()
                                    : runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED,
            "", {}, 0, "model not found in registry");
        publish_component_event(runanywhere::v1::SDK_COMPONENT_UNSPECIFIED,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                request.model_id(), &result, nullptr,
                                result.error_message().c_str());
        return copy_proto(result, out_result);
    }

    ModelInfo model;
    const bool parsed_model = model.ParseFromArray(model_bytes, static_cast<int>(model_size));
    rac_model_registry_proto_free(model_bytes);
    if (!parsed_model) {
        return parse_error(out_result, "failed to parse registered ModelInfo");
    }

    const ModelCategory category = preferred_category_for(request, model);
    const InferenceFramework framework = preferred_framework_for(request, model);
    const SDKComponent component = component_for_category(category);
    const rac_primitive_t primitive = primitive_for_component(component);
    const ModelArtifactResolution artifact_resolution = resolve_model_artifacts(model);
    const std::string& resolved_path = artifact_resolution.resolved_path;

    if (component == runanywhere::v1::SDK_COMPONENT_UNSPECIFIED ||
        primitive == RAC_PRIMITIVE_UNSPECIFIED) {
        ModelLoadResult result =
            make_load_result(false, request.model_id(), category, framework, resolved_path,
                             artifact_resolution.artifacts, 0,
                             "model category is not supported by lifecycle routing");
        publish_component_event(component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                request.model_id(), &result, nullptr,
                                result.error_message().c_str());
        return copy_proto(result, out_result);
    }

    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto existing = g_loaded.find(component);
        if (existing != g_loaded.end() && !request.force_reload() &&
            existing->second->model_id == request.model_id() &&
            existing->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            ModelLoadResult result = make_load_result(
                true, existing->second->model_id, existing->second->category,
                existing->second->framework, existing->second->resolved_path,
                existing->second->resolved_artifacts, existing->second->loaded_at_ms, "");
            return copy_proto(result, out_result);
        }
    }

    std::shared_ptr<LoadedModel> previous_loaded;
    ComponentLifecycleState previous_state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto existing = g_loaded.find(component);
        if (existing != g_loaded.end()) {
            previous_state = existing->second->state;
            previous_loaded = existing->second;
            g_loaded.erase(existing);
        }
    }
    destroy_loaded_model(previous_loaded);

    publish_component_event(component, previous_state,
                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING, request.model_id(),
                            nullptr, nullptr, nullptr);

    rac_routing_hints_t hints = {};
    hints.preferred_engine_name = framework_to_plugin_name(framework, primitive);
    hints.no_fallback = hints.preferred_engine_name ? RAC_TRUE : RAC_FALSE;
    const rac_engine_vtable_t* vt = nullptr;
    rc = rac_plugin_route(primitive, static_cast<uint32_t>(model.format()), &hints, &vt);
    if (rc != RAC_SUCCESS || !vt) {
        std::string error = "no backend route supports requested model";
        if (hints.preferred_engine_name) {
            error += " for framework ";
            error += hints.preferred_engine_name;
        }
        ModelLoadResult result =
            make_load_result(false, request.model_id(), category, framework, resolved_path,
                             artifact_resolution.artifacts, 0, error);
        {
            std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
            auto failed = std::make_shared<LoadedModel>();
            failed->component = component;
            failed->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR;
            failed->model_id = request.model_id();
            failed->resolved_path = resolved_path;
            failed->mmproj_path = artifact_resolution.mmproj_path;
            failed->resolved_artifacts = artifact_resolution.artifacts;
            failed->category = category;
            failed->framework = framework;
            failed->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
            failed->updated_at_ms = now_ms();
            failed->error_message = error;
            g_loaded[component] = std::move(failed);
        }
        publish_component_event(component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                request.model_id(), &result, nullptr,
                                result.error_message().c_str());
        return copy_proto(result, out_result);
    }

    void* impl = nullptr;
    std::function<void()> destroy;
    rc = create_backend_impl(vt, primitive, resolved_path, artifact_resolution.mmproj_path, &impl,
                             &destroy);
    if (rc != RAC_SUCCESS) {
        ModelLoadResult result =
            make_load_result(false, request.model_id(), category, framework, resolved_path,
                             artifact_resolution.artifacts, 0, rac_error_message(rc));
        {
            std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
            auto failed = std::make_shared<LoadedModel>();
            failed->component = component;
            failed->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR;
            failed->model_id = request.model_id();
            failed->resolved_path = resolved_path;
            failed->mmproj_path = artifact_resolution.mmproj_path;
            failed->resolved_artifacts = artifact_resolution.artifacts;
            failed->category = category;
            failed->framework = framework;
            failed->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
            failed->updated_at_ms = now_ms();
            failed->error_message = result.error_message();
            g_loaded[component] = std::move(failed);
        }
        publish_component_event(component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                request.model_id(), &result, nullptr,
                                result.error_message().c_str());
        return copy_proto(result, out_result);
    }

    int64_t loaded_at_ms = now_ms();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto loaded = std::make_shared<LoadedModel>();
        loaded->component = component;
        loaded->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
        loaded->model_id = request.model_id();
        loaded->resolved_path = resolved_path;
        loaded->mmproj_path = artifact_resolution.mmproj_path;
        loaded->resolved_artifacts = artifact_resolution.artifacts;
        loaded->framework = framework;
        loaded->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
        loaded->category = category;
        loaded->primitive = primitive;
        if (primitive == RAC_PRIMITIVE_GENERATE_TEXT) {
            loaded->llm_ops = vt->llm_ops;
        } else if (primitive == RAC_PRIMITIVE_TRANSCRIBE) {
            loaded->stt_ops = vt->stt_ops;
        } else if (primitive == RAC_PRIMITIVE_SYNTHESIZE) {
            loaded->tts_ops = vt->tts_ops;
        } else if (primitive == RAC_PRIMITIVE_DETECT_VOICE) {
            loaded->vad_ops = vt->vad_ops;
        } else if (primitive == RAC_PRIMITIVE_EMBED) {
            loaded->embeddings_ops = vt->embedding_ops;
        } else if (primitive == RAC_PRIMITIVE_VLM) {
            loaded->vlm_ops = vt->vlm_ops;
        } else if (primitive == RAC_PRIMITIVE_DIFFUSION) {
            loaded->diffusion_ops = vt->diffusion_ops;
        }
        loaded->impl = impl;
        loaded->model.CopyFrom(model);
        loaded->loaded_at_ms = loaded_at_ms;
        loaded->updated_at_ms = loaded->loaded_at_ms;
        loaded->destroy = std::move(destroy);
        g_loaded[component] = std::move(loaded);
    }

    ModelLoadResult result =
        make_load_result(true, request.model_id(), category, framework, resolved_path,
                         artifact_resolution.artifacts, loaded_at_ms, "");
    publish_component_event(component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY, request.model_id(),
                            &result, nullptr, nullptr);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_model_lifecycle_unload_proto(const uint8_t* request_proto_bytes,
                                              size_t request_proto_size,
                                              rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "ModelUnloadRequest bytes are empty or too large");
    }
    ModelUnloadRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse ModelUnloadRequest");
    }

    std::vector<std::shared_ptr<LoadedModel>> unloaded;
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        for (auto it = g_loaded.begin(); it != g_loaded.end();) {
            const bool model_match =
                !request.model_id().empty() && it->second->model_id == request.model_id();
            const bool category_match =
                request.has_category() && it->second->category == request.category();
            const bool should_unload = request.unload_all() || model_match || category_match;
            if (!should_unload) {
                ++it;
                continue;
            }
            it->second->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
            it->second->updated_at_ms = now_ms();
            unloaded.push_back(it->second);
            it = g_loaded.erase(it);
        }
    }

    for (const auto& model : unloaded) {
        destroy_loaded_model(model);
    }

    ModelUnloadResult result;
    result.set_success(!unloaded.empty());
    if (unloaded.empty()) {
        result.set_error_message("no loaded model matched unload request");
    }
    for (const auto& model : unloaded) {
        result.add_unloaded_model_ids(model->model_id);
        publish_component_event(model->component,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_UNLOADING,
                                runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                model->model_id, nullptr, &result, nullptr);
    }
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_model_lifecycle_current_model_proto(const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "CurrentModelRequest bytes are empty or too large");
    }
    CurrentModelRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse CurrentModelRequest");
    }

    CurrentModelResult result;
    SDKComponent component = runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        for (const auto& pair : g_loaded) {
            if (!matches_current_filter(*pair.second, request.has_category(), request.category(),
                                        request.has_framework(), request.framework())) {
                continue;
            }
            result.set_model_id(pair.second->model_id);
            result.mutable_model()->CopyFrom(pair.second->model);
            result.set_loaded_at_unix_ms(pair.second->loaded_at_ms);
            result.set_found(true);
            result.set_category(pair.second->category);
            result.set_framework(pair.second->framework);
            result.set_resolved_path(pair.second->resolved_path);
            add_artifacts_to_result(pair.second->resolved_artifacts,
                                    result.mutable_resolved_artifacts());
            component = pair.second->component;
            break;
        }
    }
    if (result.model_id().empty()) {
        result.set_found(false);
    }
    publish_current_model_event(result, component);
    publish_component_event(
        component,
        result.model_id().empty() ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED
                                  : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
        result.model_id().empty() ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED
                                  : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
        result.model_id(), nullptr, nullptr, nullptr);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_component_lifecycle_snapshot_proto(uint32_t component,
                                                    rac_proto_buffer_t* out_snapshot) {
    if (!out_snapshot) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)component;
    return feature_unavailable(out_snapshot);
#else
    ComponentLifecycleSnapshot snapshot;
    const auto sdk_component = static_cast<SDKComponent>(component);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(sdk_component);
        fill_snapshot(it == g_loaded.end() ? nullptr : it->second.get(), sdk_component, &snapshot);
    }
    return copy_proto(snapshot, out_snapshot);
#endif
}

void rac_model_lifecycle_reset(void) {
#if defined(RAC_HAVE_PROTOBUF)
    std::vector<std::shared_ptr<LoadedModel>> loaded;
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        for (auto& pair : g_loaded) {
            loaded.push_back(pair.second);
        }
        g_loaded.clear();
    }
    for (const auto& model : loaded) {
        destroy_loaded_model(model);
    }
#endif
}

}  // extern "C"
