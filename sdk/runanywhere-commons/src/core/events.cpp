/**
 * @file events.cpp
 * @brief RunAnywhere Commons - Cross-Platform Event System Implementation
 *
 * C++ is the canonical source of truth for all analytics events.
 * Platform SDKs register callbacks to receive events.
 */

#include <mutex>

#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_logger.h"

// =============================================================================
// INTERNAL STATE
// =============================================================================

namespace {

// Thread-safe event callback storage
struct EventCallbackState {
    rac_analytics_callback_fn analytics_callback = nullptr;
    void* analytics_user_data = nullptr;
    rac_public_event_callback_fn public_callback = nullptr;
    void* public_user_data = nullptr;
    std::mutex mutex;
};

EventCallbackState& get_callback_state() {
    static EventCallbackState state;
    return state;
}

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" {

rac_event_destination_t rac_event_get_destination(rac_event_type_t type) {
    switch (type) {
        // Public-only events (too chatty for telemetry, needed for UI)
        case RAC_EVENT_LLM_STREAMING_UPDATE:
        case RAC_EVENT_STT_PARTIAL_TRANSCRIPT:
        case RAC_EVENT_TTS_SYNTHESIS_CHUNK:
        case RAC_EVENT_MODEL_DOWNLOAD_PROGRESS:
        case RAC_EVENT_MODEL_EXTRACTION_PROGRESS:
            return RAC_EVENT_DESTINATION_PUBLIC_ONLY;

        // Telemetry-only events (internal metrics, not useful for app devs)
        case RAC_EVENT_VAD_SPEECH_STARTED:
        case RAC_EVENT_VAD_SPEECH_ENDED:
        case RAC_EVENT_VAD_PAUSED:
        case RAC_EVENT_VAD_RESUMED:
        case RAC_EVENT_NETWORK_CONNECTIVITY_CHANGED:
            return RAC_EVENT_DESTINATION_ANALYTICS_ONLY;

        // All other events go to both destinations
        default:
            return RAC_EVENT_DESTINATION_ALL;
    }
}

rac_result_t rac_analytics_events_set_callback(rac_analytics_callback_fn callback,
                                               void* user_data) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    state.analytics_callback = callback;
    state.analytics_user_data = user_data;

    log_info("Events", "rac_analytics_events_set_callback: callback=%p, user_data=%p", 
             (void*)callback, user_data);

    return RAC_SUCCESS;
}

rac_result_t rac_analytics_events_set_public_callback(rac_public_event_callback_fn callback,
                                                      void* user_data) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    state.public_callback = callback;
    state.public_user_data = user_data;

    return RAC_SUCCESS;
}

void rac_analytics_event_emit(rac_event_type_t type, const rac_analytics_event_data_t* data) {
    if (data == nullptr) {
        return;
    }

    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    log_debug("Events", "rac_analytics_event_emit: type=%d, has_callback=%d", 
              type, (state.analytics_callback != nullptr ? 1 : 0));

    // Get the destination for this event type
    rac_event_destination_t dest = rac_event_get_destination(type);

    // Route to analytics callback (telemetry)
    if (dest == RAC_EVENT_DESTINATION_ANALYTICS_ONLY || dest == RAC_EVENT_DESTINATION_ALL) {
        if (state.analytics_callback != nullptr) {
            log_debug("Events", "Invoking analytics callback for event type %d", type);
            state.analytics_callback(type, data, state.analytics_user_data);
        }
    }

    // Route to public callback (app developers)
    if (dest == RAC_EVENT_DESTINATION_PUBLIC_ONLY || dest == RAC_EVENT_DESTINATION_ALL) {
        if (state.public_callback != nullptr) {
            state.public_callback(type, data, state.public_user_data);
        }
    }
}

rac_bool_t rac_analytics_events_has_callback(void) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    return state.analytics_callback != nullptr ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_analytics_events_has_public_callback(void) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    return state.public_callback != nullptr ? RAC_TRUE : RAC_FALSE;
}

}  // extern "C"

// =============================================================================
// HELPER FUNCTIONS FOR C++ COMPONENTS
// =============================================================================

