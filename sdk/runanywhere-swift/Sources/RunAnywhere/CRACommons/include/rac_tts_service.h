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

#include "rac_error.h"
#include "rac_tts_types.h"

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

    /**
     * Allocate a backend-specific impl for a new TTS service instance.
     * v3 replacement for the legacy rac_service_provider_t::create callback.
     * See rac_llm_service_ops_t::create for the full semantics.
     *
     * For TTS, `model_id` is a voice ID or voice-model path.
     */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);

    /**
     * Enumerate synthesis languages the backend currently supports (derived
     * from the loaded voice(s)) as a JSON array, e.g. "[\"en\",\"de\"]".
     * Callee allocates with malloc; caller MUST free via free(). Leave this
     * slot NULL to return RAC_ERROR_NOT_SUPPORTED from the generic dispatcher.
     */
    rac_result_t (*get_languages)(void* impl, char** out_json);
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

/**
 * @brief Get supported languages for the loaded TTS model as a JSON array string.
 *
 * Dispatches through the backend vtable. Returns RAC_ERROR_NOT_SUPPORTED if the
 * backend does not enumerate languages.
 *
 * @param handle      Service handle
 * @param out_json    Output: malloc'd JSON string (e.g. "[\"en\",\"de\"]"). Caller frees.
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_get_languages(rac_handle_t handle, char** out_json);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_SERVICE_H */
