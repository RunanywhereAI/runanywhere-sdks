// SPDX-License-Identifier: Apache-2.0
//
// test_graph_primitives.cpp — v3.1 Phase 9 unit tests (GAP 05).
//
// Covers CancelToken + RingBuffer + StreamEdge primitives under
// include/rac/graph/. Test flavor matches the existing minimal
// test harness used by test_proto_event_dispatch — no GTest dep,
// just `assert` + a simple name/pass counter.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/ring_buffer.hpp"
#include "rac/graph/stream_edge.hpp"

using rac::graph::CancelToken;
using rac::graph::OverflowPolicy;
using rac::graph::RingBuffer;
using rac::graph::StreamEdge;

static int g_failed = 0;
static int g_passed = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                        \
            return;                                                            \
        }                                                                      \
    } while (0)

#define TEST(name) \
    static void test_##name();                                                 \
    static void run_test_##name() {                                            \
        std::fprintf(stderr, "[RUN ] %s\n", #name);                            \
        int before_failed = g_failed;                                          \
        test_##name();                                                         \
        if (g_failed == before_failed) {                                       \
            std::fprintf(stderr, "[  OK] %s\n", #name);                        \
            g_passed++;                                                        \
        }                                                                      \
    }                                                                          \
    static void test_##name()

// ---------------------------------------------------------------------------
// CancelToken
// ---------------------------------------------------------------------------

TEST(cancel_token_basic) {
    auto t = std::make_shared<CancelToken>();
    CHECK(!t->is_cancelled());
    t->cancel();
    CHECK(t->is_cancelled());
    t->cancel();  // idempotent
    CHECK(t->is_cancelled());
}

TEST(cancel_token_parent_child) {
    auto parent = std::make_shared<CancelToken>();
    auto child  = parent->create_child();
    CHECK(!parent->is_cancelled());
    CHECK(!child->is_cancelled());
    parent->cancel();
    CHECK(parent->is_cancelled());
    CHECK(child->is_cancelled());
}

TEST(cancel_token_child_born_cancelled) {
    auto parent = std::make_shared<CancelToken>();
    parent->cancel();
    auto child = parent->create_child();
    CHECK(child->is_cancelled());
}

TEST(cancel_token_cascade_to_grandchild) {
    auto parent     = std::make_shared<CancelToken>();
    auto child      = parent->create_child();
    auto grandchild = child->create_child();
    parent->cancel();
    CHECK(grandchild->is_cancelled());
}

TEST(cancel_token_multithreaded_cancel) {
    auto t = std::make_shared<CancelToken>();
    std::atomic<int> observed{0};
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) {
        threads.emplace_back([&, i] {
            // Half cancel, half observe.
            if (i % 2 == 0) t->cancel();
            for (int j = 0; j < 1000; ++j) {
                if (t->is_cancelled()) observed.fetch_add(1);
            }
        });
    }
    for (auto& th : threads) th.join();
    CHECK(t->is_cancelled());
}

// ---------------------------------------------------------------------------
// RingBuffer
// ---------------------------------------------------------------------------

TEST(ring_buffer_push_pop) {
    RingBuffer<int> rb(4);
    CHECK(rb.empty());
    CHECK(rb.push(1));
    CHECK(rb.push(2));
    CHECK(rb.push(3));  // capacity 4 means 3 in flight max (one slot
                        // reserved for the full/empty distinction).
    CHECK(rb.full());
    CHECK(!rb.push(99));
    int x;
    CHECK(rb.pop(x) && x == 1);
    CHECK(rb.pop(x) && x == 2);
    CHECK(rb.pop(x) && x == 3);
    CHECK(!rb.pop(x));
    CHECK(rb.empty());
}

TEST(ring_buffer_wrap_around) {
    RingBuffer<int> rb(4);
    for (int i = 0; i < 100; ++i) {
        CHECK(rb.push(i));
        int x;
        CHECK(rb.pop(x));
        CHECK(x == i);
    }
}

