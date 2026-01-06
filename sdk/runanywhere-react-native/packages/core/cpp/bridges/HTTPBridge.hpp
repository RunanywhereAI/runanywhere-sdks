/**
 * HTTPBridge.hpp
 *
 * C++ bridge for HTTP operations.
 * Calls rac_http_* API from runanywhere-commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift
 */

#pragma once

#include <string>
#include <map>
#include <functional>

namespace runanywhere {
namespace bridges {

/**
 * HTTP response
 */
struct HTTPResponse {
    int statusCode;
    std::string body;
    std::map<std::string, std::string> headers;
    std::string error;
};

/**
 * HTTP request callback type
 */
using HTTPCallback = std::function<void(const HTTPResponse&)>;

/**
 * HTTPBridge - HTTP operations via rac_http_* API
 */
class HTTPBridge {
public:
    /**
     * Get shared instance
     */
    static HTTPBridge& shared();

    /**
     * Configure HTTP transport
     * @param baseURL Base URL for API requests
     * @param apiKey API key for authentication
     */
    void configure(const std::string& baseURL, const std::string& apiKey);

    /**
     * Check if configured
     * @return true if HTTP is configured
     */
    bool isConfigured() const;

    /**
     * Perform GET request
     * @param endpoint API endpoint
     * @param callback Response callback
     */
    void get(const std::string& endpoint, HTTPCallback callback);

    /**
     * Perform POST request
     * @param endpoint API endpoint
     * @param body Request body (JSON)
     * @param callback Response callback
     */
    void post(const std::string& endpoint, const std::string& body, HTTPCallback callback);

    /**
     * Perform PUT request
     * @param endpoint API endpoint
     * @param body Request body (JSON)
     * @param callback Response callback
     */
    void put(const std::string& endpoint, const std::string& body, HTTPCallback callback);

    /**
     * Perform DELETE request
     * @param endpoint API endpoint
     * @param callback Response callback
     */
    void del(const std::string& endpoint, HTTPCallback callback);

    /**
     * Set authorization header
     * @param token Bearer token
     */
    void setAuthorizationToken(const std::string& token);

private:
    HTTPBridge() = default;
    ~HTTPBridge() = default;
    HTTPBridge(const HTTPBridge&) = delete;
    HTTPBridge& operator=(const HTTPBridge&) = delete;

    std::string baseURL_;
    std::string apiKey_;
    std::string authToken_;
    bool configured_ = false;
};

} // namespace bridges
} // namespace runanywhere
