/**
 * @file rac_http_download.cpp
 * @brief Implementation of `rac_http_download_execute` — native
 * download runner that replaces Kotlin's HttpURLConnection loop.
 *
 * v2 close-out Phase H. See `rac_http_download.h` for the contract;
 * libcurl owns the native transport implementation.
 *
 * The runner:
 *   1. Opens the destination file (append when resuming, truncate
 *      otherwise; creates parent directories as needed).
 *   2. Streams bytes through `rac_http_request_stream` /
 *      `rac_http_request_resume`, flushing to disk in the chunk
 *      callback. Throttles progress reports to at most one per
 *      100 ms to avoid flooding the JNI layer.
 *   3. Runs SHA-256 verification (embedded implementation below)
 *      when `req->expected_sha256_hex` is non-NULL. The hash is
 *      computed inline on the wire to avoid a second pass over the
 *      file.
 *   4. Maps libcurl / file-system errors to the
 *      `RAC_HTTP_DL_*` codes, which mirror the Kotlin
 *      `DownloadError` enum byte-for-byte.
 */

#include "rac/infrastructure/http/rac_http_download.h"

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace fs = std::filesystem;

namespace {

constexpr const char* kTag = "rac_http_download";

// =============================================================================
// Embedded SHA-256 — public-domain reference implementation
// (RFC 6234). Small enough (<150 LOC) that it's not worth a separate
// translation unit, and keeps commons from pulling in OpenSSL just to
// hash a file.
// =============================================================================

struct sha256_ctx {
    uint32_t state[8];
    uint64_t bitcount;
    uint8_t buffer[64];
};

const uint32_t kSha256K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

inline uint32_t rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

void sha256_transform(sha256_ctx* ctx, const uint8_t* data) {
    uint32_t w[64];
    for (int i = 0; i < 16; ++i) {
        w[i] = (uint32_t(data[i * 4]) << 24) | (uint32_t(data[i * 4 + 1]) << 16) |
               (uint32_t(data[i * 4 + 2]) << 8) | (uint32_t(data[i * 4 + 3]));
    }
    for (int i = 16; i < 64; ++i) {
        uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2], d = ctx->state[3];
    uint32_t e = ctx->state[4], f = ctx->state[5], g = ctx->state[6], h = ctx->state[7];
    for (int i = 0; i < 64; ++i) {
        uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + kSha256K[i] + w[i];
        uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + mj;
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }
    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

void sha256_init(sha256_ctx* ctx) {
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
    ctx->bitcount = 0;
}

void sha256_update(sha256_ctx* ctx, const uint8_t* data, size_t len) {
    size_t buf_fill = (ctx->bitcount / 8) % 64;
    ctx->bitcount += uint64_t(len) * 8;
    size_t first = std::min(len, 64 - buf_fill);
    std::memcpy(ctx->buffer + buf_fill, data, first);
    if (buf_fill + first == 64) {
        sha256_transform(ctx, ctx->buffer);
        data += first;
        len -= first;
        while (len >= 64) {
            sha256_transform(ctx, data);
            data += 64;
            len -= 64;
        }
        std::memcpy(ctx->buffer, data, len);
    }
}

void sha256_final(sha256_ctx* ctx, uint8_t out[32]) {
    size_t buf_fill = (ctx->bitcount / 8) % 64;
    ctx->buffer[buf_fill++] = 0x80;
    if (buf_fill > 56) {
        std::memset(ctx->buffer + buf_fill, 0, 64 - buf_fill);
        sha256_transform(ctx, ctx->buffer);
        buf_fill = 0;
    }
    std::memset(ctx->buffer + buf_fill, 0, 56 - buf_fill);
    uint64_t bc = ctx->bitcount;
    for (int i = 7; i >= 0; --i) {
        ctx->buffer[56 + i] = uint8_t(bc & 0xff);
        bc >>= 8;
    }
    sha256_transform(ctx, ctx->buffer);
    for (int i = 0; i < 8; ++i) {
        out[i * 4] = uint8_t(ctx->state[i] >> 24);
        out[i * 4 + 1] = uint8_t(ctx->state[i] >> 16);
        out[i * 4 + 2] = uint8_t(ctx->state[i] >> 8);
        out[i * 4 + 3] = uint8_t(ctx->state[i]);
    }
}

std::string bytes_to_hex(const uint8_t* bytes, size_t n) {
    static const char kHex[] = "0123456789abcdef";
    std::string s;
    s.resize(n * 2);
    for (size_t i = 0; i < n; ++i) {
        s[i * 2] = kHex[(bytes[i] >> 4) & 0xf];
        s[i * 2 + 1] = kHex[bytes[i] & 0xf];
    }
    return s;
}

bool iequals(const std::string& a, const std::string& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        char ca = a[i], cb = b[i];
        if (ca >= 'A' && ca <= 'Z') ca = static_cast<char>(ca + 32);
        if (cb >= 'A' && cb <= 'Z') cb = static_cast<char>(cb + 32);
        if (ca != cb) return false;
    }
    return true;
}

// =============================================================================
// Chunk-callback context.
// =============================================================================

struct dl_ctx {
    std::ofstream* out_file;
    sha256_ctx* hasher;     // null when not hashing
    bool hashing;           // convenience
    uint64_t bytes_written;
    uint64_t resume_prefix;

