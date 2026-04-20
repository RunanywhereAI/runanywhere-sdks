// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ring_buffer.h"

#include <gtest/gtest.h>

#include <thread>
#include <vector>

using ra::core::RingBuffer;

TEST(RingBuffer, CapacityRoundedUpToPowerOfTwo) {
    RingBuffer<int> rb(3);
    EXPECT_EQ(rb.capacity(), 4u);
    EXPECT_TRUE(rb.empty());
    EXPECT_FALSE(rb.full());
}

TEST(RingBuffer, PushPopFifoOrder) {
    RingBuffer<int> rb(4);
    EXPECT_TRUE(rb.push(1));
    EXPECT_TRUE(rb.push(2));
    EXPECT_TRUE(rb.push(3));

    int v = 0;
    EXPECT_TRUE(rb.pop(v));  EXPECT_EQ(v, 1);
    EXPECT_TRUE(rb.pop(v));  EXPECT_EQ(v, 2);
    EXPECT_TRUE(rb.pop(v));  EXPECT_EQ(v, 3);
    EXPECT_FALSE(rb.pop(v));
}

TEST(RingBuffer, PushFullReturnsFalse) {
    RingBuffer<int> rb(2);
    EXPECT_TRUE(rb.push(1));
    EXPECT_TRUE(rb.push(2));
    EXPECT_FALSE(rb.push(3));
    EXPECT_TRUE(rb.full());
}

TEST(RingBuffer, BulkPushPop) {
    RingBuffer<float> rb(16);
    const float src[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    EXPECT_EQ(rb.push_n(src, 8), 8u);
    float dst[8] = {};
    EXPECT_EQ(rb.pop_n(dst, 8), 8u);
    for (int i = 0; i < 8; ++i) EXPECT_EQ(dst[i], static_cast<float>(i));
}

TEST(RingBuffer, DrainEmptiesImmediately) {
    RingBuffer<int> rb(8);
    for (int i = 0; i < 5; ++i) rb.push(i);
    EXPECT_EQ(rb.size(), 5u);
    rb.drain();
    EXPECT_TRUE(rb.empty());
}

TEST(RingBuffer, SingleProducerSingleConsumerSmoke) {
    RingBuffer<int> rb(1024);
    constexpr int kIters = 10000;

    std::thread producer([&] {
        for (int i = 0; i < kIters; ++i) {
            while (!rb.push(i)) std::this_thread::yield();
        }
    });

    std::vector<int> got;
    got.reserve(kIters);
    int received = 0;
    while (received < kIters) {
        int v = 0;
        if (rb.pop(v)) {
            got.push_back(v);
            ++received;
        } else {
            std::this_thread::yield();
        }
    }
    producer.join();

    ASSERT_EQ(got.size(), static_cast<size_t>(kIters));
    for (int i = 0; i < kIters; ++i) EXPECT_EQ(got[i], i);
}
