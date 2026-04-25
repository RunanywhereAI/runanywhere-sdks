// SPDX-License-Identifier: Apache-2.0
//
// test_pipeline_node.cpp — v3.1 Phase 9 unit tests (GAP 05 Phase 2).
//
// Covers PipelineNode / PrimitiveNode / SplitNode / MergeNode from
// include/rac/graph/pipeline_node.hpp.
//
// Cases
// -----
//   linear_pipeline           — producer → primitive → consumer, 3-node DAG.
//   primitive_with_pool       — pool-acquired output buffers recycle correctly.
//   split_fanout              — 1 input fans out to N consumers.
//   merge_fanin               — N producers merge into one consumer.
//   cancel_mid_stream         — cancel token aborts an in-flight pipeline.
//   idempotent_start_stop     — repeated start()/stop()/join() are safe.
//
// Matches the lightweight CHECK/TEST harness from test_graph_primitives.cpp.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/memory_pool.hpp"
#include "rac/graph/pipeline_node.hpp"
#include "rac/graph/stream_edge.hpp"

using rac::graph::CancelToken;
using rac::graph::MemoryPool;
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
// 3-node linear pipeline: producer thread → PrimitiveNode (doubler) → consumer
// thread. This is the canonical shape of every DAG that real consumers (STT,
// LLM, RAG) will build — a chain of streaming primitives terminated by an
// application sink.
// ---------------------------------------------------------------------------

TEST(linear_pipeline) {
    auto doubler = make_primitive_node<int, int>(
        "doubler",
        [](int in, StreamEdge<int>& out) { out.push(in * 2); });
    doubler->start(nullptr);

    const int N = 100;
    std::thread producer([&] {
        auto input = doubler->input();
        for (int i = 0; i < N; ++i) input->push(i);
        input->close();
    });

    std::vector<int> received;
    std::thread consumer([&] {
        auto output = doubler->output();
        while (auto x = output->pop()) {
            received.push_back(*x);
        }
    });

    producer.join();
    doubler->join();
    consumer.join();

    CHECK(static_cast<int>(received.size()) == N);
    for (int i = 0; i < N; ++i) CHECK(received[i] == i * 2);
}

// ---------------------------------------------------------------------------
// PrimitiveNode capture a MemoryPool in the lambda and emits pool-backed
// buffers. Verifies the pool + node compose correctly and that every buffer
// is returned to the pool once the consumer drops its handle.
// ---------------------------------------------------------------------------

struct Frame {
    int seq{0};
    std::vector<uint8_t> pcm;
    Frame() : pcm(32, 0) {}
};

TEST(primitive_with_pool) {
    auto pool = MemoryPool<Frame>::create(/*capacity=*/4);

    auto node = make_primitive_node<int, std::shared_ptr<Frame>>(
        "pool_emitter",
        [pool](int seq, StreamEdge<std::shared_ptr<Frame>>& out) {
            auto handle = pool->acquire();
            if (!handle) return;
            handle->seq = seq;
            out.push(std::move(handle));
        });
    node->start(nullptr);

    const int N = 20;
    std::thread producer([&] {
        auto input = node->input();
        for (int i = 0; i < N; ++i) input->push(i);
        input->close();
    });

    int last_seq = -1;
    int received = 0;
    std::thread consumer([&] {
        auto out = node->output();
        while (auto h = out->pop()) {
            CHECK((*h)->seq == last_seq + 1);
            last_seq = (*h)->seq;
            ++received;
            // Handle dropped → slot returned to the pool, bounding in-flight
            // buffers to `capacity`.
        }
    });

    producer.join();
    node->join();
    consumer.join();

    CHECK(received == N);
    CHECK(pool->available() == pool->capacity());
}

// ---------------------------------------------------------------------------
// SplitNode: every pushed item is copied to each of N output edges.
// ---------------------------------------------------------------------------

TEST(split_fanout) {
    const size_t N_OUTS = 3;
    SplitNode<int> split("splitter", N_OUTS, /*capacity=*/8);
    split.start(nullptr);

    const int N = 32;
    std::thread producer([&] {
        auto in = split.input();
        for (int i = 0; i < N; ++i) in->push(i);
        in->close();
    });

    std::vector<std::vector<int>> per_output(N_OUTS);
    std::vector<std::thread> consumers;
    for (size_t k = 0; k < N_OUTS; ++k) {
        consumers.emplace_back([&, k] {
            auto edge = split.output(k);
            while (auto x = edge->pop()) {
                per_output[k].push_back(*x);
            }
        });
    }

    producer.join();
    split.join();
    for (auto& c : consumers) c.join();

    for (size_t k = 0; k < N_OUTS; ++k) {
        CHECK(static_cast<int>(per_output[k].size()) == N);
        for (int i = 0; i < N; ++i) CHECK(per_output[k][i] == i);
    }
}

