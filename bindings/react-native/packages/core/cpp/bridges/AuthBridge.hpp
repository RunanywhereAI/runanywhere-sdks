/**
 * @file AuthBridge.hpp
 * @brief C++ bridge for authentication operations.
 *
 * Auth orchestration (request JSON, refresh, response parsing, token
 * persistence) is owned by runanywhere-commons. This bridge only exposes
 * read-only native state helpers to the Nitro surface.
 */

#pragma once

#include <string>

namespace runanywhere {
namespace bridges {

/**
 * AuthBridge - Authentication state management
 *
 * Provides read-only access to the commons auth manager.
 */
class AuthBridge {
public:
    /**
     * Get shared instance
     */
    static AuthBridge& shared();

    /**
     * Get current access token
     */
    std::string getAccessToken() const;

    /**
     * Check if currently authenticated
     */
    bool isAuthenticated() const;

    /**
     * Get user ID
     */
    std::string getUserId() const;

    /**
     * Get organization ID
     */
    std::string getOrganizationId() const;

private:
    AuthBridge() = default;
    ~AuthBridge() = default;
    AuthBridge(const AuthBridge&) = delete;
    AuthBridge& operator=(const AuthBridge&) = delete;
};

} // namespace bridges
} // namespace runanywhere
