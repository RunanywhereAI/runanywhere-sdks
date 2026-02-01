/**
 * @file rac_nnapi_config.h
 * @brief RunAnywhere Commons - NNAPI (Android Neural Networks API) Configuration
 *
 * Configuration types and APIs for Android NNAPI Execution Provider support.
 * NNAPI provides vendor-agnostic hardware acceleration on Android devices,
 * routing inference to the most efficient accelerator (NPU, GPU, or DSP).
 *
 * Supported Hardware (via NNAPI):
 *   - Qualcomm: Hexagon DSP/NPU on Snapdragon SoCs
 *   - Samsung: NPU on Exynos SoCs
 *   - MediaTek: APU (AI Processing Unit) on Dimensity SoCs
 *   - Google: TPU on Tensor SoCs (Pixel devices)
 *
 * Requirements:
 *   - Android 8.1+ (API 27) for basic NNAPI
 *   - Android 10+ (API 29) for INT8/FP16 optimizations
 *   - Android 11+ (API 30) for device selection
 *
 * Key Differences from QNN:
 *   - NNAPI: Vendor-agnostic, works on any Android device with NN accelerators
 *   - QNN: Qualcomm-specific, potentially more optimized for Snapdragon
 *   - NNAPI: Built into Android, no separate SDK needed
 *   - NNAPI: INT8 quantized models get best NPU acceleration
 */

#ifndef RAC_NNAPI_CONFIG_H
#define RAC_NNAPI_CONFIG_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// NNAPI TYPES
// =============================================================================

/**
 * @brief NNAPI execution preference
 *
 * Hints to NNAPI about how to balance power and performance.
 */
typedef enum rac_nnapi_execution_preference {
    RAC_NNAPI_PREFER_DEFAULT = 0,       /**< Let NNAPI decide */
    RAC_NNAPI_PREFER_LOW_POWER = 1,     /**< Minimize power consumption */
    RAC_NNAPI_PREFER_FAST_SINGLE = 2,   /**< Minimize latency for single inference */
    RAC_NNAPI_PREFER_SUSTAINED = 3,     /**< Sustained performance for continuous inference */
} rac_nnapi_execution_preference_t;

/**
 * @brief NNAPI execution priority (Android 11+)
 *
 * Priority hints for scheduling NNAPI operations.
 */
typedef enum rac_nnapi_priority {
    RAC_NNAPI_PRIORITY_DEFAULT = 0,     /**< Default priority */
    RAC_NNAPI_PRIORITY_LOW = 1,         /**< Background tasks */
    RAC_NNAPI_PRIORITY_MEDIUM = 2,      /**< Normal interactive */
    RAC_NNAPI_PRIORITY_HIGH = 3,        /**< Real-time, time-critical */
} rac_nnapi_priority_t;

/**
 * @brief NNAPI device type
 */
typedef enum rac_nnapi_device_type {
    RAC_NNAPI_DEVICE_UNKNOWN = 0,       /**< Unknown device type */
    RAC_NNAPI_DEVICE_CPU = 1,           /**< CPU fallback */
    RAC_NNAPI_DEVICE_GPU = 2,           /**< GPU (Adreno, Mali, etc.) */
    RAC_NNAPI_DEVICE_DSP = 3,           /**< DSP (Hexagon, etc.) */
    RAC_NNAPI_DEVICE_NPU = 4,           /**< Dedicated NPU */
    RAC_NNAPI_DEVICE_ACCELERATOR = 5,   /**< Generic accelerator */
} rac_nnapi_device_type_t;

// =============================================================================
// NNAPI CONFIGURATION
// =============================================================================

/**
 * @brief NNAPI execution configuration
 *
 * Configuration for NNAPI Execution Provider session options.
 * NNAPI is Android's vendor-agnostic API for neural network acceleration.
 */
typedef struct rac_nnapi_config {
    /** Enable NNAPI execution (default: true) */
    rac_bool_t enabled;

    /**
     * Use FP16 relaxed precision mode.
     * - Enables faster inference at slight accuracy cost
     * - Requires API 29+ for optimal support
     * - Some devices may not support FP16 execution
     */
    rac_bool_t use_fp16;

    /**
     * Use NCHW tensor layout (default: true).
     * NCHW is typically more efficient for NPU/GPU execution.
     */
    rac_bool_t use_nchw;

    /**
     * Disable CPU fallback within NNAPI.
     * When true, operations unsupported by accelerator will fail instead of
     * falling back to NNAPI CPU implementation.
     * WARNING: Most models need some CPU fallback - use with caution.
     */
    rac_bool_t cpu_disabled;

    /**
     * Force CPU-only execution within NNAPI.
     * Useful for debugging or when accelerators are unreliable.
     */
    rac_bool_t cpu_only;

    /**
     * Disable ONNX Runtime CPU EP fallback.
     * When true, if NNAPI fails, the model load will fail entirely
     * instead of falling back to ORT CPU EP.
     */
    rac_bool_t disable_cpu_ep_fallback;

    /** Execution preference hint */
    rac_nnapi_execution_preference_t execution_preference;

    /** Execution priority (API 30+) */
    rac_nnapi_priority_t priority;

    /**
     * Model cache directory for compiled models.
     * NNAPI can cache compiled models for faster subsequent loads.
     * NULL = use system default cache.
     */
    const char* model_cache_dir;

    /**
     * Minimum Android API level required.
     * Default is 27 (Android 8.1).
     * Set to 29 for INT8/FP16 features.
     */
    int32_t min_api_level;

} rac_nnapi_config_t;

/**
 * Default NNAPI configuration
 *
 * Uses balanced settings that work across most Android devices.
 */
