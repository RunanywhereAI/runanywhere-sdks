/**
 * @file rac_tts_onnx.h
 * @brief RunAnywhere Commons - ONNX Backend for TTS
 *
 * C wrapper around runanywhere-core's ONNX TTS backend.
 * Mirrors Swift's ONNXTTSService implementation.
 *
 * See: Sources/ONNXRuntime/ONNXTTSService.swift
 */

#ifndef RAC_TTS_ONNX_H
#define RAC_TTS_ONNX_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_tts.h"

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
 * ONNX TTS configuration.
 */
typedef struct rac_tts_onnx_config {
    /** Number of threads (0 = auto) */
    int32_t num_threads;

    /** Enable CoreML on Apple platforms */
    rac_bool_t use_coreml;

    /** Default sample rate */
    int32_t sample_rate;
} rac_tts_onnx_config_t;

/**
 * Default ONNX TTS configuration.
 */
static const rac_tts_onnx_config_t RAC_TTS_ONNX_CONFIG_DEFAULT = {
    .num_threads = 0, .use_coreml = RAC_TRUE, .sample_rate = 22050};

// =============================================================================
// ONNX TTS API
// =============================================================================

/**
 * Creates an ONNX TTS service.
 *
 * @param model_path Path to the model directory or file
 * @param config ONNX-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_tts_onnx_create(const char* model_path,
                                              const rac_tts_onnx_config_t* config,
                                              rac_handle_t* out_handle);

/**
 * Synthesizes text to audio.
 *
 * @param handle Service handle
 * @param text Text to synthesize
 * @param options TTS options (can be NULL for defaults)
 * @param out_result Output: Synthesis result
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_tts_onnx_synthesize(rac_handle_t handle, const char* text,
                                                  const rac_tts_options_t* options,
                                                  rac_tts_result_t* out_result);

/**
 * Gets available voices.
 *
 * @param handle Service handle
 * @param out_voices Output: Array of voice names (caller must free)
 * @param out_count Output: Number of voices
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_tts_onnx_get_voices(rac_handle_t handle, char*** out_voices,
                                                  size_t* out_count);

/**
 * Stops ongoing synthesis.
 *
 * @param handle Service handle
 */
RAC_ONNX_API void rac_tts_onnx_stop(rac_handle_t handle);

/**
 * Destroys an ONNX TTS service.
 *
 * @param handle Service handle to destroy
 */
RAC_ONNX_API void rac_tts_onnx_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_ONNX_H */
