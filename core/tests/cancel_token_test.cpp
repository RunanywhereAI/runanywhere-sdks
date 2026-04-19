// SPDX-License-Identifier: Apache-2.0
#include "../graph/cancel_token.h"
#include <gtest/gtest.h>

#include <atomic>

using ra::core::CancelToken;

TEST(CancelToken, BasicCancellation) {
    auto tok = CancelToken::create();
    EXPECT_FALSE(tok->is_cancelled());
    tok->cancel();
    EXPECT_TRUE(tok->is_cancelled());
}

TEST(CancelToken, CancelIsIdempotent) {
    auto tok = CancelToken::create();
    tok->cancel();
    tok->cancel();  // must not crash or double-fire callbacks
    EXPECT_TRUE(tok->is_cancelled());
}

TEST(CancelToken, CallbackFiresExactlyOnce) {
    auto tok = CancelToken::create();
    std::atomic<int> count{0};
    tok->on_cancel([&] { ++count; });
    tok->cancel();
    tok->cancel();
    EXPECT_EQ(count.load(), 1);
}

TEST(CancelToken, CallbackFiresSynchronouslyIfAlreadyCancelled) {
    auto tok = CancelToken::create();
    tok->cancel();
    std::atomic<bool> fired{false};
    tok->on_cancel([&] { fired = true; });
    EXPECT_TRUE(fired.load());
}

TEST(CancelToken, ChildCancellationPropagatesFromParent) {
    auto parent = CancelToken::create();
    auto child  = parent->child();
    auto grand  = child->child();

    parent->cancel();
    EXPECT_TRUE(parent->is_cancelled());
    EXPECT_TRUE(child->is_cancelled());
    EXPECT_TRUE(grand->is_cancelled());
}

TEST(CancelToken, ChildAfterParentCancelReturnsCancelled) {
    auto parent = CancelToken::create();
    parent->cancel();
    auto late_child = parent->child();
    EXPECT_TRUE(late_child->is_cancelled());
}
