/**
 * @file rac_voice_agent.h
 * @brief Voice Agent Capability - Full Voice Conversation Pipeline
 *
 * C port of Swift's VoiceAgentCapability.swift
 * Swift Source: Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 *
 * Composes STT, LLM, TTS, and VAD capabilities for end-to-end voice processing.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md):
 *   - Proto-byte APIs at the bottom of this header
 *     (rac_voice_agent_initialize_proto,
 *     rac_voice_agent_component_states_proto,
 *     rac_voice_agent_process_voice_turn_proto) and
 *     rac_voice_agent_set_proto_callback in rac_voice_event_abi.h are
 *     the `SDK-facing default`. They emit/consume serialized
 *     runanywhere.v1.VoiceAgentComposeConfig / VoiceAgentComponentStates /
 *     VoiceAgentResult / VoiceEvent bytes.
 *   - The per-component rac_voice_agent_*_config_t structs feed
 *     rac_voice_agent_initialize and the proto compose path
 *     (config_from_proto). rac_voice_agent_generate_response is the one
 *     remaining non-proto verb (LLM-only text in/out), retained for the
 *     Flutter SDK's `RunAnywhere.voice.generateResponse`.
 *   - Audio pipeline state-manager helpers
 *     (rac_audio_pipeline_state_t, rac_audio_pipeline_config_t,
 *     rac_audio_pipeline_*) are `internal` voice-agent feedback
 *     prevention plumbing.
 */

#ifndef RAC_VOICE_AGENT_H
#define RAC_VOICE_AGENT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/wakeword/rac_wakeword_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Voice Agent Timing Defaults
// =============================================================================

/** Default timeout for waiting for speech input (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_SPEECH_TIMEOUT_SEC 10.0

/** Default maximum recording duration (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_MAX_RECORDING_DURATION_SEC 30.0

/** Default pause duration to end recording (seconds) */
#define RAC_VOICE_AGENT_DEFAULT_END_OF_SPEECH_PAUSE_SEC 1.5

/** Maximum time to wait for LLM response (seconds) */
#define RAC_VOICE_AGENT_LLM_RESPONSE_TIMEOUT_SEC 30.0

/** Maximum time to wait for TTS synthesis (seconds) */
#define RAC_VOICE_AGENT_TTS_RESPONSE_TIMEOUT_SEC 15.0

// =============================================================================
// TYPES - Mirrors Swift's VoiceAgentConfiguration and VoiceAgentResult
// =============================================================================

/**
 * @brief Audio pipeline state - Mirrors Swift's AudioPipelineState enum
 *
 * Represents the current state of the audio pipeline to prevent feedback loops.
 * See: Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
typedef enum rac_audio_pipeline_state {
    RAC_AUDIO_PIPELINE_IDLE = 0,                /**< System is idle, ready to start listening */
    RAC_AUDIO_PIPELINE_WAITING_WAKEWORD = 7,    /**< Waiting for wake word activation */
    RAC_AUDIO_PIPELINE_LISTENING = 1,           /**< Actively listening for speech via VAD */
    RAC_AUDIO_PIPELINE_PROCESSING_SPEECH = 2,   /**< Processing detected speech with STT */
    RAC_AUDIO_PIPELINE_GENERATING_RESPONSE = 3, /**< Generating response with LLM */
    RAC_AUDIO_PIPELINE_PLAYING_TTS = 4,         /**< Playing TTS output */
    RAC_AUDIO_PIPELINE_COOLDOWN = 5, /**< Cooldown period after TTS to prevent feedback */
    RAC_AUDIO_PIPELINE_ERROR = 6     /**< Error state requiring reset */
} rac_audio_pipeline_state_t;

/**
 * @brief Get string representation of audio pipeline state
 *
 * @param state The pipeline state
 * @return State name string (static, do not free)
 */
RAC_API const char* rac_audio_pipeline_state_name(rac_audio_pipeline_state_t state);

/**
 * @brief VAD configuration for voice agent.
 * Mirrors Swift's VADConfiguration.
 */
typedef struct rac_voice_agent_vad_config {
    /** Sample rate (default: 16000) */
    int32_t sample_rate;

    /** Frame length in seconds (default: 0.1) */
    float frame_length;

    /** Energy threshold (default: 0.005) */
    float energy_threshold;
} rac_voice_agent_vad_config_t;

/**
 * @brief Default VAD configuration.
 */
static const rac_voice_agent_vad_config_t RAC_VOICE_AGENT_VAD_CONFIG_DEFAULT = {
    .sample_rate = 16000, .frame_length = 0.1f, .energy_threshold = 0.005f};

