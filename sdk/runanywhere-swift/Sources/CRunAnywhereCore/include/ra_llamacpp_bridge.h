#ifndef RA_LLAMACPP_BRIDGE_H
#define RA_LLAMACPP_BRIDGE_H

/**
 * RunAnywhere Unified Bridge API
 *
 * This is the main C API that all platforms (iOS, Android, Flutter) use to
 * interact with ML backends. It provides a capability-based interface where
 * backends (ONNX, LlamaCpp, CoreML, etc.) can implement any subset of capabilities.
 *
 * Supported Capabilities:
 * - TEXT_GENERATION: LLM text generation
 * - EMBEDDINGS: Text/image embeddings
 * - STT: Speech-to-text (ASR)
 * - TTS: Text-to-speech
 * - VAD: Voice activity detection
 * - DIARIZATION: Speaker diarization
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// COMMON TYPES
// =============================================================================

// Include types from the canonical source
#include "ra_types.h"

// =============================================================================
// HANDLE TYPES
// =============================================================================

// Opaque handle to a backend instance
typedef void* ra_backend_handle;

// Opaque handle to a streaming session (STT, VAD, etc.)
typedef void* ra_stream_handle;

// =============================================================================
// CAPABILITY TYPES
// =============================================================================

typedef enum {
    RA_CAP_TEXT_GENERATION = 0,
    RA_CAP_EMBEDDINGS = 1,
    RA_CAP_STT = 2,
    RA_CAP_TTS = 3,
    RA_CAP_VAD = 4,
    RA_CAP_DIARIZATION = 5
} ra_capability_type;

// =============================================================================
// CALLBACKS
// =============================================================================

// Text generation streaming callback
// Returns: true to continue, false to cancel
typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);

// STT streaming callback
// is_final: true when result is final, false for partial
// Returns: true to continue, false to cancel
typedef bool (*ra_stt_stream_callback)(const char* text, bool is_final, void* user_data);

// TTS streaming callback
// samples: float32 audio samples
// num_samples: number of samples in this chunk
// is_final: true when synthesis is complete
// Returns: true to continue, false to cancel
typedef bool (*ra_tts_stream_callback)(const float* samples, size_t num_samples, bool is_final, void* user_data);

// VAD streaming callback
typedef void (*ra_vad_stream_callback)(bool is_speech, float probability, double timestamp_ms, void* user_data);

// =============================================================================
// BACKEND LIFECYCLE
// =============================================================================

/**
 * Get list of available backend names
 * @param count Output: number of backends
 * @return Array of backend names (caller must NOT free)
 */
const char** ra_get_available_backends(int* count);

/**
 * Create a backend instance by name
 * @param backend_name Name of backend ("onnx", "llamacpp", "coreml", etc.)
 * @return Handle or NULL on failure
 */
ra_backend_handle ra_create_backend(const char* backend_name);

/**
 * Initialize a backend with JSON configuration
 * @param handle Backend handle
 * @param config_json JSON configuration string (can be NULL for defaults)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_initialize(ra_backend_handle handle, const char* config_json);

/**
 * Check if backend is initialized
 */
bool ra_is_initialized(ra_backend_handle handle);

/**
 * Cleanup and destroy a backend
 */
void ra_destroy(ra_backend_handle handle);

/**
 * Get backend info as JSON
 * @param handle Backend handle
 * @return JSON string (caller must free with ra_free_string)
 */
char* ra_get_backend_info(ra_backend_handle handle);

/**
 * Check if backend supports a capability
 */
bool ra_supports_capability(ra_backend_handle handle, ra_capability_type capability);

/**
 * Get all supported capabilities
 * @param handle Backend handle
 * @param capabilities Output array (caller provides)
 * @param max_count Size of capabilities array
 * @return Number of capabilities written
 */
int ra_get_capabilities(ra_backend_handle handle, ra_capability_type* capabilities, int max_count);

/**
 * Get device type being used
 */
ra_device_type ra_get_device(ra_backend_handle handle);

/**
 * Get memory usage in bytes
 */
size_t ra_get_memory_usage(ra_backend_handle handle);

// =============================================================================
// TEXT GENERATION
// =============================================================================

/**
 * Load a text generation model
 * @param handle Backend handle
 * @param model_path Path to model file/directory
 * @param config_json Optional JSON config (can be NULL)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_text_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);

/**
 * Check if text generation model is loaded
 */
bool ra_text_is_model_loaded(ra_backend_handle handle);

/**
 * Unload text generation model
 */
ra_result_code ra_text_unload_model(ra_backend_handle handle);

/**
 * Generate text (synchronous)
 * @param handle Backend handle
 * @param prompt User prompt
 * @param system_prompt System prompt (can be NULL)
 * @param max_tokens Maximum tokens to generate
 * @param temperature Sampling temperature (0.0-2.0)
 * @param result_json Output: JSON result (caller must free with ra_free_string)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_text_generate(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    char** result_json
);

/**
 * Generate text with streaming
 * @param handle Backend handle
 * @param prompt User prompt
 * @param system_prompt System prompt (can be NULL)
 * @param max_tokens Maximum tokens to generate
 * @param temperature Sampling temperature
 * @param callback Token callback function
 * @param user_data User data passed to callback
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_text_generate_stream(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    ra_text_stream_callback callback,
    void* user_data
);

/**
 * Cancel ongoing text generation
 */
