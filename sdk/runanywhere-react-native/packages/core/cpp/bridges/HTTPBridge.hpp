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
 * - Optional HTTP executor registration for legacy/platform-adapter callers
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift
 */

#pragma once

#include <cstdint>
#include <string>
#include <functional>
#include <optional>

namespace runanywhere {
namespace bridges {

/**
 * HTTP response
 */
struct HTTPResponse {
    int32_t statusCode = 0;
    std::string body;
    std::string error;
    bool success = false;
};

/**
 * HTTP executor callback type for legacy/platform-adapter callers.
 */
using HTTPExecutor = std::function<HTTPResponse(
    const std::string& method,
    const std::string& url,
    const std::string& body,
    bool requiresAuth
)>;

/**
 * HTTPBridge - HTTP configuration and executor registration
 *
 * NOTE: Public RN HTTP requests use rac_http_client_* directly. This bridge
 * handles configuration and keeps an optional executor for legacy callers.
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
     * Register HTTP executor (called by platform)
     *
     * This allows legacy C++ components to make HTTP requests through an
     * injected executor. Public RN callers use rac_http_client_* directly.
     */
    void setHTTPExecutor(HTTPExecutor executor);

    /**
     * Execute HTTP request via registered executor
     * Returns nullopt if no executor registered
     */
    std::optional<HTTPResponse> execute(
        const std::string& method,
        const std::string& endpoint,
        const std::string& body,
        bool requiresAuth
    );

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
    HTTPExecutor executor_;
};

} // namespace bridges
} // namespace runanywhere
