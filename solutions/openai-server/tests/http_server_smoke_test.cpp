// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Lifecycle smoke: start → running → stop via the ra_server_* C ABI.

#include <gtest/gtest.h>

#include "ra_server.h"

#include <chrono>
#include <thread>

TEST(OpenAiServerLifecycle, StartsAndStops) {
    ra_server_config_t cfg{};
    cfg.host = "127.0.0.1";
    cfg.port = 0;

    ASSERT_EQ(ra_server_start(&cfg), RA_OK);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    EXPECT_EQ(ra_server_is_running(), 1);
    ra_server_status_t st{};
    ASSERT_EQ(ra_server_get_status(&st), RA_OK);
    EXPECT_GT(st.port, 0);

    EXPECT_EQ(ra_server_stop(), RA_OK);
    EXPECT_EQ(ra_server_is_running(), 0);
}

TEST(OpenAiServerLifecycle, StopWithoutStartIsOk) {
    EXPECT_EQ(ra_server_stop(), RA_OK);
}
