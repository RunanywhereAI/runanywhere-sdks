/**
 * @file rac_sha256.cpp
 * @brief Shared SHA-256 (RFC 6234) implementation. Public-domain reference.
 */

#include "rac/foundation/rac_sha256.h"

#include <algorithm>
#include <cstring>

namespace runanywhere {

namespace {

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

}  // namespace

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

std::string sha256_hex(const void* data, size_t len) {
    sha256_ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, static_cast<const uint8_t*>(data), len);
    uint8_t digest[32];
    sha256_final(&ctx, digest);
    return bytes_to_hex(digest, 32);
}

std::string sha256_hex(const std::string& data) {
    return sha256_hex(data.data(), data.size());
}

}  // namespace runanywhere
