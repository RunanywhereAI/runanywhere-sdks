/**
 * @file test_tool_value_json.cpp
 * @brief Round-trip tests for the ToolValue <-> JSON proto-byte ABI (G3).
 *
 * Covers the 5 ToolValue oneof branches required by the Swift / Kotlin / Dart
 * / RN / Web SDKs that previously hand-wrote this walk:
 *   1. string
 *   2. number
 *   3. bool
 *   4. array  (recursive — mixed scalar + nested object)
 *   5. object (recursive — mixed scalars + nested array)
 */

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                 \
    do {                                                                                  \
        if (!(cond)) {                                                                    \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

#define ASSERT_EQ_INT(a, b)                                                                 \
    do {                                                                                    \
        if (static_cast<long long>(a) != static_cast<long long>(b)) {                       \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %lld != %lld\n", __FILE__, __LINE__, \
                         static_cast<long long>(a), static_cast<long long>(b));             \
            return 1;                                                                       \
        }                                                                                   \
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

// Helper: encode a ToolValue proto, run rac_tool_value_to_json_proto, decode
// ToolValueJSON, return JSON text.
//
// IMPORTANT: never wrap a call-with-side-effects in `assert()`. Release builds
// (-DNDEBUG) erase the expression entirely, so `assert(x.Serialize(&y))` would
// silently skip the serialization and leave `y` empty. Use `RAC_HARD_CHECK`
// instead — it always evaluates its argument and throws on failure so the
// test harness reports the failure clearly.
#define RAC_HARD_CHECK(expr)                                           \
    do {                                                               \
        if (!(expr)) {                                                 \
            throw std::runtime_error("RAC_HARD_CHECK failed: " #expr); \
        }                                                              \
    } while (0)

std::string to_json(const runanywhere::v1::ToolValue& value) {
    std::string bytes;
    RAC_HARD_CHECK(value.SerializeToString(&bytes));

    rac_proto_buffer_t out{};
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_value_to_json_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                   bytes.size(), &out);
    RAC_HARD_CHECK(rc == RAC_SUCCESS);
    RAC_HARD_CHECK(out.status == RAC_SUCCESS);

    runanywhere::v1::ToolValueJSON wrapper;
    RAC_HARD_CHECK(wrapper.ParseFromArray(out.data, static_cast<int>(out.size)));
    std::string json = wrapper.json();
    rac_proto_buffer_free(&out);
    return json;
}

// Helper: wrap JSON text in ToolValueJSON, run rac_tool_value_from_json_proto,
// decode and return the ToolValue.
runanywhere::v1::ToolValue from_json(const std::string& json_text) {
    runanywhere::v1::ToolValueJSON wrapper;
    wrapper.set_json(json_text);
    std::string bytes;
    RAC_HARD_CHECK(wrapper.SerializeToString(&bytes));

    rac_proto_buffer_t out{};
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tool_value_from_json_proto(reinterpret_cast<const uint8_t*>(bytes.data()),
                                                     bytes.size(), &out);
    RAC_HARD_CHECK(rc == RAC_SUCCESS);
    RAC_HARD_CHECK(out.status == RAC_SUCCESS);

    runanywhere::v1::ToolValue value;
    RAC_HARD_CHECK(value.ParseFromArray(out.data, static_cast<int>(out.size)));
    rac_proto_buffer_free(&out);
    return value;
}

#endif  // RAC_HAVE_PROTOBUF

// 1. string round-trip
int test_round_trip_string() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolValue value;
    value.set_string_value("San Francisco");

    std::string json = to_json(value);
    ASSERT_EQ_STR(json.c_str(), "\"San Francisco\"");

    auto parsed = from_json(json);
    ASSERT_EQ_INT(parsed.kind_case(), runanywhere::v1::ToolValue::kStringValue);
    ASSERT_EQ_STR(parsed.string_value().c_str(), "San Francisco");
    return 0;
#endif
}

// 2. number round-trip
int test_round_trip_number() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolValue value;
    value.set_number_value(42.5);

    std::string json = to_json(value);
    ASSERT_EQ_STR(json.c_str(), "42.5");

    auto parsed = from_json(json);
    ASSERT_EQ_INT(parsed.kind_case(), runanywhere::v1::ToolValue::kNumberValue);
    ASSERT_TRUE(parsed.number_value() == 42.5);
    return 0;
#endif
}

// 3. bool round-trip
int test_round_trip_bool() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolValue value;
    value.set_bool_value(true);

    std::string json = to_json(value);
    ASSERT_EQ_STR(json.c_str(), "true");

    auto parsed = from_json(json);
    ASSERT_EQ_INT(parsed.kind_case(), runanywhere::v1::ToolValue::kBoolValue);
    ASSERT_EQ_INT(parsed.bool_value() ? 1 : 0, 1);
    return 0;
#endif
}

// 4. array round-trip (mixed scalar + nested object)
int test_round_trip_array() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolValue value;
    auto* arr = value.mutable_array_value();
    arr->add_values()->set_string_value("hi");
    arr->add_values()->set_number_value(7.0);
    auto* nested = arr->add_values()->mutable_object_value();
    (*nested->mutable_fields())["k"].set_bool_value(false);

    std::string json = to_json(value);
    ASSERT_SUBSTR(json.c_str(), "\"hi\"");
    ASSERT_SUBSTR(json.c_str(), "7");
    ASSERT_SUBSTR(json.c_str(), "\"k\":false");
    ASSERT_TRUE(json.front() == '[' && json.back() == ']');

    auto parsed = from_json(json);
    ASSERT_EQ_INT(parsed.kind_case(), runanywhere::v1::ToolValue::kArrayValue);
    ASSERT_EQ_INT(parsed.array_value().values_size(), 3);
    ASSERT_EQ_STR(parsed.array_value().values(0).string_value().c_str(), "hi");
    ASSERT_TRUE(parsed.array_value().values(1).number_value() == 7.0);
    ASSERT_EQ_INT(parsed.array_value().values(2).kind_case(),
                  runanywhere::v1::ToolValue::kObjectValue);
    return 0;
#endif
}

