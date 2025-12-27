# Core API Boundary Specification

## Overview

This document defines the concrete C API boundary that all platform SDKs (iOS, Android/KMP, Flutter, React Native) will use to interface with the shared RunAnywhere Core.

---

## Design Principles

1. **C ABI Stability**: All public APIs use `extern "C"` with stable C types
2. **Opaque Handles**: Internal state hidden behind `void*` handles
3. **Error Codes**: All functions return `ra_result_t` with detailed error codes
4. **Ownership Rules**: Clear memory ownership (caller-allocated, core-allocated, or shared)
5. **Thread Safety**: Core is thread-safe; wrappers may call from any thread
6. **Versioning**: API versioned independently of SDK versions

---

## Core Initialization API

### Initialization

```c
/**
 * Core API version
 */
#define RA_API_VERSION_MAJOR 1
#define RA_API_VERSION_MINOR 0
#define RA_API_VERSION_PATCH 0

/**
 * Get the core library version
 */
const char* ra_get_version(void);
uint32_t ra_get_api_version(void);  // Returns (MAJOR << 16) | (MINOR << 8) | PATCH

/**
 * SDK Environment
 */
typedef enum {
    RA_ENV_DEVELOPMENT = 0,
    RA_ENV_STAGING = 1,
    RA_ENV_PRODUCTION = 2
} ra_environment_t;

/**
 * Initialization configuration
 */
typedef struct {
    const char* api_key;          // May be NULL for development
    const char* base_url;         // API base URL (NULL for default)
    ra_environment_t environment;
    const char* device_id;        // Unique device identifier
    const char* app_id;           // Application bundle ID
    const char* app_version;      // Application version
    const char* sdk_version;      // SDK wrapper version
} ra_init_config_t;

/**
 * Platform adapter (wrapper implements these)
 */
typedef struct {
    // HTTP operations
    ra_result_t (*http_request)(const ra_http_request_t* req, ra_http_response_t* resp, void* ctx);
    ra_result_t (*http_download)(const char* url, const char* dest,
                                  ra_download_progress_callback_t progress, void* ctx);

    // File system
    ra_result_t (*file_exists)(const char* path, bool* exists, void* ctx);
    ra_result_t (*file_read)(const char* path, uint8_t** data, size_t* len, void* ctx);
    ra_result_t (*file_write)(const char* path, const uint8_t* data, size_t len, void* ctx);
    ra_result_t (*file_delete)(const char* path, void* ctx);
    ra_result_t (*file_size)(const char* path, size_t* size, void* ctx);
    ra_result_t (*dir_create)(const char* path, void* ctx);
    ra_result_t (*dir_list)(const char* path, char*** files, size_t* count, void* ctx);
    ra_result_t (*dir_delete)(const char* path, bool recursive, void* ctx);

    // Secure storage
    ra_result_t (*secure_get)(const char* key, char* value, size_t* len, void* ctx);
    ra_result_t (*secure_set)(const char* key, const char* value, void* ctx);
    ra_result_t (*secure_delete)(const char* key, void* ctx);

    // Logging
    void (*log)(ra_log_level_t level, const char* tag, const char* message, void* ctx);

    // Clock
    uint64_t (*now_ms)(void* ctx);

    // Memory info
    ra_result_t (*memory_info)(ra_memory_info_t* info, void* ctx);

    // Context pointer passed to all callbacks
    void* context;
} ra_platform_adapter_t;

/**
 * Initialize the core library
 * Must be called before any other API
 */
ra_result_t ra_initialize(const ra_init_config_t* config, const ra_platform_adapter_t* adapter);

/**
 * Shutdown the core library
 * Releases all resources
 */
ra_result_t ra_shutdown(void);

/**
 * Check if core is initialized
 */
bool ra_is_initialized(void);
```

---

## Configuration & Environment Model

### Configuration

```c
/**
 * Runtime configuration (can be changed after init)
 */
typedef struct {
    bool prefer_on_device;        // Default routing preference
    bool enable_telemetry;        // Send analytics events
    bool enable_cost_tracking;    // Track usage costs
    uint32_t max_memory_mb;       // Memory limit for models (0 = no limit)
    float privacy_threshold;      // 0.0-1.0, triggers on-device for high values
} ra_runtime_config_t;

ra_result_t ra_config_get(ra_runtime_config_t* config);
ra_result_t ra_config_set(const ra_runtime_config_t* config);
```