/**
 * @brief STT configuration for voice agent.
 * Mirrors Swift's STTConfiguration.
 */
typedef struct rac_voice_agent_stt_config {
    /** Model path - file path used for loading (can be NULL to use already-loaded model) */
    const char* model_path;
    /** Model ID - identifier for telemetry (e.g., "whisper-base") */
    const char* model_id;
    /** Model name - human-readable name (e.g., "Whisper Base") */
    const char* model_name;
} rac_voice_agent_stt_config_t;

/**
 * @brief LLM configuration for voice agent.
 * Mirrors Swift's LLMConfiguration.
 */
typedef struct rac_voice_agent_llm_config {
    /** Model path - file path used for loading (can be NULL to use already-loaded model) */
    const char* model_path;
    /** Model ID - identifier for telemetry (e.g., "llama-3.2-1b") */
    const char* model_id;
    /** Model name - human-readable name (e.g., "Llama 3.2 1B Instruct") */
    const char* model_name;
} rac_voice_agent_llm_config_t;

/**
 * @brief TTS configuration for voice agent.
 * Mirrors Swift's TTSConfiguration.
 */
typedef struct rac_voice_agent_tts_config {
    /** Voice path - file path used for loading (can be NULL/empty to use already-loaded voice) */
    const char* voice_path;
    /** Voice ID - identifier for telemetry (e.g., "vits-piper-en_GB-alba-medium") */
    const char* voice_id;
    /** Voice name - human-readable name (e.g., "Piper TTS (British English)") */
    const char* voice_name;
} rac_voice_agent_tts_config_t;

/**
 * @brief Wake word configuration for voice agent.
 */
typedef struct rac_voice_agent_wakeword_config {
    /** Whether wake word detection is enabled */
    rac_bool_t enabled;

    /** Wake word model path (ONNX format, e.g., "hey_jarvis.onnx") */
    const char* model_path;

    /** Wake word model ID for telemetry */
    const char* model_id;

    /** Human-readable wake word phrase (e.g., "Hey Jarvis") */
    const char* wake_word;

    /** Detection threshold (0.0 - 1.0, default: 0.5) */
    float threshold;

    /** Path to embedding model (required for openWakeWord) */
    const char* embedding_model_path;

    /** Path to Silero VAD model for pre-filtering (optional) */
    const char* vad_model_path;
} rac_voice_agent_wakeword_config_t;

/**
 * @brief Default wake word configuration.
 */
static const rac_voice_agent_wakeword_config_t RAC_VOICE_AGENT_WAKEWORD_CONFIG_DEFAULT = {
    .enabled = RAC_FALSE,
    .model_path = RAC_NULL,
    .model_id = RAC_NULL,
    .wake_word = RAC_NULL,
    .threshold = 0.5f,
    .embedding_model_path = RAC_NULL,
    .vad_model_path = RAC_NULL};

/**
 * @brief Voice agent configuration.
 * Mirrors Swift's VoiceAgentConfiguration.
 */
typedef struct rac_voice_agent_config {
    /** VAD configuration */
    rac_voice_agent_vad_config_t vad_config;

    /** STT configuration */
    rac_voice_agent_stt_config_t stt_config;

    /** LLM configuration */
    rac_voice_agent_llm_config_t llm_config;

    /** TTS configuration */
    rac_voice_agent_tts_config_t tts_config;

    /** Wake word configuration */
    rac_voice_agent_wakeword_config_t wakeword_config;
} rac_voice_agent_config_t;

/**
 * @brief Default voice agent configuration.
 */
static const rac_voice_agent_config_t RAC_VOICE_AGENT_CONFIG_DEFAULT = {
    .vad_config = {.sample_rate = 16000, .frame_length = 0.1f, .energy_threshold = 0.005f},
    .stt_config = {.model_path = RAC_NULL, .model_id = RAC_NULL, .model_name = RAC_NULL},
    .llm_config = {.model_path = RAC_NULL, .model_id = RAC_NULL, .model_name = RAC_NULL},
    .tts_config = {.voice_path = RAC_NULL, .voice_id = RAC_NULL, .voice_name = RAC_NULL},
    .wakeword_config = {.enabled = RAC_FALSE,
                        .model_path = RAC_NULL,
                        .model_id = RAC_NULL,
                        .wake_word = RAC_NULL,
                        .threshold = 0.5f,
                        .embedding_model_path = RAC_NULL,
                        .vad_model_path = RAC_NULL}};

// =============================================================================
// AUDIO PIPELINE STATE MANAGER CONFIG - Mirrors Swift's AudioPipelineStateManager.Configuration
// =============================================================================

