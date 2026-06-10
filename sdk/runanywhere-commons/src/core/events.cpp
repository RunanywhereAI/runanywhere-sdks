/**
 * @file events.cpp
 * @brief RunAnywhere Commons - SDK-originated event emit helpers.
 *
 * C++ is the canonical source of truth for all SDK events. These helpers build
 * the canonical runanywhere.v1.SDKEvent proto payloads and publish them through
 * the single destination router (sdk_event_publish.h), which fans out to the
 * public proto stream, telemetry, and log sinks based on each event's
 * destination bitmask.
 *
 * The C++ `rac::events::emit_*` helpers are the internal emitters used by the
 * JNI bridge and the voice-agent feature layer.
 *
 * The legacy struct-based analytics taxonomy (rac_analytics_event_data_t union,
 * the analytics/public callback registry, rac_analytics_event_emit, and
 * rac_event_get_destination) has been removed; all events now flow through the
 * proto catalog.
 */

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_sdk_emit.h"
#include "rac/infrastructure/events/rac_voice_agent_state.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include <string>
#include <utility>

#include "infrastructure/events/sdk_event_publish.h"
#include "sdk_events.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

namespace v1 = runanywhere::v1;

// Map the legacy C error result onto the envelope SDKError so failed events
// carry success=false + an error message through to telemetry. Keeps the
// per-payload `error` string too where the message is meaningful.
void set_event_error(v1::SDKEvent& event, rac_result_t error_code, const char* message) {
    if (error_code == RAC_SUCCESS && (message == nullptr || message[0] == '\0')) {
        return;
    }
    auto* err = event.mutable_error();
    err->set_message(message != nullptr ? message : "");
    err->set_c_abi_code(static_cast<int32_t>(error_code));
}

v1::ComponentLifecycleState voice_agent_state_to_proto(rac_voice_agent_component_state_t state) {
    switch (state) {
        case RAC_VOICE_AGENT_STATE_LOADING:
            return v1::COMPONENT_LIFECYCLE_STATE_LOADING;
        case RAC_VOICE_AGENT_STATE_LOADED:
            return v1::COMPONENT_LIFECYCLE_STATE_READY;
        case RAC_VOICE_AGENT_STATE_ERROR:
            return v1::COMPONENT_LIFECYCLE_STATE_ERROR;
        case RAC_VOICE_AGENT_STATE_NOT_LOADED:
        default:
            return v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
    }
}

