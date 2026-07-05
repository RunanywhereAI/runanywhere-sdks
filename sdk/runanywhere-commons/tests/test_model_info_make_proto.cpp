/**
 * @file test_model_info_make_proto.cpp
 * @brief Tests for the canonical RAModelInfo factory.
 *
 * Exercises rac_model_info_make_proto for representative URL shapes:
 *   - .gguf single-file → SINGLE_FILE artifact, LLAMA_CPP framework, LANGUAGE
 *     category, contextLength=2048.
 *   - .onnx single-file → SINGLE_FILE artifact, ONNX framework.
 *   - .mlmodelc single-file → SINGLE_FILE artifact, COREML framework.
 *   - .safetensors single-file → SINGLE_FILE artifact, METALRT framework.
 *   - multi-file artifact request (no archive suffix) → SINGLE_FILE artifact
 *     when no override is given.
 *   - .tar.gz archive → TAR_GZ_ARCHIVE artifact_type, ARCHIVE branch.
 *
 * Also exercises the platform-adapter is_non_empty_directory probe via
 * rac_path_is_non_empty_directory():
 *   - With a custom adapter callback present.
 *   - With NULL callback + file_list_directory fallback (verifies the
 *     two-call enumeration path).
 *   - With both NULL → RAC_FALSE.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
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

// Mock platform adapter for the disk probe paths.
struct MockAdapterState {
    // Behaviour of is_non_empty_directory: 0=NULL, 1=returns RAC_TRUE,
    //                                       2=returns RAC_FALSE.
    int dir_probe_mode = 0;
    int dir_probe_calls = 0;
    int list_dir_calls = 0;
    bool list_dir_returns_entry = false;
};

MockAdapterState g_mock_state;

rac_bool_t mock_is_non_empty_directory(const char* /*path*/, void* /*user*/) {
    g_mock_state.dir_probe_calls++;
    return g_mock_state.dir_probe_mode == 1 ? RAC_TRUE : RAC_FALSE;
}

rac_result_t mock_file_list_directory(const char* /*dir_path*/,
                                      rac_directory_entry_t* /*out_entries*/, size_t* in_out_count,
                                      void* /*user*/) {
    g_mock_state.list_dir_calls++;
    if (in_out_count) {
        *in_out_count = g_mock_state.list_dir_returns_entry ? 1u : 0u;
    }
    return RAC_SUCCESS;
}

// Stub callbacks required by rac_platform_adapter_t. Most of these are
// never invoked by the make() factory but they need to be non-NULL only
// for the probe-related slots; the others can stay NULL since
// rac_get_platform_adapter() simply hands back whatever struct we registered.
void mock_install_adapter(bool with_dir_probe, bool with_list_dir) {
    static rac_platform_adapter_t adapter;
    std::memset(&adapter, 0, sizeof(adapter));
    if (with_dir_probe) {
        adapter.is_non_empty_directory = &mock_is_non_empty_directory;
    }
    if (with_list_dir) {
        adapter.file_list_directory = &mock_file_list_directory;
    }
    rac_set_platform_adapter(&adapter);
}

void mock_clear_adapter() {
    rac_set_platform_adapter(nullptr);
    g_mock_state = {};
}

// Helper: serialize a make-request and dispatch the proto API.
struct MakeArgs {
    std::string url;
    std::string name;
    bool has_framework = false;
    runanywhere::v1::InferenceFramework framework =
        runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
    bool has_category = false;
    runanywhere::v1::ModelCategory category = runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
    bool has_source = false;
    runanywhere::v1::ModelSource source = runanywhere::v1::MODEL_SOURCE_UNSPECIFIED;
};

bool make_proto(const MakeArgs& args, runanywhere::v1::ModelInfo* out) {
    runanywhere::v1::ModelInfoMakeRequest request;
    request.set_url(args.url);
    request.set_name(args.name);
    if (args.has_framework)
        request.set_framework(args.framework);
    if (args.has_category)
        request.set_category(args.category);
    if (args.has_source)
        request.set_source(args.source);

    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        std::fprintf(stderr, "failed to serialize ModelInfoMakeRequest\n");
        return false;
    }

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_model_info_make_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                bytes.size(), &buffer);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_model_info_make_proto rc=%d\n", rc);
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