/**
 * @brief Audio pipeline state manager configuration
 *
 * Mirrors Swift's AudioPipelineStateManager.Configuration struct.
 * See: Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
typedef struct rac_audio_pipeline_config {
    /** Duration to wait after TTS before allowing microphone (seconds) */
    float cooldown_duration;

    /** Whether to enforce strict state transitions */
    rac_bool_t strict_transitions;

    /** Maximum TTS duration before forced timeout (seconds) */
    float max_tts_duration;
} rac_audio_pipeline_config_t;

/**
 * @brief Default audio pipeline configuration
 */
static const rac_audio_pipeline_config_t RAC_AUDIO_PIPELINE_CONFIG_DEFAULT = {
    .cooldown_duration = 0.8f, /* 800ms - better feedback prevention */
    .strict_transitions = RAC_TRUE,
    .max_tts_duration = 30.0f};

// =============================================================================
// AUDIO PIPELINE STATE MANAGER API
// =============================================================================

/**
 * @brief Check if microphone can be activated in current state
 *
 * @param current_state Current pipeline state
 * @param last_tts_end_time_ms Last TTS end time in milliseconds since epoch (0 if none)
 * @param cooldown_duration_ms Cooldown duration in milliseconds
 * @return RAC_TRUE if microphone can be activated
 */
RAC_API rac_bool_t rac_audio_pipeline_can_activate_microphone(
    rac_audio_pipeline_state_t current_state, int64_t last_tts_end_time_ms,
    int64_t cooldown_duration_ms);

/**
 * @brief Check if TTS can be played in current state
 *
 * @param current_state Current pipeline state
 * @return RAC_TRUE if TTS can be played
 */
RAC_API rac_bool_t rac_audio_pipeline_can_play_tts(rac_audio_pipeline_state_t current_state);

/**
 * @brief Check if a state transition is valid
 *
 * @param from_state Current state
 * @param to_state Target state
 * @return RAC_TRUE if transition is valid
 */
RAC_API rac_bool_t rac_audio_pipeline_is_valid_transition(rac_audio_pipeline_state_t from_state,
                                                          rac_audio_pipeline_state_t to_state);

// =============================================================================
// OPAQUE HANDLE
// =============================================================================

/**
 * @brief Opaque handle for voice agent instance.
 */
typedef struct rac_voice_agent* rac_voice_agent_handle_t;

// =============================================================================
// LIFECYCLE API
// =============================================================================

/**
 * @brief Create a standalone voice agent that owns its component handles.
 *
 * This is the recommended API. The voice agent creates and manages its own
 * STT, LLM, TTS, and VAD component handles internally. Use the model loading
 * APIs to load models after creation.
 *
 * @param out_handle Output: Handle to the created voice agent
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_create_standalone(rac_voice_agent_handle_t* out_handle);

/**
 * @brief Destroy a voice agent instance.
 *
 * Also destroys the component handles owned by the voice agent.
 *
 * @param handle Voice agent handle
 */
RAC_API void rac_voice_agent_destroy(rac_voice_agent_handle_t handle);

// =============================================================================
// INITIALIZATION & READINESS
// =============================================================================

