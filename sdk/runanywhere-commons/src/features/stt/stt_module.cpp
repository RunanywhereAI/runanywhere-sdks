/**
 * @file stt_module.cpp
 * @brief Unified STT feature module.
 *
 * W4 component unification: merges the former stt_component.cpp (handle-based
 * component path + the *_component_*_proto verbs) with STT's slice of
 * rac_nonllm_lifecycle_proto_abi.cpp (the handle-less
 * rac_stt_transcribe_lifecycle_proto / _stream verbs) into one TU.
 *
 * The component section is a direct translation of Swift's STTCapability.swift;
 * do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <new>
#include <random>
#include <string>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_proto_adapters.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_stream.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#include "sdk_events.pb.h"
#include "stt_options.pb.h"
#endif

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

/**
 * Internal STT component state.
 * Mirrors Swift's STTCapability actor state.
 */
struct rac_stt_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_stt_config_t config;

    /** Default transcription options based on config */
    rac_stt_options_t default_options;

    /** Mutex for thread safety */
    std::mutex mtx;

    /** Resolved inference framework (determined by service registry at load time) */
    rac_inference_framework_t actual_framework;

    rac_stt_component() : lifecycle(nullptr), actual_framework(RAC_FRAMEWORK_UNKNOWN) {
        // Initialize with defaults - matches rac_stt_types.h rac_stt_config_t
        config = RAC_STT_CONFIG_DEFAULT;

        default_options = RAC_STT_OPTIONS_DEFAULT;
    }
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Generate a unique ID for transcription tracking.
 */
static std::string generate_unique_id() {
    static thread_local std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<uint32_t> dis;
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "trans_%08x%08x", dis(gen), dis(gen));
    return {buffer};
}

/**
 * Count words in text.
 */
static int32_t count_words(const char* text) {
    if (!text)
        return 0;
    int32_t count = 0;
    bool in_word = false;
    while (*text != '\0') {
        if (*text == ' ' || *text == '\t' || *text == '\n') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count++;
        }
        text++;
    }
    return count;
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
    return rac::proto::copy_message(message, out, "failed to serialize STT proto result");
}

const char* language_code(runanywhere::v1::STTLanguage language) {
    switch (language) {
        case runanywhere::v1::STT_LANGUAGE_EN:
            return "en";
        case runanywhere::v1::STT_LANGUAGE_ES:
            return "es";
        case runanywhere::v1::STT_LANGUAGE_FR:
            return "fr";
        case runanywhere::v1::STT_LANGUAGE_DE:
            return "de";
        case runanywhere::v1::STT_LANGUAGE_ZH:
            return "zh";
        case runanywhere::v1::STT_LANGUAGE_JA:
            return "ja";
        case runanywhere::v1::STT_LANGUAGE_KO:
            return "ko";
        case runanywhere::v1::STT_LANGUAGE_IT:
            return "it";
        case runanywhere::v1::STT_LANGUAGE_PT:
            return "pt";
        case runanywhere::v1::STT_LANGUAGE_AR:
            return "ar";
        case runanywhere::v1::STT_LANGUAGE_RU:
            return "ru";
        case runanywhere::v1::STT_LANGUAGE_HI:
            return "hi";
        default:
            return nullptr;
    }
}

