/**
 * @file rac_stt_whisperkit_coreml.h
 * @brief RunAnywhere Commons - WhisperKit CoreML STT Backend (Apple Neural Engine)
 *
 * C API for the WhisperKit CoreML STT backend. The actual inference runs in
 * Swift via WhisperKit + CoreML; C++ provides the callback infrastructure,
 * vtable dispatch, and automatic telemetry through the standard stt_component
 * pipeline.
 *
 * This backend is Apple-only. On non-Apple platforms it is never registered.
 */

#ifndef RAC_STT_WHISPERKIT_COREML_H
#define RAC_STT_WHISPERKIT_COREML_H

#include "rac_types.h"
#include "rac_stt_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// SWIFT CALLBACK TYPES
// =============================================================================

/**
 * Callback to check if WhisperKit CoreML can handle a model ID.
 *
 * @param model_id Model identifier to check (can be NULL)
 * @param user_data User-provided context
 * @return RAC_TRUE if WhisperKit CoreML can handle this model
 */
typedef rac_bool_t (*rac_whisperkit_coreml_stt_can_handle_fn)(const char* model_id,
                                                               void* user_data);

/**
 * Callback to load a WhisperKit CoreML model.
 *
 * @param model_path Path to model directory containing .mlmodelc files
 * @param model_id Model identifier
 * @param user_data User-provided context
 * @return Opaque handle to loaded service, or NULL on failure
 */
typedef rac_handle_t (*rac_whisperkit_coreml_stt_create_fn)(const char* model_path,
                                                             const char* model_id,
                                                             void* user_data);

/**
 * Callback to transcribe audio via WhisperKit CoreML.
 *
 * @param handle Service handle from create
 * @param audio_data PCM audio data (Int16, 16kHz mono)
 * @param audio_size Size of audio data in bytes
 * @param options Transcription options
 * @param out_result Output: transcription result (text must be strdup'd)
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_whisperkit_coreml_stt_transcribe_fn)(rac_handle_t handle,
                                                                 const void* audio_data,
                                                                 size_t audio_size,
                                                                 const rac_stt_options_t* options,
                                                                 rac_stt_result_t* out_result,
                                                                 void* user_data);

/**
 * Callback to destroy/unload a WhisperKit CoreML service.
 *
 * @param handle Service handle to destroy
 * @param user_data User-provided context
 */
typedef void (*rac_whisperkit_coreml_stt_destroy_fn)(rac_handle_t handle, void* user_data);

/**
 * Swift callbacks for WhisperKit CoreML STT operations.
 */
typedef struct rac_whisperkit_coreml_stt_callbacks {
    rac_whisperkit_coreml_stt_can_handle_fn can_handle;
    rac_whisperkit_coreml_stt_create_fn create;
    rac_whisperkit_coreml_stt_transcribe_fn transcribe;
    rac_whisperkit_coreml_stt_destroy_fn destroy;
    void* user_data;
} rac_whisperkit_coreml_stt_callbacks_t;

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

/**
 * Sets the Swift callbacks for WhisperKit CoreML STT operations.
 * Must be called before rac_backend_whisperkit_coreml_register().
 *
 * @param callbacks Callback functions (copied internally)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t
rac_whisperkit_coreml_stt_set_callbacks(const rac_whisperkit_coreml_stt_callbacks_t* callbacks);

/**
 * Gets the current Swift callbacks.
 *
 * @return Pointer to callbacks, or NULL if not set
 */
RAC_API const rac_whisperkit_coreml_stt_callbacks_t*
rac_whisperkit_coreml_stt_get_callbacks(void);

/**
 * Checks if Swift callbacks are registered.
 *
 * @return RAC_TRUE if callbacks are available
 */
RAC_API rac_bool_t rac_whisperkit_coreml_stt_is_available(void);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Register the WhisperKit CoreML backend with the module and service registries.
 * Swift callbacks must be set via rac_whisperkit_coreml_stt_set_callbacks() first.
 *
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_backend_whisperkit_coreml_register(void);

/**
 * Unregister the WhisperKit CoreML backend.
 *
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_backend_whisperkit_coreml_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_WHISPERKIT_COREML_H */