namespace rac::events {

void emit_llm_generation_started(const char* generation_id, const char* model_id, bool is_streaming,
                                 rac_inference_framework_t framework, float temperature,
                                 int32_t max_tokens, int32_t context_length) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_LLM_GENERATION_STARTED;
    event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
    event.data.llm_generation.generation_id = generation_id;
    event.data.llm_generation.model_id = model_id;
    event.data.llm_generation.is_streaming = is_streaming ? RAC_TRUE : RAC_FALSE;
    event.data.llm_generation.framework = framework;
    event.data.llm_generation.temperature = temperature;
    event.data.llm_generation.max_tokens = max_tokens;
    event.data.llm_generation.context_length = context_length;

    rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_STARTED, &event);
}

void emit_llm_generation_completed(const char* generation_id, const char* model_id,
                                   int32_t input_tokens, int32_t output_tokens, double duration_ms,
                                   double tokens_per_second, bool is_streaming,
                                   double time_to_first_token_ms,
                                   rac_inference_framework_t framework, float temperature,
                                   int32_t max_tokens, int32_t context_length) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_LLM_GENERATION_COMPLETED;
    event.data.llm_generation.generation_id = generation_id;
    event.data.llm_generation.model_id = model_id;
    event.data.llm_generation.input_tokens = input_tokens;
    event.data.llm_generation.output_tokens = output_tokens;
    event.data.llm_generation.duration_ms = duration_ms;
    event.data.llm_generation.tokens_per_second = tokens_per_second;
    event.data.llm_generation.is_streaming = is_streaming ? RAC_TRUE : RAC_FALSE;
    event.data.llm_generation.time_to_first_token_ms = time_to_first_token_ms;
    event.data.llm_generation.framework = framework;
    event.data.llm_generation.temperature = temperature;
    event.data.llm_generation.max_tokens = max_tokens;
    event.data.llm_generation.context_length = context_length;
    event.data.llm_generation.error_code = RAC_SUCCESS;
    event.data.llm_generation.error_message = nullptr;

    rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_COMPLETED, &event);
}

void emit_llm_generation_failed(const char* generation_id, const char* model_id,
                                rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_LLM_GENERATION_FAILED;
    event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
    event.data.llm_generation.generation_id = generation_id;
    event.data.llm_generation.model_id = model_id;
    event.data.llm_generation.error_code = error_code;
    event.data.llm_generation.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_LLM_GENERATION_FAILED, &event);
}

void emit_llm_first_token(const char* generation_id, const char* model_id,
                          double time_to_first_token_ms, rac_inference_framework_t framework) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_LLM_FIRST_TOKEN;
    event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
    event.data.llm_generation.generation_id = generation_id;
    event.data.llm_generation.model_id = model_id;
    event.data.llm_generation.time_to_first_token_ms = time_to_first_token_ms;
    event.data.llm_generation.framework = framework;

    rac_analytics_event_emit(RAC_EVENT_LLM_FIRST_TOKEN, &event);
}

void emit_llm_streaming_update(const char* generation_id, int32_t tokens_generated) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_LLM_STREAMING_UPDATE;
    event.data.llm_generation = RAC_ANALYTICS_LLM_GENERATION_DEFAULT;
    event.data.llm_generation.generation_id = generation_id;
    event.data.llm_generation.output_tokens = tokens_generated;

    rac_analytics_event_emit(RAC_EVENT_LLM_STREAMING_UPDATE, &event);
}

void emit_stt_transcription_started(const char* transcription_id, const char* model_id,
                                    double audio_length_ms, int32_t audio_size_bytes,
                                    const char* language, bool is_streaming, int32_t sample_rate,
                                    rac_inference_framework_t framework) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STT_TRANSCRIPTION_STARTED;
    event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
    event.data.stt_transcription.transcription_id = transcription_id;
    event.data.stt_transcription.model_id = model_id;
    event.data.stt_transcription.audio_length_ms = audio_length_ms;
    event.data.stt_transcription.audio_size_bytes = audio_size_bytes;
    event.data.stt_transcription.language = language;
    event.data.stt_transcription.is_streaming = is_streaming ? RAC_TRUE : RAC_FALSE;
    event.data.stt_transcription.sample_rate = sample_rate;
    event.data.stt_transcription.framework = framework;

    rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_STARTED, &event);
}

