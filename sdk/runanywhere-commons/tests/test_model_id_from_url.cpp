/**
 * @file test_model_id_from_url.cpp
 * @brief Cross-SDK parity tests for rac_model_id_from_url().
 *
 * Source of truth: Swift's RunAnywhere.generateModelId(fromURL:) in
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/
 *   RunAnywhere+Storage.swift
 * (the Kotlin SDK mirrors the same algorithm via generateModelIdFromUrl()).
 *
 * Each expectation here was hand-derived from the Swift implementation and
 * must remain byte-exact with the Swift output, so every platform SDK can
 * delegate to this single C ABI instead of reimplementing the algorithm.
 *
 * Cases covered:
 *   - Simple filenames (.gguf, .onnx)
 *   - Multi-extension chains (.tar.gz, .zip.tar.bin.onnx)
 *   - Mixed case extensions (case-insensitive matching)
 *   - URLs with query strings (?token=abc)
 *   - URLs with fragments / anchors (#section)
 *   - Bare-name URLs (no slash)
 *   - Empty input
 *   - NULL inputs
 *   - Output buffer too small
 *   - Very long URL within capacity
 *   - Unknown extensions are NOT stripped
 */

#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

#define EXPECT_TRUE(_cond)                                                          \
    do {                                                                            \
        if (!(_cond)) {                                                             \
            std::fprintf(stderr, "FAIL @ %s:%d: %s\n", __FILE__, __LINE__, #_cond); \
            return 1;                                                               \
        }                                                                           \
    } while (0)

#define EXPECT_RC(_rc_expr, _expected)                                                         \
    do {                                                                                       \
        rac_result_t _rc = (_rc_expr);                                                         \
        if (_rc != (_expected)) {                                                              \
            std::fprintf(stderr, "FAIL @ %s:%d: rc=%d expected=%d\n", __FILE__, __LINE__, _rc, \
                         (_expected));                                                         \
            return 1;                                                                          \
        }                                                                                      \
    } while (0)

#define EXPECT_STREQ(_actual, _expected)                                                           \
    do {                                                                                           \
        if (std::strcmp((_actual), (_expected)) != 0) {                                            \
            std::fprintf(stderr, "FAIL @ %s:%d: got=\"%s\" expected=\"%s\"\n", __FILE__, __LINE__, \
                         (_actual), (_expected));                                                  \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

// Helper: invoke API with a 256-byte buffer, assert SUCCESS, compare result.
int expect_id(const char* url, const char* expected) {
    char out[256];
    out[0] = 'X';  // sentinel, must be overwritten
    EXPECT_RC(rac_model_id_from_url(url, out, sizeof(out)), RAC_SUCCESS);
    EXPECT_STREQ(out, expected);
    return 0;
}

// ---------------------------------------------------------------------------
// 1. Simple single-extension filenames.
// ---------------------------------------------------------------------------
int test_single_extension() {
    if (expect_id("model.gguf", "model") != 0)
        return 1;
    if (expect_id("llama-7b.gguf", "llama-7b") != 0)
        return 1;
    if (expect_id("phi3.onnx", "phi3") != 0)
        return 1;
    if (expect_id("path/to/model.bin", "model") != 0)
        return 1;
    if (expect_id("https://example.com/llama-7b.gguf", "llama-7b") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 2. Multi-extension chains collapse fully (.tar.gz, .zip.tar.bin.onnx).
// ---------------------------------------------------------------------------
int test_multi_extension_chain() {
    if (expect_id("model.tar.gz", "model") != 0)
        return 1;
    if (expect_id("https://example.com/big.tar.bz2", "big") != 0)
        return 1;
    // All known: zip, tar, bin, onnx — each strips off, leaving "file".
    if (expect_id("file.zip.tar.bin.onnx", "file") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 3. Case-insensitive extension matching (".GGUF", ".Onnx", ".TAR.GZ").
// ---------------------------------------------------------------------------
int test_case_insensitive_extensions() {
    if (expect_id("model.GGUF", "model") != 0)
        return 1;
    if (expect_id("Model.Onnx", "Model") != 0)
        return 1;
    if (expect_id("Sample.TAR.GZ", "Sample") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 4. URLs with query strings — the query must be stripped before extension
//    detection (matches Swift's URL parser).
// ---------------------------------------------------------------------------
int test_query_strings() {
    if (expect_id("https://example.com/model.gguf?token=abc", "model") != 0)
        return 1;
    if (expect_id("https://example.com/model.tar.gz?v=2&hash=xyz", "model") != 0)
        return 1;
    if (expect_id("model.bin?download=1", "model") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 5. URLs with anchors / fragments.
// ---------------------------------------------------------------------------
int test_url_fragments() {
    if (expect_id("https://example.com/model.gguf#section", "model") != 0)
        return 1;
    if (expect_id("model.onnx#part1", "model") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 6. Bare-name URLs without a slash — Swift's split-last fallback returns
//    the whole input. The same id (after extension stripping) must come back.
// ---------------------------------------------------------------------------
int test_bare_name_no_slash() {
    if (expect_id("bare-name", "bare-name") != 0)
        return 1;
    if (expect_id("bare-name.gguf", "bare-name") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 7. Unknown extensions are NOT stripped (mirrors Swift). The dotted suffix
//    is preserved as part of the id.
// ---------------------------------------------------------------------------
int test_unknown_extension_preserved() {
    if (expect_id("file.foo", "file.foo") != 0)
        return 1;
    if (expect_id("https://example.com/weights.safetensors", "weights.safetensors") != 0)
        return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// 8. Empty URL string → empty id (matches Swift's empty-string round-trip).
// ---------------------------------------------------------------------------
int test_empty_url() {
    char out[16];
    out[0] = 'X';
    EXPECT_RC(rac_model_id_from_url("", out, sizeof(out)), RAC_SUCCESS);
    EXPECT_STREQ(out, "");
    return 0;
}

// ---------------------------------------------------------------------------
// 9. NULL inputs → RAC_ERROR_NULL_POINTER without writing to the buffer.
// ---------------------------------------------------------------------------
int test_null_inputs() {
    char out[16];
    EXPECT_RC(rac_model_id_from_url(nullptr, out, sizeof(out)), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_id_from_url("model.gguf", nullptr, 16), RAC_ERROR_NULL_POINTER);
    EXPECT_RC(rac_model_id_from_url(nullptr, nullptr, 0), RAC_ERROR_NULL_POINTER);
    return 0;
}

// ---------------------------------------------------------------------------
// 10. Output buffer too small — the function must NOT silently truncate.
//     out_size = 0 is also rejected with BUFFER_TOO_SMALL (and out is NULL-
//     safe untouched in that case because we early-return).
// ---------------------------------------------------------------------------
int test_buffer_too_small() {
    // out_size == 0 → BUFFER_TOO_SMALL (regardless of out contents).
    char zero_out[1] = {'X'};
    EXPECT_RC(rac_model_id_from_url("model.gguf", zero_out, 0), RAC_ERROR_BUFFER_TOO_SMALL);

    // Derived id "llama-7b-instruct" (17 chars + NUL = 18 bytes) does not fit
    // in a 10-byte buffer; the function must refuse and leave the buffer empty.
    char tiny[10];
    std::memset(tiny, 'X', sizeof(tiny));
    EXPECT_RC(rac_model_id_from_url("llama-7b-instruct.gguf", tiny, sizeof(tiny)),
              RAC_ERROR_BUFFER_TOO_SMALL);
    EXPECT_STREQ(tiny, "");

    // Boundary: id fits exactly with NUL terminator.
    char exact[6];  // capacity 6 holds "model" + '\0'.
    EXPECT_RC(rac_model_id_from_url("model.gguf", exact, sizeof(exact)), RAC_SUCCESS);
    EXPECT_STREQ(exact, "model");

    return 0;
}

// ---------------------------------------------------------------------------
// 11. Very long URL within capacity — no truncation, all metadata stripped.
// ---------------------------------------------------------------------------
int test_very_long_url() {
    std::string long_filename(120, 'a');  // 120 'a's
    std::string url = "https://example.com/path/to/deep/nested/" + long_filename + ".tar.gz";
    char out[256];
    EXPECT_RC(rac_model_id_from_url(url.c_str(), out, sizeof(out)), RAC_SUCCESS);
    EXPECT_STREQ(out, long_filename.c_str());
    return 0;
}

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    int failures = 0;
    failures += test_single_extension();
    failures += test_multi_extension_chain();
    failures += test_case_insensitive_extensions();
    failures += test_query_strings();
    failures += test_url_fragments();
    failures += test_bare_name_no_slash();
    failures += test_unknown_extension_preserved();
    failures += test_empty_url();
    failures += test_null_inputs();
    failures += test_buffer_too_small();
    failures += test_very_long_url();

    if (failures == 0) {
        std::fprintf(stdout, "[PASS] test_model_id_from_url\n");
        return 0;
    }
    std::fprintf(stderr, "[FAIL] test_model_id_from_url (%d failure(s))\n", failures);
    return 1;
}
