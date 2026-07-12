/**
 * @file test_proto_buffer.cpp
 * @brief Tests for shared serialized proto buffer C ABI ownership helpers.
 */

#include <cstdio>
#include <cstring>
#include <limits>

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace {

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
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

int test_borrowed_input_validation_and_empty_parse_data() {
    const uint8_t bytes[] = {0x08, 0x01};

    ASSERT_EQ(rac_proto_bytes_validate(bytes, sizeof(bytes)), RAC_SUCCESS);
    ASSERT_TRUE(rac_proto_bytes_data_or_empty(bytes, sizeof(bytes)) == bytes);

    ASSERT_EQ(rac_proto_bytes_validate(nullptr, 0), RAC_SUCCESS);
    ASSERT_TRUE(rac_proto_bytes_data_or_empty(nullptr, 0) != nullptr);

    ASSERT_EQ(rac_proto_bytes_validate(nullptr, 1), RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(
        rac_proto_bytes_validate(bytes, static_cast<size_t>(std::numeric_limits<int>::max()) + 1U),
        RAC_ERROR_INVALID_ARGUMENT);
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

int test_zero_initialized_buffer_copy_and_free() {
    const uint8_t bytes[] = {0x0a, 0x01, 0x78};
    rac_proto_buffer_t buffer = {};

    ASSERT_EQ(rac_proto_buffer_copy(bytes, sizeof(bytes), &buffer), RAC_SUCCESS);
    ASSERT_TRUE(buffer.data != nullptr);
    ASSERT_EQ(buffer.size, sizeof(bytes));

    rac_proto_buffer_free(&buffer);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_TRUE(buffer.error_message == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);
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

int test_take_data_transfers_raw_ownership() {
    const uint8_t bytes[] = {0x12, 0x03, 0x6f, 0x6e, 0x65};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    uint8_t* out = nullptr;
    size_t size = 0;

    ASSERT_EQ(rac_proto_buffer_copy(bytes, sizeof(bytes), &buffer), RAC_SUCCESS);
    ASSERT_EQ(rac_proto_buffer_take_data(&buffer, &out, &size), RAC_SUCCESS);
    ASSERT_TRUE(out != nullptr);
    ASSERT_EQ(size, sizeof(bytes));
    ASSERT_EQ(std::memcmp(out, bytes, sizeof(bytes)), 0);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    rac_proto_buffer_free_data(out);
    rac_proto_buffer_free(&buffer);
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

int test_error_replaces_success_payload() {
    const uint8_t bytes[] = {0x01, 0x02};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_copy(bytes, sizeof(bytes), &buffer), RAC_SUCCESS);
    ASSERT_TRUE(buffer.data != nullptr);

    ASSERT_EQ(rac_proto_buffer_set_error(&buffer, RAC_ERROR_INVALID_FORMAT, "bad proto"),
              RAC_ERROR_INVALID_FORMAT);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_ERROR_INVALID_FORMAT);
    ASSERT_TRUE(buffer.error_message != nullptr);
    ASSERT_EQ(std::strcmp(buffer.error_message, "bad proto"), 0);

    rac_proto_buffer_free(&buffer);
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

int test_error_status_must_be_failure() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    ASSERT_EQ(rac_proto_buffer_set_error(&buffer, RAC_SUCCESS, "not an error"),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_TRUE(buffer.data == nullptr);
    ASSERT_TRUE(buffer.error_message == nullptr);
    ASSERT_EQ(buffer.size, 0U);
    ASSERT_EQ(buffer.status, RAC_SUCCESS);

    rac_proto_buffer_free(&buffer);
    return 0;
}

struct CallbackCapture {
    rac_result_t validation;
    const void* parse_data;
    size_t size;
};

void capture_proto_payload(const uint8_t* proto_bytes, size_t proto_size, void* user_data) {
    auto* capture = static_cast<CallbackCapture*>(user_data);
    capture->validation = rac_proto_bytes_validate(proto_bytes, proto_size);
    capture->parse_data = rac_proto_bytes_data_or_empty(proto_bytes, proto_size);
    capture->size = proto_size;
}

int test_stream_callback_payload_contract_compiles() {
    CallbackCapture capture = {.validation = RAC_ERROR_UNKNOWN, .parse_data = nullptr, .size = 99};
    rac_proto_bytes_callback_fn callback = capture_proto_payload;

    callback(nullptr, 0, &capture);
    ASSERT_EQ(capture.validation, RAC_SUCCESS);
    ASSERT_TRUE(capture.parse_data != nullptr);
    ASSERT_EQ(capture.size, 0U);
    return 0;
}

}  // namespace

int main() {
    int failures = 0;

#define RUN(name)                                \
    do {                                         \
        std::printf("[ RUN  ] %s\n", #name);     \
        int rc = name();                         \
        if (rc == 0)                             \
            std::printf("[  OK  ] %s\n", #name); \
        else {                                   \
            std::printf("[ FAIL ] %s\n", #name); \
            ++failures;                          \
        }                                        \
    } while (0)

    RUN(test_null_input_handling);
    RUN(test_borrowed_input_validation_and_empty_parse_data);
    RUN(test_empty_output_handling);
    RUN(test_zero_initialized_buffer_copy_and_free);
    RUN(test_successful_copy_and_free);
    RUN(test_take_data_transfers_raw_ownership);
    RUN(test_repeated_struct_free_is_safe);
    RUN(test_error_replaces_success_payload);
    RUN(test_error_status_propagation);
    RUN(test_error_status_must_be_failure);
    RUN(test_stream_callback_payload_contract_compiles);

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
