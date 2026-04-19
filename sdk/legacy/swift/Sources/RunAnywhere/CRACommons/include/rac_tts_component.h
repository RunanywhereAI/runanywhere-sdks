/**
 * @file rac_tts_component.h
 * @brief RunAnywhere Commons - TTS Capability Component
 *
 * C port of Swift's TTSCapability.swift from:
 * Sources/RunAnywhere/Features/TTS/TTSCapability.swift
 *
 * Actor-based TTS capability that owns voice lifecycle and synthesis.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#ifndef RAC_TTS_COMPONENT_H
#define RAC_TTS_COMPONENT_H

#include "rac_lifecycle.h"
#include "rac_error.h"
#include "rac_tts_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// NOTE: rac_tts_config_t is defined in rac_tts_types.h (included above)

// =============================================================================
// TTS COMPONENT API - Mirrors Swift's TTSCapability
// =============================================================================

/**
 * @brief Create a TTS capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the TTS component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_configure(rac_handle_t handle,
                                                 const rac_tts_config_t* config);

/**
 * @brief Check if voice is loaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_tts_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current voice ID
 *
 * @param handle Component handle
 * @return Current voice ID (NULL if not loaded)
 */
RAC_API const char* rac_tts_component_get_voice_id(rac_handle_t handle);

/**
 * @brief Load a voice
 *
 * @param handle Component handle
 * @param voice_path File path to the voice (used for loading) - REQUIRED
 * @param voice_id Voice identifier for telemetry (e.g., "vits-piper-en_GB-alba-medium")
 *                 Optional: if NULL, defaults to voice_path
 * @param voice_name Human-readable voice name (e.g., "Piper TTS (British English)")
 *                   Optional: if NULL, defaults to voice_id
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_load_voice(rac_handle_t handle, const char* voice_path,
                                                  const char* voice_id, const char* voice_name);

/**
 * @brief Unload the current voice
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_cleanup(rac_handle_t handle);

/**
 * @brief Stop current synthesis
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_stop(rac_handle_t handle);

/**
 * @brief Synthesize text to audio
 *
 * @param handle Component handle
 * @param text Text to synthesize
 * @param options Synthesis options (can be NULL for defaults)
 * @param out_result Output: Synthesis result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_synthesize(rac_handle_t handle, const char* text,
                                                  const rac_tts_options_t* options,
                                                  rac_tts_result_t* out_result);

/**
 * @brief Synthesize text with streaming
 *
 * @param handle Component handle
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param callback Callback for audio chunks
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_synthesize_stream(rac_handle_t handle, const char* text,
                                                         const rac_tts_options_t* options,
                                                         rac_tts_stream_callback_t callback,
                                                         void* user_data);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_tts_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the TTS component
 *
 * @param handle Component handle
 */
RAC_API void rac_tts_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_COMPONENT_H */
