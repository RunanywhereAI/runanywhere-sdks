// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Smoke tests for the Phase A C-ABI extension surfaces. Validates the
// thin-wrapper layer (no plugin needed for tool/structured/image/file/storage/
// extract/device/event/http/benchmark; dispatch tests live in the live
// engine integrations).

#include <gtest/gtest.h>

#include "../abi/ra_benchmark.h"
#include "../abi/ra_device.h"
#include "../abi/ra_event.h"
#include "../abi/ra_extract.h"
#include "../abi/ra_file.h"
#include "../abi/ra_http.h"
#include "../abi/ra_image.h"
#include "../abi/ra_platform_llm.h"
#include "../abi/ra_storage.h"
#include "../abi/ra_structured.h"
#include "../abi/ra_telemetry.h"
#include "../abi/ra_tool.h"

#include <cstring>
#include <string>

// --- ra_tool ----------------------------------------------------------------
TEST(RaToolAbi, DetectsDefaultFormat) {
    EXPECT_EQ(ra_tool_call_detect_format("hello world"), RA_TOOL_CALL_FORMAT_DEFAULT);
    EXPECT_EQ(ra_tool_call_detect_format("<|tool_call_start|>foo<|tool_call_end|>"),
              RA_TOOL_CALL_FORMAT_LFM2);
}

TEST(RaToolAbi, ParsesDefaultPayload) {
    ra_tool_call_t call{};
    auto rc = ra_tool_call_parse(
        "answer is <tool_call>{\"tool\":\"add\",\"arguments\":{\"a\":1}}</tool_call> done",
        &call);
    ASSERT_EQ(rc, RA_OK);
    EXPECT_EQ(call.has_call, 1);
    ASSERT_TRUE(call.tool_name);
    EXPECT_STREQ(call.tool_name, "add");
    ASSERT_TRUE(call.arguments_json);
    EXPECT_NE(std::string{call.arguments_json}.find("\"a\":1"), std::string::npos);
    ra_tool_call_free(&call);
}

TEST(RaToolAbi, FormatNameMatchesEnum) {
    EXPECT_STREQ(ra_tool_call_format_name(RA_TOOL_CALL_FORMAT_LFM2), "lfm2");
    EXPECT_STREQ(ra_tool_call_format_name(RA_TOOL_CALL_FORMAT_DEFAULT), "default");
    EXPECT_EQ(ra_tool_call_format_from_name("LFM2"), RA_TOOL_CALL_FORMAT_LFM2);
}

TEST(RaToolAbi, BuildsInitialPrompt) {
    ra_tool_parameter_t p{"city", "string", "City name", 1, {0,0,0}};
    ra_tool_definition_t t{"get_weather", "Get weather", &p, 1};
    char* prompt = nullptr;
    auto rc = ra_tool_call_build_initial_prompt(&t, 1, "what's the weather?",
                                                 RA_TOOL_CALL_FORMAT_DEFAULT, &prompt);
    ASSERT_EQ(rc, RA_OK);
    ASSERT_TRUE(prompt);
    EXPECT_NE(std::string{prompt}.find("get_weather"), std::string::npos);
    EXPECT_NE(std::string{prompt}.find("what's the weather?"), std::string::npos);
    ra_tool_string_free(prompt);
}

// --- ra_structured ----------------------------------------------------------
TEST(RaStructuredAbi, ExtractsJson) {
    char* out = nullptr;
    auto rc = ra_structured_output_extract_json("garbage {\"a\":1,\"b\":2} more", &out);
    ASSERT_EQ(rc, RA_OK);
    ASSERT_TRUE(out);
    EXPECT_STREQ(out, "{\"a\":1,\"b\":2}");
    ra_structured_output_string_free(out);
}

TEST(RaStructuredAbi, FindsMatchingBrace) {
    EXPECT_EQ(ra_structured_output_find_matching_brace("{\"x\":\"}\"}", 0), 8);
    EXPECT_EQ(ra_structured_output_find_matching_bracket("[1,[2,3],4]", 0), 10);
}

TEST(RaStructuredAbi, BuildsSystemPrompt) {
    ra_structured_output_config_t cfg{};
    cfg.json_schema = "{\"type\":\"object\"}";
    cfg.strict      = 1;
    char* prompt = nullptr;
    ASSERT_EQ(ra_structured_output_get_system_prompt(&cfg, &prompt), RA_OK);
    ASSERT_TRUE(prompt);
    EXPECT_NE(std::string{prompt}.find("JSON Schema"), std::string::npos);
    ra_structured_output_string_free(prompt);
}

// --- ra_image ---------------------------------------------------------------
TEST(RaImageAbi, CalcResizePreservesAspect) {
    int32_t w = 0, h = 0;
    ra_image_calc_resize(800, 400, 200, &w, &h);
    EXPECT_EQ(w, 200);
    EXPECT_EQ(h, 100);
    ra_image_calc_resize(100, 100, 200, &w, &h);
    EXPECT_EQ(w, 100);
    EXPECT_EQ(h, 100);
}

