// SPDX-License-Identifier: Apache-2.0
//
// test_graph_scheduler.cpp — v3.1 Phase 9 unit tests (GAP 05 Phase 2).
//
// Covers GraphScheduler from include/rac/graph/graph_scheduler.hpp. Uses the
// concrete node types in pipeline_node.hpp (PrimitiveNode / SplitNode /
// MergeNode) to assemble multi-node DAGs.
//
// Cases
// -----
//   streaming_correctness  — producer → n1 → n2 → consumer; output matches
//                            expected transform and arrives in order.
//   backpressure           — bounded edge forces the producer to wait on a
//                            slow consumer; in-flight count never exceeds
//                            capacity, no drops.
//   cancel_all_mid_stream  — cancel fires mid-run; every node stops within a
//                            bounded time, no hang.
//   split_merge_topology   — fan-out / fan-in DAG drains cleanly via scheduler.
//   empty_scheduler        — start/stop/wait on an empty scheduler is a no-op.
//
// Same CHECK/TEST harness as test_graph_primitives.cpp.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/graph/pipeline_node.hpp"
#include "rac/graph/stream_edge.hpp"

using rac::graph::CancelToken;
using rac::graph::GraphScheduler;
using rac::graph::make_primitive_node;
using rac::graph::MergeNode;
using rac::graph::OverflowPolicy;
using rac::graph::PipelineNode;
using rac::graph::PrimitiveNode;
using rac::graph::SplitNode;
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

#define TEST(name)                                                             \
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
// Linear graph drains to completion — canonical streaming use case.
// Pipeline: push i → (doubler) → (plus_one) → pop.
// Expected: (i*2) + 1 for every input.
// ---------------------------------------------------------------------------

TEST(streaming_correctness) {
    auto doubler = make_primitive_node<int, int>(
        "doubler",
        [](int x, StreamEdge<int>& out) { out.push(x * 2); },
        /*input_capacity=*/8, /*output_capacity=*/8);

    auto plus_one = make_primitive_node<int, int>(
        "plus_one",
        [](int x, StreamEdge<int>& out) { out.push(x + 1); },
        /*input_capacity=*/8, /*output_capacity=*/8);

    GraphScheduler scheduler(/*thread_pool_size=*/2);
    scheduler.add_node(doubler);
    scheduler.add_node(plus_one);
    scheduler.connect(*doubler, *plus_one);
    scheduler.start();

    const int N = 256;
    std::thread producer([&] {
        auto in = doubler->input();
        for (int i = 0; i < N; ++i) in->push(i);
        in->close();
    });

    std::vector<int> received;
    std::thread consumer([&] {
        auto out = plus_one->output();
        while (auto x = out->pop()) received.push_back(*x);
    });

    producer.join();
    scheduler.wait();
    consumer.join();

    CHECK(static_cast<int>(received.size()) == N);
    for (int i = 0; i < N; ++i) CHECK(received[i] == i * 2 + 1);
}

// ---------------------------------------------------------------------------
// Backpressure: the producer's output edge has capacity 2; the downstream
// consumer sleeps so the producer must block on push. We sample the queue
// depth and assert it never exceeds capacity — proving BlockProducer actually
// stalls instead of dropping or growing unbounded.
// ---------------------------------------------------------------------------

TEST(backpressure) {
    const size_t kCap = 2;
    auto fast = make_primitive_node<int, int>(
        "fast",
        [](int x, StreamEdge<int>& out) { out.push(x); },
        /*input_capacity=*/kCap, /*output_capacity=*/kCap,
        OverflowPolicy::BlockProducer);

    auto slow = make_primitive_node<int, int>(
        "slow",
        [](int x, StreamEdge<int>& out) {
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            out.push(x);
        },
        /*input_capacity=*/kCap, /*output_capacity=*/kCap,
        OverflowPolicy::BlockProducer);

    GraphScheduler scheduler;
    scheduler.add_node(fast);
    scheduler.add_node(slow);
    scheduler.connect(*fast, *slow);
    scheduler.start();

    const int N = 50;

    // Sampler thread peeks the shared edge between fast->slow every ms and
    // records its maximum observed depth. The shared edge IS the "slow"
    // node's input after connect() rewired it.
    std::atomic<bool> sampler_done{false};
    std::atomic<size_t> max_depth{0};
    std::thread sampler([&] {
        auto edge = slow->input();
        while (!sampler_done.load()) {
            size_t d = edge->approximate_size();
            size_t prev = max_depth.load();
            while (d > prev && !max_depth.compare_exchange_weak(prev, d)) {}
            std::this_thread::sleep_for(std::chrono::microseconds(500));
        }
    });

    std::thread producer([&] {
        auto in = fast->input();
        for (int i = 0; i < N; ++i) in->push(i);
        in->close();
    });

    std::vector<int> received;
    std::thread consumer([&] {
        auto out = slow->output();
        while (auto x = out->pop()) received.push_back(*x);
    });

    producer.join();
    scheduler.wait();
    sampler_done.store(true);
    sampler.join();
    consumer.join();

    // No drops.
    CHECK(static_cast<int>(received.size()) == N);
    for (int i = 0; i < N; ++i) CHECK(received[i] == i);
    // Bounded in-flight — BlockProducer kept the edge at or under capacity.
    CHECK(max_depth.load() <= kCap);
}

