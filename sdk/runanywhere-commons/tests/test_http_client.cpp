/**
 * @file test_http_client.cpp
 * @brief End-to-end tests for the `rac_http_client_*` C ABI.
 *
 * Runs an in-process HTTP/1.1 server (plain `socket()` + canned
 * responses, single-threaded accept loop) on 127.0.0.1:<ephemeral
 * port>. No external services — tests work fully offline.
 *
 * Covered:
 *   - GET / POST / PUT / DELETE happy path
 *   - Custom headers round-trip
 *   - Redirect (301, 302, 307)
 *   - Timeout (/slow endpoint)
 *   - Streaming download with cancellation
 *   - Resume (start → cancel at 50% → resume → verify merged content)
 */

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/http/rac_http_client.h"

// =============================================================================
// Minimal single-threaded HTTP/1.1 server used by the tests.
// =============================================================================

namespace {

std::string g_last_method;
std::string g_last_path;
std::string g_last_body;
std::vector<std::pair<std::string, std::string>> g_last_headers;

std::atomic<bool> g_server_running{false};
int g_server_fd = -1;
uint16_t g_server_port = 0;

// A "download payload" we serve on /payload; filled with deterministic
// bytes so resume can diff merged contents.
std::vector<uint8_t> make_payload(size_t n) {
    std::vector<uint8_t> p(n);
    for (size_t i = 0; i < n; ++i) {
        p[i] = static_cast<uint8_t>(i & 0xFF);
    }
    return p;
}

// 512 KiB ensures libcurl splits the response across many chunk
// callbacks (default write buffer is 16 KiB), so cancellation /
// resume tests can reliably observe mid-stream state.
std::vector<uint8_t> g_payload = make_payload(512 * 1024);

void write_all(int fd, const void* buf, size_t n) {
    const char* p = static_cast<const char*>(buf);
    while (n > 0) {
        ssize_t w = ::send(fd, p, n, 0);
        if (w <= 0) return;
        p += w;
        n -= static_cast<size_t>(w);
    }
}

// Parse "METHOD /path HTTP/1.1\r\nHeader: val\r\n\r\n<body>"
void parse_request(const std::string& raw) {
    g_last_headers.clear();
    g_last_body.clear();
    g_last_method.clear();
    g_last_path.clear();

    size_t end_of_headers = raw.find("\r\n\r\n");
    if (end_of_headers == std::string::npos) return;
    std::string head = raw.substr(0, end_of_headers);
    g_last_body = raw.substr(end_of_headers + 4);

    std::istringstream iss(head);
    std::string line;
    if (!std::getline(iss, line)) return;
    if (!line.empty() && line.back() == '\r') line.pop_back();
    {
        std::istringstream ls(line);
        std::string version;
        ls >> g_last_method >> g_last_path >> version;
    }
    while (std::getline(iss, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) break;
        auto c = line.find(':');
        if (c == std::string::npos) continue;
        std::string n = line.substr(0, c);
        std::string v = line.substr(c + 1);
        while (!v.empty() && (v.front() == ' ' || v.front() == '\t')) v.erase(0, 1);
        g_last_headers.emplace_back(std::move(n), std::move(v));
    }
}

std::string header_value(const std::string& name) {
    for (auto& h : g_last_headers) {
        if (h.first == name) return h.second;
    }
    return {};
}

void respond(int client, int status, const std::string& status_text, const std::string& body,
             const std::vector<std::pair<std::string, std::string>>& extra_headers = {}) {
    std::ostringstream oss;
    oss << "HTTP/1.1 " << status << " " << status_text << "\r\n";
    oss << "Content-Length: " << body.size() << "\r\n";
    oss << "Connection: close\r\n";
    for (auto& h : extra_headers) {
        oss << h.first << ": " << h.second << "\r\n";
    }
    oss << "\r\n";
    std::string hdr = oss.str();
    write_all(client, hdr.data(), hdr.size());
    write_all(client, body.data(), body.size());
}

void respond_bytes(int client, int status, const std::string& status_text,
                   const uint8_t* bytes, size_t n,
                   const std::vector<std::pair<std::string, std::string>>& extra_headers = {}) {
    std::ostringstream oss;
    oss << "HTTP/1.1 " << status << " " << status_text << "\r\n";
    oss << "Content-Length: " << n << "\r\n";
    oss << "Connection: close\r\n";
    for (auto& h : extra_headers) {
        oss << h.first << ": " << h.second << "\r\n";
    }
    oss << "\r\n";
    std::string hdr = oss.str();
    write_all(client, hdr.data(), hdr.size());
    write_all(client, bytes, n);
}

void handle_client(int client) {
    // Read up to 4 KiB of request — tests send small payloads only.
    char buf[8192];
    std::string raw;
    while (true) {
        ssize_t n = ::recv(client, buf, sizeof(buf), 0);
        if (n <= 0) break;
        raw.append(buf, buf + n);
        if (raw.find("\r\n\r\n") != std::string::npos) {
            // If there's a Content-Length, keep reading body.
            parse_request(raw);
            std::string cl = header_value("Content-Length");
            if (!cl.empty()) {
                size_t want = std::stoul(cl);
                while (g_last_body.size() < want) {
                    ssize_t m = ::recv(client, buf, sizeof(buf), 0);
                    if (m <= 0) break;
                    g_last_body.append(buf, buf + m);
                }
            }
            break;
        }
    }
    parse_request(raw);

    // ---- Routing --------------------------------------------------
    if (g_last_path == "/echo") {
        respond(client, 200, "OK", g_last_body,
                {{"X-Echo-Method", g_last_method}, {"X-Echo-Custom", header_value("X-Custom")}});
    } else if (g_last_path == "/redirect-301") {
        respond(client, 301, "Moved Permanently", "",
                {{"Location", "/echo"}});
    } else if (g_last_path == "/redirect-302") {
        respond(client, 302, "Found", "", {{"Location", "/echo"}});
    } else if (g_last_path == "/redirect-307") {
        respond(client, 307, "Temporary Redirect", "", {{"Location", "/echo"}});
    } else if (g_last_path == "/slow") {
        // Sleep past the client's timeout; then respond.
        std::this_thread::sleep_for(std::chrono::seconds(5));
        respond(client, 200, "OK", "slow-ok");
    } else if (g_last_path == "/payload") {
        std::string range = header_value("Range");
        if (!range.empty() && range.rfind("bytes=", 0) == 0) {
            size_t from = 0;
            try {
                from = std::stoul(range.substr(6));
            } catch (...) {
                from = 0;
            }
            if (from < g_payload.size()) {
                std::ostringstream cr;
                cr << "bytes " << from << "-" << (g_payload.size() - 1) << "/" << g_payload.size();
                respond_bytes(client, 206, "Partial Content", g_payload.data() + from,
                              g_payload.size() - from,
                              {{"Content-Range", cr.str()}, {"Accept-Ranges", "bytes"}});
                ::close(client);
                return;
            }
        }
        respond_bytes(client, 200, "OK", g_payload.data(), g_payload.size(),
                      {{"Accept-Ranges", "bytes"}});
    } else {
        respond(client, 404, "Not Found", "not found");
    }

    ::close(client);
}

void server_loop(int fd) {
    while (g_server_running) {
        sockaddr_in cli{};
        socklen_t len = sizeof(cli);
        int c = ::accept(fd, reinterpret_cast<sockaddr*>(&cli), &len);
        if (c < 0) {
            if (g_server_running) continue;
            break;
        }
        handle_client(c);
    }
}

bool start_server() {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return false;
    int one = 1;
    ::setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;  // ephemeral
    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        return false;
    }
    socklen_t l = sizeof(addr);
    if (::getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &l) != 0) {
        ::close(fd);
        return false;
    }
    g_server_port = ntohs(addr.sin_port);
    if (::listen(fd, 16) != 0) {
        ::close(fd);
        return false;
    }
    g_server_fd = fd;
    g_server_running = true;
    std::thread(server_loop, fd).detach();
    return true;
}