runanywhere::v1::STTLanguage language_from_code(const char* language) {
    if (!language || language[0] == '\0') {
        return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    }
    if (std::strncmp(language, "en", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_EN;
    if (std::strncmp(language, "es", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_ES;
    if (std::strncmp(language, "fr", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_FR;
    if (std::strncmp(language, "de", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_DE;
    if (std::strncmp(language, "zh", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_ZH;
    if (std::strncmp(language, "ja", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_JA;
    if (std::strncmp(language, "ko", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_KO;
    if (std::strncmp(language, "it", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_IT;
    if (std::strncmp(language, "pt", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_PT;
    if (std::strncmp(language, "ar", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_AR;
    if (std::strncmp(language, "ru", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_RU;
    if (std::strncmp(language, "hi", 2) == 0)
        return runanywhere::v1::STT_LANGUAGE_HI;
    return runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
}

rac_stt_options_t options_from_proto(const runanywhere::v1::STTOptions& proto,
                                     const rac_stt_options_t& defaults) {
    rac_stt_options_t options = defaults;
    if (proto.language() == runanywhere::v1::STT_LANGUAGE_AUTO) {
        options.detect_language = RAC_TRUE;
        options.language = nullptr;
    } else if (const char* language = language_code(proto.language())) {
        options.language = language;
        options.detect_language = RAC_FALSE;
    }
    options.enable_punctuation = proto.enable_punctuation() ? RAC_TRUE : RAC_FALSE;
    options.enable_diarization = proto.enable_diarization() ? RAC_TRUE : RAC_FALSE;
    options.max_speakers = proto.max_speakers();
    options.enable_timestamps = proto.enable_word_timestamps() ? RAC_TRUE : RAC_FALSE;
    return options;
}

int64_t estimate_audio_length_ms(size_t audio_size, int32_t sample_rate) {
    const int32_t rate = sample_rate > 0 ? sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;
    return static_cast<int64_t>(
        (static_cast<double>(audio_size) / static_cast<double>(RAC_STT_BYTES_PER_SAMPLE) /
         static_cast<double>(rate)) *
        1000.0);
}

void fill_stt_output(const rac_stt_result_t& result, const rac_stt_options_t& options,
                     size_t audio_size, const char* model_id, runanywhere::v1::STTOutput* out) {
    if (result.text) {
        out->set_text(result.text);
    }
    out->set_language(result.detected_language ? language_from_code(result.detected_language)
                                               : language_from_code(options.language));
    out->set_confidence(result.confidence);
    for (size_t i = 0; i < result.num_words; ++i) {
        auto* word = out->add_words();
        if (result.words[i].text) {
            word->set_word(result.words[i].text);
        }
        word->set_start_ms(result.words[i].start_ms);
        word->set_end_ms(result.words[i].end_ms);
        word->set_confidence(result.words[i].confidence);
    }

    auto* metadata = out->mutable_metadata();
    if (model_id) {
        metadata->set_model_id(model_id);
    }
    metadata->set_processing_time_ms(result.processing_time_ms);
    const int64_t audio_length_ms = estimate_audio_length_ms(audio_size, options.sample_rate);
    metadata->set_audio_length_ms(audio_length_ms);
    if (audio_length_ms > 0 && result.processing_time_ms > 0) {
        metadata->set_real_time_factor(static_cast<float>(
            static_cast<double>(result.processing_time_ms) / static_cast<double>(audio_length_ms)));
    }
}

int64_t current_time_us() {
    return rac_get_current_time_ms() * 1000;
}

bool validate_stt_stream_event(const runanywhere::v1::STTStreamEvent& event) {
    if (event.seq() == 0 || event.timestamp_us() <= 0 || event.request_id().empty()) {
        return false;
    }

    switch (event.kind()) {
        case runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED:
        case runanywhere::v1::STT_STREAM_EVENT_KIND_ENDPOINT:
            return true;
        case runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL:
            return event.has_partial() && !event.partial().is_final();
        case runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL:
            return (event.has_partial() && event.partial().is_final()) || event.has_final_output();
        case runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR:
            return event.error_code() != RAC_SUCCESS || event.has_error_message();
        default:
            return false;
    }
}

void emit_stt_stream_event(const runanywhere::v1::STTStreamEvent& event,
                           rac_stt_proto_stream_event_callback_fn callback, void* user_data) {
    if (!callback || !validate_stt_stream_event(event)) {
        return;
    }

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 || event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_data);
    }
}

void publish_stt_voice_event(runanywhere::v1::VoiceEventKind kind, const char* text,
                             float confidence, rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::SDKEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_id(generate_unique_id());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_STT);
    event.set_component(runanywhere::v1::SDK_COMPONENT_STT);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    event.set_operation_id("stt.transcribe");
    event.set_severity(error_code == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                 : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* voice = event.mutable_voice();
    voice->set_kind(kind);
    if (text) {
        voice->set_text(text);
    }
    voice->set_confidence(confidence);
    if (error_code != RAC_SUCCESS) {
        voice->set_error(rac_error_message(error_code));
    }

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size == 0 || event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

static rac_result_t stt_create_service(const char* model_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    RAC_LOG_INFO("STT.Component", "Creating STT service");

    // Create STT service
    rac_result_t result = rac_stt_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "Failed to create STT service");
        return result;
    }

    // Initialize with model path
    result = rac_stt_initialize(*out_service, model_id);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "Failed to initialize STT service");
        rac_stt_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO("STT.Component", "STT service created successfully");
    return RAC_SUCCESS;
}

static void stt_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_INFO("STT.Component", "Destroying STT service");
        rac_stt_cleanup(service);
        rac_stt_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_stt_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_stt_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_STT_MODEL;
    lifecycle_config.logger_category = "STT.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, stt_create_service,
                                               stt_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    RAC_LOG_INFO("STT.Component", "STT component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_stt_component_configure(rac_handle_t handle,
                                                    const rac_stt_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    // Resolve actual framework: if caller explicitly set one (not -1=auto), use it;
    // otherwise keep the default (UNKNOWN – resolved by service registry at load time)
    if (config->preferred_framework >= 0 &&
        config->preferred_framework != static_cast<int32_t>(RAC_FRAMEWORK_UNKNOWN)) {
        component->actual_framework =
            static_cast<rac_inference_framework_t>(config->preferred_framework);
    }

    // Update default options based on config
    if (config->language) {
        component->default_options.language = config->language;
    }
    component->default_options.sample_rate = config->sample_rate;
    component->default_options.enable_punctuation = config->enable_punctuation;
    component->default_options.enable_timestamps = config->enable_timestamps;

    RAC_LOG_INFO("STT.Component", "STT component configured");

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_stt_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_stt_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_stt_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);

    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    // Clear any lingering proto-stream callback
    // registration keyed by this component handle BEFORE freeing the memory.
    // If the allocator later hands the same address back to a fresh component
    // (rac_stt_component_create), the new component would otherwise inherit
    // the previous slot's stale seq counter / callback pointer — corrupting
    // the STT stream wire seq and pointing user_data at freed SDK memory.
    rac_stt_unset_stream_proto_callback(handle);
    // Spin-wait for any in-flight
    // dispatch_stt_stream_event() invocation on another thread before freeing
    // the component. Mirrors rac_vlm_component_destroy / rac_llm_component_destroy.
    rac_stt_proto_quiesce();

    RAC_LOG_INFO("STT.Component", "STT component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_stt_component_load_model(rac_handle_t handle, const char* model_path,
                                                     const char* model_id, const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Clear any prior proto-stream callback
    // registration BEFORE re-creating the internal service for a new model.
    // Without this, the wire-seq counter in g_slots() retains its prior value
    // and corrupts the proto stream on the very first transcribe after a model
    // switch (the load_model path elides destroy → original destroy-time fix
    // never fires for handle reuse).
    rac_stt_unset_stream_proto_callback(handle);
    // Drain any in-flight dispatcher bound to the
    // previous model before swapping in the new service so user_data captured
    // by the previous registration can be safely freed.
    rac_stt_proto_quiesce();

    // Emit model load started event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::ModelEvent m;
        m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_STARTED);
        if (model_id)
            m.set_model_id(model_id);
        if (model_name)
            m.set_model_name(model_name);
        m.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        rac::events::publish(runanywhere::v1::SDK_COMPONENT_STT,
                             runanywhere::v1::EVENT_CATEGORY_MODEL, std::move(m));
    }
#endif

    auto load_start = std::chrono::steady_clock::now();

    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);

    double load_duration_ms =
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - load_start)
                                .count());

#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::ModelEvent m;
        if (model_id)
            m.set_model_id(model_id);
        if (model_name)
            m.set_model_name(model_name);
        m.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        m.set_duration_ms(static_cast<int64_t>(load_duration_ms));
        if (result != RAC_SUCCESS) {
            m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_FAILED);
            m.set_error("Model load failed");
        } else {
            m.set_kind(runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED);
        }
        rac::events::publish(runanywhere::v1::SDK_COMPONENT_STT,
                             runanywhere::v1::EVENT_CATEGORY_MODEL, std::move(m));
    }
#endif

    return result;
}

extern "C" rac_result_t rac_stt_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_stt_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

// =============================================================================
// TRANSCRIPTION API
// =============================================================================

extern "C" rac_result_t rac_stt_component_transcribe(rac_handle_t handle, const void* audio_data,
                                                     size_t audio_size,
                                                     const rac_stt_options_t* options,
                                                     rac_stt_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);

    // Acquire lock only for state reads, release before long-running transcription
    std::string transcription_id = generate_unique_id();
    rac_handle_t service = nullptr;
    rac_stt_options_t local_options;
    rac_inference_framework_t framework;
    int32_t sample_rate = 0;
    const char* model_id = nullptr;
    const char* model_name = nullptr;

    {
        std::lock_guard<std::mutex> lock(component->mtx);

        model_id = rac_lifecycle_get_model_id(component->lifecycle);
        model_name = rac_lifecycle_get_model_name(component->lifecycle);
        framework = component->actual_framework;
        sample_rate = component->config.sample_rate;

        // Copy effective options to local so we can release the lock
        local_options = options ? *options : component->default_options;

        rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("STT.Component", "No model loaded - cannot transcribe");

            // Emit transcription failed event
#if defined(RAC_HAVE_PROTOBUF)
            {
                runanywhere::v1::VoiceLifecycleEvent voice;
                voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED);
                if (model_id)
                    voice.set_model_id(model_id);
                if (model_name)
                    voice.set_model_name(model_name);
                voice.set_error("No model loaded");
                rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                                  runanywhere::v1::EVENT_CATEGORY_STT,
                                                  std::move(voice), transcription_id.c_str());
            }
#endif

            return result;
        }
    }
    // Lock released — safe to do long-running transcription

    // Estimate audio length (assuming 16kHz mono 16-bit audio)
    double audio_length_ms = (audio_size / 2.0 / 16000.0) * 1000.0;

    RAC_LOG_INFO("STT.Component", "Transcribing audio");

    // Emit transcription started event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_TRANSCRIPTION_STARTED);
        if (model_id)
            voice.set_model_id(model_id);
        if (model_name)
            voice.set_model_name(model_name);
        voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_size));
        if (local_options.language)
            voice.set_language(local_options.language);
        voice.set_is_streaming(false);
        voice.set_sample_rate(sample_rate);
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          transcription_id.c_str());
    }
#endif

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result =
        rac_stt_transcribe(service, audio_data, audio_size, &local_options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "Transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribe");

        // Emit transcription failed event
#if defined(RAC_HAVE_PROTOBUF)
        {
            runanywhere::v1::VoiceLifecycleEvent voice;
            voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED);
            if (model_id)
                voice.set_model_id(model_id);
            if (model_name)
                voice.set_model_name(model_name);
            voice.set_error("Transcription failed");
            rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                              runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                              transcription_id.c_str());
        }
#endif

        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    double duration_ms = static_cast<double>(duration.count());

    // Update metrics if not already set
    if (out_result->processing_time_ms == 0) {
        out_result->processing_time_ms = duration.count();
    }

    // Calculate word count and real-time factor
    int32_t word_count = count_words(out_result->text);
    double real_time_factor =
        (audio_length_ms > 0 && duration_ms > 0) ? (audio_length_ms / duration_ms) : 0.0;

    RAC_LOG_INFO("STT.Component", "Transcription completed");

    // Emit transcription completed event
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED);
        if (model_id)
            voice.set_model_id(model_id);
        if (model_name)
            voice.set_model_name(model_name);
        if (out_result->text)
            voice.set_text(out_result->text);
        voice.set_confidence(out_result->confidence);
        voice.set_duration_ms(static_cast<int64_t>(duration_ms));
        voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_size));
        voice.set_word_count(word_count);
        voice.set_real_time_factor(real_time_factor);
        if (local_options.language)
            voice.set_language(local_options.language);
        voice.set_sample_rate(sample_rate);
        voice.set_framework(rac::events::framework_to_proto_int(framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          transcription_id.c_str());
    }
