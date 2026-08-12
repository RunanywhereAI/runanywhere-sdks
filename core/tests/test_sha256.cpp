/**
 * @file test_sha256.cpp
 * @brief Known-answer tests for the shared SHA-256 foundation util.
 */

#include <cstdio>
#include <string>

#include "rac/foundation/rac_sha256.h"

using runanywhere::sha256_ctx;
using runanywhere::sha256_final;
using runanywhere::sha256_hex;
using runanywhere::sha256_init;
using runanywhere::sha256_update;
using runanywhere::bytes_to_hex;

namespace {
int g_checks = 0;
int g_failures = 0;

#define CHECK(cond, label)                                                           \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (cond) {                                                                  \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                           \
    } while (0)
}  // namespace

int main() {
    std::fprintf(stdout, "=== SHA-256 KAT ===\n");

    // RFC 6234 / NIST known-answer vectors.
    CHECK(sha256_hex("", 0) ==
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "empty string");
    CHECK(sha256_hex(std::string("abc")) ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "\"abc\"");
    CHECK(sha256_hex(std::string(
              "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) ==
              "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
          "56-byte message");

    // Streaming must match one-shot (spanning the 64-byte block boundary).
    {
        const std::string big(1000, 'a');
        sha256_ctx ctx;
        sha256_init(&ctx);
        for (char c : big)
            sha256_update(&ctx, reinterpret_cast<const uint8_t*>(&c), 1);
        uint8_t digest[32];
        sha256_final(&ctx, digest);
        CHECK(bytes_to_hex(digest, 32) == sha256_hex(big), "streaming == one-shot");
    }

    std::fprintf(stdout, "=== %d checks, %d failures ===\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