// 5. object round-trip (mixed scalars + nested array)
int test_round_trip_object() {
#if !defined(RAC_HAVE_PROTOBUF)
    return 0;
#else
    runanywhere::v1::ToolValue value;
    auto& fields = *value.mutable_object_value()->mutable_fields();
    fields["name"].set_string_value("Alice");
    fields["age"].set_number_value(30.0);
    fields["active"].set_bool_value(true);
    fields["meta"].set_null_value(true);
    auto* nested_arr = fields["tags"].mutable_array_value();
    nested_arr->add_values()->set_string_value("a");
    nested_arr->add_values()->set_string_value("b");

    std::string json = to_json(value);
    ASSERT_TRUE(json.front() == '{' && json.back() == '}');
    ASSERT_SUBSTR(json.c_str(), "\"name\":\"Alice\"");
    ASSERT_SUBSTR(json.c_str(), "\"age\":30");
    ASSERT_SUBSTR(json.c_str(), "\"active\":true");
    ASSERT_SUBSTR(json.c_str(), "\"meta\":null");
    ASSERT_SUBSTR(json.c_str(), "\"tags\":[\"a\",\"b\"]");

    auto parsed = from_json(json);
    ASSERT_EQ_INT(parsed.kind_case(), runanywhere::v1::ToolValue::kObjectValue);
    const auto& out_fields = parsed.object_value().fields();
    ASSERT_EQ_INT(out_fields.size(), 5);
    ASSERT_EQ_STR(out_fields.at("name").string_value().c_str(), "Alice");
    ASSERT_TRUE(out_fields.at("age").number_value() == 30.0);
    ASSERT_EQ_INT(out_fields.at("active").bool_value() ? 1 : 0, 1);
    ASSERT_EQ_INT(out_fields.at("meta").kind_case(), runanywhere::v1::ToolValue::kNullValue);
    ASSERT_EQ_INT(out_fields.at("tags").array_value().values_size(), 2);
    return 0;
#endif
}

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;

    TestCase cases[] = {
        {"round_trip_string", test_round_trip_string},
        {"round_trip_number", test_round_trip_number},
        {"round_trip_bool", test_round_trip_bool},
        {"round_trip_array", test_round_trip_array},
        {"round_trip_object", test_round_trip_object},
    };

    int failures = 0;
    for (const auto& tc : cases) {
        std::fprintf(stderr, "[RUN ] %s\n", tc.name);
        int rc = 0;
        try {
            rc = tc.fn();
        } catch (const std::exception& e) {
            std::fprintf(stderr, "  exception: %s\n", e.what());
            rc = 1;
        }
        if (rc == 0) {
            std::fprintf(stderr, "[OK  ] %s\n", tc.name);
        } else {
            std::fprintf(stderr, "[FAIL] %s\n", tc.name);
            ++failures;
        }
    }

    std::fprintf(stderr, "\n%d/%zu tests passed.\n",
                 static_cast<int>(sizeof(cases) / sizeof(cases[0])) - failures,
                 sizeof(cases) / sizeof(cases[0]));
    return failures == 0 ? 0 : 1;
}
