/**
 * @file InitBridge.hpp
 * @brief SDK initialization bridge for React Native
 *
 * Handles rac_init() and rac_shutdown() lifecycle management.
 * Registers platform adapter with callbacks for file I/O, logging, secure storage.
 *
 * Matches Swift's CppBridge initialization pattern.
 */

#pragma once

#include <memory>
#include <string>
#include <tuple>
#include <vector>

// RACommons headers
#include "rac_core.h"
#include "rac_types.h"
#include "rac_platform_adapter.h"
#include "rac_sdk_state.h"
#include "rac_environment.h"
#include "rac_model_paths.h"

namespace runanywhere {
namespace bridges {

inline const char* defaultNativePlatform() {
#if defined(__APPLE__)
    return "ios";
#elif defined(ANDROID) || defined(__ANDROID__)
    return "android";
#else
    return "unknown";
#endif
}

/**
 * @brief SDK initialization bridge singleton
 *
 * Manages the lifecycle of the runanywhere-commons SDK.
 * Registers platform adapter and initializes state.
 */
class InitBridge {
public:
    static InitBridge& shared();

    /**
     * @brief Initialize the SDK
     *
     * 1. Registers platform adapter with RACommons
     * 2. Configures logging for environment
     * 3. Initializes SDK state
     *
     * @param environment SDK environment
     * (RAC_ENV_DEVELOPMENT/STAGING/PRODUCTION)
     * @param apiKey API key for authentication
     * @param baseURL Base URL for API requests
     * @return RAC_SUCCESS or error code
     */
    rac_result_t
    initialize(rac_environment_t environment, const std::string &apiKey,
               const std::string &baseURL, const std::string &platform,
               const std::string &sdkVersion, const std::string &buildToken,
               bool forceRefreshAssignments, bool flushTelemetry,
               bool discoverDownloadedModels, bool rescanLocalModels);

    /**
     * @brief Complete deferred services initialization
     *
     * Registers native device callbacks and then drives commons Phase 2 through
     * rac_sdk_init_phase2_proto.
     *
     * @param outResultBytes Serialized RASdkInitResult proto bytes.
     * @return RAC_SUCCESS or error code
     */
    rac_result_t completeServicesInitialization(std::vector<uint8_t>& outResultBytes);

    /**
     * @brief Retry HTTP/auth setup after an offline initialization.
     *
     * Drives the commons idempotency guard `rac_sdk_retry_http_proto`, which
     * re-checks usable external config and reports whether HTTP is configured.
     * Mirrors Swift CppBridge.SdkInit.retryHTTP().
     *
     * @param outResultBytes Serialized RASdkInitResult proto bytes.
     * @return RAC_SUCCESS or error.
     */
    rac_result_t retryHTTPSetup(std::vector<uint8_t>& outResultBytes);

    /**
     * @brief Register device manager callbacks for commons services init
     *
     * Safe to call multiple times; callback storage is refreshed each call.
     *
     * @return RAC_SUCCESS or error code
     */
    rac_result_t registerDeviceCallbacks();

    /**
     * @brief Set base directory for model paths
     *
     * Must be called after initialize() and before using model path utilities.
     * Mirrors Swift's CppBridge.ModelPaths.setBaseDirectory().
     *
     * @param baseDirectory Native model base directory
     * @return RAC_SUCCESS or error code
     */
    rac_result_t setBaseDirectory(const std::string &baseDirectory);

    /**
     * @brief Resolve the native default model base directory
     *
     * iOS returns the app Documents directory. Android returns app filesDir.
     *
     * @return Absolute directory path, or empty string if unavailable
     */
    std::string getDefaultModelBaseDirectory();

    /**
     * @brief Quiesce device callbacks and run canonical Commons shutdown.
     *
     * Keeps telemetry, HTTP, the platform adapter, and local configuration
     * alive so the coordinator can flush the terminal lifecycle event.
     */
    void shutdownCommons();

    /**
     * @brief Release RN-owned HTTP, adapter, and local configuration state.
     *
     * Call only after shutdownCommons() and telemetry teardown.
     */
    void releasePlatformState();

    /**
     * @brief Check if SDK is initialized
     */
    bool isInitialized() const { return initialized_; }

    /**
     * @brief Get current environment
     */
    rac_environment_t getEnvironment() const { return environment_; }

    // =========================================================================
    // Secure Storage Methods
    // Matches Swift: KeychainManager
    // =========================================================================

    /**
     * @brief Store a value in secure storage (Keychain/Keystore)
     * @param key Storage key
     * @param value Value to store
     * @return true if successful
     */
    bool secureSet(const std::string& key, const std::string& value);

    /**
     * @brief Get a value from secure storage
     * @param key Storage key
     * @param outValue Output value (empty if not found)
     * @return true if value found and retrieved
     */
    bool secureGet(const std::string& key, std::string& outValue);

