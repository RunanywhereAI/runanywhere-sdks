/**
 * @file rac_sha256.h
 * @brief Shared SHA-256 (RFC 6234) — the single implementation in commons.
 *
 * Public-domain reference implementation. Used by download integrity checking
 * and by the RAG content-addressed store (dedup by input hash). Do not add a
 * second SHA-256 implementation elsewhere.
 *
 * Streaming API (sha256_init/update/final) for large/streamed inputs; the
 * sha256_hex() one-shot for in-memory buffers.
 */

#ifndef RAC_FOUNDATION_SHA256_H
#define RAC_FOUNDATION_SHA256_H

#include <cstddef>
#include <cstdint>
#include <string>

namespace runanywhere {

struct sha256_ctx {
    uint32_t state[8];
    uint64_t bitcount;
    uint8_t buffer[64];
};

/** Initialize a hashing context. */
void sha256_init(sha256_ctx* ctx);

/** Feed `len` bytes into the hash. May be called repeatedly. */
void sha256_update(sha256_ctx* ctx, const uint8_t* data, size_t len);

/** Finalize into a 32-byte digest. `ctx` must not be reused after this. */
void sha256_final(sha256_ctx* ctx, uint8_t out[32]);

/** Lowercase hex encoding of `n` raw bytes. */
std::string bytes_to_hex(const uint8_t* bytes, size_t n);

/** One-shot: lowercase hex SHA-256 of an in-memory buffer. */
std::string sha256_hex(const void* data, size_t len);

/** One-shot: lowercase hex SHA-256 of a string's bytes. */
std::string sha256_hex(const std::string& data);

}  // namespace runanywhere

#endif  // RAC_FOUNDATION_SHA256_H
