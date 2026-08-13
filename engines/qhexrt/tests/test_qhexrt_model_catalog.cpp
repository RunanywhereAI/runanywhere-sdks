/** QHexRT device policy and catalog facade tests. */

#include "qhexrt_model_catalog_internal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_set>

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/qhexrt/rac_qhexrt.h"

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

namespace {

#define ASSERT_TRUE(condition)                                                                   \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #condition, __FILE__, __LINE__); \
            return 1;                                                                            \
        }                                                                                        \
    } while (0)

#define ASSERT_EQ(actual, expected)                                                       \
    do {                                                                                  \
        if (!((actual) == (expected))) {                                                  \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #actual, #expected, \
                         __FILE__, __LINE__);                                             \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

int test_supported_arch_policy() {
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V75), RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V79), RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V81), RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V68), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V69), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(RAC_QHEXRT_HEXAGON_ARCH_V73), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_arch_is_supported(static_cast<rac_qhexrt_hexagon_arch_t>(83)), RAC_FALSE);
    ASSERT_EQ(std::string(rac_qhexrt_arch_name(RAC_QHEXRT_HEXAGON_ARCH_V75)), std::string("v75"));
    ASSERT_EQ(std::string(rac_qhexrt_arch_name(RAC_QHEXRT_HEXAGON_ARCH_V79)), std::string("v79"));
    ASSERT_EQ(std::string(rac_qhexrt_arch_name(RAC_QHEXRT_HEXAGON_ARCH_V81)), std::string("v81"));
    ASSERT_EQ(std::string(rac_qhexrt_arch_name(static_cast<rac_qhexrt_hexagon_arch_t>(83))),
              std::string("unknown"));

    rac_qhexrt_device_info_t engine{};
    ASSERT_EQ(rac_qhexrt_probe(&engine), RAC_SUCCESS);
    ASSERT_EQ(engine.supported, rac_qhexrt_arch_is_supported(engine.hexagon_arch));
    ASSERT_TRUE(std::strlen(rac_qhexrt_arch_name(engine.hexagon_arch)) > 0);
    return 0;
}

int test_native_catalog_owns_arch_and_auth_policy() {
    // Expectations come from the policy table itself rather than three
    // hand-copied sets. Those sets are what drifted: lfm2_5_2_6b and the three
    // cosmos3_edge_* rows were each granted archs the test still denied, so the
    // test failed on a correct catalog. Reading the table makes that class of
    // mismatch impossible while still checking that the public lookups agree
    // with the policy the catalog actually stores.
    const size_t row_count = rac_qhexrt_catalog_model_count();
    ASSERT_TRUE(row_count > 0);

    const rac_qhexrt_hexagon_arch_t arches[] = {
        RAC_QHEXRT_HEXAGON_ARCH_V75,
        RAC_QHEXRT_HEXAGON_ARCH_V79,
        RAC_QHEXRT_HEXAGON_ARCH_V81,
    };

    // The union of every arch bit this test actually enumerates. A row whose
    // mask sets a bit outside this union is unreachable on every supported
    // device, yet the per-arch loop below would still agree with the lookups
    // and stay green. Catches a stray bit, a mixed mask like kV81 | (1U << 3),
    // and an arch added to the table without being added to `arches`.
    uint8_t known_arch_bits = 0;
    for (const rac_qhexrt_hexagon_arch_t arch : arches) {
        known_arch_bits |= rac::qhexrt::catalog::policy_arch_bit(arch);
    }

    // Row ids must be unique: find_model_policy() stops at the first match, so a
    // duplicated id silently makes the second row dead policy. The deleted
    // `all.size() == model_count()` union guard used to reject this implicitly.
    std::unordered_set<std::string> seen_ids;

    size_t private_row_count = 0;
    for (size_t i = 0; i < row_count; ++i) {
        rac::qhexrt::catalog::PolicyRow row{};
        // Also the count check the old `all.size() == model_count()` guard was
        // reaching for, but done per index: a row that is added, removed or
        // renamed changes what this loop reads, whereas a set union could stay
        // the same size across an add-plus-remove.
        ASSERT_TRUE(rac::qhexrt::catalog::policy_row_at(i, &row));
        ASSERT_TRUE(row.id != nullptr && std::strlen(row.id) > 0);
        ASSERT_TRUE(seen_ids.insert(std::string(row.id)).second);
        ASSERT_EQ(rac_qhexrt_catalog_model_is_known(row.id), RAC_TRUE);

        // Every row must be reachable on at least one arch, or it can never be
        // registered on any device, and every bit it sets must be an arch this
        // test knows about, or "reachable" is a claim about nothing.
        ASSERT_TRUE(row.arch_mask != 0);
        ASSERT_EQ(static_cast<uint8_t>(row.arch_mask & ~known_arch_bits), static_cast<uint8_t>(0));

        for (const rac_qhexrt_hexagon_arch_t arch : arches) {
            const bool expected =
                (row.arch_mask & rac::qhexrt::catalog::policy_arch_bit(arch)) != 0;
            ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch(row.id, arch),
                      expected ? RAC_TRUE : RAC_FALSE);
        }

        ASSERT_EQ(rac_qhexrt_catalog_model_requires_hf_auth(row.id),
                  row.requires_hf_auth ? RAC_TRUE : RAC_FALSE);
        if (row.requires_hf_auth) {
            ++private_row_count;
        }
    }

    // The auth gate stays pinned by intent: hosting a model behind a gated HF
    // repo should be a deliberate act, so the count is asserted rather than
    // derived. kitten_nano_0_8_varlen is the only private row today.
    ASSERT_EQ(private_row_count, static_cast<size_t>(1));
    ASSERT_EQ(rac_qhexrt_catalog_model_requires_hf_auth("kitten_nano_0_8_varlen"), RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_catalog_model_is_known("not-in-product-catalog"), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_catalog_model_requires_hf_auth("not-in-product-catalog"), RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch("qwen3_5_0_8b", RAC_QHEXRT_HEXAGON_ARCH_V73),
              RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch("qwen3_0_6b", RAC_QHEXRT_HEXAGON_ARCH_V79),
              RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch("nv_embedqa_1b", RAC_QHEXRT_HEXAGON_ARCH_V79),
              RAC_FALSE);
    ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch("nv_rerankqa_1b", RAC_QHEXRT_HEXAGON_ARCH_V79),
              RAC_FALSE);
    ASSERT_EQ(
        rac_qhexrt_catalog_model_supports_arch("nemotron_nano_8b", RAC_QHEXRT_HEXAGON_ARCH_V75),
        RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch("nemotron_ocr", RAC_QHEXRT_HEXAGON_ARCH_V81),
              RAC_TRUE);
    ASSERT_EQ(rac_qhexrt_catalog_model_requires_hf_auth("nv_embedqa_1b"), RAC_FALSE);
    return 0;
}

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)

