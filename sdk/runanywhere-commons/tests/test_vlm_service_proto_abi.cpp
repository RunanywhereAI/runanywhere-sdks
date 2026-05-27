/**
 * @file test_vlm_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical VLM service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "vlm_options.pb.h"

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

int test_vlm_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::VLMGenerationRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("VLM");
    CHECK(service != nullptr, "generated VLM service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 2, "generated VLM service exposes two RPCs");

    const google::protobuf::MethodDescriptor* generate = service->FindMethodByName("Generate");
    CHECK(generate != nullptr, "VLM Generate RPC exists");
    if (generate) {
        CHECK(generate->input_type()->full_name() == "runanywhere.v1.VLMGenerationRequest",
              "Generate accepts VLMGenerationRequest");
        CHECK(generate->output_type()->full_name() == "runanywhere.v1.VLMResult",
              "Generate returns VLMResult");
        CHECK(!(generate->client_streaming() || generate->server_streaming()), "Generate is unary");
    }

    const google::protobuf::MethodDescriptor* stream = service->FindMethodByName("Stream");
    CHECK(stream != nullptr, "VLM Stream RPC exists");
    if (stream) {
        CHECK(stream->input_type()->full_name() == "runanywhere.v1.VLMGenerationRequest",
              "Stream accepts VLMGenerationRequest");
        CHECK(stream->output_type()->full_name() == "runanywhere.v1.VLMStreamEvent",
              "Stream returns VLMStreamEvent");
        CHECK(!stream->client_streaming() && stream->server_streaming(),
              "Stream is server-streaming");
    }

    const google::protobuf::Descriptor* event = runanywhere::v1::VLMStreamEvent::descriptor();
    const google::protobuf::FieldDescriptor* result = event->FindFieldByName("result");
    CHECK(result != nullptr, "VLM stream event has terminal result field");
    if (result) {
        CHECK(result->message_type()->full_name() == "runanywhere.v1.VLMResult",
              "VLM stream result field uses VLMResult");
        CHECK(result->has_presence(), "VLM stream result field has presence");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_vlm_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: VLM service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_vlm_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
