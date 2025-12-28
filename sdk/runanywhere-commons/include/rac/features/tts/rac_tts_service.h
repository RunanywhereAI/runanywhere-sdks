/**
 * @file rac_tts_service.h
 * @brief RunAnywhere Commons - TTS Service Interface (Protocol)
 *
 * C port of Swift's TTSService protocol from:
 * Sources/RunAnywhere/Features/TTS/Protocol/TTSService.swift
 *
 * This header defines the service interface. For data types,
 * see rac_tts_types.h.
 */

#ifndef RAC_TTS_SERVICE_H
#define RAC_TTS_SERVICE_H

#include "rac_tts_types.h"

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE INTERFACE - Mirrors Swift's TTSService protocol
// =============================================================================

/**
 * @brief Create a TTS service using the service registry
 *
 * @param model_path Path to the model file (can be NULL for some providers)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_create(const char* model_path, rac_handle_t* out_handle);

/**
 * @brief Initialize a TTS service
 *
 * Mirrors Swift's TTSService.initialize()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_initialize(rac_handle_t handle);

/**
 * @brief Synthesize text to audio
 *
 * Mirrors Swift's TTSService.synthesize(text:options:)
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options Synthesis options (can be NULL for defaults)
 * @param out_result Output: Synthesis result (caller must free with rac_tts_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_synthesize(rac_handle_t handle, const char* text,
                                        const rac_tts_options_t* options,
                                        rac_tts_result_t* out_result);

/**
 * @brief Stream synthesis for long text
 *
 * Mirrors Swift's TTSService.synthesizeStream(text:options:onChunk:)
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param callback Callback for each audio chunk
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_synthesize_stream(rac_handle_t handle, const char* text,
                                               const rac_tts_options_t* options,
                                               rac_tts_stream_callback_t callback, void* user_data);

/**
 * @brief Stop current synthesis
 *
 * Mirrors Swift's TTSService.stop()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_stop(rac_handle_t handle);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_get_info(rac_handle_t handle, rac_tts_info_t* out_info);

/**
 * @brief Cleanup and release resources
 *
 * Mirrors Swift's TTSService.cleanup()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_cleanup(rac_handle_t handle);

/**
 * @brief Destroy a TTS service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_tts_destroy(rac_handle_t handle);

/**
 * @brief Free a TTS result
 *
 * @param result Result to free
 */
RAC_API void rac_tts_result_free(rac_tts_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_SERVICE_H */
