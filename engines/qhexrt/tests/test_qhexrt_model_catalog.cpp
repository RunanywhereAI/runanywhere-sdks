/** QHexRT device policy and catalog facade tests. */

#include "qhexrt_model_catalog_internal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_set>

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/device/rac_npu_capability.h"
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
    static_assert(static_cast<int32_t>(RAC_HEXAGON_ARCH_V75) ==
                  static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V75));
    static_assert(static_cast<int32_t>(RAC_HEXAGON_ARCH_V79) ==
                  static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V79));
    static_assert(static_cast<int32_t>(RAC_HEXAGON_ARCH_V81) ==
                  static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V81));

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

    rac_npu_info_t legacy{};
    rac_qhexrt_device_info_t engine{};
    ASSERT_EQ(rac_npu_probe(&legacy), RAC_SUCCESS);
    ASSERT_EQ(rac_qhexrt_probe(&engine), RAC_SUCCESS);
    ASSERT_EQ(std::string(legacy.soc_model), std::string(engine.soc_model));
    ASSERT_EQ(legacy.soc_id, engine.soc_id);
    ASSERT_EQ(static_cast<int32_t>(legacy.hexagon_arch), static_cast<int32_t>(engine.hexagon_arch));
    ASSERT_EQ(legacy.qhexrt_supported, engine.supported);
    ASSERT_EQ(std::string(rac_hexagon_arch_name(legacy.hexagon_arch)),
              std::string(rac_qhexrt_arch_name(engine.hexagon_arch)));
    return 0;
}

