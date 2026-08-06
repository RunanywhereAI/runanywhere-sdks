/**
 * @file test_schema_to_json.cpp
 * @brief Coverage for rac_structured_output_schema_to_json_proto.
 *
 * idl/structured_output.proto (API-realignment pass, so-p1) deleted the
 * typed JSON-Schema-in-protobuf tree this suite used to exercise: enum
 * JSONSchemaType and messages JSONSchemaProperty / JSONSchema are gone
 * outright — StructuredOutputOptions.schema is now a single JSON Schema
 * STRING (the `oneof constraint` arm), so there is no longer any typed tree
 * for this ABI to walk or for this test to build fixtures against. Every
 * case this file used to cover (simple object, nested object, array root,
 * enum property, $ref/definitions, raw_json passthrough) tested that walker
 * directly; with the walker's input type deleted, that behavior is
 * structurally gone, not just moved.
 *
 * schema_to_json.cpp (the implementation under test) now reports the
 * removal as a typed, non-silent RAC_ERROR_FEATURE_NOT_AVAILABLE for any
 * input rather than attempting to parse a message that no longer exists.
 * This is the one behavior left to verify.
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

namespace {

#define ASSERT_TRUE(cond)                                                                 \
    do {                                                                                  \
        if (!(cond)) {                                                                    \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: " #cond "\n", __FILE__, __LINE__); \
            return 1;                                                                     \
        }                                                                                 \
    } while (0)

// The input runanywhere.v1.JSONSchema type was deleted, so this test can no
// longer build a real fixture. It instead confirms the ABI's documented
// removed-feature contract: any input (including empty/null) yields a typed
// RAC_ERROR_FEATURE_NOT_AVAILABLE, not a silent no-op or a crash on the now-
// nonexistent proto type.
int test_schema_to_json_reports_feature_removed() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_structured_output_schema_to_json_proto(nullptr, 0, &buffer);
    ASSERT_TRUE(rc == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    ASSERT_TRUE(buffer.status == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    ASSERT_TRUE(buffer.error_message != nullptr);
    rac_proto_buffer_free(&buffer);

    // Arbitrary non-empty bytes must not change the outcome — the ABI never
    // attempts to parse them (the target type no longer exists to parse
    // into).
    const uint8_t arbitrary[] = {0x01, 0x02, 0x03};
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc2 =
        rac_structured_output_schema_to_json_proto(arbitrary, sizeof(arbitrary), &buffer);
    ASSERT_TRUE(rc2 == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    ASSERT_TRUE(buffer.status == RAC_ERROR_FEATURE_NOT_AVAILABLE);
    rac_proto_buffer_free(&buffer);
    return 0;
}

struct TestCase {
    const char* name;
    int (*fn)();
};

}  // namespace

int main() {
    TestCase cases[] = {
        {.name = "schema_to_json_reports_feature_removed",
         .fn = test_schema_to_json_reports_feature_removed},
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
}
