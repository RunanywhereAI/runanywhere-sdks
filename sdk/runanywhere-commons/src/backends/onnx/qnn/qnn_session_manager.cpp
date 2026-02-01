/**
 * @file qnn_session_manager.cpp
 * @brief QNN Session Manager Implementation
 */

#include "qnn_session_manager.h"

#include "rac/core/rac_logger.h"

#include <onnxruntime_c_api.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <sstream>

#ifdef __ANDROID__
#include <sys/stat.h>
#include <sys/system_properties.h>
#include <android/log.h>
#define QNN_SM_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "QNN_SessManager", __VA_ARGS__)
#define QNN_SM_LOGW(...) __android_log_print(ANDROID_LOG_WARN, "QNN_SessManager", __VA_ARGS__)
#define QNN_SM_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "QNN_SessManager", __VA_ARGS__)
#else
#define QNN_SM_LOGI(...) do {} while(0)
#define QNN_SM_LOGW(...) do {} while(0)
#define QNN_SM_LOGE(...) do {} while(0)
#endif

#define LOG_CAT "QNN"

namespace rac {
namespace onnx {

QNNSessionManager::QNNSessionManager() = default;

QNNSessionManager::~QNNSessionManager() = default;

bool QNNSessionManager::initialize(const OrtApi* ort_api, OrtEnv* ort_env) {
    QNN_SM_LOGI("=== QNNSessionManager::initialize() called ===");

    if (initialized_) {
        QNN_SM_LOGI("Already initialized, qnn_available_=%d", qnn_available_ ? 1 : 0);
        return true;
    }

    if (ort_api == nullptr || ort_env == nullptr) {
        QNN_SM_LOGE("Invalid ONNX Runtime API or environment");
        RAC_LOG_ERROR(LOG_CAT, "Invalid ONNX Runtime API or environment");
        return false;
    }

    ort_api_ = ort_api;
    ort_env_ = ort_env;

    // Get SoC info
    QNN_SM_LOGI("Calling rac_qnn_get_soc_info()...");
    rac_result_t result = rac_qnn_get_soc_info(&soc_info_);
    QNN_SM_LOGI("rac_qnn_get_soc_info() returned %d", result);
    QNN_SM_LOGI("  soc_info_.soc_id = %d", soc_info_.soc_id);
    QNN_SM_LOGI("  soc_info_.name = %s", soc_info_.name ? soc_info_.name : "(null)");
    QNN_SM_LOGI("  soc_info_.marketing_name = %s", soc_info_.marketing_name ? soc_info_.marketing_name : "(null)");
    QNN_SM_LOGI("  soc_info_.hexagon_arch = %d", soc_info_.hexagon_arch);
    QNN_SM_LOGI("  soc_info_.htp_available = %d", soc_info_.htp_available ? 1 : 0);

    if (result == RAC_SUCCESS && soc_info_.htp_available) {
        qnn_available_ = true;
        QNN_SM_LOGI("QNN IS AVAILABLE: %s (%s), Hexagon V%d", soc_info_.name,
                     soc_info_.marketing_name, soc_info_.hexagon_arch);
        RAC_LOG_INFO(LOG_CAT, "QNN available: %s (%s), Hexagon V%d", soc_info_.name,
                     soc_info_.marketing_name, soc_info_.hexagon_arch);
    } else {
        qnn_available_ = false;
        QNN_SM_LOGW("QNN NOT AVAILABLE on this device (result=%d, htp_available=%d)",
                    result, soc_info_.htp_available ? 1 : 0);
        RAC_LOG_INFO(LOG_CAT, "QNN not available on this device");
    }

    // Set up default cache directory
    default_cache_dir_ = get_default_cache_dir();
    QNN_SM_LOGI("Default cache dir: %s", default_cache_dir_.c_str());

    initialized_ = true;
    QNN_SM_LOGI("QNNSessionManager initialized, qnn_available_=%d", qnn_available_ ? 1 : 0);
    return true;
}

bool QNNSessionManager::is_qnn_available() const {
    bool result = initialized_ && qnn_available_;
    QNN_SM_LOGI("is_qnn_available() = %d (initialized_=%d, qnn_available_=%d)",
                result ? 1 : 0, initialized_ ? 1 : 0, qnn_available_ ? 1 : 0);
    return result;
}

rac_soc_info_t QNNSessionManager::get_soc_info() const {
    return soc_info_;
}

OrtSessionOptions* QNNSessionManager::create_qnn_session_options(const rac_qnn_config_t& config) {
    QNN_SM_LOGI("=== create_qnn_session_options() called ===");
    QNN_SM_LOGI("  config.backend = %d (0=CPU, 1=GPU, 2=HTP, 3=DSP)", config.backend);
    QNN_SM_LOGI("  config.performance_mode = %d", config.performance_mode);
    QNN_SM_LOGI("  config.precision = %d", config.precision);
    QNN_SM_LOGI("  config.vtcm_mb = %d", config.vtcm_mb);

    if (!initialized_) {
        QNN_SM_LOGE("Session manager not initialized!");
        RAC_LOG_ERROR(LOG_CAT, "Session manager not initialized");
        return nullptr;
    }

    if (!qnn_available_) {
        QNN_SM_LOGE("QNN not available, cannot create QNN session options!");
        RAC_LOG_ERROR(LOG_CAT, "QNN not available, cannot create QNN session options");
        return nullptr;
    }

    OrtSessionOptions* options = nullptr;
    OrtStatus* status = ort_api_->CreateSessionOptions(&options);
    if (status != nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create session options: %s",
                      ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return nullptr;
    }

    // Set graph optimization level
    status = ort_api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    if (status != nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "Failed to set optimization level: %s",
                        ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
    }

    // Add QNN execution provider
    if (!add_qnn_provider_options(options, config)) {
        ort_api_->ReleaseSessionOptions(options);
        return nullptr;
    }

    return options;
}

OrtSessionOptions* QNNSessionManager::create_cpu_session_options() {
    QNN_SM_LOGI("=== create_cpu_session_options() called ===");

    if (!initialized_) {
        QNN_SM_LOGE("Session manager not initialized!");
        RAC_LOG_ERROR(LOG_CAT, "Session manager not initialized");
        return nullptr;
    }

    OrtSessionOptions* options = nullptr;
    OrtStatus* status = ort_api_->CreateSessionOptions(&options);
    if (status != nullptr) {
        QNN_SM_LOGE("Failed to create session options: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_ERROR(LOG_CAT, "Failed to create session options: %s",
                      ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return nullptr;
    }

    // Set graph optimization level
    status = ort_api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    if (status != nullptr) {
        QNN_SM_LOGW("Failed to set optimization level: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_WARNING(LOG_CAT, "Failed to set optimization level: %s",
                        ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
    }

    // Set thread count for CPU execution
    status = ort_api_->SetIntraOpNumThreads(options, 4);
    if (status != nullptr) {
        QNN_SM_LOGW("Failed to set intra-op threads: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_WARNING(LOG_CAT, "Failed to set intra-op threads: %s",
                        ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
    }

    status = ort_api_->SetInterOpNumThreads(options, 1);
    if (status != nullptr) {
        QNN_SM_LOGW("Failed to set inter-op threads: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_WARNING(LOG_CAT, "Failed to set inter-op threads: %s",
                        ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
    }

    QNN_SM_LOGI("Created CPU session options successfully");
    RAC_LOG_DEBUG(LOG_CAT, "Created CPU session options");
    return options;
}

bool QNNSessionManager::add_qnn_provider_options(OrtSessionOptions* options,
                                                 const rac_qnn_config_t& config) {
    QNN_SM_LOGI("=== add_qnn_provider_options() called ===");
    QNN_SM_LOGI("  RAC_QNN_AVAILABLE = %d", RAC_QNN_AVAILABLE);

#if RAC_QNN_AVAILABLE
    QNN_SM_LOGI("QNN is compiled in, building provider options...");

    // Build QNN provider options
    std::vector<const char*> keys;
    std::vector<const char*> values;

    // Temporary storage for string values
    std::string backend_str = backend_to_string(config.backend);
    std::string perf_mode_str = perf_mode_to_string(config.performance_mode);
    std::string vtcm_str = std::to_string(config.vtcm_mb);
    std::string soc_str = std::to_string(config.soc_id > 0 ? config.soc_id : soc_info_.soc_id);
    std::string enable_htp_fp16 = (config.precision == RAC_HTP_PRECISION_FP16) ? "1" : "0";

    // Backend type
    keys.push_back("backend_path");
    if (config.backend == RAC_QNN_BACKEND_HTP) {
        values.push_back("libQnnHtp.so");
        QNN_SM_LOGI("  backend_path = libQnnHtp.so");
    } else if (config.backend == RAC_QNN_BACKEND_GPU) {
        values.push_back("libQnnGpu.so");
        QNN_SM_LOGI("  backend_path = libQnnGpu.so");
    } else if (config.backend == RAC_QNN_BACKEND_CPU) {
        values.push_back("libQnnCpu.so");
        QNN_SM_LOGI("  backend_path = libQnnCpu.so");
    } else {
        values.push_back("libQnnHtp.so");  // Default to HTP
        QNN_SM_LOGI("  backend_path = libQnnHtp.so (default)");
    }

    // HTP-specific options
    if (config.backend == RAC_QNN_BACKEND_HTP) {
        // Performance mode
        keys.push_back("htp_performance_mode");
        values.push_back(perf_mode_str.c_str());
        QNN_SM_LOGI("  htp_performance_mode = %s", perf_mode_str.c_str());

        // VTCM memory
        if (config.vtcm_mb > 0) {
            keys.push_back("vtcm_mb");
            values.push_back(vtcm_str.c_str());
            QNN_SM_LOGI("  vtcm_mb = %s", vtcm_str.c_str());
        }

        // FP16 precision
        keys.push_back("enable_htp_fp16_precision");
        values.push_back(enable_htp_fp16.c_str());
        QNN_SM_LOGI("  enable_htp_fp16_precision = %s", enable_htp_fp16.c_str());

        // SoC model
        if (config.soc_id > 0 || soc_info_.soc_id > 0) {
            keys.push_back("soc_model");
            values.push_back(soc_str.c_str());
            QNN_SM_LOGI("  soc_model = %s", soc_str.c_str());
        }
    }

    // Context caching
    std::string context_enable = config.enable_context_cache ? "1" : "0";
    keys.push_back("qnn_context_cache_enable");
    values.push_back(context_enable.c_str());
    QNN_SM_LOGI("  qnn_context_cache_enable = %s", context_enable.c_str());

    // Context cache path
    std::string cache_path;
    if (config.enable_context_cache) {
        if (config.context_cache_path != nullptr) {
            cache_path = config.context_cache_path;
        } else {
            cache_path = default_cache_dir_ + "/qnn_context_cache";
        }
        // Note: Context path is set per-model, not here
    }

    // Profiling
    if (config.enable_profiling) {
        keys.push_back("profiling_level");
        values.push_back("detailed");
        QNN_SM_LOGI("  profiling_level = detailed");
    }

    // Disable CPU fallback (for encoder validation)
    if (config.disable_cpu_fallback) {
        keys.push_back("qnn_context_embed_mode");
        values.push_back("1");
        QNN_SM_LOGI("  qnn_context_embed_mode = 1");
    }

    // Log configuration
    QNN_SM_LOGI("Configured %zu options, calling SessionOptionsAppendExecutionProvider...", keys.size());
    RAC_LOG_INFO(LOG_CAT, "Configuring QNN EP with %zu options", keys.size());
    for (size_t i = 0; i < keys.size(); ++i) {
        RAC_LOG_DEBUG(LOG_CAT, "  %s = %s", keys[i], values[i]);
    }

    // Append QNN execution provider
    OrtStatus* status =
        ort_api_->SessionOptionsAppendExecutionProvider(options, "QNN", keys.data(), values.data(),
                                                        keys.size());

    if (status != nullptr) {
        const char* err_msg = ort_api_->GetErrorMessage(status);
        QNN_SM_LOGE("Failed to append QNN EP: %s", err_msg);
        RAC_LOG_ERROR(LOG_CAT, "Failed to append QNN EP: %s", err_msg);
        ort_api_->ReleaseStatus(status);
        return false;
    }

    QNN_SM_LOGI("QNN Execution Provider configured successfully!");
    RAC_LOG_INFO(LOG_CAT, "QNN Execution Provider configured successfully");
    return true;

#else
    QNN_SM_LOGE("QNN support not compiled (RAC_QNN_AVAILABLE=0)");
    RAC_LOG_ERROR(LOG_CAT, "QNN support not compiled (RAC_QNN_AVAILABLE=0)");
    return false;
#endif
}

std::string QNNSessionManager::get_context_cache_path(const std::string& model_path,
                                                      const char* cache_dir) const {
    // Extract model name
    std::string model_name = model_path;
    size_t last_slash = model_name.find_last_of("/\\");
    if (last_slash != std::string::npos) {
        model_name = model_name.substr(last_slash + 1);
    }

    // Remove extension
    size_t dot_pos = model_name.rfind('.');
    if (dot_pos != std::string::npos) {
        model_name = model_name.substr(0, dot_pos);
    }

    // Build cache path
    std::string dir = (cache_dir != nullptr) ? cache_dir : default_cache_dir_;
    std::stringstream ss;
    ss << dir << "/" << model_name << "_soc" << soc_info_.soc_id << "_v" << soc_info_.hexagon_arch
       << ".ctx";

    return ss.str();
}

rac_result_t QNNSessionManager::validate_model_for_npu(const std::string& model_path,
                                                       rac_model_validation_result_t* out_result) {
    if (out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Initialize result
    memset(out_result, 0, sizeof(*out_result));
    out_result->is_npu_ready = RAC_FALSE;
    out_result->is_qdq_quantized = RAC_FALSE;
    out_result->has_static_shapes = RAC_TRUE;  // Assume true until proven otherwise
    out_result->all_ops_supported = RAC_TRUE;

    // Check if file exists
    std::ifstream file(model_path);
    if (!file.good()) {
        strncpy(out_result->recommendation, "Model file not found", sizeof(out_result->recommendation) - 1);
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // TODO: Implement full ONNX model parsing to check:
    // 1. QDQ quantization nodes present
    // 2. All shapes are static
    // 3. All operators are in QNN HTP supported list
    //
    // For now, this is a placeholder that allows all models
    // The Python tools (analyze_onnx_ops.py) should be used for thorough validation

    RAC_LOG_INFO(LOG_CAT, "Model validation: %s", model_path.c_str());

    // Default: assume model is ready (actual validation happens in Python tools)
    out_result->is_npu_ready = RAC_TRUE;
    out_result->is_qdq_quantized = RAC_TRUE;
    strncpy(out_result->recommendation, "Use analyze_onnx_ops.py for detailed validation",
            sizeof(out_result->recommendation) - 1);

    return RAC_SUCCESS;
}

const char* QNNSessionManager::backend_to_string(rac_qnn_backend_t backend) {
    switch (backend) {
        case RAC_QNN_BACKEND_CPU:
            return "cpu";
        case RAC_QNN_BACKEND_GPU:
            return "gpu";
        case RAC_QNN_BACKEND_HTP:
            return "htp";
        case RAC_QNN_BACKEND_DSP:
            return "dsp";
        default:
            return "htp";
    }
}

const char* QNNSessionManager::perf_mode_to_string(rac_htp_performance_mode_t mode) {
    switch (mode) {
        case RAC_HTP_PERF_DEFAULT:
            return "default";
        case RAC_HTP_PERF_BURST:
            return "burst";
        case RAC_HTP_PERF_BALANCED:
            return "balanced";
        case RAC_HTP_PERF_HIGH_PERFORMANCE:
            return "high_performance";
        case RAC_HTP_PERF_POWER_SAVER:
            return "power_saver";
        case RAC_HTP_PERF_SUSTAINED_HIGH:
            return "sustained_high_performance";
        case RAC_HTP_PERF_LOW_BALANCED:
            return "low_balanced";
        case RAC_HTP_PERF_EXTREME_POWER_SAVER:
            return "extreme_power_saver";
        default:
            return "burst";
    }
}

std::string QNNSessionManager::get_default_cache_dir() const {
#ifdef __ANDROID__
    // Use app cache directory on Android
    // This should be set by the app, but we provide a fallback
    return "/data/local/tmp/rac_qnn_cache";
#else
    // Desktop/other platforms
    return "/tmp/rac_qnn_cache";
#endif
}

}  // namespace onnx
}  // namespace rac
