/**
 * @file test_artifact_helpers_proto.cpp
 * @brief Parity tests for the canonical artifact ExpectedModelFiles helper.
 *
 * Exercises rac_artifact_expected_files_proto for every artifact subtype
 * Swift's RAModelInfo.expectedArtifactFiles +
 * RAModelInfo.OneOf_Artifact.expectedFiles handles:
 *
 *   - Top-level model.expected_files short-circuit (Swift's
 *     `if hasExpectedFiles { return expectedFiles }`).
 *   - SINGLE_FILE artifact with explicit expected_files manifest.
 *   - SINGLE_FILE artifact with required/optional pattern shorthand.
 *   - ARCHIVE (zip)   artifact with explicit expected_files manifest.
 *   - ARCHIVE (tar.gz) artifact with required/optional pattern shorthand.
 *   - MULTI_FILE artifact with descriptor list (verifies the descriptor
 *     list is copied into ExpectedModelFiles.files so the per-file download
 *     loop fires).
 *   - Default / no-artifact case → empty manifest (Swift's `.none` fallback).
 *   - Empty model bytes → empty manifest.
 *   - Negative paths: NULL out pointer, malformed bytes.
 */

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

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

#define ASSERT_STR_EQ(a, b)                                                                        \
    do {                                                                                           \
        if ((a) != (b)) {                                                                          \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d (got=\"%s\" expected=\"%s\")\n", \
                         #a, #b, __FILE__, __LINE__, std::string(a).c_str(),                       \
                         std::string(b).c_str());                                                  \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF

// Helper: serialize the model and dispatch the proto API.
bool dispatch_expected_files(const runanywhere::v1::ModelInfo& model,
                             runanywhere::v1::ExpectedModelFiles* out) {
    std::string bytes;
    if (!model.SerializeToString(&bytes)) {
        std::fprintf(stderr, "failed to serialize ModelInfo\n");
        return false;
    }

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_artifact_expected_files_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buffer);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_artifact_expected_files_proto rc=%d\n", rc);
        rac_proto_buffer_free(&buffer);
        return false;
    }
    if (buffer.status != RAC_SUCCESS) {
        std::fprintf(stderr, "buffer.status=%d msg=%s\n", buffer.status,
                     buffer.error_message ? buffer.error_message : "(null)");
        rac_proto_buffer_free(&buffer);
        return false;
    }
    bool parsed = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return parsed;
}

// Test cases — Swift parity matrix.
int test_top_level_expected_files_short_circuit() {
    // Swift's `if hasExpectedFiles { return expectedFiles }` short-circuit:
    // when the top-level model.expected_files manifest is set, return it
    // verbatim regardless of what the artifact carries.
    runanywhere::v1::ModelInfo model;
    model.set_id("top-level-manifest");
    runanywhere::v1::ExpectedModelFiles* top = model.mutable_expected_files();
    top->add_required_patterns("*.bin");
    top->add_optional_patterns("README.md");
    top->set_root_directory("models/whisper-tiny");
    top->set_description("Top-level wins.");

    // Even if the artifact branch has a competing manifest, Swift returns the
    // top-level one. Wire one into single_file to verify we don't pick it up.
    runanywhere::v1::SingleFileArtifact* art = model.mutable_single_file();
    art->mutable_expected_files()->add_required_patterns("ignored.bin");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 1);
    ASSERT_STR_EQ(result.required_patterns(0), std::string("*.bin"));
    ASSERT_EQ(result.optional_patterns_size(), 1);
    ASSERT_STR_EQ(result.optional_patterns(0), std::string("README.md"));
    ASSERT_STR_EQ(result.root_directory(), std::string("models/whisper-tiny"));
    ASSERT_STR_EQ(result.description(), std::string("Top-level wins."));
    ASSERT_EQ(result.files_size(), 0);
    return 0;
}

int test_single_file_with_explicit_manifest() {
    // SINGLE_FILE artifact carrying an explicit ExpectedModelFiles manifest.
    runanywhere::v1::ModelInfo model;
    model.set_id("single-file-explicit");
    runanywhere::v1::SingleFileArtifact* art = model.mutable_single_file();
    runanywhere::v1::ExpectedModelFiles* manifest = art->mutable_expected_files();
    manifest->add_required_patterns("model.gguf");
    manifest->add_optional_patterns("tokenizer.json");
    manifest->set_description("Single file with manifest.");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 1);
    ASSERT_STR_EQ(result.required_patterns(0), std::string("model.gguf"));
    ASSERT_EQ(result.optional_patterns_size(), 1);
    ASSERT_STR_EQ(result.optional_patterns(0), std::string("tokenizer.json"));
    ASSERT_STR_EQ(result.description(), std::string("Single file with manifest."));
    return 0;
}

