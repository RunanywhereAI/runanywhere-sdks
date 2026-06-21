/**
 * @file tts_module.cpp
 * @brief Unified TTS feature module.
 *
 * W4 component unification: merges the former tts_component.cpp (handle-based
 * component path + the *_component_*_proto verbs) with TTS's slice of
 * rac_nonllm_lifecycle_proto_abi.cpp (the handle-less
 * rac_tts_synthesize_lifecycle_proto / _stream / stop / list_voices verbs)
 * into one TU.
 *
 * The component section is a direct translation of Swift's TTSCapability.swift;
 * do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <random>
#include <string>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_proto_adapters.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_stream.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "tts_options.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_tts_component {
    rac_handle_t lifecycle;
    rac_tts_config_t config;
    rac_tts_options_t default_options;
    std::mutex mtx;

    /** Resolved inference framework (defaults to ONNX, the primary TTS backend) */
    rac_inference_framework_t actual_framework;

    rac_tts_component() : lifecycle(nullptr), actual_framework(RAC_FRAMEWORK_ONNX) {
        // Initialize with defaults - matches rac_tts_types.h rac_tts_config_t
        config = RAC_TTS_CONFIG_DEFAULT;

        default_options = RAC_TTS_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Generate a simple UUID v4-like string for event tracking
static std::string generate_uuid_v4() {
    static thread_local std::mt19937 gen(std::random_device{}());
    static thread_local std::uniform_int_distribution<> dis(0, 15);
    static const char* hex = "0123456789abcdef";
    std::string uuid = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";
    for (char& ch : uuid) {
        if (ch == 'x') {
            ch = hex[dis(gen)];
        } else if (ch == 'y') {
            ch = hex[(dis(gen) % 4) + 8];
        }
    }
    return uuid;
}

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool proto_bytes_valid(const uint8_t* bytes, size_t size) {
    return rac::proto::bytes_valid(bytes, size);
}

const void* proto_parse_data(const uint8_t* bytes, size_t size) {
    return rac::proto::parse_bytes(bytes, size);
}

rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize TTS proto result");
}

runanywhere::v1::AudioFormat proto_audio_format(rac_audio_format_enum_t format) {
    switch (format) {
        case RAC_AUDIO_FORMAT_PCM:
            return runanywhere::v1::AUDIO_FORMAT_PCM;
        case RAC_AUDIO_FORMAT_WAV:
            return runanywhere::v1::AUDIO_FORMAT_WAV;
        case RAC_AUDIO_FORMAT_MP3:
            return runanywhere::v1::AUDIO_FORMAT_MP3;
        case RAC_AUDIO_FORMAT_OPUS:
            return runanywhere::v1::AUDIO_FORMAT_OPUS;
        case RAC_AUDIO_FORMAT_AAC:
            return runanywhere::v1::AUDIO_FORMAT_AAC;
        case RAC_AUDIO_FORMAT_FLAC:
            return runanywhere::v1::AUDIO_FORMAT_FLAC;
        default:
            return runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED;
    }
}

rac_audio_format_enum_t c_audio_format(runanywhere::v1::AudioFormat format) {
    switch (format) {
        case runanywhere::v1::AUDIO_FORMAT_WAV:
            return RAC_AUDIO_FORMAT_WAV;
        case runanywhere::v1::AUDIO_FORMAT_MP3:
            return RAC_AUDIO_FORMAT_MP3;
        case runanywhere::v1::AUDIO_FORMAT_OPUS:
            return RAC_AUDIO_FORMAT_OPUS;
        case runanywhere::v1::AUDIO_FORMAT_AAC:
            return RAC_AUDIO_FORMAT_AAC;
        case runanywhere::v1::AUDIO_FORMAT_FLAC:
            return RAC_AUDIO_FORMAT_FLAC;
        case runanywhere::v1::AUDIO_FORMAT_PCM:
        case runanywhere::v1::AUDIO_FORMAT_PCM_S16LE:
        default:
            return RAC_AUDIO_FORMAT_PCM;
    }
}

rac_tts_options_t options_from_proto(const runanywhere::v1::TTSOptions& proto,
                                     const rac_tts_options_t& defaults) {
    rac_tts_options_t options = defaults;
    if (!proto.voice().empty()) {
        options.voice = proto.voice().c_str();
    }
    if (!proto.language_code().empty()) {
        options.language = proto.language_code().c_str();
    }
    if (proto.speaking_rate() > 0.0f) {
        options.rate = proto.speaking_rate();
    }
    if (proto.pitch() > 0.0f) {
        options.pitch = proto.pitch();
    }
    if (proto.volume() > 0.0f) {
        options.volume = proto.volume();
    }
    options.use_ssml = proto.enable_ssml() ? RAC_TRUE : RAC_FALSE;
    options.audio_format = c_audio_format(proto.audio_format());
    return options;
}

int64_t estimate_pcm_f32_duration_ms(size_t audio_size, int32_t sample_rate) {
    const int32_t rate = sample_rate > 0 ? sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE;
    return static_cast<int64_t>((static_cast<double>(audio_size) /
                                 static_cast<double>(sizeof(float)) / static_cast<double>(rate)) *
                                1000.0);
}

