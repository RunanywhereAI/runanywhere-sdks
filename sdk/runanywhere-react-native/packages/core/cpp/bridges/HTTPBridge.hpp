/**
 * @file HTTPBridge.hpp
 * @brief HTTP bridge documentation
 *
 * NOTE: HTTP is handled entirely by the JavaScript/platform layer.
 *
 * In Swift, HTTPService.swift handles all HTTP requests.
 * In React Native, the JS layer (HTTPService.ts) handles HTTP.
 *
 * C++ does NOT make HTTP requests directly. Instead:
 * 1. C++ provides JSON building functions (rac_auth_request_to_json, etc.)
 * 2. JS layer makes the HTTP request
 * 3. C++ parses the response (rac_auth_response_from_json, etc.)
 * 4. C++ stores state (rac_state_set_auth, etc.)
 *
 * This bridge provides:
 * - Configuration storage (base URL, API key)
 * - Authorization header management
 * - HTTP executor registration (for C++ components that need to make requests)
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift
 */

#pragma once

#include <string>
#include <functional>
#include <optional>

#include "rac_types.h"
#include "rac_http_client.h"

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
 * HTTP executor callback type
 * Platform provides this to handle HTTP requests
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
 * NOTE: Actual HTTP requests are made by the JS layer, not C++.
 * This bridge handles configuration and provides an executor for
 * C++ components that need HTTP access.
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
     * This allows C++ components to make HTTP requests through the platform.
     * The platform handles the actual network operations.
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