// Test cases — representative URLs.
int test_make_gguf_single_file() {
    MakeArgs args;
    args.url = "https://example.test/llama-7b.Q4_K_M.gguf";
    args.name = "Llama 7B Q4_K_M";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.id(), std::string("llama-7b.Q4_K_M"));
    ASSERT_EQ(model.name(), std::string("Llama 7B Q4_K_M"));
    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_GGUF);
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_EQ(model.category(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    ASSERT_EQ(model.context_length(), 2048);
    ASSERT_EQ(model.supports_thinking(), false);
    ASSERT_EQ(model.source(), runanywhere::v1::MODEL_SOURCE_REMOTE);
    ASSERT_EQ(model.download_url(), args.url);
    ASSERT_EQ(model.local_path(), std::string(""));
    ASSERT_EQ(model.download_size_bytes(), 0);
    ASSERT_TRUE(model.has_single_file());
    ASSERT_EQ(model.artifact_case(), runanywhere::v1::ModelInfo::kSingleFile);
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    ASSERT_EQ(model.is_downloaded(), false);
    ASSERT_EQ(model.is_available(), false);
    ASSERT_TRUE(model.created_at_unix_ms() > 0);
    ASSERT_TRUE(model.updated_at_unix_ms() > 0);
    return 0;
}

int test_make_onnx_single_file() {
    MakeArgs args;
    args.url = "https://example.test/whisper-base.en.onnx";
    args.name = "";  // Force generation from URL.

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.id(), std::string("whisper-base.en"));
    // Generated name strips extension and replaces dashes with spaces.
    ASSERT_EQ(model.name(), std::string("whisper base.en"));
    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_ONNX);
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
    // ONNX framework defaults to MULTIMODAL category.
    ASSERT_EQ(model.category(), runanywhere::v1::MODEL_CATEGORY_MULTIMODAL);
    // Multimodal requires context length → 2048.
    ASSERT_EQ(model.context_length(), 2048);
    ASSERT_TRUE(model.has_single_file());
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    return 0;
}

int test_make_mlmodelc_single_file() {
    MakeArgs args;
    args.url = "/local/models/whisper-tiny.mlmodelc";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_COREML);
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_COREML);
    ASSERT_TRUE(model.has_single_file());
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    return 0;
}

int test_make_safetensors_single_file() {
    MakeArgs args;
    args.url = "https://example.test/llama-3-8b.safetensors";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_SAFETENSORS);
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_METALRT);
    // METALRT framework falls into the default arm of category_from_framework
    // which returns AUDIO. (Mirrors Swift's fallback.) The point of this test
    // is to verify framework detection from .safetensors → METALRT.
    ASSERT_EQ(model.category(), runanywhere::v1::MODEL_CATEGORY_AUDIO);
    // AUDIO does not require context length.
    ASSERT_EQ(model.context_length(), 0);
    ASSERT_TRUE(model.has_single_file());
    return 0;
}

int test_make_tar_gz_archive() {
    MakeArgs args;
    args.url = "https://example.test/sherpa-onnx-whisper-base.en.tar.gz";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    // .tar.gz suffix → archive branch with TAR_GZ archive type.
    ASSERT_EQ(model.artifact_case(), runanywhere::v1::ModelInfo::kArchive);
    ASSERT_TRUE(model.has_archive());
    ASSERT_EQ(model.archive().type(), runanywhere::v1::ARCHIVE_TYPE_TAR_GZ);
    ASSERT_EQ(model.archive().structure(), runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN);
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE);
    // Format is unspecified for a .tar.gz wrapper (Swift's
    // detect_format_from_extension only knows .gz at the lowest layer; the
    // make() factory doesn't strip ".tar." pairs by itself).
    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    return 0;
}

int test_make_zip_archive() {
    MakeArgs args;
    args.url = "https://example.test/qwen-3b.zip";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.artifact_case(), runanywhere::v1::ModelInfo::kArchive);
    ASSERT_EQ(model.archive().type(), runanywhere::v1::ARCHIVE_TYPE_ZIP);
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE);
    return 0;
}

int test_make_multi_file_inferred() {
    // Multi-file artifacts arrive as a base URL without a recognized
    // archive suffix. The factory falls back to single_file in that case
    // (Swift parity); higher-level catalogs that know the artifact is
    // multi-file should override the artifact field after make().
    MakeArgs args;
    args.url = "https://example.test/qwen-vl-3b/";

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_TRUE(model.has_single_file());
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    return 0;
}

