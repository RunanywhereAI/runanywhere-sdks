/**
 * @file test_proto_buffer.cpp
 * @brief Tests for shared serialized proto buffer C ABI ownership helpers.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace {

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    if (!((a) == (b))) { \
        std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

int test_null_input_handling() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_copy(nullptr, 3, &buffer), RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_ERROR_INVALID_ARGUMENT);

    rac_proto_buffer_free(&buffer);
    return 0;
}

int test_empty_output_handling() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_copy(nullptr, 0, &buffer), RAC_SUCCESS);
    ASSERT_TRUE(buffer.data != nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    rac_proto_buffer_free(&buffer);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    return 0;
}

int test_successful_copy_and_free() {
    const uint8_t bytes[] = {0x08, 0x96, 0x01, 0x12, 0x03};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_copy(bytes, sizeof(bytes), &buffer), RAC_SUCCESS);
    ASSERT_TRUE(buffer.data != nullptr);
    ASSERT_TRUE(buffer.data != bytes);
    ASSERT_EQ(buffer.size, sizeof(bytes));
    ASSERT_EQ(std::memcmp(buffer.data, bytes, sizeof(bytes)), 0);

    rac_proto_buffer_free(&buffer);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);
    return 0;
}

int test_repeated_struct_free_is_safe() {
    const uint8_t bytes[] = {0x01};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_copy(bytes, sizeof(bytes), &buffer), RAC_SUCCESS);
    rac_proto_buffer_free(&buffer);
    rac_proto_buffer_free(&buffer);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_TRUE(buffer.error_message == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);
    return 0;
}

int test_error_status_propagation() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_set_error(&buffer, RAC_ERROR_NOT_FOUND, "missing model"),
              RAC_ERROR_NOT_FOUND);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_ERROR_NOT_FOUND);
    ASSERT_TRUE(buffer.error_message != nullptr);
    ASSERT_EQ(std::strcmp(buffer.error_message, "missing model"), 0);

    rac_proto_buffer_free(&buffer);
    ASSERT_TRUE(buffer.error_message == nullptr);
    return 0;
}

int test_raw_compatibility_helper() {
    const uint8_t bytes[] = {0x0a, 0x02, 0x6f, 0x6b};
    uint8_t* out = nullptr;
    size_t size = 0;

    ASSERT_EQ(rac_proto_buffer_copy_to_raw(bytes, sizeof(bytes), &out, &size), RAC_SUCCESS);
    ASSERT_TRUE(out != nullptr);
    ASSERT_EQ(size, sizeof(bytes));
    ASSERT_EQ(std::memcmp(out, bytes, sizeof(bytes)), 0);
    rac_proto_buffer_free_data(out);

    out = const_cast<uint8_t*>(bytes);
    size = 7;
    ASSERT_EQ(rac_proto_buffer_copy_to_raw(nullptr, 1, &out, &size),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_TRUE(out == nullptr);
    ASSERT_EQ(size, 0U);
    return 0;
}

}  // namespace

int main() {
    int failures = 0;

#define RUN(name) do { \
    std::printf("[ RUN  ] %s\n", #name); \
    int rc = name(); \
    if (rc == 0) std::printf("[  OK  ] %s\n", #name); \
    else        { std::printf("[ FAIL ] %s\n", #name); ++failures; } \
} while (0)

    RUN(test_null_input_handling);
    RUN(test_empty_output_handling);
    RUN(test_successful_copy_and_free);
    RUN(test_repeated_struct_free_is_safe);
    RUN(test_error_status_propagation);
    RUN(test_raw_compatibility_helper);

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