// Emit a voice-agent component-state transition as a ComponentInitializationEvent.
void emit_voice_agent_state(v1::SDKComponent component, rac_voice_agent_component_state_t state,
                            const char* model_id, const char* error_message) {
    v1::ComponentInitializationEvent ev;
    ev.set_kind(v1::COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED);
    ev.set_component(component);
    if (model_id)
        ev.set_model_id(model_id);
    if (error_message)
        ev.set_error(error_message);
    ev.set_current_lifecycle_state(voice_agent_state_to_proto(state));
    rac::events::publish(component, v1::EVENT_CATEGORY_COMPONENT, std::move(ev));
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace


// =============================================================================
// HELPER FUNCTIONS FOR C++ COMPONENTS / JNI BRIDGE
// =============================================================================

namespace rac::events {

#if defined(RAC_HAVE_PROTOBUF)

void emit_llm_generation_started(const char* generation_id, const char* model_id, bool is_streaming,
                                 rac_inference_framework_t framework, float temperature,
                                 int32_t max_tokens, int32_t context_length) {
    v1::GenerationEvent g;
    g.set_kind(v1::GENERATION_EVENT_KIND_STARTED);
    if (model_id)
        g.set_model_id(model_id);
    g.set_is_streaming(is_streaming);
    g.set_framework(framework_to_proto_int(framework));
    g.set_temperature(temperature);
    g.set_max_tokens(max_tokens);
    g.set_context_length(context_length);
    publish_with_session(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_LLM, std::move(g), generation_id);
}

void emit_llm_generation_completed(const char* generation_id, const char* model_id,
                                   int32_t input_tokens, int32_t output_tokens, double duration_ms,
                                   double tokens_per_second, bool is_streaming,
                                   double time_to_first_token_ms,
                                   rac_inference_framework_t framework, float temperature,
                                   int32_t max_tokens, int32_t context_length) {
    v1::GenerationEvent g;
    g.set_kind(v1::GENERATION_EVENT_KIND_COMPLETED);
    if (model_id)
        g.set_model_id(model_id);
    g.set_input_tokens(input_tokens);
    g.set_tokens_used(output_tokens);
    g.set_latency_ms(static_cast<int64_t>(duration_ms));
    g.set_duration_ms(duration_ms);
    g.set_tokens_per_second(tokens_per_second);
    g.set_is_streaming(is_streaming);
    g.set_time_to_first_token_ms(static_cast<int64_t>(time_to_first_token_ms));
    g.set_framework(framework_to_proto_int(framework));
    g.set_temperature(temperature);
    g.set_max_tokens(max_tokens);
    g.set_context_length(context_length);
    publish_with_session(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_LLM, std::move(g), generation_id);
}

void emit_llm_generation_failed(const char* generation_id, const char* model_id,
                                rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* g = event.mutable_generation();
    g->set_kind(v1::GENERATION_EVENT_KIND_FAILED);
    if (model_id)
        g->set_model_id(model_id);
    if (error_message)
        g->set_error(error_message);
    if (generation_id)
        event.set_session_id(generation_id);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_LLM);
}

void emit_llm_first_token(const char* generation_id, const char* model_id,
                          double time_to_first_token_ms, rac_inference_framework_t framework) {
    v1::GenerationEvent g;
    g.set_kind(v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED);
    if (model_id)
        g.set_model_id(model_id);
    g.set_first_token_latency_ms(static_cast<int64_t>(time_to_first_token_ms));
    g.set_framework(framework_to_proto_int(framework));
    publish_with_session(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_LLM, std::move(g), generation_id);
}

void emit_llm_streaming_update(const char* generation_id, int32_t tokens_generated) {
    v1::GenerationEvent g;
    g.set_kind(v1::GENERATION_EVENT_KIND_STREAMING_UPDATE);
    g.set_tokens_count(tokens_generated);
    publish_with_session(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_LLM, std::move(g), generation_id,
                         legacy_destination_public());
}

void emit_llm_model_load_completed(const char* model_id, const char* model_name, double duration_ms,
                                   rac_inference_framework_t framework) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_LOAD_COMPLETED);
    if (model_id)
        m.set_model_id(model_id);
    if (model_name)
        m.set_model_name(model_name);
    m.set_duration_ms(static_cast<int64_t>(duration_ms));
    m.set_framework(framework_to_proto_int(framework));
    publish(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_MODEL, std::move(m));
}

void emit_llm_model_load_failed(const char* model_id, const char* model_name, double duration_ms,
                                rac_inference_framework_t framework, rac_result_t error_code,
                                const char* error_message) {
    v1::SDKEvent event;
    auto* m = event.mutable_model();
    m->set_kind(v1::MODEL_EVENT_KIND_LOAD_FAILED);
    if (model_id)
        m->set_model_id(model_id);
    if (model_name)
        m->set_model_name(model_name);
    m->set_duration_ms(static_cast<int64_t>(duration_ms));
    m->set_framework(framework_to_proto_int(framework));
    if (error_message)
        m->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_MODEL);
}

void emit_llm_model_unloaded(const char* model_id) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_UNLOAD_COMPLETED);
    if (model_id)
        m.set_model_id(model_id);
    publish(v1::SDK_COMPONENT_LLM, v1::EVENT_CATEGORY_MODEL, std::move(m));
}

void emit_stt_transcription_started(const char* transcription_id, const char* model_id,
                                    double audio_length_ms, int32_t audio_size_bytes,
                                    const char* language, bool is_streaming, int32_t sample_rate,
                                    rac_inference_framework_t framework) {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_TRANSCRIPTION_STARTED);
    if (model_id)
        voice.set_model_id(model_id);
    voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
    voice.set_audio_size_bytes(audio_size_bytes);
    if (language)
        voice.set_language(language);
    voice.set_is_streaming(is_streaming);
    voice.set_sample_rate(sample_rate);
    voice.set_framework(framework_to_proto_int(framework));
    publish_with_session(v1::SDK_COMPONENT_STT, v1::EVENT_CATEGORY_STT, std::move(voice),
                         transcription_id);
}

