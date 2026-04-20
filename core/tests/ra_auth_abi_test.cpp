// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../abi/ra_auth.h"
#include "../abi/ra_state.h"
#include "../abi/ra_primitives.h"

#include <cstdlib>
#include <cstring>
#include <string>

TEST(RaAuthAbi, InitReset) {
    EXPECT_EQ(ra_auth_init(), RA_OK);
    EXPECT_EQ(ra_auth_reset(), RA_OK);
}

TEST(RaAuthAbi, BuildAuthenticateRequest) {
    char* out = nullptr;
    ASSERT_EQ(ra_auth_build_authenticate_request("my-api-key", "dev-123", &out), RA_OK);
    ASSERT_TRUE(out);
    const std::string body = out;
    EXPECT_NE(body.find("\"api_key\":\"my-api-key\""), std::string::npos);
    EXPECT_NE(body.find("\"device_id\":\"dev-123\""), std::string::npos);
    ra_auth_string_free(out);
}

TEST(RaAuthAbi, HandleAuthenticateResponseSetsTokens) {
    const char* body = R"({
        "access_token": "acc123",
        "refresh_token": "ref456",
        "expires_in": 3600,
        "user_id": "u-1",
        "organization_id": "o-1"
    })";
    ra_auth_clear();
    ASSERT_EQ(ra_auth_handle_authenticate_response(body), RA_OK);
    EXPECT_STREQ(ra_auth_get_access_token(),  "acc123");
    EXPECT_STREQ(ra_auth_get_refresh_token(), "ref456");
    EXPECT_STREQ(ra_auth_get_user_id(),       "u-1");
    EXPECT_STREQ(ra_auth_get_organization_id(), "o-1");
    EXPECT_EQ(ra_auth_is_authenticated(), 1);
}

TEST(RaAuthAbi, HandleRefreshResponseUpdatesAccessToken) {
    ra_auth_handle_authenticate_response(
        "{\"access_token\":\"old\",\"refresh_token\":\"r1\",\"expires_in\":3600}");
    EXPECT_STREQ(ra_auth_get_access_token(), "old");
    const char* refresh = "{\"access_token\":\"new\",\"expires_in\":3600}";
    ASSERT_EQ(ra_auth_handle_refresh_response(refresh), RA_OK);
    EXPECT_STREQ(ra_auth_get_access_token(), "new");
    // refresh_token should persist since the refresh body didn't include one
    EXPECT_STREQ(ra_auth_get_refresh_token(), "r1");
}

TEST(RaAuthAbi, GetValidTokenReturnsNullWhenUnauthenticated) {
    ra_auth_clear();
    EXPECT_EQ(ra_auth_get_valid_token(), nullptr);
}

TEST(RaAuthAbi, GetValidTokenReturnsAccessTokenWhenAuthenticated) {
    ra_auth_handle_authenticate_response(
        "{\"access_token\":\"valid-token-123\",\"expires_in\":3600}");
    const char* t = ra_auth_get_valid_token();
    ASSERT_NE(t, nullptr);
    EXPECT_STREQ(t, "valid-token-123");
}
