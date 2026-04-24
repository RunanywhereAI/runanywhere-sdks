// SPDX-License-Identifier: Apache-2.0
//
// test_memory_pool.cpp — v3.1 Phase 9 unit tests (GAP 05 Phase 2).
//
// Covers MemoryPool<T>:
//   * pool_reuse                — release+reacquire returns the recycled slot
//   * try_acquire_empty         — non-blocking acquire on empty pool is nullptr
//   * acquire_timeout           — timed acquire honours the deadline
//   * acquire_cancel            — blocked acquire unblocks on cancel
//   * leak_detection            — outstanding handles outlive the pool safely
//   * concurrent_stress         — N producers acquire/release, no deadlock/loss
//   * custom_factory            — user factory is invoked once per slot
//
// Same minimalist `CHECK` / `TEST` harness as test_graph_primitives.cpp.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "rac/graph/cancel_token.hpp"
#include "rac/graph/memory_pool.hpp"

using rac::graph::CancelToken;
using rac::graph::MemoryPool;

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

namespace {

/// Small POD-ish payload that records construction + destruction so the tests
/// can assert no leaks.
struct Buffer {
    int id{0};
    std::vector<uint8_t> data;

    Buffer() : data(16, 0) {
        alive.fetch_add(1, std::memory_order_relaxed);
    }
    ~Buffer() { alive.fetch_sub(1, std::memory_order_relaxed); }

    Buffer(const Buffer&)            = delete;
    Buffer& operator=(const Buffer&) = delete;

    static std::atomic<int> alive;
};
std::atomic<int> Buffer::alive{0};

}  // namespace

// ---------------------------------------------------------------------------
// Pool reuse
// ---------------------------------------------------------------------------

TEST(pool_reuse) {
    auto pool = MemoryPool<Buffer>::create(2);
    CHECK(pool->available() == 2);

    Buffer* raw_first = nullptr;
    {
        auto h = pool->acquire();
        CHECK(h != nullptr);
        raw_first = h.get();
        CHECK(pool->available() == 1);
        CHECK(pool->in_flight() == 1);
    }
    // Handle dropped → slot returned to pool.
    CHECK(pool->available() == 2);

    auto h2 = pool->acquire();
    CHECK(h2 != nullptr);
    // LIFO recycle — the just-returned buffer is on top of the stack, so the
    // next acquire hands back the SAME instance. Proves the slot was recycled
    // rather than heap-freed.
    CHECK(h2.get() == raw_first);
}

// ---------------------------------------------------------------------------
// try_acquire returns nullptr when empty
// ---------------------------------------------------------------------------

TEST(try_acquire_empty) {
    auto pool = MemoryPool<Buffer>::create(1);
    auto a = pool->acquire();
    CHECK(a != nullptr);
    CHECK(pool->try_acquire() == nullptr);  // exhausted
    a.reset();
    CHECK(pool->try_acquire() != nullptr);  // refilled
}

// ---------------------------------------------------------------------------
// acquire_for respects the deadline
// ---------------------------------------------------------------------------

TEST(acquire_timeout) {
    auto pool = MemoryPool<Buffer>::create(1);
    auto hold = pool->acquire();  // exhaust
    CHECK(hold != nullptr);

    const auto t0 = std::chrono::steady_clock::now();
    auto h = pool->acquire_for(std::chrono::milliseconds(80));
    const auto elapsed = std::chrono::steady_clock::now() - t0;

    CHECK(h == nullptr);
    CHECK(elapsed >= std::chrono::milliseconds(60));  // accept some jitter
    CHECK(elapsed <  std::chrono::milliseconds(500));
}

// ---------------------------------------------------------------------------
// A blocked acquire() returns nullptr when the cancel token fires.
// ---------------------------------------------------------------------------

TEST(acquire_cancel) {
    auto pool   = MemoryPool<Buffer>::create(1);
    auto hold   = pool->acquire();
    auto cancel = std::make_shared<CancelToken>();

    std::atomic<bool> returned{false};
    std::atomic<bool> got_handle{false};
    std::thread waiter([&] {
        auto h = pool->acquire(cancel.get());
        got_handle.store(h != nullptr);
        returned.store(true);
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    CHECK(!returned.load());

    cancel->cancel();
    waiter.join();
    CHECK(returned.load());
    CHECK(!got_handle.load());  // cancel ⇒ nullptr
}

// ---------------------------------------------------------------------------
// Handles outstanding at pool destruction time get plain-deleted; no leak.
// ---------------------------------------------------------------------------

TEST(leak_detection) {
    const int before = Buffer::alive.load();
    std::shared_ptr<Buffer> stray;
    {
        auto pool = MemoryPool<Buffer>::create(4);
        stray = pool->acquire();
        CHECK(Buffer::alive.load() == before + 4);
        // Pool's shared_ptr goes out of scope HERE. The weak_ptr in `stray`'s
        // deleter captures becomes empty; when `stray` is destroyed below it
        // falls back to `delete p` instead of re-queuing into a dangling pool.
    }
    CHECK(Buffer::alive.load() == before + 1);
    stray.reset();
    CHECK(Buffer::alive.load() == before);
}

// ---------------------------------------------------------------------------
// N threads hammer the pool; after every worker exits, the free list is full.
// ---------------------------------------------------------------------------

TEST(concurrent_stress) {
    const size_t capacity   = 8;
    const int    thread_cnt = 8;
    const int    per_thread = 2000;

    auto pool = MemoryPool<Buffer>::create(capacity);

    std::atomic<int> ops{0};
    std::vector<std::thread> threads;
    threads.reserve(thread_cnt);
    for (int t = 0; t < thread_cnt; ++t) {
        threads.emplace_back([&] {
            for (int i = 0; i < per_thread; ++i) {
                auto h = pool->acquire();
                if (!h) std::abort();
                // Touch the buffer to prove it's writable.
                h->id = i;
                h->data[0] = static_cast<uint8_t>(i & 0xFF);
                ops.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }
    for (auto& th : threads) th.join();

    CHECK(ops.load() == thread_cnt * per_thread);
    CHECK(pool->available() == capacity);
    CHECK(pool->in_flight() == 0);
}

// ---------------------------------------------------------------------------
// Custom factory is invoked exactly `capacity` times.
// ---------------------------------------------------------------------------

TEST(custom_factory) {
    std::atomic<int> created{0};
    auto pool = MemoryPool<Buffer>::create(3, [&] {
        created.fetch_add(1);
        auto b = std::make_unique<Buffer>();
        b->id = -1;  // distinguishable marker
        return b;
    });
    CHECK(created.load() == 3);

    auto h = pool->acquire();
    CHECK(h != nullptr);
    CHECK(h->id == -1);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main() {
    run_test_pool_reuse();
    run_test_try_acquire_empty();
    run_test_acquire_timeout();
    run_test_acquire_cancel();
    run_test_leak_detection();
    run_test_concurrent_stress();
    run_test_custom_factory();

    std::fprintf(stderr, "\n%d test(s) passed, %d test(s) failed\n",
                 g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