void fill_tts_output(const rac_tts_result_t& result, const char* text, const char* voice_id,
                     const rac_tts_options_t& options, runanywhere::v1::TTSOutput* out) {
    if (result.audio_data && result.audio_size > 0) {
        out->set_audio_data(result.audio_data, result.audio_size);
    }
    out->set_audio_format(proto_audio_format(result.audio_format));
    out->set_sample_rate(result.sample_rate);
    out->set_duration_ms(result.duration_ms);
    out->set_timestamp_ms(rac_get_current_time_ms());

    auto* metadata = out->mutable_metadata();
    if (voice_id) {
        metadata->set_voice_id(voice_id);
    } else if (options.voice) {
        metadata->set_voice_id(options.voice);
    }
    if (options.language) {
        metadata->set_language_code(options.language);
    }
    metadata->set_processing_time_ms(result.processing_time_ms);
    metadata->set_character_count(text ? static_cast<int32_t>(std::strlen(text)) : 0);
    metadata->set_audio_duration_ms(result.duration_ms);
}

void publish_tts_voice_event(runanywhere::v1::VoiceEventKind kind, int64_t duration_ms,
                             rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::SDKEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_id(generate_uuid_v4());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_TTS);
    event.set_component(runanywhere::v1::SDK_COMPONENT_TTS);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    event.set_operation_id("tts.synthesize");
    event.set_severity(error_code == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                 : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* voice = event.mutable_voice();
    voice->set_kind(kind);
    voice->set_duration_ms(duration_ms);
    if (error_code != RAC_SUCCESS) {
        voice->set_error(rac_error_message(error_code));
    }

    // Route through the events layer so TTS telemetry reaches the telemetry +
    // log sinks per the destination bitmask, not just the public proto stream.
    (void)rac::events::publish_prebuilt(event);
}

// Emit a fully-populated TTS VoiceLifecycleEvent from the lifecycle-proto path.
// The lifecycle ABI (rac_tts_synthesize_lifecycle_proto) calls the service vtable
// directly and would otherwise publish nothing, so SDK consumers — which all use
// the lifecycle path — got no TTS telemetry. Mirrors the rich event the
// handle-based rac_tts_component_synthesize emits. Pass 0 / nullptr for fields
// that don't apply to the given kind (started vs completed vs failed).
void publish_tts_lifecycle_event(runanywhere::v1::VoiceEventKind kind, const char* synthesis_id,
                                 const char* model_id, int32_t char_count,
                                 int64_t audio_duration_ms, int32_t audio_size_bytes,
                                 int64_t processing_ms, int32_t sample_rate, const char* error,
                                 const char* framework_name = nullptr) {
    runanywhere::v1::VoiceLifecycleEvent voice;
    voice.set_kind(kind);
    if (model_id != nullptr && model_id[0] != '\0') {
        voice.set_model_id(model_id);
    }
    if (char_count > 0) {
        voice.set_character_count(char_count);
    }
    if (audio_duration_ms > 0) {
        voice.set_audio_duration_ms(audio_duration_ms);
    }
    if (audio_size_bytes > 0) {
        voice.set_audio_size_bytes_tts(audio_size_bytes);
    }
    if (processing_ms > 0) {
        voice.set_processing_duration_ms(processing_ms);
        if (char_count > 0) {
            voice.set_characters_per_second(static_cast<double>(char_count) * 1000.0 /
                                            static_cast<double>(processing_ms));
        }
    }
    if (sample_rate > 0) {
        voice.set_sample_rate(sample_rate);
    }
    if (error != nullptr && error[0] != '\0') {
        voice.set_error(error);
    }
    // Framework — proto path otherwise leaves it unset (track reads
    // v.framework() via framework_proto_to_string). Convert the lifecycle ref's
    // framework name to the proto enum like the component path does.
    if (framework_name != nullptr && framework_name[0] != '\0') {
        rac_inference_framework_t fw = RAC_FRAMEWORK_UNKNOWN;
        (void)rac_inference_framework_from_string(framework_name, &fw);
        voice.set_framework(rac::events::framework_to_proto_int(fw));
    }
    rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                      runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                      synthesis_id);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

