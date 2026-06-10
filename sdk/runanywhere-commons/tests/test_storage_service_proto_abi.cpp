/**
 * @file test_storage_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical Storage service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "storage_types.pb.h"

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

    CHECK(method->input_type()->full_name() == input_type, "Storage RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "Storage RPC output type");
    CHECK(!(method->client_streaming() || method->server_streaming()), "Storage RPC is unary");
}

int test_storage_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::StorageInfoRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("Storage");
    CHECK(service != nullptr, "generated Storage service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 4, "generated Storage service exposes four RPCs");

    check_unary_rpc(service, "Info", "runanywhere.v1.StorageInfoRequest",
                    "runanywhere.v1.StorageInfoResult");
    check_unary_rpc(service, "Availability", "runanywhere.v1.StorageAvailabilityRequest",
                    "runanywhere.v1.StorageAvailabilityResult");
    check_unary_rpc(service, "DeletePlan", "runanywhere.v1.StorageDeletePlanRequest",
                    "runanywhere.v1.StorageDeletePlan");
    check_unary_rpc(service, "Delete", "runanywhere.v1.StorageDeleteRequest",
                    "runanywhere.v1.StorageDeleteResult");

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_storage_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: Storage service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_storage_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