/**
 * @brief Initialize the voice agent with configuration.
 *
 * Mirrors Swift's VoiceAgentCapability.initialize(_:).
 * This method is smart about reusing already-loaded models.
 *
 * @param handle Voice agent handle
 * @param config Configuration (can be NULL for defaults)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_initialize(rac_voice_agent_handle_t handle,
                                                const rac_voice_agent_config_t* config);

/**
 * @brief Initialize using already-loaded models.
 *
 * Mirrors Swift's VoiceAgentCapability.initializeWithLoadedModels().
 * Verifies all required components are loaded and marks the voice agent as ready.
 *
 * @param handle Voice agent handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle);

/**
 * @brief Cleanup voice agent resources.
 *
 * Mirrors Swift's VoiceAgentCapability.cleanup().
 *
 * @param handle Voice agent handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle);

/**
 * @brief Check if voice agent is ready.
 *
 * Mirrors Swift's VoiceAgentCapability.isReady property.
 *
 * @param handle Voice agent handle
 * @param out_is_ready Output: RAC_TRUE if ready
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle,
                                              rac_bool_t* out_is_ready);

// =============================================================================
// LLM TEXT VERB
// =============================================================================

/**
 * @brief Generate an LLM response from a text prompt (no STT/TTS).
 *
 * The one remaining non-proto voice-agent verb — retained for the Flutter
 * SDK's `RunAnywhere.voice.generateResponse`. Runs against the agent's
 * composed LLM handle.
 *
 * @param handle Voice agent handle
 * @param prompt Input prompt
 * @param out_response Output: Generated response (owned, must be freed with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_voice_agent_generate_response(rac_voice_agent_handle_t handle,
                                                       const char* prompt, char** out_response);

// =============================================================================
// GENERATED-PROTO C ABI
// =============================================================================

/**
 * @section voice_agent_audio_ingress Audio-Ingress Contract
 *
 * The voice-agent C ABI is a pure-CPU library and owns NO microphone access.
 * All audio must be captured by the platform SDK (iOS AVAudioEngine, Android
 * AudioRecord, Web getUserMedia, Flutter platform channels, RN audio plugin)
 * and pushed into the C core through one of the entry points below. There is
 * no implicit "C++ pulls audio" path — anything that depends on a microphone
 * MUST be wired by the SDK frontend.
 *
 * Supported ingress modes today (proto-byte path):
 *
 *   1. Per-utterance turn:
 *        rac_voice_agent_process_voice_turn_proto(handle, pcm, n, &result)
 *      or, with streamed VoiceEvent fan-out,
 *        rac_voice_agent_process_turn_proto(handle, request_bytes, n,
 *                                           event_callback, user_data).
 *      The SDK feeds ONE complete, VAD-trimmed audio buffer per turn. The
 *      C++ pipeline runs STT -> LLM -> TTS over that buffer and emits a
 *      single TURN_COMPLETED VoiceEvent. SDKs that drive their voice screen
 *      through these APIs MUST call them once per detected utterance — the
 *      C core will not transcribe anything until the SDK pushes a buffer.
 *
 *   2. Streaming raw-frame ingress (in-core segmentation):
 *        rac_voice_agent_feed_audio_proto(handle, pcm, n, sample_rate,
 *                                         channels, encoding, is_final,
 *                                         &result).
 *      The SDK pushes raw mic frames continuously (16 kHz mono PCM16); the
 *      C core performs energy-based utterance segmentation internally and,
 *      once an utterance closes, runs the same VAD -> STT -> LLM -> TTS
 *      pipeline as the per-turn path, fanning out VoiceEvents through the
 *      registered proto callback and returning the synthesized reply inline
 *      via `out_result`. This is the recommended ingress: the SDK driver
 *      reduces to "capture -> feed -> play" with no SDK-side VAD.
 *
 *   3. Continuous per-modality streaming (no voice-agent aggregation):
 *        rac_stt_stream_feed_audio_proto(session, audio_bytes, n) and
 *        rac_vad_stream_feed_audio_proto(session, audio_bytes, n).
 *      SDKs that prefer per-frame VAD/STT events bypass the voice-agent
 *      turn ABI and drive the STT/VAD streams directly, then call
 *      rac_voice_agent_transcribe_proto / synthesize_speech_proto /
 *      generate-LLM helpers for the remaining stages.
 *
 * Frontend authors: if a voice-screen view-model only calls
 * rac_voice_agent_set_proto_callback without ever pushing audio, expect
 * dead-air. Either feed raw frames (mode 2), drive the per-turn API per
 * utterance (mode 1), or attach a parallel STT/VAD stream session (mode 3).
 */

/**
 * @brief Initialize from serialized runanywhere.v1.VoiceAgentComposeConfig bytes.
 */
RAC_API rac_result_t rac_voice_agent_initialize_proto(rac_voice_agent_handle_t handle,
                                                      const uint8_t* config_proto_bytes,
                                                      size_t config_proto_size,
                                                      rac_proto_buffer_t* out_component_states);

/**
 * @brief Snapshot component state as serialized runanywhere.v1.VoiceAgentComponentStates bytes.
 */
RAC_API rac_result_t rac_voice_agent_component_states_proto(
    rac_voice_agent_handle_t handle, rac_proto_buffer_t* out_component_states);

/**
 * @brief Process one voice turn and return serialized runanywhere.v1.VoiceAgentResult bytes.
 *
 * Per-utterance entry point — see the @ref voice_agent_audio_ingress section
 * above. SDKs MUST call this once per detected utterance with a complete
 * (typically VAD-trimmed) PCM buffer. The C core does not capture or buffer
 * mic audio on its own; without an explicit call the pipeline is dead-air.
 */
RAC_API rac_result_t rac_voice_agent_process_voice_turn_proto(rac_voice_agent_handle_t handle,
                                                              const void* audio_data,
                                                              size_t audio_size,
                                                              rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

// Full-session voice-agent ABI + per-helper proto wrappers.
#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rac_voice_agent_turn_event_callback_fn)(const uint8_t* event_bytes,
                                                       size_t event_size, void* user_data);

