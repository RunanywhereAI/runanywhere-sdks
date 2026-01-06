/**
 * HTTPBridge.cpp
 *
 * C++ bridge for HTTP operations.
 * Calls rac_http_* API from runanywhere-commons.
 */

#include "HTTPBridge.hpp"

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HTTPBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[HTTPBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[HTTPBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

// TODO: Include RACommons headers when available
// #include <rac_http_client.h>

namespace runanywhere {
namespace bridges {

HTTPBridge& HTTPBridge::shared() {
    static HTTPBridge instance;
    return instance;
}

void HTTPBridge::configure(const std::string& baseURL, const std::string& apiKey) {
    LOGI("Configuring HTTP: %s", baseURL.c_str());

    baseURL_ = baseURL;
    apiKey_ = apiKey;
    configured_ = true;

    // TODO: Call rac_http_configure when RACommons is linked
    #if 0
    rac_http_config_t config;
    config.base_url = baseURL.c_str();
    config.api_key = apiKey.c_str();
    config.timeout_ms = 30000;

    rac_http_configure(&config);
    #endif
}

bool HTTPBridge::isConfigured() const {
    return configured_;
}

void HTTPBridge::get(const std::string& endpoint, HTTPCallback callback) {
    LOGI("GET %s", endpoint.c_str());

    HTTPResponse response;

    // TODO: Call rac_http_get when RACommons is linked
    #if 0
    rac_http_request_t request;
    request.method = RAC_HTTP_GET;
    request.url = (baseURL_ + endpoint).c_str();

    rac_http_response_t rawResponse;
    auto status = rac_http_request(&request, &rawResponse);

    if (status == RAC_SUCCESS) {
        response.statusCode = rawResponse.status_code;
        response.body = rawResponse.body ? rawResponse.body : "";
    } else {
        response.statusCode = 0;
        response.error = "HTTP request failed";
    }
    #else
    // Development stub
    response.statusCode = 200;
    response.body = "{}";
    #endif

    if (callback) {
        callback(response);
    }
}

void HTTPBridge::post(const std::string& endpoint, const std::string& body, HTTPCallback callback) {
    LOGI("POST %s", endpoint.c_str());

    HTTPResponse response;

    // TODO: Call rac_http_post when RACommons is linked
    #if 0
    rac_http_request_t request;
    request.method = RAC_HTTP_POST;
    request.url = (baseURL_ + endpoint).c_str();
    request.body = body.c_str();
    request.content_type = "application/json";

    rac_http_response_t rawResponse;
    auto status = rac_http_request(&request, &rawResponse);

    if (status == RAC_SUCCESS) {
        response.statusCode = rawResponse.status_code;
        response.body = rawResponse.body ? rawResponse.body : "";
    } else {
        response.statusCode = 0;
        response.error = "HTTP request failed";
    }
    #else
    // Development stub
    response.statusCode = 200;
    response.body = "{}";
    #endif

    if (callback) {
        callback(response);
    }
}

void HTTPBridge::put(const std::string& endpoint, const std::string& body, HTTPCallback callback) {
    LOGI("PUT %s", endpoint.c_str());

    HTTPResponse response;

    // TODO: Call rac_http_put when RACommons is linked
    response.statusCode = 200;
    response.body = "{}";

    if (callback) {
        callback(response);
    }
}

void HTTPBridge::del(const std::string& endpoint, HTTPCallback callback) {
    LOGI("DELETE %s", endpoint.c_str());

    HTTPResponse response;

    // TODO: Call rac_http_delete when RACommons is linked
    response.statusCode = 200;
    response.body = "{}";

    if (callback) {
        callback(response);
    }
}

void HTTPBridge::setAuthorizationToken(const std::string& token) {
    authToken_ = token;

    // TODO: Call rac_http_set_auth_token when RACommons is linked
}

} // namespace bridges
} // namespace runanywhere
