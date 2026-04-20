// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "structured_output.h"

#include <gtest/gtest.h>

namespace {

using ra::core::util::extract_json;

TEST(StructuredOutput, ExtractsFirstObject) {
    const auto r = extract_json("Reply: {\"x\":1, \"y\":{\"z\":2}} trailing");
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(*r, "{\"x\":1, \"y\":{\"z\":2}}");
}

TEST(StructuredOutput, ExtractsArray) {
    const auto r = extract_json("[1,2,3] done");
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(*r, "[1,2,3]");
}

TEST(StructuredOutput, IgnoresBracesInsideStrings) {
    const auto r = extract_json(
        "pre {\"note\":\"value with } brace\",\"ok\":true} post");
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(*r, "{\"note\":\"value with } brace\",\"ok\":true}");
}

TEST(StructuredOutput, ReturnsNullOptWhenUnbalanced) {
    EXPECT_FALSE(extract_json("{unterminated").has_value());
    EXPECT_FALSE(extract_json("no json here").has_value());
}

TEST(StructuredOutput, HandlesEscapedQuotes) {
    const auto r = extract_json("{\"s\":\"a \\\"quoted\\\" word\"}");
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(*r, "{\"s\":\"a \\\"quoted\\\" word\"}");
}

}  // namespace
