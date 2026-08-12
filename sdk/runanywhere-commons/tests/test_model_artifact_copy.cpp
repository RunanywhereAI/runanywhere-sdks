/**
 * @file test_model_artifact_copy.cpp
 * @brief Round-trip tests for artifact-descriptor deep copy.
 *
 * `rac_model_artifact_info_t` owns three heap blocks: the expected-files
 * manifest, the multi-file descriptor array, and the strategy id. Both
 * duplicators of a `rac_model_info_t` -- the public `rac_model_info_copy()` and
 * the registry's internal `deep_copy_model()` (reached here through
 * save + get) -- must duplicate all three, and must keep `file_descriptors`
 * and `file_descriptor_count` in lockstep.
 *
 * The two regressions under test:
 *
 *   1. Shallow copy loses data. `rac_model_info_copy()` used to assign the
 *      artifact struct and then null the two pointers, so every model-assignment
 *      cache round-trip silently dropped multi-file metadata and downgraded
 *      completeness validation to filename heuristics.
 *
 *   2. Shallow copy breaks the pointer/count invariant. Nulling
 *      `file_descriptors` while retaining `file_descriptor_count` hands
 *      consumers a non-zero count over a NULL array;
 *      `model_folder_is_complete_struct()` in model_registry_manifest.cpp
 *      indexes `file_descriptors[i]` bounded only by that count, so the copy
 *      dereferences NULL.
 *
 * The tests also assert the copy owns its own memory (no pointer aliasing) and
 * survives the source being freed, which is what makes it safe for both callers
 * to `rac_model_info_free()` independently.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

#define EXPECT_TRUE(_cond)                                                          \
    do {                                                                            \
        if (!(_cond)) {                                                             \
            std::fprintf(stderr, "FAIL @ %s:%d: %s\n", __FILE__, __LINE__, #_cond); \
            return 1;                                                               \
        }                                                                           \
    } while (0)

#define EXPECT_STREQ(_a, _b)                                                             \
    do {                                                                                 \
        if (!(_a) || !(_b) || std::strcmp((_a), (_b)) != 0) {                            \
            std::fprintf(stderr, "FAIL @ %s:%d: \"%s\" != \"%s\"\n", __FILE__, __LINE__, \
                         (_a) ? (_a) : "(null)", (_b) ? (_b) : "(null)");                \
            return 1;                                                                    \
        }                                                                                \
    } while (0)

const char* kRequiredPatterns[] = {"*.onnx", "tokens.txt"};
const char* kOptionalPatterns[] = {"README.md"};

// A model carrying every artifact field a real multi-file model uses: an
// expected-files manifest (required + optional patterns + description), two
// descriptors (one with url/checksum, one deliberately without, to cover the
// nullable-string path), and a custom strategy id.
rac_model_info_t* build_multi_file_model() {
    rac_model_info_t* model = rac_model_info_alloc();
    if (!model) {
        return nullptr;
    }
    model->id = rac_strdup("test-multi-file");
    model->name = rac_strdup("Test Multi File");
    model->category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
    model->format = RAC_MODEL_FORMAT_ONNX;
    model->framework = RAC_FRAMEWORK_SHERPA;
    model->download_url = rac_strdup("https://example.test/multi");
    model->description = rac_strdup("multi-file test model");

    model->artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
    model->artifact_info.archive_type = RAC_ARCHIVE_TYPE_ZIP;
    model->artifact_info.archive_structure = RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED;
    model->artifact_info.strategy_id = rac_strdup("sherpa-multi");

    rac_expected_model_files_t* files = rac_expected_model_files_alloc();
    files->required_patterns = static_cast<const char**>(calloc(2, sizeof(char*)));
    files->required_patterns[0] = rac_strdup(kRequiredPatterns[0]);
    files->required_patterns[1] = rac_strdup(kRequiredPatterns[1]);
    files->required_pattern_count = 2;
    files->optional_patterns = static_cast<const char**>(calloc(1, sizeof(char*)));
    files->optional_patterns[0] = rac_strdup(kOptionalPatterns[0]);
    files->optional_pattern_count = 1;
    files->description = rac_strdup("encoder + tokens");
    model->artifact_info.expected_files = files;

    rac_model_file_descriptor_t* descriptors = rac_model_file_descriptors_alloc(2);
    descriptors[0].relative_path = rac_strdup("encoder.onnx");
    descriptors[0].destination_path = rac_strdup("encoder.onnx");
    descriptors[0].url = rac_strdup("https://example.test/multi/encoder.onnx");
    descriptors[0].checksum_sha256 = rac_strdup("abc123");
    descriptors[0].is_required = RAC_TRUE;
    descriptors[0].role = RAC_MODEL_FILE_ROLE_PRIMARY_MODEL;
    descriptors[0].size_bytes = 4096;
    // Second descriptor leaves url and checksum NULL on purpose.
    descriptors[1].relative_path = rac_strdup("tokens.txt");
    descriptors[1].destination_path = rac_strdup("tokens.txt");
    descriptors[1].is_required = RAC_FALSE;
    descriptors[1].role = RAC_MODEL_FILE_ROLE_TOKENIZER;
    descriptors[1].size_bytes = 128;
    model->artifact_info.file_descriptors = descriptors;
    model->artifact_info.file_descriptor_count = 2;

    return model;
}

// Field-by-field check of a copy against the values build_multi_file_model()
// wrote. Takes values rather than the source pointer so it can run after the
// source has been freed.
int verify_multi_file_artifact(const rac_model_artifact_info_t& artifact) {
    EXPECT_TRUE(artifact.kind == RAC_ARTIFACT_KIND_MULTI_FILE);
    EXPECT_TRUE(artifact.archive_type == RAC_ARCHIVE_TYPE_ZIP);
    EXPECT_TRUE(artifact.archive_structure == RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED);
    EXPECT_STREQ(artifact.strategy_id, "sherpa-multi");

    EXPECT_TRUE(artifact.expected_files != nullptr);
    EXPECT_TRUE(artifact.expected_files->required_pattern_count == 2);
    EXPECT_TRUE(artifact.expected_files->required_patterns != nullptr);
    EXPECT_STREQ(artifact.expected_files->required_patterns[0], kRequiredPatterns[0]);
    EXPECT_STREQ(artifact.expected_files->required_patterns[1], kRequiredPatterns[1]);
    EXPECT_TRUE(artifact.expected_files->optional_pattern_count == 1);
    EXPECT_TRUE(artifact.expected_files->optional_patterns != nullptr);
    EXPECT_STREQ(artifact.expected_files->optional_patterns[0], kOptionalPatterns[0]);
    EXPECT_STREQ(artifact.expected_files->description, "encoder + tokens");

    EXPECT_TRUE(artifact.file_descriptor_count == 2);
    EXPECT_TRUE(artifact.file_descriptors != nullptr);
    EXPECT_STREQ(artifact.file_descriptors[0].relative_path, "encoder.onnx");
    EXPECT_STREQ(artifact.file_descriptors[0].destination_path, "encoder.onnx");
    EXPECT_STREQ(artifact.file_descriptors[0].url, "https://example.test/multi/encoder.onnx");
    EXPECT_STREQ(artifact.file_descriptors[0].checksum_sha256, "abc123");
    EXPECT_TRUE(artifact.file_descriptors[0].is_required == RAC_TRUE);
    EXPECT_TRUE(artifact.file_descriptors[0].role == RAC_MODEL_FILE_ROLE_PRIMARY_MODEL);
    EXPECT_TRUE(artifact.file_descriptors[0].size_bytes == 4096);
    EXPECT_STREQ(artifact.file_descriptors[1].relative_path, "tokens.txt");
    EXPECT_STREQ(artifact.file_descriptors[1].destination_path, "tokens.txt");
    EXPECT_TRUE(artifact.file_descriptors[1].url == nullptr);
    EXPECT_TRUE(artifact.file_descriptors[1].checksum_sha256 == nullptr);
    EXPECT_TRUE(artifact.file_descriptors[1].is_required == RAC_FALSE);
    EXPECT_TRUE(artifact.file_descriptors[1].role == RAC_MODEL_FILE_ROLE_TOKENIZER);
    EXPECT_TRUE(artifact.file_descriptors[1].size_bytes == 128);
    return 0;
}

// The invariant every consumer that iterates file_descriptors[i] relies on.
int verify_descriptor_invariant(const rac_model_artifact_info_t& artifact) {
    EXPECT_TRUE((artifact.file_descriptors != nullptr) == (artifact.file_descriptor_count > 0));
    return 0;
}

// ---------------------------------------------------------------------------
// rac_model_info_copy() preserves the whole artifact block.
// ---------------------------------------------------------------------------
int test_model_info_copy_preserves_artifact() {
    rac_model_info_t* source = build_multi_file_model();
    EXPECT_TRUE(source != nullptr);

    rac_model_info_t* copy = rac_model_info_copy(source);
    EXPECT_TRUE(copy != nullptr);

    int rc = verify_descriptor_invariant(copy->artifact_info);
    if (rc == 0) {
        rc = verify_multi_file_artifact(copy->artifact_info);
    }

    rac_model_info_free(source);
    rac_model_info_free(copy);
    return rc;
}

// ---------------------------------------------------------------------------
// The copy owns its memory: no pointer is shared with the source, and the copy
// stays fully readable after the source is freed. Both callers free
// independently, so any aliasing here is a double free in production.
// ---------------------------------------------------------------------------
int test_model_info_copy_is_independent() {
    rac_model_info_t* source = build_multi_file_model();
    EXPECT_TRUE(source != nullptr);

    rac_model_info_t* copy = rac_model_info_copy(source);
    EXPECT_TRUE(copy != nullptr);

    EXPECT_TRUE(copy->artifact_info.expected_files != source->artifact_info.expected_files);
    EXPECT_TRUE(copy->artifact_info.expected_files->required_patterns !=
                source->artifact_info.expected_files->required_patterns);
    EXPECT_TRUE(copy->artifact_info.expected_files->required_patterns[0] !=
                source->artifact_info.expected_files->required_patterns[0]);
    EXPECT_TRUE(copy->artifact_info.expected_files->optional_patterns !=
                source->artifact_info.expected_files->optional_patterns);
    EXPECT_TRUE(copy->artifact_info.expected_files->description !=
                source->artifact_info.expected_files->description);
    EXPECT_TRUE(copy->artifact_info.file_descriptors != source->artifact_info.file_descriptors);
    EXPECT_TRUE(copy->artifact_info.file_descriptors[0].relative_path !=
                source->artifact_info.file_descriptors[0].relative_path);
    EXPECT_TRUE(copy->artifact_info.file_descriptors[0].url !=
                source->artifact_info.file_descriptors[0].url);
    EXPECT_TRUE(copy->artifact_info.file_descriptors[0].checksum_sha256 !=
                source->artifact_info.file_descriptors[0].checksum_sha256);
    EXPECT_TRUE(copy->artifact_info.strategy_id != source->artifact_info.strategy_id);

    // Free the source first, then read the copy end to end.
    rac_model_info_free(source);
    const int rc = verify_multi_file_artifact(copy->artifact_info);
    rac_model_info_free(copy);
    return rc;
}

// ---------------------------------------------------------------------------
// Regression: a source whose count disagrees with its (NULL) array must not
// propagate the count. This is the shape the old shallow copy produced, and
// model_folder_is_complete_struct() dereferences file_descriptors[i] using only
// that count.
// ---------------------------------------------------------------------------
int test_copy_never_pairs_null_array_with_nonzero_count() {
    rac_model_info_t* source = rac_model_info_alloc();
    EXPECT_TRUE(source != nullptr);
    source->id = rac_strdup("inconsistent");
    source->artifact_info.kind = RAC_ARTIFACT_KIND_MULTI_FILE;
    source->artifact_info.file_descriptors = nullptr;
    source->artifact_info.file_descriptor_count = 3;  // lies about the array

    rac_model_info_t* copy = rac_model_info_copy(source);
    EXPECT_TRUE(copy != nullptr);
    EXPECT_TRUE(copy->artifact_info.file_descriptors == nullptr);
    EXPECT_TRUE(copy->artifact_info.file_descriptor_count == 0);
    const int rc = verify_descriptor_invariant(copy->artifact_info);

    rac_model_info_free(source);
    rac_model_info_free(copy);
    return rc;
}

// ---------------------------------------------------------------------------
// An artifact with no manifest and no descriptors copies to the same empty
// shape (and frees cleanly).
// ---------------------------------------------------------------------------
int test_copy_empty_artifact() {
    rac_model_info_t* source = rac_model_info_alloc();
    EXPECT_TRUE(source != nullptr);
    source->id = rac_strdup("single-file");
    source->artifact_info.kind = RAC_ARTIFACT_KIND_SINGLE_FILE;

    rac_model_info_t* copy = rac_model_info_copy(source);
    EXPECT_TRUE(copy != nullptr);
    EXPECT_TRUE(copy->artifact_info.kind == RAC_ARTIFACT_KIND_SINGLE_FILE);
    EXPECT_TRUE(copy->artifact_info.expected_files == nullptr);
    EXPECT_TRUE(copy->artifact_info.file_descriptors == nullptr);
    EXPECT_TRUE(copy->artifact_info.file_descriptor_count == 0);
    EXPECT_TRUE(copy->artifact_info.strategy_id == nullptr);
    const int rc = verify_descriptor_invariant(copy->artifact_info);

    rac_model_info_free(source);
    rac_model_info_free(copy);
    return rc;
}

// ---------------------------------------------------------------------------
// The registry's deep_copy_model() path (save + get) shares the same helper, so
// a save/get round-trip must return the artifact block intact.
// ---------------------------------------------------------------------------
int test_registry_round_trip_preserves_artifact() {
    rac_model_registry_handle_t registry = nullptr;
    EXPECT_TRUE(rac_model_registry_create(&registry) == RAC_SUCCESS);
    EXPECT_TRUE(registry != nullptr);

    rac_model_info_t* source = build_multi_file_model();
    EXPECT_TRUE(source != nullptr);
    EXPECT_TRUE(rac_model_registry_save(registry, source) == RAC_SUCCESS);

    // Free the source before reading back: the registry must hold its own copy.
    rac_model_info_free(source);

    rac_model_info_t* fetched = nullptr;
    EXPECT_TRUE(rac_model_registry_get(registry, "test-multi-file", &fetched) == RAC_SUCCESS);
    EXPECT_TRUE(fetched != nullptr);

    int rc = verify_descriptor_invariant(fetched->artifact_info);
    if (rc == 0) {
        rc = verify_multi_file_artifact(fetched->artifact_info);
    }

    rac_model_info_free(fetched);
    rac_model_registry_destroy(registry);
    return rc;
}

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    int failures = 0;
    failures += test_model_info_copy_preserves_artifact();
    failures += test_model_info_copy_is_independent();
    failures += test_copy_never_pairs_null_array_with_nonzero_count();
    failures += test_copy_empty_artifact();
    failures += test_registry_round_trip_preserves_artifact();

    if (failures == 0) {
        std::fprintf(stdout, "[PASS] test_model_artifact_copy\n");
        return 0;
    }
    std::fprintf(stderr, "[FAIL] test_model_artifact_copy (%d failure(s))\n", failures);
    return 1;
}
