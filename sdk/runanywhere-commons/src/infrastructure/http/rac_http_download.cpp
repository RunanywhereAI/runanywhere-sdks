// Diagnostic logging on Android: the SDK logger callback isn't always
// installed when this code runs, so use __android_log_print directly to
// guarantee visibility in `adb logcat -s rac_http_dl`.
#ifdef __ANDROID__
#include <android/log.h>
#endif

/**
 * @file rac_http_download.cpp
 * @brief Implementation of `rac_http_download_execute` — native
 * download runner that replaces Kotlin's HttpURLConnection loop.
 *
 * See `rac_http_download.h` for the contract;
 * platform adapters own HTTP execution.
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
 *   4. Maps transport / file-system errors to the
 *      `RAC_HTTP_DL_*` codes, which mirror the Kotlin
 *      `DownloadError` enum byte-for-byte.
 */

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/http/rac_http_download.h"

namespace fs = std::filesystem;

namespace {

constexpr const char* kTag = "rac_http_download";

// RAII guard for the C-ABI rac_http_client_t handle so the destroy fires
// regardless of which return path the runner takes. Closes the leak window
// any future early-return added between create and the success-path destroy
// would otherwise open.
struct HttpClientGuard {
    rac_http_client_t* c{nullptr};
    HttpClientGuard() = default;
    HttpClientGuard(const HttpClientGuard&) = delete;
    HttpClientGuard& operator=(const HttpClientGuard&) = delete;
    ~HttpClientGuard() {
        if (c)
            rac_http_client_destroy(c);
    }
};

// RAII guard for the .rac_resume_fallback.tmp file produced by the shift-left
// rename dance. Multiple early returns between the rename and the explicit
// remove can otherwise leave the tmp file in the caller's app dir. Call
// disarm() on the success branch once the tmp has been consumed.
struct PathRemoveGuard {
    fs::path p;
    void arm(fs::path pp) { p = std::move(pp); }
    void disarm() { p.clear(); }
    ~PathRemoveGuard() {
        if (!p.empty()) {
            std::error_code ec;
            fs::remove(p, ec);
        }
    }
};

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

inline uint32_t rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

void sha256_transform(sha256_ctx* ctx, const uint8_t* data) {
    uint32_t w[64];
    for (int i = 0; i < 16; ++i) {
        const size_t base = static_cast<size_t>(i) * 4;
        w[i] = (uint32_t(data[base]) << 24) | (uint32_t(data[base + 1]) << 16) |
               (uint32_t(data[base + 2]) << 8) | (uint32_t(data[base + 3]));
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
        const size_t base = static_cast<size_t>(i) * 4;
        out[base] = uint8_t(ctx->state[i] >> 24);
        out[base + 1] = uint8_t(ctx->state[i] >> 16);
        out[base + 2] = uint8_t(ctx->state[i] >> 8);
        out[base + 3] = uint8_t(ctx->state[i]);
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
    if (a.size() != b.size())
        return false;
    for (size_t i = 0; i < a.size(); ++i) {
        char ca = a[i], cb = b[i];
        if (ca >= 'A' && ca <= 'Z')
            ca = static_cast<char>(ca + 32);
        if (cb >= 'A' && cb <= 'Z')
            cb = static_cast<char>(cb + 32);
        if (ca != cb)
            return false;
    }
    return true;
}

// =============================================================================
// Chunk-callback context.
// =============================================================================

struct dl_ctx {
    std::ofstream* out_file;
    sha256_ctx* hasher;  // null when not hashing
    bool hashing;        // convenience
    uint64_t bytes_written;
    uint64_t resume_prefix;

    rac_http_download_progress_fn progress_cb;
    void* progress_user_data;

    bool cancelled;
    bool io_error;
};

// Treat any response body smaller than
// this threshold as "could be an error stub" — gguf / safetensors / sherpa-onnx
// WASM model payloads are all multi-MB at minimum, so a body smaller than
// `kSuspiciousResponseThreshold` arriving alongside a 4xx/5xx status (or
// alongside a content-type starting with `text/`) is structurally not a model
// payload and must NOT be allowed to overwrite a valid on-disk prefix. The
// threshold is generous so we never reject a real partial-body chunked stream
// mid-flight; the post-response check below verifies status + size + content-
// type together before deciding to roll back.
constexpr uint64_t kSuspiciousResponseThreshold = 1024;  // 1 KiB

// Fires on every adapter-delivered chunk. No time-based throttling — the
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
        if (http_status >= 400 && http_status < 600)
            return RAC_HTTP_DL_SERVER_ERROR;
        return RAC_HTTP_DL_OK;
    }
    if (rc == RAC_ERROR_INVALID_ARGUMENT)
        return RAC_HTTP_DL_INVALID_URL;
    if (rc == RAC_ERROR_TIMEOUT)
        return RAC_HTTP_DL_TIMEOUT;
    if (rc == RAC_ERROR_CANCELLED)
        return RAC_HTTP_DL_CANCELLED;
    if (rc == RAC_ERROR_NETWORK_ERROR)
        return RAC_HTTP_DL_NETWORK_ERROR;
    return RAC_HTTP_DL_UNKNOWN;
}

}  // namespace

