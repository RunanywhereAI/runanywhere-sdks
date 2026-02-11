/**
 * @file rac_llm_types.h
 * @brief RunAnywhere Commons - LLM Types and Data Structures
 *
 * C port of Swift's LLM Models from:
 * Sources/RunAnywhere/Features/LLM/Models/LLMGenerationOptions.swift
 * Sources/RunAnywhere/Features/LLM/Models/LLMGenerationResult.swift
 *
 * This header defines data structures only. For the service interface,
 * see rac_llm_service.h.
 */

#ifndef RAC_LLM_TYPES_H
#define RAC_LLM_TYPES_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONFIGURATION - Mirrors Swift's LLMConfiguration
// =============================================================================

/**
 * @brief LLM component configuration
 *
 * Mirrors Swift's LLMConfiguration struct exactly.
 * See: Sources/RunAnywhere/Features/LLM/Models/LLMConfiguration.swift
 */
typedef struct rac_llm_config {
    /** Model ID (optional - uses default if NULL) */
    const char* model_id;

    /** Preferred framework for generation (use RAC_FRAMEWORK_UNKNOWN for auto) */
    int32_t preferred_framework;

    /** Context length - max tokens the model can handle (default: 2048) */
    int32_t context_length;

    /** Temperature for sampling (0.0 - 2.0, default: 0.7) */
    float temperature;

    /** Maximum tokens to generate (default: 100) */
    int32_t max_tokens;

    /** System prompt for generation (can be NULL) */
    const char* system_prompt;

    /** Enable streaming mode (default: true) */
    rac_bool_t streaming_enabled;
} rac_llm_config_t;

/**
 * @brief Default LLM configuration
 */
static const rac_llm_config_t RAC_LLM_CONFIG_DEFAULT = {.model_id = RAC_NULL,
                                                        .preferred_framework =
                                                            99,  // RAC_FRAMEWORK_UNKNOWN
                                                        .context_length = 2048,
                                                        .temperature = 0.7f,
                                                        .max_tokens = 100,
                                                        .system_prompt = RAC_NULL,
                                                        .streaming_enabled = RAC_TRUE};

// =============================================================================
// OPTIONS - Mirrors Swift's LLMGenerationOptions
// =============================================================================

/**
 * @brief LLM generation options
 *
 * Mirrors Swift's LLMGenerationOptions struct exactly.
 * See: Sources/RunAnywhere/Features/LLM/Models/LLMGenerationOptions.swift
 */
typedef struct rac_llm_options {
    /** Maximum number of tokens to generate (default: 100) */
    int32_t max_tokens;

    /** Temperature for sampling (0.0 - 2.0, default: 0.8) */
    float temperature;

    /** Top-p sampling parameter (default: 1.0) */
    float top_p;

    /** Stop sequences (null-terminated array, can be NULL) */
    const char* const* stop_sequences;
    size_t num_stop_sequences;

    /** Enable streaming mode (default: false) */
    rac_bool_t streaming_enabled;

    /** System prompt (can be NULL) */
    const char* system_prompt;

    /**
     * Confidence threshold for cloud handoff (0.0 - 1.0).
     * 0.0 = disabled (never recommend handoff).
     * Values > 0 enable entropy-based confidence scoring.
     * If on-device confidence drops below this threshold, the result
     * will have cloud_handoff=true recommending cloud fallback.
     * Default: 0.0 (disabled).
     */
    float confidence_threshold;
} rac_llm_options_t;

/**
 * @brief Default LLM generation options
 */
static const rac_llm_options_t RAC_LLM_OPTIONS_DEFAULT = {.max_tokens = 100,
                                                          .temperature = 0.8f,
                                                          .top_p = 1.0f,
                                                          .stop_sequences = RAC_NULL,
                                                          .num_stop_sequences = 0,
                                                          .streaming_enabled = RAC_FALSE,
                                                          .system_prompt = RAC_NULL,
                                                          .confidence_threshold = 0.0f};

// =============================================================================
// CLOUD HANDOFF TYPES - Confidence-based routing signals
// =============================================================================

/**
 * @brief Reason for cloud handoff recommendation
 *
 * Indicates why the on-device engine recommended routing to cloud.
 * Uses entropy-based confidence scoring.
 */
