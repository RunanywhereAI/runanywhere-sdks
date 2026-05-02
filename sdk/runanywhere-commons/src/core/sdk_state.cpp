/**
 * @file sdk_state.cpp
 * @brief Implementation of centralized SDK state management
 *
 * C++ implementation using:
 * - Meyer's Singleton for thread-safe lazy initialization
 * - std::mutex for thread-safe state access
 * - std::string for automatic memory management
 *
 * Holds non-auth state only. Auth state (tokens, user/org IDs, expiry,
 * refresh-window math, persistence) lives in rac_auth_manager.h /
 * auth_manager.cpp (the single source of truth).
 */

#include <mutex>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_sdk_state.h"

// =============================================================================
// Internal C++ State Class
// =============================================================================

class SDKState {
   public:
    // Singleton access (Meyer's Singleton - thread-safe in C++11)
    static SDKState& instance() {
        static SDKState instance;
        return instance;
    }

    // Delete copy/move constructors
    SDKState(const SDKState&) = delete;
    SDKState& operator=(const SDKState&) = delete;

    // ==========================================================================
    // Initialization
    // ==========================================================================

    rac_result_t initialize(rac_environment_t env, const char* api_key, const char* base_url,
                            const char* device_id) {
        std::lock_guard<std::mutex> lock(mutex_);

        environment_ = env;
        api_key_ = api_key ? api_key : "";
        base_url_ = base_url ? base_url : "";
        device_id_ = device_id ? device_id : "";
        is_initialized_ = true;

        return RAC_SUCCESS;
    }

    bool isInitialized() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return is_initialized_;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        // Clear device state only; environment config survives reset.
        is_device_registered_ = false;
    }

    void shutdown() {
        std::lock_guard<std::mutex> lock(mutex_);

        // Clear everything
        is_device_registered_ = false;
        is_initialized_ = false;
        environment_ = RAC_ENV_DEVELOPMENT;
        api_key_.clear();
        base_url_.clear();
        device_id_.clear();
    }

    // ==========================================================================
    // Environment Queries
    // ==========================================================================

    rac_environment_t getEnvironment() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return environment_;
    }

    const char* getBaseUrl() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return base_url_.c_str();
    }

    const char* getApiKey() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return api_key_.c_str();
    }

    const char* getDeviceId() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return device_id_.c_str();
    }

    // ==========================================================================
    // Device State
    // ==========================================================================

    void setDeviceRegistered(bool registered) {
        std::lock_guard<std::mutex> lock(mutex_);
        is_device_registered_ = registered;
    }

    bool isDeviceRegistered() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return is_device_registered_;
    }

   private:
    SDKState() = default;
    ~SDKState() = default;

    // State
    mutable std::mutex mutex_;
    bool is_initialized_ = false;

    // Environment
    rac_environment_t environment_ = RAC_ENV_DEVELOPMENT;
    std::string api_key_;
    std::string base_url_;
    std::string device_id_;

    // Device
    bool is_device_registered_ = false;
};

// =============================================================================
// C API Implementation
// =============================================================================

extern "C" {

rac_sdk_state_handle_t rac_state_get_instance(void) {
    return reinterpret_cast<rac_sdk_state_handle_t>(&SDKState::instance());
}

rac_result_t rac_state_initialize(rac_environment_t env, const char* api_key, const char* base_url,
                                  const char* device_id) {
    return SDKState::instance().initialize(env, api_key, base_url, device_id);
}

bool rac_state_is_initialized(void) {
    return SDKState::instance().isInitialized();
}

void rac_state_reset(void) {
    SDKState::instance().reset();
}

void rac_state_shutdown(void) {
    SDKState::instance().shutdown();
}

rac_environment_t rac_state_get_environment(void) {
    return SDKState::instance().getEnvironment();
}

const char* rac_state_get_base_url(void) {
    return SDKState::instance().getBaseUrl();
}

const char* rac_state_get_api_key(void) {
    return SDKState::instance().getApiKey();
}

const char* rac_state_get_device_id(void) {
    return SDKState::instance().getDeviceId();
}

void rac_state_set_device_registered(bool registered) {
    SDKState::instance().setDeviceRegistered(registered);
}

bool rac_state_is_device_registered(void) {
    return SDKState::instance().isDeviceRegistered();
}

}  // extern "C"
