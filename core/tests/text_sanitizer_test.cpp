// SPDX-License-Identifier: Apache-2.0
#include "../voice_pipeline/text_sanitizer.h"
#include <gtest/gtest.h>

using ra::core::TextSanitizer;

TEST(TextSanitizer, StripsBoldMarkdown) {
    TextSanitizer san;
    EXPECT_EQ(san.sanitize("Hello **world**"), "Hello world");
}

TEST(TextSanitizer, StripsThinkTags) {
    TextSanitizer san;
    EXPECT_EQ(san.sanitize("<think>debating</think>hello"), "hello");
}

TEST(TextSanitizer, ExpandsAbbreviations) {
    TextSanitizer san;
    EXPECT_EQ(san.sanitize("Mr. Smith"), "Mister Smith");
    EXPECT_EQ(san.sanitize("vs. them"), "versus them");
}

TEST(TextSanitizer, NormalizesWhitespace) {
    TextSanitizer san;
    EXPECT_EQ(san.sanitize("a   b\t\tc"), "a b c");
}
