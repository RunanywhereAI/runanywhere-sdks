/**
 * @file rac_tts_service.h
 * @brief RunAnywhere Commons - TTS Service Interface
 *
 * Defines the generic TTS service API and vtable for multi-backend dispatch.
 * Backends (ONNX, Platform/System TTS, etc.) implement the vtable and register
 * with the service registry.
 */

#ifndef RAC_TTS_SERVICE_H
#define RAC_TTS_SERVICE_H

#include <RACommons/rac_error.h>
#include <RACommons/rac_tts_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SERVICE VTABLE - Backend implementations provide this
// =============================================================================

/**
 * TTS Service operations vtable.
 * Each backend implements these functions and provides a static vtable.
 */
typedef struct rac_tts_service_ops {
    /** Initialize the service */
    rac_result_t (*initialize)(void* impl);

    /** Synthesize text to audio (blocking) */
    rac_result_t (*synthesize)(void* impl, const char* text, const rac_tts_options_t* options,
                               rac_tts_result_t* out_result);

    /** Stream synthesis for long text */
    rac_result_t (*synthesize_stream)(void* impl, const char* text,
                                      const rac_tts_options_t* options,
                                      rac_tts_stream_callback_t callback, void* user_data);

    /** Stop current synthesis */
    rac_result_t (*stop)(void* impl);

    /** Get service info */
    rac_result_t (*get_info)(void* impl, rac_tts_info_t* out_info);

    /** Cleanup/release resources (keeps service alive) */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service */
    void (*destroy)(void* impl);
} rac_tts_service_ops_t;

/**
 * TTS Service instance.
 * Contains vtable pointer and backend-specific implementation.
 */
typedef struct rac_tts_service {
    /** Vtable with backend operations */
    const rac_tts_service_ops_t* ops;

    /** Backend-specific implementation handle */
    void* impl;

    /** Model/voice ID for reference */
    const char* model_id;
} rac_tts_service_t;

// =============================================================================
// PUBLIC API - Generic service functions
// =============================================================================

/**
 * @brief Create a TTS service
 *
 * Routes through service registry to find appropriate backend.
 *
 * @param voice_id Voice/model identifier (registry ID or path)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_create(const char* voice_id, rac_handle_t* out_handle);

/**
 * @brief Initialize a TTS service
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_initialize(rac_handle_t handle);

/**
 * @brief Synthesize text to audio
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