void emit_stt_transcription_completed(const char* transcription_id, const char* model_id,
                                      const char* text, float confidence, double duration_ms,
                                      double audio_length_ms, int32_t audio_size_bytes,
                                      int32_t word_count, double real_time_factor,
                                      const char* language, int32_t sample_rate,
                                      rac_inference_framework_t framework) {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_STT_COMPLETED);
    if (model_id)
        voice.set_model_id(model_id);
    if (text)
        voice.set_text(text);
    voice.set_confidence(confidence);
    voice.set_duration_ms(static_cast<int64_t>(duration_ms));
    voice.set_audio_length_ms(static_cast<int64_t>(audio_length_ms));
    voice.set_audio_size_bytes(audio_size_bytes);
    voice.set_word_count(word_count);
    voice.set_real_time_factor(real_time_factor);
    if (language)
        voice.set_language(language);
    voice.set_sample_rate(sample_rate);
    voice.set_framework(framework_to_proto_int(framework));
    publish_with_session(v1::SDK_COMPONENT_STT, v1::EVENT_CATEGORY_STT, std::move(voice),
                         transcription_id);
}

void emit_stt_transcription_failed(const char* transcription_id, const char* model_id,
                                   rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* voice = event.mutable_voice();
    voice->set_kind(v1::VOICE_EVENT_KIND_STT_FAILED);
    if (model_id)
        voice->set_model_id(model_id);
    if (error_message)
        voice->set_error(error_message);
    if (transcription_id)
        event.set_session_id(transcription_id);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_STT, v1::EVENT_CATEGORY_STT);
}

void emit_tts_synthesis_started(const char* synthesis_id, const char* model_id,
                                int32_t character_count, int32_t sample_rate,
                                rac_inference_framework_t framework) {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED);
    if (model_id)
        voice.set_model_id(model_id);
    voice.set_character_count(character_count);
    voice.set_sample_rate(sample_rate);
    voice.set_framework(framework_to_proto_int(framework));
    publish_with_session(v1::SDK_COMPONENT_TTS, v1::EVENT_CATEGORY_TTS, std::move(voice),
                         synthesis_id);
}

void emit_tts_synthesis_completed(const char* synthesis_id, const char* model_id,
                                  int32_t character_count, double audio_duration_ms,
                                  int32_t audio_size_bytes, double processing_duration_ms,
                                  double characters_per_second, int32_t sample_rate,
                                  rac_inference_framework_t framework) {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED);
    if (model_id)
        voice.set_model_id(model_id);
    voice.set_character_count(character_count);
    voice.set_audio_duration_ms(static_cast<int64_t>(audio_duration_ms));
    voice.set_audio_size_bytes_tts(audio_size_bytes);
    voice.set_processing_duration_ms(static_cast<int64_t>(processing_duration_ms));
    voice.set_characters_per_second(characters_per_second);
    voice.set_sample_rate(sample_rate);
    voice.set_framework(framework_to_proto_int(framework));
    publish_with_session(v1::SDK_COMPONENT_TTS, v1::EVENT_CATEGORY_TTS, std::move(voice),
                         synthesis_id);
}

void emit_tts_synthesis_failed(const char* synthesis_id, const char* model_id,
                               rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* voice = event.mutable_voice();
    voice->set_kind(v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED);
    if (model_id)
        voice->set_model_id(model_id);
    if (error_message)
        voice->set_error(error_message);
    if (synthesis_id)
        event.set_session_id(synthesis_id);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_TTS, v1::EVENT_CATEGORY_TTS);
}

void emit_vad_started() {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_VAD_STARTED);
    publish(v1::SDK_COMPONENT_VAD, v1::EVENT_CATEGORY_VAD, std::move(voice));
}

void emit_vad_stopped() {
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_VAD_STOPPED);
    publish(v1::SDK_COMPONENT_VAD, v1::EVENT_CATEGORY_VAD, std::move(voice));
}