static rac_result_t tts_create_service(const char* voice_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    RAC_LOG_INFO("TTS.Component", "Creating TTS service");

    rac_result_t result = rac_tts_create(voice_id, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("TTS.Component", "Failed to create TTS service");
        return result;
    }

    result = rac_tts_initialize(*out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("TTS.Component", "Failed to initialize TTS service");
        rac_tts_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO("TTS.Component", "TTS service created successfully");
    return RAC_SUCCESS;
}

static void tts_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_INFO("TTS.Component", "Destroying TTS service");
        rac_tts_cleanup(service);
        rac_tts_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_tts_component_create(rac_handle_t* out_handle) {
    return rac::features::create_lifecycle_component<rac_tts_component>(
        out_handle, RAC_RESOURCE_TYPE_TTS_VOICE, "TTS.Lifecycle", tts_create_service,
        tts_destroy_service, "TTS.Component", "TTS component created");
}

extern "C" rac_result_t rac_tts_component_configure(rac_handle_t handle,
                                                    const rac_tts_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    // Resolve actual framework: if caller explicitly set one (not -1=auto), use it;
    // otherwise keep the default (RAC_FRAMEWORK_ONNX for TTS components)
    if (config->preferred_framework >= 0 &&
        config->preferred_framework != static_cast<int32_t>(RAC_FRAMEWORK_UNKNOWN)) {
        component->actual_framework =
            static_cast<rac_inference_framework_t>(config->preferred_framework);
    }

    // Update default options based on config - matches rac_tts_config_t fields
    if (config->speaking_rate > 0) {
        component->default_options.rate = config->speaking_rate;
    }
    if (config->pitch > 0) {
        component->default_options.pitch = config->pitch;
    }
    if (config->volume > 0) {
        component->default_options.volume = config->volume;
    }
    if (config->language) {
        component->default_options.language = config->language;
    }
    if (config->voice) {
        component->default_options.voice = config->voice;
    }
    component->default_options.use_ssml = config->enable_ssml;

    RAC_LOG_INFO("TTS.Component", "TTS component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_tts_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_tts_component_get_voice_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_tts_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);

    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    // B-FL-5-001 sibling fix: clear any lingering proto-stream callback
    // registration keyed by this component handle BEFORE freeing the memory.
    // Even though rac_tts_stream_start_proto is currently NOT_IMPLEMENTED,
    // the slot registry is live and reachable via the public ABI — clearing
    // here prevents stale wire-seq / stale user_data when the handle heap
    // address is reused by a fresh component.
    rac_tts_unset_stream_proto_callback(handle);
    // spin-wait for any in-flight
    // dispatch_tts_stream_event() invocation on another thread before freeing
    // the component. Mirrors rac_vlm_component_destroy / rac_llm_component_destroy.
    rac_tts_proto_quiesce();

    RAC_LOG_INFO("TTS.Component", "TTS component destroyed");

    delete component;
}

// =============================================================================
// VOICE LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_tts_component_load_voice(rac_handle_t handle, const char* voice_path,
                                                     const char* voice_id, const char* voice_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // B-FL-5-001 sibling v2 fix: clear any prior proto-stream callback
    // registration BEFORE re-loading the voice. The load_voice path elides
    // destroy → original destroy-time fix never fires for handle reuse, so
    // the wire-seq counter in g_slots() would retain its prior value.
    rac_tts_unset_stream_proto_callback(handle);
    // drain any in-flight dispatcher bound to the
    // previous voice before swapping in the new one so user_data captured by
    // the previous registration can be safely freed.
    rac_tts_proto_quiesce();

    // Emit voice load started event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::ModelEvent m;
        m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_STARTED);
        if (voice_id)
            m.set_model_id(voice_id);
        if (voice_name)
            m.set_model_name(voice_name);
        m.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        rac::events::publish(runanywhere::v1::SDK_COMPONENT_TTS,
                             runanywhere::v1::EVENT_CATEGORY_MODEL, std::move(m));
    }
#endif

    auto load_start = std::chrono::steady_clock::now();

    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, voice_path, voice_id, voice_name, &service);

    double load_duration_ms =
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - load_start)
                                .count());

#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::ModelEvent m;
        if (voice_id)
            m.set_model_id(voice_id);
        if (voice_name)
            m.set_model_name(voice_name);
        m.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        m.set_duration_ms(static_cast<int64_t>(load_duration_ms));
        if (result != RAC_SUCCESS) {
            m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_FAILED);
            m.set_error("Voice load failed");
        } else {
            m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED);
        }
        rac::events::publish(runanywhere::v1::SDK_COMPONENT_TTS,
                             runanywhere::v1::EVENT_CATEGORY_MODEL, std::move(m));
    }
#endif

    return result;
}

extern "C" rac_result_t rac_tts_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_stop(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (service) {
        rac_tts_stop(service);
    }

    RAC_LOG_INFO("TTS.Component", "Synthesis stop requested");

    return RAC_SUCCESS;
}

// =============================================================================
// SYNTHESIS API
// =============================================================================

extern "C" rac_result_t rac_tts_component_synthesize(rac_handle_t handle, const char* text,
                                                     const rac_tts_options_t* options,
                                                     rac_tts_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);

    // Acquire lock only for state reads, release before long-running synthesis
    std::string synthesis_id = generate_uuid_v4();
    rac_handle_t service = nullptr;
    rac_tts_options_t local_options;
    rac_inference_framework_t framework;
    const char* voice_id = nullptr;
    const char* voice_name = nullptr;

    {
        std::lock_guard<std::mutex> lock(component->mtx);

        voice_id = rac_lifecycle_get_model_id(component->lifecycle);
        voice_name = rac_lifecycle_get_model_name(component->lifecycle);
        framework = component->actual_framework;

        // Copy effective options to local so we can release the lock
        local_options = options ? *options : component->default_options;

        rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("TTS.Component", "No voice loaded - cannot synthesize");
            // Emit SYNTHESIS_FAILED event
#if defined(RAC_HAVE_PROTOBUF)
            {
                runanywhere::v1::VoiceLifecycleEvent voice;
                voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED);
                if (voice_id)
                    voice.set_model_id(voice_id);
                if (voice_name)
                    voice.set_model_name(voice_name);
                voice.set_framework(rac::events::framework_to_proto_int(framework));
                voice.set_error("No voice loaded");
                rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                                  runanywhere::v1::EVENT_CATEGORY_TTS,
                                                  std::move(voice), synthesis_id.c_str());
            }
