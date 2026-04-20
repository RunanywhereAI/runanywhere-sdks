// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "ra_download.h"
#include "ra_primitives.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;

class DownloadSha256Test : public ::testing::Test {
protected:
    fs::path test_file;
    void SetUp() override {
        test_file = fs::temp_directory_path() /
            ("ra_test_sha_" + std::to_string(getpid()) + ".bin");
        std::ofstream(test_file) << "hello world";
    }
    void TearDown() override {
        std::error_code ec;
        fs::remove(test_file, ec);
    }
};

TEST_F(DownloadSha256Test, ComputesKnownDigest) {
    // "hello world" SHA-256 = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
    char* hex = nullptr;
    ASSERT_EQ(ra_download_sha256_file(test_file.string().c_str(), &hex), RA_OK);
    ASSERT_TRUE(hex);
    EXPECT_STREQ(hex,
        "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9");
    ra_download_string_free(hex);
}

TEST_F(DownloadSha256Test, VerifyMatch) {
    EXPECT_EQ(ra_download_verify_sha256(
        test_file.string().c_str(),
        "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"),
        RA_OK);
}

TEST_F(DownloadSha256Test, VerifyMismatch) {
    EXPECT_EQ(ra_download_verify_sha256(
        test_file.string().c_str(),
        "0000000000000000000000000000000000000000000000000000000000000000"),
        RA_ERR_IO);
}

TEST(DownloadSha256, MissingFileRejected) {
    char* hex = nullptr;
    EXPECT_EQ(ra_download_sha256_file("/nonexistent/path/123", &hex),
                RA_ERR_INVALID_ARGUMENT);
}
