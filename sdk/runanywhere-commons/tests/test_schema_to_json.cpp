/**
 * @file test_schema_to_json.cpp
 * @brief Parity tests for rac_structured_output_schema_to_json_proto.
 *
 * Each case builds an RAJSONSchema via the generated proto, serializes it,
 * runs the C ABI, and compares the produced JSON Schema text to a fixture
 * derived directly from Swift's JSONSchemaWriter algorithm
 * (StructuredOutputProto+Helpers.swift). The expected strings are compact
 * + key-sorted to match Swift's
 *   `JSONSerialization.data(withJSONObject:options:[.sortedKeys])`
 * ASCII '$' (0x24) sorts before lowercase letters, so $ref / $schema
 * appear before alphabetic keys.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_schema_to_json.h"
#include "rac/foundation/rac_proto_buffer.h"

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

#if defined(RAC_HAVE_PROTOBUF)

// Helper: serialize a JSONSchema, run the C ABI, copy the result text into an
// owned std::string. Returns 0 and populates *out_text on success.
int run_schema_to_json(const ::runanywhere::v1::JSONSchema& schema, std::string* out_text) {
    std::string serialized;
    if (!schema.SerializeToString(&serialized)) {
        std::fprintf(stderr, "failed to serialize JSONSchema fixture\n");
        return 1;
    }

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_structured_output_schema_to_json_proto(
        reinterpret_cast<const uint8_t*>(serialized.data()), serialized.size(), &buffer);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "schema_to_json_proto returned %d (status=%d)\n", static_cast<int>(rc),
                     static_cast<int>(buffer.status));
        rac_proto_buffer_free(&buffer);
        return 1;
    }
    if (!buffer.data || buffer.status != RAC_SUCCESS) {
        std::fprintf(stderr, "schema_to_json_proto produced empty/error buffer\n");
        rac_proto_buffer_free(&buffer);
        return 1;
    }
    out_text->assign(reinterpret_cast<const char*>(buffer.data), buffer.size);
    rac_proto_buffer_free(&buffer);
    return 0;
}

// Case 1: simple object schema.
// JSONSchemaWriter walks { type=object, properties={name=string}, required=[name] }.
int test_simple_object() {
    ::runanywhere::v1::JSONSchema schema;
    schema.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);
    auto& properties = *schema.mutable_properties();
    auto& name = properties["name"];
    name.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_STRING);
    schema.add_required("name");

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    const char* expected =
        R"({"properties":{"name":{"type":"string"}},"required":["name"],"type":"object"})";
    ASSERT_EQ_STR(actual.c_str(), expected);
    return 0;
}

// Case 2: nested object via property.object_schema. Mirrors Swift's behaviour
// where the property dict is seeded from the nested schema, then property-level
// fields override.
int test_nested_object() {
    ::runanywhere::v1::JSONSchema schema;
    schema.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);

    auto& properties = *schema.mutable_properties();
    auto& user = properties["user"];
    user.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);

    auto* user_schema = user.mutable_object_schema();
    user_schema->set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);
    auto& user_props = *user_schema->mutable_properties();
    auto& user_name = user_props["name"];
    user_name.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_STRING);
    user_schema->add_required("name");

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    // Inner property "user" gets seeded from object_schema (yielding type/
    // properties/required) then property-level type=object overrides.
    const char* expected =
        "{\"properties\":"
        "{\"user\":"
        "{\"properties\":{\"name\":{\"type\":\"string\"}},"
        "\"required\":[\"name\"],"
        "\"type\":\"object\"}"
        "},"
        "\"type\":\"object\"}";
    ASSERT_EQ_STR(actual.c_str(), expected);
    return 0;
}

// Case 3: array root with primitive element schema. Schema-level `items` is a
// JSONSchemaProperty; its writer produces {"type":"string"}.
int test_array_root() {
    ::runanywhere::v1::JSONSchema schema;
    schema.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_ARRAY);
    auto* items = schema.mutable_items();
    items->set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_STRING);

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    const char* expected = R"({"items":{"type":"string"},"type":"array"})";
    ASSERT_EQ_STR(actual.c_str(), expected);
    return 0;
}

// Case 4: enum + description on a property. Verifies enum_values are emitted
// as a JSON array via the property writer.
int test_property_with_enum() {
    ::runanywhere::v1::JSONSchema schema;
    schema.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);
    auto& properties = *schema.mutable_properties();
    auto& status = properties["status"];
    status.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_STRING);
    status.set_description("Lifecycle state");
    status.add_enum_values("active");
    status.add_enum_values("inactive");

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    // sortedKeys: description ("d"), enum ("e"), type ("t").
    const char* expected =
        "{\"properties\":"
        "{\"status\":"
        "{\"description\":\"Lifecycle state\","
        "\"enum\":[\"active\",\"inactive\"],"
        "\"type\":\"string\"}"
        "},"
        "\"type\":\"object\"}";
    ASSERT_EQ_STR(actual.c_str(), expected);
    return 0;
}

// Case 5: $ref + definitions. Verifies that '$' (0x24) sorts before lowercase
// letters and that nested definitions go through the schema writer.
int test_ref_and_definitions() {
    ::runanywhere::v1::JSONSchema schema;
    schema.set_ref("#/definitions/User");
    auto& definitions = *schema.mutable_definitions();
    auto& user_def = definitions["User"];
    user_def.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT);
    auto& user_props = *user_def.mutable_properties();
    auto& name = user_props["name"];
    name.set_type(::runanywhere::v1::JSON_SCHEMA_TYPE_STRING);

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    // '$' (0x24) sorts before 'd' (0x64), so $ref comes before definitions.
    const char* expected =
        "{\"$ref\":\"#/definitions/User\","
        "\"definitions\":"
        "{\"User\":"
        "{\"properties\":{\"name\":{\"type\":\"string\"}},"
        "\"type\":\"object\"}"
        "}"
        "}";
    ASSERT_EQ_STR(actual.c_str(), expected);
    return 0;
}

// Bonus case: top-level raw_json short-circuit. Mirrors Swift jsonSchemaString
// lines 32-34 — when raw_json is non-empty after trim, return it verbatim.
int test_raw_json_passthrough() {
    ::runanywhere::v1::JSONSchema schema;
    // Intentionally non-canonical: extra whitespace, mixed key order. Swift
    // returns this verbatim without re-canonicalization.
    schema.set_raw_json(R"(  { "type": "object", "x": 1 }  )");

    std::string actual;
    if (run_schema_to_json(schema, &actual) != 0) {
        return 1;
    }
    ASSERT_EQ_STR(actual.c_str(), R"(  { "type": "object", "x": 1 }  )");
    return 0;
}

#endif  // RAC_HAVE_PROTOBUF

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main() {
#if !defined(RAC_HAVE_PROTOBUF)
    std::printf("[schema_to_json] SKIP — built without RAC_HAVE_PROTOBUF\n");
    return 0;
#else
    TestCase cases[] = {
        {.name = "simple_object", .fn = test_simple_object},
        {.name = "nested_object", .fn = test_nested_object},
        {.name = "array_root", .fn = test_array_root},
        {.name = "property_with_enum", .fn = test_property_with_enum},
        {.name = "ref_and_definitions", .fn = test_ref_and_definitions},
        {.name = "raw_json_passthrough", .fn = test_raw_json_passthrough},
    };

    int failed = 0;
    const int count = static_cast<int>(sizeof(cases) / sizeof(cases[0]));
    for (const auto& test_case : cases) {
        std::printf("[schema_to_json] %s ... ", test_case.name);
        std::fflush(stdout);
        const int rc = test_case.fn();
        if (rc == 0) {
            std::printf("OK\n");
        } else {
            std::printf("FAIL\n");
            ++failed;
        }
    }
    std::printf("\n[schema_to_json] %d/%d passed\n", count - failed, count);
    return failed == 0 ? 0 : 1;
#endif
}
