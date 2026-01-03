/**
 * @file rac_stt_component.h
 * @brief RunAnywhere Commons - STT Capability Component
 *
 * C port of Swift's STTCapability.swift from:
 * Sources/RunAnywhere/Features/STT/STTCapability.swift
 *
 * Actor-based STT capability that owns model lifecycle and transcription.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#ifndef RAC_STT_COMPONENT_H
#define RAC_STT_COMPONENT_H

#include "rac_lifecycle.h"
#include "rac_error.h"
#include "rac_stt_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// NOTE: rac_stt_config_t is defined in rac_stt_types.h (included above)

// =============================================================================
// STT COMPONENT API - Mirrors Swift's STTCapability
// =============================================================================

/**
 * @brief Create an STT capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the STT component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_configure(rac_handle_t handle,
                                                 const rac_stt_config_t* config);

/**
 * @brief Check if model is loaded
 *
 * @param handle Component handle
 * @return RAC_TRUE if loaded, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_stt_component_is_loaded(rac_handle_t handle);

/**
 * @brief Get current model ID
 *
 * @param handle Component handle
 * @return Current model ID (NULL if not loaded)
 */
RAC_API const char* rac_stt_component_get_model_id(rac_handle_t handle);

/**
 * @brief Load a model
 *
 * @param handle Component handle
 * @param model_id Model ID to load
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_load_model(rac_handle_t handle, const char* model_id);

/**
 * @brief Unload the current model
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_unload(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_cleanup(rac_handle_t handle);

/**
 * @brief Transcribe audio data (batch mode)
 *
 * @param handle Component handle
 * @param audio_data Audio data buffer
 * @param audio_size Size of audio data in bytes
 * @param options Transcription options (can be NULL for defaults)
 * @param out_result Output: Transcription result
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_transcribe(rac_handle_t handle, const void* audio_data,
                                                  size_t audio_size,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result);

/**
 * @brief Check if streaming is supported
 *
 * @param handle Component handle
 * @return RAC_TRUE if streaming supported, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_stt_component_supports_streaming(rac_handle_t handle);

/**
 * @brief Transcribe audio with streaming
 *
 * @param handle Component handle
 * @param audio_data Audio chunk data
 * @param audio_size Size of audio chunk
 * @param options Transcription options
 * @param callback Callback for partial results
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_transcribe_stream(rac_handle_t handle,
                                                         const void* audio_data, size_t audio_size,
                                                         const rac_stt_options_t* options,
                                                         rac_stt_stream_callback_t callback,
                                                         void* user_data);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_stt_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the STT component
 *
 * @param handle Component handle
 */
RAC_API void rac_stt_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_COMPONENT_H */
