// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "../net/environment.h"

#include <gtest/gtest.h>

#include <ctime>

namespace {

using ra::core::net::AuthManager;
using ra::core::net::AuthTokens;
using ra::core::net::Environment;

class AuthManagerFixture : public ::testing::Test {
protected:
    void TearDown() override {
        // Reset singleton state between tests.
        AuthManager::global().clear_tokens();
        AuthManager::global().set_api_key("");
        AuthManager::global().set_device_id("");
        AuthManager::global().set_device_registered(false);
    }
};

TEST_F(AuthManagerFixture, EnvironmentChangeResetsEndpoints) {
    auto& a = AuthManager::global();
    a.set_environment(Environment::kStaging);
    EXPECT_EQ(a.environment(), Environment::kStaging);
    EXPECT_NE(a.endpoints().api_base_url.find("staging"), std::string::npos);
    a.set_environment(Environment::kDev);
    EXPECT_NE(a.endpoints().api_base_url.find("localhost"), std::string::npos);
}

TEST_F(AuthManagerFixture, TokensWithoutExpiryAreTreatedAsActive) {
    AuthTokens t;
    t.access_token   = "abc";
    t.refresh_token  = "xyz";
    t.expires_at_unix = 0;
    AuthManager::global().set_tokens(t);
    EXPECT_TRUE(AuthManager::global().is_authenticated());
    EXPECT_FALSE(AuthManager::global().token_needs_refresh());
}

TEST_F(AuthManagerFixture, ExpiredTokensNotAuthenticated) {
    AuthTokens t;
    t.access_token   = "abc";
    t.expires_at_unix = std::time(nullptr) - 100;
    AuthManager::global().set_tokens(t);
    EXPECT_FALSE(AuthManager::global().is_authenticated());
}

TEST_F(AuthManagerFixture, TokensWithinHorizonNeedRefresh) {
    AuthTokens t;
    t.access_token   = "abc";
    t.expires_at_unix = std::time(nullptr) + 30;  // expires in 30 s
    AuthManager::global().set_tokens(t);
    EXPECT_TRUE(AuthManager::global().is_authenticated());
    EXPECT_TRUE(AuthManager::global().token_needs_refresh(/*horizon_s=*/60));
    EXPECT_FALSE(AuthManager::global().token_needs_refresh(/*horizon_s=*/10));
}

TEST_F(AuthManagerFixture, DeviceStateRoundTrips) {
    auto& a = AuthManager::global();
    a.set_device_id("device-xyz-123");
    EXPECT_EQ(a.device_id(), "device-xyz-123");
    EXPECT_FALSE(a.is_device_registered());
    a.set_device_registered(true);
    EXPECT_TRUE(a.is_device_registered());
}

}  // namespace
