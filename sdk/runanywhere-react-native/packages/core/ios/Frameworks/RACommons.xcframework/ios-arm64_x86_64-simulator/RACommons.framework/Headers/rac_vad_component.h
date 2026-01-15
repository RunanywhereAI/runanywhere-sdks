/**
 * @file rac_vad_component.h
 * @brief RunAnywhere Commons - VAD Capability Component
 *
 * C port of Swift's VADCapability.swift from:
 * Sources/RunAnywhere/Features/VAD/VADCapability.swift
 *
 * Actor-based VAD capability that owns model lifecycle and voice detection.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 */

#ifndef RAC_VAD_COMPONENT_H
#define RAC_VAD_COMPONENT_H

#include <RACommons/rac_lifecycle.h>
#include <RACommons/rac_error.h>
#include <RACommons/rac_vad_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// NOTE: rac_vad_config_t is defined in rac_vad_types.h (included above)

// =============================================================================
// VAD COMPONENT API - Mirrors Swift's VADCapability
// =============================================================================

/**
 * @brief Create a VAD capability component
 *
 * @param out_handle Output: Handle to the component
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_create(rac_handle_t* out_handle);

/**
 * @brief Configure the VAD component
 *
 * @param handle Component handle
 * @param config Configuration
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_configure(rac_handle_t handle,
                                                 const rac_vad_config_t* config);

/**
 * @brief Check if VAD is initialized
 *
 * @param handle Component handle
 * @return RAC_TRUE if initialized, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_vad_component_is_initialized(rac_handle_t handle);

/**
 * @brief Initialize the VAD
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_initialize(rac_handle_t handle);

/**
 * @brief Cleanup and reset the component
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_cleanup(rac_handle_t handle);

/**
 * @brief Set speech activity callback
 *
 * @param handle Component handle
 * @param callback Activity callback
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_set_activity_callback(rac_handle_t handle,
                                                             rac_vad_activity_callback_fn callback,
                                                             void* user_data);

/**
 * @brief Set audio buffer callback
 *
 * @param handle Component handle
 * @param callback Audio buffer callback
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_set_audio_callback(rac_handle_t handle,
                                                          rac_vad_audio_callback_fn callback,
                                                          void* user_data);

/**
 * @brief Start VAD processing
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_start(rac_handle_t handle);

/**
 * @brief Stop VAD processing
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_stop(rac_handle_t handle);

/**
 * @brief Reset VAD state
 *
 * @param handle Component handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_reset(rac_handle_t handle);

/**
 * @brief Process audio samples
 *
 * @param handle Component handle
 * @param samples Float audio samples (PCM)
 * @param num_samples Number of samples
 * @param out_is_speech Output: Whether speech is detected
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_process(rac_handle_t handle, const float* samples,
                                               size_t num_samples, rac_bool_t* out_is_speech);

/**
 * @brief Get current speech activity state
 *
 * @param handle Component handle
 * @return RAC_TRUE if speech is active, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_vad_component_is_speech_active(rac_handle_t handle);

/**
 * @brief Get current energy threshold
 *
 * @param handle Component handle
 * @return Current energy threshold
 */
RAC_API float rac_vad_component_get_energy_threshold(rac_handle_t handle);

/**
 * @brief Set energy threshold
 *
 * @param handle Component handle
 * @param threshold New threshold (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_set_energy_threshold(rac_handle_t handle, float threshold);

/**
 * @brief Get lifecycle state
 *
 * @param handle Component handle
 * @return Current lifecycle state
 */
RAC_API rac_lifecycle_state_t rac_vad_component_get_state(rac_handle_t handle);

/**
 * @brief Get lifecycle metrics
 *
 * @param handle Component handle
 * @param out_metrics Output: Lifecycle metrics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics);

/**
 * @brief Destroy the VAD component
 *
 * @param handle Component handle
 */
RAC_API void rac_vad_component_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_COMPONENT_H */