    rac_http_download_progress_fn progress_cb;
    void* progress_user_data;

    bool cancelled;
    bool io_error;
};

// Fires on every libcurl chunk. No time-based throttling — the
// callback is a few hundred ns per call and cancellation has to be
// observable mid-stream even when a transfer completes in <100 ms
// (e.g. loopback). Callers who care about UI-update frequency throttle
// on their side (see CppBridgeDownload.kt's listener).
rac_bool_t on_chunk(const uint8_t* chunk, size_t chunk_len, uint64_t /*total_written*/,
                    uint64_t content_length, void* user) {
    auto* ctx = static_cast<dl_ctx*>(user);

    ctx->out_file->write(reinterpret_cast<const char*>(chunk),
                         static_cast<std::streamsize>(chunk_len));
    if (!ctx->out_file->good()) {
        ctx->io_error = true;
        return RAC_FALSE;  // cancel → stream returns RAC_ERROR_CANCELLED
    }
    ctx->bytes_written += chunk_len;
    if (ctx->hashing) {
        sha256_update(ctx->hasher, chunk, chunk_len);
    }

    if (ctx->progress_cb) {
        uint64_t total = content_length > 0 ? (ctx->resume_prefix + content_length) : 0;
        uint64_t written_total = ctx->resume_prefix + ctx->bytes_written;
        rac_bool_t keep = ctx->progress_cb(written_total, total, ctx->progress_user_data);
        if (keep == RAC_FALSE) {
            ctx->cancelled = true;
            return RAC_FALSE;
        }
    }
    return RAC_TRUE;
}

// =============================================================================
// Error mapping.
// =============================================================================

rac_http_download_status_t map_rac_error(rac_result_t rc, int32_t http_status) {
    if (rc == RAC_SUCCESS) {
        if (http_status >= 400 && http_status < 600) return RAC_HTTP_DL_SERVER_ERROR;
        return RAC_HTTP_DL_OK;
    }
    if (rc == RAC_ERROR_INVALID_ARGUMENT) return RAC_HTTP_DL_INVALID_URL;
    if (rc == RAC_ERROR_TIMEOUT) return RAC_HTTP_DL_TIMEOUT;
    if (rc == RAC_ERROR_CANCELLED) return RAC_HTTP_DL_CANCELLED;
    if (rc == RAC_ERROR_NETWORK_ERROR) return RAC_HTTP_DL_NETWORK_ERROR;
    return RAC_HTTP_DL_UNKNOWN;
}

}  // namespace