void install_noop_adapter() {
    static rac_platform_adapter_t adapter;
    std::memset(&adapter, 0, sizeof(adapter));
    rac_set_platform_adapter(&adapter);
}

runanywhere::v1::RegisterModelFromUrlRequest make_request(const std::string& id,
                                                          const std::string& url) {
    runanywhere::v1::RegisterModelFromUrlRequest request;
    request.set_id(id);
    request.set_name("App-owned QHexRT model");
    request.set_url(url);
    request.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT);
    request.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    request.set_source(runanywhere::v1::MODEL_SOURCE_REMOTE);
    request.set_memory_required_bytes(987654321);
    request.set_download_size_bytes(876543210);
    request.set_context_length(4096);
    request.set_supports_thinking(true);
    request.set_supports_lora(false);
    request.set_description("Presentation metadata remains app-owned");
    return request;
}

std::string serialize(const runanywhere::v1::RegisterModelFromUrlRequest& request) {
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        std::fprintf(stderr, "Unable to serialize QHexRT catalog test request\n");
        std::abort();
    }
    return bytes;
}

void remove_model(const std::string& id) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry != nullptr) {
        (void)rac_model_registry_remove_proto(registry, id.c_str());
    }
}

bool registry_contains(const std::string& id) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return false;
    }
    uint8_t* bytes = nullptr;
    size_t size = 0;
    const rac_result_t rc = rac_model_registry_get_proto(registry, id.c_str(), &bytes, &size);
    rac_model_registry_proto_free(bytes);
    return rc == RAC_SUCCESS;
}

int test_ineligible_does_not_mutate_registry() {
    install_noop_adapter();
    const std::string id = "qwen3_vl";
    remove_model(id);
    const std::string bytes = serialize(make_request(id, "https://cdn.example.test/model.json"));
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_TRUE;
    const rac_result_t rc = rac::qhexrt::catalog::register_for_arch_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), RAC_QHEXRT_HEXAGON_ARCH_V81,
        RAC_TRUE, &registered, &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(out.status, RAC_SUCCESS);
    ASSERT_EQ(out.size, static_cast<size_t>(0));
    ASSERT_EQ(registered, RAC_FALSE);
    ASSERT_TRUE(!registry_contains(id));
    rac_proto_buffer_free(&out);
    return 0;
}

