/**
 * AuthBridge.hpp
 *
 * C++ bridge for authentication operations.
 * Calls rac_auth_* API from runanywhere-commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Auth.swift
 */

#pragma once

#include <string>
#include <functional>

namespace runanywhere {
namespace bridges {

/**
 * Authentication result
 */
struct AuthResult {
    bool success;
    std::string accessToken;
    std::string refreshToken;
    int64_t expiresIn;
    std::string deviceId;
    std::string userId;
    std::string organizationId;
    std::string error;
};

/**
 * AuthBridge - Authentication operations via rac_auth_* API
 */
class AuthBridge {
public:
    /**
     * Get shared instance
     */
    static AuthBridge& shared();

    /**
     * Authenticate with API key
     * @param apiKey API key for authentication
     * @return Authentication result
     */
    AuthResult authenticate(const std::string& apiKey);

    /**
     * Refresh access token
     * @return New access token or empty string on failure
     */
    std::string refreshAccessToken();

    /**
     * Get current access token
     * @return Access token or empty string
     */
    std::string getAccessToken() const;

    /**
     * Get current user ID
     * @return User ID or empty string
     */
    std::string getUserId() const;

    /**
     * Get current organization ID
     * @return Organization ID or empty string
     */
    std::string getOrganizationId() const;

    /**
     * Get current device ID
     * @return Device ID or empty string
     */
    std::string getDeviceId() const;

    /**
     * Check if authenticated
     * @return true if authenticated
     */
    bool isAuthenticated() const;

    /**
     * Clear authentication state
     */
    void clearAuthentication();

    /**
     * Load stored tokens from secure storage
     * @return true if tokens loaded successfully
     */
    bool loadStoredTokens();

private:
    AuthBridge() = default;
    ~AuthBridge() = default;
    AuthBridge(const AuthBridge&) = delete;
    AuthBridge& operator=(const AuthBridge&) = delete;

    // State
    std::string accessToken_;
    std::string refreshToken_;
    std::string userId_;
    std::string organizationId_;
    std::string deviceId_;
    bool isAuthenticated_ = false;
};

} // namespace bridges
} // namespace runanywhere
