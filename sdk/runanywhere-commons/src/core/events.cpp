/**
 * @file events.cpp
 * @brief RunAnywhere Commons - Cross-Platform Event System Implementation
 *
 * C++ is the canonical source of truth for all analytics events.
 * Platform SDKs register callbacks to receive events.
 */

#include <mutex>

#include "rac/core/rac_analytics_events.h"

// =============================================================================
// INTERNAL STATE
// =============================================================================

namespace {

// Thread-safe event callback storage
struct EventCallbackState {
    rac_analytics_callback_fn callback = nullptr;
    void* user_data = nullptr;
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

rac_result_t rac_analytics_events_set_callback(rac_analytics_callback_fn callback,
                                               void* user_data) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    state.callback = callback;
    state.user_data = user_data;

    return RAC_SUCCESS;
}

void rac_analytics_event_emit(rac_event_type_t type, const rac_analytics_event_data_t* data) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.callback != nullptr && data != nullptr) {
        state.callback(type, data, state.user_data);
    }
}

rac_bool_t rac_analytics_events_has_callback(void) {
    auto& state = get_callback_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    return state.callback != nullptr ? RAC_TRUE : RAC_FALSE;
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

}  // namespace rac::events
