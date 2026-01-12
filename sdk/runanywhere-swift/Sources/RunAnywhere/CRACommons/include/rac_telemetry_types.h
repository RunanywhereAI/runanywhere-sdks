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

#include "rac_types.h"
#include "rac_environment.h"

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

    // Event classification
    const char* modality;  // "llm", "stt", "tts", "model", "system"

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

    // VAD fields
    double speech_duration_ms;

    // SDK lifecycle fields
    int32_t count;

    // Storage fields
    int64_t freed_bytes;

    // Network fields
    rac_bool_t is_online;
    rac_bool_t has_is_online;
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
 * Supports both V1 and V2 storage paths:
 * - V1 (legacy): modality = NULL → stores in sdk_telemetry_events table
 * - V2 (normalized): modality = "llm"/"stt"/"tts"/"model" → normalized tables
 */
typedef struct rac_telemetry_batch_request {
    rac_telemetry_payload_t* events;
    size_t events_count;
    const char* device_id;
    int64_t timestamp_ms;
    const char* modality;  // NULL for V1, "llm"/"stt"/"tts"/"model" for V2
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
    const char* device_id;       // Persistent UUID from Keychain/secure storage
    const char* device_model;    // "iPhone 16 Pro Max", "Pixel 7", etc.
    const char* device_name;     // User-assigned device name
    const char* platform;        // "ios", "android"
    const char* os_version;      // "17.0", "14"
    const char* form_factor;     // "phone", "tablet", "laptop", etc.
    const char* architecture;    // "arm64", "x86_64", etc.
    const char* chip_name;       // "A18 Pro", "Snapdragon 888", etc.
    int64_t total_memory;        // Total RAM in bytes
    int64_t available_memory;    // Available RAM in bytes
    rac_bool_t has_neural_engine;  // true if device has Neural Engine / NPU
    int32_t neural_engine_cores;   // Number of Neural Engine cores (0 if none)
    const char* gpu_family;      // "apple", "adreno", etc.
    double battery_level;        // 0.0-1.0, negative if unavailable
    const char* battery_state;   // "charging", "full", "unplugged", NULL if unavailable
    rac_bool_t is_low_power_mode;  // Low power mode enabled
    int32_t core_count;          // Total CPU cores
    int32_t performance_cores;   // Performance (P) cores
    int32_t efficiency_cores;    // Efficiency (E) cores
    const char* device_fingerprint;  // Unique device fingerprint (may be same as device_id)

    // Legacy fields (for backward compatibility)
    const char* device_type;     // "smartphone", "tablet", etc. (deprecated - use form_factor)
    const char* os_name;         // "iOS", "Android" (deprecated - use platform)
    int64_t total_disk_bytes;
    int64_t available_disk_bytes;
    const char* processor_info;
    int32_t processor_count;     // Deprecated - use core_count
    rac_bool_t is_simulator;
    const char* locale;
    const char* timezone;
} rac_device_registration_info_t;

/**
 * @brief Device registration request
 */
typedef struct rac_device_registration_request {
    rac_device_registration_info_t device_info;
    const char* sdk_version;
    const char* build_token;  // For development mode
    int64_t last_seen_at_ms;
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
