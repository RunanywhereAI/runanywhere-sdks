/**
 * @file rac_telemetry_types.h
 * @brief Telemetry data structures - canonical source of truth
 *
 * All telemetry payloads are defined here. Platform SDKs (Swift, Kotlin, Flutter)
 * use these types directly or create thin wrappers.
 *
 * Mirrors Swift's TelemetryEventPayload.swift structure.
 */

#ifndef RAC_TELEMETRY_TYPES_H
#define RAC_TELEMETRY_TYPES_H

#include "rac/core/rac_types.h"
#include "rac/infrastructure/network/rac_client_info.h"
#include "rac/infrastructure/network/rac_environment.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TELEMETRY EVENT PAYLOAD
// =============================================================================

/**
 * @brief Complete telemetry event payload
 *
 * Maps to backend SDKTelemetryEvent schema with all fields for:
 * - LLM events (tokens, generation times, etc.)
 * - STT events (audio duration, word count, etc.)
 * - TTS events (character count, audio size, etc.)
 * - VAD events (speech duration)
 * - Model lifecycle events (size, archive type)
 * - SDK lifecycle events (count)
 * - Storage events (freed bytes)
 * - Network events (online status)
 */
typedef struct rac_telemetry_payload {
    // Required fields
    const char* id;          // Unique event ID (UUID)
    const char* event_type;  // Event type string
    int64_t timestamp_ms;    // Unix timestamp in milliseconds
    int64_t created_at_ms;   // When payload was created

    // Event classification — one V2 backend endpoint per value:
    // "llm", "stt", "tts", "vlm", "rag", "imagegen", "system", "model".
    const char* modality;

    // Device identification
    const char* device_id;   // Persistent device UUID
    const char* session_id;  // Optional session ID

    // Model info
    const char* model_id;
    const char* model_name;
    const char* framework;  // "llamacpp", "onnx", "mlx", etc.

    // Device info
    const char* device;       // Device model (e.g., "iPhone15,2")
    const char* os_version;   // OS version (e.g., "17.0")
    const char* platform;     // "ios", "android", "flutter"
    const char* sdk_version;  // SDK version string

    // Common performance metrics
    double processing_time_ms;
    rac_bool_t has_processing_time_ms;  // Whether a duration was actually measured
                                        // (distinguishes a real 0 ms from "unset")
    rac_bool_t success;
    rac_bool_t has_success;  // Whether success field is set
    const char* error_message;
    const char* error_code;

    // LLM-specific fields
    int32_t input_tokens;
    int32_t output_tokens;
    int32_t total_tokens;
    double tokens_per_second;
    double time_to_first_token_ms;
    double prompt_eval_time_ms;
    double generation_time_ms;
    int32_t context_length;
    double temperature;
    int32_t max_tokens;

    // STT-specific fields
    double audio_duration_ms;
    double real_time_factor;
    int32_t word_count;
    double confidence;
    const char* language;
    rac_bool_t is_streaming;
    rac_bool_t has_is_streaming;
    int32_t segment_index;
    // Hybrid STT router attribution (populated only on the hybrid transcribe
    // path; null on plain single-backend STT).
    const char* routed_backend;   // backend/model that actually served the request
    rac_bool_t was_fallback;      // secondary served after the primary failed
    rac_bool_t has_was_fallback;  // whether was_fallback is meaningful
    int32_t attempt_count;        // 1 = primary only, 2 = primary then fallback

    // TTS-specific fields
    int32_t character_count;
    double characters_per_second;
    int32_t audio_size_bytes;
    int32_t sample_rate;
    const char* voice;
    double output_duration_ms;

    // Model lifecycle fields
    int64_t model_size_bytes;
    const char* archive_type;
    double progress;          // Download/extract progress 0..100 (model modality)
    rac_bool_t has_progress;  // Whether progress field is set

    // VLM-specific fields (VLM also carries the LLM token fields above)
    int32_t image_count;
    int32_t vision_tokens;         // image/vision tokens (via properties carrier)
    double vision_encode_time_ms;  // vision encode time (via properties carrier)
    const char* image_resolution;  // "WxH" (via properties carrier; string → dup'd/freed)

    // RAG-specific fields
    int32_t retrieved_docs_count;

    // Embeddings-specific fields (embedding_model is read from model_id;
    // total_tokens reuses the shared LLM token field above)
    int32_t input_count;          // texts embedded in the op
    int32_t vectors_produced;     // vectors returned
    int32_t embedding_dimension;  // vector dimension (via properties carrier)
    int32_t batch_size;           // texts submitted in the batch (via properties carrier)

    // RAG-specific extras (via properties carrier; retrieved_docs_count above)
    int32_t top_k;
    double retrieval_time_ms;
    int32_t query_token_count;     // estimated tokens in the query (via properties carrier)
    int32_t context_tokens;        // estimated tokens in the retrieved context (via carrier)
    const char* embedding_model;   // RAG embedding model (string → dup'd/freed)
    rac_bool_t reranker_used;      // LLM-pointwise rerank enabled for the query
    rac_bool_t has_reranker_used;  // whether reranker_used is set

    // LoRA-specific fields. Strings → must be dup'd/freed in track + payload_free.
    const char* adapter_id;
    const char* operation;       // attach/detach/failed (derived from capability kind)
    int64_t adapter_size_bytes;  // adapter file size in bytes (via properties carrier)

    // ImageGen / diffusion fields (all via properties carrier). Strings (scheduler,
    // output_format) → must be dup'd/freed in track + payload_free.
    int32_t imagegen_prompt_length;
    int32_t imagegen_negative_prompt_length;
    int32_t image_width;
    int32_t image_height;
    int32_t num_images;
    int32_t num_inference_steps;
    double guidance_scale;
    int64_t seed;
    int64_t output_size_bytes;
    const char* scheduler;
    const char* output_format;

    // Voice-agent per-turn pipeline fields (from MetricsEvent)
    double voice_stt_ms;
    double voice_llm_ms;
    double voice_tts_ms;
    double voice_total_ms;

    // VAD fields (silence_duration_ms + segment_count via properties carrier)
    double speech_duration_ms;
    double silence_duration_ms;
    int32_t segment_count;

    // Voice-agent per-turn fields (via properties carrier; voice_* timing above)
    int32_t transcript_chars;
    int32_t response_chars;
    int32_t turn_index;            // 0-based turn number within the agent session
    rac_bool_t has_turn_index;     // whether turn_index is set (0 is valid)
    rac_bool_t voice_interrupted;  // turn ended via caller cancel / barge-out
    rac_bool_t has_voice_interrupted;

    // SDK lifecycle fields
    int32_t count;

    // Storage fields
    int64_t freed_bytes;

    // Network fields
    rac_bool_t is_online;
    rac_bool_t has_is_online;

    // Live device state + SDK origin (stamped by the telemetry manager at
    // track time — callers never set these; see telemetry_manager.cpp)
    const char* sdk_binding;       // "swift", "kotlin", "flutter", "react-native", "web", "cli"
    double battery_level;          // 0.0-1.0 sampled at event time, negative if unavailable
    const char* battery_state;     // "charging", "full", "unplugged", NULL if unavailable
    rac_bool_t is_low_power_mode;  // Low power mode at event time
    rac_bool_t has_is_low_power_mode;
    int64_t total_memory;       // Total RAM in bytes, 0 if unknown
    int64_t available_memory;   // Available RAM in bytes at event time, 0 if unknown
    double cpu_usage_percent;   // 0-100 since previous event, negative if unavailable
    int32_t online_core_count;  // CPU cores online at event time, 0 if unknown
} rac_telemetry_payload_t;