void ra_text_cancel(ra_backend_handle handle);

// =============================================================================
// EMBEDDINGS
// =============================================================================

/**
 * Load an embedding model
 */
ra_result_code ra_embed_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);

/**
 * Check if embedding model is loaded
 */
bool ra_embed_is_model_loaded(ra_backend_handle handle);

/**
 * Unload embedding model
 */
ra_result_code ra_embed_unload_model(ra_backend_handle handle);

/**
 * Generate embedding for text
 * @param handle Backend handle
 * @param text Input text
 * @param embedding Output: embedding vector (caller must free with ra_free_embedding)
 * @param dimensions Output: embedding dimensions
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_embed_text(
    ra_backend_handle handle,
    const char* text,
    float** embedding,
    int* dimensions
);

/**
 * Generate embeddings for multiple texts
 * @param handle Backend handle
 * @param texts Array of input texts
 * @param num_texts Number of texts
 * @param embeddings Output: array of embedding vectors (caller must free)
 * @param dimensions Output: embedding dimensions
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_embed_batch(
    ra_backend_handle handle,
    const char** texts,
    int num_texts,
    float*** embeddings,
    int* dimensions
);

/**
 * Get embedding dimensions
 */
int ra_embed_get_dimensions(ra_backend_handle handle);

/**
 * Free embedding memory
 */
void ra_free_embedding(float* embedding);

/**
 * Free batch embeddings
 */
void ra_free_embeddings(float** embeddings, int count);

// =============================================================================
// SPEECH-TO-TEXT (STT)
// =============================================================================

/**
 * Load an STT model
 * @param handle Backend handle
 * @param model_path Path to model file/directory
 * @param model_type Model type ("whisper", "zipformer", "paraformer")
 * @param config_json Optional JSON config
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_stt_load_model(
    ra_backend_handle handle,
    const char* model_path,
    const char* model_type,
    const char* config_json
);

/**
 * Check if STT model is loaded
 */
bool ra_stt_is_model_loaded(ra_backend_handle handle);

/**
 * Unload STT model
 */
ra_result_code ra_stt_unload_model(ra_backend_handle handle);

/**
 * Transcribe audio (batch mode)
 * @param handle Backend handle
 * @param audio_samples Float32 audio samples [-1.0, 1.0]
 * @param num_samples Number of samples
 * @param sample_rate Sample rate (e.g., 16000)
 * @param language ISO 639-1 language code (can be NULL for auto-detect)
 * @param result_json Output: JSON result (caller must free with ra_free_string)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_stt_transcribe(
    ra_backend_handle handle,
    const float* audio_samples,
    size_t num_samples,
    int sample_rate,
    const char* language,
    char** result_json
);

/**
 * Check if STT supports streaming
 */
bool ra_stt_supports_streaming(ra_backend_handle handle);

/**
 * Create STT streaming session
 * @param handle Backend handle
 * @param config_json Optional JSON config
 * @return Stream handle or NULL on failure
 */
ra_stream_handle ra_stt_create_stream(ra_backend_handle handle, const char* config_json);

/**
 * Feed audio to STT stream
 * @param handle Backend handle
 * @param stream Stream handle
 * @param samples Float32 audio samples
 * @param num_samples Number of samples
 * @param sample_rate Sample rate
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_stt_feed_audio(
    ra_backend_handle handle,
    ra_stream_handle stream,
    const float* samples,
    size_t num_samples,
    int sample_rate
);

/**
 * Check if STT decoder is ready
 */
