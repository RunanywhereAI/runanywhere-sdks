/**
 * @file model_lifecycle_translation.cpp
 * @brief Proto<->C translation + event-publish helpers for model lifecycle.
 *
 * Extracted from the original `model_lifecycle.cpp`
 * SRP split. Owns the small, side-effect-free helpers that translate
 * protobuf enums to C enums, build identifiers/timestamps, escape paths,
 * and publish lifecycle SDKEvents. No global state ownership.
 */

#include "model_lifecycle_internal.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

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

runanywhere::v1::SDKComponent component_for_category(runanywhere::v1::ModelCategory category) {
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

rac_primitive_t primitive_for_component(runanywhere::v1::SDKComponent component) {
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

const char* framework_to_plugin_name(runanywhere::v1::InferenceFramework framework,
                                     rac_primitive_t primitive) {
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
            // backends or test mocks load when sherpa is not present
            // without hard-failing the load. The router's
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

rac_model_category_t c_category_from_proto(runanywhere::v1::ModelCategory category) {
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

rac_model_format_t c_format_from_proto(runanywhere::v1::ModelFormat format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<rac_model_format_t>(value)
                                                       : RAC_MODEL_FORMAT_UNKNOWN;
}

rac_inference_framework_t c_framework_from_proto(runanywhere::v1::InferenceFramework framework) {
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

rac_model_file_role_t c_file_role_from_proto(runanywhere::v1::ModelFileRole role) {
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

runanywhere::v1::ModelFileRole proto_file_role_from_resolved(rac_resolved_model_file_role_t role) {
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

namespace {

void populate_event_envelope(runanywhere::v1::SDKEvent* event,
                             runanywhere::v1::EventCategory category,
                             runanywhere::v1::ErrorSeverity severity,
                             runanywhere::v1::SDKComponent component) {
    event->set_id(generate_event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(component);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

rac_result_t publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    return rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
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

}  // namespace

void publish_component_event(runanywhere::v1::SDKComponent component,
                             runanywhere::v1::ComponentLifecycleState previous,
                             runanywhere::v1::ComponentLifecycleState current,
                             const std::string& model_id,
                             const runanywhere::v1::ModelLoadResult* load_result,
                             const runanywhere::v1::ModelUnloadResult* unload_result,
                             const char* error_message) {
    runanywhere::v1::SDKEvent event;
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

void publish_current_model_event(const runanywhere::v1::CurrentModelResult& result,
                                 runanywhere::v1::SDKComponent component) {
    runanywhere::v1::SDKEvent event;
    populate_event_envelope(&event, runanywhere::v1::EVENT_CATEGORY_MODEL,
                            runanywhere::v1::ERROR_SEVERITY_INFO, component);
    auto* registry = event.mutable_model_registry();
    registry->set_kind(runanywhere::v1::MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED);
    registry->set_model_id(result.model_id());
    registry->set_assigned_component(component);
    registry->mutable_current_model_result()->CopyFrom(result);
    (void)publish_event(event);
}

std::string vlm_config_json(const std::string& mmproj_path) {
    if (mmproj_path.empty()) {
        return "";
    }
    return R"({"mmproj_path":")" + json_escape(mmproj_path) + R"("})";
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

#endif  // RAC_HAVE_PROTOBUF

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

}  // namespace rac::core::model_lifecycle::detail
