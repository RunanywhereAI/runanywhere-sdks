/**
 * @file test_sdk_events_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical SDKEvents service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"

#include <google/protobuf/descriptor.h>
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (!(cond)) {                                                                           \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        } else {                                                                                 \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

void check_rpc(const google::protobuf::ServiceDescriptor* service, const char* method_name,
               const char* input_type, const char* output_type, bool server_streaming) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == input_type, "SDKEvents RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "SDKEvents RPC output type");
    CHECK(!method->client_streaming(), "SDKEvents RPC is not client-streaming");
    CHECK(method->server_streaming() == server_streaming, "SDKEvents RPC server-streaming shape");
}

int test_sdk_events_generated_service_contract() {
    const google::protobuf::FileDescriptor* file = runanywhere::v1::SDKEvent::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("SDKEvents");
    CHECK(service != nullptr, "generated SDKEvents service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 2, "generated SDKEvents service exposes two RPCs");

    check_rpc(service, "Publish", "runanywhere.v1.SDKEventPublishRequest",
              "runanywhere.v1.SDKEventPublishResult", false);
    check_rpc(service, "Subscribe", "runanywhere.v1.SDKEventSubscribeRequest",
              "runanywhere.v1.SDKEvent", true);

    const google::protobuf::Descriptor* publish =
        runanywhere::v1::SDKEventPublishRequest::descriptor();
    const google::protobuf::FieldDescriptor* event = publish->FindFieldByName("event");
    CHECK(event != nullptr, "Publish request carries SDKEvent");
    if (event) {
        CHECK(event->message_type()->full_name() == "runanywhere.v1.SDKEvent",
              "Publish request event field uses SDKEvent");
        CHECK(event->has_presence(), "Publish request event field has presence");
    }

    const google::protobuf::FieldDescriptor* normalize =
        publish->FindFieldByName("normalize_envelope");
    CHECK(normalize != nullptr, "Publish request carries normalization flag");
    if (normalize) {
        CHECK(normalize->type() == google::protobuf::FieldDescriptor::TYPE_BOOL,
              "normalization flag is bool");
    }

    const google::protobuf::Descriptor* result =
        runanywhere::v1::SDKEventPublishResult::descriptor();
    const google::protobuf::FieldDescriptor* normalized_event =
        result->FindFieldByName("normalized_event");
    CHECK(normalized_event != nullptr, "Publish result carries normalized event");
    if (normalized_event) {
        CHECK(normalized_event->message_type()->full_name() == "runanywhere.v1.SDKEvent",
              "Publish result normalized_event field uses SDKEvent");
        CHECK(normalized_event->has_presence(),
              "Publish result normalized_event field has presence");
    }

    const google::protobuf::Descriptor* subscribe =
        runanywhere::v1::SDKEventSubscribeRequest::descriptor();
    const google::protobuf::FieldDescriptor* filter = subscribe->FindFieldByName("filter");
    CHECK(filter != nullptr, "Subscribe request carries filter");
    if (filter) {
        CHECK(filter->message_type()->full_name() == "runanywhere.v1.SDKEventFilter",
              "Subscribe filter field uses SDKEventFilter");
        CHECK(filter->has_presence(), "Subscribe filter field has presence");
    }

    const google::protobuf::Descriptor* filter_desc = runanywhere::v1::SDKEventFilter::descriptor();
    const google::protobuf::FieldDescriptor* categories =
        filter_desc->FindFieldByName("categories");
    CHECK(categories != nullptr, "SDKEventFilter carries categories");
    if (categories) {
        CHECK(categories->is_repeated(), "SDKEventFilter categories are repeated");
        CHECK(categories->enum_type()->full_name() == "runanywhere.v1.EventCategory",
              "SDKEventFilter categories use EventCategory");
    }

    const google::protobuf::FieldDescriptor* minimum_severity =
        filter_desc->FindFieldByName("minimum_severity");
    CHECK(minimum_severity != nullptr, "SDKEventFilter carries minimum severity");
    if (minimum_severity) {
        CHECK(minimum_severity->enum_type()->full_name() == "runanywhere.v1.ErrorSeverity",
              "SDKEventFilter minimum_severity uses ErrorSeverity");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_sdk_events_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: SDKEvents service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_sdk_events_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