    /**
     * @brief Get or create the effective persistent device UUID.
     *
     * Uses the explicit initialization override when present; otherwise
     * delegates to the canonical commons resolver and preserves its exact
     * error code. The output is cleared on failure.
     *
     * @param outValue Resolved persistent device UUID.
     * @return RAC_SUCCESS or the resolver's exact error code.
     */
    rac_result_t getPersistentDeviceUUID(std::string &outValue);

    // =========================================================================
    // Device Info (Synchronous)
    // For device registration callback which must be synchronous
    // =========================================================================

    /**
     * @brief Get device model name (e.g., "iPhone 16 Pro Max")
     */
    std::string getDeviceModel();

    /**
     * @brief Get OS version (e.g., "18.2")
     */
    std::string getOSVersion();

    /**
     * @brief Get chip name (e.g., "A18 Pro")
     */
    std::string getChipName();

    /**
     * @brief Get total memory in bytes
     */
    uint64_t getTotalMemory();

    /**
     * @brief Get available memory in bytes
     */
    uint64_t getAvailableMemory();

    /**
     * @brief Get CPU core count
     */
    int getCoreCount();

    /**
     * @brief Get architecture (e.g., "arm64")
     */
    std::string getArchitecture();

    /**
     * @brief Get GPU family (e.g., "mali", "adreno")
     */
    std::string getGPUFamily();

    /**
     * @brief Check if device is a tablet
     * Uses platform-specific detection (UIDevice on iOS, Configuration on Android)
     * Matches Swift SDK: device.userInterfaceIdiom == .pad
     */
    bool isTablet();

    /**
     * @brief Get user-visible device name (UIDevice.name / Settings device_name)
     * @return Device name, or empty string when unavailable
     */
    std::string getDeviceName();

    /**
     * @brief Get battery level as 0.0..1.0, or -1.0 when unknown
     */
    float getBatteryLevel();

    /**
     * @brief Get battery state: "charging", "full", "unplugged", or "" when unknown
     */
    std::string getBatteryState();

    /**
     * @brief Check if low power / battery saver mode is enabled
     */
    bool isLowPowerMode();

    /**
     * @brief Check for a Neural Engine (Apple arm64) or NPU (Android SoC family)
     */
    bool hasNeuralEngine();

    /**
     * @brief Resolve the performance/efficiency core split from the hardware.
     *
     * iOS reads sysctl hw.perflevel{0,1}.logicalcpu; Android groups cores by
     * cpuinfo_max_freq. Outputs are only written when true is returned.
     *
     * @return true when the split could be determined; false → caller falls
     *         back to its heuristic
     */
    bool getCoreSplit(int totalCores, int& perfCores, int& effCores);

    // =========================================================================
    // Configuration Getters (for HTTP requests in production mode)
    // =========================================================================

    /**
     * @brief Get configured API key
     */
    std::string getApiKey() const { return apiKey_; }

    /**
     * @brief Get configured base URL
     */
    std::string getBaseURL() const { return baseURL_; }

    /**
     * @brief Set SDK version (passed from TypeScript layer)
     * Must be called during initialization to ensure consistency
     */
    void setSdkVersion(const std::string& version) { sdkVersion_ = version; }

    /**
     * @brief Get SDK version
     *
     * Defaults to commons' canonical version and is overridden during init by
     * the generated TypeScript Phase 1 request envelope.
     */
    std::string getSdkVersion() const {
        return sdkVersion_.empty() ? std::string(rac_sdk_get_version()) : sdkVersion_;
    }

    // Note: getEnvironment() already defined above in "SDK Environment" section

    // =========================================================================
    // HTTP Methods for Device Registration / Telemetry
    // Matches Swift: CppBridge+Device.swift http_post callback
    // =========================================================================

    /**
     * @brief Synchronous HTTP POST for device registration / telemetry
     *
     * Uses the shared native rac_http_client_* transport. Required by C++
     * rac_device_manager, whose callback API expects synchronous HTTP.
     *
     * @param url Full URL to POST to
     * @param jsonBody JSON body string
     * @param apiKey Authorization token for the request (empty for keyless)
     * @return tuple<success, statusCode, responseBody, errorMessage>
     */
    std::tuple<bool, int, std::string, std::string>
    httpPostSync(const std::string &url, const std::string &jsonBody,
                 const std::string &apiKey);

  private:
    InitBridge() = default;
    ~InitBridge() = default;

    // Disable copy/move
    InitBridge(const InitBridge &) = delete;
    InitBridge &operator=(const InitBridge &) = delete;

    rac_result_t registerPlatformAdapter();
    void resetNativeState();

    bool initialized_ = false;
    bool adapterRegistered_ = false;
    rac_environment_t environment_ = RAC_ENV_DEVELOPMENT;

    // Configuration stored at initialization
    std::string apiKey_;
    std::string baseURL_;
    std::string deviceId_;
    std::string platform_;
    std::string sdkVersion_; // SDK version from TypeScript SDKConstants
    std::vector<uint8_t> phase2RequestBytes_;

    // Platform adapter - must persist for C++ to call
    rac_platform_adapter_t adapter_{};
};

} // namespace bridges
} // namespace runanywhere
