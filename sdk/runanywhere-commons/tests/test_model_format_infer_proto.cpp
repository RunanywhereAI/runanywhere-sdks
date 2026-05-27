/**
 * @file test_model_format_infer_proto.cpp
 * @brief Tests for the URL → ModelFormat / ArtifactType proto-byte C ABI.
 *
 * Exercises rac_model_format_from_url_proto and
 * rac_artifact_infer_from_url_proto. These are the commons-side
 * replacements for the Dart withInferredArtifact / protoModelFormatFromPath
 * and Kotlin detectFormatFromUrl / inferArtifactFields helpers (Wave D-3).
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

std::vector<uint8_t> serialize_format_request(const std::string& url) {
    runanywhere::v1::ModelFormatFromUrlRequest req;
    req.set_url(url);
    std::string bytes;
    if (!req.SerializeToString(&bytes)) {
        return {};
    }
    return {bytes.begin(), bytes.end()};
}

std::vector<uint8_t> serialize_artifact_request(const std::string& url,
                                                const std::string& model_id = "") {
    runanywhere::v1::ArtifactInferFromUrlRequest req;
    req.set_url(url);
    if (!model_id.empty()) {
        req.set_model_id(model_id);
    }
    std::string bytes;
    if (!req.SerializeToString(&bytes)) {
        return {};
    }
    return {bytes.begin(), bytes.end()};
}

bool parse_format_result(const rac_proto_buffer_t& buffer,
                         runanywhere::v1::ModelFormatFromUrlResult* out) {
    if (out == nullptr || buffer.status != RAC_SUCCESS || buffer.data == nullptr) {
        return buffer.size == 0 && out != nullptr && out->ParseFromArray(nullptr, 0);
    }
    return out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool parse_artifact_result(const rac_proto_buffer_t& buffer,
                           runanywhere::v1::ArtifactInferFromUrlResult* out) {
    if (out == nullptr || buffer.status != RAC_SUCCESS || buffer.data == nullptr) {
        return buffer.size == 0 && out != nullptr && out->ParseFromArray(nullptr, 0);
    }
    return out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

// ---------------------------------------------------------------------------
// Test: format_from_url covers the single-file formats.
// ---------------------------------------------------------------------------
int test_format_from_url_single_file_formats() {
    struct Case {
        const char* url;
        runanywhere::v1::ModelFormat expected;
    };
    static const Case kCases[] = {
        {.url = "https://example.test/llama-7b.Q4_K_M.gguf",
         .expected = runanywhere::v1::MODEL_FORMAT_GGUF},
        {.url = "https://example.test/whisper-base.en.onnx",
         .expected = runanywhere::v1::MODEL_FORMAT_ONNX},
        {.url = "https://example.test/silero.ort", .expected = runanywhere::v1::MODEL_FORMAT_ORT},
        {.url = "https://example.test/ggml-model.bin",
         .expected = runanywhere::v1::MODEL_FORMAT_BIN},
        {.url = "/local/path/model.safetensors",
         .expected = runanywhere::v1::MODEL_FORMAT_SAFETENSORS},
        {.url = "/local/path/model.mlmodelc", .expected = runanywhere::v1::MODEL_FORMAT_COREML},
    };
    for (const auto& c : kCases) {
        auto req = serialize_format_request(c.url);
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), &out);
        ASSERT_EQ(rc, RAC_SUCCESS);
        runanywhere::v1::ModelFormatFromUrlResult result;
        ASSERT_TRUE(parse_format_result(out, &result));
        if (result.format() != c.expected) {
            std::fprintf(stderr, "url=%s expected=%d got=%d\n", c.url, static_cast<int>(c.expected),
                         static_cast<int>(result.format()));
            rac_proto_buffer_free(&out);
            return 1;
        }
        ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
        rac_proto_buffer_free(&out);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Test: format_from_url on archive URLs reports the archive wrapper (ZIP)
// plus an inferred inner_format when the public catalog naming is well-known.
// ---------------------------------------------------------------------------
int test_format_from_url_archives() {
    // .tar.gz wrapping ONNX content → format UNSPECIFIED, inner ONNX.
    {
        auto req =
            serialize_format_request("https://example.test/sherpa-onnx-whisper-base.en.tar.gz");
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), &out);
        ASSERT_EQ(rc, RAC_SUCCESS);
        runanywhere::v1::ModelFormatFromUrlResult result;
        ASSERT_TRUE(parse_format_result(out, &result));
        ASSERT_EQ(result.format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
        ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_ONNX);
        rac_proto_buffer_free(&out);
    }

    // .zip wrapping a GGUF model (name hints at llama) → format ZIP, inner GGUF.
    {
        auto req = serialize_format_request("https://example.test/llama-7b-gguf.zip");
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), &out);
        ASSERT_EQ(rc, RAC_SUCCESS);
        runanywhere::v1::ModelFormatFromUrlResult result;
        ASSERT_TRUE(parse_format_result(out, &result));
        ASSERT_EQ(result.format(), runanywhere::v1::MODEL_FORMAT_ZIP);
        ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_GGUF);
        rac_proto_buffer_free(&out);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Test: format_from_url returns UNSPECIFIED for unknown extensions.
// ---------------------------------------------------------------------------
int test_format_from_url_unknown() {
    auto req = serialize_format_request("https://example.test/model.xyz");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ModelFormatFromUrlResult result;
    ASSERT_TRUE(parse_format_result(out, &result));
    ASSERT_EQ(result.format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    rac_proto_buffer_free(&out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: format_from_url tolerates query strings and fragments.
// ---------------------------------------------------------------------------
int test_format_from_url_with_query_string() {
    auto req = serialize_format_request(
        "https://example.test/llama-7b.gguf?download=1&token=abc#fragment");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ModelFormatFromUrlResult result;
    ASSERT_TRUE(parse_format_result(out, &result));
    ASSERT_EQ(result.format(), runanywhere::v1::MODEL_FORMAT_GGUF);
    rac_proto_buffer_free(&out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: artifact_infer_from_url on single-file URLs → SINGLE_FILE.
// ---------------------------------------------------------------------------
int test_artifact_single_file() {
    auto req = serialize_artifact_request("https://example.test/llama-7b.Q4_K_M.gguf", "llama-7b");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_artifact_infer_from_url_proto(req.data(), req.size(), &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ArtifactInferFromUrlResult result;
    ASSERT_TRUE(parse_artifact_result(out, &result));
    ASSERT_EQ(result.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    ASSERT_EQ(result.archive_type(), runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED);
    ASSERT_EQ(result.archive_structure(), runanywhere::v1::ARCHIVE_STRUCTURE_UNSPECIFIED);
    ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    rac_proto_buffer_free(&out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: artifact_infer_from_url on .tar.gz URLs → TAR_GZ_ARCHIVE.
// ---------------------------------------------------------------------------
int test_artifact_tar_gz_archive() {
    struct Case {
        const char* url;
        runanywhere::v1::ModelFormat expected_inner;
    };
    static const Case kCases[] = {
        // Sherpa-ONNX / Whisper .tar.gz → inner ONNX.
        {.url = "https://example.test/sherpa-onnx-whisper-base.en.tar.gz",
         .expected_inner = runanywhere::v1::MODEL_FORMAT_ONNX},
        // .tgz suffix is also recognized.
        {.url = "https://example.test/zipformer-en-2025.tgz",
         .expected_inner = runanywhere::v1::MODEL_FORMAT_ONNX},
    };
    for (const auto& c : kCases) {
        auto req = serialize_artifact_request(c.url);
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = rac_artifact_infer_from_url_proto(req.data(), req.size(), &out);
        ASSERT_EQ(rc, RAC_SUCCESS);
        runanywhere::v1::ArtifactInferFromUrlResult result;
        ASSERT_TRUE(parse_artifact_result(out, &result));
        ASSERT_EQ(result.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE);
        ASSERT_EQ(result.archive_type(), runanywhere::v1::ARCHIVE_TYPE_TAR_GZ);
        ASSERT_EQ(result.archive_structure(), runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN);
        ASSERT_EQ(result.inner_format(), c.expected_inner);
        rac_proto_buffer_free(&out);
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Test: artifact_infer_from_url on .zip URLs → ZIP_ARCHIVE.
// ---------------------------------------------------------------------------
int test_artifact_zip_archive() {
    auto req = serialize_artifact_request("https://example.test/llama-7b-gguf.zip");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_artifact_infer_from_url_proto(req.data(), req.size(), &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ArtifactInferFromUrlResult result;
    ASSERT_TRUE(parse_artifact_result(out, &result));
    ASSERT_EQ(result.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE);
    ASSERT_EQ(result.archive_type(), runanywhere::v1::ARCHIVE_TYPE_ZIP);
    ASSERT_EQ(result.archive_structure(), runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN);
    // "llama" heuristic → GGUF inner format.
    ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_GGUF);
    rac_proto_buffer_free(&out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: artifact_infer_from_url on .tar.bz2 URLs → TAR_BZ2_ARCHIVE.
// ---------------------------------------------------------------------------
int test_artifact_tar_bz2_archive() {
    auto req = serialize_artifact_request("https://example.test/piper-en-amy.tar.bz2");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_artifact_infer_from_url_proto(req.data(), req.size(), &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ArtifactInferFromUrlResult result;
    ASSERT_TRUE(parse_artifact_result(out, &result));
    ASSERT_EQ(result.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE);
    ASSERT_EQ(result.archive_type(), runanywhere::v1::ARCHIVE_TYPE_TAR_BZ2);
    // "piper" heuristic → ONNX inner format.
    ASSERT_EQ(result.inner_format(), runanywhere::v1::MODEL_FORMAT_ONNX);
    rac_proto_buffer_free(&out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: empty request serializes and parses to the default result.
// ---------------------------------------------------------------------------
int test_empty_request_default_result() {
    // Empty request → default SINGLE_FILE artifact + UNSPECIFIED format.
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_artifact_infer_from_url_proto(nullptr, 0, &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ArtifactInferFromUrlResult result;
    ASSERT_TRUE(parse_artifact_result(out, &result));
    ASSERT_EQ(result.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    ASSERT_EQ(result.archive_type(), runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED);
    rac_proto_buffer_free(&out);

    rac_proto_buffer_t fmt_out;
    rac_proto_buffer_init(&fmt_out);
    rac_result_t fmt_rc = rac_model_format_from_url_proto(nullptr, 0, &fmt_out);
    ASSERT_EQ(fmt_rc, RAC_SUCCESS);
    runanywhere::v1::ModelFormatFromUrlResult fmt_result;
    ASSERT_TRUE(parse_format_result(fmt_out, &fmt_result));
    ASSERT_EQ(fmt_result.format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    ASSERT_EQ(fmt_result.inner_format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    rac_proto_buffer_free(&fmt_out);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: null out-pointer returns RAC_ERROR_NULL_POINTER.
// ---------------------------------------------------------------------------
int test_null_out_pointer() {
    auto req = serialize_format_request("https://example.test/llama-7b.gguf");
    rac_result_t rc = rac_model_format_from_url_proto(req.data(), req.size(), nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);

    rac_result_t rc2 = rac_artifact_infer_from_url_proto(req.data(), req.size(), nullptr);
    ASSERT_EQ(rc2, RAC_ERROR_NULL_POINTER);
    return 0;
}

// ---------------------------------------------------------------------------
// Test: invalid input bytes (size>0 with null data) are rejected.
// ---------------------------------------------------------------------------
int test_invalid_input_bytes() {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_model_format_from_url_proto(nullptr, 42, &out);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&out);

    rac_proto_buffer_t out2;
    rac_proto_buffer_init(&out2);
    rac_result_t rc2 = rac_artifact_infer_from_url_proto(nullptr, 42, &out2);
    ASSERT_EQ(rc2, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&out2);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; model format infer tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {.name = "format_from_url_single_file_formats",
         .fn = test_format_from_url_single_file_formats},
        {.name = "format_from_url_archives", .fn = test_format_from_url_archives},
        {.name = "format_from_url_unknown", .fn = test_format_from_url_unknown},
        {.name = "format_from_url_with_query_string", .fn = test_format_from_url_with_query_string},
        {.name = "artifact_single_file", .fn = test_artifact_single_file},
        {.name = "artifact_tar_gz_archive", .fn = test_artifact_tar_gz_archive},
        {.name = "artifact_zip_archive", .fn = test_artifact_zip_archive},
        {.name = "artifact_tar_bz2_archive", .fn = test_artifact_tar_bz2_archive},
        {.name = "empty_request_default_result", .fn = test_empty_request_default_result},
        {.name = "null_out_pointer", .fn = test_null_out_pointer},
        {.name = "invalid_input_bytes", .fn = test_invalid_input_bytes},
    };

    int failures = 0;
    for (const auto& t : kTests) {
        std::printf("RUN  %s\n", t.name);
        int rc = t.fn();
        if (rc != 0) {
            std::printf("FAIL %s\n", t.name);
            failures++;
        } else {
            std::printf("PASS %s\n", t.name);
        }
    }

    if (failures > 0) {
        std::fprintf(stderr, "\n%d test(s) failed.\n", failures);
        return 1;
    }
    std::printf("\nAll %zu test(s) passed.\n", sizeof(kTests) / sizeof(kTests[0]));
    return 0;
#endif
}
