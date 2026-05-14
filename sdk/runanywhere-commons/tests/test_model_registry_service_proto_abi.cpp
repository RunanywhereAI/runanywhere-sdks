/**
 * @file test_model_registry_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical ModelRegistry service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"

#include <google/protobuf/descriptor.h>
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

void check_unary_rpc(const google::protobuf::ServiceDescriptor* service, const char* method_name,
                     const char* input_type, const char* output_type) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == input_type, "ModelRegistry RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "ModelRegistry RPC output type");
    CHECK(!(method->client_streaming() || method->server_streaming()),
          "ModelRegistry RPC is unary");
}

int test_model_registry_generated_service_contract() {
    const google::protobuf::FileDescriptor* file = runanywhere::v1::ModelInfo::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("ModelRegistry");
    CHECK(service != nullptr, "generated ModelRegistry service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->full_name() == "runanywhere.v1.ModelRegistry",
          "generated ModelRegistry service full name");
    CHECK(service->method_count() == 8, "generated ModelRegistry service exposes eight RPCs");

    check_unary_rpc(service, "Register", "runanywhere.v1.ModelInfo", "runanywhere.v1.ModelInfo");
    check_unary_rpc(service, "Update", "runanywhere.v1.ModelInfo", "runanywhere.v1.ModelInfo");
    check_unary_rpc(service, "Get", "runanywhere.v1.ModelGetRequest",
                    "runanywhere.v1.ModelGetResult");
    check_unary_rpc(service, "List", "runanywhere.v1.ModelListRequest",
                    "runanywhere.v1.ModelListResult");
    check_unary_rpc(service, "Remove", "runanywhere.v1.ModelDeleteRequest",
                    "runanywhere.v1.ModelDeleteResult");
    check_unary_rpc(service, "Import", "runanywhere.v1.ModelImportRequest",
                    "runanywhere.v1.ModelImportResult");
    check_unary_rpc(service, "Discover", "runanywhere.v1.ModelDiscoveryRequest",
                    "runanywhere.v1.ModelDiscoveryResult");
    check_unary_rpc(service, "Refresh", "runanywhere.v1.ModelRegistryRefreshRequest",
                    "runanywhere.v1.ModelRegistryRefreshResult");

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_model_registry_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: ModelRegistry service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_model_registry_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
