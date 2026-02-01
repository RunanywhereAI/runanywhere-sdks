/**
 * @file rac_onnx_npu.h
 * @brief RunAnywhere Commons - ONNX NPU Acceleration API
 *
 * Public C API for NPU (Qualcomm QNN HTP) accelerated inference.
 * Provides functions for:
 * - NPU detection and device information
 * - NPU-accelerated TTS (hybrid execution for Kokoro)
 * - Model validation for NPU compatibility
 * - Execution statistics and profiling
 *
 * IMPORTANT: For Kokoro TTS, ISTFT is NOT supported on QNN HTP.
 * Use the hybrid execution API (rac_tts_onnx_create_hybrid) which
 * runs the encoder on NPU and vocoder on CPU.
 */

#ifndef RAC_ONNX_NPU_H
#define RAC_ONNX_NPU_H

#include "rac/backends/rac_qnn_config.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

/** Opaque handle to split model executor */
typedef void* rac_split_executor_t;

/** Execution statistics for split model executor */
typedef struct rac_split_exec_stats {
    float encoder_inference_ms;   /**< Time spent in encoder (NPU) */
    float vocoder_inference_ms;   /**< Time spent in vocoder (CPU) */
    float total_inference_ms;     /**< Total inference time */
    uint64_t total_inferences;    /**< Number of inferences run */
    rac_bool_t encoder_on_npu;    /**< Whether encoder ran on NPU */
} rac_split_exec_stats_t;

// =============================================================================
// NPU DETECTION
// =============================================================================

/**
 * @brief Check if Qualcomm NPU (QNN HTP) is available on this device
 *
 * Returns true if:
 * - Device has a supported Qualcomm SoC (SM8550, SM8650, etc.)
 * - QNN libraries are available
 * - Hexagon architecture is V68 or newer
 *
 * @return RAC_TRUE if NPU available, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_onnx_is_npu_available(void);

/**
 * @brief Get NPU device information as JSON string
 *
 * Returns a JSON object with:
 * - name: SoC name (e.g., "SM8650")
 * - soc_id: Qualcomm SoC ID
 * - hexagon_arch: Hexagon architecture version
 * - marketing_name: Marketing name (e.g., "Snapdragon 8 Gen 3")
 * - htp_available: Whether HTP backend is available
 * - htp_tops: Estimated TOPS (tera operations per second)
 *
 * @param out_json Output buffer for JSON string
 * @param json_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_onnx_get_npu_info_json(char* out_json, size_t json_size);

/**
 * @brief Get detailed SoC information
 *
 * @param out_info Output structure for SoC info
 * @return RAC_SUCCESS or RAC_ERROR_QNN_NOT_AVAILABLE
 */
RAC_API rac_result_t rac_onnx_get_soc_info(rac_soc_info_t* out_info);

// =============================================================================
// NPU-ENABLED TTS (HYBRID EXECUTION)
// =============================================================================

/**
 * @brief Create TTS service with hybrid NPU+CPU execution
 *
 * This is the RECOMMENDED approach for Kokoro TTS and similar models
 * that use ISTFT in their vocoder (ISTFT not supported on NPU).
 *
 * The pipeline runs:
 * - Encoder on NPU (QNN HTP) for ~85-90% of compute
 * - Vocoder on CPU for ISTFT and audio output
 *
 * @param encoder_path Path to encoder ONNX model (QDQ quantized for NPU)
 * @param vocoder_path Path to vocoder ONNX model (fp32 for CPU)
 * @param qnn_config QNN configuration (NULL for defaults)
 * @param out_handle Output service handle
 * @return RAC_SUCCESS or error code
 *
 * @note Use rac_tts_synthesize() from rac_tts_service.h for synthesis
 * @note Use rac_tts_destroy() to cleanup
 */
RAC_API rac_result_t rac_tts_onnx_create_hybrid(const char* encoder_path, const char* vocoder_path,
                                                const rac_qnn_config_t* qnn_config,
                                                rac_handle_t* out_handle);

