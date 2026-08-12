/**
 * @file AuthBridge.cpp
 * @brief C++ bridge for authentication operations.
 *
 * Auth orchestration is owned by runanywhere-commons. This bridge only exposes
 * read-only native state helpers to the Nitro surface.
 */

#include "AuthBridge.hpp"

#include "rac/infrastructure/network/rac_auth_manager.h"

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

namespace {

std::string copyNullable(const char* value) {
    return value != nullptr ? std::string(value) : std::string();
}

} // anonymous namespace

// =============================================================================
// Singleton Implementation
// =============================================================================

AuthBridge& AuthBridge::shared() {
    static AuthBridge instance;
    return instance;
}

// State Management (Owned by commons)
// =============================================================================

std::string AuthBridge::getAccessToken() const {
    return copyNullable(rac_auth_get_access_token());
}

bool AuthBridge::isAuthenticated() const {
    return rac_auth_is_authenticated();
}

std::string AuthBridge::getUserId() const {
    return copyNullable(rac_auth_get_user_id());
}

std::string AuthBridge::getOrganizationId() const {
    return copyNullable(rac_auth_get_organization_id());
}

} // namespace bridges
} // namespace runanywhere
