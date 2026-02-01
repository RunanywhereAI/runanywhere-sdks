/**
 * @file qnn_session_manager.h
 * @brief QNN Session Manager for ONNX Runtime QNN Execution Provider
 *
 * Manages QNN Execution Provider sessions for NPU-accelerated inference.
 * Handles session configuration, QNN-specific options, and context caching.
 */

#ifndef RAC_QNN_SESSION_MANAGER_H
#define RAC_QNN_SESSION_MANAGER_H

#include "rac/backends/rac_qnn_config.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

// Forward declarations
struct OrtApi;
struct OrtEnv;
struct OrtSessionOptions;
struct OrtSession;

namespace rac {
namespace onnx {

/**
 * @brief QNN Session Manager for NPU-accelerated ONNX inference
 *
 * This class manages ONNX Runtime sessions configured with the QNN Execution Provider
 * for Qualcomm NPU (HTP) acceleration.
 *
 * Key responsibilities:
 * - Configure QNN EP session options
 * - Manage context caching for faster subsequent loads
 * - Provide CPU session options for fallback
 * - Validate QNN availability at runtime
 */
class QNNSessionManager {
public:
    QNNSessionManager();
    ~QNNSessionManager();

    // Non-copyable
    QNNSessionManager(const QNNSessionManager&) = delete;
    QNNSessionManager& operator=(const QNNSessionManager&) = delete;

    /**
     * @brief Initialize the session manager
     * @param ort_api ONNX Runtime API pointer
     * @param ort_env ONNX Runtime environment
     * @return true if initialization successful
     */
    bool initialize(const OrtApi* ort_api, OrtEnv* ort_env);

    /**
     * @brief Check if QNN execution provider is available
     * @return true if QNN EP is available and can be used
     */
    bool is_qnn_available() const;

    /**
     * @brief Get the detected SoC information
     * @return SoC info structure
     */
    rac_soc_info_t get_soc_info() const;

    /**
     * @brief Create session options configured for QNN (NPU) execution
     *
     * @param config QNN configuration
     * @return Session options pointer (caller takes ownership), nullptr on failure
     *
     * @note The returned session options include QNN EP as the primary provider
     *       with CPU EP as fallback (unless disable_cpu_fallback is set)
     */
    OrtSessionOptions* create_qnn_session_options(const rac_qnn_config_t& config);

    /**
     * @brief Create session options for CPU-only execution
     *
     * Used for vocoder models that contain ISTFT (not supported on NPU).
     *
     * @return Session options pointer (caller takes ownership)
     */
    OrtSessionOptions* create_cpu_session_options();

    /**
     * @brief Generate a context cache path for a model
     *
     * Context caching speeds up subsequent model loads by saving the compiled
     * QNN graph to disk.
     *
     * @param model_path Path to the ONNX model
     * @param cache_dir Optional cache directory (nullptr = use default)
     * @return Cache file path
     */
    std::string get_context_cache_path(const std::string& model_path,
                                       const char* cache_dir = nullptr) const;

    /**
     * @brief Validate model can run on NPU
     *
     * Checks if all operators in the model are supported on QNN HTP.
     *
     * @param model_path Path to ONNX model
     * @param out_result Validation result
     * @return RAC_SUCCESS if valid for NPU, error code otherwise
     */
    rac_result_t validate_model_for_npu(const std::string& model_path,
                                        rac_model_validation_result_t* out_result);

private:
    /**
     * @brief Convert QNN backend enum to string for ONNX Runtime
     */
    static const char* backend_to_string(rac_qnn_backend_t backend);

    /**
     * @brief Convert HTP performance mode to string
     */
    static const char* perf_mode_to_string(rac_htp_performance_mode_t mode);

    /**
     * @brief Get default cache directory
     */
    std::string get_default_cache_dir() const;

    /**
     * @brief Add QNN provider options to session
     */
    bool add_qnn_provider_options(OrtSessionOptions* options, const rac_qnn_config_t& config);

    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    bool initialized_ = false;
    bool qnn_available_ = false;
    rac_soc_info_t soc_info_ = {};
    std::string default_cache_dir_;
};

}  // namespace onnx
}  // namespace rac

#endif  // RAC_QNN_SESSION_MANAGER_H