/**
 * @brief Create TTS service with NPU acceleration (single model)
 *
 * WARNING: For Kokoro TTS, use rac_tts_onnx_create_hybrid instead.
 * Single model loading will fail if the model contains ISTFT.
 *
 * @param model_path Path to QDQ-quantized ONNX model
 * @param qnn_config QNN configuration (NULL for defaults)
 * @param out_handle Output service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_onnx_create_npu(const char* model_path,
                                             const rac_qnn_config_t* qnn_config,
                                             rac_handle_t* out_handle);

// =============================================================================
// NPU STATISTICS
// =============================================================================

/**
 * @brief Get NPU execution statistics for a TTS service
 *
 * Returns timing breakdown, operator distribution, and memory usage.
 *
 * @param handle TTS service handle (from rac_tts_onnx_create_hybrid)
 * @param out_stats Output statistics structure
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_tts_onnx_get_npu_stats(rac_handle_t handle, rac_npu_stats_t* out_stats);

/**
 * @brief Check if a TTS service is using NPU acceleration
 *
 * @param handle TTS service handle
 * @return RAC_TRUE if NPU active, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_tts_onnx_is_npu_active(rac_handle_t handle);

// =============================================================================
// MODEL VALIDATION
// =============================================================================

/**
 * @brief Validate that a model can run on NPU
 *
 * Checks:
 * 1. QDQ quantization format (required for NPU)
 * 2. Static shapes (dynamic dimensions not supported)
 * 3. All operators supported on QNN HTP
 *
 * @param model_path Path to ONNX model
 * @param out_result Validation result details
 * @return RAC_SUCCESS if model is NPU-ready, error code otherwise
 *
 * @note For thorough validation, use the Python tool:
 *       python tools/model_splitting/analyze_onnx_ops.py <model_path>
 */
RAC_API rac_result_t rac_onnx_validate_model_for_npu(const char* model_path,
                                                     rac_model_validation_result_t* out_result);

/**
 * @brief Get list of QNN HTP supported ONNX operators
 *
 * Returns a comma-separated list of supported operator types.
 *
 * @param out_ops Output buffer for operator list
 * @param ops_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_onnx_get_npu_supported_ops(char* out_ops, size_t ops_size);

// =============================================================================
// CONTEXT CACHING
// =============================================================================

/**
 * @brief Generate pre-compiled context binary for faster model loads
 *
 * Context caching saves the compiled QNN graph to disk, significantly
 * reducing subsequent model load times (from seconds to milliseconds).
 *
 * @param model_path Path to ONNX model
 * @param qnn_config QNN configuration
 * @param output_path Path for context binary output (.ctx file)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_onnx_generate_context_binary(const char* model_path,
                                                      const rac_qnn_config_t* qnn_config,
                                                      const char* output_path);

/**
 * @brief Check if a context binary exists for a model
 *
 * @param model_path Path to ONNX model
 * @param cache_dir Cache directory (NULL for default)
 * @return RAC_TRUE if context binary exists, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_onnx_has_context_binary(const char* model_path, const char* cache_dir);

// =============================================================================
// SPLIT MODEL EXECUTOR (Low-level API)
// =============================================================================

/**
 * @brief Create split model executor for direct hybrid inference
 *
 * This is a lower-level API for advanced use cases. For typical TTS,
 * use rac_tts_onnx_create_hybrid instead.
 *
 * @param config Split model configuration
 * @param qnn_config QNN configuration
 * @param out_executor Output executor handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_split_executor_create(const rac_split_model_config_t* config,
                                               const rac_qnn_config_t* qnn_config,
                                               rac_split_executor_t* out_executor);

/**
 * @brief Run hybrid inference (encoder on NPU, vocoder on CPU)
 *
 * @param executor Split executor handle
 * @param phoneme_ids Input phoneme IDs
 * @param phoneme_count Number of phonemes
 * @param style_vector Style embedding (256 floats)
 * @param out_audio Output audio buffer (caller allocated)
 * @param out_audio_samples Number of audio samples written
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_split_executor_run(rac_split_executor_t executor,
                                            const int64_t* phoneme_ids, size_t phoneme_count,
                                            const float* style_vector, float* out_audio,
                                            size_t* out_audio_samples);

/**
 * @brief Get execution statistics from split executor
 *
 * @param executor Split executor handle
 * @param out_stats Output statistics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_split_executor_get_stats(rac_split_executor_t executor,
                                                  rac_split_exec_stats_t* out_stats);

/**
 * @brief Destroy split model executor
 *
 * @param executor Split executor handle
 */
RAC_API void rac_split_executor_destroy(rac_split_executor_t executor);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ONNX_NPU_H */