extern "C" rac_http_download_status_t rac_http_download_execute(
    const rac_http_download_request_t* req, rac_http_download_progress_fn progress_cb,
    void* progress_user_data, int32_t* out_http_status) {

    if (out_http_status) *out_http_status = 0;

    if (!req || !req->url || !req->destination_path) {
        return RAC_HTTP_DL_INVALID_URL;
    }

    // ---- Ensure destination directory exists -----------------------
    std::error_code ec;
    fs::path dest(req->destination_path);
    if (dest.has_parent_path()) {
        fs::create_directories(dest.parent_path(), ec);
        if (ec) {
            RAC_LOG_ERROR(kTag, "mkdir failed: %s", ec.message().c_str());
            return RAC_HTTP_DL_FILE_ERROR;
        }
    }

    // ---- Open destination file --------------------------------------
    std::ios::openmode mode = std::ios::binary | std::ios::out;
    if (req->resume_from_byte > 0) {
        mode |= std::ios::app;
    } else {
        mode |= std::ios::trunc;
    }
    std::ofstream out(dest, mode);
    if (!out.is_open()) {
        RAC_LOG_ERROR(kTag, "cannot open %s for writing", req->destination_path);
        return RAC_HTTP_DL_FILE_ERROR;
    }

    // ---- Create http client ----------------------------------------
    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS) {
        return RAC_HTTP_DL_UNKNOWN;
    }

    // ---- Rehydrate resume-prefix hash if needed --------------------
    //
    // When resuming and verifying the checksum, we need to feed the
    // SHA-256 context with the bytes already on disk BEFORE streaming
    // the rest. Otherwise the final digest wouldn't cover the whole
    // file.
    sha256_ctx hasher;
    bool do_hash = (req->expected_sha256_hex && req->expected_sha256_hex[0] != '\0');
    if (do_hash) {
        sha256_init(&hasher);
        if (req->resume_from_byte > 0) {
            std::ifstream in(dest, std::ios::binary);
            if (!in.is_open()) {
                rac_http_client_destroy(client);
                return RAC_HTTP_DL_FILE_ERROR;
            }
            std::vector<uint8_t> buf(64 * 1024);
            uint64_t remaining = req->resume_from_byte;
            while (remaining > 0 && in.good()) {
                size_t chunk = static_cast<size_t>(std::min<uint64_t>(buf.size(), remaining));
                in.read(reinterpret_cast<char*>(buf.data()), static_cast<std::streamsize>(chunk));
                std::streamsize read_n = in.gcount();
                if (read_n <= 0) break;
                sha256_update(&hasher, buf.data(), static_cast<size_t>(read_n));
                remaining -= static_cast<uint64_t>(read_n);
            }
        }
    }

    // ---- Build request descriptor ----------------------------------
    rac_http_request_t http_req{};
    http_req.method = "GET";
    http_req.url = req->url;
    http_req.headers = req->headers;
    http_req.header_count = req->header_count;
    http_req.timeout_ms = req->timeout_ms;
    http_req.follow_redirects = req->follow_redirects == RAC_TRUE ? RAC_TRUE : RAC_TRUE;

    // ---- Drive the transfer ----------------------------------------
    dl_ctx ctx{};
    ctx.out_file = &out;
    ctx.hasher = do_hash ? &hasher : nullptr;
    ctx.hashing = do_hash;
    ctx.bytes_written = 0;
    ctx.resume_prefix = req->resume_from_byte;
    ctx.progress_cb = progress_cb;
    ctx.progress_user_data = progress_user_data;

    rac_http_response_t resp_meta{};
    rac_result_t rc;
    if (req->resume_from_byte > 0) {
        rc = rac_http_request_resume(client, &http_req, req->resume_from_byte, on_chunk, &ctx,
                                     &resp_meta);
    } else {
        rc = rac_http_request_stream(client, &http_req, on_chunk, &ctx, &resp_meta);
    }

    int32_t http_status = resp_meta.status;
    if (out_http_status) *out_http_status = http_status;
    rac_http_response_free(&resp_meta);
    rac_http_client_destroy(client);

    out.flush();
    out.close();

    if (ctx.io_error) {
        return RAC_HTTP_DL_FILE_ERROR;
    }
    if (ctx.cancelled) {
        return RAC_HTTP_DL_CANCELLED;
    }

    rac_http_download_status_t status = map_rac_error(rc, http_status);
    if (status != RAC_HTTP_DL_OK) {
        return status;
    }
    // Treat an HTTP 4xx/5xx on the wire as a server error even if
    // libcurl reported RAC_SUCCESS (status is still populated).
    if (http_status >= 400 && http_status < 600) {
        return RAC_HTTP_DL_SERVER_ERROR;
    }

    // ---- Checksum verification (final pass over the hasher) --------
    if (do_hash) {
        uint8_t digest[32];
        sha256_final(&hasher, digest);
        std::string actual = bytes_to_hex(digest, 32);
        if (!iequals(actual, req->expected_sha256_hex)) {
            RAC_LOG_WARNING(kTag, "checksum mismatch: expected=%s actual=%s",
                            req->expected_sha256_hex, actual.c_str());
            return RAC_HTTP_DL_CHECKSUM_FAILED;
        }
    }

    // One final progress emit at 100% so listeners always see the
    // completion frame (the throttle in `on_chunk` may have swallowed
    // the last one).
    if (progress_cb) {
        uint64_t final_bytes = ctx.resume_prefix + ctx.bytes_written;
        progress_cb(final_bytes, final_bytes, progress_user_data);
    }
    return RAC_HTTP_DL_OK;
}