int test_single_file_with_pattern_shorthand() {
    // SINGLE_FILE artifact with patterns shorthand (no explicit manifest).
    runanywhere::v1::ModelInfo model;
    model.set_id("single-file-patterns");
    runanywhere::v1::SingleFileArtifact* art = model.mutable_single_file();
    art->add_required_patterns("*.gguf");
    art->add_required_patterns("config.json");
    art->add_optional_patterns("README.md");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 2);
    ASSERT_STR_EQ(result.required_patterns(0), std::string("*.gguf"));
    ASSERT_STR_EQ(result.required_patterns(1), std::string("config.json"));
    ASSERT_EQ(result.optional_patterns_size(), 1);
    ASSERT_STR_EQ(result.optional_patterns(0), std::string("README.md"));
    // Description and root_directory remain empty when synthesised from
    // patterns shorthand.
    ASSERT_STR_EQ(result.description(), std::string(""));
    ASSERT_STR_EQ(result.root_directory(), std::string(""));
    return 0;
}

int test_zip_archive_with_explicit_manifest() {
    // ARCHIVE (zip) artifact with explicit ExpectedModelFiles manifest.
    runanywhere::v1::ModelInfo model;
    model.set_id("zip-explicit");
    runanywhere::v1::ArchiveArtifact* art = model.mutable_archive();
    art->set_type(runanywhere::v1::ARCHIVE_TYPE_ZIP);
    art->set_structure(runanywhere::v1::ARCHIVE_STRUCTURE_DIRECTORY_BASED);
    runanywhere::v1::ExpectedModelFiles* manifest = art->mutable_expected_files();
    manifest->add_required_patterns("encoder.onnx");
    manifest->add_required_patterns("decoder.onnx");
    manifest->set_root_directory("whisper");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 2);
    ASSERT_STR_EQ(result.required_patterns(0), std::string("encoder.onnx"));
    ASSERT_STR_EQ(result.required_patterns(1), std::string("decoder.onnx"));
    ASSERT_STR_EQ(result.root_directory(), std::string("whisper"));
    return 0;
}

int test_tar_gz_archive_with_pattern_shorthand() {
    // ARCHIVE (tar.gz) artifact with patterns shorthand.
    runanywhere::v1::ModelInfo model;
    model.set_id("tar-gz-patterns");
    runanywhere::v1::ArchiveArtifact* art = model.mutable_archive();
    art->set_type(runanywhere::v1::ARCHIVE_TYPE_TAR_GZ);
    art->set_structure(runanywhere::v1::ARCHIVE_STRUCTURE_NESTED_DIRECTORY);
    art->add_required_patterns("*.onnx");
    art->add_optional_patterns("tokens.txt");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 1);
    ASSERT_STR_EQ(result.required_patterns(0), std::string("*.onnx"));
    ASSERT_EQ(result.optional_patterns_size(), 1);
    ASSERT_STR_EQ(result.optional_patterns(0), std::string("tokens.txt"));
    return 0;
}

int test_multi_file_descriptors() {
    // MULTI_FILE artifact: ExpectedModelFiles.files seeded from descriptor
    // list. Mirrors Swift's
    //   var expected = RAExpectedModelFiles()
    //   expected.files = artifact.files
    //   return expected
    // Each descriptor's url/filename/role/is_required round-trips.
    runanywhere::v1::ModelInfo model;
    model.set_id("multi-file");
    runanywhere::v1::MultiFileArtifact* art = model.mutable_multi_file();

    // Primary GGUF model file.
    {
        runanywhere::v1::ModelFileDescriptor* d = art->add_files();
        d->set_url("https://example.test/qwen-vl/model.gguf");
        d->set_filename("model.gguf");
        d->set_is_required(true);
        d->set_role(runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);
    }
    // Vision projector (mmproj).
    {
        runanywhere::v1::ModelFileDescriptor* d = art->add_files();
        d->set_url("https://example.test/qwen-vl/mmproj.gguf");
        d->set_filename("mmproj.gguf");
        d->set_is_required(true);
        d->set_role(runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR);
    }
    // Tokenizer (optional).
    {
        runanywhere::v1::ModelFileDescriptor* d = art->add_files();
        d->set_url("https://example.test/qwen-vl/tokenizer.json");
        d->set_filename("tokenizer.json");
        d->set_is_required(false);
        d->set_role(runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);
    }

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    // Patterns remain empty for multi_file — only files is populated.
    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.optional_patterns_size(), 0);
    ASSERT_EQ(result.files_size(), 3);

    ASSERT_STR_EQ(result.files(0).url(), std::string("https://example.test/qwen-vl/model.gguf"));
    ASSERT_STR_EQ(result.files(0).filename(), std::string("model.gguf"));
    ASSERT_EQ(result.files(0).is_required(), true);
    ASSERT_EQ(result.files(0).role(), runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);

    ASSERT_STR_EQ(result.files(1).filename(), std::string("mmproj.gguf"));
    ASSERT_EQ(result.files(1).role(), runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR);

    ASSERT_STR_EQ(result.files(2).filename(), std::string("tokenizer.json"));
    ASSERT_EQ(result.files(2).is_required(), false);
    ASSERT_EQ(result.files(2).role(), runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);
    return 0;
}

