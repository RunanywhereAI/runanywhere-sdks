/**
 * @file rac_wakeword_onnx.h
 * @brief RunAnywhere Commons - ONNX Backend for Wake Word Detection
 *
 * ONNX Runtime backend for wake word detection using openWakeWord models.
 *
 * Model Requirements:
 * - openWakeWord ONNX models (https://github.com/dscripka/openWakeWord)
 * - Silero VAD ONNX model for pre-filtering (optional but recommended)
 *
 * Architecture:
 * - Uses ONNX Runtime for inference
 * - Supports multiple wake word models simultaneously
 * - Integrates with Silero VAD for speech filtering
 */

#ifndef RAC_WAKEWORD_ONNX_H
#define RAC_WAKEWORD_ONNX_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/wakeword/rac_wakeword.h"

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
// ONNX-SPECIFIC CONFIGURATION
// =============================================================================

/**
 * @brief ONNX backend configuration for wake word detection
 */
typedef struct rac_wakeword_onnx_config {
    /** Sample rate in Hz (default: 16000) */
    int32_t sample_rate;

    /** Detection threshold (0.0 - 1.0, default: 0.5) */
    float threshold;

    /** Number of ONNX Runtime threads (0 = auto) */
    int32_t num_threads;

    /** Frame length in samples (default: 1280 = 80ms @ 16kHz) */
    int32_t frame_length;

    /** Enable graph optimization */
    rac_bool_t enable_optimization;

    /** Path to embedding model (required for openWakeWord) */
    const char* embedding_model_path;

    /** Path to melspectrogram model (required for openWakeWord) */
    const char* melspec_model_path;
} rac_wakeword_onnx_config_t;

/**
 * @brief Default ONNX configuration
 */
static const rac_wakeword_onnx_config_t RAC_WAKEWORD_ONNX_CONFIG_DEFAULT = {
    .sample_rate = 16000,
    .threshold = 0.5f,
    .num_threads = 1,
    .frame_length = 1280,  // 80ms @ 16kHz
    .enable_optimization = RAC_TRUE,
    .embedding_model_path = NULL,
    .melspec_model_path = NULL
};

// =============================================================================
// ONNX WAKE WORD API
// =============================================================================

/**
 * @brief Create ONNX wake word detector
 *
 * @param config Configuration (NULL for defaults)
 * @param[out] out_handle Output: Detector handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_create(
    const rac_wakeword_onnx_config_t* config,
    rac_handle_t* out_handle);

/**
 * @brief Initialize shared models (embedding + melspec)
 *
 * openWakeWord uses shared feature extraction models. Call this before
 * loading any wake word models.
 *
 * @param handle Detector handle
 * @param embedding_model_path Path to embedding model ONNX file
 * @param melspec_model_path Path to melspectrogram model ONNX file (optional)
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_init_shared_models(
    rac_handle_t handle,
    const char* embedding_model_path,
    const char* melspec_model_path);

/**
 * @brief Load a wake word classification model
 *
 * @param handle Detector handle
 * @param model_path Path to wake word ONNX model
 * @param model_id Unique model identifier
 * @param wake_word Human-readable wake word
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_load_model(
    rac_handle_t handle,
    const char* model_path,
    const char* model_id,
    const char* wake_word);

/**
 * @brief Load Silero VAD model
 *
 * @param handle Detector handle
 * @param vad_model_path Path to Silero VAD ONNX model
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_load_vad(
    rac_handle_t handle,
    const char* vad_model_path);

/**
 * @brief Process audio frame
 *
 * @param handle Detector handle
 * @param samples Float audio samples (16kHz PCM)
 * @param num_samples Number of samples
 * @param[out] out_detected Index of detected keyword (-1 if none)
 * @param[out] out_confidence Detection confidence (0.0 - 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_process(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    int32_t* out_detected,
    float* out_confidence);

/**
 * @brief Process audio frame with VAD result
 *
 * @param handle Detector handle
 * @param samples Float audio samples
 * @param num_samples Number of samples
 * @param[out] out_detected Index of detected keyword (-1 if none)
 * @param[out] out_confidence Detection confidence
 * @param[out] out_vad_speech Whether VAD detected speech
 * @param[out] out_vad_confidence VAD confidence
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_process_with_vad(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    int32_t* out_detected,
    float* out_confidence,
    rac_bool_t* out_vad_speech,
    float* out_vad_confidence);

/**
 * @brief Set detection threshold
 *
 * @param handle Detector handle
 * @param threshold New threshold (0.0 - 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_set_threshold(
    rac_handle_t handle,
    float threshold);

/**
 * @brief Reset detector state
 *
 * @param handle Detector handle
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_reset(rac_handle_t handle);

/**
 * @brief Unload a wake word model
 *
 * @param handle Detector handle
 * @param model_id Model identifier to unload
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_wakeword_onnx_unload_model(
    rac_handle_t handle,
    const char* model_id);

/**
 * @brief Destroy ONNX wake word detector
 *
 * @param handle Detector handle to destroy
 */
RAC_ONNX_API void rac_wakeword_onnx_destroy(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * @brief Register ONNX wake word backend
 *
 * Call this during initialization to enable ONNX-based wake word detection.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_backend_wakeword_onnx_register(void);

/**
 * @brief Unregister ONNX wake word backend
 *
 * @return RAC_SUCCESS or error code
 */
RAC_ONNX_API rac_result_t rac_backend_wakeword_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_WAKEWORD_ONNX_H */
