// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// OpenAI-route smoke tests. Exercises the HTTP surface without an LLM
// session registered — real-LLM e2e lives in core/tests/e2e/ behind
// RA_TEST_GGUF.

#include <gtest/gtest.h>

#include "ra_server.h"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <chrono>
#include <thread>

using json = nlohmann::json;

class OpenAiRoutesTest : public ::testing::Test {
protected:
    int port = 0;

    void SetUp() override {
        ra_server_config_t cfg{};
        cfg.host = "127.0.0.1";
        cfg.port = 0;
        ASSERT_EQ(ra_server_start(&cfg), RA_OK);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        ra_server_status_t s{};
        ASSERT_EQ(ra_server_get_status(&s), RA_OK);
        port = s.port;
    }
    void TearDown() override { ra_server_stop(); }
};

TEST_F(OpenAiRoutesTest, HealthReturnsOk) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/health");
    ASSERT_TRUE(r) << "no response from /health";
    EXPECT_EQ(r->status, 200);
    auto body = json::parse(r->body);
    EXPECT_EQ(body.value("status", ""), "ok");
    EXPECT_TRUE(body.contains("model_loaded"));
}

TEST_F(OpenAiRoutesTest, HealthzAlias) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/healthz");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
}

TEST_F(OpenAiRoutesTest, RootReturnsInfo) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
    auto body = json::parse(r->body);
    EXPECT_EQ(body.value("name", ""), "RunAnywhere Server");
    EXPECT_TRUE(body["endpoints"].is_array());
}

TEST_F(OpenAiRoutesTest, ModelsListOpenAiShape) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Get("/v1/models");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 200);
    auto body = json::parse(r->body);
    EXPECT_EQ(body.value("object", ""), "list");
    EXPECT_TRUE(body["data"].is_array());
    EXPECT_GE(body["data"].size(), 1u);
}

TEST_F(OpenAiRoutesTest, ChatCompletionReturns503WithoutSession) {
    httplib::Client c("127.0.0.1", port);
    json req = {
        {"model", "runanywhere-local"},
        {"messages", json::array({json{{"role", "user"}, {"content", "hi"}}})}
    };
    auto r = c.Post("/v1/chat/completions", req.dump(), "application/json");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 503);
    auto body = json::parse(r->body);
    EXPECT_TRUE(body.contains("error"));
}

TEST_F(OpenAiRoutesTest, ChatCompletionWithNoMessagesReturns400) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Post("/v1/chat/completions", "{\"messages\":[]}",
                    "application/json");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 400);
}

TEST_F(OpenAiRoutesTest, InvalidJsonReturns400) {
    httplib::Client c("127.0.0.1", port);
    auto r = c.Post("/v1/chat/completions", "not json", "application/json");
    ASSERT_TRUE(r);
    EXPECT_EQ(r->status, 400);
}