void emit_vad_speech_started(float energy_level) {
    (void)energy_level;
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_SPEECH_STARTED);
    publish_with_session(v1::SDK_COMPONENT_VAD, v1::EVENT_CATEGORY_VAD, std::move(voice),
                         /*session_id=*/nullptr, legacy_destination_telemetry());
}

void emit_vad_speech_ended(double speech_duration_ms, float energy_level) {
    (void)energy_level;
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(v1::VOICE_EVENT_KIND_SPEECH_ENDED);
    voice.set_duration_ms(static_cast<int64_t>(speech_duration_ms));
    publish_with_session(v1::SDK_COMPONENT_VAD, v1::EVENT_CATEGORY_VAD, std::move(voice),
                         /*session_id=*/nullptr, legacy_destination_telemetry());
}

// =============================================================================
// SDK LIFECYCLE EVENTS
// =============================================================================

void emit_sdk_init_started() {
    v1::InitializationEvent ev;
    ev.set_stage(v1::INITIALIZATION_STAGE_STARTED);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_INITIALIZATION, std::move(ev));
}

void emit_sdk_init_completed(double duration_ms) {
    v1::SDKEvent event;
    event.mutable_initialization()->set_stage(v1::INITIALIZATION_STAGE_COMPLETED);
    (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_INITIALIZATION);
}

void emit_sdk_init_failed(rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* init = event.mutable_initialization();
    init->set_stage(v1::INITIALIZATION_STAGE_FAILED);
    if (error_message)
        init->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_INITIALIZATION);
}

void emit_sdk_models_loaded(int32_t count, double duration_ms) {
    v1::SDKEvent event;
    event.mutable_initialization()->set_stage(v1::INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED);
    (*event.mutable_properties())["model_count"] = std::to_string(count);
    (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_INITIALIZATION);
}

// =============================================================================
// MODEL DOWNLOAD EVENTS
// =============================================================================

void emit_model_download_started(const char* model_id, int64_t total_bytes,
                                 const char* archive_type) {
    (void)archive_type;
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_DOWNLOAD_STARTED);
    if (model_id)
        m.set_model_id(model_id);
    m.set_total_bytes(total_bytes);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD, std::move(m));
}

void emit_model_download_progress(const char* model_id, double progress, int64_t bytes_downloaded,
                                  int64_t total_bytes) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_DOWNLOAD_PROGRESS);
    if (model_id)
        m.set_model_id(model_id);
    m.set_progress(static_cast<float>(progress));
    m.set_bytes_downloaded(bytes_downloaded);
    m.set_total_bytes(total_bytes);
    // Progress is too chatty for telemetry — public stream only.
    v1::SDKEvent event;
    *event.mutable_model() = std::move(m);
    event.set_destination(legacy_destination_public());
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD);
}

void emit_model_download_completed(const char* model_id, int64_t size_bytes, double duration_ms,
                                   const char* archive_type) {
    (void)archive_type;
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_DOWNLOAD_COMPLETED);
    if (model_id)
        m.set_model_id(model_id);
    m.set_model_size_bytes(size_bytes);
    m.set_duration_ms(static_cast<int64_t>(duration_ms));
    m.set_progress(1.0f);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD, std::move(m));
}

void emit_model_download_failed(const char* model_id, rac_result_t error_code,
                                const char* error_message) {
    v1::SDKEvent event;
    auto* m = event.mutable_model();
    m->set_kind(v1::MODEL_EVENT_KIND_DOWNLOAD_FAILED);
    if (model_id)
        m->set_model_id(model_id);
    if (error_message)
        m->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD);
}

void emit_model_download_cancelled(const char* model_id) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_DOWNLOAD_CANCELLED);
    if (model_id)
        m.set_model_id(model_id);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD, std::move(m));
}

// =============================================================================
// MODEL EXTRACTION EVENTS
// =============================================================================

void emit_model_extraction_started(const char* model_id, const char* archive_type) {
    (void)archive_type;
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_EXTRACTION_STARTED);
    if (model_id)
        m.set_model_id(model_id);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD, std::move(m));
}

