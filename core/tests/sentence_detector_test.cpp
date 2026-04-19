// SPDX-License-Identifier: Apache-2.0
#include "../voice_pipeline/sentence_detector.h"
#include <gtest/gtest.h>

#include <string>
#include <vector>

using ra::core::SentenceDetector;

TEST(SentenceDetector, EmitsOnPeriodAfterTwoWords) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Hello ");
    det.feed("world");
    det.feed(". ");

    ASSERT_EQ(out.size(), 1u);
    EXPECT_NE(out[0].find("Hello world"), std::string::npos);
}

TEST(SentenceDetector, HoldsUntilSecondWord) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Hi.");
    EXPECT_TRUE(out.empty());
    det.feed(" World.");
    EXPECT_EQ(out.size(), 1u);
}

TEST(SentenceDetector, ResetClearsBufferAndCounters) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Hello world");
    det.reset();
    det.feed(".");
    EXPECT_TRUE(out.empty());
}

TEST(SentenceDetector, FlushEmitsBufferedTail) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Final thoughts");
    det.flush();
    ASSERT_EQ(out.size(), 1u);
    EXPECT_EQ(out[0], "Final thoughts");
}