typedef enum rac_handoff_reason {
    /** No handoff needed - on-device inference was confident */
    RAC_HANDOFF_REASON_NONE = 0,

    /** First token had low confidence (early bail-out) */
    RAC_HANDOFF_REASON_FIRST_TOKEN_LOW_CONFIDENCE = 1,

    /** Rolling window of tokens showed degrading confidence (mid-generation bail-out) */
    RAC_HANDOFF_REASON_ROLLING_WINDOW_DEGRADATION = 2,
} rac_handoff_reason_t;

// =============================================================================
// RESULT - Mirrors Swift's LLMGenerationResult
// =============================================================================

/**
 * @brief LLM generation result
 */
typedef struct rac_llm_result {
    /** Generated text (owned, must be freed with rac_free) */
    char* text;

    /** Number of tokens in prompt */
    int32_t prompt_tokens;

    /** Number of tokens generated */
    int32_t completion_tokens;

    /** Total tokens (prompt + completion) */
    int32_t total_tokens;

    /** Time to first token in milliseconds */
    int64_t time_to_first_token_ms;

    /** Total generation time in milliseconds */
    int64_t total_time_ms;

    /** Tokens per second */
    float tokens_per_second;

    /** Model confidence score (0.0 - 1.0), based on token entropy */
    float confidence;

    /** Whether the engine recommends routing to cloud */
    rac_bool_t cloud_handoff;

    /** Reason for cloud handoff recommendation */
    rac_handoff_reason_t handoff_reason;
} rac_llm_result_t;

// =============================================================================
// INFO - Mirrors Swift's LLMService properties
// =============================================================================

/**
 * @brief LLM service handle info
 *
 * Mirrors Swift's LLMService properties.
 */
typedef struct rac_llm_info {
    /** Whether the service is ready for generation (isReady) */
    rac_bool_t is_ready;

    /** Current model identifier (currentModel, can be NULL) */
    const char* current_model;

    /** Context length (contextLength, 0 if unknown) */
    int32_t context_length;

    /** Whether streaming is supported (supportsStreaming) */
    rac_bool_t supports_streaming;
} rac_llm_info_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief LLM streaming callback
 *
 * Called for each generated token during streaming.
 * Mirrors Swift's onToken callback pattern.
 *
 * @param token The generated token string
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop generation
 */
typedef rac_bool_t (*rac_llm_stream_callback_fn)(const char* token, void* user_data);

// =============================================================================
// THINKING TAG PATTERN - Mirrors Swift's ThinkingTagPattern
// =============================================================================

/**
 * @brief Pattern for extracting thinking/reasoning content from model output
 *
 * Mirrors Swift's ThinkingTagPattern struct exactly.
 * See: Sources/RunAnywhere/Features/LLM/Models/ThinkingTagPattern.swift
 */
typedef struct rac_thinking_tag_pattern {
    /** Opening tag for thinking content (e.g., "<think>") */
    const char* opening_tag;

    /** Closing tag for thinking content (e.g., "</think>") */
    const char* closing_tag;
} rac_thinking_tag_pattern_t;

/**
 * @brief Default thinking tag pattern (DeepSeek/Hermes style)
 */
static const rac_thinking_tag_pattern_t RAC_THINKING_TAG_DEFAULT = {.opening_tag = "<think>",
                                                                    .closing_tag = "</think>"};

/**
 * @brief Alternative thinking pattern with full word
 */
static const rac_thinking_tag_pattern_t RAC_THINKING_TAG_FULL = {.opening_tag = "<thinking>",
                                                                 .closing_tag = "</thinking>"};

// =============================================================================
// STRUCTURED OUTPUT - Mirrors Swift's StructuredOutputConfig
// =============================================================================

/**
 * @brief Structured output configuration
 *
 * Mirrors Swift's StructuredOutputConfig struct.
 * See: Sources/RunAnywhere/Features/LLM/StructuredOutput/Generatable.swift
 *
 * Note: In C, we pass the JSON schema directly instead of using reflection.
 */
typedef struct rac_structured_output_config {
    /** JSON schema for the expected output structure */
    const char* json_schema;

    /** Whether to include the schema in the prompt */
    rac_bool_t include_schema_in_prompt;
} rac_structured_output_config_t;

/**
 * @brief Default structured output configuration
 */
static const rac_structured_output_config_t RAC_STRUCTURED_OUTPUT_DEFAULT = {
    .json_schema = RAC_NULL, .include_schema_in_prompt = RAC_TRUE};

/**
 * @brief Structured output validation result
 *
 * Mirrors Swift's StructuredOutputValidation struct.
 */
