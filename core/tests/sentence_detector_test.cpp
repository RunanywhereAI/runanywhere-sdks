// SPDX-License-Identifier: Apache-2.0
#include "sentence_detector.h"
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

TEST(SentenceDetector, EmitsOnExclamationAndQuestion) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Hello world! ");
    ASSERT_GE(out.size(), 1u);
    EXPECT_NE(out.back().find("Hello world"), std::string::npos);

    det.feed("Are you here? ");
    ASSERT_GE(out.size(), 2u);
    EXPECT_NE(out.back().find("Are you here"), std::string::npos);
}

TEST(SentenceDetector, ChainOfSentencesEmitsEach) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("Hello world. ");
    det.feed("How are you doing? ");
    det.feed("I am fine. ");
    EXPECT_EQ(out.size(), 3u);
}

TEST(SentenceDetector, CustomMinWordsForEmitHoldsFragment) {
    SentenceDetector::Config cfg;
    cfg.min_words_for_emit = 10;  // Raise high enough that short fragments
                                  // don't fire on their own.
    SentenceDetector det(cfg);
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    // A short sentence (well under 10 words by any counting scheme) must
    // not emit under the high threshold.
    det.feed("Short. ");
    EXPECT_TRUE(out.empty());

    // After flush(), the buffered tail emits regardless of word count.
    det.flush();
    EXPECT_EQ(out.size(), 1u);
}

TEST(SentenceDetector, ForceFlushOnRunOn) {
    SentenceDetector::Config cfg;
    cfg.max_words_before_force_flush = 5;
    SentenceDetector det(cfg);
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    // Feed 8 words with no terminal punctuation. The force-flush threshold
    // is 5, so at least one emit should fire even without a period.
    det.feed("alpha beta gamma delta epsilon zeta eta theta ");
    EXPECT_FALSE(out.empty());
}

TEST(SentenceDetector, ResetClearsWordCounter) {
    SentenceDetector det;
    std::vector<std::string> out;
    det.set_callback([&](std::string s) { out.push_back(std::move(s)); });

    det.feed("First sentence. ");
    ASSERT_EQ(out.size(), 1u);
    det.reset();
    // After reset, word accumulator is zero.
    EXPECT_EQ(det.words_accumulated(), 0);
}