#endif

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_stt_component_supports_streaming(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = rac_lifecycle_get_service(component->lifecycle);
    if (!service) {
        return RAC_FALSE;
    }

    rac_stt_info_t info;
    rac_result_t result = rac_stt_get_info(service, &info);
    if (result != RAC_SUCCESS) {
        return RAC_FALSE;
    }

    return info.supports_streaming;
}

extern "C" rac_result_t
rac_stt_component_transcribe_stream(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                    const rac_stt_options_t* options,
                                    rac_stt_stream_callback_t callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "No model loaded - cannot transcribe stream");
        return result;
    }

    // Check if streaming is supported
    rac_stt_info_t info;
    result = rac_stt_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        RAC_LOG_ERROR("STT.Component", "Streaming not supported");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO("STT.Component", "Starting streaming transcription");

    const rac_stt_options_t* effective_options = options ? options : &component->default_options;

    // Get model info for telemetry - use lifecycle methods for consistency with non-streaming path
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Debug: Log if model_id is null
    if (!model_id) {
        RAC_LOG_WARNING(
            "STT.Component",
            "rac_lifecycle_get_model_id returned null - model_id may not be set in telemetry");
    } else {
        RAC_LOG_DEBUG("STT.Component", "STT streaming transcription using model_id: %s", model_id);
    }

    // Calculate audio length in ms (assume 16kHz, 16-bit mono)
    double audio_length_ms = (audio_size * 1000.0) / (component->config.sample_rate * 2);

    // Generate transcription ID for tracking
    std::string transcription_id = generate_unique_id();

    // Emit STT_TRANSCRIPTION_STARTED event with is_streaming = RAC_TRUE