---

## Error Model

### Error Codes

```c
typedef int32_t ra_result_t;

// Success
#define RA_SUCCESS                      0

// Initialization errors (-1xx)
#define RA_ERROR_NOT_INITIALIZED       -100
#define RA_ERROR_ALREADY_INITIALIZED   -101
#define RA_ERROR_INVALID_API_KEY       -102
#define RA_ERROR_PLATFORM_ADAPTER      -103

// Parameter errors (-2xx)
#define RA_ERROR_INVALID_PARAM         -200
#define RA_ERROR_NULL_POINTER          -201
#define RA_ERROR_INVALID_HANDLE        -202
#define RA_ERROR_BUFFER_TOO_SMALL      -203

// Model errors (-3xx)
#define RA_ERROR_MODEL_NOT_FOUND       -300
#define RA_ERROR_MODEL_NOT_LOADED      -301
#define RA_ERROR_MODEL_LOAD_FAILED     -302
#define RA_ERROR_MODEL_ALREADY_LOADED  -303
#define RA_ERROR_MODEL_INCOMPATIBLE    -304

// Component errors (-4xx)
#define RA_ERROR_COMPONENT_NOT_READY   -400
#define RA_ERROR_COMPONENT_BUSY        -401
#define RA_ERROR_COMPONENT_FAILED      -402

// Network errors (-5xx)
#define RA_ERROR_NETWORK_UNAVAILABLE   -500
#define RA_ERROR_NETWORK_TIMEOUT       -501
#define RA_ERROR_NETWORK_FAILED        -502

// Memory errors (-6xx)
#define RA_ERROR_OUT_OF_MEMORY         -600
#define RA_ERROR_MEMORY_PRESSURE       -601

// File errors (-7xx)
#define RA_ERROR_FILE_NOT_FOUND        -700
#define RA_ERROR_FILE_READ_FAILED      -701
#define RA_ERROR_FILE_WRITE_FAILED     -702
#define RA_ERROR_CHECKSUM_MISMATCH     -703

// Cancellation
#define RA_ERROR_CANCELLED             -900

/**
 * Get human-readable error message
 */
const char* ra_error_message(ra_result_t code);

/**
 * Get last error details (thread-local)
 */
const char* ra_get_last_error_details(void);
```

---

## Event Model

### Event Types

```c
/**
 * Event categories
 */
typedef enum {
    RA_EVENT_INITIALIZATION = 1,
    RA_EVENT_CONFIGURATION = 2,
    RA_EVENT_GENERATION = 3,
    RA_EVENT_MODEL = 4,
    RA_EVENT_VOICE = 5,
    RA_EVENT_PERFORMANCE = 6,
    RA_EVENT_NETWORK = 7,
    RA_EVENT_STORAGE = 8,
    RA_EVENT_COMPONENT = 9,
    RA_EVENT_MEMORY = 10,
    RA_EVENT_ROUTING = 11
} ra_event_category_t;

/**
 * Event destination
 */
typedef enum {
    RA_EVENT_DEST_PUBLIC = 1,      // Visible to SDK consumers
    RA_EVENT_DEST_ANALYTICS = 2,   // Sent to telemetry backend
    RA_EVENT_DEST_BOTH = 3         // Both public and analytics
} ra_event_destination_t;

/**
 * Event structure
 */
typedef struct {
    ra_event_category_t category;
    const char* type;              // e.g., "generation.started", "model.loaded"
    const char* payload_json;      // JSON payload
    ra_event_destination_t destination;
    uint64_t timestamp_ms;
    const char* session_id;        // Optional correlation ID
} ra_event_t;

/**
 * Event callback
 */
typedef void (*ra_event_callback_t)(const ra_event_t* event, void* context);

/**
 * Subscribe to events
 */
ra_result_t ra_event_subscribe(ra_event_category_t category,
                                ra_event_callback_t callback, void* context,
                                uint32_t* subscription_id);

/**
 * Unsubscribe from events
 */
ra_result_t ra_event_unsubscribe(uint32_t subscription_id);

/**
 * Publish event (for internal use or wrapper-originated events)
 */
ra_result_t ra_event_publish(const ra_event_t* event);
```

---

## Request/Response Models for Capabilities

### LLM (Language Model)