#endif
            return result;
        }
    }
    // Lock released — safe to do long-running synthesis

    // Emit SYNTHESIS_STARTED event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED);
        if (voice_id)
            voice.set_model_id(voice_id);
        if (voice_name)
            voice.set_model_name(voice_name);
        voice.set_character_count(static_cast<int32_t>(std::strlen(text)));
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                          runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                          synthesis_id.c_str());
    }
#endif

    RAC_LOG_INFO("TTS.Component", "Synthesizing text");

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result = rac_tts_synthesize(service, text, &local_options, out_result);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("TTS.Component", "Synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesize");
        // Emit SYNTHESIS_FAILED event
#if defined(RAC_HAVE_PROTOBUF)
        {
            runanywhere::v1::VoiceLifecycleEvent voice;
            voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED);
            if (voice_id)
                voice.set_model_id(voice_id);
            if (voice_name)
                voice.set_model_name(voice_name);
            voice.set_processing_duration_ms(static_cast<int64_t>(duration.count()));
            voice.set_framework(rac::events::framework_to_proto_int(framework));
            voice.set_error("Synthesis failed");
            rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                              runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                              synthesis_id.c_str());
        }
#endif
        return result;
    }

    if (out_result->processing_time_ms == 0) {
        out_result->processing_time_ms = duration.count();
    }

    // Emit SYNTHESIS_COMPLETED event
    {
        int32_t char_count = static_cast<int32_t>(std::strlen(text));
        double processing_ms = static_cast<double>(out_result->processing_time_ms);
        double chars_per_sec = processing_ms > 0 ? (char_count * 1000.0 / processing_ms) : 0.0;

#if defined(RAC_HAVE_PROTOBUF)
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED);
        if (voice_id)
            voice.set_model_id(voice_id);
        if (voice_name)
            voice.set_model_name(voice_name);
        voice.set_character_count(char_count);
        voice.set_audio_duration_ms(static_cast<int64_t>(out_result->duration_ms));
        voice.set_audio_size_bytes_tts(static_cast<int32_t>(out_result->audio_size));
        voice.set_processing_duration_ms(static_cast<int64_t>(processing_ms));
        voice.set_characters_per_second(chars_per_sec);
        voice.set_sample_rate(static_cast<int32_t>(out_result->sample_rate));
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                          runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                          synthesis_id.c_str());
#endif
    }

    RAC_LOG_INFO("TTS.Component", "Synthesis completed");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_tts_component_synthesize_stream(rac_handle_t handle, const char* text,
                                                            const rac_tts_options_t* options,
                                                            rac_tts_stream_callback_t callback,
                                                            void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);

    // Acquire lock only for state reads, release before long-running synthesis
    std::string synthesis_id = generate_uuid_v4();
    rac_handle_t service = nullptr;
    rac_tts_options_t local_options;
    rac_inference_framework_t framework;
    const char* voice_id = nullptr;
    const char* voice_name = nullptr;
    int32_t char_count = static_cast<int32_t>(std::strlen(text));

    {
        std::lock_guard<std::mutex> lock(component->mtx);

        voice_id = rac_lifecycle_get_model_id(component->lifecycle);
        voice_name = rac_lifecycle_get_model_name(component->lifecycle);
        framework = component->actual_framework;

        // Copy effective options to local so we can release the lock
        local_options = options ? *options : component->default_options;

        rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("TTS.Component", "No voice loaded - cannot synthesize stream");
            // Emit SYNTHESIS_FAILED event
#if defined(RAC_HAVE_PROTOBUF)
            {
                runanywhere::v1::VoiceLifecycleEvent voice;
                voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED);
                if (voice_id)
                    voice.set_model_id(voice_id);
                if (voice_name)
                    voice.set_model_name(voice_name);
                voice.set_framework(rac::events::framework_to_proto_int(framework));
                voice.set_error("No voice loaded");
                rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                                  runanywhere::v1::EVENT_CATEGORY_TTS,
                                                  std::move(voice), synthesis_id.c_str());
            }
#endif
            return result;
        }
    }
    // Lock released — safe to do long-running synthesis

    // Emit SYNTHESIS_STARTED event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED);
        if (voice_id)
            voice.set_model_id(voice_id);
        if (voice_name)
            voice.set_model_name(voice_name);
        voice.set_character_count(char_count);
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                          runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                          synthesis_id.c_str());
    }
