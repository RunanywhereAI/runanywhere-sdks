/**
 * @file rac_stt_service.h
 * @brief RunAnywhere Commons - STT Service Interface
 *
 * Defines the generic STT service API and vtable for multi-backend dispatch.
 * Backends (ONNX, Whisper, etc.) implement the vtable and register
 * with the service registry.
 */

#ifndef RAC_STT_SERVICE_H
#define RAC_STT_SERVICE_H

#include "rac_error.h"
#include "rac_stt_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * STT Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_stt_service_ops {
    /** Initialize the service with a model path */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /** Transcribe audio (batch mode) */
    rac_result_t (*transcribe)(void* impl, const void* audio_data, size_t audio_size,
                               const rac_stt_options_t* options, rac_stt_result_t* out_result);

    /** Stream transcription for real-time processing */
    rac_result_t (*transcribe_stream)(void* impl, const void* audio_data, size_t audio_size,
                                      const rac_stt_options_t* options,
                                      rac_stt_stream_callback_t callback, void* user_data);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_stt_info_t* out_info);

    /** Cleanup/unload model (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);
} rac_stt_service_ops_t;

/**
 * STT Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_stt_service {
    /** Vtable with backend operations */
    const rac_stt_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model ID for reference */
    const char* model_id;
} rac_stt_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create an STT service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param model_path Path to the model file (can be NULL for some providers)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_create(const char* model_path, rac_handle_t* out_handle);

/**
 * @brief Initialize an STT service
 *
 * @param handle Service handle
 * @param model_path Path to the model file (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_initialize(rac_handle_t handle, const char* model_path);

/**
 * @brief Transcribe audio data (batch mode)
 *
 * @param handle Service handle
 * @param audio_data Audio data buffer
 * @param audio_size Size of audio data in bytes
 * @param options Transcription options (can be NULL for defaults)
 * @param out_result Output: Transcription result (caller must free with rac_stt_result_free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_transcribe(rac_handle_t handle, const void* audio_data,
                                        size_t audio_size, const rac_stt_options_t* options,
                                        rac_stt_result_t* out_result);

/**
 * @brief Stream transcription for real-time processing
 *
 * @param handle Service handle
 * @param audio_data Audio chunk data
 * @param audio_size Size of audio chunk
 * @param options Transcription options
 * @param callback Callback for partial results
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_transcribe_stream(rac_handle_t handle, const void* audio_data,
                                               size_t audio_size, const rac_stt_options_t* options,
                                               rac_stt_stream_callback_t callback, void* user_data);

/**
 * @brief Get service information
 *
 * @param handle Service handle
 * @param out_info Output: Service information
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_get_info(rac_handle_t handle, rac_stt_info_t* out_info);

/**
 * @brief Cleanup and release resources
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_stt_cleanup(rac_handle_t handle);

/**
 * @brief Destroy an STT service instance
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_stt_destroy(rac_handle_t handle);

/**
 * @brief Free an STT result
 *
 * @param result Result to free
 */
RAC_API void rac_stt_result_free(rac_stt_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_SERVICE_H */
