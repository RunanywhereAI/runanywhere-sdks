#ifndef RUNANYWHERE_ONNX_BRIDGE_H
#define RUNANYWHERE_ONNX_BRIDGE_H

#include <stddef.h>
#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Create an ONNX runtime instance
 * @return Handle to the ONNX backend, or NULL on failure
 */
ra_onnx_handle ra_onnx_create(void);

/**
 * @brief Initialize the ONNX runtime with configuration
 * @param handle The ONNX backend handle
 * @param config_json JSON configuration string (can be NULL for defaults)
 * @return RA_SUCCESS on success, error code otherwise
 */
int ra_onnx_initialize(ra_onnx_handle handle, const char* config_json);

/**
 * @brief Load an ONNX model from file
 * @param handle The ONNX backend handle
 * @param model_path Path to the .onnx model file
 * @return RA_SUCCESS on success, error code otherwise
 */
int ra_onnx_load_model(ra_onnx_handle handle, const char* model_path);

/**
 * @brief Check if model is loaded
 * @param handle The ONNX backend handle
 * @return 1 if model is loaded, 0 otherwise
 */
int ra_onnx_is_model_loaded(ra_onnx_handle handle);

/**
 * @brief Run inference on the loaded model
 * @param handle The ONNX backend handle
 * @param prompt Input text prompt
 * @param max_tokens Maximum number of tokens to generate
 * @param temperature Sampling temperature (0.0 - 2.0)
 * @param result_json Output parameter for JSON result string
 * @return RA_SUCCESS on success, error code otherwise
 *
 * @note The result_json string must be freed using ra_free_string()
 */
int ra_onnx_infer(
    ra_onnx_handle handle,
    const char* prompt,
    int max_tokens,
    float temperature,
    char** result_json
);

/**
 * @brief Run streaming inference (token by token)
 * @param handle The ONNX backend handle
 * @param prompt Input text prompt
 * @param max_tokens Maximum number of tokens to generate
 * @param temperature Sampling temperature
 * @param callback Function called for each generated token
 * @param user_data User data passed to callback
 * @return RA_SUCCESS on success, error code otherwise
 */
typedef void (*ra_onnx_stream_callback)(const char* token, void* user_data);

int ra_onnx_infer_stream(
    ra_onnx_handle handle,
    const char* prompt,
    int max_tokens,
    float temperature,
    ra_onnx_stream_callback callback,
    void* user_data
);

/**
 * @brief Cancel ongoing inference
 * @param handle The ONNX backend handle
 */
void ra_onnx_cancel(ra_onnx_handle handle);

/**
 * @brief Get current memory usage in bytes
 * @param handle The ONNX backend handle
 * @return Memory usage in bytes
 */
size_t ra_onnx_memory_usage(ra_onnx_handle handle);

/**
 * @brief Get device type being used
 * @param handle The ONNX backend handle
 * @return Device type string (e.g., "CPU", "CoreML", "NNAPI")
 */
const char* ra_onnx_device_type(ra_onnx_handle handle);

/**
 * @brief Set telemetry event callback
 * @param handle The ONNX backend handle
 * @param callback Function called for telemetry events
 * @param user_data User data passed to callback
 */
typedef void (*ra_onnx_telemetry_callback)(const char* event_json, void* user_data);

void ra_onnx_set_telemetry_callback(
    ra_onnx_handle handle,
    ra_onnx_telemetry_callback callback,
    void* user_data
);

/**
 * @brief Unload the current model
 * @param handle The ONNX backend handle
 * @return RA_SUCCESS on success, error code otherwise
 */
int ra_onnx_unload_model(ra_onnx_handle handle);

/**
 * @brief Destroy the ONNX runtime instance
 * @param handle The ONNX backend handle
 */
void ra_onnx_destroy(ra_onnx_handle handle);

/**
 * @brief Free a string allocated by the library
 * @param str String to free
 */
void ra_free_string(char* str);

//==============================================================================
// MODALITY-SPECIFIC FUNCTIONS
//==============================================================================

#include "modality_types.h"

/**
 * @brief Set the modality for the loaded model
 * @param handle The ONNX backend handle
 * @param modality The modality type (ASR, TTS, LLM, etc.)
 * @return RA_SUCCESS on success, error code otherwise
 *
 * @note This should be called after load_model() to configure the backend
 *       for the specific use case
 */
int ra_onnx_set_modality(ra_onnx_handle handle, ra_modality_type modality);

/**
 * @brief Get the current modality
 * @param handle The ONNX backend handle
 * @return Current modality type
 */
ra_modality_type ra_onnx_get_modality(ra_onnx_handle handle);

