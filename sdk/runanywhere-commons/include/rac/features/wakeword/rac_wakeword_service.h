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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_create(rac_handle_t* out_handle);

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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_initialize(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_load_model(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_load_vad(rac_handle_t handle,
                                            const char* vad_model_path);

/**
 * @brief Unload a specific wake word model
 *
 * @param handle Service handle
 * @param model_id Model identifier to unload
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_unload_model(rac_handle_t handle,
                                                const char* model_id);

/**
 * @brief Unload all wake word models
 *
 * Keeps the service initialized but removes all loaded models.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_unload_all(rac_handle_t handle);

/**
 * @brief Get list of loaded models
 *
 * @param handle Service handle
 * @param[out] out_models Output: Array of model info (owned by service)
 * @param[out] out_count Output: Number of models
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_get_models(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_set_callback(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_set_vad_callback(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_start(rac_handle_t handle);

/**
 * @brief Stop listening for wake words
 *
 * Disables wake word detection. Audio frames will be ignored until
 * rac_wakeword_start() is called again.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_stop(rac_handle_t handle);

/**
 * @brief Pause detection temporarily
 *
 * Pauses detection without clearing state. Useful during TTS playback
 * to avoid self-triggering.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_pause(rac_handle_t handle);

/**
 * @brief Resume detection after pause
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_resume(rac_handle_t handle);

/**
 * @brief Reset detector state
 *
 * Clears internal buffers and resets the detection state. Call this
 * after a detection or when starting a new audio stream.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_reset(rac_handle_t handle);

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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_process(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_process_int16(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_set_threshold(rac_handle_t handle,
                                                 float threshold);

/**
 * @brief Set model-specific threshold
 *
 * @param handle Service handle
 * @param model_id Model identifier
 * @param threshold Model threshold (0.0 - 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_set_model_threshold(rac_handle_t handle,
                                                       const char* model_id,
                                                       float threshold);

/**
 * @brief Enable/disable VAD pre-filtering
 *
 * @param handle Service handle
 * @param enabled Whether to enable VAD filtering
 * @return RAC_SUCCESS or error code
 */
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_set_vad_enabled(rac_handle_t handle,
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
RAC_API RAC_NODISCARD rac_result_t rac_wakeword_get_info(rac_handle_t handle,
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

// =============================================================================
// PROVIDER REGISTRATION (backend hook)
// =============================================================================
//
// The wake-word service layer lives in rac_commons and therefore cannot
// directly link against any concrete inference backend. Instead, any backend
// that wants to serve wake-word detection (today: the ONNX wake-word backend
// in src/backends/onnx/wakeword_onnx.cpp, and any future backends such as
// MetalRT) registers a vtable of function pointers via
// rac_wakeword_provider_set(). The service layer then dispatches every
// model-load / audio-process / reset / destroy call through that vtable.
//
// If no provider has registered, all service operations still succeed
// structurally (the service can be created, started, stopped) but
// rac_wakeword_process() becomes a no-op - detections never fire. Callers
// can detect this via rac_wakeword_has_provider() or by observing zero
// detections on known-positive audio.
//
// Lifetime: the callbacks struct passed to rac_wakeword_provider_set() must
// outlive every wake-word service instance. Typically this is a static
// global inside the provider backend's translation unit. The caller retains
// ownership; the service layer does not copy or free the struct.
//
// Thread-safety: rac_wakeword_provider_set() is expected to be called once
// at SDK startup, before any wake-word services exist. Calling it
// concurrently with live service instances is undefined.
// =============================================================================

/**
 * @brief Callback vtable a wake-word inference backend must implement to
 *        serve as the wake-word provider for rac_wakeword_* services.
 *
 * All function pointers may be NULL if the provider does not support that
 * operation; the service layer checks each before calling. The `user_data`
 * pointer is stored and passed back into every callback so providers can
 * associate each `backend_handle` with their own state.
 */
typedef struct rac_wakeword_provider_ops {
    /** Create a backend-specific handle. Called once per wake-word service
     *  during rac_wakeword_initialize(). Must return a handle suitable for
     *  passing to every other vtable method (and to `destroy`). */
    rac_result_t (*create)(const rac_wakeword_config_t* config,
                           rac_handle_t* out_backend_handle,
                           void* user_data);

    /** Load a wake-word classification model (ONNX, etc.). */
    rac_result_t (*load_model)(rac_handle_t backend_handle,
                               const char* model_path,
                               const char* model_id,
                               const char* wake_word,
                               void* user_data);

    /** Unload a wake-word model previously loaded with load_model. */
    rac_result_t (*unload_model)(rac_handle_t backend_handle,
                                 const char* model_id,
                                 void* user_data);

    /** Load a VAD pre-filter model (Silero). Optional. */
    rac_result_t (*load_vad)(rac_handle_t backend_handle,
                             const char* vad_model_path,
                             void* user_data);

    /** Run one frame of audio through inference + optional VAD.
     *  out_detected_index is set to >= 0 if a wake word fires (index into
     *  the provider's loaded-models list) or -1 otherwise. */
    rac_result_t (*process)(rac_handle_t backend_handle,
                            const float* samples, size_t num_samples,
                            int32_t* out_detected_index,
                            float* out_confidence,
                            rac_bool_t* out_vad_speech,
                            float* out_vad_confidence,
                            void* user_data);

    /** Reset internal state (KV cache, sliding window, etc.). */
    rac_result_t (*reset)(rac_handle_t backend_handle, void* user_data);

    /** Adjust detection threshold at runtime. */
    rac_result_t (*set_threshold)(rac_handle_t backend_handle,
                                  float threshold,
                                  void* user_data);

    /** Tear down the backend handle. */
    void (*destroy)(rac_handle_t backend_handle, void* user_data);

    /** Opaque user-data passed through to every callback. */
    void* user_data;
} rac_wakeword_provider_ops_t;

/**
 * @brief Register a wake-word inference provider.
 *
 * Called once at SDK startup by the concrete backend
 * (e.g. rac_backend_wakeword_onnx_register() wires up the ONNX provider).
 *
 * @param ops Provider vtable. Must outlive all wake-word services.
 *            Pass NULL to clear the registration.
 * @return RAC_SUCCESS always.
 */
RAC_API rac_result_t rac_wakeword_provider_set(const rac_wakeword_provider_ops_t* ops);

/**
 * @brief Query whether a wake-word provider is currently registered.
 *
 * @return RAC_TRUE if a provider has been set via rac_wakeword_provider_set(),
 *         RAC_FALSE otherwise. Useful for test code and graceful degradation.
 */
RAC_API rac_bool_t rac_wakeword_has_provider(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_WAKEWORD_SERVICE_H */
