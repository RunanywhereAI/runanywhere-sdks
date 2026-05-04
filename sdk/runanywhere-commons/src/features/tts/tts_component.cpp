/**
 * @file tts_component.cpp
 * @brief TTS Capability Component Implementation
 *
 * C++ port of Swift's TTSCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/TTS/TTSCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
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

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "tts_options.pb.h"
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
    for (size_t i = 0; i < uuid.size(); i++) {
        if (uuid[i] == 'x') {
            uuid[i] = hex[dis(gen)];
        } else if (uuid[i] == 'y') {
            uuid[i] = hex[(dis(gen) % 4) + 8];
        }
    }
    return uuid;
}

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool proto_bytes_valid(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* proto_parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto_message(const google::protobuf::MessageLite& message,
                                rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize TTS proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
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
                                 static_cast<double>(sizeof(float)) /
                                 static_cast<double>(rate)) *
                                1000.0);
}

void fill_tts_output(const rac_tts_result_t& result,
                     const char* text,
                     const char* voice_id,
                     const rac_tts_options_t& options,
                     runanywhere::v1::TTSOutput* out) {
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

void publish_tts_voice_event(runanywhere::v1::VoiceEventKind kind,
                             int64_t duration_ms,
                             rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::SDKEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_id(generate_uuid_v4());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_TTS);
    event.set_component(runanywhere::v1::SDK_COMPONENT_TTS);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_severity(error_code == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                                                 : runanywhere::v1::EVENT_SEVERITY_ERROR);
    auto* voice = event.mutable_voice();
    voice->set_kind(kind);
    voice->set_duration_ms(duration_ms);
    if (error_code != RAC_SUCCESS) {
        voice->set_error(rac_error_message(error_code));
    }

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 ||
        event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

static rac_result_t tts_create_service(const char* voice_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    log_info("TTS.Component", "Creating TTS service");

    rac_result_t result = rac_tts_create(voice_id, out_service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Failed to create TTS service");
        return result;
    }

    result = rac_tts_initialize(*out_service);
    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Failed to initialize TTS service");
        rac_tts_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    log_info("TTS.Component", "TTS service created successfully");
    return RAC_SUCCESS;
}

static void tts_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        log_info("TTS.Component", "Destroying TTS service");
        rac_tts_cleanup(service);
        rac_tts_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_tts_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_tts_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_TTS_VOICE;
    lifecycle_config.logger_category = "TTS.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, tts_create_service,
                                               tts_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    log_info("TTS.Component", "TTS component created");

    return RAC_SUCCESS;
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

    log_info("TTS.Component", "TTS component configured");

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

    log_info("TTS.Component", "TTS component destroyed");

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

    // Emit voice load started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_STARTED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_STARTED, &event);
    }

    auto load_start = std::chrono::steady_clock::now();

    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, voice_path, voice_id, voice_name, &service);

    double load_duration_ms =
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - load_start)
                                .count());

    if (result != RAC_SUCCESS) {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_FAILED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = result;
        event.data.llm_model.error_message = "Voice load failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_FAILED, &event);
    } else {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_TTS_VOICE_LOAD_COMPLETED;
        event.data.llm_model.model_id = voice_id;
        event.data.llm_model.model_name = voice_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_TTS_VOICE_LOAD_COMPLETED, &event);
    }

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

    log_info("TTS.Component", "Synthesis stop requested");

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
            log_error("TTS.Component", "No voice loaded - cannot synthesize");
            // Emit SYNTHESIS_FAILED event
            rac_analytics_event_data_t event_data;
            event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
            event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
            event_data.data.tts_synthesis.model_id = voice_id;
            event_data.data.tts_synthesis.model_name = voice_name;
            event_data.data.tts_synthesis.framework = framework;
            event_data.data.tts_synthesis.error_code = result;
            event_data.data.tts_synthesis.error_message = "No voice loaded";
            rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
            return result;
        }
    }
    // Lock released — safe to do long-running synthesis

    // Emit SYNTHESIS_STARTED event
    {
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = static_cast<int32_t>(std::strlen(text));
        event_data.data.tts_synthesis.framework = framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_STARTED, &event_data);
    }

    log_info("TTS.Component", "Synthesizing text");

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result = rac_tts_synthesize(service, text, &local_options, out_result);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesize");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.processing_duration_ms =
            static_cast<double>(duration.count());
        event_data.data.tts_synthesis.framework = framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "Synthesis failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
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

        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.audio_duration_ms =
            static_cast<double>(out_result->duration_ms);
        event_data.data.tts_synthesis.audio_size_bytes =
            static_cast<int32_t>(out_result->audio_size);
        event_data.data.tts_synthesis.processing_duration_ms = processing_ms;
        event_data.data.tts_synthesis.characters_per_second = chars_per_sec;
        event_data.data.tts_synthesis.sample_rate = static_cast<int32_t>(out_result->sample_rate);
        event_data.data.tts_synthesis.framework = framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_COMPLETED, &event_data);
    }

    log_info("TTS.Component", "Synthesis completed");

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
            log_error("TTS.Component", "No voice loaded - cannot synthesize stream");
            // Emit SYNTHESIS_FAILED event
            rac_analytics_event_data_t event_data;
            event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
            event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
            event_data.data.tts_synthesis.model_id = voice_id;
            event_data.data.tts_synthesis.model_name = voice_name;
            event_data.data.tts_synthesis.framework = framework;
            event_data.data.tts_synthesis.error_code = result;
            event_data.data.tts_synthesis.error_message = "No voice loaded";
            rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
            return result;
        }
    }
    // Lock released — safe to do long-running synthesis

    // Emit SYNTHESIS_STARTED event
    {
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.framework = framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_STARTED, &event_data);
    }

    log_info("TTS.Component", "Starting streaming synthesis");

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result =
        rac_tts_synthesize_stream(service, text, &local_options, callback, user_data);

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    if (result != RAC_SUCCESS) {
        log_error("TTS.Component", "Streaming synthesis failed");
        rac_lifecycle_track_error(component->lifecycle, result, "synthesizeStream");
        // Emit SYNTHESIS_FAILED event
        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.processing_duration_ms =
            static_cast<double>(duration.count());
        event_data.data.tts_synthesis.framework = framework;
        event_data.data.tts_synthesis.error_code = result;
        event_data.data.tts_synthesis.error_message = "Streaming synthesis failed";
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event_data);
    } else {
        // Emit SYNTHESIS_COMPLETED event (streaming complete)
        double processing_ms = static_cast<double>(duration.count());
        double chars_per_sec = processing_ms > 0 ? (char_count * 1000.0 / processing_ms) : 0.0;

        rac_analytics_event_data_t event_data;
        event_data.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
        event_data.data.tts_synthesis.synthesis_id = synthesis_id.c_str();
        event_data.data.tts_synthesis.model_id = voice_id;
        event_data.data.tts_synthesis.model_name = voice_name;
        event_data.data.tts_synthesis.character_count = char_count;
        event_data.data.tts_synthesis.processing_duration_ms = processing_ms;
        event_data.data.tts_synthesis.characters_per_second = chars_per_sec;
        event_data.data.tts_synthesis.framework = framework;
        rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_COMPLETED, &event_data);
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
        log_error("TTS.Component", "No voice loaded - cannot enumerate languages");
        return result;
    }

    return rac_tts_get_languages(service, out_json);
}

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

extern "C" rac_result_t rac_tts_component_list_voices_proto(
    rac_handle_t handle,
    rac_tts_proto_voice_callback_fn callback,
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
            (void)rac_sdk_event_publish_failure(rc, "TTS voice is not loaded", "tts",
                                                "listVoices", RAC_TRUE);
            return rc;
        }
    }

    rac_tts_info_t info = {};
    rac_result_t rc = rac_tts_get_info(service, &info);
    if (rc != RAC_SUCCESS) {
        (void)rac_sdk_event_publish_failure(rc, "TTS voice listing failed", "tts",
                                            "listVoices", RAC_TRUE);
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
        if (size > 0 &&
            !voice.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
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
        if (size > 0 &&
            !voice.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            return RAC_ERROR_ENCODING_ERROR;
        }
        callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_data);
    }

    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_tts_component_synthesize_proto(
    rac_handle_t handle,
    const char* text,
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
    rac_handle_t handle,
    const char* text,
    const uint8_t* options_proto_bytes,
    size_t options_proto_size,
    rac_tts_proto_chunk_callback_fn callback,
    void* user_data) {
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
    } context{callback, user_data, text, voice_id, options};

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
        metadata->set_character_count(ctx->text ? static_cast<int32_t>(std::strlen(ctx->text))
                                                : 0);
        metadata->set_audio_duration_ms(output.duration_ms());
        const size_t size = output.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size == 0 ||
            output.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
        }
    };

    publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED, 0);
    rac_result_t rc =
        rac_tts_component_synthesize_stream(handle, text, &options, bridge, &context);
    if (rc != RAC_SUCCESS) {
        publish_tts_voice_event(runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED, 0, rc);
        (void)rac_sdk_event_publish_failure(rc, "TTS streaming synthesis failed", "tts",
                                            "synthesizeStream", RAC_TRUE);
    }
    return rc;
#endif
}
