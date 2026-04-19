// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Back-pressure and multi-producer / multi-consumer stress for StreamEdge<T>.
// The block policy must apply back-pressure to the producer (slow consumer
// never forces a drop), cancellation must release all waiters, and the
// FIFO invariant must hold under contention.
//
// This suite is deliberately heavier than stream_edge_test.cpp — every
// test here spawns ≥2 threads. Green under ASan/UBSan and TSan.

#include "../graph/stream_edge.h"
#include "../graph/cancel_token.h"

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <thread>
#include <utility>
#include <vector>

using ra::core::CancelToken;
using ra::core::PopResult;
using ra::core::PushResult;
using ra::core::StreamEdge;

TEST(StreamEdgeStress, ProducerConsumerFifoUnderContention) {
    constexpr int kItems = 10'000;
    StreamEdge<int> edge(64);

    std::thread producer([&] {
        for (int i = 0; i < kItems; ++i) {
            EXPECT_EQ(edge.push(i), PushResult::kOk);
        }
        edge.close();
    });

    std::vector<int> received;
    received.reserve(kItems);
    std::thread consumer([&] {
        while (true) {
            auto v = edge.pop();
            if (!v) break;
            received.push_back(*v);
        }
    });

    producer.join();
    consumer.join();

    ASSERT_EQ(received.size(), static_cast<std::size_t>(kItems));
    for (int i = 0; i < kItems; ++i) {
        EXPECT_EQ(received[i], i);
    }
}

TEST(StreamEdgeStress, BackPressureAppliesToProducer) {
    // Small capacity, slow consumer — producer must block instead of
    // dropping frames. Track blocking by counting producer "stalls".
    constexpr int kItems    = 200;
    constexpr int kCapacity = 4;
    StreamEdge<int> edge(kCapacity);

    std::atomic<int> produced{0};
    std::thread producer([&] {
        for (int i = 0; i < kItems; ++i) {
            EXPECT_EQ(edge.push(i), PushResult::kOk);
            produced.fetch_add(1, std::memory_order_relaxed);
        }
        edge.close();
    });

    // Consumer pops deliberately slower than producer; at steady state the
    // queue size should hover near capacity, proving back-pressure.
    std::vector<int> received;
    received.reserve(kItems);
    std::thread consumer([&] {
        int observed_at_cap = 0;
        while (true) {
            // Small sleep makes consumption deliberately slower than the
            // producer, forcing push() to block.
            std::this_thread::sleep_for(std::chrono::microseconds(50));
            if (edge.size() >= static_cast<std::size_t>(kCapacity - 1)) {
                ++observed_at_cap;
            }
            auto v = edge.pop();
            if (!v) break;
            received.push_back(*v);
        }
        // At least *some* samples should have observed near-capacity; a
        // naive drop-policy or infinite-buffer bug would keep size low.
        EXPECT_GT(observed_at_cap, 0);
    });

    producer.join();
    consumer.join();
    EXPECT_EQ(produced.load(), kItems);
    ASSERT_EQ(received.size(), static_cast<std::size_t>(kItems));
}

TEST(StreamEdgeStress, MultipleProducersPreserveEachProducersFifo) {
    constexpr int kProducers      = 4;
    constexpr int kItemsPerThread = 2'000;
    StreamEdge<std::pair<int, int>> edge(32);

    std::vector<std::thread> producers;
    producers.reserve(kProducers);
    for (int p = 0; p < kProducers; ++p) {
        producers.emplace_back([&, p] {
            for (int i = 0; i < kItemsPerThread; ++i) {
                EXPECT_EQ(edge.push({p, i}), PushResult::kOk);
            }
        });
    }

    constexpr std::size_t kTotalItems =
        static_cast<std::size_t>(kProducers) *
        static_cast<std::size_t>(kItemsPerThread);
    std::vector<std::pair<int, int>> received;
    received.reserve(kTotalItems);
    std::thread consumer([&] {
        while (received.size() < kTotalItems) {
            auto v = edge.pop();
            if (!v) break;
            received.push_back(*v);
        }
    });

    for (auto& t : producers) t.join();
    edge.close();
    consumer.join();

    // For each producer, the sub-sequence of items they pushed must appear
    // in the received list in the same order they were produced.
    std::vector<int> last_seen(kProducers, -1);
    for (auto& [pid, seq] : received) {
        EXPECT_GT(seq, last_seen[pid]) << "producer " << pid
                                        << " out of order";
        last_seen[pid] = seq;
    }
    for (int p = 0; p < kProducers; ++p) {
        EXPECT_EQ(last_seen[p], kItemsPerThread - 1);
    }
}

TEST(StreamEdgeStress, CancelTokenUnblocksAllWaiters) {
    constexpr int kWaiters = 8;
    auto tok = CancelToken::create();
    StreamEdge<int> edge(4, tok);

    std::atomic<int> cancelled_count{0};
    std::vector<std::thread> waiters;
    waiters.reserve(kWaiters);
    for (int i = 0; i < kWaiters; ++i) {
        waiters.emplace_back([&] {
            PopResult r{};
            auto v = edge.pop(&r);
            EXPECT_FALSE(v.has_value());
            if (r == PopResult::kCancelled) {
                cancelled_count.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    tok->cancel();

    for (auto& t : waiters) t.join();
    EXPECT_EQ(cancelled_count.load(), kWaiters);
}
