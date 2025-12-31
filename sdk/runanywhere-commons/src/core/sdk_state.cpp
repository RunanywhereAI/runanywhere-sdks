/**
 * @file sdk_state.cpp
 * @brief Implementation of centralized SDK state management
 *
 * C++ implementation using:
 * - Meyer's Singleton for thread-safe lazy initialization
 * - std::mutex for thread-safe state access
 * - std::string for automatic memory management
 * - std::optional for nullable values
 */

#include <cstring>
#include <ctime>
#include <mutex>
#include <optional>
#include <string>

#include "rac/core/rac_error.h"
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

        // Clear auth state
        access_token_.reset();
        refresh_token_.reset();
        token_expires_at_ = 0;
        user_id_.reset();
        organization_id_.reset();
        is_authenticated_ = false;

        // Clear device state
        is_device_registered_ = false;

        // Keep environment config (or clear it too for full reset)
        // is_initialized_ = false;
        // environment_ = RAC_ENV_DEVELOPMENT;
        // api_key_.clear();
        // base_url_.clear();
        // device_id_.clear();
    }

    void shutdown() {
        std::lock_guard<std::mutex> lock(mutex_);

        // Clear everything
        access_token_.reset();
        refresh_token_.reset();
        token_expires_at_ = 0;
        user_id_.reset();
        organization_id_.reset();
        is_authenticated_ = false;
        is_device_registered_ = false;
        is_initialized_ = false;
        environment_ = RAC_ENV_DEVELOPMENT;
        api_key_.clear();
        base_url_.clear();
        device_id_.clear();

        // Clear callbacks
        auth_changed_callback_ = nullptr;
        auth_changed_user_data_ = nullptr;
        persist_callback_ = nullptr;
        load_callback_ = nullptr;
        persistence_user_data_ = nullptr;
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
    // Auth State
    // ==========================================================================

    rac_result_t setAuth(const rac_auth_data_t* auth) {
        if (!auth)
            return RAC_ERROR_INVALID_ARGUMENT;

        bool was_authenticated;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            was_authenticated = is_authenticated_;

            access_token_ = auth->access_token ? auth->access_token : "";
            refresh_token_ = auth->refresh_token ? std::optional<std::string>(auth->refresh_token)
                                                 : std::nullopt;
            token_expires_at_ = auth->expires_at_unix;
            user_id_ = auth->user_id ? std::optional<std::string>(auth->user_id) : std::nullopt;
            organization_id_ = auth->organization_id
                                   ? std::optional<std::string>(auth->organization_id)
                                   : std::nullopt;

            if (auth->device_id && strlen(auth->device_id) > 0) {
                device_id_ = auth->device_id;
            }

            is_authenticated_ = true;
        }

        // Notify callback outside of lock
        notifyAuthChanged(true);

        // Persist to secure storage if callback registered
        persistAuth();

        return RAC_SUCCESS;
    }

    const char* getAccessToken() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!access_token_.has_value() || access_token_->empty()) {
            return nullptr;
        }
        return access_token_->c_str();
    }

    const char* getRefreshToken() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!refresh_token_.has_value()) {
            return nullptr;
        }
        return refresh_token_->c_str();
    }

    bool isAuthenticated() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!is_authenticated_ || !access_token_.has_value()) {
            return false;
        }
        // Check if token is expired
        if (token_expires_at_ > 0) {
            int64_t now = static_cast<int64_t>(std::time(nullptr));
            if (now >= token_expires_at_) {
                return false;
            }
        }
        return true;
    }

    bool tokenNeedsRefresh() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!is_authenticated_ || token_expires_at_ == 0) {
            return false;
        }
        int64_t now = static_cast<int64_t>(std::time(nullptr));
        // Refresh if expires within 60 seconds
        return (token_expires_at_ - now) <= 60;
    }

    int64_t getTokenExpiresAt() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return token_expires_at_;
    }

    const char* getUserId() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!user_id_.has_value()) {
            return nullptr;
        }
        return user_id_->c_str();
    }

    const char* getOrganizationId() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!organization_id_.has_value()) {
            return nullptr;
        }
        return organization_id_->c_str();
    }

    void clearAuth() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            access_token_.reset();
            refresh_token_.reset();
            token_expires_at_ = 0;
            user_id_.reset();
            organization_id_.reset();
            is_authenticated_ = false;
        }

        notifyAuthChanged(false);

        // Clear from secure storage
        if (persist_callback_) {
            persist_callback_("access_token", nullptr, persistence_user_data_);
            persist_callback_("refresh_token", nullptr, persistence_user_data_);
        }
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

    // ==========================================================================
    // Callbacks
    // ==========================================================================

    void setAuthChangedCallback(rac_auth_changed_callback_t callback, void* user_data) {
        std::lock_guard<std::mutex> lock(mutex_);
        auth_changed_callback_ = callback;
        auth_changed_user_data_ = user_data;
    }

    void setPersistenceCallbacks(rac_persist_callback_t persist, rac_load_callback_t load,
                                 void* user_data) {
        std::lock_guard<std::mutex> lock(mutex_);
        persist_callback_ = persist;
        load_callback_ = load;
        persistence_user_data_ = user_data;
    }

   private:
    SDKState() = default;
    ~SDKState() = default;

    void notifyAuthChanged(bool is_authenticated) {
        rac_auth_changed_callback_t callback;
        void* user_data;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            callback = auth_changed_callback_;
            user_data = auth_changed_user_data_;
        }
        if (callback) {
            callback(is_authenticated, user_data);
        }
    }

    void persistAuth() {
        rac_persist_callback_t callback;
        void* user_data;
        std::string access, refresh;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            callback = persist_callback_;
            user_data = persistence_user_data_;
            if (access_token_.has_value())
                access = *access_token_;
            if (refresh_token_.has_value())
                refresh = *refresh_token_;
        }
        if (callback) {
            if (!access.empty()) {
                callback("access_token", access.c_str(), user_data);
            }
            if (!refresh.empty()) {
                callback("refresh_token", refresh.c_str(), user_data);
            }
        }
    }

    // State
    mutable std::mutex mutex_;
    bool is_initialized_ = false;

    // Environment
    rac_environment_t environment_ = RAC_ENV_DEVELOPMENT;
    std::string api_key_;
    std::string base_url_;
    std::string device_id_;

    // Auth
    std::optional<std::string> access_token_;
    std::optional<std::string> refresh_token_;
    int64_t token_expires_at_ = 0;
    std::optional<std::string> user_id_;
    std::optional<std::string> organization_id_;
    bool is_authenticated_ = false;

    // Device
    bool is_device_registered_ = false;

    // Callbacks
    rac_auth_changed_callback_t auth_changed_callback_ = nullptr;
    void* auth_changed_user_data_ = nullptr;
    rac_persist_callback_t persist_callback_ = nullptr;
    rac_load_callback_t load_callback_ = nullptr;
    void* persistence_user_data_ = nullptr;
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