int test_eligible_preserves_app_definition() {
    install_noop_adapter();
    const std::string id = "qwen3_5_0_8b";
    remove_model(id);
    const auto request = make_request(id, "https://cdn.example.test/model.json");
    const std::string bytes = serialize(request);
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_FALSE;
    const rac_result_t rc = rac::qhexrt::catalog::register_for_arch_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), RAC_QHEXRT_HEXAGON_ARCH_V81,
        RAC_TRUE, &registered, &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(out.status, RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_TRUE);

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(saved.ParseFromArray(out.data, static_cast<int>(out.size)));
    ASSERT_EQ(saved.id(), request.id());
    ASSERT_EQ(saved.name(), request.name());
    ASSERT_EQ(saved.download_url(), request.url());
    ASSERT_EQ(saved.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT);
    ASSERT_EQ(saved.category(), request.category());
    ASSERT_EQ(saved.memory_required_bytes(), request.memory_required_bytes());
    ASSERT_EQ(saved.download_size_bytes(), request.download_size_bytes());
    ASSERT_EQ(saved.context_length(), request.context_length());
    ASSERT_EQ(saved.supports_thinking(), request.supports_thinking());
    ASSERT_TRUE(saved.has_metadata());
    ASSERT_EQ(saved.metadata().description(), request.description());
    ASSERT_TRUE(registry_contains(id));

    rac_proto_buffer_free(&out);
    remove_model(id);
    return 0;
}

int test_unavailable_engine_does_not_accept_catalog_rows() {
    install_noop_adapter();
    const std::string id = "qwen3_5_0_8b";
    remove_model(id);
    const std::string bytes = serialize(make_request(id, "https://cdn.example.test/model.json"));
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_TRUE;
    ASSERT_EQ(rac::qhexrt::catalog::register_for_arch_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                  RAC_QHEXRT_HEXAGON_ARCH_V81, RAC_FALSE, &registered, &out),
              RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_FALSE);
    ASSERT_EQ(out.size, static_cast<size_t>(0));
    ASSERT_TRUE(!registry_contains(id));
    rac_proto_buffer_free(&out);
    return 0;
}

int test_public_catalog_abi_skips_stub_or_unregistered_backend() {
    install_noop_adapter();
    const std::string id = "qwen3_5_0_8b";
    remove_model(id);
    const std::string bytes = serialize(make_request(id, "https://cdn.example.test/model.json"));
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_TRUE;
    ASSERT_EQ(rac_qhexrt_catalog_register_model_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &registered, &out),
              RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_FALSE);
    ASSERT_EQ(out.size, static_cast<size_t>(0));
    ASSERT_TRUE(!registry_contains(id));
    rac_proto_buffer_free(&out);
    return 0;
}

const char* kHfTree = R"JSON([
  {"type":"file","path":"v75/test.json","size":11},
  {"type":"file","path":"v75/context.bin","size":12},
  {"type":"file","path":"v81/test.json","size":21},
  {"type":"file","path":"v81/context.bin","size":22,
   "lfs":{"oid":"abc123","size":22}}
])JSON";

int g_hf_request_count = 0;

rac_result_t fake_hf_tree(void*, const rac_http_request_t* request, rac_http_response_t* response) {
    if (request == nullptr || request->url == nullptr || response == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ++g_hf_request_count;
    std::memset(response, 0, sizeof(*response));
    if (std::string(request->url)
            .find("/api/models/runanywhere/test_HNPU/tree/main?recursive=true") ==
        std::string::npos) {
        response->status = 404;
        return RAC_SUCCESS;
    }
    const size_t size = std::strlen(kHfTree);
    response->body_bytes = static_cast<uint8_t*>(std::malloc(size));
    if (response->body_bytes == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::memcpy(response->body_bytes, kHfTree, size);
    response->body_len = size;
    response->status = 200;
    return RAC_SUCCESS;
}

const rac_http_transport_ops_t kFakeTransport = {
    fake_hf_tree, nullptr, nullptr, nullptr, nullptr,
};

int test_logical_hf_ref_selects_v81_before_commons_registration() {
    install_noop_adapter();
    ASSERT_EQ(rac_http_transport_register(&kFakeTransport, nullptr), RAC_SUCCESS);
    const std::string id = "qwen3_5_0_8b";
    remove_model(id);
    const auto request = make_request(id, "https://huggingface.co/runanywhere/test_HNPU/test.json");
    const std::string bytes = serialize(request);
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_FALSE;
    const rac_result_t rc = rac::qhexrt::catalog::register_for_arch_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), RAC_QHEXRT_HEXAGON_ARCH_V81,
        RAC_TRUE, &registered, &out);
    ASSERT_EQ(rc, RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_TRUE);

    runanywhere::v1::ModelInfo saved;
    ASSERT_TRUE(saved.ParseFromArray(out.data, static_cast<int>(out.size)));
    ASSERT_TRUE(saved.has_multi_file());
    ASSERT_EQ(saved.multi_file().files_size(), 2);
    ASSERT_EQ(saved.multi_file().files(0).filename(), std::string("test.json"));
    ASSERT_TRUE(saved.multi_file().files(0).url().find("/resolve/main/v81/test.json") !=
                std::string::npos);
    ASSERT_EQ(saved.multi_file().files(1).filename(), std::string("context.bin"));
    ASSERT_EQ(saved.multi_file().files(1).checksum_sha256(), std::string("abc123"));

    rac_proto_buffer_free(&out);
    remove_model(id);
    rac_http_transport_register(nullptr, nullptr);
    return 0;
}

