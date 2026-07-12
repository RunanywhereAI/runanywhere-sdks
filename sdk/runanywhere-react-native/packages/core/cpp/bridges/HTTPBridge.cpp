/**
 * @file HTTPBridge.cpp
 * @brief HTTP bridge implementation
 *
 * NOTE: Public RN HTTP is handled by rac_http_client_*; this bridge manages
 * shared bootstrap configuration only.
 */

#include "HTTPBridge.hpp"

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HTTPBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[HTTPBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[HTTPBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
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
