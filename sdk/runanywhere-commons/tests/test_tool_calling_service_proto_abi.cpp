/**
 * @file test_tool_calling_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical ToolCalling service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"

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

void check_unary_rpc(const google::protobuf::ServiceDescriptor* service, const char* method_name,
                     const char* input_type, const char* output_type) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == input_type, "ToolCalling RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "ToolCalling RPC output type");
    CHECK(!(method->client_streaming() || method->server_streaming()), "ToolCalling RPC is unary");
}

int test_tool_calling_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::ToolParseRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("ToolCalling");
    CHECK(service != nullptr, "generated ToolCalling service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 3, "generated ToolCalling service exposes three RPCs");

    check_unary_rpc(service, "Parse", "runanywhere.v1.ToolParseRequest",
                    "runanywhere.v1.ToolParseResult");
    check_unary_rpc(service, "FormatPrompt", "runanywhere.v1.ToolPromptFormatRequest",
                    "runanywhere.v1.ToolPromptFormatResult");
    check_unary_rpc(service, "ValidateCall", "runanywhere.v1.ToolCallValidationRequest",
                    "runanywhere.v1.ToolCallValidationResult");

    const google::protobuf::Descriptor* format_request =
        runanywhere::v1::ToolPromptFormatRequest::descriptor();
    const google::protobuf::FieldDescriptor* options = format_request->FindFieldByName("options");
    CHECK(options != nullptr, "ToolPromptFormatRequest carries options");
    if (options) {
        CHECK(options->message_type()->full_name() == "runanywhere.v1.ToolCallingOptions",
              "ToolPromptFormatRequest options use ToolCallingOptions");
        CHECK(options->has_presence(), "ToolPromptFormatRequest options field has presence");
    }

    const google::protobuf::FieldDescriptor* tool_results =
        format_request->FindFieldByName("tool_results");
    CHECK(tool_results != nullptr, "ToolPromptFormatRequest carries follow-up tool results");
    if (tool_results) {
        CHECK(tool_results->is_repeated(), "ToolPromptFormatRequest tool_results are repeated");
        CHECK(tool_results->message_type()->full_name() == "runanywhere.v1.ToolResult",
              "ToolPromptFormatRequest tool_results use ToolResult");
    }

    const google::protobuf::Descriptor* validation_request =
        runanywhere::v1::ToolCallValidationRequest::descriptor();
    const google::protobuf::FieldDescriptor* tool_call =
        validation_request->FindFieldByName("tool_call");
    CHECK(tool_call != nullptr, "ToolCallValidationRequest carries ToolCall");
    if (tool_call) {
        CHECK(tool_call->message_type()->full_name() == "runanywhere.v1.ToolCall",
              "ToolCallValidationRequest tool_call uses ToolCall");
        CHECK(tool_call->has_presence(), "ToolCallValidationRequest tool_call field has presence");
    }

    const google::protobuf::Descriptor* validation_result =
        runanywhere::v1::ToolCallValidationResult::descriptor();
    const google::protobuf::FieldDescriptor* errors =
        validation_result->FindFieldByName("validation_errors");
    CHECK(errors != nullptr, "ToolCallValidationResult carries validation errors");
    if (errors) {
        CHECK(errors->is_repeated(), "ToolCallValidationResult validation_errors are repeated");
        CHECK(errors->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "ToolCallValidationResult validation_errors are strings");
    }

    const google::protobuf::FieldDescriptor* matched_tool =
        validation_result->FindFieldByName("matched_tool");
    CHECK(matched_tool != nullptr, "ToolCallValidationResult carries matched tool definition");
    if (matched_tool) {
        CHECK(matched_tool->message_type()->full_name() == "runanywhere.v1.ToolDefinition",
              "ToolCallValidationResult matched_tool uses ToolDefinition");
        CHECK(matched_tool->has_presence(),
              "ToolCallValidationResult matched_tool field has presence");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_tool_calling_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: ToolCalling service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_tool_calling_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