// ---------------------------------------------------------------------------
// Cancel mid-stream: producer keeps feeding; downstream node sleeps long
// enough that cancel fires before the graph drains. Scheduler shutdown must
// complete within a bounded window regardless of backlog.
// ---------------------------------------------------------------------------

TEST(cancel_all_mid_stream) {
    auto slow = make_primitive_node<int, int>(
        "slow",
        [](int x, StreamEdge<int>& out) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            out.push(x);
        },
        /*input_capacity=*/4, /*output_capacity=*/4);

    GraphScheduler scheduler;
    scheduler.add_node(slow);
    scheduler.start();

    auto root = scheduler.root_cancel_token();
    std::atomic<int> pushed{0};
    std::thread producer([&] {
        auto in = slow->input();
        for (int i = 0; i < 10000; ++i) {
            if (!in->push(i, root.get())) break;
            pushed.fetch_add(1);
        }
    });

    // Drain whatever comes out so the slow node doesn't deadlock on its own
    // backpressure while we try to measure cancel latency.
    std::atomic<bool> consumer_done{false};
    std::thread consumer([&] {
        auto out = slow->output();
        while (auto x = out->pop()) { (void)x; }
        consumer_done.store(true);
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(60));

    const auto t0 = std::chrono::steady_clock::now();
    scheduler.cancel_all();
    scheduler.wait();
    const auto elapsed = std::chrono::steady_clock::now() - t0;

    producer.join();
    consumer.join();

    CHECK(root->is_cancelled());
    CHECK(consumer_done.load());
    // Shutdown bounded — each blocked wait polls cancel at 50 ms, so allow 2s.
    CHECK(elapsed < std::chrono::seconds(2));
    CHECK(pushed.load() < 10000);
}

// ---------------------------------------------------------------------------
// Split + merge topology — proves the scheduler's overloaded connect() works
// for the fan-out / fan-in shape that will back RAG query → embed × N →
// rerank in T4.6.
//
//   producer → [identity] → Split → (A, B) → Merge → [sink]
//
// Every input is duplicated into A and B by the split, then both copies hit
// the merge, so the sink sees each input exactly twice.
// ---------------------------------------------------------------------------

TEST(split_merge_topology) {
    auto head = make_primitive_node<int, int>(
        "head", [](int x, StreamEdge<int>& out) { out.push(x); });
    auto tail = make_primitive_node<int, int>(
        "tail", [](int x, StreamEdge<int>& out) { out.push(x); });
    auto split = std::make_shared<SplitNode<int>>("split", /*num_outputs=*/2);
    auto merge = std::make_shared<MergeNode<int>>("merge", /*num_inputs=*/2);

    GraphScheduler scheduler;
    scheduler.add_node(head);
    scheduler.add_node(split);
    scheduler.add_node(merge);
    scheduler.add_node(tail);

    scheduler.connect(*head, *split);
    // Hand each split output directly to a merge input — no extra bridge node
    // needed since both edges are typed StreamEdge<int>.
    merge->set_input(0, split->output(0));
    merge->set_input(1, split->output(1));
    scheduler.connect(*merge, *tail);

    scheduler.start();

    const int N = 40;
    std::thread producer([&] {
        auto in = head->input();
        for (int i = 0; i < N; ++i) in->push(i);
        in->close();
    });

    std::vector<int> received;
    std::thread consumer([&] {
        auto out = tail->output();
        while (auto x = out->pop()) received.push_back(*x);
    });

    producer.join();
    scheduler.wait();
    consumer.join();

    CHECK(static_cast<int>(received.size()) == N * 2);
    // Each input value appears exactly twice.
    std::vector<int> counts(N, 0);
    for (int v : received) {
        CHECK(v >= 0 && v < N);
        counts[v]++;
    }
    for (int i = 0; i < N; ++i) CHECK(counts[i] == 2);
}

// ---------------------------------------------------------------------------
// An empty scheduler start/stop/wait is a no-op — don't hang, don't crash.
// ---------------------------------------------------------------------------

TEST(empty_scheduler) {
    GraphScheduler scheduler;
    CHECK(scheduler.node_count() == 0);
    scheduler.start();
    CHECK(scheduler.running());
    scheduler.stop();
    scheduler.wait();
    CHECK(!scheduler.running());
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main() {
    run_test_streaming_correctness();
    run_test_backpressure();
    run_test_cancel_all_mid_stream();
    run_test_split_merge_topology();
    run_test_empty_scheduler();

    std::fprintf(stderr, "\n%d test(s) passed, %d test(s) failed\n",
                 g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