TEST(RaImageAbi, ResizeRgbBilinear) {
    uint8_t pixels[3 * 4 * 4] = {0};  // 4x4 RGB, all zero
    ra_image_data_t in{pixels, 4, 4, 4 * 3, RA_VLM_IMAGE_FORMAT_RGB};
    ra_image_data_t out{};
    ASSERT_EQ(ra_image_resize(&in, 2, 2, 1, &out), RA_OK);
    EXPECT_EQ(out.width, 2);
    EXPECT_EQ(out.height, 2);
    EXPECT_EQ(out.format, RA_VLM_IMAGE_FORMAT_RGB);
    ra_image_free(&out);
}

// --- ra_file / ra_storage ---------------------------------------------------
TEST(RaFileAbi, AppDirsAreNonEmpty) {
    char* p = nullptr;
    ASSERT_EQ(ra_file_app_support_dir(&p), RA_OK);
    ASSERT_TRUE(p && p[0]);
    ra_file_string_free(p);
}

TEST(RaStorageAbi, DiskSpaceForCwd) {
    ra_storage_disk_space_t info{};
    EXPECT_EQ(ra_storage_disk_space_for(".", &info), RA_OK);
    EXPECT_GT(info.capacity_bytes, 0);
}

// --- ra_extract -------------------------------------------------------------
TEST(RaExtractAbi, DetectsArchiveType) {
    EXPECT_EQ(ra_detect_archive_type("foo.zip"), RA_ARCHIVE_ZIP);
    EXPECT_EQ(ra_detect_archive_type("foo.tar.gz"), RA_ARCHIVE_TAR_GZ);
    EXPECT_EQ(ra_detect_archive_type("foo.bin"), RA_ARCHIVE_UNKNOWN);
}

// --- ra_device --------------------------------------------------------------
TEST(RaDeviceAbi, RegisterWithoutCallbacksReportsBackendUnavailable) {
    // No bridge registered; the call should report backend unavailable
    // unless the device is already flagged registered.
    auto rc = ra_device_manager_register_if_needed();
    EXPECT_TRUE(rc == RA_OK || rc == RA_ERR_BACKEND_UNAVAILABLE);
}

// --- ra_event ---------------------------------------------------------------
TEST(RaEventAbi, SubscribeAndPublish) {
    int hits = 0;
    auto cb = +[](const ra_event_t* e, void* ud) {
        if (e && e->category == RA_EVENT_CATEGORY_LIFECYCLE) ++(*static_cast<int*>(ud));
    };
    auto id = ra_event_subscribe(RA_EVENT_CATEGORY_LIFECYCLE, cb, &hits);
    ASSERT_GE(id, 0);
    ra_event_t ev{RA_EVENT_CATEGORY_LIFECYCLE, "test", nullptr, 0};
    ra_event_publish(&ev);
    EXPECT_EQ(hits, 1);
    EXPECT_EQ(ra_event_unsubscribe(id), RA_OK);
}

// --- ra_http ----------------------------------------------------------------
TEST(RaHttpAbi, NoExecutorReturnsUnsupported) {
    ra_http_set_executor(nullptr, nullptr);
    EXPECT_EQ(ra_http_has_executor(), 0);
    ra_http_request_t req{RA_HTTP_GET, "https://example.com", nullptr, 0, nullptr, 0, 0};
    ra_http_response_t resp{};
    EXPECT_EQ(ra_http_execute(&req, &resp), RA_ERR_CAPABILITY_UNSUPPORTED);
}

// --- ra_telemetry -----------------------------------------------------------
TEST(RaTelemetryAbi, TrackEmits) {
    EXPECT_EQ(ra_telemetry_track("test_event", nullptr), RA_OK);
}

// --- ra_platform_llm --------------------------------------------------------
TEST(RaPlatformLlmAbi, UnregisteredBackendUnavailable) {
    EXPECT_EQ(ra_platform_llm_is_available(RA_PLATFORM_LLM_FOUNDATION_MODELS, nullptr), 0);
}

// --- ra_benchmark -----------------------------------------------------------
TEST(RaBenchmarkAbi, MonotonicNowIncreases) {
    auto a = ra_monotonic_now_ms();
    auto b = ra_monotonic_now_ms();
    EXPECT_GE(b, a);
}

TEST(RaBenchmarkAbi, StatsSummary) {
    ra_benchmark_stats_t* s = nullptr;
    ASSERT_EQ(ra_benchmark_stats_create(&s), RA_OK);
    for (double v : {1.0, 2.0, 3.0, 4.0, 5.0}) ra_benchmark_stats_record(s, v);
    EXPECT_EQ(ra_benchmark_stats_count(s), 5);
    ra_benchmark_summary_t sum{};
    EXPECT_EQ(ra_benchmark_stats_get_summary(s, &sum), RA_OK);
    EXPECT_DOUBLE_EQ(sum.min_value, 1.0);
    EXPECT_DOUBLE_EQ(sum.max_value, 5.0);
    EXPECT_DOUBLE_EQ(sum.mean_value, 3.0);
    EXPECT_GE(sum.p95, 4.0);
    ra_benchmark_stats_destroy(s);
}

TEST(RaBenchmarkAbi, TimingJson) {
    ra_benchmark_timing_t t{};
    ra_benchmark_timing_init(&t, "decode");
    ra_benchmark_timing_finish(&t);
    char* json = nullptr;
    ASSERT_EQ(ra_benchmark_timing_to_json(&t, &json), RA_OK);
    EXPECT_NE(std::string{json}.find("\"label\":\"decode\""), std::string::npos);
    ra_benchmark_string_free(json);
    if (t.label) std::free(t.label);
}