#if defined(RAC_HAVE_PROTOBUF)
    {
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_TRANSCRIPTION_STARTED);
        if (model_id)
            voice.set_model_id(model_id);
        if (model_name)
            voice.set_model_name(model_name);
        voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_size));
        if (effective_options->language)
            voice.set_language(effective_options->language);
        voice.set_is_streaming(true);  // Streaming mode!
        voice.set_sample_rate(component->config.sample_rate);
        voice.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          transcription_id.c_str());
    }
#endif

    auto start_time = std::chrono::steady_clock::now();

    result = rac_stt_transcribe_stream(service, audio_data, audio_size, effective_options, callback,
                                       user_data);

    auto end_time = std::chrono::steady_clock::now();
    double duration_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "Streaming transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribeStream");

        // Emit STT_TRANSCRIPTION_FAILED event
#if defined(RAC_HAVE_PROTOBUF)
        {
            runanywhere::v1::VoiceLifecycleEvent voice;
            voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED);
            if (model_id)
                voice.set_model_id(model_id);
            if (model_name)
                voice.set_model_name(model_name);
            voice.set_is_streaming(true);
            voice.set_duration_ms(static_cast<int64_t>(duration_ms));
            voice.set_error(rac_error_message(result));
            rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                              runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                              transcription_id.c_str());
        }
