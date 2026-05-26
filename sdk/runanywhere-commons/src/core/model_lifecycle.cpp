/**
 * @file model_lifecycle.cpp
 * @brief Canonical model lifecycle C ABI over generated proto bytes.
 */

#include <algorithm>
#include <atomic>
#include <cctype>
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
#include "rac/core/rac_logger.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_route.h"
#include "rac/router/rac_routing_hints.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "download_service.pb.h"
#include "model_types.pb.h"
#include "sdk_events.pb.h"
#endif

#include <thread>

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
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
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
                            error_message && error_message[0] != '\0'
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
    if (error_message && error_message[0] != '\0') {
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
            // After the LLM/VLM plugin unification, llama.cpp publishes ONE
            // vtable named "llamacpp" with both llm_ops and vlm_ops slots
            // filled. Routing is by primitive on the same plugin entry, so
            // both LLM and VLM resolve to the same plugin name.
            (void)primitive;
            return "llamacpp";
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            // Voice primitives on ONNX-format models are typically served by
            // the Sherpa plugin (it advertises STT/TTS/VAD ops over ONNX
            // Runtime); the production "onnx" plugin only exposes embedding
            // ops. We intentionally do NOT pin to "sherpa" here so the router
            // picks the highest-priority registered plugin that actually
            // advertises the voice primitive — letting alternate voice
            // backends (whispercpp/whisperkit) or test mocks load when sherpa
            // is not present without hard-failing the load. The router's
            // primitive-support filter (rac_engine_router.cpp) skips engines
            // missing the requested ops, so non-voice plugins ("onnx" in
            // production) are still excluded.
            if (primitive == RAC_PRIMITIVE_DETECT_VOICE || primitive == RAC_PRIMITIVE_TRANSCRIBE ||
                primitive == RAC_PRIMITIVE_SYNTHESIZE) {
                return nullptr;
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

struct ModelArtifactResolution {
    std::string resolved_path;
    std::string mmproj_path;
    std::vector<ModelFileDescriptor> artifacts;
};

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

std::string lowercase_ascii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

bool path_has_extension(const std::string& path, const char* extension) {
    if (!extension) {
        return false;
    }
    const std::string lower_path = lowercase_ascii(path);
    const std::string lower_extension = "." + lowercase_ascii(extension);
    return lower_path.size() >= lower_extension.size() &&
           lower_path.compare(lower_path.size() - lower_extension.size(), lower_extension.size(),
                              lower_extension) == 0;
}

bool path_matches_proto_format(const std::string& path, ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_GGUF:
            return path_has_extension(path, "gguf");
        case runanywhere::v1::MODEL_FORMAT_GGML:
            return path_has_extension(path, "ggml");
        case runanywhere::v1::MODEL_FORMAT_ONNX:
            return path_has_extension(path, "onnx");
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return path_has_extension(path, "ort");
        case runanywhere::v1::MODEL_FORMAT_BIN:
        case runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT:
            return path_has_extension(path, "bin");
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
            return path_has_extension(path, "mlmodel");
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return path_has_extension(path, "mlpackage");
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
            return path_has_extension(path, "tflite");
        case runanywhere::v1::MODEL_FORMAT_SAFETENSORS:
            return path_has_extension(path, "safetensors");
        case runanywhere::v1::MODEL_FORMAT_ZIP:
            return path_has_extension(path, "zip");
        case runanywhere::v1::MODEL_FORMAT_COREML:
            return path_has_extension(path, "mlmodelc") || path_has_extension(path, "mlmodel") ||
                   path_has_extension(path, "mlpackage");
        case runanywhere::v1::MODEL_FORMAT_UNSPECIFIED:
        case runanywhere::v1::MODEL_FORMAT_UNKNOWN:
        default:
            return path_has_extension(path, "gguf") || path_has_extension(path, "ggml") ||
                   path_has_extension(path, "onnx") || path_has_extension(path, "ort") ||
                   path_has_extension(path, "bin") || path_has_extension(path, "mlmodel") ||
                   path_has_extension(path, "mlpackage") || path_has_extension(path, "mlmodelc") ||
                   path_has_extension(path, "tflite") || path_has_extension(path, "safetensors") ||
                   path_has_extension(path, "zip");
    }
}

bool path_is_absolute(const std::string& path) {
    return !path.empty() && (path[0] == '/' || path[0] == '\\' ||
                             (path.size() > 1 &&
                              std::isalpha(static_cast<unsigned char>(path[0])) && path[1] == ':'));
}

std::string join_model_path(const std::string& root, const std::string& relative_or_absolute) {
    if (relative_or_absolute.empty()) {
        return "";
    }
    if (path_is_absolute(relative_or_absolute) || root.empty()) {
        return relative_or_absolute;
    }
    if (root.back() == '/' || root.back() == '\\') {
        return root + relative_or_absolute;
    }
    return root + "/" + relative_or_absolute;
}

std::string descriptor_relative_path(const ModelFileDescriptor& file) {
    if (file.has_destination_path() && !file.destination_path().empty()) {
        return file.destination_path();
    }
    if (file.has_relative_path() && !file.relative_path().empty()) {
        return file.relative_path();
    }
    if (!file.filename().empty()) {
        return file.filename();
    }
    return "";
}

bool descriptor_is_mmproj(const ModelFileDescriptor& file) {
    if (file.role() == runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR) {
        return true;
    }
    const std::string name = lowercase_ascii(descriptor_relative_path(file));
    return name.find("mmproj") != std::string::npos || name.find("mm-proj") != std::string::npos ||
           name.find("vision-projector") != std::string::npos ||
           name.find("vision_projector") != std::string::npos ||
           name.find("multimodal_projector") != std::string::npos ||
           name.find("multi-modal-projector") != std::string::npos;
}

void append_synthesized_artifact(const ModelFileDescriptor& source, const std::string& root,
                                 std::vector<ModelFileDescriptor>* artifacts) {
    if (!artifacts) {
        return;
    }
    const std::string rel = descriptor_relative_path(source);
    if (rel.empty()) {
        return;
    }
    const std::string absolute = join_model_path(root, rel);
    for (const ModelFileDescriptor& existing : *artifacts) {
        if (existing.has_local_path() && existing.local_path() == absolute) {
            return;
        }
    }

    ModelFileDescriptor descriptor;
    descriptor.CopyFrom(source);
    if (!descriptor.has_relative_path() || descriptor.relative_path().empty()) {
        descriptor.set_relative_path(rel);
    }
    if (!descriptor.has_destination_path() || descriptor.destination_path().empty()) {
        descriptor.set_destination_path(rel);
    }
    if (descriptor.filename().empty()) {
        descriptor.set_filename(basename_of_path(rel));
    }
    descriptor.set_local_path(absolute);
    artifacts->push_back(std::move(descriptor));
}

void synthesize_artifact_resolution_from_descriptors(const ModelInfo& model,
                                                     const std::string& artifact_root,
                                                     ModelArtifactResolution* out) {
    if (!out || artifact_root.empty()) {
        return;
    }
    const bool can_set_primary = out->resolved_path.empty() || out->resolved_path == artifact_root;

    auto visit_descriptor = [&](const ModelFileDescriptor& file) {
        append_synthesized_artifact(file, artifact_root, &out->artifacts);
        const std::string rel = descriptor_relative_path(file);
        if (rel.empty()) {
            return;
        }
        const std::string absolute = join_model_path(artifact_root, rel);
        if (file.role() == runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL && can_set_primary) {
            out->resolved_path = absolute;
        }
        if (descriptor_is_mmproj(file) && out->mmproj_path.empty()) {
            out->mmproj_path = absolute;
        }
    };

    if (model.has_multi_file()) {
        for (const ModelFileDescriptor& file : model.multi_file().files()) {
            visit_descriptor(file);
        }
    }
    if (model.has_expected_files()) {
        for (const ModelFileDescriptor& file : model.expected_files().files()) {
            visit_descriptor(file);
        }
    }

    if (can_set_primary && out->resolved_path == artifact_root) {
        auto select_primary_candidate = [&](const ModelFileDescriptor& file) {
            if (descriptor_is_mmproj(file)) {
                return;
            }
            const std::string rel = descriptor_relative_path(file);
            if (!rel.empty() && path_matches_proto_format(rel, model.format())) {
                out->resolved_path = join_model_path(artifact_root, rel);
            }
        };
        if (model.has_multi_file()) {
            for (const ModelFileDescriptor& file : model.multi_file().files()) {
                if (out->resolved_path != artifact_root) {
                    break;
                }
                select_primary_candidate(file);
            }
        }
        if (out->resolved_path == artifact_root && model.has_expected_files()) {
            for (const ModelFileDescriptor& file : model.expected_files().files()) {
                if (out->resolved_path != artifact_root) {
                    break;
                }
                select_primary_candidate(file);
            }
        }
    }
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
    return R"({"mmproj_path":")" + json_escape(mmproj_path) + R"("})";
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
    // Registry local_path may point at a single file (legacy self-heal picked
    // mmproj first). Scan the containing folder so primary + companions resolve.
    std::string artifact_root = out.resolved_path;
    if (path_has_extension(artifact_root, "gguf") || path_has_extension(artifact_root, "onnx") ||
        path_has_extension(artifact_root, "bin") || path_has_extension(artifact_root, "ort")) {
        const size_t sep = artifact_root.find_last_of("/\\");
        if (sep != std::string::npos) {
            artifact_root = artifact_root.substr(0, sep);
        }
    }

    ProtoModelPathBridge bridge(model);
    rac_model_path_resolution_t resolution = {};
    const char* checksum = model.has_checksum_sha256() && !model.checksum_sha256().empty()
                               ? model.checksum_sha256().c_str()
                               : nullptr;
    const rac_result_t rc = rac_model_paths_resolve_artifact(
        &bridge.model, artifact_root.c_str(), checksum, &resolution);
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

    if (model.has_multi_file() || model.has_expected_files()) {
        synthesize_artifact_resolution_from_descriptors(model, artifact_root, &out);
    }
    return out;
}

// =============================================================================
// AUTO-DOWNLOAD ON LOAD (CLUSTER-19 examples-react-native-002)
// =============================================================================

// Detect models whose registry entry has not yet resolved into a local
// artifact. Both classic single-file and multi-file/expected-files entries
// surface "missing" the same way: `is_downloaded` flips to true only after
// the orchestrator landed the bytes, and `local_path` is set to the
// resolved primary artifact at the same time. Built-in models are
// considered always-available.
bool model_artifact_present(const ModelInfo& model) {
    if (model.has_built_in() && model.built_in()) {
        return true;
    }
    if (model.is_downloaded()) {
        return true;
    }
    if (!model.local_path().empty()) {
        return true;
    }
    return false;
}

bool model_has_download_source(const ModelInfo& model) {
    if (!model.download_url().empty()) {
        return true;
    }
    if (model.has_multi_file()) {
        for (const ModelFileDescriptor& file : model.multi_file().files()) {
            if (!file.url().empty()) {
                return true;
            }
        }
    }
    if (model.has_expected_files()) {
        for (const ModelFileDescriptor& file : model.expected_files().files()) {
            if (!file.url().empty()) {
                return true;
            }
        }
    }
    // ArchiveArtifact carries extraction metadata; the canonical download
    // URL still lives on ModelInfo.download_url. has_archive() alone is
    // not a download signal — only the top-level download_url field plus
    // the per-file URLs in multi_file/expected_files indicate a fetchable
    // source.
    return false;
}

// pass3-syn-cluster19: orchestrate plan→start→poll for a single model. Used
// by `rac_model_lifecycle_load_proto` when the caller opts into
// `validate_availability=true` and the registry entry has no resolved
// artifact yet, so SDK callers can collapse the legacy
// `getModel → downloadModel(asyncIterator) → loadModel` chain into a
// single `loadModel(id)` round-trip.
//
// Returns RAC_SUCCESS only after the download manager reports
// DOWNLOAD_STATE_COMPLETED for the spawned task; any FAILED / CANCELLED
// terminal state surfaces a structured error message in @p out_error.
// A `timeout_seconds` ceiling guards against indefinite hang when an HTTP
// transport stalls — five minutes mirrors the default per-file budget the
// orchestrator already enforces internally.
rac_result_t download_and_wait_for_model(const std::string& model_id,
                                         const ModelInfo& registered_model,
                                         std::string* out_error,
                                         int timeout_seconds = 300) {
    if (out_error) {
        out_error->clear();
    }
    if (rac_http_transport_is_registered() == RAC_FALSE) {
        if (out_error) {
            *out_error =
                "model is not downloaded and no HTTP transport is registered for auto-download";
        }
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Step 1 — produce a download plan from the registered ModelInfo. The
    // plan service handles per-platform path resolution and capability
    // checks; we forward the registry's view of the model so the planner
    // sees the same artifact descriptors the lifecycle path will use.
    runanywhere::v1::DownloadPlanRequest plan_request;
    plan_request.set_model_id(model_id);
    plan_request.mutable_model()->CopyFrom(registered_model);
    plan_request.set_validate_existing_bytes(true);
    std::vector<uint8_t> plan_bytes(plan_request.ByteSizeLong());
    if (!plan_bytes.empty() &&
        !plan_request.SerializeToArray(plan_bytes.data(), static_cast<int>(plan_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadPlanRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }
    rac_proto_buffer_t plan_out = {};
    rac_proto_buffer_init(&plan_out);
    rac_result_t rc =
        rac_download_plan_proto(plan_bytes.empty() ? nullptr : plan_bytes.data(),
                                plan_bytes.size(), &plan_out);
    if (rc != RAC_SUCCESS) {
        if (out_error) {
            *out_error = plan_out.error_message ? plan_out.error_message
                                                : "rac_download_plan_proto failed";
        }
        rac_proto_buffer_free(&plan_out);
        return rc;
    }
    runanywhere::v1::DownloadPlanResult plan_result;
    const bool plan_parsed =
        plan_result.ParseFromArray(plan_out.data, static_cast<int>(plan_out.size));
    rac_proto_buffer_free(&plan_out);
    if (!plan_parsed) {
        if (out_error) {
            *out_error = "failed to parse DownloadPlanResult";
        }
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!plan_result.can_start()) {
        if (out_error) {
            *out_error = plan_result.error_message().empty()
                             ? "download plan reports can_start=false"
                             : plan_result.error_message();
        }
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }

    // Step 2 — start the download. update_registry_on_completion=true so the
    // worker updates the registry entry with the resolved local_path; the
    // subsequent get_proto reread (in the outer load path) will then see
    // the populated artifact.
    runanywhere::v1::DownloadStartRequest start_request;
    start_request.set_model_id(model_id);
    start_request.mutable_plan()->CopyFrom(plan_result);
    start_request.set_update_registry_on_completion(true);
    std::vector<uint8_t> start_bytes(start_request.ByteSizeLong());
    if (!start_bytes.empty() &&
        !start_request.SerializeToArray(start_bytes.data(),
                                        static_cast<int>(start_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadStartRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }
    rac_proto_buffer_t start_out = {};
    rac_proto_buffer_init(&start_out);
    rc = rac_download_start_proto(start_bytes.empty() ? nullptr : start_bytes.data(),
                                  start_bytes.size(), &start_out);
    if (rc != RAC_SUCCESS) {
        if (out_error) {
            *out_error = start_out.error_message ? start_out.error_message
                                                 : "rac_download_start_proto failed";
        }
        rac_proto_buffer_free(&start_out);
        return rc;
    }
    runanywhere::v1::DownloadStartResult start_result;
    const bool start_parsed =
        start_result.ParseFromArray(start_out.data, static_cast<int>(start_out.size));
    rac_proto_buffer_free(&start_out);
    if (!start_parsed) {
        if (out_error) {
            *out_error = "failed to parse DownloadStartResult";
        }
        return RAC_ERROR_DECODING_ERROR;
    }
    if (!start_result.accepted() || start_result.task_id().empty()) {
        if (out_error) {
            *out_error = start_result.error_message().empty()
                             ? "download orchestrator rejected start request"
                             : start_result.error_message();
        }
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }

    const std::string task_id = start_result.task_id();
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(timeout_seconds);

    // Step 3 — poll DownloadSubscribeRequest until the task reaches a
    // terminal state. The orchestrator's progress poll is a cheap read of
    // the latest snapshot, so a 100 ms cadence keeps the wait responsive
    // without burning CPU; HTTP completion is already async inside the
    // orchestrator worker.
    runanywhere::v1::DownloadSubscribeRequest subscribe_request;
    subscribe_request.set_model_id(model_id);
    subscribe_request.set_task_id(task_id);
    std::vector<uint8_t> subscribe_bytes(subscribe_request.ByteSizeLong());
    if (!subscribe_bytes.empty() &&
        !subscribe_request.SerializeToArray(subscribe_bytes.data(),
                                            static_cast<int>(subscribe_bytes.size()))) {
        if (out_error) {
            *out_error = "failed to serialize DownloadSubscribeRequest";
        }
        return RAC_ERROR_ENCODING_ERROR;
    }

    while (true) {
        if (std::chrono::steady_clock::now() >= deadline) {
            if (out_error) {
                *out_error = "auto-download timeout while loading model";
            }
            return RAC_ERROR_TIMEOUT;
        }

        rac_proto_buffer_t progress_out = {};
        rac_proto_buffer_init(&progress_out);
        rc = rac_download_progress_poll_proto(
            subscribe_bytes.empty() ? nullptr : subscribe_bytes.data(),
            subscribe_bytes.size(), &progress_out);
        if (rc != RAC_SUCCESS) {
            if (out_error) {
                *out_error = progress_out.error_message
                                 ? progress_out.error_message
                                 : "rac_download_progress_poll_proto failed";
            }
            rac_proto_buffer_free(&progress_out);
            return rc;
        }
        runanywhere::v1::DownloadProgress progress;
        const bool progress_parsed =
            progress.ParseFromArray(progress_out.data, static_cast<int>(progress_out.size));
        rac_proto_buffer_free(&progress_out);
        if (!progress_parsed) {
            if (out_error) {
                *out_error = "failed to parse DownloadProgress";
            }
            return RAC_ERROR_DECODING_ERROR;
        }

        const auto state = progress.state();
        if (state == runanywhere::v1::DOWNLOAD_STATE_COMPLETED) {
            return RAC_SUCCESS;
        }
        if (state == runanywhere::v1::DOWNLOAD_STATE_FAILED) {
            if (out_error) {
                *out_error = progress.error_message().empty() ? "auto-download failed"
                                                              : progress.error_message();
            }
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        if (state == runanywhere::v1::DOWNLOAD_STATE_CANCELLED) {
            if (out_error) {
                *out_error = "auto-download cancelled";
            }
            return RAC_ERROR_CANCELLED;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
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

    // CLUSTER-19 examples-react-native-002: collapse the legacy
    // `getModel → downloadModel(asyncIterator) → loadModel` chain into a
    // single `loadModel(id)` call when callers opt in via
    // `validate_availability=true`. If the registry says the model is
    // missing on disk AND the entry advertises a download source, drive
    // the canonical download orchestrator before continuing and re-fetch
    // the ModelInfo so the post-download local_path is observed.
    if (request.validate_availability() && !model_artifact_present(model) &&
        model_has_download_source(model)) {
        std::string dl_error;
        const rac_result_t dl_rc =
            download_and_wait_for_model(request.model_id(), model, &dl_error);
        if (dl_rc != RAC_SUCCESS) {
            const ModelCategory fail_category = preferred_category_for(request, model);
            const InferenceFramework fail_framework = preferred_framework_for(request, model);
            ModelLoadResult result = make_load_result(
                false, request.model_id(), fail_category, fail_framework, "", {}, 0,
                dl_error.empty() ? "auto-download failed" : dl_error);
            publish_component_event(component_for_category(fail_category),
                                    runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                    runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                    request.model_id(), &result, nullptr,
                                    result.error_message().c_str());
            return copy_proto(result, out_result);
        }

        // Re-fetch the registry entry — the download worker calls
        // rac_model_registry_update_download_status() on success
        // (update_registry_on_completion=true above), so the refreshed
        // ModelInfo carries the now-populated local_path.
        uint8_t* refreshed_bytes = nullptr;
        size_t refreshed_size = 0;
        const rac_result_t refetch_rc = rac_model_registry_get_proto(
            registry, request.model_id().c_str(), &refreshed_bytes, &refreshed_size);
        if (refetch_rc == RAC_SUCCESS && refreshed_bytes) {
            ModelInfo refreshed;
            if (refreshed.ParseFromArray(refreshed_bytes, static_cast<int>(refreshed_size))) {
                model.Swap(&refreshed);
            }
            rac_model_registry_proto_free(refreshed_bytes);
        }
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
    RAC_LOG_INFO("ModelLifecycle", "Model load succeeded for %s", request.model_id().c_str());
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