#endif

    RAC_LOG_INFO("TTS.Component", "Starting streaming synthesis");

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result =
        rac_tts_synthesize_stream(service, text, &local_options, callback, user_data);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("TTS.Component", "Streaming synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesizeStream");
        // Emit SYNTHESIS_FAILED event
#if defined(RAC_HAVE_PROTOBUF)
        {
            runanywhere::v1::VoiceLifecycleEvent voice;
            voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED);
            if (voice_id)
                voice.set_model_id(voice_id);
            if (voice_name)
                voice.set_model_name(voice_name);
            voice.set_processing_duration_ms(static_cast<int64_t>(duration.count()));
            voice.set_framework(rac::events::framework_to_proto_int(framework));
            voice.set_error("Streaming synthesis failed");
            rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                              runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                              synthesis_id.c_str());
        }
#endif
    } else {
        // Emit SYNTHESIS_COMPLETED event (streaming complete)
        double processing_ms = static_cast<double>(duration.count());
        double chars_per_sec = processing_ms > 0 ? (char_count * 1000.0 / processing_ms) : 0.0;

#if defined(RAC_HAVE_PROTOBUF)
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED);
        if (voice_id)
            voice.set_model_id(voice_id);
        if (voice_name)
            voice.set_model_name(voice_name);
        voice.set_character_count(char_count);
        voice.set_processing_duration_ms(static_cast<int64_t>(processing_ms));
        voice.set_characters_per_second(chars_per_sec);
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_TTS,
                                          runanywhere::v1::EVENT_CATEGORY_TTS, std::move(voice),
                                          synthesis_id.c_str());
#endif
    }

    return result;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_tts_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_tts_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

// =============================================================================
// LANGUAGE INTROSPECTION
// =============================================================================

extern "C" rac_result_t rac_tts_component_get_supported_languages(rac_handle_t handle,
                                                                  char** out_json) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_json)
        return RAC_ERROR_INVALID_ARGUMENT;

    *out_json = nullptr;

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("TTS.Component", "No voice loaded - cannot enumerate languages");
        return result;
    }

    return rac_tts_get_languages(service, out_json);
}

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

extern "C" rac_result_t
rac_tts_component_list_voices_proto(rac_handle_t handle, rac_tts_proto_voice_callback_fn callback,
                                    void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = reinterpret_cast<rac_tts_component*>(handle);
    rac_handle_t service = nullptr;
    const char* loaded_voice = nullptr;
    {
        std::lock_guard<std::mutex> lock(component->mtx);
        loaded_voice = rac_lifecycle_get_model_id(component->lifecycle);
        rac_result_t rc = rac_lifecycle_require_service(component->lifecycle, &service);
        if (rc != RAC_SUCCESS) {
            publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
            (void)rac_sdk_event_publish_failure(rc, "TTS voice is not loaded", "tts", "listVoices",
                                                RAC_TRUE);
            return rc;
        }
    }

    rac_tts_info_t info = {};
    rac_result_t rc = rac_tts_get_info(service, &info);
    if (rc != RAC_SUCCESS) {
        (void)rac_sdk_event_publish_failure(rc, "TTS voice listing failed", "tts", "listVoices",
                                            RAC_TRUE);
        return rc;
    }

    bool emitted = false;
    for (size_t i = 0; i < info.num_voices; ++i) {
        const char* id = info.available_voices ? info.available_voices[i] : nullptr;
        if (!id) {
            continue;
        }
        runanywhere::v1::TTSVoiceInfo voice;
        voice.set_id(id);
        voice.set_display_name(id);
        const size_t size = voice.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !voice.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            return RAC_ERROR_ENCODING_ERROR;
        }
        callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_data);
        emitted = true;
    }

    if (!emitted && loaded_voice) {
        runanywhere::v1::TTSVoiceInfo voice;
        voice.set_id(loaded_voice);
        voice.set_display_name(loaded_voice);
        const size_t size = voice.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !voice.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            return RAC_ERROR_ENCODING_ERROR;
        }
        callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_data);
    }

    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_tts_component_synthesize_proto(rac_handle_t handle, const char* text,
                                                           const uint8_t* options_proto_bytes,
                                                           size_t options_proto_size,
                                                           rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)text;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle || !text) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "TTS synthesize proto requires handle and text");
    }
    if (!proto_bytes_valid(options_proto_bytes, options_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "TTSOptions bytes are invalid");
    }

    runanywhere::v1::TTSOptions proto_options;
    if (!proto_options.ParseFromArray(proto_parse_data(options_proto_bytes, options_proto_size),
                                      static_cast<int>(options_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse TTSOptions");
    }
    const char* voice_id = rac_tts_component_get_voice_id(handle);
    if (!voice_id) {
        const rac_result_t rc = RAC_ERROR_NOT_INITIALIZED;
        publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "TTS voice is not loaded", "tts", "synthesize",
                                            RAC_TRUE);
        return rac_proto_buffer_set_error(out_result, rc, "TTS voice is not loaded");
    }

    rac_tts_options_t options = options_from_proto(proto_options, RAC_TTS_OPTIONS_DEFAULT);
    rac_tts_result_t result = {};
    publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED, 0);
    rac_result_t rc = rac_tts_component_synthesize(handle, text, &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "TTS synthesis failed", "tts", "synthesize",
                                            RAC_TRUE);
        return rac_proto_buffer_set_error(out_result, rc, "TTS synthesis failed");
    }

    runanywhere::v1::TTSOutput output;
    fill_tts_output(result, text, voice_id, options, &output);
    publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED,
                            result.duration_ms);
    rac_tts_result_free(&result);
    return copy_proto_message(output, out_result);
