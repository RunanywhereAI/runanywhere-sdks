/**
 * @file test_model_assignment_proto.cpp
 * @brief Tests for model assignment proto-byte refresh/cache behavior.
 */

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"

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

struct FakeAssignmentTransport {
    std::vector<std::string> payloads;
    int call_count = 0;
    int32_t status_code = 200;
    rac_result_t callback_result = RAC_SUCCESS;
    rac_result_t response_result = RAC_SUCCESS;
    std::string error_message;
    bool saw_requires_auth = false;
    std::vector<std::string> endpoints;
};

template <typename Message>
std::string serialize_to_string(const Message& message) {
    std::string bytes;
    const bool serialized = message.SerializeToString(&bytes);
    if (!serialized) {
        bytes.clear();
    }
    return bytes;
}

runanywhere::v1::ModelInfo make_assignment_model(const std::string& id, const std::string& name) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_download_url("https://example.test/" + id + ".gguf");
    model.set_download_size_bytes(1024);
    model.set_source(runanywhere::v1::MODEL_SOURCE_REMOTE);
    return model;
}

std::string make_model_list_payload(const std::vector<runanywhere::v1::ModelInfo>& models) {
    runanywhere::v1::ModelInfoList list;
    for (const auto& model : models) {
        list.add_models()->CopyFrom(model);
    }
    return serialize_to_string(list);
}

rac_result_t fake_assignment_http_get(const char* endpoint, rac_bool_t requires_auth,
                                      rac_assignment_http_response_t* out_response,
                                      void* user_data) {
    auto* fake = static_cast<FakeAssignmentTransport*>(user_data);
    if (!fake || !out_response) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    fake->call_count++;
    fake->saw_requires_auth = requires_auth == RAC_TRUE;
    fake->endpoints.emplace_back(endpoint ? endpoint : "");

    if (fake->callback_result != RAC_SUCCESS) {
        return fake->callback_result;
    }

    const size_t payload_index =
        fake->payloads.empty()
            ? 0
            : std::min(static_cast<size_t>(fake->call_count - 1), fake->payloads.size() - 1);
    const std::string* payload = fake->payloads.empty() ? nullptr : &fake->payloads[payload_index];

    out_response->result = fake->response_result;
    out_response->status_code = fake->status_code;
    out_response->response_body = payload ? payload->data() : nullptr;
    out_response->response_length = payload ? payload->size() : 0;
    out_response->error_message =
        fake->error_message.empty() ? nullptr : fake->error_message.c_str();
    return RAC_SUCCESS;
}

void reset_assignment_state() {
    rac_model_assignment_clear_cache();
    rac_model_assignment_set_cache_timeout(3600);
    rac_assignment_callbacks_t callbacks = {};
    rac_model_assignment_set_callbacks(&callbacks);
}

bool install_fake_transport(FakeAssignmentTransport* fake) {
    rac_assignment_callbacks_t callbacks = {};
    callbacks.http_get = fake_assignment_http_get;
    callbacks.user_data = fake;
    callbacks.auto_fetch = RAC_FALSE;
    return rac_model_assignment_set_callbacks(&callbacks) == RAC_SUCCESS;
}

runanywhere::v1::ModelRegistryRefreshRequest make_refresh_request(bool force_refresh) {
    runanywhere::v1::ModelRegistryRefreshRequest request;
    request.set_include_remote_catalog(true);
    request.set_force_refresh(force_refresh);
    request.set_catalog_uri("/assignments/test");
    return request;
}

bool call_assignment_refresh(const runanywhere::v1::ModelRegistryRefreshRequest& request,
                             runanywhere::v1::ModelRegistryRefreshResult* out) {
    const std::string bytes = serialize_to_string(request);
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_model_assignment_refresh_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &buffer);
    if (rc != RAC_SUCCESS || buffer.status != RAC_SUCCESS || !buffer.data || !out) {
        rac_proto_buffer_free(&buffer);
        return false;
    }
    const bool parsed = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return parsed;
}

int test_cache_refresh_policy() {
    reset_assignment_state();

    FakeAssignmentTransport fake;
    fake.payloads.push_back(
        make_model_list_payload({make_assignment_model("cpp03.cache", "Cache One")}));
    fake.payloads.push_back(
        make_model_list_payload({make_assignment_model("cpp03.cache", "Cache Two")}));
    ASSERT_TRUE(install_fake_transport(&fake));

    runanywhere::v1::ModelRegistryRefreshResult result;
    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(true), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 1);
    ASSERT_EQ(result.models().models(0).name(), "Cache One");
    ASSERT_EQ(fake.call_count, 1);
    ASSERT_TRUE(fake.saw_requires_auth);

    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(false), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 1);
    ASSERT_EQ(result.models().models(0).name(), "Cache One");
    ASSERT_EQ(fake.call_count, 1);

    rac_model_assignment_set_cache_timeout(0);
    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(false), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 1);
    ASSERT_EQ(result.models().models(0).name(), "Cache Two");
    ASSERT_EQ(fake.call_count, 2);

    reset_assignment_state();
    return 0;
}

