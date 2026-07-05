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

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// CONFIGURATION - Mirrors Swift's LLMConfiguration

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

// OPTIONS - Mirrors Swift's LLMGenerationOptions

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

    /** Top-k sampling parameter (idl/llm_options.proto:55). 0 = disabled. */
    int32_t top_k;

    /** Repetition penalty (idl/llm_options.proto:59). 1.0 = no penalty. */
    float repetition_penalty;

    /** OpenAI-style frequency penalty (idl/llm_options.proto:100). 0.0 = disabled. */
    float frequency_penalty;

    /** OpenAI-style presence penalty (idl/llm_options.proto:101). 0.0 = disabled. */
    float presence_penalty;

    /** Minimum-probability sampling (idl/llm_options.proto:107). 0.0 = disabled. */
    float min_p;

    /** Deterministic sampling seed (idl/llm_options.proto:97). 0 = backend default. */
    int64_t seed;

    /** Grammar / constrained-decoding rule text, GBNF (can be NULL). */
    const char* grammar;

    /** Per-request backend thread hint (idl/llm_options.proto:119). 0 = backend default. */
    int32_t n_threads;

    /**
     * When RAC_TRUE, suppress the model's thinking phase for this generation
     * (idl/llm_options.proto disable_thinking). Commons prepends the model
     * no-think directive at the prompt level; RAC_FALSE = normal thinking.
     * Appended at the end of the struct so zero-initialized callers default to
     * RAC_FALSE (thinking enabled).
     */
    rac_bool_t disable_thinking;
} rac_llm_options_t;

/**
 * @brief Default LLM generation options
 *
 * The sampling fields below the legacy struct members default to the proto's
 * documented "unset / disabled" sentinels (idl/llm_options.proto): top_k=0,
 * repetition_penalty=1.0, frequency/presence/min_p=0.0, seed=0, no grammar,
 * n_threads=0. Engines apply each only when its non-disabled value is present.
 */
static const rac_llm_options_t RAC_LLM_OPTIONS_DEFAULT = {.max_tokens = 100,
                                                          .temperature = 0.8f,
                                                          .top_p = 1.0f,
                                                          .stop_sequences = RAC_NULL,
                                                          .num_stop_sequences = 0,
                                                          .streaming_enabled = RAC_FALSE,
                                                          .system_prompt = RAC_NULL,
                                                          .top_k = 0,
                                                          .repetition_penalty = 1.0f,
                                                          .frequency_penalty = 0.0f,
                                                          .presence_penalty = 0.0f,
                                                          .min_p = 0.0f,
                                                          .seed = 0,
                                                          .grammar = RAC_NULL,
                                                          .n_threads = 0,
                                                          .disable_thinking = RAC_FALSE};

// RESULT - Mirrors Swift's LLMGenerationResult

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
} rac_llm_result_t;

// INFO - Mirrors Swift's LLMService properties

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

// CALLBACKS

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

// THINKING TAG PATTERN - Mirrors Swift's ThinkingTagPattern

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

// STRUCTURED OUTPUT - Mirrors Swift's StructuredOutputConfig

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

// STREAMING RESULT - Mirrors Swift's LLMStreamingResult

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

// MEMORY MANAGEMENT

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