typedef struct rac_structured_output_validation {
    /** Whether the output is valid according to the schema */
    rac_bool_t is_valid;

    /** Error message if validation failed (can be NULL) */
    const char* error_message;

    /** Extracted JSON string (can be NULL) */
    char* extracted_json;
} rac_structured_output_validation_t;

// =============================================================================
// STREAMING RESULT - Mirrors Swift's LLMStreamingResult
// =============================================================================

/**
 * @brief Token event during streaming
 *
 * Provides detailed information about each token during streaming generation.
 */
typedef struct rac_llm_token_event {
    /** The generated token text */
    const char* token;

    /** Token index in the sequence */
    int32_t token_index;

    /** Is this the final token? */
    rac_bool_t is_final;

    /** Tokens generated per second so far */
    float tokens_per_second;
} rac_llm_token_event_t;

/**
 * @brief Extended streaming callback with token event details
 *
 * @param event Token event details
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop generation
 */
typedef rac_bool_t (*rac_llm_token_event_callback_fn)(const rac_llm_token_event_t* event,
                                                      void* user_data);

/**
 * @brief Cloud handoff callback for streaming generation
 *
 * Called when the on-device engine detects low confidence mid-stream
 * and recommends routing to cloud. The partial text generated so far
 * is provided so the cloud provider can continue from where on-device stopped.
 *
 * @param confidence Current confidence score (0.0 - 1.0)
 * @param reason The reason for handoff
 * @param partial_text Text generated so far before handoff (can be NULL)
 * @param user_data User-provided context
 */
typedef void (*rac_llm_handoff_callback_fn)(float confidence, rac_handoff_reason_t reason,
                                            const char* partial_text, void* user_data);

/**
 * @brief Streaming result handle
 *
 * Opaque handle for managing streaming generation.
 * In C++, this wraps the streaming state and provides synchronization.
 *
 * Note: LLMStreamingResult in Swift returns an AsyncThrowingStream and a Task.
 * In C, we use callbacks instead of async streams.
 */
typedef void* rac_llm_stream_handle_t;

/**
 * @brief Streaming generation parameters
 *
 * Configuration for starting a streaming generation.
 */
typedef struct rac_llm_stream_params {
    /** Prompt to generate from */
    const char* prompt;

    /** Generation options */
    rac_llm_options_t options;

    /** Callback for each token */
    rac_llm_stream_callback_fn on_token;

    /** Extended callback with token event details (optional, can be NULL) */
    rac_llm_token_event_callback_fn on_token_event;

    /** Callback when cloud handoff is recommended mid-stream (optional, can be NULL) */
    rac_llm_handoff_callback_fn on_handoff;

    /** User data passed to callbacks */
    void* user_data;

    /** Optional thinking tag pattern to extract thinking content */
    const rac_thinking_tag_pattern_t* thinking_pattern;
} rac_llm_stream_params_t;

/**
 * @brief Streaming generation metrics
 *
 * Metrics collected during streaming generation.
 */
typedef struct rac_llm_stream_metrics {
    /** Time to first token in milliseconds */
    int64_t time_to_first_token_ms;

    /** Total generation time in milliseconds */
    int64_t total_time_ms;

    /** Number of tokens generated */
    int32_t tokens_generated;

    /** Tokens per second */
    float tokens_per_second;

    /** Number of tokens in the prompt */
    int32_t prompt_tokens;

    /** Thinking tokens if thinking pattern was used */
    int32_t thinking_tokens;

    /** Response tokens (excluding thinking) */
    int32_t response_tokens;

    /** Model confidence score (0.0 - 1.0), based on token entropy */
    float confidence;

    /** Whether the engine recommends routing to cloud */
    rac_bool_t cloud_handoff;

    /** Reason for cloud handoff recommendation */
    rac_handoff_reason_t handoff_reason;
} rac_llm_stream_metrics_t;

/**
 * @brief Complete streaming result
 *
 * Final result after streaming generation is complete.
 */
typedef struct rac_llm_stream_result {
    /** Full generated text (owned, must be freed with rac_free) */
    char* text;

    /** Extracted thinking content if pattern was provided (can be NULL) */
    char* thinking_content;

    /** Generation metrics */
    rac_llm_stream_metrics_t metrics;

    /** Error code if generation failed (RAC_SUCCESS on success) */
    rac_result_t error_code;

    /** Error message if generation failed (can be NULL) */
    char* error_message;
} rac_llm_stream_result_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free LLM result resources
 *
 * @param result Result to free (can be NULL)
 */
RAC_API void rac_llm_result_free(rac_llm_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_TYPES_H */
