/**
 * @file rac_qnn_config.h
 * @brief RunAnywhere Commons - QNN (Qualcomm Neural Network) Configuration
 *
 * Configuration types and APIs for Qualcomm QNN Execution Provider support.
 * QNN enables NPU (Neural Processing Unit) acceleration on Qualcomm Snapdragon SoCs.
 *
 * Supported SoCs:
 *   - SM8650 (Snapdragon 8 Gen 3) - V75 Hexagon architecture
 *   - SM8550 (Snapdragon 8 Gen 2) - V73 Hexagon architecture
 *   - SM7550 (Snapdragon 7+ Gen 3) - V73 Hexagon architecture
 *
 * IMPORTANT: ISTFT (Inverse Short-Time Fourier Transform) is NOT supported on QNN HTP.
 * Models using ISTFT (e.g., Kokoro TTS) require hybrid execution with model splitting:
 *   - Encoder runs on NPU (QNN HTP)
 *   - Vocoder runs on CPU (contains ISTFT)
 */

#ifndef RAC_QNN_CONFIG_H
#define RAC_QNN_CONFIG_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// QNN BACKEND TYPES
// =============================================================================

/**
 * @brief QNN backend type for execution provider selection
 */
typedef enum rac_qnn_backend {
    RAC_QNN_BACKEND_CPU = 0,      /**< QNN CPU backend (fallback) */
    RAC_QNN_BACKEND_GPU = 1,      /**< QNN GPU backend (Adreno) */
    RAC_QNN_BACKEND_HTP = 2,      /**< QNN HTP backend (Hexagon NPU) - recommended */
    RAC_QNN_BACKEND_DSP = 3,      /**< QNN DSP backend (legacy Hexagon) */
} rac_qnn_backend_t;

/**
 * @brief HTP (Hexagon Tensor Processor) performance mode
 *
 * Performance modes control the power/performance trade-off for NPU execution.
 */
typedef enum rac_htp_performance_mode {
    RAC_HTP_PERF_DEFAULT = 0,           /**< Default performance mode */
    RAC_HTP_PERF_BURST = 1,             /**< Maximum performance, high power consumption */
    RAC_HTP_PERF_BALANCED = 2,          /**< Balanced performance and power */
    RAC_HTP_PERF_HIGH_PERFORMANCE = 3,  /**< Sustained high performance */
    RAC_HTP_PERF_POWER_SAVER = 4,       /**< Power saving mode, reduced performance */
    RAC_HTP_PERF_SUSTAINED_HIGH = 5,    /**< Sustained high without thermal throttling */
    RAC_HTP_PERF_LOW_BALANCED = 6,      /**< Low power balanced mode */
    RAC_HTP_PERF_EXTREME_POWER_SAVER = 7, /**< Extreme power saving mode */
} rac_htp_performance_mode_t;

/**
 * @brief HTP precision mode for inference
 */
typedef enum rac_htp_precision {
    RAC_HTP_PRECISION_INT8 = 0,    /**< INT8 quantized (best performance) */
    RAC_HTP_PRECISION_FP16 = 1,    /**< FP16 half precision */
} rac_htp_precision_t;

/**
 * @brief NPU execution strategy for TTS/STT models
 *
 * IMPORTANT: For Kokoro-82M and similar models with ISTFT, HYBRID is the ONLY valid strategy
 * because ISTFT is not supported on QNN HTP. NPU_REQUIRED will FAIL for these models.
 */
typedef enum rac_npu_strategy {
    RAC_NPU_STRATEGY_CPU_ONLY = 0,      /**< No NPU, use CPU only */
    RAC_NPU_STRATEGY_NPU_PREFERRED = 1, /**< Try NPU, fallback to CPU for unsupported ops */
    RAC_NPU_STRATEGY_NPU_REQUIRED = 2,  /**< NPU only, fail if ANY op can't run on NPU */
    RAC_NPU_STRATEGY_HYBRID = 3,        /**< NPU for encoder, CPU for vocoder (DEFAULT for Kokoro) */
} rac_npu_strategy_t;

// =============================================================================
// QNN CONFIGURATION
// =============================================================================

/**
 * @brief QNN execution configuration
 *
 * Configuration for QNN Execution Provider session options.
 * Used when creating NPU-accelerated inference sessions.
 */