int test_make_request_overrides() {
    // Caller supplies an explicit framework and category; the factory should
    // honour those overrides.
    MakeArgs args;
    args.url = "https://example.test/model.bin";
    args.has_framework = true;
    args.framework = runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
    args.has_category = true;
    args.category = runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
    args.has_source = true;
    args.source = runanywhere::v1::MODEL_SOURCE_BUILT_IN;

    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(make_proto(args, &model));

    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS);
    ASSERT_EQ(model.category(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    ASSERT_EQ(model.source(), runanywhere::v1::MODEL_SOURCE_BUILT_IN);
    ASSERT_EQ(model.context_length(), 2048);
    return 0;
}

// Disk-probe tests — exercise rac_path_is_non_empty_directory directly.
// The make() factory itself never sets local_path so the probe wouldn't
// fire there, but the helper is reachable as a public API for SDKs and
// future make() variants that accept localPath.
int test_path_probe_with_callback() {
    mock_install_adapter(/*with_dir_probe=*/true, /*with_list_dir=*/false);
    g_mock_state.dir_probe_mode = 1;  // Returns RAC_TRUE.

    rac_bool_t r = rac_path_is_non_empty_directory("/tmp/whatever");
    ASSERT_EQ(r, RAC_TRUE);
    ASSERT_EQ(g_mock_state.dir_probe_calls, 1);
    ASSERT_EQ(g_mock_state.list_dir_calls, 0);

    g_mock_state.dir_probe_mode = 2;  // Returns RAC_FALSE.
    r = rac_path_is_non_empty_directory("/tmp/whatever");
    ASSERT_EQ(r, RAC_FALSE);

    mock_clear_adapter();
    return 0;
}

int test_path_probe_fallback_to_list_directory() {
    mock_install_adapter(/*with_dir_probe=*/false, /*with_list_dir=*/true);

    // Empty directory case → 0 entries → RAC_FALSE.
    g_mock_state.list_dir_returns_entry = false;
    rac_bool_t r = rac_path_is_non_empty_directory("/tmp/empty-dir");
    ASSERT_EQ(r, RAC_FALSE);
    ASSERT_EQ(g_mock_state.list_dir_calls, 1);

    // Non-empty directory case → 1 entry → RAC_TRUE.
    g_mock_state.list_dir_returns_entry = true;
    r = rac_path_is_non_empty_directory("/tmp/has-entries");
    ASSERT_EQ(r, RAC_TRUE);
    ASSERT_EQ(g_mock_state.list_dir_calls, 2);

    mock_clear_adapter();
    return 0;
}

int test_path_probe_no_callbacks() {
    mock_install_adapter(/*with_dir_probe=*/false, /*with_list_dir=*/false);

    rac_bool_t r = rac_path_is_non_empty_directory("/tmp/whatever");
    ASSERT_EQ(r, RAC_FALSE);

    mock_clear_adapter();
    return 0;
}

int test_path_probe_null_path() {
    mock_install_adapter(/*with_dir_probe=*/true, /*with_list_dir=*/true);
    g_mock_state.dir_probe_mode = 1;

    rac_bool_t r = rac_path_is_non_empty_directory(nullptr);
    ASSERT_EQ(r, RAC_FALSE);
    // Empty path → RAC_FALSE without any callback firing.
    ASSERT_EQ(g_mock_state.dir_probe_calls, 0);

    r = rac_path_is_non_empty_directory("");
    ASSERT_EQ(r, RAC_FALSE);
    ASSERT_EQ(g_mock_state.dir_probe_calls, 0);

    mock_clear_adapter();
    return 0;
}

// Negative paths.
int test_null_out_pointer() {
    rac_result_t rc = rac_model_info_make_proto(nullptr, 0, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

int test_invalid_input_bytes() {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_model_info_make_proto(nullptr, 42, &out);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&out);
    return 0;
}

int test_empty_request_default_result() {
    // Empty request → empty url → empty id/name → SINGLE_FILE artifact and
    // UNKNOWN framework / AUDIO category fallback.
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_model_info_make_proto(nullptr, 0, &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    runanywhere::v1::ModelInfo model;
    ASSERT_TRUE(model.ParseFromArray(out.data, static_cast<int>(out.size)));
    ASSERT_EQ(model.id(), std::string(""));
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN);
    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    ASSERT_TRUE(model.has_single_file());
    ASSERT_EQ(model.source(), runanywhere::v1::MODEL_SOURCE_REMOTE);
    rac_proto_buffer_free(&out);
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; model_info_make_proto tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {.name = "make_gguf_single_file", .fn = test_make_gguf_single_file},
        {.name = "make_onnx_single_file", .fn = test_make_onnx_single_file},
        {.name = "make_mlmodelc_single_file", .fn = test_make_mlmodelc_single_file},
        {.name = "make_safetensors_single_file", .fn = test_make_safetensors_single_file},
        {.name = "make_tar_gz_archive", .fn = test_make_tar_gz_archive},
        {.name = "make_zip_archive", .fn = test_make_zip_archive},
        {.name = "make_multi_file_inferred", .fn = test_make_multi_file_inferred},
        {.name = "make_request_overrides", .fn = test_make_request_overrides},
        {.name = "path_probe_with_callback", .fn = test_path_probe_with_callback},
        {.name = "path_probe_fallback_to_list_directory",
         .fn = test_path_probe_fallback_to_list_directory},
        {.name = "path_probe_no_callbacks", .fn = test_path_probe_no_callbacks},
        {.name = "path_probe_null_path", .fn = test_path_probe_null_path},
        {.name = "null_out_pointer", .fn = test_null_out_pointer},
        {.name = "invalid_input_bytes", .fn = test_invalid_input_bytes},
        {.name = "empty_request_default_result", .fn = test_empty_request_default_result},
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