int test_invalid_request_returns_typed_error() {
    reset_assignment_state();

    const uint8_t invalid[] = {0x80};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_model_assignment_refresh_proto(invalid, sizeof(invalid), &buffer);
    ASSERT_EQ(rc, RAC_ERROR_INVALID_FORMAT);
    ASSERT_EQ(buffer.status, RAC_ERROR_INVALID_FORMAT);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_TRUE(buffer.error_message != nullptr);

    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_metadata_normalization_into_model_info() {
    reset_assignment_state();

    runanywhere::v1::ModelInfo remote;
    remote.set_id("cpp03.normalized");
    remote.set_download_url("https://example.test/models/cpp03.normalized.gguf");
    remote.mutable_metadata()->set_description("remote catalog description");
    remote.set_download_size_bytes(4096);

    FakeAssignmentTransport fake;
    fake.payloads.push_back(make_model_list_payload({remote}));
    ASSERT_TRUE(install_fake_transport(&fake));

    runanywhere::v1::ModelRegistryRefreshResult result;
    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(true), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 1);

    const auto& model = result.models().models(0);
    ASSERT_EQ(model.id(), "cpp03.normalized");
    ASSERT_EQ(model.name(), "cpp03.normalized");
    ASSERT_EQ(model.format(), runanywhere::v1::MODEL_FORMAT_GGUF);
    ASSERT_EQ(model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_TRUE(model.has_preferred_framework());
    ASSERT_EQ(model.preferred_framework(), runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_EQ(model.category(), runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    ASSERT_EQ(model.source(), runanywhere::v1::MODEL_SOURCE_REMOTE);
    ASSERT_TRUE(model.has_single_file());
    ASSERT_TRUE(model.has_artifact_type());
    ASSERT_EQ(model.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    ASSERT_TRUE(model.has_registry_status());
    ASSERT_EQ(model.registry_status(), runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    ASSERT_TRUE(model.has_is_downloaded());
    ASSERT_TRUE(!model.is_downloaded());
    ASSERT_TRUE(model.has_is_available());
    ASSERT_TRUE(!model.is_available());
    ASSERT_TRUE(model.has_metadata());
    ASSERT_EQ(model.metadata().description(), "remote catalog description");
    ASSERT_TRUE(model.has_compatibility());
    ASSERT_EQ(model.compatibility().compatible_frameworks(0),
              runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_EQ(model.compatibility().compatible_formats(0), runanywhere::v1::MODEL_FORMAT_GGUF);

    reset_assignment_state();
    return 0;
}

int test_json_diarization_and_segmentation_categories() {
    reset_assignment_state();

    FakeAssignmentTransport fake;
    fake.payloads.emplace_back(R"json({"models":[
        {"id":"category.diarization.string","category":"speaker-diarization"},
        {"id":"category.segmentation.string","category":"semantic_segmentation"},
        {"id":"category.diarization.numeric","category":10},
        {"id":"category.segmentation.numeric","category":11}
    ]})json");
    ASSERT_TRUE(install_fake_transport(&fake));

    runanywhere::v1::ModelRegistryRefreshResult result;
    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(true), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 4);
    ASSERT_EQ(result.models().models(0).category(),
              runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION);
    ASSERT_EQ(result.models().models(1).category(),
              runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION);
    ASSERT_EQ(result.models().models(2).category(),
              runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION);
    ASSERT_EQ(result.models().models(3).category(),
              runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION);

    reset_assignment_state();
    return 0;
}

int test_no_config_no_transport_returns_empty_result() {
    reset_assignment_state();

    rac_model_info_t** legacy_models = nullptr;
    size_t legacy_count = 99;
    ASSERT_EQ(rac_model_assignment_fetch(RAC_TRUE, &legacy_models, &legacy_count), RAC_SUCCESS);
    ASSERT_TRUE(legacy_models == nullptr);
    ASSERT_EQ(legacy_count, 0);

    runanywhere::v1::ModelRegistryRefreshResult result;
    ASSERT_TRUE(call_assignment_refresh(make_refresh_request(true), &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.models().models_size(), 0);
    ASSERT_TRUE(result.warnings_size() >= 1);
    ASSERT_TRUE(result.warnings(0).find("transport") != std::string::npos);

    reset_assignment_state();
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    try {
        std::fprintf(stdout, "test_model_assignment_proto\n");
#if !defined(RAC_HAVE_PROTOBUF)
        std::fprintf(stdout, "  skip: protobuf runtime is disabled\n");
        return 0;
#else
#define RUN_TEST(fn)                                \
    do {                                            \
        std::fprintf(stdout, "[ RUN  ] %s\n", #fn); \
        const int rc = fn();                        \
        if (rc != 0)                                \
            return rc;                              \
        std::fprintf(stdout, "[ OK   ] %s\n", #fn); \
    } while (0)

        RUN_TEST(test_cache_refresh_policy);
        RUN_TEST(test_invalid_request_returns_typed_error);
        RUN_TEST(test_metadata_normalization_into_model_info);
        RUN_TEST(test_json_diarization_and_segmentation_categories);
        RUN_TEST(test_no_config_no_transport_returns_empty_result);

        std::fprintf(stdout, "test_model_assignment_proto: all tests passed\n");
        return 0;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