rac_result_t rac_state_set_auth(const rac_auth_data_t* auth) {
    return SDKState::instance().setAuth(auth);
}

const char* rac_state_get_access_token(void) {
    return SDKState::instance().getAccessToken();
}

const char* rac_state_get_refresh_token(void) {
    return SDKState::instance().getRefreshToken();
}

bool rac_state_is_authenticated(void) {
    return SDKState::instance().isAuthenticated();
}

bool rac_state_token_needs_refresh(void) {
    return SDKState::instance().tokenNeedsRefresh();
}

int64_t rac_state_get_token_expires_at(void) {
    return SDKState::instance().getTokenExpiresAt();
}

const char* rac_state_get_user_id(void) {
    return SDKState::instance().getUserId();
}

const char* rac_state_get_organization_id(void) {
    return SDKState::instance().getOrganizationId();
}

void rac_state_clear_auth(void) {
    SDKState::instance().clearAuth();
}

void rac_state_set_device_registered(bool registered) {
    SDKState::instance().setDeviceRegistered(registered);
}

bool rac_state_is_device_registered(void) {
    return SDKState::instance().isDeviceRegistered();
}

void rac_state_on_auth_changed(rac_auth_changed_callback_t callback, void* user_data) {
    SDKState::instance().setAuthChangedCallback(callback, user_data);
}

void rac_state_set_persistence_callbacks(rac_persist_callback_t persist, rac_load_callback_t load,
                                         void* user_data) {
    SDKState::instance().setPersistenceCallbacks(persist, load, user_data);
}

}  // extern "C"
