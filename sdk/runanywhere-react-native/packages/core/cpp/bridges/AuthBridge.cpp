/**
 * @file AuthBridge.cpp
 * @brief C++ bridge for authentication operations.
 *
 * NOTE: The RACommons library (librac_commons.so) does NOT export auth state
 * management functions. Authentication must be handled at the platform level
 * (TypeScript/Kotlin/Swift) with tokens managed outside of C++.
 *
 * This bridge provides a passthrough interface that delegates to platform.
 */

#include "AuthBridge.hpp"
#include "rac_error.h"
#include <stdexcept>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "AuthBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[AuthBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[AuthBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[AuthBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[AuthBridge WARN] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

// =============================================================================
// Singleton Implementation
// =============================================================================

AuthBridge& AuthBridge::shared() {
    static AuthBridge instance;
    return instance;
}

// =============================================================================
// Platform Callbacks
// =============================================================================

void AuthBridge::setPlatformCallbacks(const AuthPlatformCallbacks& callbacks) {
    platformCallbacks_ = callbacks;
    LOGI("Platform callbacks set for AuthBridge");
}

// =============================================================================
// JSON Building (Platform calls HTTP, we just format)
// =============================================================================

std::string AuthBridge::buildAuthenticateRequestJSON(
    const std::string& apiKey,
    const std::string& deviceId,
    const std::string& platform,
    const std::string& sdkVersion
) {
    // Simple JSON building without external dependencies
    std::string json = "{";
    json += "\"api_key\":\"" + apiKey + "\",";
    json += "\"device_id\":\"" + deviceId + "\",";
    json += "\"platform\":\"" + platform + "\",";
    json += "\"sdk_version\":\"" + sdkVersion + "\"";
    json += "}";
    return json;
}

std::string AuthBridge::buildRefreshRequestJSON(
    const std::string& refreshToken,
    const std::string& deviceId
) {
    std::string json = "{";
    json += "\"refresh_token\":\"" + refreshToken + "\",";
    json += "\"device_id\":\"" + deviceId + "\"";
    json += "}";
    return json;
}

// =============================================================================
// Response Handling (Parse JSON and extract fields)
// =============================================================================

AuthResponse AuthBridge::handleAuthResponse(const std::string& jsonResponse) {
    AuthResponse response;

    // Simple JSON parsing (extract key fields)
    // In production, use a proper JSON library
    auto extractString = [&](const std::string& key) -> std::string {
        std::string searchKey = "\"" + key + "\":\"";
        size_t pos = jsonResponse.find(searchKey);
        if (pos == std::string::npos) return "";
        pos += searchKey.length();
        size_t endPos = jsonResponse.find("\"", pos);
        if (endPos == std::string::npos) return "";
        return jsonResponse.substr(pos, endPos - pos);
    };

    auto extractInt = [&](const std::string& key) -> int64_t {
        std::string searchKey = "\"" + key + "\":";
        size_t pos = jsonResponse.find(searchKey);
        if (pos == std::string::npos) return 0;
        pos += searchKey.length();
        try {
            return std::stoll(jsonResponse.substr(pos));
        } catch (...) {
            return 0;
        }
    };

    response.accessToken = extractString("access_token");
    response.refreshToken = extractString("refresh_token");
    response.deviceId = extractString("device_id");
    response.userId = extractString("user_id");
    response.organizationId = extractString("organization_id");
    response.expiresIn = extractInt("expires_in");
    response.success = !response.accessToken.empty();

    if (!response.success) {
        response.error = extractString("error");
        if (response.error.empty()) {
            response.error = extractString("message");
        }
    }

    return response;
}

// =============================================================================
// State Management (Delegated to platform via callbacks)
// =============================================================================

void AuthBridge::setAuth(const AuthResponse& auth) {
    // Store locally for C++ access
    currentAuth_ = auth;
    isAuthenticated_ = auth.success && !auth.accessToken.empty();

    // Notify platform
    if (platformCallbacks_.onAuthStateChanged) {
        platformCallbacks_.onAuthStateChanged(isAuthenticated_);
    }

    LOGI("Auth state updated: authenticated=%d", isAuthenticated_ ? 1 : 0);
}

std::string AuthBridge::getAccessToken() const {
    if (platformCallbacks_.getAccessToken) {
        return platformCallbacks_.getAccessToken();
    }
    return currentAuth_.accessToken;
}

std::string AuthBridge::getRefreshToken() const {
    if (platformCallbacks_.getRefreshToken) {
        return platformCallbacks_.getRefreshToken();
    }
    return currentAuth_.refreshToken;
}

bool AuthBridge::isAuthenticated() const {
    if (platformCallbacks_.isAuthenticated) {
        return platformCallbacks_.isAuthenticated();
    }
    return isAuthenticated_;
}

bool AuthBridge::tokenNeedsRefresh() const {
    if (platformCallbacks_.tokenNeedsRefresh) {
        return platformCallbacks_.tokenNeedsRefresh();
    }
    // Default: check if we have refresh token but no valid access token
    return !currentAuth_.refreshToken.empty() && currentAuth_.accessToken.empty();
}

std::string AuthBridge::getUserId() const {
    if (platformCallbacks_.getUserId) {
        return platformCallbacks_.getUserId();
    }
    return currentAuth_.userId;
}

std::string AuthBridge::getOrganizationId() const {
    if (platformCallbacks_.getOrganizationId) {
        return platformCallbacks_.getOrganizationId();
    }
    return currentAuth_.organizationId;
}

void AuthBridge::clearAuth() {
    currentAuth_ = AuthResponse();
    isAuthenticated_ = false;

    if (platformCallbacks_.clearAuth) {
        platformCallbacks_.clearAuth();
    }

    if (platformCallbacks_.onAuthStateChanged) {
        platformCallbacks_.onAuthStateChanged(false);
    }

    LOGI("Auth state cleared");
}

} // namespace bridges
} // namespace runanywhere