void stop_server() {
    g_server_running = false;
    if (g_server_fd >= 0) {
        ::shutdown(g_server_fd, SHUT_RDWR);
        ::close(g_server_fd);
        g_server_fd = -1;
    }
}

std::string server_url(const std::string& path) {
    std::ostringstream oss;
    oss << "http://127.0.0.1:" << g_server_port << path;
    return oss.str();
}

// =============================================================================
// Tiny assert machinery.
// =============================================================================

int g_failures = 0;
int g_passes = 0;

#define CHECK(cond)                                                                    \
    do {                                                                               \
        if (cond) {                                                                    \
            ++g_passes;                                                                \
        } else {                                                                       \
            ++g_failures;                                                              \
            std::cerr << "\033[31m[FAIL]\033[0m " << __FILE__ << ":" << __LINE__       \
                      << " — " #cond << "\n";                                          \
        }                                                                              \
    } while (0)

#define CHECK_EQ_I(a, b)                                                               \
    do {                                                                               \
        auto _a = (a);                                                                 \
        auto _b = (b);                                                                 \
        if (_a == _b) {                                                                \
            ++g_passes;                                                                \
        } else {                                                                       \
            ++g_failures;                                                              \
            std::cerr << "\033[31m[FAIL]\033[0m " << __FILE__ << ":" << __LINE__       \
                      << " — " #a " == " #b " (got " << _a << " vs " << _b << ")\n";   \
        }                                                                              \
    } while (0)