#endif
    } else {
        // Emit STT_TRANSCRIPTION_COMPLETED event with is_streaming = RAC_TRUE
        // Note: For streaming, we don't have final consolidated text, so word_count is not
        // available. We can still compute real_time_factor from audio_length_ms and duration_ms.
        double real_time_factor =
            (audio_length_ms > 0 && duration_ms > 0) ? (audio_length_ms / duration_ms) : 0.0;

#if defined(RAC_HAVE_PROTOBUF)
        runanywhere::v1::VoiceLifecycleEvent voice;
        voice.set_kind(runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED);
        if (model_id)
            voice.set_model_id(model_id);
        if (model_name)
            voice.set_model_name(model_name);
        voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
        voice.set_audio_size_bytes(static_cast<int32_t>(audio_size));
        if (effective_options->language)
            voice.set_language(effective_options->language);
        voice.set_is_streaming(true);  // Streaming mode!
        voice.set_duration_ms(static_cast<int64_t>(duration_ms));
        voice.set_real_time_factor(real_time_factor);
        // word_count not available for streaming - text is delivered via callbacks
        voice.set_sample_rate(component->config.sample_rate);
        voice.set_framework(rac::events::framework_to_proto_int(component->actual_framework));
        rac::events::publish_with_session(runanywhere::v1::SDK_COMPONENT_STT,
                                          runanywhere::v1::EVENT_CATEGORY_STT, std::move(voice),
                                          transcription_id.c_str());
#endif
    }

    return result;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_stt_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_stt_component_get_metrics(rac_handle_t handle,
                                                      rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

// =============================================================================
// LANGUAGE INTROSPECTION
// =============================================================================

extern "C" rac_result_t rac_stt_component_get_supported_languages(rac_handle_t handle,
                                                                  char** out_json) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_json)
        return RAC_ERROR_INVALID_ARGUMENT;

    *out_json = nullptr;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("STT.Component", "No model loaded - cannot enumerate languages");
        return result;
    }

    return rac_stt_get_languages(service, out_json);
}

extern "C" rac_result_t rac_stt_component_detect_language(rac_handle_t handle,
                                                          const void* audio_data, size_t audio_size,
                                                          char** out_language) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!audio_data || audio_size == 0 || !out_language)
        return RAC_ERROR_INVALID_ARGUMENT;

    *out_language = nullptr;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);

    rac_handle_t service = nullptr;
    rac_stt_options_t local_options;
    {
        std::lock_guard<std::mutex> lock(component->mtx);

        rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("STT.Component", "No model loaded - cannot detect language");
            return result;
        }

        local_options = component->default_options;
    }

    // Force detection path: ignore any sticky language setting in default options.
    local_options.language = nullptr;
    local_options.detect_language = RAC_TRUE;

    return rac_stt_detect_language(service, audio_data, audio_size, &local_options, out_language);
}

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

extern "C" rac_result_t
rac_stt_component_transcribe_proto(rac_handle_t handle, const void* audio_data, size_t audio_size,
                                   const uint8_t* options_proto_bytes, size_t options_proto_size,
                                   rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)audio_data;
    (void)audio_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!handle || !audio_data || audio_size == 0) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "STT transcribe proto requires handle and audio bytes");
    }
    if (!proto_bytes_valid(options_proto_bytes, options_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "STTOptions bytes are invalid");
    }

    runanywhere::v1::STTOptions proto_options;
    if (!proto_options.ParseFromArray(proto_parse_data(options_proto_bytes, options_proto_size),
                                      static_cast<int>(options_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse STTOptions");
    }

    const char* model_id = rac_stt_component_get_model_id(handle);
    if (!model_id) {
        const rac_result_t rc = RAC_ERROR_NOT_INITIALIZED;
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT model is not loaded", "stt", "transcribe",
                                            RAC_TRUE);
        return rac_proto_buffer_set_error(out_result, rc, "STT model is not loaded");
    }

    rac_stt_options_t options = options_from_proto(proto_options, RAC_STT_OPTIONS_DEFAULT);
    rac_stt_result_t result = {};
    publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_PROCESSING, nullptr, 0.0f);
    rac_result_t rc =
        rac_stt_component_transcribe(handle, audio_data, audio_size, &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT transcription failed", "stt", "transcribe",
                                            RAC_TRUE);
        return rac_proto_buffer_set_error(out_result, rc, "STT transcription failed");
    }

    runanywhere::v1::STTOutput output;
    fill_stt_output(result, options, audio_size, model_id, &output);
    publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED, result.text,
                            result.confidence);
    rac_stt_result_free(&result);
    return copy_proto_message(output, out_result);
#endif
}