TEST(ring_buffer_spsc_concurrent) {
    RingBuffer<int> rb(16);
    const int N = 10000;
    std::thread producer([&] {
        for (int i = 0; i < N; ++i) {
            while (!rb.push(i)) {
                std::this_thread::yield();
            }
        }
    });
    std::thread consumer([&] {
        int expected = 0;
        while (expected < N) {
            int x;
            if (rb.pop(x)) {
                if (x != expected) {
                    std::fprintf(stderr, "out-of-order: got %d expected %d\n",
                                 x, expected);
                    std::abort();
                }
                expected++;
            } else {
                std::this_thread::yield();
            }
        }
    });
    producer.join();
    consumer.join();
    CHECK(rb.empty());
}

// ---------------------------------------------------------------------------
// StreamEdge
// ---------------------------------------------------------------------------

TEST(stream_edge_drop_newest) {
    StreamEdge<int> edge(2, OverflowPolicy::DropNewest);
    CHECK(edge.push(1));
    CHECK(edge.push(2));
    CHECK(!edge.push(3));  // full; dropped
    auto a = edge.pop();
    CHECK(a.has_value() && *a == 1);
    auto b = edge.pop();
    CHECK(b.has_value() && *b == 2);
}

TEST(stream_edge_drop_oldest) {
    StreamEdge<int> edge(2, OverflowPolicy::DropOldest);
    CHECK(edge.push(1));
    CHECK(edge.push(2));
    CHECK(edge.push(3));  // evicts 1
    CHECK(edge.push(4));  // evicts 2
    auto a = edge.pop();
    CHECK(a.has_value() && *a == 3);
    auto b = edge.pop();
    CHECK(b.has_value() && *b == 4);
}

TEST(stream_edge_block_producer_cancel) {
    StreamEdge<int> edge(1, OverflowPolicy::BlockProducer);
    auto cancel = std::make_shared<CancelToken>();
    CHECK(edge.push(42, cancel.get()));

    std::atomic<bool> push_returned{false};
    std::atomic<bool> push_result{true};
    std::thread t([&] {
        // This should block (capacity=1, already full) until cancel fires.
        bool r = edge.push(99, cancel.get());
        push_result.store(r);
        push_returned.store(true);
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    CHECK(!push_returned.load());

    cancel->cancel();
    t.join();
    CHECK(push_returned.load());
    CHECK(!push_result.load());  // cancel caused push to return false
}

TEST(stream_edge_close_unblocks_consumer) {
    StreamEdge<int> edge(4);
    std::atomic<bool> popped{false};
    std::thread t([&] {
        auto r = edge.pop();
        popped.store(true);
        // Should be nullopt because we closed without pushing.
        if (r.has_value()) std::abort();
    });
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    edge.close();
    t.join();
    CHECK(popped.load());
}

TEST(stream_edge_producer_consumer_parallel) {
    StreamEdge<int> edge(4);
    const int N = 1000;
    std::thread producer([&] {
        for (int i = 0; i < N; ++i) edge.push(i);
        edge.close();
    });
    std::vector<int> received;
    std::thread consumer([&] {
        while (auto x = edge.pop()) {
            received.push_back(*x);
        }
    });
    producer.join();
    consumer.join();
    CHECK(static_cast<int>(received.size()) == N);
    for (int i = 0; i < N; ++i) CHECK(received[i] == i);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main() {
    run_test_cancel_token_basic();
    run_test_cancel_token_parent_child();
    run_test_cancel_token_child_born_cancelled();
    run_test_cancel_token_cascade_to_grandchild();
    run_test_cancel_token_multithreaded_cancel();

    run_test_ring_buffer_push_pop();
    run_test_ring_buffer_wrap_around();
    run_test_ring_buffer_spsc_concurrent();

    run_test_stream_edge_drop_newest();
    run_test_stream_edge_drop_oldest();
    run_test_stream_edge_block_producer_cancel();
    run_test_stream_edge_close_unblocks_consumer();
    run_test_stream_edge_producer_consumer_parallel();

    std::fprintf(stderr, "\n%d test(s) passed, %d test(s) failed\n",
                 g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
