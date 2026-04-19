// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Tests for the extern "C" ABI surface that frontends link against.
// These functions are tiny and unglamorous but are the *only* thing
// every frontend binding calls by name — if they drift, every frontend
// breaks silently. A cheap unit test catches that at C++ CI time.

#include <gtest/gtest.h>

extern "C" {
#include "../abi/ra_primitives.h"
#include "../abi/ra_version.h"
}

TEST(AbiStatusStr, AllKnownCodesHaveDescriptiveString) {
    // Every status code must return a non-null, non-empty string. Walking
    // the known codes ensures no case falls through to "Unknown error"
    // silently.
    const ra_status_t codes[] = {
        RA_OK,
        RA_ERR_CANCELLED,
        RA_ERR_INVALID_ARGUMENT,
        RA_ERR_MODEL_LOAD_FAILED,
        RA_ERR_MODEL_NOT_FOUND,
        RA_ERR_RUNTIME_UNAVAILABLE,
        RA_ERR_BACKEND_UNAVAILABLE,
        RA_ERR_CAPABILITY_UNSUPPORTED,
        RA_ERR_OUT_OF_MEMORY,
        RA_ERR_IO,
        RA_ERR_TIMEOUT,
        RA_ERR_ABI_MISMATCH,
        RA_ERR_INTERNAL,
    };
    for (auto code : codes) {
        const char* s = ra_status_str(code);
        ASSERT_NE(s, nullptr);
        EXPECT_NE(std::string(s), "") << "empty string for code " << code;
        EXPECT_NE(std::string(s), "Unknown error")
            << "code " << code << " fell through to Unknown error branch";
    }
}

TEST(AbiStatusStr, UnknownCodeReturnsUnknownError) {
    EXPECT_STREQ(ra_status_str(-9999), "Unknown error");
}

TEST(AbiStatusStr, OkReturnsOk) {
    EXPECT_STREQ(ra_status_str(RA_OK), "OK");
}

TEST(AbiVersion, AbiAndPluginVersionsAreNonZero) {
    // The ABI version carries meaningful value only if it's non-zero; an
    // all-zero version would mean the RA_ABI_VERSION macro wasn't wired
    // up correctly.
    EXPECT_NE(ra_abi_version(), 0u);
    EXPECT_NE(ra_plugin_api_version(), 0u);
}

TEST(AbiVersion, BuildInfoIsNonEmpty) {
    const char* info = ra_build_info();
    ASSERT_NE(info, nullptr);
    EXPECT_GT(std::string(info).size(), 0u);
}