```c
/**
 * LLM component handle
 */
typedef void* ra_llm_handle_t;

/**
 * LLM configuration
 */
typedef struct {
    const char* model_path;
    uint32_t context_length;       // Max tokens in context
    uint32_t gpu_layers;           // Layers to offload to GPU (0 = CPU only)
    bool use_mmap;                 // Memory-map model file
    uint32_t threads;              // CPU threads (0 = auto)
} ra_llm_config_t;

/**
 * Generation options
 */
typedef struct {
    uint32_t max_tokens;           // Max tokens to generate
    float temperature;             // 0.0-2.0
    float top_p;                   // 0.0-1.0
    uint32_t top_k;                // 0 = disabled
    float repeat_penalty;          // 1.0 = no penalty
    const char* stop_sequences;    // JSON array of stop strings
    const char* system_prompt;     // System prompt (may be NULL)
    bool stream;                   // Enable streaming
} ra_llm_options_t;

/**
 * Generation result
 */
typedef struct {
    char* text;                    // Generated text (caller must free)
    uint32_t prompt_tokens;        // Tokens in prompt
    uint32_t completion_tokens;    // Tokens generated
    float time_to_first_token_ms;  // TTFT
    float total_time_ms;           // Total generation time
    float tokens_per_second;       // Generation speed
    bool finished;                 // True if generation completed
    const char* finish_reason;     // "stop", "length", "cancelled"
} ra_llm_result_t;

/**
 * Streaming callback
 */
typedef void (*ra_llm_stream_callback_t)(const char* token, bool is_complete,
                                          const ra_llm_result_t* result, void* context);

/**
 * LLM component API
 */
ra_result_t ra_llm_create(ra_llm_handle_t* handle);
ra_result_t ra_llm_initialize(ra_llm_handle_t handle, const ra_llm_config_t* config);
ra_result_t ra_llm_generate(ra_llm_handle_t handle, const char* prompt,
                            const ra_llm_options_t* options, ra_llm_result_t* result);
ra_result_t ra_llm_generate_stream(ra_llm_handle_t handle, const char* prompt,
                                    const ra_llm_options_t* options,
                                    ra_llm_stream_callback_t callback, void* context);
ra_result_t ra_llm_cancel(ra_llm_handle_t handle);
ra_result_t ra_llm_cleanup(ra_llm_handle_t handle);
ra_result_t ra_llm_destroy(ra_llm_handle_t handle);

/**
 * Free result (caller must call after use)
 */
void ra_llm_result_free(ra_llm_result_t* result);
```

### STT (Speech-to-Text)

```c
/**
 * STT component handle
 */
typedef void* ra_stt_handle_t;

/**
 * STT configuration
 */
typedef struct {
    const char* model_path;
    const char* language;          // ISO 639-1 code (NULL = auto-detect)
    uint32_t sample_rate;          // Expected: 16000
    bool enable_timestamps;        // Word-level timestamps
    bool enable_punctuation;       // Auto-punctuation
} ra_stt_config_t;

/**
 * Transcription result
 */
typedef struct {
    char* text;                    // Transcribed text (caller must free)
    float confidence;              // 0.0-1.0
    const char* language;          // Detected language
    const char* segments_json;     // JSON array of word segments (if timestamps enabled)
    float processing_time_ms;
} ra_stt_result_t;

/**
 * Streaming callback
 */
typedef void (*ra_stt_stream_callback_t)(const char* partial_text, bool is_final,
                                          const ra_stt_result_t* result, void* context);

/**
 * STT component API
 */
ra_result_t ra_stt_create(ra_stt_handle_t* handle);
ra_result_t ra_stt_initialize(ra_stt_handle_t handle, const ra_stt_config_t* config);
ra_result_t ra_stt_transcribe(ra_stt_handle_t handle, const float* audio, size_t samples,
                               ra_stt_result_t* result);
ra_result_t ra_stt_stream_start(ra_stt_handle_t handle, ra_stt_stream_callback_t callback,
                                 void* context, ra_stream_handle_t* stream);
ra_result_t ra_stt_stream_feed(ra_stream_handle_t stream, const float* audio, size_t samples);
ra_result_t ra_stt_stream_end(ra_stream_handle_t stream, ra_stt_result_t* final_result);
ra_result_t ra_stt_cleanup(ra_stt_handle_t handle);
ra_result_t ra_stt_destroy(ra_stt_handle_t handle);

void ra_stt_result_free(ra_stt_result_t* result);
```

