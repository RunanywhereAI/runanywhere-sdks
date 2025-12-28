/**
 * @file rac_vad_onnx.h
 * @brief RunAnywhere Commons - ONNX Backend for VAD
 *
 * C wrapper around runanywhere-core's ONNX VAD backend.
 * Mirrors Swift's VADService implementation pattern.
 */

#ifndef RAC_VAD_ONNX_H
#define RAC_VAD_ONNX_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_vad.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_ONNX_BUILDING)
#if defined(_WIN32)
#define RAC_ONNX_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_ONNX_API __attribute__((visibility("default")))
#else
#define RAC_ONNX_API
#endif
#else
#define RAC_ONNX_API
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * ONNX VAD configuration.
 */
typedef struct rac_vad_onnx_config {
    /** Sample rate (default: 16000) */
    int32_t sample_rate;

    /** Energy threshold for detection (0.0 to 1.0) */
    float energy_threshold;

    /** Frame length in seconds (default: 0.032 = 32ms) */
    float frame_length;

    /** Number of threads (0 = auto) */
    int32_t num_threads;
} rac_vad_onnx_config_t;

/**
 * Default ONNX VAD configuration.
 */
static const rac_vad_onnx_config_t RAC_VAD_ONNX_CONFIG_DEFAULT = {
    .sample_rate = 16000, .energy_threshold = 0.5f, .frame_length = 0.032f, .num_threads = 0};

// =============================================================================
// ONNX VAD API
// =============================================================================

/**
 * Creates an ONNX VAD service.
 *
 * @param model_path Path to the VAD model (can be NULL for built-in)
 * @param config ONNX-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_create(const char* model_path,
                                              const rac_vad_onnx_config_t* config,
                                              rac_handle_t* out_handle);

/**
 * Processes audio samples for voice activity.
 *
 * @param handle Service handle
 * @param samples Float32 PCM samples
 * @param num_samples Number of samples
 * @param out_is_speech Output: Whether speech was detected
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_process(rac_handle_t handle, const float* samples,
                                               size_t num_samples, rac_bool_t* out_is_speech);

/**
 * Starts continuous VAD processing.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_start(rac_handle_t handle);

/**
 * Stops continuous VAD processing.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_stop(rac_handle_t handle);

/**
 * Resets VAD state.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_reset(rac_handle_t handle);

/**
 * Sets the energy threshold.
 *
 * @param handle Service handle
 * @param threshold New threshold (0.0 to 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_vad_onnx_set_threshold(rac_handle_t handle, float threshold);

/**
 * Checks if speech is currently active.
 *
 * @param handle Service handle
 * @return RAC_TRUE if speech is active
 */
RAC_ONNX_API rac_bool_t rac_vad_onnx_is_speech_active(rac_handle_t handle);

/**
 * Destroys an ONNX VAD service.
 *
 * @param handle Service handle to destroy
 */
RAC_ONNX_API void rac_vad_onnx_destroy(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the ONNX backend with the commons module and service registries.
 *
 * Should be called once during SDK initialization.
 * This registers:
 * - Module: "onnx" with STT, TTS, VAD capabilities
 * - Service providers: ONNX STT, TTS, VAD providers
 *
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_backend_onnx_register(void);

/**
 * Unregisters the ONNX backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ONNX_H */
