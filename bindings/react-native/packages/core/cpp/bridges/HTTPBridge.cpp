/**
 * @file HTTPBridge.cpp
 * @brief HTTP bridge implementation
 *
 * NOTE: Public RN HTTP is handled by rac_http_client_*; this bridge manages
 * shared bootstrap configuration only.
 */

#include "HTTPBridge.hpp"

#include <cstddef>

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

namespace {

void wipeAndClear(std::string &value) {
  volatile char *bytes = value.empty() ? nullptr : value.data();
  for (std::size_t i = 0; i < value.size(); ++i) {
    bytes[i] = '\0';
  }
  value.clear();
}

} // anonymous namespace

HTTPBridge& HTTPBridge::shared() {
    static HTTPBridge instance;
    return instance;
}

void HTTPBridge::configure(const std::string& baseURL, const std::string& apiKey) {
  std::lock_guard<std::mutex> lock(mutex_);
  wipeAndClear(apiKey_);
  baseURL_ = baseURL;
  apiKey_ = apiKey;
  configured_ = true;

  LOGI("HTTP bridge configured");
}

bool HTTPBridge::isConfigured() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return configured_;
}

std::string HTTPBridge::getBaseURL() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return baseURL_;
}

std::string HTTPBridge::getAPIKey() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return apiKey_;
}

void HTTPBridge::setAuthorizationToken(const std::string& token) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (authToken_) {
    wipeAndClear(*authToken_);
  }
    authToken_ = token;
    LOGD("Authorization token set");
}

std::optional<std::string> HTTPBridge::getAuthorizationToken() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return authToken_;
}

void HTTPBridge::clearAuthorizationToken() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (authToken_) {
    wipeAndClear(*authToken_);
  }
    authToken_.reset();
    LOGD("Authorization token cleared");
}

void HTTPBridge::reset() {
  std::lock_guard<std::mutex> lock(mutex_);
  wipeAndClear(apiKey_);
  if (authToken_) {
    wipeAndClear(*authToken_);
  }
  authToken_.reset();
  baseURL_.clear();
  configured_ = false;
  LOGD("HTTP configuration reset");
}

std::string HTTPBridge::buildURL(const std::string& endpoint) const {
  std::lock_guard<std::mutex> lock(mutex_);
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