### TTS (Text-to-Speech)

```c
/**
 * TTS component handle
 */
typedef void* ra_tts_handle_t;

/**
 * TTS configuration
 */
typedef struct {
    const char* model_path;
    const char* voice_id;          // Voice identifier
    float speaking_rate;           // 0.5-2.0 (1.0 = normal)
    float pitch;                   // 0.5-2.0 (1.0 = normal)
    uint32_t sample_rate;          // Output sample rate (22050 typical)
} ra_tts_config_t;

/**
 * Synthesis result
 */
typedef struct {
    float* audio;                  // PCM float32 (caller must free)
    size_t sample_count;
    uint32_t sample_rate;
    float duration_ms;
    float processing_time_ms;
} ra_tts_result_t;

/**
 * Streaming callback
 */
typedef void (*ra_tts_stream_callback_t)(const float* audio, size_t samples,
                                          bool is_complete, void* context);

/**
 * TTS component API
 */
ra_result_t ra_tts_create(ra_tts_handle_t* handle);
ra_result_t ra_tts_initialize(ra_tts_handle_t handle, const ra_tts_config_t* config);
ra_result_t ra_tts_synthesize(ra_tts_handle_t handle, const char* text,
                               ra_tts_result_t* result);
ra_result_t ra_tts_synthesize_stream(ra_tts_handle_t handle, const char* text,
                                      ra_tts_stream_callback_t callback, void* context);
ra_result_t ra_tts_get_voices(ra_tts_handle_t handle, char** voices_json);
ra_result_t ra_tts_cancel(ra_tts_handle_t handle);
ra_result_t ra_tts_cleanup(ra_tts_handle_t handle);
ra_result_t ra_tts_destroy(ra_tts_handle_t handle);

void ra_tts_result_free(ra_tts_result_t* result);
```

### VAD (Voice Activity Detection)

```c
/**
 * VAD component handle
 */
typedef void* ra_vad_handle_t;

/**
 * VAD configuration
 */
typedef struct {
    float speech_threshold;        // Energy threshold for speech
    float silence_threshold;       // Energy threshold for silence
    uint32_t min_speech_frames;    // Minimum frames to confirm speech
    uint32_t min_silence_frames;   // Minimum frames to confirm silence
    uint32_t frame_size_samples;   // Samples per frame (160-320 typical)
} ra_vad_config_t;

/**
 * VAD result
 */
typedef struct {
    bool is_speech;
    float energy;                  // Current energy level
    float probability;             // Speech probability 0.0-1.0
    uint64_t speech_start_ms;      // When speech started (0 if not speaking)
    uint64_t speech_duration_ms;   // How long speech has lasted
} ra_vad_result_t;

/**
 * VAD component API
 */
ra_result_t ra_vad_create(ra_vad_handle_t* handle);
ra_result_t ra_vad_initialize(ra_vad_handle_t handle, const ra_vad_config_t* config);
ra_result_t ra_vad_process(ra_vad_handle_t handle, const float* audio, size_t samples,
                            ra_vad_result_t* result);
ra_result_t ra_vad_calibrate(ra_vad_handle_t handle, const float* ambient_audio,
                              size_t samples);
void ra_vad_notify_tts_start(ra_vad_handle_t handle);
void ra_vad_notify_tts_end(ra_vad_handle_t handle);
ra_result_t ra_vad_reset(ra_vad_handle_t handle);
ra_result_t ra_vad_destroy(ra_vad_handle_t handle);
```

---

## Streaming Strategy

### Problem: Per-Token FFI Crossings

Streaming generation calls back per token, which is expensive across FFI.

### Solution: Batched Streaming

```c
/**
 * Streaming configuration
 */
typedef struct {
    uint32_t batch_size;           // Tokens to accumulate (10-50)
    uint32_t max_delay_ms;         // Max time before forced callback (50-100)
} ra_stream_config_t;

/**
 * Batched stream callback
 * tokens: Array of token strings
 * count: Number of tokens in batch
 */
typedef void (*ra_llm_batch_callback_t)(const char** tokens, size_t count,
                                         bool is_complete,
                                         const ra_llm_result_t* result, void* context);

/**
 * Configure streaming behavior
 */
ra_result_t ra_stream_configure(const ra_stream_config_t* config);

/**
 * Batched streaming generation
 */
ra_result_t ra_llm_generate_stream_batched(ra_llm_handle_t handle, const char* prompt,
                                            const ra_llm_options_t* options,
                                            ra_llm_batch_callback_t callback, void* context);
```

