/**
 * @file test_structured_output_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical StructuredOutput service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "structured_output.pb.h"

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

    CHECK(method->input_type()->full_name() == input_type, "StructuredOutput RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "StructuredOutput RPC output type");
    CHECK(!(method->client_streaming() || method->server_streaming()),
          "StructuredOutput RPC is unary");
}

int test_structured_output_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::StructuredOutputRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service =
        file->FindServiceByName("StructuredOutput");
    CHECK(service != nullptr, "generated StructuredOutput service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 3, "generated StructuredOutput service exposes three RPCs");

    check_unary_rpc(service, "PreparePrompt", "runanywhere.v1.StructuredOutputRequest",
                    "runanywhere.v1.StructuredOutputPromptResult");
    check_unary_rpc(service, "Validate", "runanywhere.v1.StructuredOutputValidationRequest",
                    "runanywhere.v1.StructuredOutputValidation");
    check_unary_rpc(service, "Parse", "runanywhere.v1.StructuredOutputParseRequest",
                    "runanywhere.v1.StructuredOutputResult");

    const google::protobuf::Descriptor* parse_request =
        runanywhere::v1::StructuredOutputParseRequest::descriptor();
    const google::protobuf::FieldDescriptor* text = parse_request->FindFieldByName("text");
    CHECK(text != nullptr, "StructuredOutputParseRequest carries model text");
    if (text) {
        CHECK(text->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "StructuredOutputParseRequest text is a string");
    }

    const google::protobuf::FieldDescriptor* parse_options =
        parse_request->FindFieldByName("options");
    CHECK(parse_options != nullptr, "StructuredOutputParseRequest carries options");
    if (parse_options) {
        CHECK(parse_options->message_type()->full_name() ==
                  "runanywhere.v1.StructuredOutputOptions",
              "StructuredOutputParseRequest options use StructuredOutputOptions");
        CHECK(parse_options->has_presence(),
              "StructuredOutputParseRequest options field has presence");
    }

    const google::protobuf::Descriptor* validation_request =
        runanywhere::v1::StructuredOutputValidationRequest::descriptor();
    const google::protobuf::FieldDescriptor* validation_options =
        validation_request->FindFieldByName("options");
    CHECK(validation_options != nullptr, "StructuredOutputValidationRequest carries options");
    if (validation_options) {
        CHECK(validation_options->message_type()->full_name() ==
                  "runanywhere.v1.StructuredOutputOptions",
              "StructuredOutputValidationRequest options use StructuredOutputOptions");
        CHECK(validation_options->has_presence(),
              "StructuredOutputValidationRequest options field has presence");
    }

    const google::protobuf::Descriptor* prompt_result =
        runanywhere::v1::StructuredOutputPromptResult::descriptor();
    const google::protobuf::FieldDescriptor* prepared_prompt =
        prompt_result->FindFieldByName("prepared_prompt");
    CHECK(prepared_prompt != nullptr, "StructuredOutputPromptResult carries prepared prompt");
    if (prepared_prompt) {
        CHECK(prepared_prompt->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "StructuredOutputPromptResult prepared_prompt is a string");
    }

    const google::protobuf::FieldDescriptor* json_schema =
        prompt_result->FindFieldByName("json_schema");
    CHECK(json_schema != nullptr, "StructuredOutputPromptResult carries JSON schema constraint");
    if (json_schema) {
        CHECK(json_schema->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "StructuredOutputPromptResult json_schema is a string");
        CHECK(json_schema->has_presence(),
              "StructuredOutputPromptResult json_schema field has presence");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_structured_output_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: StructuredOutput service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_structured_output_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
