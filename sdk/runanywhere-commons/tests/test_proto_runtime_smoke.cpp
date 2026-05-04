/**
 * @file test_proto_runtime_smoke.cpp
 * @brief Focused smoke test for protobuf runtime activation behind exported C ABIs.
 */

#include <cstdio>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "storage_types.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                              \
    do {                                                                                \
        ++test_count;                                                                   \
        if (!(cond)) {                                                                  \
            ++fail_count;                                                               \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__,        \
                         __LINE__, #cond);                                             \
        } else {                                                                        \
            std::fprintf(stdout, "  ok:   %s\n", label);                              \
        }                                                                               \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct StorageFixture {
    int64_t total = 4096;
    int64_t free = 1024;
};

int64_t zero_size_callback(const char*, void*) {
    return 0;
}

rac_bool_t missing_path_callback(const char*, rac_bool_t* is_directory, void*) {
    if (is_directory) {
        *is_directory = RAC_FALSE;
    }
    return RAC_FALSE;
}

int64_t free_space_callback(void* user_data) {
    return static_cast<StorageFixture*>(user_data)->free;
}

int64_t total_space_callback(void* user_data) {
    return static_cast<StorageFixture*>(user_data)->total;
}

template <typename T>
bool serialize(const T& message, std::vector<uint8_t>* out) {
    if (!out) {
        return false;
    }
    out->resize(message.ByteSizeLong());
    if (out->empty()) {
        return true;
    }
    return message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_raw(const uint8_t* bytes, size_t size, T* out) {
    const void* data = size == 0 ? static_cast<const void*>("")
                                 : static_cast<const void*>(bytes);
    return out && out->ParseFromArray(data, static_cast<int>(size));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS && parse_raw(buffer.data, buffer.size, out);
}

int test_registry_list_proto_is_active() {
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "registry creates");

    uint8_t* bytes = nullptr;
    size_t size = 0;
    const rac_result_t rc = rac_model_registry_list_proto(registry, &bytes, &size);
    runanywhere::v1::ModelInfoList list;
    CHECK(rc == RAC_SUCCESS, "registry list proto returns success");
    CHECK(bytes != nullptr, "registry list proto returns owned bytes");
    CHECK(parse_raw(bytes, size, &list), "registry list proto parses");
    CHECK(list.models_size() == 0, "empty registry list has zero models");

    rac_model_registry_proto_free(bytes);
    rac_model_registry_destroy(registry);
    return 0;
}

int test_storage_info_proto_is_active() {
    StorageFixture fixture;
    rac_storage_callbacks_t callbacks{};
    callbacks.calculate_dir_size = zero_size_callback;
    callbacks.get_file_size = zero_size_callback;
    callbacks.path_exists = missing_path_callback;
    callbacks.get_available_space = free_space_callback;
    callbacks.get_total_space = total_space_callback;
    callbacks.user_data = &fixture;

    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_storage_analyzer_create(&callbacks, &analyzer) == RAC_SUCCESS &&
              analyzer != nullptr,
          "storage analyzer creates");
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "storage registry creates");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_storage_analyzer_info_proto(analyzer, registry, nullptr, 0, &out);
    runanywhere::v1::StorageInfoResult result;
    CHECK(rc == RAC_SUCCESS, "storage info proto returns success");
    CHECK(parse_buffer(out, &result), "storage info proto parses");
    CHECK(result.success(), "storage info reports success");
    CHECK(result.info().device().total_bytes() == fixture.total,
          "storage info carries device total");
    CHECK(result.info().device().free_bytes() == fixture.free,
          "storage info carries device free");

    rac_proto_buffer_free(&out);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_lifecycle_current_model_proto_is_active() {
    rac_model_lifecycle_reset();

    runanywhere::v1::CurrentModelRequest request;
    std::vector<uint8_t> request_bytes;
    CHECK(serialize(request, &request_bytes), "current model request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_model_lifecycle_current_model_proto(
        request_bytes.empty() ? nullptr : request_bytes.data(), request_bytes.size(), &out);
    runanywhere::v1::CurrentModelResult result;
    CHECK(rc == RAC_SUCCESS, "current model proto returns success");
    CHECK(parse_buffer(out, &result), "current model proto parses");
    CHECK(result.model_id().empty(), "current model reports no loaded model");

    rac_proto_buffer_free(&out);
    return 0;
}

int test_llm_no_model_returns_typed_domain_error() {
    rac_model_lifecycle_reset();

    runanywhere::v1::LLMGenerateRequest request;
    request.set_prompt("hello");
    std::vector<uint8_t> request_bytes;
    CHECK(serialize(request, &request_bytes), "LLM request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_llm_generate_proto(request_bytes.data(), request_bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NOT_INITIALIZED,
          "LLM no-model proto returns typed not-initialized error");
    CHECK(out.status == RAC_ERROR_NOT_INITIALIZED,
          "LLM no-model proto marks buffer with typed error");
    CHECK(out.error_message != nullptr, "LLM no-model proto carries error message");
    CHECK(std::string(out.error_message).find("protobuf support") == std::string::npos,
          "LLM no-model error is not protobuf-unavailable");

    rac_proto_buffer_free(&out);
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_proto_runtime_smoke\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: protobuf runtime is disabled\n");
    return 0;
#else
#define RUN(name)                                                                        \
    do {                                                                                \
        std::fprintf(stdout, "[ RUN  ] %s\n", #name);                                  \
        name();                                                                         \
    } while (0)

    RUN(test_registry_list_proto_is_active);
    RUN(test_storage_info_proto_is_active);
    RUN(test_lifecycle_current_model_proto_is_active);
    RUN(test_llm_no_model_returns_typed_domain_error);

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
