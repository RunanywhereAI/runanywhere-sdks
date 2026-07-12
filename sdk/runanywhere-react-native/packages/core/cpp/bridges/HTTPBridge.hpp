/**
 * @file HTTPBridge.hpp
 * @brief HTTP bridge documentation
 *
 * NOTE: React Native HTTP transport is now owned by native C++.
 *
 * Public Nitro methods use rac_http_client_* directly for auth and ad-hoc
 * requests. This bridge remains as shared configuration storage for C++
 * components that need base URL / API key state.
 *
 * This bridge provides:
 * - Configuration storage (base URL, API key)
 * - Authorization header management
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift
 */

#pragma once

#include <optional>
#include <string>

namespace runanywhere {
namespace bridges {

/**
 * HTTPBridge - shared HTTP configuration
 *
 * NOTE: Public RN HTTP requests use rac_http_client_* directly. This bridge
 * only stores configuration needed by native bootstrap callbacks.
 */
class HTTPBridge {
public:
    /**
     * Get shared instance
     */
    static HTTPBridge& shared();

    /**
     * Configure HTTP with base URL and API key
     */
    void configure(const std::string& baseURL, const std::string& apiKey);

    /**
     * Check if configured
     */
    bool isConfigured() const { return configured_; }

    /**
     * Get base URL
     */
    const std::string& getBaseURL() const { return baseURL_; }

    /**
     * Get API key
     */
    const std::string& getAPIKey() const { return apiKey_; }

    /**
     * Set authorization token
     */
    void setAuthorizationToken(const std::string& token);

    /**
     * Get authorization token
     */
    std::optional<std::string> getAuthorizationToken() const;

    /**
     * Clear authorization token
     */
    void clearAuthorizationToken();

    /**
     * Build full URL from endpoint
     */
    std::string buildURL(const std::string& endpoint) const;

private:
    HTTPBridge() = default;
    ~HTTPBridge() = default;
    HTTPBridge(const HTTPBridge&) = delete;
    HTTPBridge& operator=(const HTTPBridge&) = delete;

    bool configured_ = false;
    std::string baseURL_;
    std::string apiKey_;
    std::optional<std::string> authToken_;
};

} // namespace bridges
} // namespace runanywhere
