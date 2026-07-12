/**
 * @file test_structured_output.cpp
 * @brief Focused tests for centralized structured-output helpers.
 */

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_structured_output.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "structured_output.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                 \
    do {                                                                                  \
        if (!(cond)) {                                                                    \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

#define ASSERT_EQ_INT(a, b)                                                             \
    do {                                                                                \
        if ((a) != (b)) {                                                               \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %d != %d\n", __FILE__, __LINE__, \
                         static_cast<int>(a), static_cast<int>(b));                     \
            return 1;                                                                   \
        }                                                                               \
    } while (0)

#define ASSERT_EQ_STR(actual, expected)                                                           \
    do {                                                                                          \
        if (std::strcmp((actual), (expected)) != 0) {                                             \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d\n  expected: \"%s\"\n  actual:   \"%s\"\n", \
                         __FILE__, __LINE__, (expected), (actual));                               \
            return 1;                                                                             \
        }                                                                                         \
    } while (0)

#define ASSERT_SUBSTR(haystack, needle)                                                         \
    do {                                                                                        \
        if (std::strstr((haystack), (needle)) == nullptr) {                                     \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: '%s' not found in '%.200s'\n", __FILE__, \
                         __LINE__, (needle), (haystack));                                       \
            return 1;                                                                           \
        }                                                                                       \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)
int test_parse_proto_uses_generated_contract() {
    runanywhere::v1::StructuredOutputParseRequest request;
    request.set_text(R"(answer {"status":"ok","count":2})");
    request.mutable_options()->set_json_schema(
        "{\"type\":\"object\",\"required\":[\"status\"],\"properties\":{"
        "\"status\":{\"type\":\"string\"},\"count\":{\"type\":\"integer\"}},"
        "\"additionalProperties\":false}");

    std::string bytes;
    ASSERT_TRUE(request.SerializeToString(&bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    rac_result_t rc = rac_structured_output_parse_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    ASSERT_TRUE(result_bytes.data != nullptr);

    runanywhere::v1::StructuredOutputResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_TRUE(result.has_validation());
    ASSERT_EQ_INT(result.validation().is_valid(), true);
    ASSERT_EQ_INT(result.validation().contains_json(), true);
    ASSERT_SUBSTR(result.parsed_json().c_str(), "\"status\":\"ok\"");
    ASSERT_EQ_INT(result.validation().validation_errors_size(), 0);

    rac_proto_buffer_free(&result_bytes);

    request.set_text(R"(ignore {not json} then {"status":"ok","count":2})");
    bytes.clear();
    ASSERT_TRUE(request.SerializeToString(&bytes));
    rac_proto_buffer_init(&result_bytes);
    rc = rac_structured_output_parse_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                           bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    result.Clear();
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.validation().is_valid(), true);
    ASSERT_SUBSTR(result.parsed_json().c_str(), "\"status\":\"ok\"");
    rac_proto_buffer_free(&result_bytes);

    request.set_text(R"({"count":"two","extra":true})");
    bytes.clear();
    ASSERT_TRUE(request.SerializeToString(&bytes));
    rac_proto_buffer_init(&result_bytes);
    rc = rac_structured_output_parse_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                           bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    result.Clear();
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.validation().is_valid(), false);
    ASSERT_EQ_INT(result.validation().validation_errors_size(), 3);
    std::string validation_errors;
    for (const auto& error : result.validation().validation_errors()) {
        validation_errors += error;
        validation_errors += '\n';
    }
    ASSERT_SUBSTR(validation_errors.c_str(), "$.status is required");
    ASSERT_SUBSTR(validation_errors.c_str(), "$.count must be integer");
    ASSERT_SUBSTR(validation_errors.c_str(), "$.extra is not allowed");
    rac_proto_buffer_free(&result_bytes);
    return 0;
}

int test_parse_proto_extracts_array_with_brace_in_string() {
    runanywhere::v1::StructuredOutputParseRequest request;
    request.set_text(R"(answer [{"text":"brace } inside"}])");

    std::string bytes;
    ASSERT_TRUE(request.SerializeToString(&bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    const rac_result_t rc = rac_structured_output_parse_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);

    runanywhere::v1::StructuredOutputResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.validation().is_valid(), true);
    ASSERT_EQ_INT(result.validation().contains_json(), true);
    ASSERT_EQ_STR(result.parsed_json().c_str(), "[{\"text\":\"brace } inside\"}]");

    rac_proto_buffer_free(&result_bytes);
    return 0;
}

int test_prepare_prompt_proto_uses_generated_contract() {
    runanywhere::v1::StructuredOutputRequest request;
    request.set_prompt("Return a status");
    auto* options = request.mutable_options();
    options->set_include_schema_in_prompt(true);
    options->set_json_schema(
        "{\"type\":\"object\",\"required\":[\"status\"],"
        "\"properties\":{\"status\":{\"type\":\"string\"}}}");

    std::string bytes;
    ASSERT_TRUE(request.SerializeToString(&bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    const rac_result_t rc = rac_structured_output_prepare_prompt_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    ASSERT_TRUE(result_bytes.data != nullptr);

    runanywhere::v1::StructuredOutputPromptResult result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.error_code(), RAC_SUCCESS);
    ASSERT_SUBSTR(result.prepared_prompt().c_str(), "Return a status");
    ASSERT_SUBSTR(result.prepared_prompt().c_str(), "\"status\"");
    ASSERT_TRUE(result.has_system_prompt());
    ASSERT_SUBSTR(result.system_prompt().c_str(), "outputs ONLY valid JSON");
    ASSERT_TRUE(result.has_json_schema());
    ASSERT_SUBSTR(result.json_schema().c_str(), "\"type\":\"object\"");

    rac_proto_buffer_free(&result_bytes);
    return 0;
}

int test_validate_proto_uses_generated_contract() {
    runanywhere::v1::StructuredOutputValidationRequest request;
    request.set_text(R"(answer {"status":"ok"})");
    auto* schema = request.mutable_options()->mutable_schema();
    schema->set_type(runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);
    schema->add_required("status");
    schema->set_additional_properties(false);
    auto* properties = schema->mutable_properties();
    (*properties)["status"].set_type(runanywhere::v1::JSON_SCHEMA_TYPE_STRING);

    std::string bytes;
    ASSERT_TRUE(request.SerializeToString(&bytes));

    rac_proto_buffer_t result_bytes{};
    rac_proto_buffer_init(&result_bytes);
    rac_result_t rc = rac_structured_output_validate_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    ASSERT_TRUE(result_bytes.data != nullptr);

    runanywhere::v1::StructuredOutputValidation result;
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.is_valid(), true);
    ASSERT_EQ_INT(result.contains_json(), true);
    ASSERT_TRUE(result.has_raw_output());
    ASSERT_SUBSTR(result.raw_output().c_str(), "{\"status\":\"ok\"}");
    ASSERT_TRUE(result.has_extracted_json());
    ASSERT_EQ_STR(result.extracted_json().c_str(), "{\"status\":\"ok\"}");
    ASSERT_EQ_INT(result.validation_errors_size(), 0);

    rac_proto_buffer_free(&result_bytes);

    request.set_text("no json here");
    bytes.clear();
    ASSERT_TRUE(request.SerializeToString(&bytes));
    rac_proto_buffer_init(&result_bytes);
    rc = rac_structured_output_validate_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                              bytes.size(), &result_bytes);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(result_bytes.status, RAC_SUCCESS);
    result.Clear();
    ASSERT_TRUE(result.ParseFromArray(result_bytes.data, static_cast<int>(result_bytes.size)));
    ASSERT_EQ_INT(result.is_valid(), false);
    ASSERT_EQ_INT(result.contains_json(), false);
    ASSERT_TRUE(result.has_error_message());
    ASSERT_TRUE(!result.has_extracted_json());
    rac_proto_buffer_free(&result_bytes);
    return 0;
}
#endif

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main() {
#if !defined(RAC_HAVE_PROTOBUF)
    std::printf("[structured_output] skipped: protobuf runtime is disabled\n");
    return 0;
#else
    TestCase cases[] = {
        {.name = "parse_proto_uses_generated_contract",
         .fn = test_parse_proto_uses_generated_contract},
        {.name = "parse_proto_extracts_array_with_brace_in_string",
         .fn = test_parse_proto_extracts_array_with_brace_in_string},
        {.name = "prepare_prompt_proto_uses_generated_contract",
         .fn = test_prepare_prompt_proto_uses_generated_contract},
        {.name = "validate_proto_uses_generated_contract",
         .fn = test_validate_proto_uses_generated_contract},
    };

    int failed = 0;
    const int count = static_cast<int>(sizeof(cases) / sizeof(cases[0]));
    for (const auto& test_case : cases) {
        std::printf("[structured_output] %s ... ", test_case.name);
        std::fflush(stdout);
        const int rc = test_case.fn();
        if (rc == 0) {
            std::printf("OK\n");
        } else {
            std::printf("FAIL\n");
            ++failed;
        }
    }
    std::printf("\n[structured_output] %d/%d passed\n", count - failed, count);
    return failed == 0 ? 0 : 1;
#endif
}