void emit_model_extraction_progress(const char* model_id, double progress) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_EXTRACTION_PROGRESS);
    if (model_id)
        m.set_model_id(model_id);
    m.set_progress(static_cast<float>(progress));
    // Progress is too chatty for telemetry — public stream only.
    v1::SDKEvent event;
    *event.mutable_model() = std::move(m);
    event.set_destination(legacy_destination_public());
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD);
}

void emit_model_extraction_completed(const char* model_id, int64_t size_bytes, double duration_ms) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_EXTRACTION_COMPLETED);
    if (model_id)
        m.set_model_id(model_id);
    m.set_model_size_bytes(size_bytes);
    m.set_duration_ms(static_cast<int64_t>(duration_ms));
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD, std::move(m));
}

void emit_model_extraction_failed(const char* model_id, rac_result_t error_code,
                                  const char* error_message) {
    v1::SDKEvent event;
    auto* m = event.mutable_model();
    m->set_kind(v1::MODEL_EVENT_KIND_EXTRACTION_FAILED);
    if (model_id)
        m->set_model_id(model_id);
    if (error_message)
        m->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DOWNLOAD);
}

void emit_model_deleted(const char* model_id, int64_t size_bytes) {
    v1::ModelEvent m;
    m.set_kind(v1::MODEL_EVENT_KIND_DELETE_COMPLETED);
    if (model_id)
        m.set_model_id(model_id);
    m.set_model_size_bytes(size_bytes);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_MODEL, std::move(m));
}

// =============================================================================
// STORAGE EVENTS
// =============================================================================

void emit_storage_cache_cleared(int64_t freed_bytes) {
    v1::StorageEvent s;
    s.set_kind(v1::STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED);
    s.set_freed_bytes(freed_bytes);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_STORAGE, std::move(s));
}

void emit_storage_cache_clear_failed(rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* s = event.mutable_storage();
    s->set_kind(v1::STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED);
    if (error_message)
        s->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_STORAGE);
}

void emit_storage_temp_cleaned(int64_t freed_bytes) {
    v1::StorageEvent s;
    s.set_kind(v1::STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED);
    s.set_freed_bytes(freed_bytes);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_STORAGE, std::move(s));
}

// =============================================================================
// DEVICE EVENTS
// =============================================================================

void emit_device_registered(const char* device_id) {
    v1::DeviceEvent d;
    d.set_kind(v1::DEVICE_EVENT_KIND_DEVICE_REGISTERED);
    if (device_id)
        d.set_device_id(device_id);
    publish(v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DEVICE, std::move(d));
}

void emit_device_registration_failed(rac_result_t error_code, const char* error_message) {
    v1::SDKEvent event;
    auto* d = event.mutable_device();
    d->set_kind(v1::DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED);
    if (error_message)
        d->set_error(error_message);
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_DEVICE);
}

// =============================================================================
// NETWORK EVENTS
// =============================================================================

void emit_network_connectivity_changed(bool is_online) {
    v1::SDKEvent event;
    auto* n = event.mutable_network();
    n->set_kind(v1::NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED);
    n->set_is_online(is_online);
    // Connectivity changes are internal metrics, not app-facing — telemetry only.
    event.set_destination(legacy_destination_telemetry());
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_NETWORK);
}

// =============================================================================
// SDK ERROR EVENTS
// =============================================================================

void emit_sdk_error(rac_result_t error_code, const char* error_message, const char* operation,
                    const char* context) {
    v1::SDKEvent event;
    auto* f = event.mutable_failure();
    if (operation)
        f->set_operation(operation);
    if (context)
        (*event.mutable_properties())["context"] = context;
    set_event_error(event, error_code, error_message);
    publish(event, v1::SDK_COMPONENT_UNSPECIFIED, v1::EVENT_CATEGORY_FAILURE);
}

// =============================================================================
// VOICE AGENT STATE EVENTS
// =============================================================================

void emit_voice_agent_stt_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    emit_voice_agent_state(v1::SDK_COMPONENT_STT, state, model_id, error_message);
}

void emit_voice_agent_llm_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    emit_voice_agent_state(v1::SDK_COMPONENT_LLM, state, model_id, error_message);
}

void emit_voice_agent_tts_state_changed(rac_voice_agent_component_state_t state,
                                        const char* model_id, const char* error_message) {
    emit_voice_agent_state(v1::SDK_COMPONENT_TTS, state, model_id, error_message);
}