### Alternative: Pull Model

```c
/**
 * Poll-based streaming (wrapper pulls when ready)
 */
typedef void* ra_generation_stream_t;

ra_result_t ra_llm_stream_start(ra_llm_handle_t handle, const char* prompt,
                                 const ra_llm_options_t* options,
                                 ra_generation_stream_t* stream);

/**
 * Poll for available tokens
 * Returns RA_SUCCESS if tokens available, RA_ERROR_BUFFER_TOO_SMALL if none
 */
ra_result_t ra_llm_stream_poll(ra_generation_stream_t stream,
                                char* buffer, size_t buffer_size, size_t* tokens_read);

/**
 * Check if generation is complete
 */
ra_result_t ra_llm_stream_is_complete(ra_generation_stream_t stream, bool* complete);

/**
 * Get final result and close stream
 */
ra_result_t ra_llm_stream_finish(ra_generation_stream_t stream, ra_llm_result_t* result);
```

---

## Threading Rules & Ownership

### Threading Rules

1. **Core is thread-safe**: All functions can be called from any thread
2. **Callbacks on core threads**: Callbacks may be invoked on internal threads; wrappers must dispatch to main thread if needed
3. **Handle thread affinity**: Handles should be used from the creating thread or with external synchronization
4. **No blocking in callbacks**: Callbacks must return quickly; defer work to wrapper threads

### Ownership Rules

```c
/**
 * OWNERSHIP CONVENTIONS:
 *
 * 1. Caller-allocated, Core-filled:
 *    - Config structs (ra_llm_config_t, ra_stt_config_t, etc.)
 *    - Result structs (ra_llm_result_t, ra_stt_result_t, etc.)
 *    - Caller allocates, passes pointer, core fills
 *    - Caller must call ra_*_result_free() when done
 *
 * 2. Core-allocated, Caller-frees:
 *    - char* text fields in results
 *    - float* audio fields in results
 *    - Caller must free using ra_free() or result_free()
 *
 * 3. Borrowed (valid during callback only):
 *    - const char* tokens in stream callbacks
 *    - const float* audio in stream callbacks
 *    - Do not store; copy if needed
 *
 * 4. Handles:
 *    - Created by core, owned by caller
 *    - Caller must call ra_*_destroy() when done
 */

/**
 * Free core-allocated memory
 */
void ra_free(void* ptr);

/**
 * Duplicate string (for borrowed strings in callbacks)
 */
char* ra_strdup(const char* str);
```

---

## Versioning Strategy

### ABI Versioning

```c
/**
 * ABI version check
 */
#define RA_ABI_VERSION 1

/**
 * Check ABI compatibility
 * Returns RA_SUCCESS if compatible, RA_ERROR_* if not
 */
ra_result_t ra_check_abi_version(uint32_t expected_version);

/**
 * Struct versioning pattern
 */
typedef struct {
    uint32_t struct_size;          // sizeof(this_struct)
    // ... fields ...
} ra_versioned_config_t;

// Usage:
// ra_versioned_config_t config = {0};
// config.struct_size = sizeof(config);
// Core checks struct_size to determine version
```

### Backward Compatibility

1. **New fields added at end** of structs
2. **New error codes** in reserved ranges
3. **New functions** don't replace old ones
4. **Deprecated functions** marked with `RA_DEPRECATED`

```c
#define RA_DEPRECATED __attribute__((deprecated))

// Old function (still works)
RA_DEPRECATED ra_result_t ra_llm_load_model(const char* path);

// New function with more options
ra_result_t ra_llm_load_model_ex(const ra_llm_config_t* config);
```

---

## Summary

This API boundary specification provides:

1. **Stable C ABI** for all platform bindings
2. **Clear ownership rules** for memory management
3. **Event system** for async communication
4. **Streaming strategies** to minimize FFI overhead
5. **Versioning strategy** for backward compatibility

Wrappers (iOS/KMP/Flutter/RN) implement `ra_platform_adapter_t` and call the C API. Core handles all business logic, state machines, and orchestration.

---

*Document generated: December 2025*
