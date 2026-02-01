/**
 * @file nnapi_session_manager.cpp
 * @brief NNAPI Session Manager Implementation
 *
 * Implements ONNX Runtime NNAPI Execution Provider session management
 * for Android NPU acceleration.
 */

#include "nnapi_session_manager.h"
#include "rac/core/rac_logger.h"

#include <onnxruntime_c_api.h>

#include <cstring>
#include <fstream>
#include <sstream>

// =============================================================================
// NNAPI-specific ONNX Runtime API
// =============================================================================
// The ONNX Runtime library exports a specific function for NNAPI EP,
// not the generic SessionOptionsAppendExecutionProvider.
// We declare it here to call it directly.
// =============================================================================
#ifdef __ANDROID__
extern "C" {
    // NNAPI flags from nnapi_provider_factory.h
    enum NNAPIFlags {
        NNAPI_FLAG_USE_NONE = 0x000,
        NNAPI_FLAG_USE_FP16 = 0x001,
        NNAPI_FLAG_USE_NCHW = 0x002,
        NNAPI_FLAG_CPU_DISABLED = 0x004,
        NNAPI_FLAG_CPU_ONLY = 0x008
    };

    // Direct NNAPI EP function - exported by libonnxruntime.so
    OrtStatus* OrtSessionOptionsAppendExecutionProvider_Nnapi(
        OrtSessionOptions* options, uint32_t nnapi_flags);
}
#endif

#ifdef __ANDROID__
#include <android/log.h>
#include <sys/system_properties.h>
#define NNAPI_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "NNAPI_EP", __VA_ARGS__)
#define NNAPI_LOGW(...) __android_log_print(ANDROID_LOG_WARN, "NNAPI_EP", __VA_ARGS__)
#define NNAPI_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "NNAPI_EP", __VA_ARGS__)
#else
#define NNAPI_LOGI(...) do { printf("[NNAPI_EP] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define NNAPI_LOGW(...) do { printf("[NNAPI_EP WARN] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define NNAPI_LOGE(...) do { fprintf(stderr, "[NNAPI_EP ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

#define LOG_CAT "NNAPI_EP"