extern "C" rac_result_t rac_stt_component_transcribe_stream_proto(
    rac_handle_t handle, const void* audio_data, size_t audio_size,
    const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_stt_proto_stream_event_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)audio_data;
    (void)audio_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !audio_data || audio_size == 0 || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!proto_bytes_valid(options_proto_bytes, options_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::STTOptions proto_options;
    if (!proto_options.ParseFromArray(proto_parse_data(options_proto_bytes, options_proto_size),
                                      static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }

    const std::string request_id = generate_unique_id();
    if (!rac_stt_component_get_model_id(handle)) {
        const rac_result_t rc = RAC_ERROR_NOT_INITIALIZED;
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT model is not loaded", "stt",
                                            "transcribeStream", RAC_TRUE);
        runanywhere::v1::STTStreamEvent error;
        error.set_seq(1);
        error.set_timestamp_us(current_time_us());
        error.set_request_id(request_id);
        error.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR);
        error.set_error_code(rc);
        error.set_error_message("STT model is not loaded");
        emit_stt_stream_event(error, callback, user_data);
        return rc;
    }

    rac_stt_options_t options = options_from_proto(proto_options, RAC_STT_OPTIONS_DEFAULT);

    struct StreamContext {
        rac_stt_proto_stream_event_callback_fn callback;
        void* user_data;
        std::string request_id;
        uint64_t next_seq;
        rac_stt_options_t options;
        size_t audio_size;
    } context{.callback = callback,
              .user_data = user_data,
              .request_id = request_id,
              .next_seq = 1,
              .options = options,
              .audio_size = audio_size};

    runanywhere::v1::STTStreamEvent started;
    started.set_seq(context.next_seq++);
    started.set_timestamp_us(current_time_us());
    started.set_request_id(context.request_id);
    started.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED);
    emit_stt_stream_event(started, callback, user_data);

    auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
        auto* ctx = static_cast<StreamContext*>(opaque);
        runanywhere::v1::STTStreamEvent event;
        event.set_seq(ctx->next_seq++);
        event.set_timestamp_us(current_time_us());
        event.set_request_id(ctx->request_id);
        event.set_kind(is_final == RAC_TRUE ? runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL
                                            : runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL);
        auto* partial = event.mutable_partial();
        if (partial_text) {
            partial->set_text(partial_text);
        }
        partial->set_is_final(is_final == RAC_TRUE);
        partial->set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
        partial->set_request_id(ctx->request_id);
        partial->set_language(language_from_code(ctx->options.language));
        if (is_final == RAC_TRUE) {
            auto* final_output = event.mutable_final_output();
            if (partial_text) {
                final_output->set_text(partial_text);
            }
            final_output->set_language(language_from_code(ctx->options.language));
            final_output->set_duration_ms(
                estimate_audio_length_ms(ctx->audio_size, ctx->options.sample_rate));
            final_output->mutable_metadata()->set_audio_length_ms(final_output->duration_ms());
        }
        emit_stt_stream_event(event, ctx->callback, ctx->user_data);
    };

    publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_PROCESSING, nullptr, 0.0f);
    rac_result_t rc = rac_stt_component_transcribe_stream(handle, audio_data, audio_size, &options,
                                                          bridge, &context);
    if (rc != RAC_SUCCESS) {
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT streaming transcription failed", "stt",
                                            "transcribeStream", RAC_TRUE);
        runanywhere::v1::STTStreamEvent error;
        error.set_seq(context.next_seq++);
        error.set_timestamp_us(current_time_us());
        error.set_request_id(context.request_id);
        error.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR);
        error.set_error_code(rc);
        error.set_error_message("STT streaming transcription failed");
        emit_stt_stream_event(error, callback, user_data);
    }
    return rc;
#endif
}

// =============================================================================
// Persistent per-session streaming handles.
//
// Route straight through the service vtable. When a backend leaves the
// stream_* slots NULL, these helpers report RAC_ERROR_NOT_SUPPORTED and
// rac_stt_stream.cpp falls back to the per-chunk transcribe_stream path.
// =============================================================================

namespace {

// Wraps a backend-owned stream handle together with the lifecycle service
// instance that produced it. We pin (acquire) the lifecycle service on
// stream_create so subsequent feed/destroy calls always route through the
// same service even if a concurrent rac_lifecycle_unload would otherwise
// destroy the backend. The pinned ref is released by stream_destroy.
//
// This honors the contract in include/rac/features/stt/rac_stt_stream.h
// that "the lifecycle manager — unloading the model cancels active
// sessions" by ensuring the service cannot be destroyed mid-session.
struct PersistentStreamHandle {
    rac_handle_t lifecycle = nullptr;
    rac_stt_service_t* service = nullptr;
    rac_handle_t backend_handle = nullptr;
};

}  // namespace