#endif
}

extern "C" rac_result_t rac_tts_component_synthesize_stream_proto(
    rac_handle_t handle, const char* text, const uint8_t* options_proto_bytes,
    size_t options_proto_size, rac_tts_proto_chunk_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)text;
    (void)options_proto_bytes;
    (void)options_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !text || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!proto_bytes_valid(options_proto_bytes, options_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::TTSOptions proto_options;
    if (!proto_options.ParseFromArray(proto_parse_data(options_proto_bytes, options_proto_size),
                                      static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    const char* voice_id = rac_tts_component_get_voice_id(handle);
    if (!voice_id) {
        const rac_result_t rc = RAC_ERROR_NOT_INITIALIZED;
        publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "TTS voice is not loaded", "tts",
                                            "synthesizeStream", RAC_TRUE);
        return rc;
    }

    rac_tts_options_t options = options_from_proto(proto_options, RAC_TTS_OPTIONS_DEFAULT);
    struct StreamContext {
        rac_tts_proto_chunk_callback_fn callback;
        void* user_data;
        const char* text;
        const char* voice_id;
        rac_tts_options_t options;
    } context{.callback = callback,
              .user_data = user_data,
              .text = text,
              .voice_id = voice_id,
              .options = options};

    auto bridge = [](const void* audio_data, size_t audio_size, void* opaque) {
        auto* ctx = static_cast<StreamContext*>(opaque);
        runanywhere::v1::TTSOutput output;
        if (audio_data && audio_size > 0) {
            output.set_audio_data(audio_data, audio_size);
        }
        output.set_audio_format(proto_audio_format(ctx->options.audio_format));
        output.set_sample_rate(ctx->options.sample_rate > 0 ? ctx->options.sample_rate
                                                            : RAC_TTS_DEFAULT_SAMPLE_RATE);
        output.set_duration_ms(estimate_pcm_f32_duration_ms(audio_size, output.sample_rate()));
        output.set_timestamp_ms(rac_get_current_time_ms());
        auto* metadata = output.mutable_metadata();
        if (ctx->voice_id) {
            metadata->set_voice_id(ctx->voice_id);
        }
        if (ctx->options.language) {
            metadata->set_language_code(ctx->options.language);
        }
        metadata->set_character_count(ctx->text ? static_cast<int32_t>(std::strlen(ctx->text)) : 0);
        metadata->set_audio_duration_ms(output.duration_ms());
        const size_t size = output.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size == 0 || output.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
        }
    };

    publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED, 0);
    rac_result_t rc = rac_tts_component_synthesize_stream(handle, text, &options, bridge, &context);
    if (rc != RAC_SUCCESS) {
        publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "TTS streaming synthesis failed", "tts",
                                            "synthesizeStream", RAC_TRUE);
    }
    return rc;
#endif
}

// =============================================================================
// LIFECYCLE-OWNED GENERATED-PROTO C ABI (formerly TTS slice of
// rac_nonllm_lifecycle_proto_abi.cpp)
//
// Handle-less verbs that resolve the loaded voice via the global registry
// (rac::lifecycle::acquire_lifecycle_tts) rather than a component handle.
// =============================================================================

namespace {

#if defined(RAC_HAVE_PROTOBUF)

// Shared anon-ns helpers carried verbatim from rac_nonllm_lifecycle_proto_abi.cpp.
// Internal linkage keeps these distinct from the component-section helpers above
// (proto_bytes_valid / proto_parse_data / copy_proto_message) — no ODR clash.
bool valid_bytes(const uint8_t* bytes, size_t size) {
    return rac::proto::bytes_valid(bytes, size);
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    return rac::proto::parse_bytes(bytes, size);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac::proto::parse_error(out, message);
}

void free_tts_options(rac_tts_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->voice));
    if (options->language != RAC_TTS_OPTIONS_DEFAULT.language) {
        rac_free(const_cast<char*>(options->language));
    }
    *options = RAC_TTS_OPTIONS_DEFAULT;
}

rac_result_t parse_tts_request(const uint8_t* request_proto_bytes, size_t request_proto_size,
                               runanywhere::v1::TTSSynthesisRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "TTSSynthesisRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse TTSSynthesisRequest");
    }
    if (out_request->text().empty() && !out_request->has_ssml()) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "TTSSynthesisRequest.text or ssml is required");
    }
    return RAC_SUCCESS;
}

#endif  // RAC_HAVE_PROTOBUF

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

}  // namespace

