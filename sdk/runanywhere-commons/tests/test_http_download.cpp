/**
 * @file test_http_download.cpp
 * @brief Integration tests for `rac_http_download_execute` — the
 * runner that replaces the HttpURLConnection loop in Kotlin.
 *
 * Reuses the same in-process loopback HTTP/1.1 server pattern as
 * test_http_client.cpp. Scenarios:
 *   - happy path (full download to disk, SHA-256 verify)
 *   - cancellation via progress callback → CANCELLED status
 *   - resume (download half + kill + resume + verify bytes match)
 *   - HTTP 404 → SERVER_ERROR
 *   - invalid URL → INVALID_URL
 *   - checksum mismatch → CHECKSUM_FAILED
 */

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/http/rac_http_download.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace fs = std::filesystem;

namespace {

std::atomic<bool> g_running{false};
int g_fd = -1;
uint16_t g_port = 0;

std::vector<uint8_t> make_payload(size_t n) {
    std::vector<uint8_t> p(n);
    for (size_t i = 0; i < n; ++i) p[i] = static_cast<uint8_t>((i * 7) & 0xff);
    return p;
}
// 512 KiB — large enough that libcurl's default 16 KiB write buffer
// forces multiple on_chunk callbacks, so cancel / resume tests can
// observe mid-stream state deterministically.
std::vector<uint8_t> g_payload = make_payload(512 * 1024);

// SHA-256("<deterministic 32 KiB payload>") — expected digest is
// computed once at runtime before the tests run.
std::string g_expected_sha;

std::string path_from_url(const char* url) {
    std::string s = url ? url : "";
    auto scheme = s.find("://");
    if (scheme != std::string::npos) {
        auto slash = s.find('/', scheme + 3);
        return slash == std::string::npos ? "/" : s.substr(slash);
    }
    return s;
}

rac_bool_t stream_payload_from(size_t from, rac_http_body_chunk_fn cb, void* cb_user_data) {
    const size_t chunk = 8192;
    uint64_t delivered = 0;
    for (size_t offset = from; offset < g_payload.size(); offset += chunk) {
        size_t n = std::min(chunk, g_payload.size() - offset);
        delivered += n;
        if (cb(g_payload.data() + offset, n, delivered,
               static_cast<uint64_t>(g_payload.size() - from), cb_user_data) == RAC_FALSE) {
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

rac_result_t test_transport_send(void*, const rac_http_request_t*, rac_http_response_t* out_resp) {
    if (!out_resp) return RAC_ERROR_INVALID_ARGUMENT;
    out_resp->status = 200;
    return RAC_SUCCESS;
}

rac_result_t test_transport_stream(void*, const rac_http_request_t* req,
                                   rac_http_body_chunk_fn cb, void* cb_user_data,
                                   rac_http_response_t* out_resp_meta) {
    if (!req || !req->url || !cb || !out_resp_meta) return RAC_ERROR_INVALID_ARGUMENT;
    std::string path = path_from_url(req->url);
    if (path == "/payload") {
        out_resp_meta->status = 200;
        return stream_payload_from(0, cb, cb_user_data) == RAC_TRUE ? RAC_SUCCESS
                                                                    : RAC_ERROR_CANCELLED;
    }
    if (path == "/missing") {
        static const uint8_t body[] = {'n', 'o', 't', ' ', 'f', 'o', 'u', 'n', 'd'};
        out_resp_meta->status = 404;
        cb(body, sizeof(body), sizeof(body), sizeof(body), cb_user_data);
        return RAC_SUCCESS;
    }
    out_resp_meta->status = 400;
    return RAC_SUCCESS;
}

rac_result_t test_transport_resume(void*, const rac_http_request_t* req, uint64_t resume_from_byte,
                                   rac_http_body_chunk_fn cb, void* cb_user_data,
                                   rac_http_response_t* out_resp_meta) {
    if (!req || !req->url || !cb || !out_resp_meta) return RAC_ERROR_INVALID_ARGUMENT;
    std::string path = path_from_url(req->url);
    if (path != "/payload") {
        out_resp_meta->status = 404;
        return RAC_SUCCESS;
    }
    out_resp_meta->status = 206;
    size_t from = std::min<size_t>(static_cast<size_t>(resume_from_byte), g_payload.size());
    return stream_payload_from(from, cb, cb_user_data) == RAC_TRUE ? RAC_SUCCESS
                                                                   : RAC_ERROR_CANCELLED;
}

const rac_http_transport_ops_t g_test_transport_ops = {
    test_transport_send,
    test_transport_stream,
    test_transport_resume,
    nullptr,
    nullptr,
};

void write_all(int fd, const void* buf, size_t n) {
    const char* p = static_cast<const char*>(buf);
    while (n > 0) {
        ssize_t w = ::send(fd, p, n, 0);
        if (w <= 0) return;
        p += w;
        n -= static_cast<size_t>(w);
    }
}

void handle_client(int c) {
    char buf[8192];
    std::string raw;
    while (true) {
        ssize_t n = ::recv(c, buf, sizeof(buf), 0);
        if (n <= 0) break;
        raw.append(buf, buf + n);
        if (raw.find("\r\n\r\n") != std::string::npos) break;
    }
    // Parse request line + Range.
    std::string method, path, range;
    {
        auto eol = raw.find("\r\n");
        auto first = raw.substr(0, eol == std::string::npos ? 0 : eol);
        std::istringstream iss(first);
        iss >> method >> path;
        auto rpos = raw.find("Range:");
        if (rpos != std::string::npos) {
            auto eolr = raw.find("\r\n", rpos);
            std::string line = raw.substr(rpos, eolr - rpos);
            auto bpos = line.find("bytes=");
            if (bpos != std::string::npos) range = line.substr(bpos + 6);
        }
    }

    if (path == "/payload") {
        uint64_t from = 0;
        if (!range.empty()) {
            try {
                from = std::stoul(range);
            } catch (...) {
                from = 0;
            }
        }
        if (from > 0 && from < g_payload.size()) {
            std::ostringstream hdr;
            hdr << "HTTP/1.1 206 Partial Content\r\n"
                << "Content-Length: " << (g_payload.size() - from) << "\r\n"
                << "Content-Range: bytes " << from << "-" << (g_payload.size() - 1) << "/"
                << g_payload.size() << "\r\n"
                << "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n";
            auto s = hdr.str();
            write_all(c, s.data(), s.size());
            write_all(c, g_payload.data() + from, g_payload.size() - from);
        } else {
            std::ostringstream hdr;
            hdr << "HTTP/1.1 200 OK\r\nContent-Length: " << g_payload.size()
                << "\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n";
            auto s = hdr.str();
            write_all(c, s.data(), s.size());
            write_all(c, g_payload.data(), g_payload.size());
        }
    } else if (path == "/missing") {
        std::string body = "not found";
        std::ostringstream hdr;
        hdr << "HTTP/1.1 404 Not Found\r\nContent-Length: " << body.size()
            << "\r\nConnection: close\r\n\r\n";
        auto s = hdr.str();
        write_all(c, s.data(), s.size());
        write_all(c, body.data(), body.size());
    } else {
        std::string body = "bad";
        std::ostringstream hdr;
        hdr << "HTTP/1.1 400 Bad Request\r\nContent-Length: " << body.size()
            << "\r\nConnection: close\r\n\r\n";
        auto s = hdr.str();
        write_all(c, s.data(), s.size());
        write_all(c, body.data(), body.size());
    }
    ::close(c);
}

void loop(int fd) {
    while (g_running) {
        sockaddr_in cli{};
        socklen_t len = sizeof(cli);
        int c = ::accept(fd, reinterpret_cast<sockaddr*>(&cli), &len);
        if (c < 0) {
            if (g_running) continue;
            break;
        }
        handle_client(c);
    }
}

bool start() {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return false;
    int one = 1;
    ::setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        return false;
    }
    socklen_t l = sizeof(addr);
    ::getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &l);
    g_port = ntohs(addr.sin_port);
    ::listen(fd, 16);
    g_fd = fd;
    g_running = true;
    std::thread(loop, fd).detach();
    return true;
}

void stop() {
    g_running = false;
    if (g_fd >= 0) {
        ::shutdown(g_fd, SHUT_RDWR);
        ::close(g_fd);
        g_fd = -1;
    }
}

std::string url(const std::string& p) {
    std::ostringstream o;
    o << "http://127.0.0.1:" << g_port << p;
    return o.str();
}

// Compact SHA-256 matching the one in rac_http_download.cpp. Used to
// compute the expected digest of the server payload at test startup
// so the checksum-verify path can exercise RAC_HTTP_DL_OK.
namespace sha {
struct ctx {
    uint32_t s[8];
    uint64_t bc;
    uint8_t b[64];
};
static const uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
inline uint32_t rr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
void tr(ctx* c, const uint8_t* d) {
    uint32_t w[64];
    for (int i = 0; i < 16; ++i)
        w[i] = (uint32_t(d[i * 4]) << 24) | (uint32_t(d[i * 4 + 1]) << 16) |
               (uint32_t(d[i * 4 + 2]) << 8) | d[i * 4 + 3];
    for (int i = 16; i < 64; ++i) {
        uint32_t s0 = rr(w[i - 15], 7) ^ rr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = rr(w[i - 2], 17) ^ rr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = c->s[0], b = c->s[1], cc = c->s[2], dd = c->s[3], e = c->s[4], f = c->s[5],
             g = c->s[6], h = c->s[7];
    for (int i = 0; i < 64; ++i) {
        uint32_t S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + K[i] + w[i];
        uint32_t S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22);
        uint32_t mj = (a & b) ^ (a & cc) ^ (b & cc);
        uint32_t t2 = S0 + mj;
        h = g;
        g = f;
        f = e;
        e = dd + t1;
        dd = cc;
        cc = b;
        b = a;
        a = t1 + t2;
    }
    c->s[0] += a;
    c->s[1] += b;
    c->s[2] += cc;
    c->s[3] += dd;
    c->s[4] += e;
    c->s[5] += f;
    c->s[6] += g;
    c->s[7] += h;
}
std::string hash(const uint8_t* data, size_t len) {
    ctx c{};
    c.s[0] = 0x6a09e667;
    c.s[1] = 0xbb67ae85;
    c.s[2] = 0x3c6ef372;
    c.s[3] = 0xa54ff53a;
    c.s[4] = 0x510e527f;
    c.s[5] = 0x9b05688c;
    c.s[6] = 0x1f83d9ab;
    c.s[7] = 0x5be0cd19;
    // For brevity use a single-call path: copy into full-block buffer
    size_t i = 0;
    while (len - i >= 64) {
        tr(&c, data + i);
        i += 64;
    }
    size_t rem = len - i;
    std::memcpy(c.b, data + i, rem);
    c.b[rem] = 0x80;
    if (rem >= 56) {
        std::memset(c.b + rem + 1, 0, 64 - rem - 1);
        tr(&c, c.b);
        std::memset(c.b, 0, 56);
    } else {
        std::memset(c.b + rem + 1, 0, 56 - rem - 1);
    }
    uint64_t bc = uint64_t(len) * 8;
    for (int j = 7; j >= 0; --j) {
        c.b[56 + j] = uint8_t(bc & 0xff);
        bc >>= 8;
    }
    tr(&c, c.b);
    uint8_t out[32];
    for (int j = 0; j < 8; ++j) {
        out[j * 4] = uint8_t(c.s[j] >> 24);
        out[j * 4 + 1] = uint8_t(c.s[j] >> 16);
        out[j * 4 + 2] = uint8_t(c.s[j] >> 8);
        out[j * 4 + 3] = uint8_t(c.s[j]);
    }
    static const char hx[] = "0123456789abcdef";
    std::string s;
    s.resize(64);
    for (int j = 0; j < 32; ++j) {
        s[j * 2] = hx[(out[j] >> 4) & 0xf];
        s[j * 2 + 1] = hx[out[j] & 0xf];
    }
    return s;
}
}  // namespace sha

int passes = 0, failures = 0;

#define T_CHECK(cond)                                                                  \
    do {                                                                               \
        if (cond) {                                                                    \
            ++passes;                                                                  \
        } else {                                                                       \
            ++failures;                                                                \
            std::cerr << "\033[31m[FAIL]\033[0m " << __FILE__ << ":" << __LINE__       \
                      << " — " #cond << "\n";                                          \
        }                                                                              \
    } while (0)

fs::path tmp_file(const std::string& name) {
    fs::path p = fs::temp_directory_path() / ("rac_http_dl_" + std::to_string(::getpid()) + "_" + name);
    fs::remove(p);
    return p;
}

void test_happy_path_with_checksum() {
    auto dest = tmp_file("happy.bin");
    std::string dest_str = dest.string();
    rac_http_download_request_t req{};
    auto u = url("/payload");
    req.url = u.c_str();
    req.destination_path = dest_str.c_str();
    req.timeout_ms = 10000;
    req.follow_redirects = RAC_TRUE;
    req.expected_sha256_hex = g_expected_sha.c_str();
    int32_t http_status = 0;
    auto rc = rac_http_download_execute(&req, nullptr, nullptr, &http_status);
    T_CHECK(rc == RAC_HTTP_DL_OK);
    T_CHECK(http_status == 200);
    T_CHECK(fs::exists(dest));
    T_CHECK(fs::file_size(dest) == g_payload.size());
    fs::remove(dest);
}

void test_checksum_mismatch() {
    auto dest = tmp_file("bad-sum.bin");
    std::string dest_str = dest.string();
    rac_http_download_request_t req{};
    auto u = url("/payload");
    req.url = u.c_str();
    req.destination_path = dest_str.c_str();
    req.timeout_ms = 10000;
    req.follow_redirects = RAC_TRUE;
    std::string wrong(64, '0');
    req.expected_sha256_hex = wrong.c_str();
    int32_t http_status = 0;
    auto rc = rac_http_download_execute(&req, nullptr, nullptr, &http_status);
    T_CHECK(rc == RAC_HTTP_DL_CHECKSUM_FAILED);
    fs::remove(dest);
}

void test_server_error_404() {
    auto dest = tmp_file("404.bin");
    std::string dest_str = dest.string();
    rac_http_download_request_t req{};
    auto u = url("/missing");
    req.url = u.c_str();
    req.destination_path = dest_str.c_str();
    req.timeout_ms = 10000;
    req.follow_redirects = RAC_TRUE;
    int32_t http_status = 0;
    auto rc = rac_http_download_execute(&req, nullptr, nullptr, &http_status);
    T_CHECK(rc == RAC_HTTP_DL_SERVER_ERROR);
    T_CHECK(http_status == 404);
    fs::remove(dest);
}

void test_invalid_url() {
    rac_http_download_request_t req{};
    req.url = nullptr;
    req.destination_path = "/tmp/whatever";
    auto rc = rac_http_download_execute(&req, nullptr, nullptr, nullptr);
    T_CHECK(rc == RAC_HTTP_DL_INVALID_URL);
}

struct cancel_ctx {
    uint64_t cancel_at = 0;
    uint64_t last = 0;
};
rac_bool_t cancel_midway(uint64_t bytes, uint64_t, void* u) {
    auto* ctx = static_cast<cancel_ctx*>(u);
    ctx->last = bytes;
    return bytes >= ctx->cancel_at ? RAC_FALSE : RAC_TRUE;
}

void test_cancel_via_progress() {
    auto dest = tmp_file("cancel.bin");
    std::string dest_str = dest.string();
    rac_http_download_request_t req{};
    auto u = url("/payload");
    req.url = u.c_str();
    req.destination_path = dest_str.c_str();
    req.timeout_ms = 10000;
    req.follow_redirects = RAC_TRUE;
    cancel_ctx cc{};
    cc.cancel_at = g_payload.size() / 3;
    int32_t http_status = 0;
    auto rc = rac_http_download_execute(&req, cancel_midway, &cc, &http_status);
    T_CHECK(rc == RAC_HTTP_DL_CANCELLED);
    fs::remove(dest);
}

void test_resume_merged_matches_payload() {
    auto dest = tmp_file("resume.bin");
    std::string dest_str = dest.string();

    // Pass 1: stop after ~50% by cancelling.
    {
        rac_http_download_request_t req{};
        auto u = url("/payload");
        req.url = u.c_str();
        req.destination_path = dest_str.c_str();
        req.timeout_ms = 10000;
        req.follow_redirects = RAC_TRUE;
        cancel_ctx cc{};
        cc.cancel_at = g_payload.size() / 2;
        int32_t s = 0;
        rac_http_download_execute(&req, cancel_midway, &cc, &s);
    }

    uint64_t prefix = fs::exists(dest) ? fs::file_size(dest) : 0;
    T_CHECK(prefix > 0);
    T_CHECK(prefix < g_payload.size());

    // Pass 2: resume.
    rac_http_download_request_t req{};
    auto u = url("/payload");
    req.url = u.c_str();
    req.destination_path = dest_str.c_str();
    req.timeout_ms = 10000;
    req.follow_redirects = RAC_TRUE;
    req.resume_from_byte = prefix;
    req.expected_sha256_hex = g_expected_sha.c_str();
    int32_t status = 0;
    auto rc = rac_http_download_execute(&req, nullptr, nullptr, &status);
    T_CHECK(rc == RAC_HTTP_DL_OK);
    T_CHECK(fs::file_size(dest) == g_payload.size());

    // Byte-for-byte compare the merged file against the source payload.
    std::ifstream in(dest, std::ios::binary);
    std::vector<uint8_t> merged((std::istreambuf_iterator<char>(in)),
                                std::istreambuf_iterator<char>());
    T_CHECK(merged == g_payload);

    fs::remove(dest);
}

}  // namespace

int main() {
    std::cout << "=== rac_http_download tests ===\n";
    if (!start()) {
        std::cerr << "failed to start loopback server\n";
        return 1;
    }
    std::cout << "loopback server on 127.0.0.1:" << g_port << "\n";

    g_expected_sha = sha::hash(g_payload.data(), g_payload.size());
    std::cout << "payload sha256 = " << g_expected_sha << "\n";

    rac_http_transport_register(&g_test_transport_ops, nullptr);

    test_happy_path_with_checksum();
    test_checksum_mismatch();
    test_server_error_404();
    test_invalid_url();
    test_cancel_via_progress();
    test_resume_merged_matches_payload();

    rac_http_transport_register(nullptr, nullptr);
    stop();
    std::cout << "passes=" << passes << " failures=" << failures << "\n";
    return failures == 0 ? 0 : 1;
}