namespace rac {
namespace onnx {

// =============================================================================
// NNAPISessionManager Implementation
// =============================================================================

NNAPISessionManager::NNAPISessionManager() {
    NNAPI_LOGI("NNAPISessionManager created");
}

NNAPISessionManager::~NNAPISessionManager() {
    NNAPI_LOGI("NNAPISessionManager destroyed");
}

bool NNAPISessionManager::initialize(const OrtApi* ort_api, OrtEnv* ort_env) {
    if (initialized_) {
        return true;
    }

    if (ort_api == nullptr || ort_env == nullptr) {
        NNAPI_LOGE("Invalid ONNX Runtime API or environment");
        return false;
    }

    ort_api_ = ort_api;
    ort_env_ = ort_env;

    NNAPI_LOGI("╔════════════════════════════════════════════════════════════╗");
    NNAPI_LOGI("║  Initializing NNAPI Execution Provider                     ║");
    NNAPI_LOGI("╚════════════════════════════════════════════════════════════╝");

    // Detect Android API level
    android_api_level_ = detect_android_api_level();
    stats_.android_api_level = android_api_level_;

    NNAPI_LOGI("  Android API Level: %d", android_api_level_);

#ifdef __ANDROID__
    // NNAPI requires Android 8.1+ (API 27)
    if (android_api_level_ >= 27) {
        nnapi_available_ = true;
        NNAPI_LOGI("  NNAPI Available: YES (API %d >= 27)", android_api_level_);

        // Check for advanced features
        if (android_api_level_ >= 29) {
            NNAPI_LOGI("  FP16 Support: Available (API 29+)");
            NNAPI_LOGI("  INT8 Optimization: Available (API 29+)");
        } else {
            NNAPI_LOGI("  FP16 Support: Limited (API < 29)");
            NNAPI_LOGI("  INT8 Optimization: Limited (API < 29)");
        }

        if (android_api_level_ >= 30) {
            NNAPI_LOGI("  Device Selection: Available (API 30+)");
        }
    } else {
        nnapi_available_ = false;
        NNAPI_LOGW("  NNAPI Available: NO (API %d < 27)", android_api_level_);
    }
#else
    nnapi_available_ = false;
    NNAPI_LOGI("  NNAPI Available: NO (not Android)");
#endif

    // Detect NNAPI devices
    if (nnapi_available_) {
        std::vector<std::string> devices;
        if (detect_nnapi_devices(devices) == RAC_SUCCESS && !devices.empty()) {
            stats_.device_name = devices[0];
            NNAPI_LOGI("  Primary NNAPI Device: %s", stats_.device_name.c_str());
            for (size_t i = 1; i < devices.size(); ++i) {
                NNAPI_LOGI("  Additional Device [%zu]: %s", i, devices[i].c_str());
            }
        }
    }

    initialized_ = true;
    NNAPI_LOGI("  Initialization: SUCCESS");

    return true;
}

bool NNAPISessionManager::is_nnapi_available() const {
    return initialized_ && nnapi_available_;
}

int32_t NNAPISessionManager::get_android_api_level() const {
    return android_api_level_;
}

int32_t NNAPISessionManager::detect_android_api_level() const {
#ifdef __ANDROID__
    char sdk_version[PROP_VALUE_MAX];
    int len = __system_property_get("ro.build.version.sdk", sdk_version);
    if (len > 0) {
        return std::atoi(sdk_version);
    }
#endif
    return 0;
}

OrtSessionOptions* NNAPISessionManager::create_nnapi_session_options(const NNAPIConfig& config) {
    if (!initialized_) {
        NNAPI_LOGE("Session manager not initialized");
        return nullptr;
    }

    if (!nnapi_available_ && config.enabled) {
        NNAPI_LOGW("NNAPI not available, creating CPU session options");
        return create_cpu_session_options();
    }

    OrtSessionOptions* options = nullptr;
    OrtStatus* status = ort_api_->CreateSessionOptions(&options);

    if (status != nullptr) {
        NNAPI_LOGE("Failed to create session options: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return nullptr;
    }

    // Set basic options
    ort_api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);

    if (config.enabled && !config.cpu_only) {
        NNAPI_LOGI("╔════════════════════════════════════════════════════════════╗");
        NNAPI_LOGI("║  Configuring NNAPI Execution Provider                      ║");
        NNAPI_LOGI("╚════════════════════════════════════════════════════════════╝");

        if (!add_nnapi_provider_options(options, config)) {
            NNAPI_LOGW("Failed to add NNAPI EP, falling back to CPU");
            // Continue with CPU-only execution
        } else {
            NNAPI_LOGI("  NNAPI EP: Added successfully");
            stats_.nnapi_active = true;
        }
    } else {
        NNAPI_LOGI("  Using CPU execution (NNAPI disabled or CPU-only mode)");
    }

    return options;
}

bool NNAPISessionManager::add_nnapi_provider_options(OrtSessionOptions* options,
                                                      const NNAPIConfig& config) {
    if (options == nullptr) {
        return false;
    }

#ifdef __ANDROID__
    NNAPI_LOGI("  Adding NNAPI Execution Provider...");

    // Build NNAPI flags
    // NNAPI EP flags are passed as a uint32_t bitmask
    //
    // Available flags (from onnxruntime/core/providers/nnapi/nnapi_builtin/nnapi_api.h):
    //   NNAPI_FLAG_USE_FP16 = 0x001       - Use FP16 relaxed precision
    //   NNAPI_FLAG_USE_NCHW = 0x002       - Prefer NCHW data layout
    //   NNAPI_FLAG_CPU_DISABLED = 0x004   - Disable NNAPI CPU fallback
    //   NNAPI_FLAG_CPU_ONLY = 0x008       - Force CPU-only execution in NNAPI

    uint32_t nnapi_flags = 0;

    if (config.use_fp16) {
        nnapi_flags |= 0x001;  // NNAPI_FLAG_USE_FP16
        NNAPI_LOGI("    Flag: USE_FP16 (relaxed precision)");
    }

    if (config.use_nchw) {
        nnapi_flags |= 0x002;  // NNAPI_FLAG_USE_NCHW
        NNAPI_LOGI("    Flag: USE_NCHW (optimized layout)");
    }

    if (config.cpu_disabled) {
        nnapi_flags |= 0x004;  // NNAPI_FLAG_CPU_DISABLED
        NNAPI_LOGI("    Flag: CPU_DISABLED (no NNAPI CPU fallback)");
    }

    if (config.cpu_only) {
        nnapi_flags |= 0x008;  // NNAPI_FLAG_CPU_ONLY
        NNAPI_LOGI("    Flag: CPU_ONLY (force CPU in NNAPI)");
    }

    // ==========================================================================
    // Use the NNAPI-specific API function
    // ==========================================================================
    // The generic SessionOptionsAppendExecutionProvider("NNAPI", ...) does NOT
    // work with this library. We must use the specific NNAPI function:
    // OrtSessionOptionsAppendExecutionProvider_Nnapi(options, flags)
    // ==========================================================================

    NNAPI_LOGI("    NNAPI Flags: 0x%08X", nnapi_flags);
    NNAPI_LOGI("    Using OrtSessionOptionsAppendExecutionProvider_Nnapi (direct API)");

    OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_Nnapi(options, nnapi_flags);

    if (status != nullptr) {
        const char* err_msg = ort_api_->GetErrorMessage(status);
        NNAPI_LOGE("  ❌ Failed to add NNAPI EP: %s", err_msg);
        ort_api_->ReleaseStatus(status);
        return false;
    }

    NNAPI_LOGI("  ✅ NNAPI Execution Provider added successfully!");
    NNAPI_LOGI("     Operations will be routed to NPU hardware");

    // Add model cache directory if specified
    if (!config.model_cache_dir.empty()) {
        NNAPI_LOGI("  Model cache dir: %s", config.model_cache_dir.c_str());
        // Note: Model caching is handled internally by NNAPI on Android 10+
    }

    return true;

#else
    NNAPI_LOGW("NNAPI EP not available on non-Android platforms");
    return false;
#endif
}

OrtSessionOptions* NNAPISessionManager::create_cpu_session_options(int num_threads) {
    if (!initialized_) {
        NNAPI_LOGE("Session manager not initialized");
        return nullptr;
    }

    OrtSessionOptions* options = nullptr;
    OrtStatus* status = ort_api_->CreateSessionOptions(&options);

    if (status != nullptr) {
        NNAPI_LOGE("Failed to create CPU session options: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return nullptr;
    }

    // Configure CPU execution
    int threads = num_threads > 0 ? num_threads : 4;
    ort_api_->SetIntraOpNumThreads(options, threads);
    ort_api_->SetInterOpNumThreads(options, 2);
    ort_api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);

    NNAPI_LOGI("Created CPU session options: %d threads (intra), 2 threads (inter)", threads);

    return options;
}

rac_result_t NNAPISessionManager::detect_nnapi_devices(std::vector<std::string>& out_devices) {
    out_devices.clear();

#ifdef __ANDROID__
    // NNAPI device enumeration is only available on Android 10+ (API 29)
    if (android_api_level_ < 29) {
        // On older Android, we can't enumerate devices
        // But we know NNAPI is available, so add a generic entry
        out_devices.push_back("nnapi-default");
        NNAPI_LOGI("  Device enumeration requires API 29+, using default");
        return RAC_SUCCESS;
    }

    // On Android 10+, we could use ANeuralNetworksDevice_getCount and related APIs
    // However, these are not available through standard NDK headers
    // The NNAPI EP will automatically select the best device

    // For now, detect device type from system properties
    char hardware[PROP_VALUE_MAX];
    int len = __system_property_get("ro.hardware", hardware);

    if (len > 0) {
        // Check for known Qualcomm hardware
        if (strstr(hardware, "qcom") != nullptr ||
            strstr(hardware, "sm8") != nullptr ||
            strstr(hardware, "sm7") != nullptr) {
            out_devices.push_back("qualcomm-dsp");  // Hexagon DSP via NNAPI
            stats_.vendor_name = "Qualcomm";
            NNAPI_LOGI("  Detected Qualcomm hardware: %s", hardware);
        }

        // Check for Samsung Exynos
        if (strstr(hardware, "exynos") != nullptr ||
            strstr(hardware, "samsung") != nullptr) {
            out_devices.push_back("samsung-npu");  // Samsung NPU via NNAPI
            stats_.vendor_name = "Samsung";
            NNAPI_LOGI("  Detected Samsung Exynos hardware: %s", hardware);
        }

        // Check for MediaTek
        if (strstr(hardware, "mt") != nullptr ||
            strstr(hardware, "mediatek") != nullptr) {
            out_devices.push_back("mediatek-apu");  // MediaTek APU via NNAPI
            stats_.vendor_name = "MediaTek";
            NNAPI_LOGI("  Detected MediaTek hardware: %s", hardware);
        }
    }

    // Check for GPU support
    char gpu_model[PROP_VALUE_MAX];
    len = __system_property_get("ro.hardware.vulkan", gpu_model);
    if (len > 0) {
        if (strstr(gpu_model, "adreno") != nullptr) {
            out_devices.push_back("qualcomm-gpu");  // Adreno GPU via NNAPI
            NNAPI_LOGI("  Detected Adreno GPU: %s", gpu_model);
        } else if (strstr(gpu_model, "mali") != nullptr) {
            out_devices.push_back("arm-gpu");  // Mali GPU via NNAPI
            NNAPI_LOGI("  Detected Mali GPU: %s", gpu_model);
        }
    }

    // Always add CPU fallback
    out_devices.push_back("nnapi-cpu");

    if (out_devices.empty()) {
        out_devices.push_back("nnapi-default");
    }

#else
    // Not Android
    NNAPI_LOGI("  NNAPI device detection not available (non-Android)");
#endif

    return RAC_SUCCESS;
}

}  // namespace onnx
}  // namespace rac