// =============================================================================
// Tests.
// =============================================================================

void test_get_happy_path() {
    rac_http_client_t* c = nullptr;
    CHECK_EQ_I(rac_http_client_create(&c), RAC_SUCCESS);

    std::string url = server_url("/echo");
    rac_http_request_t req{};
    req.method = "GET";
    req.url = url.c_str();
    req.follow_redirects = RAC_TRUE;
    req.timeout_ms = 5000;

    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_SUCCESS);
    CHECK_EQ_I(resp.status, 200);
    // /echo reflects the body; GET has no body → 0 bytes back.
    CHECK_EQ_I(resp.body_len, size_t{0});

    rac_http_response_free(&resp);
    rac_http_client_destroy(c);
}

void test_post_roundtrip() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    std::string url = server_url("/echo");
    const char* body = "hello-commons";
    rac_http_request_t req{};
    req.method = "POST";
    req.url = url.c_str();
    req.body_bytes = reinterpret_cast<const uint8_t*>(body);
    req.body_len = std::strlen(body);

    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_SUCCESS);
    CHECK_EQ_I(resp.status, 200);
    CHECK_EQ_I(resp.body_len, std::strlen(body));
    CHECK(resp.body_bytes && std::memcmp(resp.body_bytes, body, resp.body_len) == 0);

    rac_http_response_free(&resp);
    rac_http_client_destroy(c);
}

void test_put_and_delete() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    std::string url = server_url("/echo");
    for (const char* m : {"PUT", "DELETE"}) {
        const char* body = "payload";
        rac_http_request_t req{};
        req.method = m;
        req.url = url.c_str();
        req.body_bytes = reinterpret_cast<const uint8_t*>(body);
        req.body_len = std::strlen(body);
        rac_http_response_t resp{};
        CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_SUCCESS);
        CHECK_EQ_I(resp.status, 200);
        rac_http_response_free(&resp);
    }

    rac_http_client_destroy(c);
}

void test_custom_headers() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    std::string url = server_url("/echo");
    rac_http_header_kv_t hs[2] = {{"X-Custom", "round-trip"}, {"X-Sdk", "rac-commons"}};
    rac_http_request_t req{};
    req.method = "GET";
    req.url = url.c_str();
    req.headers = hs;
    req.header_count = 2;

    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_SUCCESS);
    CHECK_EQ_I(resp.status, 200);

    // /echo bounces X-Custom back on X-Echo-Custom.
    bool found = false;
    for (size_t i = 0; i < resp.header_count; ++i) {
        if (std::strcmp(resp.headers[i].name, "X-Echo-Custom") == 0) {
            found = (std::strcmp(resp.headers[i].value, "round-trip") == 0);
            break;
        }
    }
    CHECK(found);

    rac_http_response_free(&resp);
    rac_http_client_destroy(c);
}

void test_redirects() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    for (const char* path : {"/redirect-301", "/redirect-302", "/redirect-307"}) {
        std::string url = server_url(path);
        rac_http_request_t req{};
        req.method = "GET";
        req.url = url.c_str();
        req.follow_redirects = RAC_TRUE;
        rac_http_response_t resp{};
        CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_SUCCESS);
        CHECK_EQ_I(resp.status, 200);
        CHECK(resp.redirected_url != nullptr);
        rac_http_response_free(&resp);
    }

    rac_http_client_destroy(c);
}

void test_timeout() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    std::string url = server_url("/slow");
    rac_http_request_t req{};
    req.method = "GET";
    req.url = url.c_str();
    req.timeout_ms = 150;

    rac_http_response_t resp{};
    rac_result_t rc = rac_http_request_send(c, &req, &resp);
    CHECK_EQ_I(rc, RAC_ERROR_TIMEOUT);
    rac_http_response_free(&resp);

    rac_http_client_destroy(c);
}

