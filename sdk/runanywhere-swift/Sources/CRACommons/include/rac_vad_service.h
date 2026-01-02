/**
 * @file rac_vad_service.h
 * @brief RunAnywhere Commons - VAD Service Interface (Protocol)
 *
 * C port of Swift's VADService protocol from:
 * Sources/RunAnywhere/Features/VAD/Protocol/VADService.swift
 *
 * This header defines the service interface. For data types,
 * see rac_vad_types.h.
 */

#ifndef RAC_VAD_SERVICE_H
#define RAC_VAD_SERVICE_H

#include "rac_error.h"
#include "rac_vad_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE INTERFACE - Mirrors Swift's VADService protocol
// =============================================================================

/**
 * @brief Create a VAD service
 *
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_create(rac_handle_t* out_handle);

/**
 * @brief Initialize the VAD service
 *
 * Mirrors Swift's VADService.initialize()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_initialize(rac_handle_t handle);

/**
 * @brief Set speech activity callback
 *
 * Mirrors Swift's VADService.onSpeechActivity property.
 *
 * @param handle Service handle
 * @param callback Activity callback (can be NULL to unset)
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_set_activity_callback(rac_handle_t handle,
                                                   rac_vad_activity_callback_fn callback,
                                                   void* user_data);

/**
 * @brief Set audio buffer callback
 *
 * Mirrors Swift's VADService.onAudioBuffer property.
 *
 * @param handle Service handle
 * @param callback Audio callback (can be NULL to unset)
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_set_audio_callback(rac_handle_t handle,
                                                rac_vad_audio_callback_fn callback,
                                                void* user_data);

/**
 * @brief Start VAD processing
 *
 * Mirrors Swift's VADService.start()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_start(rac_handle_t handle);

/**
 * @brief Stop VAD processing
 *
 * Mirrors Swift's VADService.stop()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_stop(rac_handle_t handle);

/**
 * @brief Reset VAD state
 *
 * Mirrors Swift's VADService.reset()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_reset(rac_handle_t handle);

/**
 * @brief Pause VAD processing
 *
 * Mirrors Swift's VADService.pause() (optional, default no-op)
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_pause(rac_handle_t handle);

/**
 * @brief Resume VAD processing
 *
 * Mirrors Swift's VADService.resume() (optional, default no-op)
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_resume(rac_handle_t handle);

/**
 * @brief Process audio samples
 *
 * Mirrors Swift's VADService.processAudioData(_:)
 *
 * @param handle Service handle
 * @param samples Float audio samples (PCM)
 * @param num_samples Number of samples
 * @param out_is_speech Output: Whether speech is detected
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_process_samples(rac_handle_t handle, const float* samples,
                                             size_t num_samples, rac_bool_t* out_is_speech);

/**
 * @brief Set energy threshold
 *
 * Mirrors Swift's VADService.energyThreshold setter.
 *
 * @param handle Service handle
 * @param threshold New threshold (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_set_energy_threshold(rac_handle_t handle, float threshold);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_vad_get_info(rac_handle_t handle, rac_vad_info_t* out_info);

/**
 * @brief Destroy a VAD service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_vad_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_SERVICE_H */