typedef struct rac_qnn_config {
    /** Backend selection (HTP recommended for NPU) */
    rac_qnn_backend_t backend;

    /** Performance mode for HTP backend */
    rac_htp_performance_mode_t performance_mode;

    /** Precision mode for HTP inference */
    rac_htp_precision_t precision;

    /** VTCM memory allocation in MB (0 = default, typically 4-8MB) */
    int32_t vtcm_mb;

    /**
     * Disable CPU fallback - fail if any op can't run on NPU.
     *
     * WARNING: Set to RAC_FALSE for Kokoro TTS (hybrid mode required).
     * ISTFT is not supported on HTP, so vocoder must run on CPU.
     * Use RAC_TRUE only for encoder-only validation.
     */
    rac_bool_t disable_cpu_fallback;

    /** Enable context caching for faster subsequent model loads */
    rac_bool_t enable_context_cache;

    /** Context cache directory path (NULL = use default cache directory) */
    const char* context_cache_path;

    /** Number of HTP threads (0 = auto-detect optimal) */
    int32_t num_htp_threads;

    /** Enable detailed profiling for performance analysis */
    rac_bool_t enable_profiling;

    /**
     * SoC ID override (0 = auto-detect from device)
     * Common SoC IDs:
     *   - 57 = SM8650 (Snapdragon 8 Gen 3)
     *   - 53 = SM8550 (Snapdragon 8 Gen 2)
     *   - 62 = SM7550 (Snapdragon 7+ Gen 3)
     */
    int32_t soc_id;

    /** NPU execution strategy */
    rac_npu_strategy_t strategy;

} rac_qnn_config_t;

/**
 * Default QNN configuration for TTS workloads (e.g., Kokoro)
 *
 * NOTE: disable_cpu_fallback is FALSE because Kokoro requires hybrid execution.
 * ISTFT is not supported on QNN HTP, so the vocoder must run on CPU.
 */
#define RAC_QNN_CONFIG_DEFAULT                                                                     \
    {                                                                                              \
        .backend = RAC_QNN_BACKEND_HTP, .performance_mode = RAC_HTP_PERF_BURST,                    \
        .precision = RAC_HTP_PRECISION_INT8, .vtcm_mb = 8,                                         \
        .disable_cpu_fallback = RAC_FALSE, /* FALSE for Kokoro hybrid mode */                      \
        .enable_context_cache = RAC_TRUE, .context_cache_path = NULL, .num_htp_threads = 0,        \
        .enable_profiling = RAC_FALSE, .soc_id = 0, .strategy = RAC_NPU_STRATEGY_HYBRID,           \
    }

/**
 * QNN configuration for encoder-only NPU validation
 *
 * Use this config to verify the encoder runs 100% on NPU.
 * Only use for testing - production should use RAC_QNN_CONFIG_DEFAULT with hybrid.
 */
#define RAC_QNN_CONFIG_NPU_STRICT                                                                  \
    {                                                                                              \
        .backend = RAC_QNN_BACKEND_HTP, .performance_mode = RAC_HTP_PERF_BURST,                    \
        .precision = RAC_HTP_PRECISION_INT8, .vtcm_mb = 8,                                         \
        .disable_cpu_fallback = RAC_TRUE, /* TRUE - fail if any op on CPU */                       \
        .enable_context_cache = RAC_TRUE, .context_cache_path = NULL, .num_htp_threads = 0,        \
        .enable_profiling = RAC_FALSE, .soc_id = 0, .strategy = RAC_NPU_STRATEGY_NPU_REQUIRED,     \
    }

// =============================================================================
// SPLIT MODEL CONFIGURATION (HYBRID EXECUTION)
// =============================================================================

/**
 * @brief Split model configuration for hybrid NPU+CPU execution
 *
 * Required for models with ISTFT (e.g., Kokoro TTS) that cannot run 100% on NPU.
 * The encoder runs on NPU (QNN HTP) and vocoder runs on CPU.
 */
typedef struct rac_split_model_config {
    /** Path to encoder ONNX model (runs on NPU) */
    const char* encoder_path;

    /** Path to vocoder ONNX model (runs on CPU due to ISTFT) */
    const char* vocoder_path;

    /** Whether encoder is QDQ quantized (recommended for NPU) */
    rac_bool_t encoder_is_quantized;

    /** Encoder output tensor names (comma-separated, e.g., "magnitude,phase") */
    const char* encoder_output_names;

    /** Vocoder input tensor names (must match encoder outputs) */
    const char* vocoder_input_names;

} rac_split_model_config_t;

// =============================================================================
// SOC INFORMATION
// =============================================================================

/**
 * @brief Qualcomm SoC information
 */
