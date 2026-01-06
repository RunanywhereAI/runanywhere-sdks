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

// RACommons headers
#include "rac/core/rac_core.h"
#include "rac/core/rac_types.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/network/rac_environment.h"

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