struct collect_ctx {
    std::vector<uint8_t> bytes;
    size_t stop_after = 0;  // if non-zero, cancel after this many bytes
};

rac_bool_t collect_chunks(const uint8_t* chunk, size_t len, uint64_t, uint64_t, void* user) {
    auto* ctx = static_cast<collect_ctx*>(user);
    ctx->bytes.insert(ctx->bytes.end(), chunk, chunk + len);
    if (ctx->stop_after && ctx->bytes.size() >= ctx->stop_after) {
        return RAC_FALSE;
    }
    return RAC_TRUE;
}

void test_streaming_cancellation() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    std::string url = server_url("/payload");
    rac_http_request_t req{};
    req.method = "GET";
    req.url = url.c_str();

    collect_ctx ctx;
    ctx.stop_after = g_payload.size() / 2;  // cancel at ~50%

    rac_http_response_t resp{};
    rac_result_t rc = rac_http_request_stream(c, &req, collect_chunks, &ctx, &resp);
    CHECK_EQ_I(rc, RAC_ERROR_CANCELLED);
    CHECK(ctx.bytes.size() >= ctx.stop_after);
    CHECK(ctx.bytes.size() < g_payload.size());
    // Streaming never populates body_bytes.
    CHECK(resp.body_bytes == nullptr);

    rac_http_response_free(&resp);
    rac_http_client_destroy(c);
}

void test_resume_merged_matches() {
    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);

    // --- pass 1: download first half and cancel -------------------
    std::string url = server_url("/payload");
    rac_http_request_t req{};
    req.method = "GET";
    req.url = url.c_str();

    collect_ctx first;
    first.stop_after = g_payload.size() / 2;

    rac_http_response_t r1{};
    (void)rac_http_request_stream(c, &req, collect_chunks, &first, &r1);
    rac_http_response_free(&r1);

    // Truncate to the exact cancel point to simulate what a caller
    // would keep on disk (the cancel callback sees the whole chunk,
    // so `first.bytes` is usually a few bytes past the limit).
    first.bytes.resize(first.stop_after);

    // --- pass 2: resume from where we stopped ---------------------
    collect_ctx rest;
    rac_http_response_t r2{};
    rac_result_t rc = rac_http_request_resume(c, &req, first.bytes.size(), collect_chunks,
                                              &rest, &r2);
    CHECK_EQ_I(rc, RAC_SUCCESS);
    CHECK_EQ_I(r2.status, 206);

    // Merge and compare.
    std::vector<uint8_t> merged = first.bytes;
    merged.insert(merged.end(), rest.bytes.begin(), rest.bytes.end());
    CHECK_EQ_I(merged.size(), g_payload.size());
    CHECK(merged == g_payload);

    rac_http_response_free(&r2);
    rac_http_client_destroy(c);
}

void test_invalid_arguments() {
    CHECK_EQ_I(rac_http_client_create(nullptr), RAC_ERROR_INVALID_ARGUMENT);

    rac_http_client_t* c = nullptr;
    rac_http_client_create(&c);
    rac_http_response_t resp{};
    CHECK_EQ_I(rac_http_request_send(c, nullptr, &resp), RAC_ERROR_INVALID_ARGUMENT);

    rac_http_request_t req{};  // method/url NULL → invalid
    CHECK_EQ_I(rac_http_request_send(c, &req, &resp), RAC_ERROR_INVALID_ARGUMENT);

    rac_http_response_free(&resp);
    rac_http_client_destroy(c);

    // Destroy NULL is a no-op.
    rac_http_client_destroy(nullptr);
    rac_http_response_free(nullptr);
}

}  // namespace

int main() {
    std::cout << "=== rac_http_client tests ===\n";

    if (!start_server()) {
        std::cerr << "failed to start loopback HTTP server\n";
        return 1;
    }
    std::cout << "loopback server listening on 127.0.0.1:" << g_server_port << "\n";

    test_get_happy_path();
    test_post_roundtrip();
    test_put_and_delete();
    test_custom_headers();
    test_redirects();
    test_timeout();
    test_streaming_cancellation();
    test_resume_merged_matches();
    test_invalid_arguments();

    stop_server();

    std::cout << "passes=" << g_passes << " failures=" << g_failures << "\n";
    return g_failures == 0 ? 0 : 1;
}
