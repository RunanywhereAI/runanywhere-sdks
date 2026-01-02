/**
 * @file telemetry_manager.cpp
 * @brief Telemetry manager implementation
 *
 * Handles event queuing, batching by modality, and HTTP callbacks.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_telemetry_manager {
    // Configuration
    rac_environment_t environment;
    std::string device_id;
    std::string platform;
    std::string sdk_version;
    std::string device_model;
    std::string os_version;

    // HTTP callback
    rac_telemetry_http_callback_t http_callback;
    void* http_user_data;

    // Event queue
    std::vector<rac_telemetry_payload_t> queue;
    std::mutex queue_mutex;

    // V2 modalities for grouping
    std::set<std::string> v2_modalities = {"llm", "stt", "tts", "model"};
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

namespace {

// Get current timestamp in milliseconds
int64_t get_current_timestamp_ms() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

// Generate UUID
std::string generate_uuid() {
    // Simple UUID generation (not RFC4122 compliant, but sufficient for event IDs)
    static const char hex[] = "0123456789abcdef";
    std::string uuid = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";

    for (char& c : uuid) {
        if (c == 'x') {
            c = hex[rand() % 16];
        } else if (c == 'y') {
            c = hex[(rand() % 4) + 8];  // 8, 9, a, or b
        }
    }

    return uuid;
}

// Duplicate string (caller must free)
char* dup_string(const char* s) {
    if (!s)
        return nullptr;
    size_t len = strlen(s) + 1;
    char* copy = (char*)malloc(len);
    if (copy)
        memcpy(copy, s, len);
    return copy;
}

// Convert analytics event type to modality
const char* event_type_to_modality(rac_event_type_t type) {
    if (type >= RAC_EVENT_LLM_MODEL_LOAD_STARTED && type <= RAC_EVENT_LLM_STREAMING_UPDATE) {
        return "llm";
    }
    if (type >= RAC_EVENT_STT_MODEL_LOAD_STARTED && type <= RAC_EVENT_STT_PARTIAL_TRANSCRIPT) {
        return "stt";
    }
    if (type >= RAC_EVENT_TTS_VOICE_LOAD_STARTED && type <= RAC_EVENT_TTS_SYNTHESIS_CHUNK) {
        return "tts";
    }
    if (type >= RAC_EVENT_VAD_STARTED && type <= RAC_EVENT_VAD_RESUMED) {
        return "system";  // VAD goes to system
    }
    return "system";
}

// Convert analytics event type to event type string
const char* event_type_to_string(rac_event_type_t type) {
    switch (type) {
        // LLM
        case RAC_EVENT_LLM_MODEL_LOAD_STARTED:
            return "llm.model.load.started";
        case RAC_EVENT_LLM_MODEL_LOAD_COMPLETED:
            return "llm.model.load.completed";
        case RAC_EVENT_LLM_MODEL_LOAD_FAILED:
            return "llm.model.load.failed";
        case RAC_EVENT_LLM_MODEL_UNLOADED:
            return "llm.model.unloaded";
        case RAC_EVENT_LLM_GENERATION_STARTED:
            return "llm.generation.started";
        case RAC_EVENT_LLM_GENERATION_COMPLETED:
            return "llm.generation.completed";
        case RAC_EVENT_LLM_GENERATION_FAILED:
            return "llm.generation.failed";
        case RAC_EVENT_LLM_FIRST_TOKEN:
            return "llm.generation.first_token";
        case RAC_EVENT_LLM_STREAMING_UPDATE:
            return "llm.generation.streaming";

        // STT
        case RAC_EVENT_STT_MODEL_LOAD_STARTED:
            return "stt.model.load.started";
        case RAC_EVENT_STT_MODEL_LOAD_COMPLETED:
            return "stt.model.load.completed";
        case RAC_EVENT_STT_MODEL_LOAD_FAILED:
            return "stt.model.load.failed";
        case RAC_EVENT_STT_MODEL_UNLOADED:
            return "stt.model.unloaded";
        case RAC_EVENT_STT_TRANSCRIPTION_STARTED:
            return "stt.transcription.started";
        case RAC_EVENT_STT_TRANSCRIPTION_COMPLETED:
            return "stt.transcription.completed";
        case RAC_EVENT_STT_TRANSCRIPTION_FAILED:
            return "stt.transcription.failed";
        case RAC_EVENT_STT_PARTIAL_TRANSCRIPT:
            return "stt.transcription.partial";

        // TTS
        case RAC_EVENT_TTS_VOICE_LOAD_STARTED:
            return "tts.voice.load.started";
        case RAC_EVENT_TTS_VOICE_LOAD_COMPLETED:
            return "tts.voice.load.completed";
        case RAC_EVENT_TTS_VOICE_LOAD_FAILED:
            return "tts.voice.load.failed";
        case RAC_EVENT_TTS_VOICE_UNLOADED:
            return "tts.voice.unloaded";
        case RAC_EVENT_TTS_SYNTHESIS_STARTED:
            return "tts.synthesis.started";
        case RAC_EVENT_TTS_SYNTHESIS_COMPLETED:
            return "tts.synthesis.completed";
        case RAC_EVENT_TTS_SYNTHESIS_FAILED:
            return "tts.synthesis.failed";
        case RAC_EVENT_TTS_SYNTHESIS_CHUNK:
            return "tts.synthesis.chunk";

        // VAD
        case RAC_EVENT_VAD_STARTED:
            return "vad.started";
        case RAC_EVENT_VAD_STOPPED:
            return "vad.stopped";
        case RAC_EVENT_VAD_SPEECH_STARTED:
            return "vad.speech.started";
        case RAC_EVENT_VAD_SPEECH_ENDED:
            return "vad.speech.ended";
        case RAC_EVENT_VAD_PAUSED:
            return "vad.paused";
        case RAC_EVENT_VAD_RESUMED:
            return "vad.resumed";

        // VoiceAgent
        case RAC_EVENT_VOICE_AGENT_TURN_STARTED:
            return "voice_agent.turn.started";
        case RAC_EVENT_VOICE_AGENT_TURN_COMPLETED:
            return "voice_agent.turn.completed";
        case RAC_EVENT_VOICE_AGENT_TURN_FAILED:
            return "voice_agent.turn.failed";

        default:
            return "unknown";
    }
}

// Convert framework enum to string
const char* framework_to_string(rac_inference_framework_t framework) {
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return "onnx";
        case RAC_FRAMEWORK_LLAMACPP:
            return "llamacpp";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "foundation_models";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "system_tts";
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return "fluid_audio";
        case RAC_FRAMEWORK_BUILTIN:
            return "builtin";
        case RAC_FRAMEWORK_NONE:
            return "none";
        case RAC_FRAMEWORK_UNKNOWN:
        default:
            return "unknown";
    }
}

}  // namespace

// =============================================================================
// LIFECYCLE
// =============================================================================

rac_telemetry_manager_t* rac_telemetry_manager_create(rac_environment_t env, const char* device_id,
                                                      const char* platform,
                                                      const char* sdk_version) {
    auto* manager = new (std::nothrow) rac_telemetry_manager_t();
    if (!manager)
        return nullptr;

    manager->environment = env;
    manager->device_id = device_id ? device_id : "";
    manager->platform = platform ? platform : "";
    manager->sdk_version = sdk_version ? sdk_version : "";
    manager->http_callback = nullptr;
    manager->http_user_data = nullptr;

    log_debug("Telemetry", "Telemetry manager created for environment %d", env);

    return manager;
}

void rac_telemetry_manager_destroy(rac_telemetry_manager_t* manager) {
    if (!manager)
        return;

    // Flush any remaining events
    rac_telemetry_manager_flush(manager);

    delete manager;
    log_debug("Telemetry", "Telemetry manager destroyed");
}

void rac_telemetry_manager_set_device_info(rac_telemetry_manager_t* manager,
                                           const char* device_model, const char* os_version) {
    if (!manager)
        return;

    manager->device_model = device_model ? device_model : "";
    manager->os_version = os_version ? os_version : "";
}

void rac_telemetry_manager_set_http_callback(rac_telemetry_manager_t* manager,
                                             rac_telemetry_http_callback_t callback,
                                             void* user_data) {
    if (!manager)
        return;

    manager->http_callback = callback;
    manager->http_user_data = user_data;
}

// =============================================================================
// EVENT TRACKING
// =============================================================================

rac_result_t rac_telemetry_manager_track(rac_telemetry_manager_t* manager,
                                         const rac_telemetry_payload_t* payload) {
    if (!manager || !payload) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Deep copy payload for queue
    rac_telemetry_payload_t copy = *payload;
    copy.id = dup_string(payload->id);
    copy.event_type = dup_string(payload->event_type);
    copy.modality = dup_string(payload->modality);
    copy.device_id = dup_string(manager->device_id.c_str());
    copy.session_id = dup_string(payload->session_id);
    copy.model_id = dup_string(payload->model_id);
    copy.model_name = dup_string(payload->model_name);
    copy.framework = dup_string(payload->framework);
    copy.device = dup_string(manager->device_model.c_str());
    copy.os_version = dup_string(manager->os_version.c_str());
    copy.platform = dup_string(manager->platform.c_str());
    copy.sdk_version = dup_string(manager->sdk_version.c_str());
    copy.error_message = dup_string(payload->error_message);
    copy.error_code = dup_string(payload->error_code);
    copy.language = dup_string(payload->language);
    copy.voice = dup_string(payload->voice);
    copy.archive_type = dup_string(payload->archive_type);

    {
        std::lock_guard<std::mutex> lock(manager->queue_mutex);
        manager->queue.push_back(copy);
    }

    log_debug("Telemetry", "Telemetry event queued: %s", payload->event_type);

    return RAC_SUCCESS;
}

rac_result_t rac_telemetry_manager_track_analytics(rac_telemetry_manager_t* manager,
                                                   rac_event_type_t event_type,
                                                   const rac_analytics_event_data_t* data) {
    if (!manager) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_telemetry_payload_t payload = rac_telemetry_payload_default();

    // Generate ID and timestamps
    std::string uuid = generate_uuid();
    payload.id = uuid.c_str();
    payload.timestamp_ms = get_current_timestamp_ms();
    payload.created_at_ms = payload.timestamp_ms;

    // Set event type and modality
    payload.event_type = event_type_to_string(event_type);
    payload.modality = event_type_to_modality(event_type);

    // Fill in data based on event type
    if (data) {
        switch (event_type) {
            // LLM Generation events
            case RAC_EVENT_LLM_GENERATION_STARTED:
            case RAC_EVENT_LLM_GENERATION_COMPLETED:
            case RAC_EVENT_LLM_GENERATION_FAILED:
            case RAC_EVENT_LLM_FIRST_TOKEN:
            case RAC_EVENT_LLM_STREAMING_UPDATE: {
                const auto& llm = data->data.llm_generation;
                payload.model_id = llm.model_id;
                payload.session_id = llm.generation_id;
                payload.input_tokens = llm.input_tokens;
                payload.output_tokens = llm.output_tokens;
                payload.total_tokens = llm.input_tokens + llm.output_tokens;
                payload.processing_time_ms = llm.duration_ms;
                payload.tokens_per_second = llm.tokens_per_second;
                payload.time_to_first_token_ms = llm.time_to_first_token_ms;
                payload.is_streaming = llm.is_streaming;
                payload.has_is_streaming = RAC_TRUE;
                payload.framework = framework_to_string(llm.framework);
                payload.temperature = llm.temperature;
                payload.max_tokens = llm.max_tokens;
                payload.context_length = llm.context_length;
                if (llm.error_code != RAC_SUCCESS) {
                    payload.success = RAC_FALSE;
                    payload.has_success = RAC_TRUE;
                    payload.error_message = llm.error_message;
                } else if (event_type == RAC_EVENT_LLM_GENERATION_COMPLETED) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
                break;
            }

            // LLM Model events
            case RAC_EVENT_LLM_MODEL_LOAD_STARTED:
            case RAC_EVENT_LLM_MODEL_LOAD_COMPLETED:
            case RAC_EVENT_LLM_MODEL_LOAD_FAILED:
            case RAC_EVENT_LLM_MODEL_UNLOADED: {
                const auto& model = data->data.llm_model;
                payload.model_id = model.model_id;
                payload.model_size_bytes = model.model_size_bytes;
                payload.processing_time_ms = model.duration_ms;
                payload.framework = framework_to_string(model.framework);
                if (model.error_code != RAC_SUCCESS) {
                    payload.success = RAC_FALSE;
                    payload.has_success = RAC_TRUE;
                    payload.error_message = model.error_message;
                } else if (event_type == RAC_EVENT_LLM_MODEL_LOAD_COMPLETED) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
                break;
            }

            // STT events
            case RAC_EVENT_STT_TRANSCRIPTION_STARTED:
            case RAC_EVENT_STT_TRANSCRIPTION_COMPLETED:
            case RAC_EVENT_STT_TRANSCRIPTION_FAILED:
            case RAC_EVENT_STT_PARTIAL_TRANSCRIPT: {
                const auto& stt = data->data.stt_transcription;
                payload.model_id = stt.model_id;
                payload.session_id = stt.transcription_id;
                payload.processing_time_ms = stt.duration_ms;
                payload.audio_duration_ms = stt.audio_length_ms;
                payload.audio_size_bytes = stt.audio_size_bytes;
                payload.word_count = stt.word_count;
                payload.real_time_factor = stt.real_time_factor;
                payload.confidence = stt.confidence;
                payload.language = stt.language;
                payload.sample_rate = stt.sample_rate;
                payload.is_streaming = stt.is_streaming;
                payload.has_is_streaming = RAC_TRUE;
                payload.framework = framework_to_string(stt.framework);
                if (stt.error_code != RAC_SUCCESS) {
                    payload.success = RAC_FALSE;
                    payload.has_success = RAC_TRUE;
                    payload.error_message = stt.error_message;
                } else if (event_type == RAC_EVENT_STT_TRANSCRIPTION_COMPLETED) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
                break;
            }

            // TTS events
            case RAC_EVENT_TTS_SYNTHESIS_STARTED:
            case RAC_EVENT_TTS_SYNTHESIS_COMPLETED:
            case RAC_EVENT_TTS_SYNTHESIS_FAILED:
            case RAC_EVENT_TTS_SYNTHESIS_CHUNK: {
                const auto& tts = data->data.tts_synthesis;
                payload.model_id = tts.model_id;
                payload.session_id = tts.synthesis_id;
                payload.character_count = tts.character_count;
                payload.output_duration_ms = tts.audio_duration_ms;
                payload.audio_size_bytes = tts.audio_size_bytes;
                payload.processing_time_ms = tts.processing_duration_ms;
                payload.characters_per_second = tts.characters_per_second;
                payload.sample_rate = tts.sample_rate;
                payload.framework = framework_to_string(tts.framework);
                if (tts.error_code != RAC_SUCCESS) {
                    payload.success = RAC_FALSE;
                    payload.has_success = RAC_TRUE;
                    payload.error_message = tts.error_message;
                } else if (event_type == RAC_EVENT_TTS_SYNTHESIS_COMPLETED) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
                break;
            }

            // VAD events
            case RAC_EVENT_VAD_STARTED:
            case RAC_EVENT_VAD_STOPPED:
            case RAC_EVENT_VAD_SPEECH_STARTED:
            case RAC_EVENT_VAD_SPEECH_ENDED:
            case RAC_EVENT_VAD_PAUSED:
            case RAC_EVENT_VAD_RESUMED: {
                const auto& vad = data->data.vad;
                payload.speech_duration_ms = vad.speech_duration_ms;
                break;
            }

            default:
                break;
        }
    }

    return rac_telemetry_manager_track(manager, &payload);
}

// =============================================================================
// FLUSH
// =============================================================================

rac_result_t rac_telemetry_manager_flush(rac_telemetry_manager_t* manager) {
    if (!manager) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!manager->http_callback) {
        log_warning("Telemetry", "No HTTP callback registered, cannot flush telemetry");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // Get events from queue
    std::vector<rac_telemetry_payload_t> events;
    {
        std::lock_guard<std::mutex> lock(manager->queue_mutex);
        events = std::move(manager->queue);
        manager->queue.clear();
    }

    if (events.empty()) {
        return RAC_SUCCESS;
    }

    log_debug("Telemetry", "Flushing %zu telemetry events", events.size());

    // Get endpoint
    const char* endpoint = rac_endpoint_telemetry(manager->environment);
    bool requires_auth = (manager->environment != RAC_ENV_DEVELOPMENT);

    if (manager->environment == RAC_ENV_DEVELOPMENT) {
        // Development: Send array directly to Supabase
        rac_telemetry_batch_request_t batch = {};
        batch.events = events.data();
        batch.events_count = events.size();
        batch.device_id = manager->device_id.c_str();
        batch.timestamp_ms = get_current_timestamp_ms();
        batch.modality = nullptr;  // Not used for development

        char* json = nullptr;
        size_t json_len = 0;
        rac_result_t result =
            rac_telemetry_manager_batch_to_json(&batch, manager->environment, &json, &json_len);

        if (result == RAC_SUCCESS && json) {
            manager->http_callback(manager->http_user_data, endpoint, json, json_len,
                                   requires_auth ? RAC_TRUE : RAC_FALSE);
            free(json);
        }
    } else {
        // Production: Group by modality and send batch requests
        std::map<std::string, std::vector<rac_telemetry_payload_t>> by_modality;

        for (const auto& event : events) {
            std::string modality = event.modality ? event.modality : "system";
            // For "system" events, use V1 path (modality = nullptr)
            if (manager->v2_modalities.find(modality) == manager->v2_modalities.end()) {
                modality = "system";
            }
            by_modality[modality].push_back(event);
        }

        for (const auto& pair : by_modality) {
            const std::string& modality = pair.first;
            const auto& modality_events = pair.second;

            rac_telemetry_batch_request_t batch = {};
            batch.events = const_cast<rac_telemetry_payload_t*>(modality_events.data());
            batch.events_count = modality_events.size();
            batch.device_id = manager->device_id.c_str();
            batch.timestamp_ms = get_current_timestamp_ms();
            batch.modality = (modality == "system") ? nullptr : modality.c_str();

            char* json = nullptr;
            size_t json_len = 0;
            rac_result_t result =
                rac_telemetry_manager_batch_to_json(&batch, manager->environment, &json, &json_len);

            if (result == RAC_SUCCESS && json) {
                manager->http_callback(manager->http_user_data, endpoint, json, json_len,
                                       RAC_TRUE  // Production always requires auth
                );
                free(json);
            }
        }
    }

    // Free duplicated strings in events
    for (auto& event : events) {
        free((void*)event.id);
        free((void*)event.event_type);
        free((void*)event.modality);
        free((void*)event.device_id);
        free((void*)event.session_id);
        free((void*)event.model_id);
        free((void*)event.model_name);
        free((void*)event.framework);
        free((void*)event.device);
        free((void*)event.os_version);
        free((void*)event.platform);
        free((void*)event.sdk_version);
        free((void*)event.error_message);
        free((void*)event.error_code);
        free((void*)event.language);
        free((void*)event.voice);
        free((void*)event.archive_type);
    }

    return RAC_SUCCESS;
}

void rac_telemetry_manager_http_complete(rac_telemetry_manager_t* manager, rac_bool_t success,
                                         const char* /*response_json*/, const char* error_message) {
    if (!manager)
        return;

    if (success) {
        log_debug("Telemetry", "Telemetry HTTP request completed successfully");
    } else {
        log_warning("Telemetry", "Telemetry HTTP request failed: %s",
                    error_message ? error_message : "unknown");
    }

    // Could parse response and handle retries here if needed
}
