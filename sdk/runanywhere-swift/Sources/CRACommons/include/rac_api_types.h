/**
 * @file rac_api_types.h
 * @brief API request and response data types
 *
 * Defines all data structures for API communication.
 * This is the canonical source of truth - platform SDKs create thin wrappers.
 */

#ifndef RAC_API_TYPES_H
#define RAC_API_TYPES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Authentication Types
// =============================================================================

/**
 * @brief Authentication request payload
 * Sent to POST /api/v1/auth/sdk/authenticate
 */
typedef struct {
    const char* api_key;
    const char* device_id;
    const char* platform;  // "ios", "android", etc.
    const char* sdk_version;
} rac_auth_request_t;

/**
 * @brief Authentication response payload
 * Received from authentication and refresh endpoints
 */
typedef struct {
    char* access_token;
    char* refresh_token;
    char* device_id;
    char* user_id;  // Can be NULL (org-level auth)
    char* organization_id;
    char* token_type;    // Usually "bearer"
    int32_t expires_in;  // Seconds until expiry
} rac_auth_response_t;

/**
 * @brief Refresh token request payload
 * Sent to POST /api/v1/auth/sdk/refresh
 */
typedef struct {
    const char* device_id;
    const char* refresh_token;
} rac_refresh_request_t;

// =============================================================================
// Health Check Types
// =============================================================================

/**
 * @brief Health status enum
 */
typedef enum {
    RAC_HEALTH_HEALTHY = 0,
    RAC_HEALTH_DEGRADED = 1,
    RAC_HEALTH_UNHEALTHY = 2
} rac_health_status_t;

/**
 * @brief Health check response
 * Received from GET /v1/health
 */
typedef struct {
    rac_health_status_t status;
    char* version;
    int64_t timestamp;  // Unix timestamp
} rac_health_response_t;

// =============================================================================
// Device Registration Types
// =============================================================================

/**
 * @brief Device hardware information
 */
typedef struct {
    const char* device_fingerprint;
    const char* device_model;  // e.g., "iPhone15,2"
    const char* os_version;    // e.g., "17.0"
    const char* platform;      // "ios", "android", etc.
    const char* architecture;  // "arm64", "x86_64", etc.
    int64_t total_memory;      // Bytes
    int32_t cpu_cores;
    bool has_neural_engine;
    bool has_gpu;
} rac_device_info_t;

/**
 * @brief Device registration request
 * Sent to POST /api/v1/devices/register
 */
typedef struct {
    rac_device_info_t device_info;
    const char* sdk_version;
    const char* build_token;
    int64_t last_seen_at;  // Unix timestamp
} rac_device_reg_request_t;

/**
 * @brief Device registration response
 */
typedef struct {
    char* device_id;
    char* status;       // "registered" or "updated"
    char* sync_status;  // "synced" or "pending"
} rac_device_reg_response_t;

// =============================================================================
// Telemetry Types
// =============================================================================

/**
 * @brief Telemetry event payload
 * Contains all possible fields for LLM, STT, TTS, VAD events
 */
typedef struct {
    // Required fields
    const char* id;
    const char* event_type;
    int64_t timestamp;   // Unix timestamp ms
    int64_t created_at;  // Unix timestamp ms

    // Event classification
    const char* modality;  // "llm", "stt", "tts", "model", "system"

    // Device identification
    const char* device_id;
    const char* session_id;

    // Model info
    const char* model_id;
    const char* model_name;
    const char* framework;

    // Device info
    const char* device;
    const char* os_version;
    const char* platform;
    const char* sdk_version;

    // Common metrics
    double processing_time_ms;
    bool success;
    bool has_success;  // Whether success field is set
    const char* error_message;
    const char* error_code;

    // LLM-specific
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

    // STT-specific
    double audio_duration_ms;
    double real_time_factor;
    int32_t word_count;
    double confidence;
    const char* language;
    bool is_streaming;
    int32_t segment_index;

    // TTS-specific
    int32_t character_count;
    double characters_per_second;
    int32_t audio_size_bytes;
    int32_t sample_rate;
    const char* voice;
    double output_duration_ms;

    // Model lifecycle
    int64_t model_size_bytes;
    const char* archive_type;

    // VAD-specific
    double speech_duration_ms;

    // SDK lifecycle
    int32_t count;

    // Storage
    int64_t freed_bytes;

    // Network
    bool is_online;
    bool has_is_online;
} rac_telemetry_event_t;

/**
 * @brief Telemetry batch request
 * Sent to POST /api/v1/sdk/telemetry
 */
typedef struct {
    rac_telemetry_event_t* events;
    size_t event_count;
    const char* device_id;
    int64_t timestamp;
    const char* modality;  // Can be NULL for V1 path
} rac_telemetry_batch_t;

/**
 * @brief Telemetry batch response
 */
typedef struct {
    bool success;
    int32_t events_received;
    int32_t events_stored;
    int32_t events_skipped;
    char** errors;
    size_t error_count;
    char* storage_version;  // "V1" or "V2"
} rac_telemetry_response_t;

// =============================================================================
// API Error Types
// =============================================================================

/**
 * @brief API error information
 */
typedef struct {
    int32_t status_code;
    char* message;
    char* code;
    char* raw_body;
    char* request_url;
} rac_api_error_t;

// =============================================================================
// Memory Management
// =============================================================================

/**
 * @brief Free authentication response
 */
void rac_auth_response_free(rac_auth_response_t* response);

/**
 * @brief Free health response
 */
void rac_health_response_free(rac_health_response_t* response);

/**
 * @brief Free device registration response
 */
void rac_device_reg_response_free(rac_device_reg_response_t* response);

/**
 * @brief Free telemetry response
 */
void rac_telemetry_response_free(rac_telemetry_response_t* response);

/**
 * @brief Free API error
 */
void rac_api_error_free(rac_api_error_t* error);

// =============================================================================
// JSON Serialization
// =============================================================================

/**
 * @brief Serialize auth request to JSON
 * @param request The request to serialize
 * @return JSON string (caller must free), or NULL on error
 */
char* rac_auth_request_to_json(const rac_auth_request_t* request);

/**
 * @brief Parse auth response from JSON
 * @param json The JSON string
 * @param out_response Output response (caller must free with rac_auth_response_free)
 * @return 0 on success, -1 on error
 */
int rac_auth_response_from_json(const char* json, rac_auth_response_t* out_response);

/**
 * @brief Serialize refresh request to JSON
 */
char* rac_refresh_request_to_json(const rac_refresh_request_t* request);

/**
 * @brief Serialize device registration request to JSON
 */
char* rac_device_reg_request_to_json(const rac_device_reg_request_t* request);

/**
 * @brief Parse device registration response from JSON
 */
int rac_device_reg_response_from_json(const char* json, rac_device_reg_response_t* out_response);

/**
 * @brief Serialize telemetry event to JSON
 */
char* rac_telemetry_event_to_json(const rac_telemetry_event_t* event);

/**
 * @brief Serialize telemetry batch to JSON
 */
char* rac_telemetry_batch_to_json(const rac_telemetry_batch_t* batch);

/**
 * @brief Parse telemetry response from JSON
 */
int rac_telemetry_response_from_json(const char* json, rac_telemetry_response_t* out_response);

/**
 * @brief Parse API error from HTTP response
 */
int rac_api_error_from_response(int status_code, const char* body, const char* url,
                                rac_api_error_t* out_error);

#ifdef __cplusplus
}
#endif

#endif  // RAC_API_TYPES_H
