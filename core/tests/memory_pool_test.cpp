// SPDX-License-Identifier: Apache-2.0
#include "memory_pool.h"
#include <gtest/gtest.h>

using ra::core::MemoryPool;
using ra::core::PooledBlock;

TEST(MemoryPool, AcquireUntilEmpty) {
    MemoryPool pool(/*block_bytes=*/64, /*num_blocks=*/4);
    EXPECT_EQ(pool.available(), 4u);

    auto* a = pool.acquire();
    auto* b = pool.acquire();
    auto* c = pool.acquire();
    auto* d = pool.acquire();
    EXPECT_NE(a, nullptr);
    EXPECT_NE(b, nullptr);
    EXPECT_NE(c, nullptr);
    EXPECT_NE(d, nullptr);
    EXPECT_EQ(pool.acquire(), nullptr);
    EXPECT_EQ(pool.available(), 0u);

    pool.release(a);
    pool.release(b);
    EXPECT_EQ(pool.available(), 2u);
}

TEST(MemoryPool, PooledBlockReleasesOnDestruction) {
    MemoryPool pool(64, 2);
    {
        PooledBlock blk(&pool, pool.acquire());
        EXPECT_EQ(pool.available(), 1u);
        EXPECT_TRUE(blk);
    }
    EXPECT_EQ(pool.available(), 2u);
}

TEST(MemoryPool, BlocksAreAligned) {
    MemoryPool pool(/*block_bytes=*/100, /*num_blocks=*/4,
                    /*alignment=*/64);
    auto* p = pool.acquire();
    ASSERT_NE(p, nullptr);
    EXPECT_EQ(reinterpret_cast<std::uintptr_t>(p) % 64, 0u);
    pool.release(p);
}
