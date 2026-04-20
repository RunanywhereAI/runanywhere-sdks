// SPDX-License-Identifier: Apache-2.0
#include "stream_edge.h"
#include "cancel_token.h"
#include <gtest/gtest.h>

#include <thread>
#include <vector>

using ra::core::CancelToken;
using ra::core::EdgePolicy;
using ra::core::PopResult;
using ra::core::PushResult;
using ra::core::StreamEdge;

TEST(StreamEdge, PushPopFifoOrder) {
    StreamEdge<int> edge(4);
    EXPECT_EQ(edge.try_push(1), PushResult::kOk);
    EXPECT_EQ(edge.try_push(2), PushResult::kOk);
    auto v = edge.try_pop();
    ASSERT_TRUE(v.has_value());
    EXPECT_EQ(*v, 1);
    v = edge.try_pop();
    ASSERT_TRUE(v.has_value());
    EXPECT_EQ(*v, 2);
}

TEST(StreamEdge, TryPushFullReturnsFull) {
    StreamEdge<int> edge(1);
    EXPECT_EQ(edge.try_push(1), PushResult::kOk);
    EXPECT_EQ(edge.try_push(2), PushResult::kFull);
}

TEST(StreamEdge, CloseReleasesPopWaiter) {
    StreamEdge<int> edge(4);
    std::thread consumer([&] {
        PopResult r{};
        auto v = edge.pop(&r);
        EXPECT_FALSE(v.has_value());
        EXPECT_EQ(r, PopResult::kClosed);
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    edge.close();
    consumer.join();
}

TEST(StreamEdge, CancelTokenReleasesPopWaiter) {
    auto tok = CancelToken::create();
    StreamEdge<int> edge(4, tok);
    std::thread consumer([&] {
        PopResult r{};
        auto v = edge.pop(&r);
        EXPECT_FALSE(v.has_value());
        EXPECT_EQ(r, PopResult::kCancelled);
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    tok->cancel();
    consumer.join();
}

TEST(StreamEdge, ClearLockedDropsQueuedItems) {
    StreamEdge<std::string> edge(4);
    edge.try_push("a");
    edge.try_push("b");
    EXPECT_EQ(edge.size(), 2u);
    edge.clear_locked();
    EXPECT_EQ(edge.size(), 0u);
}

TEST(StreamEdge, DropOldestPolicyReplacesHead) {
    StreamEdge<int> edge(2, nullptr, EdgePolicy::kDropOldest);
    EXPECT_EQ(edge.push(1), PushResult::kOk);
    EXPECT_EQ(edge.push(2), PushResult::kOk);
    EXPECT_EQ(edge.push(3), PushResult::kOk);  // drops 1
    auto v = edge.try_pop();
    ASSERT_TRUE(v.has_value());
    EXPECT_EQ(*v, 2);
}
