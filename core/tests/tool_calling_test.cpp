// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "../util/tool_calling.h"

#include <gtest/gtest.h>

namespace {

using ra::core::util::parse_tool_call;
using ra::core::util::detect_tool_call_format;
using ra::core::util::tool_call_format_from_name;
using ra::core::util::ToolCallFormat;

TEST(ToolCalling, DefaultFormatExtractsNameAndArgs) {
    const std::string out =
        "I'll check the weather. <tool_call>{\"tool\":\"get_weather\","
        "\"arguments\":{\"city\":\"SF\"}}</tool_call> Thinking...";
    const auto parsed = parse_tool_call(out);
    EXPECT_TRUE(parsed.has_call);
    EXPECT_EQ(parsed.tool_name, "get_weather");
    EXPECT_EQ(parsed.arguments_json, "{\"city\":\"SF\"}");
    EXPECT_EQ(parsed.format, ToolCallFormat::kDefault);
    EXPECT_EQ(parsed.clean_text.find("<tool_call>"), std::string::npos);
}

TEST(ToolCalling, DefaultFormatAcceptsNameField) {
    const auto parsed = parse_tool_call(
        "<tool_call>{\"name\":\"lookup\",\"arguments\":{}}</tool_call>");
    EXPECT_TRUE(parsed.has_call);
    EXPECT_EQ(parsed.tool_name, "lookup");
    EXPECT_EQ(parsed.arguments_json, "{}");
}

TEST(ToolCalling, NoTagsReturnsNoCall) {
    const auto parsed = parse_tool_call("Just a regular assistant reply.");
    EXPECT_FALSE(parsed.has_call);
    EXPECT_EQ(parsed.clean_text, "Just a regular assistant reply.");
}

TEST(ToolCalling, LFM2FormatParsesFunctionSyntax) {
    const std::string out =
        "<|tool_call_start|>[get_weather(city=\"SF\", units=\"celsius\")]"
        "<|tool_call_end|>";
    const auto parsed = parse_tool_call(out);
    EXPECT_TRUE(parsed.has_call);
    EXPECT_EQ(parsed.tool_name, "get_weather");
    EXPECT_EQ(parsed.format, ToolCallFormat::kLFM2);
    EXPECT_NE(parsed.arguments_json.find("\"city\":\"SF\""), std::string::npos);
    EXPECT_NE(parsed.arguments_json.find("\"units\":\"celsius\""),
              std::string::npos);
}

TEST(ToolCalling, AutoDetectPrefersLFM2WhenBothPresent) {
    const std::string out =
        "text <|tool_call_start|>[f(x=1)]<|tool_call_end|> more";
    EXPECT_EQ(detect_tool_call_format(out), ToolCallFormat::kLFM2);
}

TEST(ToolCalling, FormatFromNameIsCaseInsensitive) {
    EXPECT_EQ(tool_call_format_from_name("LFM2"), ToolCallFormat::kLFM2);
    EXPECT_EQ(tool_call_format_from_name("lfm2"), ToolCallFormat::kLFM2);
    EXPECT_EQ(tool_call_format_from_name("default"), ToolCallFormat::kDefault);
    EXPECT_EQ(tool_call_format_from_name("bogus"),   ToolCallFormat::kDefault);
}

}  // namespace
