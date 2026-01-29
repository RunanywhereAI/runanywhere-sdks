/**
 * @file rac_wakeword_service.h
 * @brief RunAnywhere Commons - Wake Word Service Interface
 *
 * Service interface for wake word detection.
 * Follows the same patterns as VAD, STT, TTS, LLM services.
 *
 * Usage:
 *   1. Create service: rac_wakeword_create()
 *   2. Initialize: rac_wakeword_initialize()
 *   3. Load models: rac_wakeword_load_model()
 *   4. Set callback: rac_wakeword_set_callback()
 *   5. Start listening: rac_wakeword_start()
 *   6. Process audio: rac_wakeword_process()
 *   7. Stop: rac_wakeword_stop()
 *   8. Cleanup: rac_wakeword_destroy()
 */

#ifndef RAC_WAKEWORD_SERVICE_H
#define RAC_WAKEWORD_SERVICE_H

#include "rac/core/rac_error.h"
#include "rac/features/wakeword/rac_wakeword_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE LIFECYCLE
// =============================================================================

/**
 * @brief Create a wake word detection service
 *
 * Creates an uninitialized service instance. Call rac_wakeword_initialize()
 * to configure and prepare the service for use.
 *
 * @param[out] out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_create(rac_handle_t* out_handle);

/**
 * @brief Initialize the wake word service
 *
 * Initializes the service with the provided configuration. Must be called
 * before loading models or processing audio.
 *
 * @param handle Service handle
 * @param config Configuration (NULL for defaults)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_initialize(rac_handle_t handle,
                                              const rac_wakeword_config_t* config);

/**
 * @brief Destroy a wake word service instance
 *
 * Stops processing, unloads all models, and frees all resources.
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_wakeword_destroy(rac_handle_t handle);

// =============================================================================
// MODEL MANAGEMENT
// =============================================================================

/**
 * @brief Load a wake word model
 *
 * Loads an ONNX wake word model (e.g., from openWakeWord). Multiple models
 * can be loaded simultaneously for detecting different wake words.
 *
 * @param handle Service handle
 * @param model_path Path to ONNX wake word model file
 * @param model_id Unique identifier for this model
 * @param wake_word Human-readable wake word phrase (e.g., "Hey Jarvis")
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_load_model(rac_handle_t handle,
                                              const char* model_path,
                                              const char* model_id,
                                              const char* wake_word);

/**
 * @brief Load VAD model for pre-filtering
 *
 * Loads a Silero VAD model to filter audio before wake word detection.
 * This reduces false positives by only processing speech segments.
 *
 * @param handle Service handle
 * @param vad_model_path Path to Silero VAD ONNX model
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_load_vad(rac_handle_t handle,
                                            const char* vad_model_path);

/**
 * @brief Unload a specific wake word model
 *
 * @param handle Service handle
 * @param model_id Model identifier to unload
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_unload_model(rac_handle_t handle,
                                                const char* model_id);

/**
 * @brief Unload all wake word models
 *
 * Keeps the service initialized but removes all loaded models.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_unload_all(rac_handle_t handle);

/**
 * @brief Get list of loaded models
 *
 * @param handle Service handle
 * @param[out] out_models Output: Array of model info (owned by service)
 * @param[out] out_count Output: Number of models
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_get_models(rac_handle_t handle,
                                              const rac_wakeword_model_info_t** out_models,
                                              int32_t* out_count);

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief Set wake word detection callback
 *
 * The callback is invoked whenever a wake word is detected. Only one callback
 * can be registered at a time.
 *
 * @param handle Service handle
 * @param callback Detection callback (NULL to unset)
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_set_callback(rac_handle_t handle,
                                                rac_wakeword_callback_fn callback,
                                                void* user_data);

/**
 * @brief Set VAD state callback (optional, for debugging)
 *
 * @param handle Service handle
 * @param callback VAD callback (NULL to unset)
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_set_vad_callback(rac_handle_t handle,
                                                    rac_wakeword_vad_callback_fn callback,
                                                    void* user_data);

// =============================================================================
// DETECTION CONTROL
// =============================================================================

/**
 * @brief Start listening for wake words
 *
 * Enables wake word detection. After calling this, audio frames passed to
 * rac_wakeword_process() will be analyzed for wake words.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_start(rac_handle_t handle);

/**
 * @brief Stop listening for wake words
 *
 * Disables wake word detection. Audio frames will be ignored until
 * rac_wakeword_start() is called again.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_stop(rac_handle_t handle);

/**
 * @brief Pause detection temporarily
 *
 * Pauses detection without clearing state. Useful during TTS playback
 * to avoid self-triggering.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_pause(rac_handle_t handle);

/**
 * @brief Resume detection after pause
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_resume(rac_handle_t handle);

/**
 * @brief Reset detector state
 *
 * Clears internal buffers and resets the detection state. Call this
 * after a detection or when starting a new audio stream.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_reset(rac_handle_t handle);

// =============================================================================
// AUDIO PROCESSING
// =============================================================================

/**
 * @brief Process audio samples (float format)
 *
 * Processes a frame of audio samples for wake word detection. If a wake word
 * is detected and a callback is registered, the callback will be invoked.
 *
 * @param handle Service handle
 * @param samples Float audio samples (PCM, -1.0 to 1.0)
 * @param num_samples Number of samples
 * @param[out] out_result Optional: Frame processing result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_process(rac_handle_t handle,
                                           const float* samples,
                                           size_t num_samples,
                                           rac_wakeword_frame_result_t* out_result);

/**
 * @brief Process audio samples (int16 format)
 *
 * Convenience function that accepts 16-bit PCM audio.
 *
 * @param handle Service handle
 * @param samples Int16 audio samples (PCM, -32768 to 32767)
 * @param num_samples Number of samples
 * @param[out] out_result Optional: Frame processing result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_process_int16(rac_handle_t handle,
                                                 const int16_t* samples,
                                                 size_t num_samples,
                                                 rac_wakeword_frame_result_t* out_result);

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief Set detection threshold
 *
 * Sets the global detection threshold. Higher values reduce false positives
 * but may miss quieter wake words.
 *
 * @param handle Service handle
 * @param threshold New threshold (0.0 - 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_set_threshold(rac_handle_t handle,
                                                 float threshold);

/**
 * @brief Set model-specific threshold
 *
 * @param handle Service handle
 * @param model_id Model identifier
 * @param threshold Model threshold (0.0 - 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_set_model_threshold(rac_handle_t handle,
                                                       const char* model_id,
                                                       float threshold);

/**
 * @brief Enable/disable VAD pre-filtering
 *
 * @param handle Service handle
 * @param enabled Whether to enable VAD filtering
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_set_vad_enabled(rac_handle_t handle,
                                                   rac_bool_t enabled);

// =============================================================================
// STATUS
// =============================================================================

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param[out] out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_wakeword_get_info(rac_handle_t handle,
                                            rac_wakeword_info_t* out_info);

/**
 * @brief Check if service is ready
 *
 * @param handle Service handle
 * @return RAC_TRUE if ready, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_wakeword_is_ready(rac_handle_t handle);

/**
 * @brief Check if currently listening
 *
 * @param handle Service handle
 * @return RAC_TRUE if listening, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_wakeword_is_listening(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_WAKEWORD_SERVICE_H */