int test_native_catalog_owns_arch_and_auth_policy() {
    const std::unordered_set<std::string> v75 = {
        "lfm2_5_230m",          "lfm2_5_350m",         "qwen3_0_6b",      "qwen3_5_0_8b",
        "qwen3_5_2b",           "ternary_bonsai_1_7b", "internvl3_5_1b",  "qwen3_vl",
        "nemotron_ocr",         "nemotron_ocr_v1",     "nemotron_parse",  "whisper_base",
        "whisper_small",        "moonshine_tiny",      "moonshine_base",  "parakeet_tdt_0_6b_v2",
        "parakeet_tdt_0_6b_v3", "parakeet_rnnt_1_1b",  "canary_1b_flash", "nemotron_asr_streaming",
        "melotts_en",           "kokoro_en",           "kitten_nano_0_8", "embeddinggemma_300m",
        "nv_embedqa_1b",        "nv_rerankqa_1b",      "siglip2_base",
    };
    const std::unordered_set<std::string> v79 = {
        "lfm2_5_230m",    "lfm2_5_350m",   "llama3_2_1b",
        "gemma4_e2b",     "phi_tiny_moe",  "qwen3_5_0_8b",
        "qwen3_5_2b",     "qwen3_5_4b",    "deepseek_r1_distill_qwen_1_5b",
        "internvl3_5_1b", "qwen3_vl",      "gemma4_e2b_vlm",
        "whisper_base",   "whisper_small", "moonshine_base",
        "moonshine_tiny", "melotts_en",    "embeddinggemma_300m",
        "siglip2_base",   "lama_dilated",
    };
    const std::unordered_set<std::string> v81 = {
        "qwen3_0_6b",
        "llama3_2_1b",
        "lfm2_5_230m",
        "lfm2_5_350m",
        "gemma4_e2b",
        "gemma4_e4b",
        "gemma3n_e4b",
        "phi_tiny_moe",
        "qwen3_5_0_8b",
        "qwen3_5_2b",
        "qwen3_5_4b",
        "deepseek_r1_distill_qwen_1_5b",
        "deepseek_r1_distill_qwen_7b",
        "ternary_bonsai_1_7b",
        "nemotron_nano_8b",
        "nemoguard_content_8b",
        "nemoguard_topic_8b",
        "qwen3_vl_2b_text",
        "internvl3_5_1b",
        "gemma4_e2b_vlm",
        "gemma4_e4b_vlm",
        "nemotron_nano_vl_8b",
        "whisper_base",
        "whisper_small",
        "moonshine_base",
        "moonshine_tiny",
        "parakeet_tdt_0_6b_v2",
        "parakeet_tdt_0_6b_v3",
        "parakeet_rnnt_1_1b",
        "canary_qwen_2_5b",
        "canary_1b_flash",
        "nemotron_asr_streaming",
        "kokoro_en",
        "melotts_en",
        "kitten_nano_0_8",
        "kitten_mini_0_1",
        "kitten_mini_0_8",
        "kitten_micro_0_8",
        "kitten_nano_0_2",
        "kitten_nano_0_1",
        "embeddinggemma_300m",
        "nv_embedqa_1b",
        "nv_rerankqa_1b",
        "nv_embedcode_7b",
        "llama_embed_nemotron_8b",
        "siglip2_base",
        "lama_dilated",
    };
    std::unordered_set<std::string> all = v75;
    all.insert(v79.begin(), v79.end());
    all.insert(v81.begin(), v81.end());
    ASSERT_EQ(all.size(), static_cast<size_t>(51));
    for (const std::string& id : all) {
        ASSERT_EQ(rac_qhexrt_catalog_model_is_known(id.c_str()), RAC_TRUE);
        ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch(id.c_str(), RAC_QHEXRT_HEXAGON_ARCH_V75),
                  v75.count(id) == 0 ? RAC_FALSE : RAC_TRUE);
        ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch(id.c_str(), RAC_QHEXRT_HEXAGON_ARCH_V79),
                  v79.count(id) == 0 ? RAC_FALSE : RAC_TRUE);
        ASSERT_EQ(rac_qhexrt_catalog_model_supports_arch(id.c_str(), RAC_QHEXRT_HEXAGON_ARCH_V81),
                  v81.count(id) == 0 ? RAC_FALSE : RAC_TRUE);
    }

    const std::unordered_set<std::string> private_ids = {
        "qwen3_0_6b",
        "llama_embed_nemotron_8b",
        "nv_embedcode_7b",
        "nv_embedqa_1b",
        "nv_rerankqa_1b",
        "nemotron_nano_8b",
        "nemoguard_content_8b",
        "nemoguard_topic_8b",
        "nemotron_nano_vl_8b",
        "nemotron_ocr",
        "nemotron_ocr_v1",
        "nemotron_parse",
        "parakeet_tdt_0_6b_v2",
        "parakeet_tdt_0_6b_v3",
        "parakeet_rnnt_1_1b",
        "canary_qwen_2_5b",
        "canary_1b_flash",
        "nemotron_asr_streaming",
        "kokoro_en",
        "kitten_nano_0_8",
        "kitten_mini_0_1",
        "kitten_mini_0_8",
        "kitten_micro_0_8",
        "kitten_nano_0_2",
        "kitten_nano_0_1",
    };
    ASSERT_EQ(private_ids.size(), static_cast<size_t>(25));
    for (const std::string& id : all) {
        ASSERT_EQ(rac_qhexrt_catalog_model_requires_hf_auth(id.c_str()),
                  private_ids.count(id) == 0 ? RAC_FALSE : RAC_TRUE);
    }
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
    ASSERT_EQ(saved.description(), request.description());
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

int test_private_model_skips_network_without_token_and_registers_with_token() {
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
    ASSERT_EQ(registered, RAC_FALSE);
    ASSERT_EQ(out.size, static_cast<size_t>(0));
    ASSERT_EQ(g_hf_request_count, 0);
    ASSERT_TRUE(!registry_contains(id));
    rac_proto_buffer_free(&out);

    rac_http_hf_token_set("test-token-never-logged");
    ASSERT_EQ(rac_http_hf_token_is_configured(), RAC_TRUE);
    registered = RAC_FALSE;
    ASSERT_EQ(rac::qhexrt::catalog::register_for_arch_proto(
                  reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                  RAC_QHEXRT_HEXAGON_ARCH_V81, RAC_TRUE, &registered, &out),
              RAC_SUCCESS);
    ASSERT_EQ(registered, RAC_TRUE);
    ASSERT_EQ(g_hf_request_count, 1);
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
        {"private_model_skips_network_without_token_and_registers_with_token",
         test_private_model_skips_network_without_token_and_registers_with_token},
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