#define RAC_NNAPI_CONFIG_DEFAULT                                                                   \
    {                                                                                              \
        .enabled = RAC_TRUE,                                                                       \
        .use_fp16 = RAC_FALSE,                                                                     \
        .use_nchw = RAC_TRUE,                                                                      \
        .cpu_disabled = RAC_FALSE,                                                                 \
        .cpu_only = RAC_FALSE,                                                                     \
        .disable_cpu_ep_fallback = RAC_FALSE,                                                      \
        .execution_preference = RAC_NNAPI_PREFER_DEFAULT,                                          \
        .priority = RAC_NNAPI_PRIORITY_DEFAULT,                                                    \
        .model_cache_dir = NULL,                                                                   \
        .min_api_level = 27,                                                                       \
    }

/**
 * NNAPI configuration for maximum performance
 *
 * Aggressive settings for lowest latency. May increase power consumption.
 */
#define RAC_NNAPI_CONFIG_PERFORMANCE                                                               \
    {                                                                                              \
        .enabled = RAC_TRUE,                                                                       \
        .use_fp16 = RAC_TRUE,                                                                      \
        .use_nchw = RAC_TRUE,                                                                      \
        .cpu_disabled = RAC_FALSE,                                                                 \
        .cpu_only = RAC_FALSE,                                                                     \
        .disable_cpu_ep_fallback = RAC_FALSE,                                                      \
        .execution_preference = RAC_NNAPI_PREFER_FAST_SINGLE,                                      \
        .priority = RAC_NNAPI_PRIORITY_HIGH,                                                       \
        .model_cache_dir = NULL,                                                                   \
        .min_api_level = 29,                                                                       \
    }

/**
 * NNAPI configuration for power efficiency
 *
 * Optimized for battery life during extended use.
 */
#define RAC_NNAPI_CONFIG_POWER_SAVER                                                               \
    {                                                                                              \
        .enabled = RAC_TRUE,                                                                       \
        .use_fp16 = RAC_FALSE,                                                                     \
        .use_nchw = RAC_TRUE,                                                                      \
        .cpu_disabled = RAC_FALSE,                                                                 \
        .cpu_only = RAC_FALSE,                                                                     \
        .disable_cpu_ep_fallback = RAC_FALSE,                                                      \
        .execution_preference = RAC_NNAPI_PREFER_LOW_POWER,                                        \
        .priority = RAC_NNAPI_PRIORITY_LOW,                                                        \
        .model_cache_dir = NULL,                                                                   \
        .min_api_level = 27,                                                                       \
    }

// =============================================================================
// NNAPI DEVICE INFORMATION
// =============================================================================

/**
 * @brief NNAPI device information
 */
typedef struct rac_nnapi_device_info {
    /** Device name (e.g., "nnapi-reference", "qti-dsp") */
    char name[64];

    /** Device type */
    rac_nnapi_device_type_t device_type;

    /** Vendor name (e.g., "Qualcomm", "Samsung") */
    char vendor[64];

    /** Feature level (NNAPI version) */
    int32_t feature_level;

    /** Whether device is available */
    rac_bool_t is_available;

} rac_nnapi_device_info_t;

// =============================================================================
// NNAPI STATISTICS
// =============================================================================

/**
 * @brief NNAPI execution statistics
 */
typedef struct rac_nnapi_stats {
    /** Whether NNAPI is active */
    rac_bool_t is_nnapi_active;

    /** Android API level */
    int32_t android_api_level;

    /** Primary device type being used */
    rac_nnapi_device_type_t active_device_type;

    /** Primary device name */
    char active_device_name[64];

    /** Vendor name */
    char vendor_name[64];

    /** Model load time in milliseconds */
    double load_time_ms;

    /** Average inference time in milliseconds */
    double avg_inference_ms;

    /** Total inference count */
    int64_t total_inferences;

    /** Number of available NNAPI devices */
    int32_t device_count;

} rac_nnapi_stats_t;

// =============================================================================
// NNAPI DETECTION AND INFORMATION API
// =============================================================================

/**
 * @brief Check if NNAPI is available on this device
 *
 * @return RAC_TRUE if NNAPI is available, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_nnapi_is_available(void);

/**
 * @brief Get Android API level
 *
 * @return Android API level, or 0 if not Android
 */
RAC_API int32_t rac_nnapi_get_api_level(void);

/**
 * @brief Get list of available NNAPI devices
 *
 * @param out_devices Array of device info structures (caller allocated)
 * @param max_devices Maximum number of devices to return
 * @param out_count Actual number of devices found
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_nnapi_get_devices(rac_nnapi_device_info_t* out_devices, size_t max_devices,
                                           size_t* out_count);

/**
 * @brief Get NNAPI information as JSON string
 *
 * @param out_json Output buffer for JSON string
 * @param json_size Size of output buffer
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_nnapi_get_info_json(char* out_json, size_t json_size);

// =============================================================================
// NNAPI CONFIGURATION HELPERS
// =============================================================================

/**
 * @brief Initialize NNAPI config with default values
 *
 * @param config Config structure to initialize
 */
RAC_API void rac_nnapi_config_init_default(rac_nnapi_config_t* config);

/**
 * @brief Initialize NNAPI config for performance mode
 *
 * @param config Config structure to initialize
 */
RAC_API void rac_nnapi_config_init_performance(rac_nnapi_config_t* config);

/**
 * @brief Initialize NNAPI config for power saving mode
 *
 * @param config Config structure to initialize
 */
RAC_API void rac_nnapi_config_init_power_saver(rac_nnapi_config_t* config);

#ifdef __cplusplus
}
#endif

#endif /* RAC_NNAPI_CONFIG_H */