/**
 * @brief Drive one voice turn and stream VoiceEvent fan-out via @p event_callback.
 *
 * Per-utterance entry point — see the @ref voice_agent_audio_ingress section
 * (above the GENERATED-PROTO C ABI block). The SDK serializes a
 * `runanywhere.v1.VoiceAgentTurnRequest` containing the complete PCM buffer
 * for one detected utterance; the C core runs VAD/STT/LLM/TTS over it and
 * emits VoiceEvents through @p event_callback. The C core does NOT capture
 * microphone audio — frontends that wire up
 * rac_voice_agent_set_proto_callback without ever calling this API (or
 * driving a parallel rac_stt_stream_feed_audio_proto session) will see
 * dead-air on the voice screen.
 */
RAC_API rac_result_t rac_voice_agent_process_turn_proto(
    rac_voice_agent_handle_t handle, const uint8_t* request_bytes, size_t request_size,
    rac_voice_agent_turn_event_callback_fn event_callback, void* user_data);

/**
 * @brief Cancel one request-scoped voice turn.
 *
 * @p request_bytes contains a serialized `VoiceAgentTurnRequest`; only its
 * non-empty `request_id` is consumed. Cancellation is cooperative: an active
 * LLM/TTS backend receives its native interrupt immediately, while a
 * non-interruptible STT call is allowed to return and the pipeline exits at
 * the next stage boundary. A cancel that arrives just before the turn starts
 * remains keyed to that request id and cannot affect a later turn.
 */
RAC_API rac_result_t rac_voice_agent_cancel_turn_proto(rac_voice_agent_handle_t handle,
                                                       const uint8_t* request_bytes,
                                                       size_t request_size);

/**
 * @brief Streaming raw-frame audio ingress with in-core segmentation.
 *
 * Ingress mode 2 (see the @ref voice_agent_audio_ingress section). The SDK
 * pushes raw mic frames as they are captured — 16 kHz mono signed-16-bit
 * little-endian PCM (UNSPECIFIED encoding is treated as PCM_S16_LE). The C
 * core accumulates them, performs energy-based utterance endpointing, and on
 * each completed utterance runs the full VAD -> STT -> LLM -> TTS turn
 * pipeline, emitting the same VoiceEvents as
 * `rac_voice_agent_process_turn_proto` through the proto callback registered
 * via `rac_voice_agent_set_proto_callback`.
 *
 * When a turn completes during a call, @p out_result is filled with a
 * serialized `runanywhere.v1.VoiceAgentResult` carrying the transcript,
 * assistant response, and synthesized reply as WAV bytes (for inline
 * playback). When no utterance closes this call, @p out_result is an empty
 * success buffer. Pass @p is_final = RAC_TRUE to flush any in-progress
 * utterance (e.g. when the session is stopping).
 *
 * The call may block for the duration of a turn when an utterance closes; do
 * not call it from a real-time audio callback — feed from a dedicated
 * consumer loop. @p out_result must be released with rac_proto_buffer_free().
 *
 * @param handle        Voice agent handle.
 * @param audio_data    Raw PCM frame bytes (may be NULL only when size == 0).
 * @param audio_size    Size of @p audio_data in bytes.
 * @param sample_rate_hz Sample rate hint (16000 expected).
 * @param channels      Channel count hint (1 expected).
 * @param encoding      AudioEncoding value (0/UNSPECIFIED or PCM_S16_LE).
 * @param is_final      RAC_TRUE to flush the in-progress utterance.
 * @param out_result    Output: serialized VoiceAgentResult (owned).
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_voice_agent_feed_audio_proto(rac_voice_agent_handle_t handle,
                                                      const void* audio_data, size_t audio_size,
                                                      int32_t sample_rate_hz, int32_t channels,
                                                      int32_t encoding, rac_bool_t is_final,
                                                      rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_voice_agent_transcribe_proto(rac_voice_agent_handle_t handle,
                                                      const uint8_t* request_bytes,
                                                      size_t request_size,
                                                      rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_voice_agent_synthesize_speech_proto(rac_voice_agent_handle_t handle,
                                                             const uint8_t* request_bytes,
                                                             size_t request_size,
                                                             rac_proto_buffer_t* out_result);

RAC_API rac_result_t rac_voice_agent_component_create_proto(const uint8_t* config_bytes,
                                                            size_t config_size,
                                                            rac_voice_agent_handle_t* out_handle);

RAC_API rac_result_t rac_voice_agent_component_destroy_proto(rac_voice_agent_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VOICE_AGENT_H */