extern "C" {

rac_result_t rac_tts_synthesize_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::TTSSynthesisRequest request;
    rac_result_t rc =
        parse_tts_request(request_proto_bytes, request_proto_size, &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    rac::lifecycle::LifecycleTtsRef ref;
    rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "TTS lifecycle voice/model is not loaded");
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_tts_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert TTSOptions");
    }
    if (request.has_options() && request.options().sample_rate() > 0) {
        options.sample_rate = request.options().sample_rate();
    }

    const bool use_ssml = request.has_ssml() && !request.ssml().empty();
    if (use_ssml) {
        options.use_ssml = RAC_TRUE;
    }
    const std::string& text = use_ssml ? request.ssml() : request.text();
    rac_tts_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_tts_result_t raw = {};

    const std::string synthesis_id = generate_uuid_v4();
    const int32_t char_count = static_cast<int32_t>(text.size());
    publish_tts_lifecycle_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED,
                                synthesis_id.c_str(), ref.model_id, char_count, 0, 0, 0, 0, nullptr,
                                ref.framework_name);

    const auto synth_start = std::chrono::steady_clock::now();
    rc = rac_tts_synthesize(&service, text.c_str(), &options, &raw);
    const int64_t processing_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                      std::chrono::steady_clock::now() - synth_start)
                                      .count();
    if (rc != RAC_SUCCESS) {
        publish_tts_lifecycle_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED,
                                    synthesis_id.c_str(), ref.model_id, char_count, 0, 0,
                                    processing_ms, 0, rac_error_message(rc), ref.framework_name);
        free_tts_options(&options);
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    publish_tts_lifecycle_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED,
                                synthesis_id.c_str(), ref.model_id, char_count,
                                static_cast<int64_t>(raw.duration_ms),
                                static_cast<int32_t>(raw.audio_size), processing_ms,
                                static_cast<int32_t>(raw.sample_rate), nullptr, ref.framework_name);

    runanywhere::v1::TTSOutput output;
    if (!rac::foundation::rac_tts_result_to_proto(&raw, &output)) {
        rac_tts_result_free(&raw);
        free_tts_options(&options);
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode TTSOutput");
    }
    output.set_timestamp_ms(rac_get_current_time_ms());
    output.set_is_final(true);
    output.set_error_code(RAC_SUCCESS);
    output.set_audio_size_bytes(static_cast<int64_t>(raw.audio_size));
    auto* metadata = output.mutable_metadata();
    metadata->set_voice_id(options.voice ? options.voice : (ref.model_id ? ref.model_id : ""));
    if (options.language) {
        metadata->set_language_code(options.language);
    }
    metadata->set_character_count(static_cast<int32_t>(text.size()));

    rc = copy_proto(output, out_result);
    rac_tts_result_free(&raw);
    free_tts_options(&options);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc;
#endif
}

// ---------------------------------------------------------------------------
// TTS lifecycle stream / stop ABIs (FLT-12)
// ---------------------------------------------------------------------------