void emit_stt_transcription_completed(const char* transcription_id, const char* model_id,
                                      const char* text, float confidence, double duration_ms,
                                      double audio_length_ms, int32_t audio_size_bytes,
                                      int32_t word_count, double real_time_factor,
                                      const char* language, int32_t sample_rate,
                                      rac_inference_framework_t framework) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STT_TRANSCRIPTION_COMPLETED;
    event.data.stt_transcription.transcription_id = transcription_id;
    event.data.stt_transcription.model_id = model_id;
    event.data.stt_transcription.text = text;
    event.data.stt_transcription.confidence = confidence;
    event.data.stt_transcription.duration_ms = duration_ms;
    event.data.stt_transcription.audio_length_ms = audio_length_ms;
    event.data.stt_transcription.audio_size_bytes = audio_size_bytes;
    event.data.stt_transcription.word_count = word_count;
    event.data.stt_transcription.real_time_factor = real_time_factor;
    event.data.stt_transcription.language = language;
    event.data.stt_transcription.sample_rate = sample_rate;
    event.data.stt_transcription.framework = framework;
    event.data.stt_transcription.error_code = RAC_SUCCESS;

    rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_COMPLETED, &event);
}

void emit_stt_transcription_failed(const char* transcription_id, const char* model_id,
                                   rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STT_TRANSCRIPTION_FAILED;
    event.data.stt_transcription = RAC_ANALYTICS_STT_TRANSCRIPTION_DEFAULT;
    event.data.stt_transcription.transcription_id = transcription_id;
    event.data.stt_transcription.model_id = model_id;
    event.data.stt_transcription.error_code = error_code;
    event.data.stt_transcription.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_STT_TRANSCRIPTION_FAILED, &event);
}

void emit_tts_synthesis_started(const char* synthesis_id, const char* model_id,
                                int32_t character_count, int32_t sample_rate,
                                rac_inference_framework_t framework) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_TTS_SYNTHESIS_STARTED;
    event.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
    event.data.tts_synthesis.synthesis_id = synthesis_id;
    event.data.tts_synthesis.model_id = model_id;
    event.data.tts_synthesis.character_count = character_count;
    event.data.tts_synthesis.sample_rate = sample_rate;
    event.data.tts_synthesis.framework = framework;

    rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_STARTED, &event);
}

void emit_tts_synthesis_completed(const char* synthesis_id, const char* model_id,
                                  int32_t character_count, double audio_duration_ms,
                                  int32_t audio_size_bytes, double processing_duration_ms,
                                  double characters_per_second, int32_t sample_rate,
                                  rac_inference_framework_t framework) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_TTS_SYNTHESIS_COMPLETED;
    event.data.tts_synthesis.synthesis_id = synthesis_id;
    event.data.tts_synthesis.model_id = model_id;
    event.data.tts_synthesis.character_count = character_count;
    event.data.tts_synthesis.audio_duration_ms = audio_duration_ms;
    event.data.tts_synthesis.audio_size_bytes = audio_size_bytes;
    event.data.tts_synthesis.processing_duration_ms = processing_duration_ms;
    event.data.tts_synthesis.characters_per_second = characters_per_second;
    event.data.tts_synthesis.sample_rate = sample_rate;
    event.data.tts_synthesis.framework = framework;
    event.data.tts_synthesis.error_code = RAC_SUCCESS;

    rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_COMPLETED, &event);
}

void emit_tts_synthesis_failed(const char* synthesis_id, const char* model_id,
                               rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_TTS_SYNTHESIS_FAILED;
    event.data.tts_synthesis = RAC_ANALYTICS_TTS_SYNTHESIS_DEFAULT;
    event.data.tts_synthesis.synthesis_id = synthesis_id;
    event.data.tts_synthesis.model_id = model_id;
    event.data.tts_synthesis.error_code = error_code;
    event.data.tts_synthesis.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_TTS_SYNTHESIS_FAILED, &event);
}

void emit_vad_started() {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VAD_STARTED;
    event.data.vad = RAC_ANALYTICS_VAD_DEFAULT;

    rac_analytics_event_emit(RAC_EVENT_VAD_STARTED, &event);
}

void emit_vad_stopped() {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VAD_STOPPED;
    event.data.vad = RAC_ANALYTICS_VAD_DEFAULT;

    rac_analytics_event_emit(RAC_EVENT_VAD_STOPPED, &event);
}

void emit_vad_speech_started(float energy_level) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VAD_SPEECH_STARTED;
    event.data.vad.speech_duration_ms = 0.0;
    event.data.vad.energy_level = energy_level;

    rac_analytics_event_emit(RAC_EVENT_VAD_SPEECH_STARTED, &event);
}

void emit_vad_speech_ended(double speech_duration_ms, float energy_level) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VAD_SPEECH_ENDED;
    event.data.vad.speech_duration_ms = speech_duration_ms;
    event.data.vad.energy_level = energy_level;

    rac_analytics_event_emit(RAC_EVENT_VAD_SPEECH_ENDED, &event);
}

