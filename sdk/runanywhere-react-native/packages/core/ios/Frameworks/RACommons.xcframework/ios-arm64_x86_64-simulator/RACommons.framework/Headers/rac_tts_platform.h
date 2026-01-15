/**
 * @file rac_tts_platform.h
 * @brief RunAnywhere Commons - Platform TTS Backend (System TTS)
 *
 * C API for platform-native TTS services. On Apple platforms, this uses
 * AVSpeechSynthesizer. The actual implementation is in Swift, with C++
 * providing the registration and callback infrastructure.
 *
 * This backend follows the same pattern as ONNX TTS backend, but delegates
 * to Swift via function pointer callbacks since AVSpeechSynthesizer is
 * an Apple-only framework.
 */

#ifndef RAC_TTS_PLATFORM_H
#define RAC_TTS_PLATFORM_H

#include <RACommons/rac_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/** Opaque handle to platform TTS service */
typedef struct rac_tts_platform* rac_tts_platform_handle_t;

/**
 * Platform TTS configuration.
 */
typedef struct rac_tts_platform_config {
    /** Voice identifier (can be NULL for default) */
    const char* voice_id;
    /** Language code (e.g., "en-US") */
    const char* language;
    /** Reserved for future use */
    void* reserved;
} rac_tts_platform_config_t;

/**
 * Synthesis options for platform TTS.
 */
typedef struct rac_tts_platform_options {
    /** Speech rate (0.5 = half speed, 1.0 = normal, 2.0 = double) */
    float rate;
    /** Pitch multiplier (0.5 = low, 1.0 = normal, 2.0 = high) */
    float pitch;
    /** Volume (0.0 = silent, 1.0 = full) */
    float volume;
    /** Voice identifier override (can be NULL) */
    const char* voice_id;
    /** Reserved for future options */
    void* reserved;
} rac_tts_platform_options_t;

// =============================================================================
// SWIFT CALLBACK TYPES
// =============================================================================

/**
 * Callback to check if platform TTS can handle a voice ID.
 * Implemented in Swift.
 *
 * @param voice_id Voice identifier to check (can be NULL)
 * @param user_data User-provided context
 * @return RAC_TRUE if this backend can handle the voice
 */
typedef rac_bool_t (*rac_platform_tts_can_handle_fn)(const char* voice_id, void* user_data);

/**
 * Callback to create platform TTS service.
 * Implemented in Swift.
 *
 * @param config Configuration options
 * @param user_data User-provided context
 * @return Handle to created service (Swift object pointer), or NULL on failure
 */
typedef rac_handle_t (*rac_platform_tts_create_fn)(const rac_tts_platform_config_t* config,
                                                   void* user_data);

/**
 * Callback to synthesize speech.
 * Implemented in Swift.
 *
 * @param handle Service handle from create
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_platform_tts_synthesize_fn)(rac_handle_t handle, const char* text,
                                                       const rac_tts_platform_options_t* options,
                                                       void* user_data);

/**
 * Callback to stop speech.
 * Implemented in Swift.
 *
 * @param handle Service handle
 * @param user_data User-provided context
 */
typedef void (*rac_platform_tts_stop_fn)(rac_handle_t handle, void* user_data);

/**
 * Callback to destroy platform TTS service.
 * Implemented in Swift.
 *
 * @param handle Service handle to destroy
 * @param user_data User-provided context
 */
typedef void (*rac_platform_tts_destroy_fn)(rac_handle_t handle, void* user_data);

/**
 * Swift callbacks for platform TTS operations.
 */
typedef struct rac_platform_tts_callbacks {
    rac_platform_tts_can_handle_fn can_handle;
    rac_platform_tts_create_fn create;
    rac_platform_tts_synthesize_fn synthesize;
    rac_platform_tts_stop_fn stop;
    rac_platform_tts_destroy_fn destroy;
    void* user_data;
} rac_platform_tts_callbacks_t;

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

/**
 * Sets the Swift callbacks for platform TTS operations.
 * Must be called before using platform TTS services.
 *
 * @param callbacks Callback functions (copied internally)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_platform_tts_set_callbacks(const rac_platform_tts_callbacks_t* callbacks);

/**
 * Gets the current Swift callbacks.
 *
 * @return Pointer to callbacks, or NULL if not set
 */
RAC_API const rac_platform_tts_callbacks_t* rac_platform_tts_get_callbacks(void);

/**
 * Checks if Swift callbacks are registered.
 *
 * @return RAC_TRUE if callbacks are available
 */
RAC_API rac_bool_t rac_platform_tts_is_available(void);

// =============================================================================
// SERVICE API
// =============================================================================

/**
 * Creates a platform TTS service.
 *
 * @param config Configuration options (can be NULL for defaults)
 * @param out_handle Output: Service handle
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_tts_platform_create(const rac_tts_platform_config_t* config,
                                             rac_tts_platform_handle_t* out_handle);

/**
 * Destroys a platform TTS service.
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_tts_platform_destroy(rac_tts_platform_handle_t handle);

/**
 * Synthesizes speech using platform TTS.
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options Synthesis options (can be NULL for defaults)
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_tts_platform_synthesize(rac_tts_platform_handle_t handle, const char* text,
                                                 const rac_tts_platform_options_t* options);

/**
 * Stops current speech synthesis.
 *
 * @param handle Service handle
 */
RAC_API void rac_tts_platform_stop(rac_tts_platform_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_PLATFORM_H */
