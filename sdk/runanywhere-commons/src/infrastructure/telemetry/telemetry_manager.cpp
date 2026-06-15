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
#include <random>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "component_types.pb.h"
#include "sdk_events.pb.h"
#endif

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

    // Batching configuration
    static constexpr size_t BATCH_SIZE_PRODUCTION = 10;  // Flush after 10 events in production
    static constexpr int64_t BATCH_TIMEOUT_MS = 5000;    // Flush after 5 seconds in production
    static constexpr size_t MAX_QUEUE_SIZE = 256;  // Cap while flushes defer (e.g. pre-auth)
    int64_t last_flush_time_ms = 0;                // Track last flush time for timeout
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

// Generate UUID using thread-safe RNG
std::string generate_uuid() {
    static thread_local std::mt19937 gen(std::random_device{}());
    static thread_local std::uniform_int_distribution<> dis(0, 15);

    static const char hex[] = "0123456789abcdef";
    std::string uuid = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";

    for (char& c : uuid) {
        if (c == 'x') {
            c = hex[dis(gen)];
        } else if (c == 'y') {
            c = hex[(dis(gen) % 4) + 8];  // 8, 9, a, or b
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

// Free the strings dup'd into a queued payload copy
void free_payload_strings(rac_telemetry_payload_t& event) {
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

#if defined(RAC_HAVE_PROTOBUF)

// Convert a proto InferenceFramework enum int to the same telemetry strings as
// framework_to_string (which keys on the distinct rac_inference_framework_t C
// enum). The two enums have different integer values, so this maps explicitly.
const char* framework_proto_to_string(int32_t framework) {
    switch (static_cast<runanywhere::v1::InferenceFramework>(framework)) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            return "onnx";
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return "sherpa";
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return "llamacpp";
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return "foundation_models";
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return "system_tts";
        case runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
            return "fluid_audio";
        case runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN:
            return "builtin";
        case runanywhere::v1::INFERENCE_FRAMEWORK_NONE:
            return "none";
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
            return "coreml";
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLX:
            return "mlx";
        case runanywhere::v1::INFERENCE_FRAMEWORK_GENIE:
            return "genie";
        default:
            return "unknown";
    }
}

// Component → modality string for the V2 telemetry table grouping. One string
// per backend V2 endpoint (POST /api/v2/sdk/telemetry/{modality}): llm, stt,
// tts, vlm, rag, imagegen, system, model. Model events override the component
// (any component can emit a model lifecycle event). Components without a
// dedicated endpoint (embeddings, vad, voice_agent, …) fall through to system.
const char* component_to_modality(runanywhere::v1::SDKComponent component, bool is_model_event) {
    if (is_model_event) {
        return "model";
    }
    switch (component) {
        case runanywhere::v1::SDK_COMPONENT_LLM:
            return "llm";
        case runanywhere::v1::SDK_COMPONENT_VLM:
            return "vlm";
        case runanywhere::v1::SDK_COMPONENT_STT:
            return "stt";
        case runanywhere::v1::SDK_COMPONENT_TTS:
            return "tts";
        case runanywhere::v1::SDK_COMPONENT_RAG:
            return "rag";
        case runanywhere::v1::SDK_COMPONENT_DIFFUSION:
            return "imagegen";
        case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS:
            return "embeddings";
        case runanywhere::v1::SDK_COMPONENT_VAD:
            return "vad";
        case runanywhere::v1::SDK_COMPONENT_VOICE_AGENT:
            return "voice";
        default:
            return "system";
    }
}

#endif  // RAC_HAVE_PROTOBUF

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
    // Start the batch timer at creation. Flushing the very first tracked event
    // immediately ("first flush to start timer") handed the batch to the SDK's
    // HTTP layer during Phase 1 — before HTTPClientAdapter.configure() — and
    // the fire-and-forget callback silently dropped it (sdk.init.started was
    // lost on every launch). First flush now waits for batch size / timeout /
    // a completion event / the Phase-2 flush kick, all of which run after the
    // HTTP layer is configured.
    manager->last_flush_time_ms = get_current_timestamp_ms();

    RAC_LOG_DEBUG("Telemetry", "Telemetry manager created for environment %d", env);

    return manager;
}

void rac_telemetry_manager_destroy(rac_telemetry_manager_t* manager) {
    if (!manager)
        return;

    // Flush any remaining events
    rac_telemetry_manager_flush(manager);

    // Anything still queued (e.g. flush deferred pre-auth) is freed, not sent
    {
        std::lock_guard<std::mutex> lock(manager->queue_mutex);
        if (!manager->queue.empty()) {
            RAC_LOG_WARNING("Telemetry", "Dropping %zu unsent telemetry event(s) on destroy",
                            manager->queue.size());
        }
        for (auto& event : manager->queue) {
            free_payload_strings(event);
        }
        manager->queue.clear();
    }

    delete manager;
    RAC_LOG_DEBUG("Telemetry", "Telemetry manager destroyed");
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
        if (manager->queue.size() >= rac_telemetry_manager::MAX_QUEUE_SIZE) {
            RAC_LOG_WARNING("Telemetry", "Queue full (%zu events), dropping oldest",
                            manager->queue.size());
            free_payload_strings(manager->queue.front());
            manager->queue.erase(manager->queue.begin());
        }
        manager->queue.push_back(copy);
    }

    // Use WARN level for production visibility (INFO is filtered in production)
    RAC_LOG_DEBUG("Telemetry", "Telemetry event queued: %s", payload->event_type);

    // Auto-flush logic
    if (!manager->http_callback) {
        RAC_LOG_DEBUG("Telemetry", "HTTP callback not set, skipping auto-flush");
        return RAC_SUCCESS;
    }

    bool should_flush = false;
    size_t queue_size = 0;
    int64_t current_time = get_current_timestamp_ms();

    {
        std::lock_guard<std::mutex> lock(manager->queue_mutex);
        queue_size = manager->queue.size();
    }

    if (manager->environment == RAC_ENV_DEVELOPMENT) {
        // Development: Immediate flush for real-time debugging
        should_flush = true;
        RAC_LOG_DEBUG("Telemetry", "Development mode: auto-flushing immediately (queue size: %zu)",
                      queue_size);
    } else {
        // Production: Flush based on batch size or timeout
        // (completion events trigger an immediate flush in rac_telemetry_manager_track_proto)
        // Flush if queue reaches batch size
        if (queue_size >= rac_telemetry_manager::BATCH_SIZE_PRODUCTION) {
            should_flush = true;
            RAC_LOG_DEBUG("Telemetry", "Auto-flushing: queue size (%zu) >= batch size (%zu)",
                          queue_size, rac_telemetry_manager::BATCH_SIZE_PRODUCTION);
        }
        // Flush if timeout reached (5 seconds since last flush)
        else if (manager->last_flush_time_ms > 0 && (current_time - manager->last_flush_time_ms) >=
                                                        rac_telemetry_manager::BATCH_TIMEOUT_MS) {
            should_flush = true;
            RAC_LOG_DEBUG("Telemetry", "Auto-flushing: timeout reached (%lld ms since last flush)",
                          current_time - manager->last_flush_time_ms);
        }
    }

    if (should_flush) {
        RAC_LOG_DEBUG("Telemetry", "Triggering auto-flush (queue size: %zu)", queue_size);
        rac_telemetry_manager_flush(manager);
        // Note: last_flush_time_ms is updated inside flush()
    }

    return RAC_SUCCESS;
}

#if defined(RAC_HAVE_PROTOBUF)

namespace {

using runanywhere::v1::SDKEvent;

// Derive the dotted event-type string + completion flag from the SDKEvent
// (oneof case + kind enum). Reproduces the legacy event_type_to_string table
// exactly for the events telemetry consumes. `out_is_completion` flags terminal
// generation/transcription/synthesis events that trigger an immediate flush.
std::string proto_event_type_string(const SDKEvent& ev, bool& out_is_completion) {
    out_is_completion = false;
    switch (ev.event_case()) {
        case SDKEvent::kGeneration: {
            // Generation events are emitted by both LLM and VLM (streamed VLM
            // rides the same GenerationEvent); prefix by component so a VLM
            // stream doesn't surface as "llm.generation.*" under modality vlm.
            const char* p =
                ev.component() == runanywhere::v1::SDK_COMPONENT_VLM ? "vlm" : "llm";
            switch (ev.generation().kind()) {
                case runanywhere::v1::GENERATION_EVENT_KIND_STARTED:
                    return std::string(p) + ".generation.started";
                case runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED:
                    return std::string(p) + ".generation.first_token";
                case runanywhere::v1::GENERATION_EVENT_KIND_STREAMING_UPDATE:
                    return std::string(p) + ".generation.streaming";
                case runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED:
                case runanywhere::v1::GENERATION_EVENT_KIND_STREAM_COMPLETED:
                    out_is_completion = true;
                    return std::string(p) + ".generation.completed";
                case runanywhere::v1::GENERATION_EVENT_KIND_FAILED:
                    out_is_completion = true;
                    return std::string(p) + ".generation.failed";
                case runanywhere::v1::GENERATION_EVENT_KIND_CANCELLED:
                    out_is_completion = true;
                    return std::string(p) + ".generation.cancelled";
                case runanywhere::v1::GENERATION_EVENT_KIND_CANCEL_REQUESTED:
                    return std::string(p) + ".generation.cancel_requested";
                case runanywhere::v1::GENERATION_EVENT_KIND_MODEL_UNLOADED:
                    return std::string(p) + ".model.unloaded";
                default:
                    return std::string(p) + ".generation";
            }
        }
        case SDKEvent::kModel: {
            const bool is_stt = ev.component() == runanywhere::v1::SDK_COMPONENT_STT;
            const bool is_tts = ev.component() == runanywhere::v1::SDK_COMPONENT_TTS;
            const char* dom = is_stt ? "stt.model" : (is_tts ? "tts.voice" : "llm.model");
            switch (ev.model().kind()) {
                case runanywhere::v1::MODEL_EVENT_KIND_LOAD_STARTED:
                    return std::string(dom) + ".load.started";
                case runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED:
                    return std::string(dom) + ".load.completed";
                case runanywhere::v1::MODEL_EVENT_KIND_LOAD_FAILED:
                    return std::string(dom) + ".load.failed";
                case runanywhere::v1::MODEL_EVENT_KIND_UNLOAD_COMPLETED:
                    return is_stt ? "stt.model.unloaded"
                                  : (is_tts ? "tts.voice.unloaded" : "llm.model.unloaded");
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_STARTED:
                    return "model.download.started";
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_PROGRESS:
                    return "model.download.progress";
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_COMPLETED:
                    return "model.download.completed";
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_FAILED:
                    return "model.download.failed";
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_CANCELLED:
                    return "model.download.cancelled";
                case runanywhere::v1::MODEL_EVENT_KIND_EXTRACTION_STARTED:
                    return "model.extraction.started";
                case runanywhere::v1::MODEL_EVENT_KIND_EXTRACTION_PROGRESS:
                    return "model.extraction.progress";
                case runanywhere::v1::MODEL_EVENT_KIND_EXTRACTION_COMPLETED:
                    return "model.extraction.completed";
                case runanywhere::v1::MODEL_EVENT_KIND_EXTRACTION_FAILED:
                    return "model.extraction.failed";
                case runanywhere::v1::MODEL_EVENT_KIND_DELETE_COMPLETED:
                    return "model.deleted";
                default:
                    return "model";
            }
        }
        case SDKEvent::kVoice: {
            switch (ev.voice().kind()) {
                case runanywhere::v1::VOICE_EVENT_KIND_TRANSCRIPTION_STARTED:
                    return "stt.transcription.started";
                case runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED:
                    out_is_completion = true;
                    return "stt.transcription.completed";
                case runanywhere::v1::VOICE_EVENT_KIND_STT_FAILED:
                    out_is_completion = true;
                    return "stt.transcription.failed";
                case runanywhere::v1::VOICE_EVENT_KIND_STT_PARTIAL_RESULT:
                    return "stt.transcription.partial";
                case runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_STARTED:
                    return "tts.synthesis.started";
                case runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED:
                    out_is_completion = true;
                    return "tts.synthesis.completed";
                case runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_FAILED:
                    out_is_completion = true;
                    return "tts.synthesis.failed";
                case runanywhere::v1::VOICE_EVENT_KIND_AUDIO_GENERATED:
                    return "tts.synthesis.chunk";
                case runanywhere::v1::VOICE_EVENT_KIND_VAD_STARTED:
                    return "vad.started";
                case runanywhere::v1::VOICE_EVENT_KIND_VAD_STOPPED:
                    return "vad.stopped";
                case runanywhere::v1::VOICE_EVENT_KIND_SPEECH_STARTED:
                    return "vad.speech.started";
                case runanywhere::v1::VOICE_EVENT_KIND_SPEECH_ENDED:
                    return "vad.speech.ended";
                case runanywhere::v1::VOICE_EVENT_KIND_VAD_PAUSED:
                    return "vad.paused";
                case runanywhere::v1::VOICE_EVENT_KIND_VAD_RESUMED:
                    return "vad.resumed";
                default:
                    return "voice";
            }
        }
        case SDKEvent::kInitialization: {
            switch (ev.initialization().stage()) {
                case runanywhere::v1::INITIALIZATION_STAGE_STARTED:
                    return "sdk.init.started";
                case runanywhere::v1::INITIALIZATION_STAGE_COMPLETED:
                    return "sdk.init.completed";
                case runanywhere::v1::INITIALIZATION_STAGE_FAILED:
                    return "sdk.init.failed";
                case runanywhere::v1::INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED:
                    return "sdk.models.loaded";
                default:
                    return "sdk.init";
            }
        }
        case SDKEvent::kStorage: {
            switch (ev.storage().kind()) {
                case runanywhere::v1::STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED:
                    return "storage.cache.cleared";
                case runanywhere::v1::STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED:
                    return "storage.cache.clear_failed";
                case runanywhere::v1::STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED:
                    return "storage.temp.cleaned";
                default:
                    return "storage";
            }
        }
        case SDKEvent::kDevice: {
            switch (ev.device().kind()) {
                case runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTERED:
                    return "device.registered";
                case runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED:
                    return "device.registration.failed";
                default:
                    return "device";
            }
        }
        case SDKEvent::kNetwork:
            return "network.connectivity.changed";
        case SDKEvent::kVoicePipeline: {
            if (ev.component() == runanywhere::v1::SDK_COMPONENT_VAD) {
                return "vad.process";
            }
            if (ev.voice_pipeline().payload_case() == runanywhere::v1::VoiceEvent::kMetrics) {
                out_is_completion = true;
                return "voice.turn.metrics";
            }
            return "voice.pipeline";
        }
        case SDKEvent::kCapability: {
            // VLM / RAG / diffusion (imagegen) capability operations. *_COMPLETED
            // and *_FAILED are terminal → flag for immediate flush.
            switch (ev.capability().kind()) {
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED:
                    return "vlm.process.started";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED:
                    out_is_completion = true;
                    return "vlm.process.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED:
                    out_is_completion = true;
                    return "vlm.process.failed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED:
                    return "imagegen.generate.started";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS:
                    return "imagegen.generate.progress";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED:
                    out_is_completion = true;
                    return "imagegen.generate.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED:
                    out_is_completion = true;
                    return "imagegen.generate.failed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED:
                    return "rag.ingestion.started";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED:
                    out_is_completion = true;
                    return "rag.ingestion.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED:
                    return "rag.query.started";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED:
                    out_is_completion = true;
                    return "rag.query.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED:
                    out_is_completion = true;
                    return "rag.query.failed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED:
                    return "embeddings.embed.started";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED:
                    out_is_completion = true;
                    return "embeddings.embed.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED:
                    out_is_completion = true;
                    return "embeddings.embed.failed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED:
                    out_is_completion = true;
                    return "lora.attach.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED:
                    out_is_completion = true;
                    return "lora.detach.completed";
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED:
                    out_is_completion = true;
                    return "lora.failed";
                default:
                    return "capability";
            }
        }
        case SDKEvent::kFailure:
            return "sdk.error";
        default:
            return "unknown";
    }
}

// Telemetry records lifecycle MILESTONES (started / completed / failed / summary),
// not high-frequency streaming ticks (per-token, per-partial, per-chunk, per-step,
// per-progress). Those still reach the public event stream + log via the
// destination bitmask — they are only excluded from the telemetry batch, so a
// single LLM stream produces one row per generation instead of one per token (and
// a download/diffusion run does not emit a row per progress callback).
bool telemetry_records(const SDKEvent& ev) {
    switch (ev.event_case()) {
        case SDKEvent::kGeneration:
            switch (ev.generation().kind()) {
                case runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED:
                case runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED:
                case runanywhere::v1::GENERATION_EVENT_KIND_STREAMING_UPDATE:
                case runanywhere::v1::GENERATION_EVENT_KIND_THINKING_DELTA:
                    return false;
                default:
                    return true;
            }
        case SDKEvent::kVoice:
            switch (ev.voice().kind()) {
                case runanywhere::v1::VOICE_EVENT_KIND_STT_PARTIAL_RESULT:
                case runanywhere::v1::VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL:
                case runanywhere::v1::VOICE_EVENT_KIND_STT_PROCESSING:
                case runanywhere::v1::VOICE_EVENT_KIND_AUDIO_GENERATED:
                    return false;
                default:
                    return true;
            }
        case SDKEvent::kCapability:
            return ev.capability().kind() !=
                   runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS;
        case SDKEvent::kVoicePipeline:
            // VAD is per-frame → record failures only (avoid flooding). Voice-agent
            // records only the per-turn MetricsEvent summary; all other pipeline
            // sub-events (tokens, state changes, audio frames) stay public/log only.
            if (ev.component() == runanywhere::v1::SDK_COMPONENT_VAD) {
                return ev.has_error() ||
                       ev.category() == runanywhere::v1::EVENT_CATEGORY_FAILURE;
            }
            return ev.voice_pipeline().payload_case() == runanywhere::v1::VoiceEvent::kMetrics;
        case SDKEvent::kModel:
            switch (ev.model().kind()) {
                case runanywhere::v1::MODEL_EVENT_KIND_LOAD_PROGRESS:
                case runanywhere::v1::MODEL_EVENT_KIND_DOWNLOAD_PROGRESS:
                case runanywhere::v1::MODEL_EVENT_KIND_EXTRACTION_PROGRESS:
                    return false;
                default:
                    return true;
            }
        default:
            return true;
    }
}

}  // namespace

rac_result_t rac_telemetry_manager_track_proto(rac_telemetry_manager_t* manager,
                                               const uint8_t* sdk_event_bytes, size_t len) {
    if (!manager) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    SDKEvent ev;
    if (sdk_event_bytes != nullptr && len > 0 &&
        !ev.ParseFromArray(sdk_event_bytes, static_cast<int>(len))) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Telemetry records milestones only — drop high-frequency streaming ticks
    // (per-token / per-partial / per-chunk / per-progress) so a stream does not
    // emit one telemetry row per token. They still reached the public + log sinks.
    if (!telemetry_records(ev)) {
        return RAC_SUCCESS;
    }

    rac_telemetry_payload_t payload = rac_telemetry_payload_default();

    std::string uuid = generate_uuid();
    payload.id = uuid.c_str();
    payload.timestamp_ms = get_current_timestamp_ms();
    payload.created_at_ms = payload.timestamp_ms;

    bool is_completion = false;
    std::string event_type = proto_event_type_string(ev, is_completion);
    payload.event_type = event_type.c_str();

    // Oneof arms the translator has no name for (component lifecycle state
    // transitions, cancellation envelopes, …) must not reach the backend as
    // literal "unknown" rows — they are public/log events, not analytics.
    if (event_type == "unknown") {
        return RAC_SUCCESS;
    }

    // Model artifact events (download/extraction/delete) group under the
    // shared "model" modality. Load/unload events are per-component — their
    // event_type already says stt.model.* / tts.voice.* / llm.model.* — so
    // route them to that component's modality instead of "model" (keeps the
    // dashboard's modality column consistent with the event name).
    bool is_model_event = false;
    if (ev.event_case() == SDKEvent::kModel) {
        switch (ev.model().kind()) {
            case runanywhere::v1::MODEL_EVENT_KIND_LOAD_STARTED:
            case runanywhere::v1::MODEL_EVENT_KIND_LOAD_PROGRESS:
            case runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED:
            case runanywhere::v1::MODEL_EVENT_KIND_LOAD_FAILED:
            case runanywhere::v1::MODEL_EVENT_KIND_UNLOAD_COMPLETED:
                is_model_event = ev.component() == runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
                break;
            default:
                is_model_event = true;
                break;
        }
    }
    payload.modality = component_to_modality(ev.component(), is_model_event);

    // Common: session id from the envelope.
    if (!ev.session_id().empty()) {
        payload.session_id = ev.session_id().c_str();
    }

    // Error → success=false + error_message. Read the envelope SDKError first,
    // falling back to the per-payload `error` string so failed events that only
    // populate the payload error field are still recorded as failures (parity
    // with the legacy union path, which carried error on the per-event struct).
    const std::string* payload_error = nullptr;
    switch (ev.event_case()) {
        case SDKEvent::kGeneration:
            payload_error = &ev.generation().error();
            break;
        case SDKEvent::kModel:
            payload_error = &ev.model().error();
            break;
        case SDKEvent::kVoice:
            payload_error = &ev.voice().error();
            break;
        case SDKEvent::kStorage:
            payload_error = &ev.storage().error();
            break;
        case SDKEvent::kCapability:
            payload_error = &ev.capability().error();
            break;
        default:
            break;
    }
    if (ev.has_error() && !ev.error().message().empty()) {
        payload.success = RAC_FALSE;
        payload.has_success = RAC_TRUE;
        payload.error_message = ev.error().message().c_str();
    } else if (payload_error != nullptr && !payload_error->empty()) {
        payload.success = RAC_FALSE;
        payload.has_success = RAC_TRUE;
        payload.error_message = payload_error->c_str();
    }

    // Strings referenced by the payload must outlive the track() copy below; keep
    // them in locals in this scope (track() deep-copies before returning).
    std::string framework_str;

    switch (ev.event_case()) {
        case SDKEvent::kGeneration: {
            const auto& g = ev.generation();
            if (!g.model_id().empty())
                payload.model_id = g.model_id().c_str();
            payload.model_name = !g.model_name().empty()
                                     ? g.model_name().c_str()
                                     : (!g.model_id().empty() ? g.model_id().c_str() : nullptr);
            payload.input_tokens = g.input_tokens();
            payload.output_tokens = g.tokens_used() != 0 ? g.tokens_used() : g.tokens_count();
            payload.total_tokens = payload.input_tokens + payload.output_tokens;
            const double dur =
                g.duration_ms() != 0.0 ? g.duration_ms() : static_cast<double>(g.latency_ms());
            payload.processing_time_ms = dur;
            payload.generation_time_ms = dur;
            payload.tokens_per_second = g.tokens_per_second();
            payload.time_to_first_token_ms = g.time_to_first_token_ms() != 0
                                                 ? static_cast<double>(g.time_to_first_token_ms())
                                                 : static_cast<double>(g.first_token_latency_ms());
            payload.is_streaming = g.is_streaming() ? RAC_TRUE : RAC_FALSE;
            payload.has_is_streaming = RAC_TRUE;
            framework_str = framework_proto_to_string(g.framework());
            payload.framework = framework_str.c_str();
            payload.temperature = g.temperature();
            payload.max_tokens = g.max_tokens();
            payload.context_length = g.context_length();
            if ((ev.generation().kind() == runanywhere::v1::GENERATION_EVENT_KIND_COMPLETED ||
                 ev.generation().kind() == runanywhere::v1::GENERATION_EVENT_KIND_STREAM_COMPLETED) &&
                !ev.has_error()) {
                payload.success = RAC_TRUE;
                payload.has_success = RAC_TRUE;
            }
            break;
        }
        case SDKEvent::kModel: {
            const auto& m = ev.model();
            if (!m.model_id().empty())
                payload.model_id = m.model_id().c_str();
            payload.model_name = !m.model_name().empty()
                                     ? m.model_name().c_str()
                                     : (!m.model_id().empty() ? m.model_id().c_str() : nullptr);
            payload.model_size_bytes = m.model_size_bytes();
            payload.processing_time_ms = static_cast<double>(m.duration_ms());
            framework_str = framework_proto_to_string(m.framework());
            payload.framework = framework_str.c_str();
            // ModelEvent.progress is 0..1; the backend model endpoint wants 0..100.
            // Only emit when present so non-progress events don't send progress=0.
            if (m.progress() > 0.0f) {
                payload.progress = static_cast<double>(m.progress()) * 100.0;
                payload.has_progress = RAC_TRUE;
            }
            if (m.kind() == runanywhere::v1::MODEL_EVENT_KIND_LOAD_COMPLETED && !ev.has_error()) {
                payload.success = RAC_TRUE;
                payload.has_success = RAC_TRUE;
            }
            break;
        }
        case SDKEvent::kVoice: {
            const auto& v = ev.voice();
            const bool is_tts = ev.component() == runanywhere::v1::SDK_COMPONENT_TTS;
            const bool is_stt = ev.component() == runanywhere::v1::SDK_COMPONENT_STT;
            if (is_stt) {
                if (!v.model_id().empty())
                    payload.model_id = v.model_id().c_str();
                payload.model_name = !v.model_name().empty()
                                         ? v.model_name().c_str()
                                         : (!v.model_id().empty() ? v.model_id().c_str() : nullptr);
                payload.processing_time_ms = static_cast<double>(v.duration_ms());
                payload.audio_duration_ms = static_cast<double>(v.audio_length_ms());
                payload.audio_size_bytes = v.audio_size_bytes();
                payload.word_count = v.word_count();
                payload.real_time_factor = v.real_time_factor();
                payload.confidence = v.confidence();
                if (!v.language().empty())
                    payload.language = v.language().c_str();
                payload.sample_rate = v.sample_rate();
                payload.is_streaming = v.is_streaming() ? RAC_TRUE : RAC_FALSE;
                payload.has_is_streaming = RAC_TRUE;
                framework_str = framework_proto_to_string(v.framework());
                payload.framework = framework_str.c_str();
                if (v.kind() == runanywhere::v1::VOICE_EVENT_KIND_STT_COMPLETED &&
                    !ev.has_error()) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
            } else if (is_tts) {
                if (!v.model_id().empty()) {
                    payload.model_id = v.model_id().c_str();
                    payload.voice = v.model_id().c_str();  // voice == model_id for TTS
                }
                payload.model_name = !v.model_name().empty()
                                         ? v.model_name().c_str()
                                         : (!v.model_id().empty() ? v.model_id().c_str() : nullptr);
                payload.character_count = v.character_count();
                payload.output_duration_ms = static_cast<double>(v.audio_duration_ms());
                payload.audio_size_bytes = v.audio_size_bytes_tts();
                payload.processing_time_ms = static_cast<double>(v.processing_duration_ms());
                payload.characters_per_second = v.characters_per_second();
                payload.sample_rate = v.sample_rate();
                framework_str = framework_proto_to_string(v.framework());
                payload.framework = framework_str.c_str();
                if (v.kind() == runanywhere::v1::VOICE_EVENT_KIND_SYNTHESIS_COMPLETED &&
                    !ev.has_error()) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
            } else {
                // VAD — telemetry reads only speech_duration_ms (= duration_ms(7)).
                payload.speech_duration_ms = static_cast<double>(v.duration_ms());
            }
            break;
        }
        case SDKEvent::kStorage: {
            payload.freed_bytes = ev.storage().freed_bytes();
            break;
        }
        case SDKEvent::kNetwork: {
            payload.is_online = ev.network().is_online() ? RAC_TRUE : RAC_FALSE;
            payload.has_is_online = RAC_TRUE;
            break;
        }
        case SDKEvent::kCapability: {
            // CapabilityOperationEvent is a flat analytics struct (kind, model_id,
            // operation, progress, input_count, output_count, error). The generic
            // counts carry different metrics per component:
            //   VLM  → input_count = image count, output_count = output tokens
            //   RAG  → output_count = retrieved docs count
            //   imagegen/diffusion → only progress (not a /imagegen schema field),
            //                        so it routes with base fields only.
            const auto& c = ev.capability();
            if (!c.model_id().empty()) {
                payload.model_id = c.model_id().c_str();
                // Dashboards render model_name; mirror the kGeneration/kModel
                // extractors' id-as-name fallback so capability rows aren't blank.
                payload.model_name = c.model_id().c_str();
            }
            // CapabilityOperationEvent has no duration field; completed
            // emitters carry it in the envelope properties map instead
            // (internal contract — avoids a proto change).
            {
                auto it = ev.properties().find("duration_ms");
                if (it != ev.properties().end()) {
                    const double dur = std::atof(it->second.c_str());
                    if (dur > 0.0) {
                        payload.processing_time_ms = dur;
                    }
                }
            }
            // LoRA capability events ride on SDK_COMPONENT_LLM, so component_to_modality
            // mapped them to "llm". Override to "lora" by capability kind. model_id
            // carries the base model; the operation is encoded in event_type.
            switch (c.kind()) {
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED:
                    payload.modality = "lora";
                    break;
                default:
                    break;
            }
            switch (ev.component()) {
                case runanywhere::v1::SDK_COMPONENT_VLM:
                    payload.image_count = static_cast<int32_t>(c.input_count());
                    payload.output_tokens = static_cast<int32_t>(c.output_count());
                    payload.total_tokens = payload.input_tokens + payload.output_tokens;
                    break;
                case runanywhere::v1::SDK_COMPONENT_RAG:
                    payload.retrieved_docs_count = static_cast<int32_t>(c.output_count());
                    break;
                case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS:
                    // input_count = texts embedded, output_count = vectors produced.
                    // embedding_model is read from model_id (set above) in the JSON.
                    payload.input_count = static_cast<int32_t>(c.input_count());
                    payload.vectors_produced = static_cast<int32_t>(c.output_count());
                    break;
                default:
                    break;
            }
            switch (c.kind()) {
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED:
                case runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED:
                    if (!ev.has_error()) {
                        payload.success = RAC_TRUE;
                        payload.has_success = RAC_TRUE;
                    }
                    break;
                default:
                    break;
            }
            break;
        }
        case SDKEvent::kVoicePipeline: {
            const auto& vp = ev.voice_pipeline();
            if (ev.component() == runanywhere::v1::SDK_COMPONENT_VAD) {
                if (vp.payload_case() == runanywhere::v1::VoiceEvent::kVad) {
                    payload.speech_duration_ms =
                        static_cast<double>(vp.vad().speech_duration_ms());
                    payload.silence_duration_ms =
                        static_cast<double>(vp.vad().silence_duration_ms());
                }
            } else if (vp.payload_case() == runanywhere::v1::VoiceEvent::kMetrics) {
                // Per-turn voice-agent pipeline summary.
                const auto& m = vp.metrics();
                payload.voice_stt_ms = m.stt_final_ms();
                payload.voice_llm_ms = m.llm_total_ms();
                payload.voice_tts_ms = m.tts_total_ms();
                payload.voice_total_ms = m.end_to_end_ms();
                payload.processing_time_ms = m.end_to_end_ms();
                if (!ev.has_error()) {
                    payload.success = RAC_TRUE;
                    payload.has_success = RAC_TRUE;
                }
            }
            break;
        }
        default:
            break;
    }

    // Uniform terminal-status rule: any terminal event that reached this point
    // without an error is a success; failures were already marked FALSE via the
    // error extraction above. Started/progress events stay unset (no outcome
    // yet) and cancellations stay unset (user action, neither success nor
    // failure). Per-arm extractors above may have set success already — this
    // only fills the gaps (sdk.init.completed, model.download.completed,
    // device.registered, storage events, …).
    if (payload.has_success == RAC_FALSE) {
        auto ends_with = [&event_type](const char* suffix) {
            const size_t n = strlen(suffix);
            return event_type.size() >= n &&
                   event_type.compare(event_type.size() - n, n, suffix) == 0;
        };
        if (ends_with(".failed")) {
            payload.success = RAC_FALSE;
            payload.has_success = RAC_TRUE;
        } else if (ends_with(".completed") || ends_with(".loaded") || ends_with(".deleted") ||
                   ends_with(".cleared") || ends_with(".cleaned") || ends_with(".registered") ||
                   ends_with(".stopped")) {
            payload.success = RAC_TRUE;
            payload.has_success = RAC_TRUE;
        }
    }

    rac_result_t result = rac_telemetry_manager_track(manager, &payload);

    if (result == RAC_SUCCESS && manager->environment != RAC_ENV_DEVELOPMENT && is_completion &&
        manager->http_callback) {
        RAC_LOG_DEBUG("Telemetry", "Completion event detected, triggering immediate flush");
        rac_telemetry_manager_flush(manager);
    }

    return result;
}

#else  // !RAC_HAVE_PROTOBUF

rac_result_t rac_telemetry_manager_track_proto(rac_telemetry_manager_t* manager,
                                               const uint8_t* /*sdk_event_bytes*/, size_t /*len*/) {
    return manager ? RAC_SUCCESS : RAC_ERROR_INVALID_ARGUMENT;
}

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// FLUSH
// =============================================================================

rac_result_t rac_telemetry_manager_flush(rac_telemetry_manager_t* manager) {
    if (!manager) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!manager->http_callback) {
        RAC_LOG_DEBUG("Telemetry", "No HTTP callback registered, cannot flush telemetry");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    // The V2 telemetry endpoints only accept a JWT; flushing before
    // authentication would 401 and silently drop the batch (the HTTP callback
    // is fire-and-forget). Keep events queued — rac_auth_handle_*_response
    // kicks a flush the moment a token lands.
    if (rac_env_requires_auth(manager->environment) && !rac_auth_is_authenticated()) {
        size_t queued = 0;
        {
            std::lock_guard<std::mutex> lock(manager->queue_mutex);
            queued = manager->queue.size();
        }
        if (queued > 0) {
            RAC_LOG_DEBUG("Telemetry", "Deferring flush of %zu events: not authenticated yet",
                          queued);
        }
        return RAC_SUCCESS;
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

    RAC_LOG_DEBUG("Telemetry", "Flushing %zu telemetry events", events.size());

    // Update last flush time
    manager->last_flush_time_ms = get_current_timestamp_ms();

    // Group events by modality and POST each group to its own V2 endpoint:
    // /api/v2/sdk/telemetry/{modality}. Modality is encoded in the path, not
    // the body (the backend batch schema is extra="forbid").
    std::map<std::string, std::vector<rac_telemetry_payload_t>> by_modality;
    for (const auto& event : events) {
        std::string modality = event.modality ? event.modality : "system";
        by_modality[modality].push_back(event);
    }

    // Modalities whose batch failed to serialize — their events are re-queued
    // below (retry on next flush) instead of being dropped.
    std::map<std::string, bool> failed_modalities;
    for (const auto& pair : by_modality) {
        const std::string& modality = pair.first;
        const auto& modality_events = pair.second;

        rac_telemetry_batch_request_t batch = {};
        batch.events = const_cast<rac_telemetry_payload_t*>(modality_events.data());
        batch.events_count = modality_events.size();
        batch.device_id = manager->device_id.c_str();
        batch.timestamp_ms = get_current_timestamp_ms();

        char* json = nullptr;
        size_t json_len = 0;
        rac_result_t result =
            rac_telemetry_manager_batch_to_json(&batch, manager->environment, &json, &json_len);
        if (result != RAC_SUCCESS || !json) {
            RAC_LOG_WARNING("Telemetry", "Re-queuing telemetry batch: JSON build failed (rc=%d, "
                            "modality=%s, %zu events)",
                            (int)result, modality.c_str(), modality_events.size());
            failed_modalities[modality] = true;
            continue;
        }

        const std::string endpoint = std::string(RAC_ENDPOINT_TELEMETRY_V2_PREFIX) + modality;
        RAC_LOG_DEBUG("Telemetry", "POST %s (%zu bytes): %.500s", endpoint.c_str(), json_len, json);
        manager->http_callback(manager->http_user_data, endpoint.c_str(), json, json_len, RAC_TRUE);
        free(json);
    }

    // Free events that were sent; re-queue events whose batch failed to
    // serialize so a transient failure retries on the next flush instead of
    // silently dropping them.
    if (failed_modalities.empty()) {
        for (auto& event : events) {
            free_payload_strings(event);
        }
    } else {
        std::lock_guard<std::mutex> lock(manager->queue_mutex);
        for (auto& event : events) {
            const std::string modality = event.modality ? event.modality : "system";
            if (failed_modalities.count(modality) > 0) {
                manager->queue.push_back(event);  // shallow copy keeps owned strings
            } else {
                free_payload_strings(event);
            }
        }
    }

    return RAC_SUCCESS;
}

void rac_telemetry_manager_http_complete(rac_telemetry_manager_t* manager, rac_bool_t success,
                                         const char* /*response_json*/, const char* error_message) {
    if (!manager)
        return;

    if (success == RAC_TRUE) {
        RAC_LOG_DEBUG("Telemetry", "Telemetry HTTP request completed successfully");
    } else {
        RAC_LOG_WARNING("Telemetry", "Telemetry HTTP request failed: %s",
                        error_message ? error_message : "unknown");
    }

    // Could parse response and handle retries here if needed
}