// ---------------------------------------------------------------------------
// MergeNode: N producers drain into one output; output closes exactly once,
// after the last producer-drain worker exits.
// ---------------------------------------------------------------------------

TEST(merge_fanin) {
    const size_t N_INS = 3;
    MergeNode<int> merge("merger", N_INS, /*capacity=*/8);
    merge.start(nullptr);

    const int per_producer = 50;
    std::vector<std::thread> producers;
    for (size_t k = 0; k < N_INS; ++k) {
        producers.emplace_back([&, k] {
            auto in = merge.input(k);
            for (int i = 0; i < per_producer; ++i) {
                in->push(static_cast<int>(k) * 1000 + i);
            }
            in->close();
        });
    }

    std::vector<int> received;
    std::thread consumer([&] {
        auto out = merge.output();
        while (auto x = out->pop()) {
            received.push_back(*x);
        }
    });

    for (auto& p : producers) p.join();
    merge.join();
    consumer.join();

    CHECK(static_cast<int>(received.size())
          == static_cast<int>(N_INS) * per_producer);
    // Count per source stream to confirm no drops/dupes.
    std::vector<int> count(N_INS, 0);
    for (int v : received) {
        const int src = v / 1000;
        CHECK(src >= 0 && src < static_cast<int>(N_INS));
        count[src]++;
    }
    for (size_t k = 0; k < N_INS; ++k) CHECK(count[k] == per_producer);
}

// ---------------------------------------------------------------------------
// Cancel mid-stream: producer is slow, consumer never drains, cancel wakes
// every blocked push/pop within ~50 ms.
// ---------------------------------------------------------------------------

TEST(cancel_mid_stream) {
    // Share the node's output-edge cancel with the processing lambda so the
    // (bounded) `out.push` honours cancel and doesn't deadlock on its own
    // backpressure while the cancel flag is being raised.
    std::shared_ptr<CancelToken> op_cancel = std::make_shared<CancelToken>();
    auto node = make_primitive_node<int, int>(
        "slow_doubler",
        [op_cancel](int in, StreamEdge<int>& out) {
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            out.push(in * 2, op_cancel.get());
        },
        /*input_capacity=*/2, /*output_capacity=*/2);

    auto parent_cancel = std::make_shared<CancelToken>();
    node->start(parent_cancel);

    std::atomic<int> pushed{0};
    std::thread producer([&] {
        auto in = node->input();
        for (int i = 0; i < 10000; ++i) {
            if (!in->push(i, parent_cancel.get())) break;
            pushed.fetch_add(1);
        }
    });

    // Sink that discards output so the slow node can progress until cancel.
    std::thread drain([&] {
        auto out = node->output();
        while (auto x = out->pop()) { (void)x; }
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(40));
    parent_cancel->cancel();
    op_cancel->cancel();
    node->stop();

    producer.join();
    node->join();
    drain.join();

    // Producer saw the cancel and stopped somewhere before the 10k-th push.
    CHECK(pushed.load() < 10000);
    CHECK(node->cancel_token() != nullptr);
    CHECK(node->cancel_token()->is_cancelled());
}

// ---------------------------------------------------------------------------
// start() / stop() / join() are idempotent — GraphScheduler relies on this to
// be resilient to shutdown races.
// ---------------------------------------------------------------------------

TEST(idempotent_start_stop) {
    auto node = make_primitive_node<int, int>(
        "identity",
        [](int in, StreamEdge<int>& out) { out.push(in); });

    node->start(nullptr);
    node->start(nullptr);  // second call is a no-op — must not spawn a 2nd thread
    node->stop();
    node->stop();          // repeated stop is a no-op
    node->join();
    node->join();          // join after join is fine
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main() {
    run_test_linear_pipeline();
    run_test_primitive_with_pool();
    run_test_split_fanout();
    run_test_merge_fanin();
    run_test_cancel_mid_stream();
    run_test_idempotent_start_stop();

    std::fprintf(stderr, "\n%d test(s) passed, %d test(s) failed\n",
                 g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