// =============================================================================
// SDK LIFECYCLE EVENTS
// =============================================================================

void emit_sdk_init_started() {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_SDK_INIT_STARTED;
    event.data.sdk_lifecycle = RAC_ANALYTICS_SDK_LIFECYCLE_DEFAULT;

    rac_analytics_event_emit(RAC_EVENT_SDK_INIT_STARTED, &event);
}

void emit_sdk_init_completed(double duration_ms) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_SDK_INIT_COMPLETED;
    event.data.sdk_lifecycle = RAC_ANALYTICS_SDK_LIFECYCLE_DEFAULT;
    event.data.sdk_lifecycle.duration_ms = duration_ms;

    rac_analytics_event_emit(RAC_EVENT_SDK_INIT_COMPLETED, &event);
}

void emit_sdk_init_failed(rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_SDK_INIT_FAILED;
    event.data.sdk_lifecycle = RAC_ANALYTICS_SDK_LIFECYCLE_DEFAULT;
    event.data.sdk_lifecycle.error_code = error_code;
    event.data.sdk_lifecycle.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_SDK_INIT_FAILED, &event);
}

void emit_sdk_models_loaded(int32_t count, double duration_ms) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_SDK_MODELS_LOADED;
    event.data.sdk_lifecycle = RAC_ANALYTICS_SDK_LIFECYCLE_DEFAULT;
    event.data.sdk_lifecycle.count = count;
    event.data.sdk_lifecycle.duration_ms = duration_ms;

    rac_analytics_event_emit(RAC_EVENT_SDK_MODELS_LOADED, &event);
}

// =============================================================================
// MODEL DOWNLOAD EVENTS
// =============================================================================

void emit_model_download_started(const char* model_id, int64_t total_bytes,
                                 const char* archive_type) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DOWNLOAD_STARTED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.total_bytes = total_bytes;
    event.data.model_download.archive_type = archive_type;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_STARTED, &event);
}

void emit_model_download_progress(const char* model_id, double progress, int64_t bytes_downloaded,
                                  int64_t total_bytes) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DOWNLOAD_PROGRESS;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.progress = progress;
    event.data.model_download.bytes_downloaded = bytes_downloaded;
    event.data.model_download.total_bytes = total_bytes;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_PROGRESS, &event);
}

void emit_model_download_completed(const char* model_id, int64_t size_bytes, double duration_ms,
                                   const char* archive_type) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DOWNLOAD_COMPLETED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.size_bytes = size_bytes;
    event.data.model_download.duration_ms = duration_ms;
    event.data.model_download.archive_type = archive_type;
    event.data.model_download.progress = 100.0;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_COMPLETED, &event);
}

void emit_model_download_failed(const char* model_id, rac_result_t error_code,
                                const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DOWNLOAD_FAILED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.error_code = error_code;
    event.data.model_download.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_FAILED, &event);
}

void emit_model_download_cancelled(const char* model_id) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DOWNLOAD_CANCELLED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_CANCELLED, &event);
}

// =============================================================================
// MODEL EXTRACTION EVENTS
// =============================================================================

void emit_model_extraction_started(const char* model_id, const char* archive_type) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_EXTRACTION_STARTED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.archive_type = archive_type;

    rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_STARTED, &event);
}

void emit_model_extraction_progress(const char* model_id, double progress) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_EXTRACTION_PROGRESS;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.progress = progress;

    rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_PROGRESS, &event);
}

void emit_model_extraction_completed(const char* model_id, int64_t size_bytes, double duration_ms) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_EXTRACTION_COMPLETED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.size_bytes = size_bytes;
    event.data.model_download.duration_ms = duration_ms;

    rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_COMPLETED, &event);
}

void emit_model_extraction_failed(const char* model_id, rac_result_t error_code,
                                  const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_EXTRACTION_FAILED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.error_code = error_code;
    event.data.model_download.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_FAILED, &event);
}

void emit_model_deleted(const char* model_id, int64_t size_bytes) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_MODEL_DELETED;
    event.data.model_download = RAC_ANALYTICS_MODEL_DOWNLOAD_DEFAULT;
    event.data.model_download.model_id = model_id;
    event.data.model_download.size_bytes = size_bytes;

    rac_analytics_event_emit(RAC_EVENT_MODEL_DELETED, &event);
}