extern "C" rac_result_t rac_stt_component_stream_create(rac_handle_t handle,
                                                        const rac_stt_options_t* options,
                                                        rac_handle_t* out_stream_handle) {
    if (!handle || !out_stream_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_stream_handle = nullptr;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Acquire (not require) so the lifecycle service refcount is held for
    // the lifetime of the stream. This is the key fix so that
    // a concurrent unload now waits
    // for stream_destroy before tearing down the backend service.
    rac_handle_t service_handle = nullptr;
    rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service_handle);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    auto* service = static_cast<rac_stt_service_t*>(service_handle);
    if (!service || !service->ops || !service->ops->stream_create) {
        rac_lifecycle_release_service(component->lifecycle);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const rac_stt_options_t* effective = options ? options : &component->default_options;
    rac_handle_t backend_stream = nullptr;
    rc = service->ops->stream_create(service->impl, effective, &backend_stream);
    if (rc != RAC_SUCCESS || backend_stream == nullptr) {
        rac_lifecycle_release_service(component->lifecycle);
        return rc;
    }

    auto* wrapper = new (std::nothrow) PersistentStreamHandle{};
    if (wrapper == nullptr) {
        (void)service->ops->stream_destroy(service->impl, backend_stream);
        rac_lifecycle_release_service(component->lifecycle);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    wrapper->lifecycle = component->lifecycle;
    wrapper->service = service;
    wrapper->backend_handle = backend_stream;
    *out_stream_handle = wrapper;
    return RAC_SUCCESS;
}

extern "C" rac_result_t
rac_stt_component_stream_feed_audio_chunk(rac_handle_t handle, rac_handle_t stream_handle,
                                          const int16_t* samples, size_t count,
                                          rac_stt_stream_callback_t callback, void* user_data) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!stream_handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (count > 0 && !samples)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    auto* wrapper = static_cast<PersistentStreamHandle*>(stream_handle);
    auto* service = wrapper->service;
    if (!service || !service->ops || !service->ops->stream_feed_audio_chunk) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->stream_feed_audio_chunk(service->impl, wrapper->backend_handle, samples,
                                                 count, callback, user_data);
}

extern "C" rac_result_t rac_stt_component_stream_destroy(rac_handle_t handle,
                                                         rac_handle_t stream_handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!stream_handle)
        return RAC_SUCCESS;

    auto* component = reinterpret_cast<rac_stt_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    auto* wrapper = static_cast<PersistentStreamHandle*>(stream_handle);
    auto* service = wrapper->service;
    rac_result_t rc = RAC_SUCCESS;
    if (service && service->ops && service->ops->stream_destroy && wrapper->backend_handle) {
        rc = service->ops->stream_destroy(service->impl, wrapper->backend_handle);
    } else if (!service || !service->ops || !service->ops->stream_destroy) {
        rc = RAC_ERROR_NOT_SUPPORTED;
    }
    // Always release the pinned lifecycle ref so unload can proceed even
    // when the backend reports an error during destroy.
    if (wrapper->lifecycle) {
        rac_lifecycle_release_service(wrapper->lifecycle);
    }
    delete wrapper;
    return rc;
}

// =============================================================================
// LIFECYCLE-OWNED GENERATED-PROTO C ABI (formerly STT slice of
// rac_nonllm_lifecycle_proto_abi.cpp)
//
// Handle-less verbs that resolve the loaded model via the global registry
// (rac::lifecycle::acquire_lifecycle_stt) rather than a component handle.
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

// 3-arg variant carried from the nonllm slice. Coexists as an overload with the
// 2-arg estimate_audio_length_ms in the component section above.
int64_t estimate_audio_length_ms(size_t byte_count, int32_t sample_rate, size_t bytes_per_sample) {
    const int32_t rate = sample_rate > 0 ? sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;
    const size_t width = bytes_per_sample > 0 ? bytes_per_sample : RAC_STT_BYTES_PER_SAMPLE;
    return static_cast<int64_t>(
        (static_cast<double>(byte_count) / static_cast<double>(width) / static_cast<double>(rate)) *
        1000.0);
}

rac_result_t parse_stt_request(const uint8_t* request_proto_bytes, size_t request_proto_size,
                               runanywhere::v1::STTTranscriptionRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "STTTranscriptionRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse STTTranscriptionRequest");
    }
    if (out_request->has_audio() && (!out_request->audio().file_uri().empty() ||
                                     !out_request->audio().adapter_handle().empty())) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_NOT_SUPPORTED,
            "STTTranscriptionRequest audio file_uri/adapter_handle requires a platform adapter");
    }
    if (!out_request->has_audio() || out_request->audio().audio_data().empty()) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "STTTranscriptionRequest.audio.audio_data is required");
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