typedef struct rac_soc_info {
    /** SoC name (e.g., "SM8650", "SM8550") */
    char name[64];

    /** SoC ID (e.g., 57 for SM8650) */
    int32_t soc_id;

    /** Hexagon architecture version (e.g., 73, 75) */
    int32_t hexagon_arch;

    /** Marketing name (e.g., "Snapdragon 8 Gen 3") */
    char marketing_name[128];

    /** Whether HTP (NPU) is available */
    rac_bool_t htp_available;

    /** Estimated HTP compute capability (TOPS) */
    float htp_tops;

} rac_soc_info_t;

// =============================================================================
// NPU STATISTICS
// =============================================================================

/**
 * @brief NPU execution statistics
 */
typedef struct rac_npu_stats {
    /** Whether NPU is currently active */
    rac_bool_t is_npu_active;

    /** Active NPU execution strategy */
    rac_npu_strategy_t active_strategy;

    /** Number of operators running on NPU */
    int32_t ops_on_npu;

    /** Number of operators running on CPU (fallback) */
    int32_t ops_on_cpu;

    /** Percentage of ops on NPU (0.0 - 1.0), target: >0.85 */
    float npu_op_percentage;

    /** Encoder inference time in milliseconds (NPU) */
    double encoder_inference_ms;

    /** Vocoder inference time in milliseconds (CPU) */
    double vocoder_inference_ms;

    /** Total end-to-end inference time in milliseconds */
    double total_inference_ms;

    /** NPU memory usage in bytes */
    int64_t npu_memory_bytes;

    /** CPU memory usage in bytes */
    int64_t cpu_memory_bytes;

    /** Total inference count */
    int64_t total_inferences;

} rac_npu_stats_t;

// =============================================================================
// MODEL VALIDATION
// =============================================================================

/**
 * @brief Model validation result for NPU compatibility
 */
typedef struct rac_model_validation_result {
    /** Whether model is ready for NPU execution */
    rac_bool_t is_npu_ready;

    /** Whether model is QDQ quantized */
    rac_bool_t is_qdq_quantized;

    /** Whether model has static shapes (required for NPU) */
    rac_bool_t has_static_shapes;

    /** Whether all operators are supported on HTP */
    rac_bool_t all_ops_supported;

    /** Number of unsupported operators */
    int32_t unsupported_op_count;

    /** Comma-separated list of unsupported operator types */
    char unsupported_ops[512];

    /** Comma-separated list of dynamic dimension names */
    char dynamic_dims[256];

    /** Recommended action to make model NPU-ready */
    char recommendation[512];

} rac_model_validation_result_t;

// =============================================================================
// QNN DETECTION AND INFORMATION API
// =============================================================================

/**
 * @brief Check if QNN/HTP (NPU) is available on this device
 *
 * @return RAC_TRUE if QNN HTP backend is available, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_qnn_is_available(void);

/**
 * @brief Get detected SoC information
 *
 * @param out_info Output SoC information structure
 * @return RAC_SUCCESS or error code (RAC_ERROR_QNN_NOT_AVAILABLE if not supported)
 */
RAC_API rac_result_t rac_qnn_get_soc_info(rac_soc_info_t* out_info);

/**
 * @brief Get SoC information as JSON string
 *
 * @param out_json Output buffer for JSON string
 * @param json_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_qnn_get_soc_info_json(char* out_json, size_t json_size);

/**
 * @brief Validate that a model can run on NPU
 *
 * Checks:
 *   1. QDQ quantization format (not dynamic quantization)
 *   2. Static shapes (no dynamic dimensions)
 *   3. All operators supported on HTP
 *
 * @param model_path Path to ONNX model
 * @param out_result Validation result details
 * @return RAC_SUCCESS if model is NPU-ready, error code otherwise
 */
RAC_API rac_result_t rac_qnn_validate_model(const char* model_path,
                                            rac_model_validation_result_t* out_result);

/**
 * @brief Get list of QNN HTP supported operators
 *
 * Returns a comma-separated list of ONNX operator types supported on HTP.
 *
 * @param out_ops Output buffer for operator list
 * @param ops_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_qnn_get_supported_ops(char* out_ops, size_t ops_size);

// =============================================================================
// QNN CONFIGURATION HELPERS
// =============================================================================

/**
 * @brief Initialize QNN config with default values
 *
 * @param config Config structure to initialize
 */
RAC_API void rac_qnn_config_init_default(rac_qnn_config_t* config);

/**
 * @brief Initialize split model config
 *
 * @param config Split model config structure to initialize
 * @param encoder_path Path to encoder ONNX model
 * @param vocoder_path Path to vocoder ONNX model
 */
RAC_API void rac_split_model_config_init(rac_split_model_config_t* config, const char* encoder_path,
                                         const char* vocoder_path);

#ifdef __cplusplus
}
#endif

#endif /* RAC_QNN_CONFIG_H */
