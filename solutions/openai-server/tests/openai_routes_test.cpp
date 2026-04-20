// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../../../core/abi/ra_server.h"

#include <chrono>
#include <cstdio>
#include <netdb.h>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

namespace {

std::string fetch(const std::string& host, int port, const std::string& req) {
    addrinfo hints{}; hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    addrinfo* res = nullptr;
    if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0) return "";
    int fd = ::socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    ::connect(fd, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);
    ::send(fd, req.data(), req.size(), 0);
    std::string out; char buf[2048];
    while (true) {
        auto n = ::recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) break;
        out.append(buf, buf + n);
    }
    ::close(fd);
    return out;
}

class OpenAiRoutesTest : public ::testing::Test {
protected:
    int port = 0;

    void SetUp() override {
        ra_server_config_t cfg{};
        cfg.host = "127.0.0.1";
        cfg.port = 0;
        ASSERT_EQ(ra_server_start(&cfg), RA_OK);
        ra_server_status_t status{};
        ra_server_get_status(&status);
        port = status.port;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    void TearDown() override {
        ra_server_stop();
    }
};

}  // namespace

TEST_F(OpenAiRoutesTest, HealthReturns200) {
    const auto r = fetch("127.0.0.1", port,
        "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    EXPECT_NE(r.find("200 OK"), std::string::npos);
    EXPECT_NE(r.find(R"({"ok":true})"), std::string::npos);
}

TEST_F(OpenAiRoutesTest, HealthzStillWorks) {
    const auto r = fetch("127.0.0.1", port,
        "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    EXPECT_NE(r.find("200 OK"), std::string::npos);
}

TEST_F(OpenAiRoutesTest, RootReturnsInfoJson) {
    const auto r = fetch("127.0.0.1", port,
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    EXPECT_NE(r.find("200 OK"), std::string::npos);
    EXPECT_NE(r.find("runanywhere-openai-server"), std::string::npos);
    EXPECT_NE(r.find("/v1/chat/completions"), std::string::npos);
}

TEST_F(OpenAiRoutesTest, V1ModelsReturnsOpenAiShape) {
    const auto r = fetch("127.0.0.1", port,
        "GET /v1/models HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
    EXPECT_NE(r.find("200 OK"), std::string::npos);
    EXPECT_NE(r.find("\"object\":\"list\""), std::string::npos);
    EXPECT_NE(r.find("runanywhere-local"), std::string::npos);
}

TEST_F(OpenAiRoutesTest, ChatCompletionReturnsOpenAiEnvelope) {
    const std::string body = R"({"model":"runanywhere-local","messages":[{"role":"user","content":"hello there"}]})";
    char req[1024];
    std::snprintf(req, sizeof(req),
        "POST /v1/chat/completions HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n\r\n%s",
        body.size(), body.c_str());
    const auto r = fetch("127.0.0.1", port, req);
    EXPECT_NE(r.find("200 OK"), std::string::npos);
    EXPECT_NE(r.find("\"object\":\"chat.completion\""), std::string::npos);
    EXPECT_NE(r.find("\"finish_reason\":\"stop\""), std::string::npos);
    EXPECT_NE(r.find("\"usage\""), std::string::npos);
}

TEST_F(OpenAiRoutesTest, ChatCompletionWithNoUserReturns400) {
    const std::string body = R"({"messages":[]})";
    char req[512];
    std::snprintf(req, sizeof(req),
        "POST /v1/chat/completions HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n\r\n%s",
        body.size(), body.c_str());
    const auto r = fetch("127.0.0.1", port, req);
    EXPECT_NE(r.find("400"), std::string::npos);
}
