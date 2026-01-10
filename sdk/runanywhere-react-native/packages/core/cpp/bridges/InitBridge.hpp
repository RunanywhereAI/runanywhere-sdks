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

#include <string>
#include <functional>
#include <memory>
#include <tuple>

// RACommons headers
#include "rac_core.h"
#include "rac_types.h"
#include "rac_platform_adapter.h"
#include "rac_sdk_state.h"
#include "rac_environment.h"
#include "rac_model_paths.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief Platform callbacks provided by React Native/JavaScript layer
 *
 * These callbacks are invoked by C++ when platform-specific operations are needed.
 */
struct PlatformCallbacks {
    // File operations
    std::function<bool(const std::string& path)> fileExists;
    std::function<std::string(const std::string& path)> fileRead;
    std::function<bool(const std::string& path, const std::string& data)> fileWrite;
    std::function<bool(const std::string& path)> fileDelete;

    // Secure storage (keychain/keystore)
    std::function<std::string(const std::string& key)> secureGet;
    std::function<bool(const std::string& key, const std::string& value)> secureSet;
    std::function<bool(const std::string& key)> secureDelete;

    // Logging
    std::function<void(int level, const std::string& category, const std::string& message)> log;

    // Clock
    std::function<int64_t()> nowMs;
};

/**
 * @brief SDK Environment enum matching Swift's SDKEnvironment
 */
enum class SDKEnvironment {
    Development = 0,
    Staging = 1,
    Production = 2
};

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
     * @brief Register platform callbacks
     *
     * Must be called BEFORE initialize() to set up platform operations.
     *
     * @param callbacks Platform-specific callbacks
     */
    void setPlatformCallbacks(const PlatformCallbacks& callbacks);

    /**
     * @brief Initialize the SDK
     *
     * 1. Registers platform adapter with RACommons
     * 2. Configures logging for environment
     * 3. Initializes SDK state
     *
     * @param environment SDK environment (development, staging, production)
     * @param apiKey API key for authentication
     * @param baseURL Base URL for API requests
     * @param deviceId Persistent device identifier
     * @return RAC_SUCCESS or error code
     */
    rac_result_t initialize(SDKEnvironment environment,
                           const std::string& apiKey,
                           const std::string& baseURL,
                           const std::string& deviceId);

    /**
     * @brief Set base directory for model paths
     *
     * Must be called after initialize() and before using model path utilities.
     * Mirrors Swift's CppBridge.ModelPaths.setBaseDirectory().
     *
     * @param documentsPath Path to Documents directory
     * @return RAC_SUCCESS or error code
     */
    rac_result_t setBaseDirectory(const std::string& documentsPath);

    /**
     * @brief Shutdown the SDK
     */
    void shutdown();

    /**
     * @brief Check if SDK is initialized
     */
    bool isInitialized() const { return initialized_; }

    /**
     * @brief Get current environment
     */
    SDKEnvironment getEnvironment() const { return environment_; }

    /**
     * @brief Convert SDK environment to RAC environment
     */
    static rac_environment_t toRacEnvironment(SDKEnvironment env);

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
     * @brief Delete a value from secure storage
     * @param key Storage key
     * @return true if deleted or didn't exist
     */
    bool secureDelete(const std::string& key);

    /**
     * @brief Check if a key exists in secure storage
     * @param key Storage key
     * @return true if key exists
     */
    bool secureExists(const std::string& key);

    /**
     * @brief Get or create persistent device UUID
     *
     * Strategy (matches Swift DeviceIdentity):
     * 1. Try to load from secure storage (survives reinstalls)
     * 2. If not found, generate new UUID and store
     *
     * @return Persistent device UUID
     */
    std::string getPersistentDeviceUUID();

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

    // =========================================================================
    // HTTP Methods for Device Registration
    // Matches Swift: CppBridge+Device.swift http_post callback
    // =========================================================================

    /**
     * @brief Synchronous HTTP POST for device registration
     *
     * Uses native URLSession (iOS) or HttpURLConnection (Android).
     * Required by C++ rac_device_manager which expects synchronous HTTP.
     *
     * @param url Full URL to POST to
     * @param jsonBody JSON body string
     * @param supabaseKey Supabase API key (for dev mode, empty for prod)
     * @return tuple<success, statusCode, responseBody, errorMessage>
     */
    std::tuple<bool, int, std::string, std::string> httpPostSync(
        const std::string& url,
        const std::string& jsonBody,
        const std::string& supabaseKey
    );

private:
    InitBridge() = default;
    ~InitBridge();

    // Disable copy/move
    InitBridge(const InitBridge&) = delete;
    InitBridge& operator=(const InitBridge&) = delete;

    void registerPlatformAdapter();

    bool initialized_ = false;
    bool adapterRegistered_ = false;
    SDKEnvironment environment_ = SDKEnvironment::Development;

    // Configuration stored at initialization
    std::string apiKey_;
    std::string baseURL_;
    std::string deviceId_;

    // Platform adapter - must persist for C++ to call
    rac_platform_adapter_t adapter_{};

    // Platform callbacks from JS layer
    PlatformCallbacks callbacks_{};
};

} // namespace bridges
} // namespace runanywhere
