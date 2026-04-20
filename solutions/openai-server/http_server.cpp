// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "http_server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <sstream>

namespace ra::solutions::openai {

namespace {

std::string ascii_lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                    [](unsigned char c) { return std::tolower(c); });
    return s;
}

std::string read_all(int fd, std::size_t max_bytes = 4 * 1024 * 1024) {
    std::string out;
    out.reserve(4096);
    char buf[4096];
    while (out.size() < max_bytes) {
        auto n = ::read(fd, buf, sizeof(buf));
        if (n <= 0) break;
        out.append(buf, buf + n);
        if (n < static_cast<ssize_t>(sizeof(buf))) break;  // likely end
    }
    return out;
}

bool write_all(int fd, const std::string& s) {
    const char* p = s.data();
    std::size_t left = s.size();
    while (left > 0) {
        auto n = ::write(fd, p, left);
        if (n <= 0) return false;
        p += n; left -= static_cast<std::size_t>(n);
    }
    return true;
}

bool parse_request(const std::string& raw, HttpRequest& out) {
    const auto crlf = raw.find("\r\n");
    if (crlf == std::string::npos) return false;
    std::string reqLine = raw.substr(0, crlf);
    auto sp1 = reqLine.find(' ');
    auto sp2 = reqLine.rfind(' ');
    if (sp1 == std::string::npos || sp2 == std::string::npos || sp1 == sp2) {
        return false;
    }
    out.method = reqLine.substr(0, sp1);
    const std::string fullPath = reqLine.substr(sp1 + 1, sp2 - sp1 - 1);
    const auto qm = fullPath.find('?');
    if (qm != std::string::npos) {
        out.path  = fullPath.substr(0, qm);
        out.query = fullPath.substr(qm + 1);
    } else {
        out.path = fullPath;
    }
    // Headers
    std::size_t pos = crlf + 2;
    while (pos < raw.size()) {
        const auto eol = raw.find("\r\n", pos);
        if (eol == std::string::npos) break;
        if (eol == pos) { pos = eol + 2; break; }  // end of headers
        const auto line = raw.substr(pos, eol - pos);
        const auto c = line.find(':');
        if (c != std::string::npos) {
            std::string k = ascii_lower(line.substr(0, c));
            std::string v = line.substr(c + 1);
            while (!v.empty() && (v.front() == ' ' || v.front() == '\t')) v.erase(v.begin());
            out.headers[k] = v;
        }
        pos = eol + 2;
    }
    out.body = raw.substr(pos);
    return true;
}

std::string reason_phrase(int code) {
    switch (code) {
    case 200: return "OK";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 500: return "Internal Server Error";
    default:   return "Status";
    }
}

std::string serialize_response(const HttpResponse& r) {
    std::ostringstream os;
    os << "HTTP/1.1 " << r.status << " " << reason_phrase(r.status) << "\r\n"
       << "Content-Type: " << r.content_type << "\r\n"
       << "Content-Length: " << r.body.size() << "\r\n"
       << "Access-Control-Allow-Origin: *\r\n"
       << "Connection: close\r\n\r\n"
       << r.body;
    return os.str();
}

}  // namespace

HttpServer::HttpServer() {
    signal(SIGPIPE, SIG_IGN);
}

HttpServer::~HttpServer() { stop(); }

int HttpServer::start(const std::string& host, int port) {
    if (running_.load()) return -1;
    listen_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd_ < 0) return -1;

    int optval = 1;
    ::setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(static_cast<uint16_t>(port));
    if (host.empty() || host == "0.0.0.0") {
        addr.sin_addr.s_addr = INADDR_ANY;
    } else {
        addr.sin_addr.s_addr = inet_addr(host.c_str());
    }
    if (::bind(listen_fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(listen_fd_); listen_fd_ = -1;
        return -1;
    }
    if (::listen(listen_fd_, 16) < 0) {
        ::close(listen_fd_); listen_fd_ = -1;
        return -1;
    }
    // Resolve the actual port (useful when port=0 for auto-pick).
    sockaddr_in bound{}; socklen_t len = sizeof(bound);
    ::getsockname(listen_fd_, reinterpret_cast<sockaddr*>(&bound), &len);
    bound_port_ = ntohs(bound.sin_port);
    running_.store(true);
    accept_thread_ = std::thread([this] { acceptLoop(); });
    return 0;
}

void HttpServer::stop() {
    if (!running_.load()) return;
    running_.store(false);
    if (listen_fd_ >= 0) {
        ::shutdown(listen_fd_, SHUT_RDWR);
        ::close(listen_fd_);
        listen_fd_ = -1;
    }
    if (accept_thread_.joinable()) accept_thread_.join();
}

void HttpServer::on(const std::string& method, const std::string& path,
                     RouteHandler h) {
    std::lock_guard lk(routes_mu_);
    routes_[method + " " + path] = std::move(h);
}

void HttpServer::acceptLoop() {
    while (running_.load()) {
        sockaddr_in peer{}; socklen_t len = sizeof(peer);
        int fd = ::accept(listen_fd_,
                            reinterpret_cast<sockaddr*>(&peer), &len);
        if (fd < 0) {
            if (!running_.load()) break;
            continue;
        }
        std::thread([this, fd] { handleConnection(fd); }).detach();
    }
}

void HttpServer::handleConnection(int client_fd) {
    std::string raw = read_all(client_fd);
    HttpRequest req;
    if (!parse_request(raw, req)) {
        HttpResponse r{400, "text/plain", "bad request"};
        write_all(client_fd, serialize_response(r));
        ::close(client_fd);
        return;
    }
    HttpResponse r = dispatch(req);
    write_all(client_fd, serialize_response(r));
    ::close(client_fd);
}

HttpResponse HttpServer::dispatch(const HttpRequest& req) {
    std::lock_guard lk(routes_mu_);
    const auto key = req.method + " " + req.path;
    auto it = routes_.find(key);
    if (it != routes_.end()) return it->second(req);
    auto fallback = routes_.find("* *");
    if (fallback != routes_.end()) return fallback->second(req);
    return HttpResponse{404, "application/json",
        R"({"error":{"message":"route not found","type":"invalid_request_error"}})"};
}

}  // namespace ra::solutions::openai