rac_result_t rac_tts_synthesize_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_tts_lifecycle_stream_event_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_t error_buf;
    rac_proto_buffer_init(&error_buf);

    runanywhere::v1::TTSSynthesisRequest request;
    rac_result_t rc =
        parse_tts_request(request_proto_bytes, request_proto_size, &request, &error_buf);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&error_buf);
        return rc;
    }

    rac::lifecycle::LifecycleTtsRef ref;
    rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&error_buf);
        return rc;
    }

    if (!ref.ops || !ref.ops->synthesize_stream) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        rac_proto_buffer_free(&error_buf);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_tts_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        rac_proto_buffer_free(&error_buf);
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.has_options() && request.options().sample_rate() > 0) {
        options.sample_rate = request.options().sample_rate();
    }

    const bool use_ssml = request.has_ssml() && !request.ssml().empty();
    if (use_ssml) {
        options.use_ssml = RAC_TRUE;
    }
    const std::string& text = use_ssml ? request.ssml() : request.text();

    const std::string request_id =
        request.request_id().empty()
            ? std::string("tts-lifecycle-") + std::to_string(rac_get_current_time_ms())
            : request.request_id();

    struct StreamCtx {
        rac_tts_lifecycle_stream_event_callback_fn fn;
        void* user_data;
        std::string request_id;
        uint64_t next_seq;
        std::string voice_id;
        std::string language_code;
        int32_t sample_rate;
        rac_audio_format_enum_t audio_format;
        int32_t character_count;
    };
    StreamCtx ctx{.fn = callback,
                  .user_data = user_data,
                  .request_id = request_id,
                  .next_seq = 1,
                  .voice_id = options.voice ? options.voice : (ref.model_id ? ref.model_id : ""),
                  .language_code = options.language ? options.language : "",
                  .sample_rate =
                      options.sample_rate > 0 ? options.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE,
                  .audio_format = options.audio_format,
                  .character_count = static_cast<int32_t>(text.size())};

    auto emit_event = [](const runanywhere::v1::TTSStreamEvent& event,
                         rac_tts_lifecycle_stream_event_callback_fn fn, void* user_ctx) {
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_ctx);
    };

    // STARTED envelope.
    {
        runanywhere::v1::TTSStreamEvent started;
        started.set_seq(ctx.next_seq++);
        started.set_timestamp_us(rac_get_current_time_ms() * 1000);
        started.set_request_id(ctx.request_id);
        started.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_STARTED);
        emit_event(started, ctx.fn, ctx.user_data);
    }

    auto chunk_bridge = [](const void* audio_data, size_t audio_size, void* opaque) {
        auto* c = static_cast<StreamCtx*>(opaque);
        runanywhere::v1::TTSStreamEvent event;
        event.set_seq(c->next_seq++);
        event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        event.set_request_id(c->request_id);
        event.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_AUDIO_CHUNK);
        auto* output = event.mutable_output();
        if (audio_data && audio_size > 0) {
            output->set_audio_data(audio_data, audio_size);
        }
        const auto audio_format_proto = [c]() {
            switch (c->audio_format) {
                case RAC_AUDIO_FORMAT_WAV:
                    return runanywhere::v1::AUDIO_FORMAT_WAV;
                case RAC_AUDIO_FORMAT_MP3:
                    return runanywhere::v1::AUDIO_FORMAT_MP3;
                case RAC_AUDIO_FORMAT_OPUS:
                    return runanywhere::v1::AUDIO_FORMAT_OPUS;
                case RAC_AUDIO_FORMAT_AAC:
                    return runanywhere::v1::AUDIO_FORMAT_AAC;
                case RAC_AUDIO_FORMAT_FLAC:
                    return runanywhere::v1::AUDIO_FORMAT_FLAC;
                case RAC_AUDIO_FORMAT_PCM:
                default:
                    return runanywhere::v1::AUDIO_FORMAT_PCM;
            }
        }();
        output->set_audio_format(audio_format_proto);
        output->set_sample_rate(c->sample_rate);
        output->set_timestamp_ms(rac_get_current_time_ms());
        output->set_audio_size_bytes(static_cast<int64_t>(audio_size));
        auto* metadata = output->mutable_metadata();
        metadata->set_voice_id(c->voice_id);
        metadata->set_language_code(c->language_code);
        metadata->set_character_count(c->character_count);
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        c->fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), c->user_data);
    };

    rc = ref.ops->synthesize_stream(ref.impl, text.c_str(), &options, chunk_bridge, &ctx);

    if (rc != RAC_SUCCESS) {
        runanywhere::v1::TTSStreamEvent error_event;
        error_event.set_seq(ctx.next_seq++);
        error_event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        error_event.set_request_id(ctx.request_id);
        error_event.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_ERROR);
        error_event.set_error_code(rc);
        error_event.set_error_message(rac_error_message(rc));
        emit_event(error_event, ctx.fn, ctx.user_data);
    } else {
        runanywhere::v1::TTSStreamEvent completed;
        completed.set_seq(ctx.next_seq++);
        completed.set_timestamp_us(rac_get_current_time_ms() * 1000);
        completed.set_request_id(ctx.request_id);
        completed.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_COMPLETED);
        emit_event(completed, ctx.fn, ctx.user_data);
    }

    free_tts_options(&options);
    rac::lifecycle::release_lifecycle_tts(&ref);
    rac_proto_buffer_free(&error_buf);
    return rc;
#endif
}

rac_result_t rac_tts_stop_lifecycle_proto(rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_result);
#else
    rac::lifecycle::LifecycleTtsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "TTS lifecycle voice/model is not loaded");
    }

    rac_result_t stop_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->stop) {
        stop_rc = ref.ops->stop(ref.impl);
    }

    runanywhere::v1::TTSServiceState state;
    state.set_is_ready(stop_rc == RAC_SUCCESS);
    if (ref.model_id) {
        state.set_current_voice(ref.model_id);
    }
    if (stop_rc != RAC_SUCCESS) {
        state.set_error_code(stop_rc);
        state.set_error_message(rac_error_message(stop_rc));
    }
    rc = copy_proto(state, out_result);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc == RAC_SUCCESS ? stop_rc : rc;
#endif
}

rac_result_t rac_tts_list_voices_lifecycle_proto(rac_proto_buffer_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out);
#else
    rac::lifecycle::LifecycleTtsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out, rc, "TTS lifecycle voice/model is not loaded");
    }

    runanywhere::v1::TTSVoiceList list;
    if (ref.ops && ref.ops->get_info) {
        rac_tts_info_t info = {};
        rac_result_t info_rc = ref.ops->get_info(ref.impl, &info);
        if (info_rc == RAC_SUCCESS) {
            for (size_t i = 0; i < info.num_voices; ++i) {
                const char* id = info.available_voices ? info.available_voices[i] : nullptr;
                if (!id)
                    continue;
                runanywhere::v1::TTSVoiceInfo* voice = list.add_voices();
                voice->set_id(id);
                voice->set_display_name(id);
            }
        }
    }

    if (list.voices_size() == 0 && ref.model_id) {
        runanywhere::v1::TTSVoiceInfo* voice = list.add_voices();
        voice->set_id(ref.model_id);
        voice->set_display_name(ref.model_id);
    }

    rc = copy_proto(list, out);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc;
#endif
}

}  // extern "C"