void emit_voice_agent_all_ready() {
    v1::ComponentInitializationEvent ev;
    ev.set_kind(v1::COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY);
    ev.set_current_lifecycle_state(v1::COMPONENT_LIFECYCLE_STATE_READY);
    publish(v1::SDK_COMPONENT_VOICE_AGENT, v1::EVENT_CATEGORY_COMPONENT, std::move(ev));
}

#else  // !RAC_HAVE_PROTOBUF

// Without protobuf the proto event catalog is unavailable; the SDK-originated
// emit helpers degrade to no-ops so non-protobuf builds still link.
void emit_llm_generation_started(const char*, const char*, bool, rac_inference_framework_t, float,
                                 int32_t, int32_t) {}
void emit_llm_generation_completed(const char*, const char*, int32_t, int32_t, double, double, bool,
                                   double, rac_inference_framework_t, float, int32_t, int32_t) {}
void emit_llm_generation_failed(const char*, const char*, rac_result_t, const char*) {}
void emit_llm_first_token(const char*, const char*, double, rac_inference_framework_t) {}
void emit_llm_streaming_update(const char*, int32_t) {}
void emit_llm_model_load_completed(const char*, const char*, double, rac_inference_framework_t) {}
void emit_llm_model_load_failed(const char*, const char*, double, rac_inference_framework_t,
                                rac_result_t, const char*) {}
void emit_llm_model_unloaded(const char*) {}
void emit_stt_transcription_started(const char*, const char*, double, int32_t, const char*, bool,
                                    int32_t, rac_inference_framework_t) {}
void emit_stt_transcription_completed(const char*, const char*, const char*, float, double, double,
                                      int32_t, int32_t, double, const char*, int32_t,
                                      rac_inference_framework_t) {}
void emit_stt_transcription_failed(const char*, const char*, rac_result_t, const char*) {}
void emit_tts_synthesis_started(const char*, const char*, int32_t, int32_t,
                                rac_inference_framework_t) {}
void emit_tts_synthesis_completed(const char*, const char*, int32_t, double, int32_t, double, double,
                                  int32_t, rac_inference_framework_t) {}
void emit_tts_synthesis_failed(const char*, const char*, rac_result_t, const char*) {}
void emit_vad_started() {}
void emit_vad_stopped() {}
void emit_vad_speech_started(float) {}
void emit_vad_speech_ended(double, float) {}
void emit_sdk_init_started() {}
void emit_sdk_init_completed(double) {}
void emit_sdk_init_failed(rac_result_t, const char*) {}
void emit_sdk_models_loaded(int32_t, double) {}
void emit_model_download_started(const char*, int64_t, const char*) {}
void emit_model_download_progress(const char*, double, int64_t, int64_t) {}
void emit_model_download_completed(const char*, int64_t, double, const char*) {}
void emit_model_download_failed(const char*, rac_result_t, const char*) {}
void emit_model_download_cancelled(const char*) {}
void emit_model_extraction_started(const char*, const char*) {}
void emit_model_extraction_progress(const char*, double) {}
void emit_model_extraction_completed(const char*, int64_t, double) {}
void emit_model_extraction_failed(const char*, rac_result_t, const char*) {}
void emit_model_deleted(const char*, int64_t) {}
void emit_storage_cache_cleared(int64_t) {}
void emit_storage_cache_clear_failed(rac_result_t, const char*) {}
void emit_storage_temp_cleaned(int64_t) {}
void emit_device_registered(const char*) {}
void emit_device_registration_failed(rac_result_t, const char*) {}
void emit_network_connectivity_changed(bool) {}
void emit_sdk_error(rac_result_t, const char*, const char*, const char*) {}
void emit_voice_agent_stt_state_changed(rac_voice_agent_component_state_t, const char*,
                                        const char*) {}
void emit_voice_agent_llm_state_changed(rac_voice_agent_component_state_t, const char*,
                                        const char*) {}
void emit_voice_agent_tts_state_changed(rac_voice_agent_component_state_t, const char*,
                                        const char*) {}
void emit_voice_agent_all_ready() {}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::events