rac_result_t rac_stt_transcribe_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::STTTranscriptionRequest request;
    rac_result_t rc =
        parse_stt_request(request_proto_bytes, request_proto_size, &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    rac::lifecycle::LifecycleSttRef ref;
    rc = rac::lifecycle::acquire_lifecycle_stt(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "STT lifecycle model is not loaded");
    }

    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_stt_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert STTOptions");
    }
    if (request.has_options() && request.options().has_language_code() &&
        !request.options().language_code().empty()) {
        options.language = request.options().language_code().c_str();
        options.detect_language = RAC_FALSE;
    }
    if (request.audio().sample_rate() > 0) {
        options.sample_rate = request.audio().sample_rate();
    }
    if (request.audio().audio_format() != runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED) {
        options.audio_format = c_audio_format(request.audio().audio_format());
    }

    const std::string& audio = request.audio().audio_data();
    rac_stt_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_stt_result_t raw = {};
    rc = rac_stt_transcribe(&service, audio.data(), audio.size(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::STTOutput output;
    if (!rac::foundation::rac_stt_result_to_proto(&raw, &output)) {
        rac_stt_result_free(&raw);
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode STTOutput");
    }
    output.set_timestamp_ms(rac_get_current_time_ms());
    const size_t sample_width =
        request.audio().encoding() == runanywhere::v1::STT_AUDIO_ENCODING_PCM_F32_LE
            ? sizeof(float)
            : RAC_STT_BYTES_PER_SAMPLE;
    const int64_t duration_ms =
        request.audio().duration_ms() > 0
            ? request.audio().duration_ms()
            : estimate_audio_length_ms(audio.size(), options.sample_rate, sample_width);
    output.set_duration_ms(duration_ms);
    auto* metadata = output.mutable_metadata();
    metadata->set_model_id(ref.model_id ? ref.model_id : "");
    metadata->set_audio_length_ms(duration_ms);
    if (duration_ms > 0 && metadata->processing_time_ms() > 0) {
        metadata->set_real_time_factor(
            static_cast<float>(static_cast<double>(metadata->processing_time_ms()) /
                               static_cast<double>(duration_ms)));
    }

    rc = copy_proto(output, out_result);
    rac_stt_result_free(&raw);
    rac::lifecycle::release_lifecycle_stt(&ref);
    return rc;
#endif
}

rac_result_t rac_stt_transcribe_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_stt_lifecycle_stream_event_callback_fn callback, void* user_data) {
    if (!callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::STTTranscriptionRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.has_audio() &&
        (!request.audio().file_uri().empty() || !request.audio().adapter_handle().empty())) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (!request.has_audio() || request.audio().audio_data().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac::lifecycle::LifecycleSttRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_stt(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!ref.ops || !ref.ops->transcribe_stream) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_stt_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.has_options() && request.options().has_language_code() &&
        !request.options().language_code().empty()) {
        options.language = request.options().language_code().c_str();
        options.detect_language = RAC_FALSE;
    }
    if (request.audio().sample_rate() > 0) {
        options.sample_rate = request.audio().sample_rate();
    }
    if (request.audio().audio_format() != runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED) {
        options.audio_format = c_audio_format(request.audio().audio_format());
    }

    // Bridge context: forwards backend partial/final callbacks into
    // serialized STTStreamEvent envelopes via the caller's proto callback.
    struct StreamCtx {
        rac_stt_lifecycle_stream_event_callback_fn fn;
        void* user_data;
        std::string request_id;
        uint64_t next_seq;
        runanywhere::v1::STTLanguage language;
        size_t audio_size;
        int32_t sample_rate;
        size_t sample_width;
    };

    const std::string request_id =
        request.request_id().empty()
            ? std::string("stt-lifecycle-") + std::to_string(rac_get_current_time_ms())
            : request.request_id();

    const size_t sample_width =
        request.audio().encoding() == runanywhere::v1::STT_AUDIO_ENCODING_PCM_F32_LE
            ? sizeof(float)
            : RAC_STT_BYTES_PER_SAMPLE;

    const int32_t effective_sample_rate =
        options.sample_rate > 0 ? options.sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;

    runanywhere::v1::STTLanguage language_enum = runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    if (request.has_options()) {
        language_enum = request.options().language();
    }

    StreamCtx ctx{.fn = callback,
                  .user_data = user_data,
                  .request_id = request_id,
                  .next_seq = 1,
                  .language = language_enum,
                  .audio_size = request.audio().audio_data().size(),
                  .sample_rate = effective_sample_rate,
                  .sample_width = sample_width};

    auto emit_event = [](const runanywhere::v1::STTStreamEvent& event,
                         rac_stt_lifecycle_stream_event_callback_fn fn, void* user_ctx) {
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_ctx);
    };

    // Emit STARTED envelope before the backend call so SDK consumers can wire
    // their state machine (kind = STARTED, seq = 1).
    {
        runanywhere::v1::STTStreamEvent started;
        started.set_seq(ctx.next_seq++);
        started.set_timestamp_us(rac_get_current_time_ms() * 1000);
        started.set_request_id(ctx.request_id);
        started.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED);
        emit_event(started, ctx.fn, ctx.user_data);
    }

    auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
        auto* c = static_cast<StreamCtx*>(opaque);
        runanywhere::v1::STTStreamEvent event;
        event.set_seq(c->next_seq++);
        event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        event.set_request_id(c->request_id);
        event.set_kind(is_final == RAC_TRUE ? runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL
                                            : runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL);
        auto* partial = event.mutable_partial();
        if (partial_text) {
            partial->set_text(partial_text);
        }
        partial->set_is_final(is_final == RAC_TRUE);
        partial->set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
        partial->set_request_id(c->request_id);
        partial->set_language(c->language);
        if (is_final == RAC_TRUE) {
            auto* final_output = event.mutable_final_output();
            if (partial_text) {
                final_output->set_text(partial_text);
            }
            final_output->set_language(c->language);
            const int64_t audio_length_ms =
                estimate_audio_length_ms(c->audio_size, c->sample_rate, c->sample_width);
            final_output->set_duration_ms(audio_length_ms);
            final_output->mutable_metadata()->set_audio_length_ms(audio_length_ms);
        }
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        c->fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), c->user_data);
    };

    const std::string& audio = request.audio().audio_data();
    rc = ref.ops->transcribe_stream(ref.impl, audio.data(), audio.size(), &options, bridge, &ctx);
    if (rc != RAC_SUCCESS) {
        runanywhere::v1::STTStreamEvent error_event;
        error_event.set_seq(ctx.next_seq++);
        error_event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        error_event.set_request_id(ctx.request_id);
        error_event.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR);
        error_event.set_error_code(rc);
        error_event.set_error_message(rac_error_message(rc));
        emit_event(error_event, ctx.fn, ctx.user_data);
    }
    rac::lifecycle::release_lifecycle_stt(&ref);
    return rc;
#endif
}

}  // extern "C"