// =============================================================================
// STORAGE EVENTS
// =============================================================================

void emit_storage_cache_cleared(int64_t freed_bytes) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STORAGE_CACHE_CLEARED;
    event.data.storage = RAC_ANALYTICS_STORAGE_DEFAULT;
    event.data.storage.freed_bytes = freed_bytes;

    rac_analytics_event_emit(RAC_EVENT_STORAGE_CACHE_CLEARED, &event);
}

void emit_storage_cache_clear_failed(rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STORAGE_CACHE_CLEAR_FAILED;
    event.data.storage = RAC_ANALYTICS_STORAGE_DEFAULT;
    event.data.storage.error_code = error_code;
    event.data.storage.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_STORAGE_CACHE_CLEAR_FAILED, &event);
}

void emit_storage_temp_cleaned(int64_t freed_bytes) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_STORAGE_TEMP_CLEANED;
    event.data.storage = RAC_ANALYTICS_STORAGE_DEFAULT;
    event.data.storage.freed_bytes = freed_bytes;

    rac_analytics_event_emit(RAC_EVENT_STORAGE_TEMP_CLEANED, &event);
}

// =============================================================================
// DEVICE EVENTS
// =============================================================================

void emit_device_registered(const char* device_id) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_DEVICE_REGISTERED;
    event.data.device = RAC_ANALYTICS_DEVICE_DEFAULT;
    event.data.device.device_id = device_id;

    rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTERED, &event);
}

void emit_device_registration_failed(rac_result_t error_code, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_DEVICE_REGISTRATION_FAILED;
    event.data.device = RAC_ANALYTICS_DEVICE_DEFAULT;
    event.data.device.error_code = error_code;
    event.data.device.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTRATION_FAILED, &event);
}

// =============================================================================
// NETWORK EVENTS
// =============================================================================

void emit_network_connectivity_changed(bool is_online) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_NETWORK_CONNECTIVITY_CHANGED;
    event.data.network = RAC_ANALYTICS_NETWORK_DEFAULT;
    event.data.network.is_online = is_online ? RAC_TRUE : RAC_FALSE;

    rac_analytics_event_emit(RAC_EVENT_NETWORK_CONNECTIVITY_CHANGED, &event);
}

// =============================================================================
// SDK ERROR EVENTS
// =============================================================================

void emit_sdk_error(rac_result_t error_code, const char* error_message, const char* operation,
                    const char* context) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_SDK_ERROR;
    event.data.sdk_error = RAC_ANALYTICS_SDK_ERROR_DEFAULT;
    event.data.sdk_error.error_code = error_code;
    event.data.sdk_error.error_message = error_message;
    event.data.sdk_error.operation = operation;
    event.data.sdk_error.context = context;

    rac_analytics_event_emit(RAC_EVENT_SDK_ERROR, &event);
}

// =============================================================================
// VOICE AGENT STATE EVENTS
// =============================================================================

void emit_voice_agent_stt_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VOICE_AGENT_STT_STATE_CHANGED;
    event.data.voice_agent_state.component = "stt";
    event.data.voice_agent_state.state = state;
    event.data.voice_agent_state.model_id = model_id;
    event.data.voice_agent_state.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_STT_STATE_CHANGED, &event);
}

void emit_voice_agent_llm_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VOICE_AGENT_LLM_STATE_CHANGED;
    event.data.voice_agent_state.component = "llm";
    event.data.voice_agent_state.state = state;
    event.data.voice_agent_state.model_id = model_id;
    event.data.voice_agent_state.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_LLM_STATE_CHANGED, &event);
}

void emit_voice_agent_tts_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VOICE_AGENT_TTS_STATE_CHANGED;
    event.data.voice_agent_state.component = "tts";
    event.data.voice_agent_state.state = state;
    event.data.voice_agent_state.model_id = model_id;
    event.data.voice_agent_state.error_message = error_message;

    rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_TTS_STATE_CHANGED, &event);
}

void emit_voice_agent_all_ready() {
    rac_analytics_event_data_t event = {};
    event.type = RAC_EVENT_VOICE_AGENT_ALL_READY;
    event.data.voice_agent_state.component = "all";
    event.data.voice_agent_state.state = RAC_VOICE_AGENT_STATE_LOADED;
    event.data.voice_agent_state.model_id = nullptr;
    event.data.voice_agent_state.error_message = nullptr;

    rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_ALL_READY, &event);
}

}  // namespace rac::events