//------------------------------------------------------------------------------
// ASR/STT Functions (Voice-to-Text)
//------------------------------------------------------------------------------

/**
 * @brief Transcribe audio to text (ASR/STT)
 * @param handle The ONNX backend handle
 * @param audio_data Audio data bytes
 * @param audio_size Size of audio data in bytes
 * @param audio_config Audio configuration (sample rate, format, etc.)
 * @param language Language code (e.g., "en", "es") or NULL for auto-detect
 * @param result_json Output JSON with transcription result
 * @return RA_SUCCESS on success, error code otherwise
 *
 * Result JSON format:
 * {
 *   "text": "transcribed text",
 *   "confidence": 0.95,
 *   "language": "en",
 *   "metadata": {
 *     "processing_time_ms": 123.4,
 *     "audio_duration_ms": 5000.0,
 *     "real_time_factor": 0.0247
 *   }
 * }
 *
 * @note Result must be freed with ra_free_string()
 */
int ra_onnx_transcribe(
    ra_onnx_handle handle,
    const uint8_t* audio_data,
    size_t audio_size,
    const ra_audio_config* audio_config,
    const char* language,
    char** result_json
);

//------------------------------------------------------------------------------
// TTS Functions (Text-to-Voice)
//------------------------------------------------------------------------------

/**
 * @brief Synthesize text to speech (TTS)
 * @param handle The ONNX backend handle
 * @param text Text to synthesize
 * @param voice_id Voice identifier (or NULL for default)
 * @param audio_config Desired output audio configuration
 * @param rate Speech rate (0.5 to 2.0, 1.0 = normal)
 * @param pitch Speech pitch (0.5 to 2.0, 1.0 = normal)
 * @param audio_data Output parameter for synthesized audio bytes
 * @param audio_size Output parameter for audio data size
 * @param duration_ms Output parameter for audio duration in milliseconds
 * @return RA_SUCCESS on success, error code otherwise
 *
 * @note audio_data must be freed with ra_free_audio_data()
 */
int ra_onnx_synthesize(
    ra_onnx_handle handle,
    const char* text,
    const char* voice_id,
    const ra_audio_config* audio_config,
    float rate,
    float pitch,
    uint8_t** audio_data,
    size_t* audio_size,
    double* duration_ms
);

/**
 * @brief Free audio data allocated by ra_onnx_synthesize
 * @param audio_data Audio data to free
 */
void ra_free_audio_data(uint8_t* audio_data);

//------------------------------------------------------------------------------
// LLM Functions (Text-to-Text)
//------------------------------------------------------------------------------

/**
 * @brief Generate text from prompt (LLM)
 * @param handle The ONNX backend handle
 * @param messages_json JSON array of messages (conversation history)
 * @param system_prompt System prompt (or NULL)
 * @param max_tokens Maximum tokens to generate
 * @param temperature Sampling temperature
 * @param result_json Output JSON with generation result
 * @return RA_SUCCESS on success, error code otherwise
 *
 * Messages JSON format:
 * [
 *   {"role": "system", "content": "You are a helpful assistant"},
 *   {"role": "user", "content": "Hello!"},
 *   {"role": "assistant", "content": "Hi! How can I help?"},
 *   {"role": "user", "content": "What's the weather?"}
 * ]
 *
 * Result JSON format:
 * {
 *   "text": "generated response",
 *   "token_usage": {
 *     "prompt_tokens": 45,
 *     "completion_tokens": 12,
 *     "total_tokens": 57
 *   },
 *   "finish_reason": "completed",
 *   "metadata": {
 *     "inference_time_ms": 234.5
 *   }
 * }
 *
 * @note Result must be freed with ra_free_string()
 */
int ra_onnx_generate_text(
    ra_onnx_handle handle,
    const char* messages_json,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    char** result_json
);

/**
 * @brief Stream text generation token by token
 * @param handle The ONNX backend handle
 * @param messages_json JSON array of messages
 * @param system_prompt System prompt (or NULL)
 * @param max_tokens Maximum tokens to generate
 * @param temperature Sampling temperature
 * @param callback Function called for each generated token
 * @param user_data User data passed to callback
 * @return RA_SUCCESS on success, error code otherwise
 */
typedef void (*ra_text_stream_callback)(const char* token, void* user_data);

int ra_onnx_generate_text_stream(
    ra_onnx_handle handle,
    const char* messages_json,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    ra_text_stream_callback callback,
    void* user_data
);

#ifdef __cplusplus
}
#endif

#endif // RUNANYWHERE_ONNX_BRIDGE_H
