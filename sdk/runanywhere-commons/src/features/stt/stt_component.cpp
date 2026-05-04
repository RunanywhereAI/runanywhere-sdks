/**
 * @file stt_component.cpp
 * @brief STT Capability Component Implementation
 *
 * C++ port of Swift's STTCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/STT/STTCapability.swift
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
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
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
    return std::string(buffer);
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
                                          "failed to serialize STT proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
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
    if (std::strncmp(language, "en", 2) == 0) return runanywhere::v1::STT_LANGUAGE_EN;
    if (std::strncmp(language, "es", 2) == 0) return runanywhere::v1::STT_LANGUAGE_ES;
    if (std::strncmp(language, "fr", 2) == 0) return runanywhere::v1::STT_LANGUAGE_FR;
    if (std::strncmp(language, "de", 2) == 0) return runanywhere::v1::STT_LANGUAGE_DE;
    if (std::strncmp(language, "zh", 2) == 0) return runanywhere::v1::STT_LANGUAGE_ZH;
    if (std::strncmp(language, "ja", 2) == 0) return runanywhere::v1::STT_LANGUAGE_JA;
    if (std::strncmp(language, "ko", 2) == 0) return runanywhere::v1::STT_LANGUAGE_KO;
    if (std::strncmp(language, "it", 2) == 0) return runanywhere::v1::STT_LANGUAGE_IT;
    if (std::strncmp(language, "pt", 2) == 0) return runanywhere::v1::STT_LANGUAGE_PT;
    if (std::strncmp(language, "ar", 2) == 0) return runanywhere::v1::STT_LANGUAGE_AR;
    if (std::strncmp(language, "ru", 2) == 0) return runanywhere::v1::STT_LANGUAGE_RU;
    if (std::strncmp(language, "hi", 2) == 0) return runanywhere::v1::STT_LANGUAGE_HI;
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
    return static_cast<int64_t>((static_cast<double>(audio_size) /
                                 static_cast<double>(RAC_STT_BYTES_PER_SAMPLE) /
                                 static_cast<double>(rate)) *
                                1000.0);
}

void fill_stt_output(const rac_stt_result_t& result,
                     const rac_stt_options_t& options,
                     size_t audio_size,
                     const char* model_id,
                     runanywhere::v1::STTOutput* out) {
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
        metadata->set_real_time_factor(
            static_cast<float>(static_cast<double>(result.processing_time_ms) /
                               static_cast<double>(audio_length_ms)));
    }
}

void publish_stt_voice_event(runanywhere::v1::VoiceEventKind kind,
                             const char* text,
                             float confidence,
                             rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::SDKEvent event;
    event.set_timestamp_ms(rac_get_current_time_ms());
    event.set_id(generate_unique_id());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_STT);
    event.set_component(runanywhere::v1::SDK_COMPONENT_STT);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_severity(error_code == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                                                 : runanywhere::v1::EVENT_SEVERITY_ERROR);
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

static rac_result_t stt_create_service(const char* model_id, void* user_data,
                                       rac_handle_t* out_service) {
    (void)user_data;

    log_info("STT.Component", "Creating STT service");

    // Create STT service
    rac_result_t result = rac_stt_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Failed to create STT service");
        return result;
    }

    // Initialize with model path
    result = rac_stt_initialize(*out_service, model_id);
    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Failed to initialize STT service");
        rac_stt_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    log_info("STT.Component", "STT service created successfully");
    return RAC_SUCCESS;
}

static void stt_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        log_info("STT.Component", "Destroying STT service");
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

    log_info("STT.Component", "STT component created");

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

    log_info("STT.Component", "STT component configured");

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

    log_info("STT.Component", "STT component destroyed");

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

    // Emit model load started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_MODEL_LOAD_STARTED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_MODEL_LOAD_STARTED, &event);
    }

    auto load_start = std::chrono::steady_clock::now();

    rac_handle_t service = nullptr;
    rac_result_t result =
        rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);

    double load_duration_ms =
        static_cast<double>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - load_start)
                                .count());

    if (result != RAC_SUCCESS) {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_MODEL_LOAD_FAILED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = result;
        event.data.llm_model.error_message = "Model load failed";
        rac_analytics_event_emit(RAC_EVENT_STT_MODEL_LOAD_FAILED, &event);
    } else {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_MODEL_LOAD_COMPLETED;
        event.data.llm_model.model_id = model_id;
        event.data.llm_model.model_name = model_name;
        event.data.llm_model.framework = component->actual_framework;
        event.data.llm_model.duration_ms = load_duration_ms;
        event.data.llm_model.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_MODEL_LOAD_COMPLETED, &event);
    }

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
            log_error("STT.Component", "No model loaded - cannot transcribe");

            // Emit transcription failed event
            rac_analytics_event_data_t event = {};
            event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
            event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
            event.data.stt_transcription.transcription_id = transcription_id.c_str();
            event.data.stt_transcription.model_id = model_id;
            event.data.stt_transcription.model_name = model_name;
            event.data.stt_transcription.error_code = result;
            event.data.stt_transcription.error_message = "No model loaded";
            rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);

            return result;
        }
    }
    // Lock released — safe to do long-running transcription

    // Estimate audio length (assuming 16kHz mono 16-bit audio)
    double audio_length_ms = (audio_size / 2.0 / 16000.0) * 1000.0;

    log_info("STT.Component", "Transcribing audio");

    // Emit transcription started event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_STARTED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = local_options.language;
        event.data.stt_transcription.is_streaming = RAC_FALSE;
        event.data.stt_transcription.sample_rate = sample_rate;
        event.data.stt_transcription.framework = framework;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_STARTED, &event);
    }

    auto start_time = std::chrono::steady_clock::now();

    rac_result_t result =
        rac_stt_transcribe(service, audio_data, audio_size, &local_options, out_result);

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribe");

        // Emit transcription failed event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.error_code = result;
        event.data.stt_transcription.error_message = "Transcription failed";
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);

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

    log_info("STT.Component", "Transcription completed");

    // Emit transcription completed event
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_COMPLETED;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.text = out_result->text;
        event.data.stt_transcription.confidence = out_result->confidence;
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.word_count = word_count;
        event.data.stt_transcription.real_time_factor = real_time_factor;
        event.data.stt_transcription.language = local_options.language;
        event.data.stt_transcription.sample_rate = sample_rate;
        event.data.stt_transcription.framework = framework;
        event.data.stt_transcription.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_COMPLETED, &event);
    }

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
        log_error("STT.Component", "No model loaded - cannot transcribe stream");
        return result;
    }

    // Check if streaming is supported
    rac_stt_info_t info;
    result = rac_stt_get_info(service, &info);
    if (result != RAC_SUCCESS || (info.supports_streaming == 0)) {
        log_error("STT.Component", "Streaming not supported");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    log_info("STT.Component", "Starting streaming transcription");

    const rac_stt_options_t* effective_options = options ? options : &component->default_options;

    // Get model info for telemetry - use lifecycle methods for consistency with non-streaming path
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    const char* model_name = rac_lifecycle_get_model_name(component->lifecycle);

    // Debug: Log if model_id is null
    if (!model_id) {
        log_warning(
            "STT.Component",
            "rac_lifecycle_get_model_id returned null - model_id may not be set in telemetry");
    } else {
        log_debug("STT.Component", "STT streaming transcription using model_id: %s", model_id);
    }

    // Calculate audio length in ms (assume 16kHz, 16-bit mono)
    double audio_length_ms = (audio_size * 1000.0) / (component->config.sample_rate * 2);

    // Generate transcription ID for tracking
    std::string transcription_id = generate_unique_id();

    // Emit STT_TRANSCRIPTION_STARTED event with is_streaming = RAC_TRUE
    {
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_STARTED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.is_streaming = RAC_TRUE;  // Streaming mode!
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework = component->actual_framework;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_STARTED, &event);
    }

    auto start_time = std::chrono::steady_clock::now();

    result = rac_stt_transcribe_stream(service, audio_data, audio_size, effective_options, callback,
                                       user_data);

    auto end_time = std::chrono::steady_clock::now();
    double duration_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    if (result != RAC_SUCCESS) {
        log_error("STT.Component", "Streaming transcription failed");
        rac_lifecycle_track_error(component->lifecycle, result, "transcribeStream");

        // Emit STT_TRANSCRIPTION_FAILED event
        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.is_streaming = RAC_TRUE;
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.error_code = result;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);
    } else {
        // Emit STT_TRANSCRIPTION_COMPLETED event with is_streaming = RAC_TRUE
        // Note: For streaming, we don't have final consolidated text, so word_count is not
        // available. We can still compute real_time_factor from audio_length_ms and duration_ms.
        double real_time_factor =
            (audio_length_ms > 0 && duration_ms > 0) ? (audio_length_ms / duration_ms) : 0.0;

        rac_analytics_event_data_t event = {};
        event.type = RAC_EVENT_STT_TRANSCRIPTION_COMPLETED;
        event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
        event.data.stt_transcription.transcription_id = transcription_id.c_str();
        event.data.stt_transcription.model_id = model_id;
        event.data.stt_transcription.model_name = model_name;
        event.data.stt_transcription.audio_length_ms = audio_length_ms;
        event.data.stt_transcription.audio_size_bytes = static_cast<int32_t>(audio_size);
        event.data.stt_transcription.language = effective_options->language;
        event.data.stt_transcription.is_streaming = RAC_TRUE;  // Streaming mode!
        event.data.stt_transcription.duration_ms = duration_ms;
        event.data.stt_transcription.real_time_factor = real_time_factor;
        // word_count not available for streaming - text is delivered via callbacks
        event.data.stt_transcription.sample_rate = component->config.sample_rate;
        event.data.stt_transcription.framework = component->actual_framework;
        event.data.stt_transcription.error_code = RAC_SUCCESS;
        rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_COMPLETED, &event);
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
        log_error("STT.Component", "No model loaded - cannot enumerate languages");
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
            log_error("STT.Component", "No model loaded - cannot detect language");
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

extern "C" rac_result_t rac_stt_component_transcribe_proto(
    rac_handle_t handle,
    const void* audio_data,
    size_t audio_size,
    const uint8_t* options_proto_bytes,
    size_t options_proto_size,
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
    rac_handle_t handle,
    const void* audio_data,
    size_t audio_size,
    const uint8_t* options_proto_bytes,
    size_t options_proto_size,
    rac_stt_proto_partial_callback_fn callback,
    void* user_data) {
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
    if (!rac_stt_component_get_model_id(handle)) {
        const rac_result_t rc = RAC_ERROR_NOT_INITIALIZED;
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT model is not loaded", "stt",
                                            "transcribeStream", RAC_TRUE);
        return rc;
    }

    struct StreamContext {
        rac_stt_proto_partial_callback_fn callback;
        void* user_data;
    } context{callback, user_data};

    auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
        auto* ctx = static_cast<StreamContext*>(opaque);
        runanywhere::v1::STTPartialResult partial;
        if (partial_text) {
            partial.set_text(partial_text);
        }
        partial.set_is_final(is_final == RAC_TRUE);
        partial.set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
        const size_t size = partial.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size == 0 ||
            partial.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
            ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
        }
    };

    rac_stt_options_t options = options_from_proto(proto_options, RAC_STT_OPTIONS_DEFAULT);
    publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_PROCESSING, nullptr, 0.0f);
    rac_result_t rc = rac_stt_component_transcribe_stream(handle, audio_data, audio_size, &options,
                                                          bridge, &context);
    if (rc != RAC_SUCCESS) {
        publish_stt_voice_event(runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED, nullptr, 0.0f, rc);
        (void)rac_sdk_event_publish_failure(rc, "STT streaming transcription failed", "stt",
                                            "transcribeStream", RAC_TRUE);
    }
    return rc;
#endif
}
