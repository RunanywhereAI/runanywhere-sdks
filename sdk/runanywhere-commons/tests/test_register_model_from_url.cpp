/**
 * @file test_register_model_from_url.cpp
 * @brief Parity tests for rac_register_model_from_url_proto (P2-T6).
 *
 * Exercises the canonical "register a model from a URL" entry point — the
 * single-call composition of rac_model_info_make_proto (P2-T4) and the
 * existing registry persistence path. Verifies that the returned ModelInfo
 * round-trips through rac_model_registry_get_proto by id.
 *
 * Pattern mirrors test_model_info_make_proto.cpp: mock the platform adapter
 * for the disk probe path so make() runs the same way it does in production.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
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

// ---------------------------------------------------------------------------
// Mock platform adapter — required because rac_model_info_make_proto runs the
// disk probe via rac_get_platform_adapter(). For a freshly-made model the
// local_path is empty so the probe never fires, but we install a no-op
// adapter to keep behaviour deterministic.
// ---------------------------------------------------------------------------
void install_noop_adapter() {
    static rac_platform_adapter_t adapter;
    std::memset(&adapter, 0, sizeof(adapter));
    rac_set_platform_adapter(&adapter);
}

void clear_adapter() {
    rac_set_platform_adapter(nullptr);
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------
struct RegisterArgs {
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

bool register_proto(const RegisterArgs& args, runanywhere::v1::ModelInfo* out) {
    runanywhere::v1::RegisterModelFromUrlRequest request;
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
        std::fprintf(stderr, "failed to serialize RegisterModelFromUrlRequest\n");
        return false;
    }

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_register_model_from_url_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buffer);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_register_model_from_url_proto rc=%d\n", rc);
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

// Read back a model by id via rac_model_registry_get_proto on the global
// registry. Returns true when the model is found and parsed.
bool read_back_by_id(const std::string& id, runanywhere::v1::ModelInfo* out) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        std::fprintf(stderr, "rac_get_model_registry returned null\n");
        return false;
    }
    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t rc = rac_model_registry_get_proto(registry, id.c_str(), &bytes, &size);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_model_registry_get_proto rc=%d for id=%s\n", rc, id.c_str());
        return false;
    }
    bool parsed = out->ParseFromArray(bytes, static_cast<int>(size));
    rac_model_registry_proto_free(bytes);
    return parsed;
}

// Cleanup helper — best-effort remove by id so tests don't bleed state.
void remove_by_id(const std::string& id) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry)
        return;
    (void)rac_model_registry_remove_proto(registry, id.c_str());
}

// ---------------------------------------------------------------------------
// End-to-end test cases.
// ---------------------------------------------------------------------------
int test_register_gguf_round_trip() {
    install_noop_adapter();

    RegisterArgs args;
    args.url = "https://example.test/llama-7b-chat.Q4_K_M.gguf";
    args.name = "Llama 7B Chat Q4_K_M";

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(register_proto(args, &saved));

    // Verify the saved entry honours the make() defaults.
    ASSERT_EQ(saved.id(), std::string("llama-7b-chat.Q4_K_M"));
    ASSERT_EQ(saved.name(), std::string("Llama 7B Chat Q4_K_M"));
    ASSERT_EQ(saved.format(), runanywhere::v1::MODEL_FORMAT_GGUF);
    ASSERT_EQ(saved.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_EQ(saved.category(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    ASSERT_EQ(saved.context_length(), 2048);
    ASSERT_EQ(saved.download_url(), args.url);
    ASSERT_EQ(saved.source(), runanywhere::v1::MODEL_SOURCE_REMOTE);
    ASSERT_TRUE(saved.has_single_file());
    ASSERT_EQ(saved.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    ASSERT_TRUE(saved.created_at_unix_ms() > 0);
    ASSERT_TRUE(saved.updated_at_unix_ms() > 0);

    // End-to-end: read back through rac_model_registry_get_proto and verify
    // the saved entry equals what we just stored.
    runanywhere::v1::ModelInfo retrieved;
    ASSERT_TRUE(read_back_by_id(saved.id(), &retrieved));

    ASSERT_EQ(retrieved.id(), saved.id());
    ASSERT_EQ(retrieved.name(), saved.name());
    ASSERT_EQ(retrieved.format(), saved.format());
    ASSERT_EQ(retrieved.framework(), saved.framework());
    ASSERT_EQ(retrieved.category(), saved.category());
    ASSERT_EQ(retrieved.context_length(), saved.context_length());
    ASSERT_EQ(retrieved.download_url(), saved.download_url());
    ASSERT_EQ(retrieved.source(), saved.source());
    ASSERT_EQ(retrieved.has_single_file(), saved.has_single_file());
    ASSERT_EQ(retrieved.artifact_type(), saved.artifact_type());

    remove_by_id(saved.id());
    clear_adapter();
    return 0;
}

int test_register_archive_round_trip() {
    install_noop_adapter();

    RegisterArgs args;
    args.url = "https://example.test/sherpa-onnx-whisper-tiny.tar.gz";
    args.name = "Whisper Tiny ONNX";
    args.has_framework = true;
    args.framework = runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
    args.has_category = true;
    args.category = runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(register_proto(args, &saved));

    ASSERT_EQ(saved.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
    ASSERT_EQ(saved.category(), runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION);
    ASSERT_EQ(saved.artifact_case(), runanywhere::v1::ModelInfo::kArchive);
    ASSERT_TRUE(saved.has_archive());
    ASSERT_EQ(saved.archive().type(), runanywhere::v1::ARCHIVE_TYPE_TAR_GZ);
    ASSERT_EQ(saved.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE);

    // Round-trip via registry get.
    runanywhere::v1::ModelInfo retrieved;
    ASSERT_TRUE(read_back_by_id(saved.id(), &retrieved));
    ASSERT_EQ(retrieved.id(), saved.id());
    ASSERT_EQ(retrieved.framework(), saved.framework());
    ASSERT_EQ(retrieved.category(), saved.category());
    ASSERT_TRUE(retrieved.has_archive());
    ASSERT_EQ(retrieved.archive().type(), saved.archive().type());

    remove_by_id(saved.id());
    clear_adapter();
    return 0;
}

int test_register_with_source_override() {
    install_noop_adapter();

    RegisterArgs args;
    args.url = "https://example.test/whisper-base.en.onnx";
    args.has_source = true;
    args.source = runanywhere::v1::MODEL_SOURCE_LOCAL;

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(register_proto(args, &saved));
    ASSERT_EQ(saved.source(), runanywhere::v1::MODEL_SOURCE_LOCAL);
    // Name auto-generated.
    ASSERT_TRUE(!saved.name().empty());

    // Round-trip.
    runanywhere::v1::ModelInfo retrieved;
    ASSERT_TRUE(read_back_by_id(saved.id(), &retrieved));
    ASSERT_EQ(retrieved.source(), saved.source());

    remove_by_id(saved.id());
    clear_adapter();
    return 0;
}

// ---------------------------------------------------------------------------
// Negative paths.
// ---------------------------------------------------------------------------
int test_null_out_pointer() {
    rac_result_t rc = rac_register_model_from_url_proto(nullptr, 0, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

int test_invalid_input_bytes() {
    install_noop_adapter();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_register_model_from_url_proto(nullptr, 42, &out);
    ASSERT_EQ(rc, RAC_ERROR_DECODING_ERROR);
    rac_proto_buffer_free(&out);
    clear_adapter();
    return 0;
}

// Empty input (size==0) parses to a default-zeroed request with an empty url.
// That must be rejected rather than persisting a phantom model keyed by the
// empty-string id (commons-121).
int test_empty_input_rejected() {
    install_noop_adapter();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_register_model_from_url_proto(nullptr, 0, &out);
    ASSERT_EQ(rc, RAC_ERROR_INVALID_ARGUMENT);
    rac_proto_buffer_free(&out);

    // The empty-string id must not have leaked into the registry.
    rac_model_registry_handle_t registry = rac_get_model_registry();
    ASSERT_TRUE(registry != nullptr);
    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t get_rc = rac_model_registry_get_proto(registry, "", &bytes, &size);
    ASSERT_EQ(get_rc, RAC_ERROR_NOT_FOUND);
    if (bytes) {
        rac_model_registry_proto_free(bytes);
    }

    clear_adapter();
    return 0;
}

// An explicitly empty url in a non-empty request is rejected the same way.
int test_empty_url_rejected() {
    install_noop_adapter();

    RegisterArgs args;
    args.url = "";
    args.name = "Phantom";

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(!register_proto(args, &saved));

    clear_adapter();
    return 0;
}

// ---------------------------------------------------------------------------
// Regression: merge-not-replace on re-registration (commons-014).
//
// When the catalog seed re-runs on app launch, registerModel() must NOT
// clobber the download-completion state set on a prior launch. Previously
// the Android example carried a `existingRegistryIds()` skip-pass to paper
// over this; the fix moves the merge into commons so all SDKs benefit and
// the example workaround can be deleted.
// ---------------------------------------------------------------------------
int test_re_register_preserves_download_state() {
    install_noop_adapter();

    // First register: simulates a fresh catalog seed.
    RegisterArgs args;
    args.url = "https://example.test/preserve-llama.Q4_K_M.gguf";
    args.name = "Preserve Test";

    runanywhere::v1::ModelInfo first;
    ASSERT_TRUE(register_proto(args, &first));
    ASSERT_TRUE(!first.is_downloaded());
    ASSERT_TRUE(first.local_path().empty());

    // Simulate the post-download self-heal: mark is_downloaded + local_path
    // + checksum_sha256 via the canonical update path.
    {
        runanywhere::v1::ModelInfo mutated = first;
        mutated.set_local_path("/tmp/preserve-llama.Q4_K_M.gguf");
        mutated.set_is_downloaded(true);
        mutated.set_is_available(true);
        mutated.set_checksum_sha256(
            "abc123def4567890abc123def4567890abc123def4567890abc123def4567890");
        mutated.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
        std::string mutated_bytes;
        ASSERT_TRUE(mutated.SerializeToString(&mutated_bytes));
        rac_model_registry_handle_t registry = rac_get_model_registry();
        ASSERT_TRUE(registry != nullptr);
        rac_result_t update_rc = rac_model_registry_update_proto(
            registry, reinterpret_cast<const uint8_t*>(mutated_bytes.data()), mutated_bytes.size());
        ASSERT_EQ(update_rc, RAC_SUCCESS);
    }

    // Sanity check the mutation landed.
    runanywhere::v1::ModelInfo after_update;
    ASSERT_TRUE(read_back_by_id(first.id(), &after_update));
    ASSERT_TRUE(after_update.is_downloaded());
    ASSERT_EQ(after_update.local_path(), std::string("/tmp/preserve-llama.Q4_K_M.gguf"));
    ASSERT_EQ(after_update.checksum_sha256(),
              std::string("abc123def4567890abc123def4567890abc123def4567890abc123def4567890"));

    // Second register: same URL/name (re-seed). Without the merge fix this
    // would reset is_downloaded=false, clear local_path, and drop the
    // checksum. With the fix all three survive.
    runanywhere::v1::ModelInfo re_registered;
    ASSERT_TRUE(register_proto(args, &re_registered));
    ASSERT_EQ(re_registered.id(), first.id());
    ASSERT_TRUE(re_registered.is_downloaded());
    ASSERT_EQ(re_registered.local_path(), std::string("/tmp/preserve-llama.Q4_K_M.gguf"));
    ASSERT_EQ(re_registered.checksum_sha256(),
              std::string("abc123def4567890abc123def4567890abc123def4567890abc123def4567890"));

    // Round-trip via registry get — same invariants.
    runanywhere::v1::ModelInfo retrieved;
    ASSERT_TRUE(read_back_by_id(first.id(), &retrieved));
    ASSERT_TRUE(retrieved.is_downloaded());
    ASSERT_EQ(retrieved.local_path(), std::string("/tmp/preserve-llama.Q4_K_M.gguf"));
    ASSERT_EQ(retrieved.checksum_sha256(),
              std::string("abc123def4567890abc123def4567890abc123def4567890abc123def4567890"));

    remove_by_id(first.id());
    clear_adapter();
    return 0;
}

// Override path: when the caller explicitly sets a runtime field, the
// existing value must NOT be preserved (the explicit set wins).
int test_re_register_allows_explicit_override() {
    install_noop_adapter();

    RegisterArgs args;
    args.url = "https://example.test/override-llama.Q4_K_M.gguf";
    args.name = "Override Test";

    runanywhere::v1::ModelInfo first;
    ASSERT_TRUE(register_proto(args, &first));

    // Stamp a local_path.
    {
        runanywhere::v1::ModelInfo mutated = first;
        mutated.set_local_path("/tmp/old-path.gguf");
        mutated.set_is_downloaded(true);
        std::string mutated_bytes;
        ASSERT_TRUE(mutated.SerializeToString(&mutated_bytes));
        rac_model_registry_handle_t registry = rac_get_model_registry();
        ASSERT_TRUE(registry != nullptr);
        ASSERT_EQ(rac_model_registry_update_proto(
                      registry, reinterpret_cast<const uint8_t*>(mutated_bytes.data()),
                      mutated_bytes.size()),
                  RAC_SUCCESS);
    }

    // Caller-driven explicit reset via the lower-level register_proto path
    // (the canonical re-set escape hatch — populate the fields you want to
    // overwrite on the inbound ModelInfo).
    {
        runanywhere::v1::ModelInfo replacement = first;
        replacement.set_local_path("");
        replacement.set_is_downloaded(false);
        replacement.set_is_available(false);
        replacement.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
        std::string bytes;
        ASSERT_TRUE(replacement.SerializeToString(&bytes));
        rac_model_registry_handle_t registry = rac_get_model_registry();
        ASSERT_EQ(rac_model_registry_register_proto(
                      registry, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()),
                  RAC_SUCCESS);
    }

    runanywhere::v1::ModelInfo retrieved;
    ASSERT_TRUE(read_back_by_id(first.id(), &retrieved));
    ASSERT_TRUE(!retrieved.is_downloaded());
    ASSERT_TRUE(retrieved.local_path().empty());

    remove_by_id(first.id());
    clear_adapter();
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("SKIP: RAC_HAVE_PROTOBUF not defined; register_model_from_url tests skipped.\n");
    return 0;
#else
    struct TestCase {
        const char* name;
        int (*fn)();
    };
    static const TestCase kTests[] = {
        {"register_gguf_round_trip", test_register_gguf_round_trip},
        {"register_archive_round_trip", test_register_archive_round_trip},
        {"register_with_source_override", test_register_with_source_override},
        {"null_out_pointer", test_null_out_pointer},
        {"invalid_input_bytes", test_invalid_input_bytes},
        {"empty_input_rejected", test_empty_input_rejected},
        {"empty_url_rejected", test_empty_url_rejected},
        {"re_register_preserves_download_state", test_re_register_preserves_download_state},
        {"re_register_allows_explicit_override", test_re_register_allows_explicit_override},
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
