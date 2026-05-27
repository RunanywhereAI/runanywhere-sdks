/**
 * @file test_diffusion_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical Diffusion service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"

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

int test_diffusion_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::DiffusionGenerationRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("Diffusion");
    CHECK(service != nullptr, "generated Diffusion service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 2, "generated Diffusion service exposes two RPCs");

    const google::protobuf::MethodDescriptor* generate = service->FindMethodByName("Generate");
    CHECK(generate != nullptr, "Diffusion Generate RPC exists");
    if (generate) {
        CHECK(generate->input_type()->full_name() == "runanywhere.v1.DiffusionGenerationRequest",
              "Generate accepts DiffusionGenerationRequest");
        CHECK(generate->output_type()->full_name() == "runanywhere.v1.DiffusionResult",
              "Generate returns DiffusionResult");
        CHECK(!(generate->client_streaming() || generate->server_streaming()), "Generate is unary");
    }

    const google::protobuf::MethodDescriptor* stream = service->FindMethodByName("Stream");
    CHECK(stream != nullptr, "Diffusion Stream RPC exists");
    if (stream) {
        CHECK(stream->input_type()->full_name() == "runanywhere.v1.DiffusionGenerationRequest",
              "Stream accepts DiffusionGenerationRequest");
        CHECK(stream->output_type()->full_name() == "runanywhere.v1.DiffusionStreamEvent",
              "Stream returns DiffusionStreamEvent");
        CHECK(!stream->client_streaming(), "Stream is not client-streaming");
        CHECK(stream->server_streaming(), "Stream is server-streaming");
    }

    const google::protobuf::Descriptor* request =
        runanywhere::v1::DiffusionGenerationRequest::descriptor();
    const google::protobuf::FieldDescriptor* options = request->FindFieldByName("options");
    CHECK(options != nullptr, "Diffusion request carries generation options");
    if (options) {
        CHECK(options->message_type()->full_name() == "runanywhere.v1.DiffusionGenerationOptions",
              "request options use DiffusionGenerationOptions");
        CHECK(options->has_presence(), "request options field has presence");
    }

    const google::protobuf::Descriptor* event = runanywhere::v1::DiffusionStreamEvent::descriptor();
    const google::protobuf::FieldDescriptor* progress = event->FindFieldByName("progress");
    CHECK(progress != nullptr, "Diffusion stream event has progress field");
    if (progress) {
        CHECK(progress->message_type()->full_name() == "runanywhere.v1.DiffusionProgress",
              "Diffusion stream progress field uses DiffusionProgress");
        CHECK(progress->has_presence(), "Diffusion stream progress field has presence");
    }

    const google::protobuf::FieldDescriptor* result = event->FindFieldByName("result");
    CHECK(result != nullptr, "Diffusion stream event has terminal result field");
    if (result) {
        CHECK(result->message_type()->full_name() == "runanywhere.v1.DiffusionResult",
              "Diffusion stream result field uses DiffusionResult");
        CHECK(result->has_presence(), "Diffusion stream result field has presence");
    }

    const google::protobuf::EnumDescriptor* kind =
        file->FindEnumTypeByName("DiffusionStreamEventKind");
    CHECK(kind != nullptr, "Diffusion stream event kind enum exists");
    if (kind) {
        CHECK(kind->FindValueByName("DIFFUSION_STREAM_EVENT_KIND_PROGRESS") != nullptr,
              "Diffusion stream supports progress events");
        CHECK(kind->FindValueByName("DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE") != nullptr,
              "Diffusion stream supports intermediate image events");
        CHECK(kind->FindValueByName("DIFFUSION_STREAM_EVENT_KIND_COMPLETED") != nullptr,
              "Diffusion stream supports completion events");
        CHECK(kind->FindValueByName("DIFFUSION_STREAM_EVENT_KIND_ERROR") != nullptr,
              "Diffusion stream supports error events");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_diffusion_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: Diffusion service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_diffusion_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