/**
 * @brief Default/empty telemetry payload
 */
RAC_API rac_telemetry_payload_t rac_telemetry_payload_default(void);

/**
 * @brief Free any allocated strings in a telemetry payload
 */
RAC_API void rac_telemetry_payload_free(rac_telemetry_payload_t* payload);

// =============================================================================
// TELEMETRY BATCH REQUEST
// =============================================================================

/**
 * @brief Batch telemetry request for API
 *
 * One batch per modality. The modality is encoded in the endpoint path
 * (/api/v2/sdk/telemetry/{modality}), not in the body — the backend batch
 * schema is extra="forbid".
 */
typedef struct rac_telemetry_batch_request {
    rac_telemetry_payload_t* events;
    size_t events_count;
    const char* device_id;
    int64_t timestamp_ms;
    const char* modality;  // V2 modality segment: "llm"/"stt"/"tts"/"vlm"/etc.
} rac_telemetry_batch_request_t;

/**
 * @brief Batch telemetry response from API
 */
typedef struct rac_telemetry_batch_response {
    rac_bool_t success;
    int32_t events_received;
    int32_t events_stored;
    int32_t events_skipped;  // Duplicates skipped
    const char** errors;     // Array of error messages
    size_t errors_count;
    const char* storage_version;  // "V1" or "V2"
} rac_telemetry_batch_response_t;