int test_multi_file_empty_descriptors() {
    // MULTI_FILE artifact with zero descriptors → empty manifest. Mirrors
    // Swift's `guard !artifact.files.isEmpty else { return .none }`.
    runanywhere::v1::ModelInfo model;
    model.set_id("multi-file-empty");
    model.mutable_multi_file();  // Empty file list.

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.files_size(), 0);
    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.optional_patterns_size(), 0);
    return 0;
}

int test_no_artifact_default() {
    // No artifact set on the model → empty manifest. Mirrors Swift's
    // `default: return .none`.
    runanywhere::v1::ModelInfo model;
    model.set_id("no-artifact");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.optional_patterns_size(), 0);
    ASSERT_EQ(result.files_size(), 0);
    return 0;
}

int test_built_in_artifact_default() {
    // built_in artifact (oneof variant) → empty manifest.
    runanywhere::v1::ModelInfo model;
    model.set_id("built-in");
    model.set_built_in(true);

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.files_size(), 0);
    return 0;
}

int test_custom_strategy_id_default() {
    // custom_strategy_id artifact → empty manifest (Swift's `.custom` falls
    // through the `default` arm of expectedFiles).
    runanywhere::v1::ModelInfo model;
    model.set_id("custom-strategy");
    model.set_custom_strategy_id("my-strategy");

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(dispatch_expected_files(model, &result));

    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.files_size(), 0);
    return 0;
}

int test_empty_model_bytes_returns_empty_manifest() {
    // Empty input → default ModelInfo → empty manifest.
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_artifact_expected_files_proto(nullptr, 0, &buffer);
    ASSERT_EQ(rc, RAC_SUCCESS);

    runanywhere::v1::ExpectedModelFiles result;
    ASSERT_TRUE(result.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));
    ASSERT_EQ(result.required_patterns_size(), 0);
    ASSERT_EQ(result.files_size(), 0);
    rac_proto_buffer_free(&buffer);
    return 0;
}

// Negative paths.
int test_null_out_pointer() {
    rac_result_t rc = rac_artifact_expected_files_proto(nullptr, 0, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

int test_invalid_input_bytes() {
    // Non-zero size with NULL data is invalid.
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_artifact_expected_files_proto(nullptr, 42, &buffer);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_malformed_input_bytes() {
    // Wire-format garbage that does not parse as a ModelInfo.
    static const uint8_t kGarbage[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_artifact_expected_files_proto(kGarbage, sizeof(kGarbage), &buffer);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&buffer);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf(
        "SKIP: RAC_HAVE_PROTOBUF not defined; artifact_helpers_proto tests "
        "skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {.name = "top_level_expected_files_short_circuit",
         .fn = test_top_level_expected_files_short_circuit},
        {.name = "single_file_with_explicit_manifest",
         .fn = test_single_file_with_explicit_manifest},
        {.name = "single_file_with_pattern_shorthand",
         .fn = test_single_file_with_pattern_shorthand},
        {.name = "zip_archive_with_explicit_manifest",
         .fn = test_zip_archive_with_explicit_manifest},
        {.name = "tar_gz_archive_with_pattern_shorthand",
         .fn = test_tar_gz_archive_with_pattern_shorthand},
        {.name = "multi_file_descriptors", .fn = test_multi_file_descriptors},
        {.name = "multi_file_empty_descriptors", .fn = test_multi_file_empty_descriptors},
        {.name = "no_artifact_default", .fn = test_no_artifact_default},
        {.name = "built_in_artifact_default", .fn = test_built_in_artifact_default},
        {.name = "custom_strategy_id_default", .fn = test_custom_strategy_id_default},
        {.name = "empty_model_bytes_returns_empty_manifest",
         .fn = test_empty_model_bytes_returns_empty_manifest},
        {.name = "null_out_pointer", .fn = test_null_out_pointer},
        {.name = "invalid_input_bytes", .fn = test_invalid_input_bytes},
        {.name = "malformed_input_bytes", .fn = test_malformed_input_bytes},
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