int test_public_model_registers_without_token() {
    install_noop_adapter();
    ASSERT_EQ(rac_http_transport_register(&kFakeTransport, nullptr), RAC_SUCCESS);
    const std::string id = "qwen3_0_6b";
    remove_model(id);
    const std::string bytes =
        serialize(make_request(id, "https://huggingface.co/runanywhere/test_HNPU/test.json"));
    rac_http_hf_token_set("");
    ASSERT_EQ(rac_http_hf_token_is_configured(), RAC_FALSE);
    g_hf_request_count = 0;
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_TRUE;
    ASSERT_EQ(rac::qhexrt::catalog::register_for_arch_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                  RAC_QHEXRT_HEXAGON_ARCH_V81, RAC_TRUE, &registered, &out),
              RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_TRUE);
    ASSERT_EQ(g_hf_request_count, 2);
    ASSERT_TRUE(registry_contains(id));
    rac_proto_buffer_free(&out);

    remove_model(id);
    rac_http_hf_token_set(nullptr);
    rac_http_transport_register(nullptr, nullptr);
    return 0;
}

int test_invalid_definitions_fail_closed() {
    install_noop_adapter();
    auto request = make_request("not-in-product-catalog", "https://cdn.example.test/model.json");
    std::string bytes = serialize(request);
    rac_proto_buffer_t out{};
    rac_bool_t registered = RAC_TRUE;
    ASSERT_EQ(rac::qhexrt::catalog::register_for_arch_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                  RAC_QHEXRT_HEXAGON_ARCH_V81, RAC_TRUE, &registered, &out),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(registered, RAC_FALSE);
    rac_proto_buffer_free(&out);

    request.clear_id();
    bytes = serialize(request);
    registered = RAC_TRUE;
    ASSERT_EQ(rac::qhexrt::catalog::register_for_arch_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                  RAC_QHEXRT_HEXAGON_ARCH_V81, RAC_TRUE, &registered, &out),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(registered, RAC_FALSE);
    rac_proto_buffer_free(&out);
    return 0;
}

#endif  // RAC_QHEXRT_HAVE_PROTOBUF

}  // namespace

int main() {
    struct TestCase {
        const char* name;
        int (*run)();
    };
    static const TestCase tests[] = {
        {"supported_arch_policy", test_supported_arch_policy},
        {"native_catalog_owns_arch_and_auth_policy", test_native_catalog_owns_arch_and_auth_policy},
#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
        {"ineligible_does_not_mutate_registry", test_ineligible_does_not_mutate_registry},
        {"eligible_preserves_app_definition", test_eligible_preserves_app_definition},
        {"unavailable_engine_does_not_accept_catalog_rows",
         test_unavailable_engine_does_not_accept_catalog_rows},
        {"public_catalog_abi_skips_stub_or_unregistered_backend",
         test_public_catalog_abi_skips_stub_or_unregistered_backend},
        {"logical_hf_ref_selects_v81_before_commons_registration",
         test_logical_hf_ref_selects_v81_before_commons_registration},
        {"public_model_registers_without_token", test_public_model_registers_without_token},
        {"invalid_definitions_fail_closed", test_invalid_definitions_fail_closed},
#endif
    };

    int failures = 0;
    for (const TestCase& test : tests) {
        std::printf("RUN  %s\n", test.name);
        const int rc = test.run();
        std::printf("%s %s\n", rc == 0 ? "PASS" : "FAIL", test.name);
        failures += rc == 0 ? 0 : 1;
    }
    if (failures != 0) {
        std::fprintf(stderr, "%d QHexRT catalog test(s) failed\n", failures);
        return 1;
    }
    std::printf("All %zu QHexRT catalog tests passed.\n", sizeof(tests) / sizeof(tests[0]));
    return 0;
}