/**
 * @brief Free batch response
 */
RAC_API void rac_telemetry_batch_response_free(rac_telemetry_batch_response_t* response);

// =============================================================================
// DEVICE REGISTRATION TYPES
// =============================================================================

/**
 * @brief Device information for registration (telemetry-specific)
 *
 * Platform-specific values are passed in from Swift/Kotlin.
 * Matches backend schemas/device.py DeviceInfo schema.
 * Note: Named differently from rac_device_info_t to avoid conflict.
 */
typedef struct rac_device_registration_info {
    // Required fields (backend schema)
    const char* device_id;           // Persistent UUID from Keychain/secure storage
    const char* device_model;        // "iPhone 16 Pro Max", "Pixel 7", etc.
    const char* device_name;         // User-assigned device name
    const char* platform;            // "ios", "android"
    const char* os_version;          // "17.0", "14"
    const char* form_factor;         // "phone", "tablet", "laptop", etc.
    const char* architecture;        // "arm64", "x86_64", etc.
    const char* chip_name;           // "A18 Pro", "Snapdragon 888", etc.
    int64_t total_memory;            // Total RAM in bytes
    int64_t available_memory;        // Available RAM in bytes
    rac_bool_t has_neural_engine;    // true if device has Neural Engine / NPU
    int32_t neural_engine_cores;     // Number of Neural Engine cores (0 if none)
    const char* gpu_family;          // "apple", "adreno", etc.
    double battery_level;            // 0.0-1.0, negative if unavailable
    const char* battery_state;       // "charging", "full", "unplugged", NULL if unavailable
    rac_bool_t is_low_power_mode;    // Low power mode enabled
    int32_t core_count;              // Total CPU cores
    int32_t performance_cores;       // Performance (P) cores
    int32_t efficiency_cores;        // Efficiency (E) cores
    const char* device_fingerprint;  // Unique device fingerprint (may be same as device_id)
} rac_device_registration_info_t;

/**
 * @brief Device registration request
 */
typedef struct rac_device_registration_request {
    rac_device_registration_info_t device_info;
    const char* sdk_version;
    const char* build_token;  // For development mode
    int64_t last_seen_at_ms;
    rac_client_info_t client_info;
} rac_device_registration_request_t;

/**
 * @brief Device registration response
 */
typedef struct rac_device_registration_response {
    const char* device_id;
    const char* status;       // "registered" or "updated"
    const char* sync_status;  // "synced" or "pending"
} rac_device_registration_response_t;

#ifdef __cplusplus
}
#endif

#endif  // RAC_TELEMETRY_TYPES_H
