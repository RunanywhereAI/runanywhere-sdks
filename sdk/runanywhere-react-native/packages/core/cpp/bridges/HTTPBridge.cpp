/**
 * @file HTTPBridge.cpp
 * @brief HTTP bridge implementation
 *
 * NOTE: HTTP is handled by the JS layer. This bridge manages configuration.
 */

#include "HTTPBridge.hpp"

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HTTPBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[HTTPBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[HTTPBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[HTTPBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

HTTPBridge& HTTPBridge::shared() {
    static HTTPBridge instance;
    return instance;
}

void HTTPBridge::configure(const std::string& baseURL, const std::string& apiKey) {
    baseURL_ = baseURL;
    apiKey_ = apiKey;
    configured_ = true;

    LOGI("HTTP configured: baseURL=%s", baseURL.c_str());
}

void HTTPBridge::setAuthorizationToken(const std::string& token) {
    authToken_ = token;
    LOGD("Authorization token set");
}

std::optional<std::string> HTTPBridge::getAuthorizationToken() const {
    return authToken_;
}

void HTTPBridge::clearAuthorizationToken() {
    authToken_.reset();
    LOGD("Authorization token cleared");
}

void HTTPBridge::setHTTPExecutor(HTTPExecutor executor) {
    executor_ = executor;
    LOGI("HTTP executor registered");
}

std::optional<HTTPResponse> HTTPBridge::execute(
    const std::string& method,
    const std::string& endpoint,
    const std::string& body,
    bool requiresAuth
) {
    if (!executor_) {
        LOGE("No HTTP executor registered - HTTP requests must go through JS layer");
        return std::nullopt;
    }

    std::string url = buildURL(endpoint);
    LOGD("Executing %s %s", method.c_str(), url.c_str());

    return executor_(method, url, body, requiresAuth);
}

std::string HTTPBridge::buildURL(const std::string& endpoint) const {
    if (baseURL_.empty()) {
        return endpoint;
    }

    // Ensure proper URL joining
    std::string url = baseURL_;
    if (!url.empty() && url.back() == '/') {
        url.pop_back();
    }

    if (!endpoint.empty() && endpoint.front() != '/') {
        url += '/';
    }

    url += endpoint;
    return url;
}

} // namespace bridges
} // namespace runanywhere
