// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../http_server.h"

#include <chrono>
#include <netdb.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

using ra::solutions::openai::HttpServer;
using ra::solutions::openai::HttpResponse;

namespace {

std::string fetch(const std::string& host, int port, const std::string& req) {
    addrinfo hints{}; hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    addrinfo* res = nullptr;
    const std::string svc = std::to_string(port);
    if (getaddrinfo(host.c_str(), svc.c_str(), &hints, &res) != 0) return "";
    int fd = ::socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) { freeaddrinfo(res); return ""; }
    int rc = ::connect(fd, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);
    if (rc < 0) { ::close(fd); return ""; }
    ::send(fd, req.data(), req.size(), 0);
    std::string out; out.reserve(1024);
    char buf[1024];
    while (true) {
        auto n = ::recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) break;
        out.append(buf, buf + n);
    }
    ::close(fd);
    return out;
}

}  // namespace

TEST(OpenAiHttpServer, HealthcheckReturns200) {
    HttpServer s;
    s.on("GET", "/healthz", [](const auto&) {
        return HttpResponse{200, "application/json", R"({"ok":true})"};
    });
    ASSERT_EQ(s.start("127.0.0.1", 0), 0);
    const int port = s.port();
    ASSERT_GT(port, 0);

    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    const std::string req =
        "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    const auto reply = fetch("127.0.0.1", port, req);
    EXPECT_NE(reply.find("200 OK"), std::string::npos);
    EXPECT_NE(reply.find(R"({"ok":true})"), std::string::npos);

    s.stop();
}

TEST(OpenAiHttpServer, UnknownRouteReturns404) {
    HttpServer s;
    ASSERT_EQ(s.start("127.0.0.1", 0), 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    const std::string req =
        "GET /nope HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    const auto reply = fetch("127.0.0.1", s.port(), req);
    EXPECT_NE(reply.find("404"), std::string::npos);
    s.stop();
}
