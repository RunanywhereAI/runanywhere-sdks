/**
 * @file test_structured_output.cpp
 * @brief Focused tests for centralized structured-output helpers.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
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

int test_extract_object_from_mixed_text() {
    char* json = nullptr;
    size_t len = 0;
    const rac_result_t rc =
        rac_structured_output_extract_json("prefix {\"ok\":true} suffix", &json, &len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(json != nullptr);
    ASSERT_EQ_STR(json, "{\"ok\":true}");
    ASSERT_EQ_INT(len, std::strlen("{\"ok\":true}"));
    std::free(json);
    return 0;
}

int test_extract_array_with_braces_in_string() {
    char* json = nullptr;
    const rac_result_t rc =
        rac_structured_output_extract_json(R"(answer [{"text":"brace } inside"}])", &json, nullptr);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(json != nullptr);
    ASSERT_EQ_STR(json, "[{\"text\":\"brace } inside\"}]");
    std::free(json);
    return 0;
}

int test_extract_skips_invalid_candidate() {
    char* json = nullptr;
    const rac_result_t rc =
        rac_structured_output_extract_json("ignore {not json} then {\"ok\":true}", &json, nullptr);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(json != nullptr);
    ASSERT_EQ_STR(json, "{\"ok\":true}");
    std::free(json);
    return 0;
}

int test_validate_success_and_failure() {
    rac_structured_output_validation_t validation{};
    rac_result_t rc = rac_structured_output_validate("result {\"value\":42}", nullptr, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_TRUE);
    ASSERT_TRUE(validation.extracted_json != nullptr);
    ASSERT_EQ_STR(validation.extracted_json, "{\"value\":42}");
    rac_structured_output_validation_free(&validation);

    rc = rac_structured_output_validate("no json here", nullptr, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
    ASSERT_TRUE(validation.extracted_json == nullptr);
    ASSERT_TRUE(validation.error_message != nullptr);
    rac_structured_output_validation_free(&validation);

    rc = rac_structured_output_validate("bad {not json}", nullptr, &validation);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(validation.is_valid, RAC_FALSE);
    ASSERT_TRUE(validation.extracted_json == nullptr);
    ASSERT_TRUE(validation.error_message != nullptr);
    rac_structured_output_validation_free(&validation);
    return 0;
}

int test_parse_result_schema_validation() {
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    config.json_schema =
        "{\"type\":\"object\",\"required\":[\"status\"],\"properties\":{"
        "\"status\":{\"type\":\"string\"},\"count\":{\"type\":\"integer\"}},"
        "\"additionalProperties\":false}";
    config.include_schema_in_prompt = RAC_TRUE;

    rac_structured_output_parse_result_t parsed{};
    rac_result_t rc =
        rac_structured_output_parse(R"(result {"status":"ok","count":2})", &config, &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(parsed.is_valid, RAC_TRUE);
    ASSERT_EQ_INT(parsed.contains_json, RAC_TRUE);
    ASSERT_TRUE(parsed.parsed_json != nullptr);
    ASSERT_SUBSTR(parsed.parsed_json, "\"status\":\"ok\"");
    ASSERT_SUBSTR(parsed.validation_errors_json, "[]");
    rac_structured_output_parse_result_free(&parsed);

    rc = rac_structured_output_parse(R"({"count":"two","extra":true})", &config, &parsed);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(parsed.is_valid, RAC_FALSE);
    ASSERT_TRUE(parsed.parsed_json != nullptr);
    ASSERT_SUBSTR(parsed.validation_errors_json, "$.status is required");
    ASSERT_SUBSTR(parsed.validation_errors_json, "$.count must be integer");
    ASSERT_SUBSTR(parsed.validation_errors_json, "$.extra is not allowed");
    rac_structured_output_parse_result_free(&parsed);
    return 0;
}

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
    const rac_result_t rc = rac_structured_output_parse_proto(
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
    const rac_result_t rc = rac_structured_output_validate_proto(
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
    return 0;
}
#endif

int test_prepare_prompt_and_system_prompt() {
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    config.json_schema = R"({"type":"object"})";
    config.include_schema_in_prompt = RAC_TRUE;

    char* prepared = nullptr;
    rac_result_t rc = rac_structured_output_prepare_prompt("Return a status", &config, &prepared);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(prepared != nullptr);
    ASSERT_SUBSTR(prepared, "Return a status");
    ASSERT_SUBSTR(prepared, "{\"type\":\"object\"}");
    std::free(prepared);

    char* system = nullptr;
    rc = rac_structured_output_get_system_prompt(config.json_schema, &system);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_TRUE(system != nullptr);
    ASSERT_SUBSTR(system, "outputs ONLY valid JSON");
    ASSERT_SUBSTR(system, "{\"type\":\"object\"}");
    std::free(system);
    return 0;
}

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main() {
    TestCase cases[] = {
        {.name = "extract_object_from_mixed_text", .fn = test_extract_object_from_mixed_text},
        {.name = "extract_array_with_braces_in_string",
         .fn = test_extract_array_with_braces_in_string},
        {.name = "extract_skips_invalid_candidate", .fn = test_extract_skips_invalid_candidate},
        {.name = "validate_success_and_failure", .fn = test_validate_success_and_failure},
        {.name = "parse_result_schema_validation", .fn = test_parse_result_schema_validation},
#if defined(RAC_HAVE_PROTOBUF)
        {.name = "parse_proto_uses_generated_contract",
         .fn = test_parse_proto_uses_generated_contract},
        {.name = "prepare_prompt_proto_uses_generated_contract",
         .fn = test_prepare_prompt_proto_uses_generated_contract},
        {.name = "validate_proto_uses_generated_contract",
         .fn = test_validate_proto_uses_generated_contract},
#endif
        {.name = "prepare_prompt_and_system_prompt", .fn = test_prepare_prompt_and_system_prompt},
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
}
