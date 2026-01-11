/**
 * @file AuthBridge.hpp
 * @brief C++ bridge for authentication operations.
 *
 * NOTE: The RACommons library (librac_commons.so) does NOT export auth state
 * management functions. Authentication must be handled at the platform level
 * (TypeScript/Kotlin/Swift) with tokens managed outside of C++.
 *
 * This bridge provides a passthrough interface that delegates to platform.
 */

#pragma once

#include <string>
#include <functional>

namespace runanywhere {
namespace bridges {

/**
 * Auth response structure
 */
struct AuthResponse {
    bool success = false;
    std::string accessToken;
    std::string refreshToken;
    std::string deviceId;
    std::string userId;
    std::string organizationId;
    int64_t expiresIn = 0;
    std::string error;
};

/**
 * Platform callbacks for auth operations
 *
 * Platform (TypeScript/Kotlin/Swift) implements secure storage
 * and HTTP operations, this C++ layer just provides the interface.
 */
struct AuthPlatformCallbacks {
    // Get tokens from platform secure storage
    std::function<std::string()> getAccessToken;
    std::function<std::string()> getRefreshToken;

    // Query auth state
    std::function<bool()> isAuthenticated;
    std::function<bool()> tokenNeedsRefresh;

    // Get user info
    std::function<std::string()> getUserId;
    std::function<std::string()> getOrganizationId;

    // Clear auth (logout)
    std::function<void()> clearAuth;

    // Notify platform of auth state changes
    std::function<void(bool authenticated)> onAuthStateChanged;
};

/**
 * AuthBridge - Authentication state management
 *
 * Provides JSON building/parsing utilities and state access.
 * Actual HTTP calls and secure storage are done by platform.
 */
class AuthBridge {
public:
    /**
     * Get shared instance
     */
    static AuthBridge& shared();

    /**
     * Set platform callbacks
     * Must be called during SDK initialization
     */
    void setPlatformCallbacks(const AuthPlatformCallbacks& callbacks);

    /**
     * Build authenticate request JSON
     * Platform uses this to make HTTP POST to /api/v1/auth/sdk/authenticate
     */
    std::string buildAuthenticateRequestJSON(
        const std::string& apiKey,
        const std::string& deviceId,
        const std::string& platform,
        const std::string& sdkVersion
    );

    /**
     * Build refresh request JSON
     * Platform uses this to make HTTP POST to /api/v1/auth/sdk/refresh
     */
    std::string buildRefreshRequestJSON(
        const std::string& refreshToken,
        const std::string& deviceId
    );

    /**
     * Handle authentication response JSON
     * Returns parsed AuthResponse
     */
    AuthResponse handleAuthResponse(const std::string& jsonResponse);

    /**
     * Set auth state (called by platform after successful auth)
     */
    void setAuth(const AuthResponse& auth);

    /**
     * Get current access token
     */
    std::string getAccessToken() const;

    /**
     * Get current refresh token
     */
    std::string getRefreshToken() const;

    /**
     * Check if currently authenticated
     */
    bool isAuthenticated() const;

    /**
     * Check if token needs refresh
     */
    bool tokenNeedsRefresh() const;

    /**
     * Get user ID
     */
    std::string getUserId() const;

    /**
     * Get organization ID
     */
    std::string getOrganizationId() const;

    /**
     * Clear authentication state
     */
    void clearAuth();

private:
    AuthBridge() = default;
    ~AuthBridge() = default;
    AuthBridge(const AuthBridge&) = delete;
    AuthBridge& operator=(const AuthBridge&) = delete;

    AuthPlatformCallbacks platformCallbacks_{};
    AuthResponse currentAuth_{};
    bool isAuthenticated_ = false;
};

} // namespace bridges
} // namespace runanywhere
