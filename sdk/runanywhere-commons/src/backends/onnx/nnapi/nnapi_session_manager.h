/**
 * @file nnapi_session_manager.h
 * @brief NNAPI Session Manager for ONNX Runtime NNAPI Execution Provider
 *
 * Manages ONNX Runtime sessions with NNAPI Execution Provider for Android NPU
 * acceleration. NNAPI is Android's standard Neural Networks API that provides
 * vendor-agnostic access to NPU, GPU, and DSP hardware.
 *
 * Key differences from QNN EP:
 *   - NNAPI: Vendor-agnostic, works on Qualcomm, Samsung, MediaTek, etc.
 *   - QNN: Qualcomm-specific, potentially more optimized for Qualcomm hardware
 *   - NNAPI: Built into Android, requires API 27+ (Android 8.1+)
 *   - NNAPI: Simpler setup - no separate SDK needed
 *
 * Best Practices:
 *   - Use INT8 quantized models for best NPU acceleration
 *   - FP16 may work on some devices but not guaranteed
 *   - FP32 typically falls back to CPU
 *
 * This is implemented as Option A from the NPU integration strategy.
 */

#ifndef RAC_NNAPI_SESSION_MANAGER_H
#define RAC_NNAPI_SESSION_MANAGER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#include <memory>
#include <string>
#include <vector>

// Forward declarations
struct OrtApi;
struct OrtEnv;
struct OrtSessionOptions;
struct OrtSession;

namespace rac {
namespace onnx {

/**
 * @brief NNAPI execution priority
 */
enum class NNAPIExecutionPriority {
    DEFAULT = 0,    // Let NNAPI decide
    LOW = 1,        // Background tasks
    MEDIUM = 2,     // Normal interactive
    HIGH = 3,       // Real-time, time-critical
};

/**
 * @brief NNAPI configuration options
 */
struct NNAPIConfig {
    // Enable NNAPI acceleration
    bool enabled = true;

    // NNAPI options
    bool use_fp16 = false;              // Enable FP16 execution (device-dependent)
    bool use_nchw = true;               // Use NCHW layout (more efficient on NPU)
    bool cpu_disabled = false;          // Disable CPU fallback in NNAPI
    bool cpu_only = false;              // Force CPU-only execution
    bool disable_cpu_ep_fallback = false;  // Disable ONNX CPU EP fallback

    // Execution settings
    NNAPIExecutionPriority priority = NNAPIExecutionPriority::DEFAULT;
    int32_t execution_preference = -1;  // -1 = default, 0 = low_power, 1 = fast, 2 = sustained

    // Model cache path (for compiled model caching)
    std::string model_cache_dir;

    // Android API level requirements
    // NNAPI available: API 27+ (Android 8.1+)
    // FP16 support: API 29+ (Android 10+)
    // INT8 optimization: API 29+ (Android 10+)
    int32_t min_api_level = 27;
};

/**
 * @brief NNAPI execution statistics
 */
struct NNAPIStats {
    bool nnapi_active = false;          // Is NNAPI being used
    bool npu_selected = false;          // Is NPU selected as accelerator
    int32_t android_api_level = 0;      // Device Android API level
    std::string device_name;            // NNAPI device name (if detected)
    std::string vendor_name;            // Hardware vendor
    double load_time_ms = 0;            // Model load time
    double inference_time_ms = 0;       // Inference time
    int64_t inference_count = 0;        // Number of inferences
};

/**
 * @brief NNAPI Session Manager for Android NPU acceleration
 *
 * Provides ONNX Runtime session management with NNAPI Execution Provider.
 * This enables hardware-accelerated inference on Android devices through
 * the standard NNAPI interface, which routes to the most appropriate
 * hardware accelerator (NPU, GPU, or DSP).
 *
 * Usage:
 *   1. Create NNAPISessionManager
 *   2. Call initialize() with ORT API and environment
 *   3. Check is_nnapi_available() for NNAPI support
 *   4. Create sessions with create_nnapi_session_options()
 */
class NNAPISessionManager {
public:
    NNAPISessionManager();
    ~NNAPISessionManager();

    // Non-copyable
    NNAPISessionManager(const NNAPISessionManager&) = delete;
    NNAPISessionManager& operator=(const NNAPISessionManager&) = delete;

    /**
     * @brief Initialize the session manager
     * @param ort_api ONNX Runtime API pointer
     * @param ort_env ONNX Runtime environment
     * @return true if initialization successful
     */
    bool initialize(const OrtApi* ort_api, OrtEnv* ort_env);

    /**
     * @brief Check if NNAPI execution provider is available
     * @return true if NNAPI EP is available
     */
    bool is_nnapi_available() const;

    /**
     * @brief Get Android API level
     * @return API level or 0 if not Android
     */
    int32_t get_android_api_level() const;

    /**
     * @brief Get NNAPI statistics
     * @return Current NNAPI stats
     */
    NNAPIStats get_stats() const { return stats_; }

    /**
     * @brief Create session options configured for NNAPI (NPU) execution
     *
     * @param config NNAPI configuration
     * @return Session options pointer (caller takes ownership), nullptr on failure
     *
     * @note The returned session options include NNAPI EP as the primary provider
     *       with CPU EP as fallback (unless disable_cpu_ep_fallback is set)
     */
    OrtSessionOptions* create_nnapi_session_options(const NNAPIConfig& config);

    /**
     * @brief Create session options for CPU-only execution
     *
     * Used as fallback when NNAPI is not available or not desired.
     *
     * @param num_threads Number of threads (0 = auto)
     * @return Session options pointer (caller takes ownership)
     */
    OrtSessionOptions* create_cpu_session_options(int num_threads = 0);

    /**
     * @brief Detect available NNAPI devices
     *
     * @param out_devices Output vector of device names
     * @return RAC_SUCCESS or error code
     */
    rac_result_t detect_nnapi_devices(std::vector<std::string>& out_devices);

private:
    /**
     * @brief Detect Android API level
     */
    int32_t detect_android_api_level() const;

    /**
     * @brief Add NNAPI provider options to session
     */
    bool add_nnapi_provider_options(OrtSessionOptions* options, const NNAPIConfig& config);

    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    bool initialized_ = false;
    bool nnapi_available_ = false;
    int32_t android_api_level_ = 0;
    NNAPIStats stats_;
};

}  // namespace onnx
}  // namespace rac

#endif  // RAC_NNAPI_SESSION_MANAGER_H
