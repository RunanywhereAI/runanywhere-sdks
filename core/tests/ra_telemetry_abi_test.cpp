// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../abi/ra_telemetry.h"
#include "../abi/ra_primitives.h"

#include <cstdlib>
#include <string>

TEST(RaTelemetryAbi, DefaultPayloadEmitsSDKVersion) {
    char* out = nullptr;
    ASSERT_EQ(ra_telemetry_payload_default(&out), RA_OK);
    ASSERT_TRUE(out);
    const std::string body = out;
    EXPECT_NE(body.find("\"sdk_version\""), std::string::npos);
    EXPECT_NE(body.find("\"platform\""), std::string::npos);
    ra_telemetry_string_free(out);
}

TEST(RaTelemetryAbi, DeviceRegistrationToJson) {
    ra_device_registration_info_t info{};
    info.device_id              = "dev-abc";
    info.os_name                = "iOS";
    info.os_version             = "18.2";
    info.app_version            = "1.0";
    info.sdk_version            = "2.0.0";
    info.model_name             = "iPhone15,2";
    info.chip_name              = "Apple A17";
    info.total_memory_bytes     = 6000000000;
    info.available_storage_bytes = 45000000000;
    char* out = nullptr;
    ASSERT_EQ(ra_device_registration_to_json(&info, &out), RA_OK);
    ASSERT_TRUE(out);
    const std::string body = out;
    EXPECT_NE(body.find("\"device_id\":\"dev-abc\""), std::string::npos);
    EXPECT_NE(body.find("\"os_name\":\"iOS\""),       std::string::npos);
    EXPECT_NE(body.find("\"chip_name\":\"Apple A17\""), std::string::npos);
    EXPECT_NE(body.find("\"total_memory_bytes\":6000000000"), std::string::npos);
    ra_telemetry_string_free(out);
}

TEST(RaTelemetryAbi, ParseResponseExtractsCounts) {
    int32_t acc = 0, rej = 0;
    EXPECT_EQ(ra_telemetry_parse_response(
        "{\"accepted\":42,\"rejected\":3}", &acc, &rej), RA_OK);
    EXPECT_EQ(acc, 42);
    EXPECT_EQ(rej, 3);
}

TEST(RaTelemetryAbi, PropertiesToJson) {
    const char* pairs[] = { "model_id", "qwen", "ttft_ms", "123" };
    char* out = nullptr;
    ASSERT_EQ(ra_telemetry_properties_to_json(pairs, 2, &out), RA_OK);
    ASSERT_TRUE(out);
    const std::string body = out;
    EXPECT_NE(body.find("\"model_id\":\"qwen\""), std::string::npos);
    EXPECT_NE(body.find("\"ttft_ms\":\"123\""),   std::string::npos);
    ra_telemetry_string_free(out);
}

TEST(RaTelemetryAbi, EndpointReturnsNonEmpty) {
    const char* ep = ra_device_registration_endpoint();
    ASSERT_TRUE(ep);
    EXPECT_TRUE(std::string(ep).find("/v1/devices") != std::string::npos);
}