extern "C" rac_http_download_status_t
rac_http_download_execute(const rac_http_download_request_t* req,
                          rac_http_download_progress_fn progress_cb, void* progress_user_data,
                          int32_t* out_http_status) {
    if (out_http_status)
        *out_http_status = 0;

    if (!req || !req->url || !req->destination_path) {
#ifdef __ANDROID__
        __android_log_print(
            ANDROID_LOG_ERROR, "rac_http_dl", "INVALID_URL early-return: req=%p url=%p dest=%p",
            static_cast<const void*>(req), req ? static_cast<const void*>(req->url) : nullptr,
            req ? static_cast<const void*>(req->destination_path) : nullptr);
#endif
        return RAC_HTTP_DL_INVALID_URL;
    }
    // Privacy: do not emit the full URL or destination path to logcat.
    // Model download URLs frequently carry signed-URL query parameters or
    // bearer tokens, and destination paths reveal the app's filesystem
    // layout and model ids. logcat is collected by QA tooling, crash
    // reporters, MDM agents, and adb sessions, so unconditional INFO
    // diagnostics are not appropriate here. Errors and progress are
    // reported via the SDK logger / return codes below.

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

    if (req->resume_from_byte > 0) {
        if (!fs::exists(dest, ec) || ec) {
            RAC_LOG_ERROR(kTag, "resume requested but destination does not exist");
            return RAC_HTTP_DL_FILE_ERROR;
        }
        uint64_t existing_size = static_cast<uint64_t>(fs::file_size(dest, ec));
        if (ec || existing_size != req->resume_from_byte) {
            RAC_LOG_ERROR(kTag, "resume offset mismatch: requested=%llu existing=%llu",
                          static_cast<unsigned long long>(req->resume_from_byte),
                          static_cast<unsigned long long>(ec ? 0 : existing_size));
            return RAC_HTTP_DL_FILE_ERROR;
        }
    }

    // When a fresh download was requested (`resume_from_byte == 0`)
    // but a non-trivial partial file already lives at the destination
    // (e.g. from a previous attempt that left a real gguf prefix on disk),
    // truncating-then-replaying erases the only good copy of the prefix.
    // If the next attempt then trips the shift-left fallback or a 416
    // error stub, the file ends up as a 49-byte HTML page.
    //
    // Defensive policy:
    //   1. If the on-disk file starts with an HTML/XML magic byte (`<`)
    //      OR is small enough to be an error-page stub (<= 1 KiB), treat
    //      it as garbage and truncate as before.
    //   2. Otherwise, promote the fresh download to a resume from the
    //      current file size so the existing bytes are preserved and only
    //      the tail is re-fetched.
    //
    // This is intentionally a heuristic — without a server etag/If-Match
    // we cannot prove the prefix matches the upstream payload. The shift-
    // left fallback in the success path covers the case where the server
    // re-serves the full body, so the worst-case outcome is one extra
    // shift-left pass instead of permanent corruption.
    uint64_t effective_resume_from = req->resume_from_byte;
    if (req->resume_from_byte == 0 && fs::exists(dest, ec) && !ec) {
        uint64_t existing_size = static_cast<uint64_t>(fs::file_size(dest, ec));
        if (!ec && existing_size > 0) {
            bool looks_like_stub = false;
            // Sniff the first 16 bytes. HTML/XML error pages start with '<'
            // (whitespace tolerated). Tiny files (<= 1 KiB) are presumed to
            // be transport-layer error stubs since gguf / safetensors /
            // sherpa-onnx-wasm payloads are all multi-MB at minimum.
            constexpr uint64_t kStubMaxBytes = 1024;
            if (existing_size <= kStubMaxBytes) {
                looks_like_stub = true;
            } else {
                std::ifstream sniff(dest, std::ios::binary);
                if (sniff.is_open()) {
                    char sniff_buf[16] = {0};
                    sniff.read(sniff_buf, sizeof(sniff_buf));
                    std::streamsize sniff_n = sniff.gcount();
                    for (std::streamsize i = 0; i < sniff_n; ++i) {
                        char c = sniff_buf[i];
                        if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
                            continue;
                        if (c == '<') {
                            looks_like_stub = true;
                        }
                        break;
                    }
                }
            }
            if (!looks_like_stub) {
                RAC_LOG_WARNING(
                    kTag,
                    "fresh download but %llu bytes already on disk; promoting to resume to "
                    "preserve prior partial",
                    static_cast<unsigned long long>(existing_size));
                effective_resume_from = existing_size;
            }
        }
    }

    // ---- Open destination file --------------------------------------
    std::ios::openmode mode = std::ios::binary | std::ios::out;
    if (effective_resume_from > 0) {
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
    HttpClientGuard cg;
    if (rac_http_client_create(&cg.c) != RAC_SUCCESS) {
        return RAC_HTTP_DL_UNKNOWN;
    }

    // ---- Rehydrate resume-prefix hash if needed --------------------
    //
    // When resuming and verifying the checksum, we need to feed the
    // SHA-256 context with the bytes already on disk BEFORE streaming
    // the rest. Otherwise the final digest wouldn't cover the whole
    // file.
    sha256_ctx hasher;
    bool do_hash = (req->expected_sha256_hex != nullptr && req->expected_sha256_hex[0] != '\0');
    if (do_hash) {
        sha256_init(&hasher);
        if (effective_resume_from > 0) {
            std::ifstream in(dest, std::ios::binary);
            if (!in.is_open()) {
                return RAC_HTTP_DL_FILE_ERROR;
            }
            std::vector<uint8_t> buf(static_cast<size_t>(64) * 1024);
            uint64_t remaining = effective_resume_from;
            while (remaining > 0 && in.good()) {
                size_t chunk = static_cast<size_t>(std::min<uint64_t>(buf.size(), remaining));
                in.read(reinterpret_cast<char*>(buf.data()), static_cast<std::streamsize>(chunk));
                std::streamsize read_n = in.gcount();
                if (read_n <= 0)
                    break;
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
    http_req.follow_redirects = RAC_TRUE;

    // ---- Drive the transfer ----------------------------------------
    dl_ctx ctx{};
    ctx.out_file = &out;
    ctx.hasher = do_hash ? &hasher : nullptr;
    ctx.hashing = do_hash;
    ctx.bytes_written = 0;
    ctx.resume_prefix = effective_resume_from;
    ctx.progress_cb = progress_cb;
    ctx.progress_user_data = progress_user_data;

    rac_http_response_t resp_meta{};
    rac_result_t rc;
    if (effective_resume_from > 0) {
        rc = rac_http_request_resume(cg.c, &http_req, effective_resume_from, on_chunk, &ctx,
                                     &resp_meta);
    } else {
        rc = rac_http_request_stream(cg.c, &http_req, on_chunk, &ctx, &resp_meta);
    }

    int32_t http_status = resp_meta.status;
    if (out_http_status)
        *out_http_status = http_status;
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "rac_http_dl",
                        "request_stream returned: rc=%d http_status=%d bytes_written=%llu",
                        static_cast<int>(rc), http_status,
                        static_cast<unsigned long long>(ctx.bytes_written));
#endif
    // Snapshot the canonical X-RAC-Range-Honored header before freeing the
    // response so the resume-fallback check below can still observe it.
    // Swift URLSession and Kotlin OkHttp emit `X-RAC-Range-Honored: false`
    // whenever a resume request received 200 — see
    // sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift:496-505
    // and sdk/runanywhere-kotlin/.../OkHttpHttpTransport.kt:360-366.
    bool range_honored_signal_header = false;
    if (effective_resume_from > 0 && rc == RAC_SUCCESS && resp_meta.headers != nullptr) {
        for (size_t i = 0; i < resp_meta.header_count; ++i) {
            const auto& kv = resp_meta.headers[i];
            if (kv.name == nullptr || kv.value == nullptr) {
                continue;
            }
            if (iequals(kv.name, "X-RAC-Range-Honored") && iequals(kv.value, "false")) {
                range_honored_signal_header = true;
                break;
            }
        }
    }

    // Observe the response Content-Type
    // so the strict 416/error-body rollback below can distinguish "text/html
    // CDN error stub" from "application/octet-stream truncated payload". We
    // also fold "no content-type" into the suspicious-body class — a 4xx with
    // a missing content-type and a tiny body is overwhelmingly an error stub
    // (S3 / Cloudflare / nginx all emit text-style stubs even when they fail
    // to set Content-Type).
    bool response_content_type_is_textlike = false;
    bool response_content_type_present = false;
    if (rc == RAC_SUCCESS && resp_meta.headers != nullptr) {
        for (size_t i = 0; i < resp_meta.header_count; ++i) {
            const auto& kv = resp_meta.headers[i];
            if (kv.name == nullptr || kv.value == nullptr) {
                continue;
            }
            if (iequals(kv.name, "Content-Type")) {
                response_content_type_present = true;
                std::string value(kv.value);
                // Case-fold the prefix for the startswith check.
                for (auto& c : value) {
                    if (c >= 'A' && c <= 'Z')
                        c = static_cast<char>(c + 32);
                }
                if (value.rfind("text/", 0) == 0) {
                    response_content_type_is_textlike = true;
                }
                break;
            }
        }
    }
    // Snapshot the Content-Range total ("bytes */<total>" on a 416) before
    // freeing the response. When a resume requests a range at/after EOF the
    // server reports the resource's true length here. It is the authoritative
    // size to validate an already-complete file against — the caller's
    // expected byte count may only be a catalog estimate, and many GGUF
    // mirrors omit a checksum entirely.
    int64_t content_range_total = -1;
    if (rc == RAC_SUCCESS && resp_meta.headers != nullptr) {
        for (size_t i = 0; i < resp_meta.header_count; ++i) {
            const auto& kv = resp_meta.headers[i];
            if (kv.name == nullptr || kv.value == nullptr) {
                continue;
            }
            if (iequals(kv.name, "Content-Range")) {
                std::string value(kv.value);
                size_t slash = value.rfind('/');
                if (slash != std::string::npos && slash + 1 < value.size()) {
                    std::string total = value.substr(slash + 1);
                    size_t b = total.find_first_not_of(" \t");
                    size_t e = total.find_last_not_of(" \t");
                    if (b != std::string::npos) {
                        total = total.substr(b, e - b + 1);
                        if (total != "*" &&
                            total.find_first_not_of("0123456789") == std::string::npos) {
                            content_range_total = std::strtoll(total.c_str(), nullptr, 10);
                        }
                    }
                }
                break;
            }
        }
    }
    rac_http_response_free(&resp_meta);

    out.flush();
    out.close();

    if (ctx.io_error) {
        return RAC_HTTP_DL_FILE_ERROR;
    }
    if (ctx.cancelled) {
        return RAC_HTTP_DL_CANCELLED;
    }

    // ---- strict body validation -----
    //
    // An earlier change (commit d0a5885b6) gated the shift-left fallback on
    // status == 200 || (206 + Range-Honored:false), which prevents HTTP 416
    // from chopping the file down to the error stub size. But the body itself
    // was still APPENDED (resume) or WRITTEN (fresh) to the destination by the
    // chunk callback before the runner observed the status. In the resume
    // path this leaves `[386 MB valid prefix][49 B HTML stub]` on disk; the
    // 49 B suffix corrupts the file even though the gross size only changed
    // by a tiny fraction. Multiple platform lanes saw the 49 B
    // HTML overwrite the gguf on the post-relaunch retry.
    //
    // Policy (strict gate, scoped to HTTP 416 per task spec):
    //   - status is HTTP 416 Range Not Satisfiable (the canonical CDN response
    //     to a resume offset past the resource end)
    //   - AND body is suspiciously small (< kSuspiciousResponseThreshold)
    //   - AND content-type starts with `text/` OR is absent
    //   → roll back the appended/written bytes (truncate the destination back
    //     to effective_resume_from on resume; remove the file on fresh) and
    //     return RAC_HTTP_DL_NETWORK_ERROR so callers DON'T treat the on-disk
    //     state as part of a successful payload.
    //
    // We scope this strict gate to HTTP 416 specifically (not all 4xx/5xx)
    // so that the existing RAC_HTTP_DL_SERVER_ERROR semantics for non-Range
    // error statuses (404 / 500 / etc.) remain unchanged. Other 4xx/5xx
    // statuses with prior on-disk prefix are still partially defended by:
    //   1. The shift-left gate (which already excludes them via its status
    //      eligibility check) — no truncation of the valid prefix happens.
    //   2. The download orchestrator's post-finalize size guard — refuses to
    //      register `downloaded:true` for any file that ends up < 80% of
    //      expected. The 49-byte HTML body from a 404 attached to a fresh
    //      download would trip this guard during the next finalize.
    const bool status_is_416 = http_status == 416;
    const bool body_is_tiny = ctx.bytes_written < kSuspiciousResponseThreshold;
    const bool body_is_textlike_or_unknown =
        response_content_type_is_textlike || !response_content_type_present;
    if (rc == RAC_SUCCESS && status_is_416 && body_is_tiny && body_is_textlike_or_unknown) {
        RAC_LOG_WARNING(
            kTag,
            "HTTP 416 returned %llu-byte %s body; rejecting write and rolling back to %llu bytes",
            static_cast<unsigned long long>(ctx.bytes_written),
            response_content_type_is_textlike ? "text/* (error-stub-shaped)"
                                              : "unknown-content-type",
            static_cast<unsigned long long>(effective_resume_from));
        if (effective_resume_from > 0) {
            // Resume path: truncate the file back to the pre-request size so
            // the valid prefix is preserved verbatim and a follow-up resume
            // (from a fresh URL or after the server recovers) can pick up
            // where it left off.
            std::error_code trunc_ec;
            fs::resize_file(dest, static_cast<uintmax_t>(effective_resume_from), trunc_ec);
            if (trunc_ec) {
                RAC_LOG_ERROR(kTag,
                              "rollback truncate failed: %s (file may have %llu garbage bytes "
                              "appended past offset %llu)",
                              trunc_ec.message().c_str(),
                              static_cast<unsigned long long>(ctx.bytes_written),
                              static_cast<unsigned long long>(effective_resume_from));
                return RAC_HTTP_DL_FILE_ERROR;
            }
        } else {
            // Fresh-download path: the file was opened in trunc mode and
            // overwritten with the error stub. Remove it entirely so the
            // caller observes a clean "no partial" state and can retry from
            // scratch without the stub masquerading as a recoverable prefix.
            std::error_code rm_ec;
            fs::remove(dest, rm_ec);
            // Best-effort: even if remove fails the file is just an HTML
            // stub that the next iteration's promote-to-resume sniff will
            // catch via the `looks_like_stub` heuristic.
            (void)rm_ec;
        }

        // A 416 on ANY resume (promoted from a fresh request that found a
        // complete file, OR an explicit resume_from_byte) means the server has
        // nothing at/after our offset — the on-disk file already holds the
        // entire resource. A genuine partial would have received a 206 with the
        // remaining bytes, never a 416, so resuming from our own EOF and being
        // told "range unsatisfiable" is a positive completeness signal. Report
        // success (after verifying the checksum when provided) instead of a
        // retryable network error, so an already-downloaded model whose size
        // was only estimated — or has no checksum — isn't stuck re-failing.
        const bool resumed_to_eof = (effective_resume_from > 0);
        if (resumed_to_eof) {
            // If the server reported its true length and the on-disk file
            // overshot it (trailing garbage from an earlier interrupted write),
            // trim to the exact size before trusting or hashing the file.
            if (content_range_total > 0 &&
                static_cast<int64_t>(effective_resume_from) > content_range_total) {
                std::error_code trim_ec;
                fs::resize_file(dest, static_cast<uintmax_t>(content_range_total), trim_ec);
                if (trim_ec) {
                    RAC_LOG_ERROR(kTag, "trim-to-content-range-total failed: %s",
                                  trim_ec.message().c_str());
                    return RAC_HTTP_DL_FILE_ERROR;
                }
                effective_resume_from = static_cast<uint64_t>(content_range_total);
            }
            if (do_hash) {
                // The streamed hasher consumed the rolled-back stub bytes, so
                // recompute the digest over the on-disk file before trusting it.
                sha256_init(&hasher);
                std::ifstream rehash(dest, std::ios::binary);
                if (!rehash.is_open()) {
                    return RAC_HTTP_DL_FILE_ERROR;
                }
                std::vector<uint8_t> hbuf(static_cast<size_t>(64) * 1024);
                while (rehash.good()) {
                    rehash.read(reinterpret_cast<char*>(hbuf.data()),
                                static_cast<std::streamsize>(hbuf.size()));
                    std::streamsize n = rehash.gcount();
                    if (n <= 0)
                        break;
                    sha256_update(&hasher, hbuf.data(), static_cast<size_t>(n));
                }
                uint8_t digest[32];
                sha256_final(&hasher, digest);
                std::string actual = bytes_to_hex(digest, 32);
                if (!iequals(actual, req->expected_sha256_hex)) {
                    RAC_LOG_WARNING(kTag,
                                    "HTTP 416 on already-on-disk file but checksum mismatch: "
                                    "expected=%s actual=%s",
                                    req->expected_sha256_hex, actual.c_str());
                    return RAC_HTTP_DL_CHECKSUM_FAILED;
                }
            }
            RAC_LOG_WARNING(kTag,
                            "HTTP 416 on resume — destination already complete (%llu bytes)",
                            static_cast<unsigned long long>(effective_resume_from));
            if (progress_cb) {
                progress_cb(effective_resume_from, effective_resume_from, progress_user_data);
            }
            return RAC_HTTP_DL_OK;
        }
        return RAC_HTTP_DL_NETWORK_ERROR;
    }

    // ---- Resume fallback: server ignored Range and replayed full body --
    //
    // When the request was a resume (`effective_resume_from > 0`) but the
    // server responded with HTTP 200 instead of 206, the body we just
    // appended is the FULL payload — not the [resume_prefix : end] tail
    // we asked for. The file on disk is now [original prefix][full payload];
    // the prefix is no longer valid. Shift left by `effective_resume_from`
    // so the file ends up as the full payload only. The operation succeeds
    // deterministically instead of silently producing a corrupted file or
    // surfacing a misleading CHECKSUM_FAILED. Mirrors the behavior callers
    // expect from a CDN that does not honor Range (e.g. some S3 / GCS
    // configurations and proxies that strip the header).
    //
    // The previous gate (`http_status == 200
    // || range_honored_signal_header`) ALSO fired for HTTP 416 + Range-
    // not-honored header, which is the canonical CDN response to a resume
    // request whose offset is past the resource end. The body for 416 is
    // typically a few dozen bytes of HTML error page (Cloudflare returns
    // exactly 49 bytes for some configs), and shift-left chops the file
    // down to that tiny body — destroying the existing partial. Two
    // defenses, both required:
    //   1. Status gate: only HTTP 200 (full-body replay) OR the rare
    //      HTTP 206 + Range-not-honored header (transport-layer signal
    //      that a CDN replayed the full payload through a 206 wrapper).
    //      All 4xx/5xx statuses — including 416 — are explicitly excluded.
    //   2. Body-size gate: `ctx.bytes_written >= effective_resume_from`.
    //      The shift would discard `effective_resume_from` bytes from the
    //      front of the new body. If the body is shorter than the prefix
    //      we'd throw away, the body is structurally not a full payload
    //      and the shift can only cause data loss.
    const bool shift_left_status_eligible =
        http_status == 200 || (http_status == 206 && range_honored_signal_header);
    const bool shift_left_body_sufficient = ctx.bytes_written >= effective_resume_from;
    if (effective_resume_from > 0 && rc == RAC_SUCCESS && shift_left_status_eligible &&
        shift_left_body_sufficient) {
        RAC_LOG_WARNING(kTag,
                        "resume request returned HTTP 200 (Range not honored); shifting "
                        "destination left by %llu bytes to recover the full payload",
                        static_cast<unsigned long long>(effective_resume_from));
        fs::path tmp_path(std::string(req->destination_path) + ".rac_resume_fallback.tmp");
        std::error_code ren_ec;
        fs::rename(dest, tmp_path, ren_ec);
        if (ren_ec) {
            return RAC_HTTP_DL_FILE_ERROR;
        }
        PathRemoveGuard tmpg;
        tmpg.arm(tmp_path);
        {
            std::ifstream src(tmp_path, std::ios::binary);
            std::ofstream dst(dest, std::ios::binary | std::ios::trunc);
            if (!src.is_open() || !dst.is_open()) {
                // Try to put the original file back; the guard will clean up
                // tmp_path either way (if restore succeeded the remove is a
                // harmless no-op).
                std::error_code restore_ec;
                fs::rename(tmp_path, dest, restore_ec);
                if (!restore_ec) {
                    tmpg.disarm();
                }
                return RAC_HTTP_DL_FILE_ERROR;
            }
            src.seekg(static_cast<std::streamoff>(effective_resume_from));
            std::vector<char> shift_buf(static_cast<size_t>(64) * 1024);
            while (src.good()) {
                src.read(shift_buf.data(), static_cast<std::streamsize>(shift_buf.size()));
                std::streamsize n = src.gcount();
                if (n <= 0)
                    break;
                dst.write(shift_buf.data(), n);
                if (!dst.good()) {
                    return RAC_HTTP_DL_FILE_ERROR;
                }
            }
        }

        // Re-hash from the corrected file. The previously rehydrated hasher
        // covered the now-discarded prefix plus a body that turned out to be
        // the full payload (not the resume tail), so the running digest is
        // wrong; recompute it from scratch over the on-disk bytes.
        if (do_hash) {
            sha256_init(&hasher);
            std::ifstream rehash(dest, std::ios::binary);
            std::vector<uint8_t> hbuf(static_cast<size_t>(64) * 1024);
            while (rehash.good()) {
                rehash.read(reinterpret_cast<char*>(hbuf.data()),
                            static_cast<std::streamsize>(hbuf.size()));
                std::streamsize n = rehash.gcount();
                if (n <= 0)
                    break;
                sha256_update(&hasher, hbuf.data(), static_cast<size_t>(n));
            }
        }

        // Treat the corrected payload as a successful full download for the
        // remaining status / checksum / progress emission paths below.
        ctx.resume_prefix = 0;
    }

    rac_http_download_status_t status = map_rac_error(rc, http_status);
    if (status != RAC_HTTP_DL_OK) {
        return status;
    }
    // Treat an HTTP 4xx/5xx on the wire as a server error even when
    // the transport reports RAC_SUCCESS (status is still populated).
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