bool ra_stt_is_ready(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Decode and get current result
 * @param handle Backend handle
 * @param stream Stream handle
 * @param result_json Output: JSON result (caller must free)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_stt_decode(ra_backend_handle handle, ra_stream_handle stream, char** result_json);

/**
 * Check for end-of-speech (endpoint detection)
 */
bool ra_stt_is_endpoint(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Signal end of audio input
 */
void ra_stt_input_finished(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Reset stream for new utterance
 */
void ra_stt_reset_stream(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Destroy STT stream
 */
void ra_stt_destroy_stream(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Cancel ongoing transcription
 */
void ra_stt_cancel(ra_backend_handle handle);

// =============================================================================
// TEXT-TO-SPEECH (TTS)
// =============================================================================

/**
 * Load a TTS model
 * @param handle Backend handle
 * @param model_path Path to model file/directory
 * @param model_type Model type ("piper", "coqui", "bark")
 * @param config_json Optional JSON config
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_tts_load_model(
    ra_backend_handle handle,
    const char* model_path,
    const char* model_type,
    const char* config_json
);

/**
 * Check if TTS model is loaded
 */
bool ra_tts_is_model_loaded(ra_backend_handle handle);

/**
 * Unload TTS model
 */
ra_result_code ra_tts_unload_model(ra_backend_handle handle);

/**
 * Synthesize speech (batch mode)
 * @param handle Backend handle
 * @param text Text to synthesize
 * @param voice_id Voice identifier (can be NULL for default)
 * @param speed_rate Speed rate (1.0 = normal)
 * @param pitch_shift Pitch shift in semitones
 * @param audio_samples Output: float32 audio samples (caller must free with ra_free_audio)
 * @param num_samples Output: number of samples
 * @param sample_rate Output: sample rate
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_tts_synthesize(
    ra_backend_handle handle,
    const char* text,
    const char* voice_id,
    float speed_rate,
    float pitch_shift,
    float** audio_samples,
    size_t* num_samples,
    int* sample_rate
);

/**
 * Synthesize speech with streaming
 */
ra_result_code ra_tts_synthesize_stream(
    ra_backend_handle handle,
    const char* text,
    const char* voice_id,
    float speed_rate,
    float pitch_shift,
    ra_tts_stream_callback callback,
    void* user_data
);

/**
 * Check if TTS supports streaming
 */
bool ra_tts_supports_streaming(ra_backend_handle handle);

/**
 * Get available voices as JSON array
 * @param handle Backend handle
 * @return JSON string (caller must free with ra_free_string)
 */
char* ra_tts_get_voices(ra_backend_handle handle);

/**
 * Cancel ongoing synthesis
 */
void ra_tts_cancel(ra_backend_handle handle);

/**
 * Free audio samples
 */
void ra_free_audio(float* audio_samples);

// =============================================================================
// VOICE ACTIVITY DETECTION (VAD)
// =============================================================================

/**
 * Load a VAD model
 * @param handle Backend handle
 * @param model_path Path to model file (can be NULL for built-in)
 * @param config_json Optional JSON config
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_vad_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);

/**
 * Check if VAD model is loaded
 */
bool ra_vad_is_model_loaded(ra_backend_handle handle);

/**
 * Unload VAD model
 */
ra_result_code ra_vad_unload_model(ra_backend_handle handle);

/**
 * Process audio chunk and get speech probability
 * @param handle Backend handle
 * @param samples Float32 audio samples
 * @param num_samples Number of samples
 * @param sample_rate Sample rate
 * @param is_speech Output: true if speech detected
 * @param probability Output: speech probability [0.0, 1.0]
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_vad_process(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    bool* is_speech,
    float* probability
);

/**
 * Detect speech segments in full audio
 * @param handle Backend handle
 * @param samples Float32 audio samples
 * @param num_samples Number of samples
 * @param sample_rate Sample rate
 * @param result_json Output: JSON array of segments (caller must free)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_vad_detect_segments(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    char** result_json
);

/**
 * Create VAD streaming session
 */
ra_stream_handle ra_vad_create_stream(ra_backend_handle handle, const char* config_json);

/**
 * Feed audio to VAD stream
 */
ra_result_code ra_vad_feed_stream(
    ra_backend_handle handle,
    ra_stream_handle stream,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    bool* is_speech,
    float* probability
);

/**
 * Destroy VAD stream
 */
void ra_vad_destroy_stream(ra_backend_handle handle, ra_stream_handle stream);

/**
 * Reset VAD state
 */
void ra_vad_reset(ra_backend_handle handle);

// =============================================================================
// SPEAKER DIARIZATION
// =============================================================================

/**
 * Load a diarization model
 */
ra_result_code ra_diarize_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);

/**
 * Check if diarization model is loaded
 */
bool ra_diarize_is_model_loaded(ra_backend_handle handle);

/**
 * Unload diarization model
 */
ra_result_code ra_diarize_unload_model(ra_backend_handle handle);

/**
 * Perform speaker diarization on audio
 * @param handle Backend handle
 * @param samples Float32 audio samples
 * @param num_samples Number of samples
 * @param sample_rate Sample rate
 * @param min_speakers Minimum expected speakers (0 for auto)
 * @param max_speakers Maximum expected speakers (0 for auto)
 * @param result_json Output: JSON result (caller must free)
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_diarize(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    int min_speakers,
    int max_speakers,
    char** result_json
);

/**
 * Cancel ongoing diarization
 */
void ra_diarize_cancel(ra_backend_handle handle);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Free a string allocated by the bridge
 */
void ra_free_string(char* str);

/**
 * Get last error message
 * @return Error message (do NOT free, valid until next call)
 */
const char* ra_get_last_error(void);

/**
 * Get bridge version
 */
const char* ra_get_version(void);

/**
 * Extract an archive (tar.bz2, tar.gz, zip) to a destination directory
 * @param archive_path Path to the archive file
 * @param dest_dir Destination directory path
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_extract_archive(const char* archive_path, const char* dest_dir);

#ifdef __cplusplus
}
#endif

#endif // RA_LLAMACPP_BRIDGE_H
