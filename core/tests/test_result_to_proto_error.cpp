/**
 * @file test_result_to_proto_error.cpp
 * @brief Parity test for `rac_result_to_proto_error()`.
 *
 * For every canonical `rac_result_t` constant from `rac_error.h`, asserts:
 *   1. The function returns RAC_SUCCESS.
 *   2. The serialized proto round-trips through ParseFromArray.
 *   3. The deserialized SDKError.code matches abs(input).
 *   4. SDKError.c_abi_code preserves the original signed value.
 *   5. SDKError.message is non-empty.
 *   6. SDKError.category is one of the canonical 9 buckets (>= 0, <= 8).
 *
 * Skips cleanly when RAC_HAVE_PROTOBUF is not defined (consistent with the
 * sibling `test_proto_buffer.cpp` and `test_sdk_event_stream.cpp` patterns).
 */

#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_error_proto.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
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
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

// Round-trip a single rac_result_t via rac_result_to_proto_error and validate
// the resulting SDKError. Returns true on full success.
bool round_trip_one(rac_result_t code, const char* label) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    rac_result_t rc = rac_result_to_proto_error(code, &buffer);
    bool ok = (rc == RAC_SUCCESS);
    CHECK(rc == RAC_SUCCESS, label);

    if (!ok) {
        rac_proto_buffer_free(&buffer);
        return false;
    }
    CHECK(buffer.data != nullptr, label);
    CHECK(buffer.status == RAC_SUCCESS, label);

    ::runanywhere::v1::SDKError parsed;
    const bool parse_ok = parsed.ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    CHECK(parse_ok, label);
    if (!parse_ok) {
        rac_proto_buffer_free(&buffer);
        return false;
    }

    const int32_t expected_signed = static_cast<int32_t>(code);
    const int32_t expected_abs = expected_signed < 0 ? -expected_signed : expected_signed;

    CHECK(static_cast<int32_t>(parsed.code()) == expected_abs, label);
    CHECK(parsed.c_abi_code() == expected_signed, label);

    // category bucket: must be one of the 9 canonical values
    const int category = static_cast<int>(parsed.category());
    CHECK(category >= 0 && category <= 8, label);

    // For real errors (non-success), category must NOT be UNSPECIFIED — that
    // would indicate the canonical mapping forgot a range.
    if (code != RAC_SUCCESS) {
        CHECK(category != static_cast<int>(::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED), label);
    }

    // message is required, non-empty, and not the literal "Unknown error code"
    // for codes that the C ABI knows about.
    const std::string& msg = parsed.message();
    CHECK(!msg.empty(), label);
    if (code != RAC_SUCCESS) {
        CHECK(msg != "Unknown error code", label);
    }

    rac_proto_buffer_free(&buffer);
    return true;
}

#define ROUND_TRIP(code) round_trip_one((code), #code)

void test_all_canonical_codes() {
    // Initialization (-100..-109)
    ROUND_TRIP(RAC_ERROR_NOT_INITIALIZED);
    ROUND_TRIP(RAC_ERROR_ALREADY_INITIALIZED);
    ROUND_TRIP(RAC_ERROR_INITIALIZATION_FAILED);
    ROUND_TRIP(RAC_ERROR_INVALID_CONFIGURATION);
    ROUND_TRIP(RAC_ERROR_INVALID_API_KEY);
    ROUND_TRIP(RAC_ERROR_ENVIRONMENT_MISMATCH);
    ROUND_TRIP(RAC_ERROR_INVALID_PARAMETER);

    // Model (-110..-129)
    ROUND_TRIP(RAC_ERROR_MODEL_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_MODEL_LOAD_FAILED);
    ROUND_TRIP(RAC_ERROR_MODEL_VALIDATION_FAILED);
    ROUND_TRIP(RAC_ERROR_MODEL_INCOMPATIBLE);
    ROUND_TRIP(RAC_ERROR_INVALID_MODEL_FORMAT);
    ROUND_TRIP(RAC_ERROR_MODEL_STORAGE_CORRUPTED);
    ROUND_TRIP(RAC_ERROR_MODEL_NOT_LOADED);

    // Generation (-130..-149)
    ROUND_TRIP(RAC_ERROR_GENERATION_FAILED);
    ROUND_TRIP(RAC_ERROR_GENERATION_TIMEOUT);
    ROUND_TRIP(RAC_ERROR_CONTEXT_TOO_LONG);
    ROUND_TRIP(RAC_ERROR_TOKEN_LIMIT_EXCEEDED);
    ROUND_TRIP(RAC_ERROR_COST_LIMIT_EXCEEDED);
    ROUND_TRIP(RAC_ERROR_INFERENCE_FAILED);

    // Network (-150..-179)
    ROUND_TRIP(RAC_ERROR_NETWORK_UNAVAILABLE);
    ROUND_TRIP(RAC_ERROR_NETWORK_ERROR);
    ROUND_TRIP(RAC_ERROR_REQUEST_FAILED);
    ROUND_TRIP(RAC_ERROR_DOWNLOAD_FAILED);
    ROUND_TRIP(RAC_ERROR_SERVER_ERROR);
    ROUND_TRIP(RAC_ERROR_TIMEOUT);
    ROUND_TRIP(RAC_ERROR_INVALID_RESPONSE);
    ROUND_TRIP(RAC_ERROR_HTTP_ERROR);
    ROUND_TRIP(RAC_ERROR_CONNECTION_LOST);
    ROUND_TRIP(RAC_ERROR_PARTIAL_DOWNLOAD);
    ROUND_TRIP(RAC_ERROR_HTTP_REQUEST_FAILED);
    ROUND_TRIP(RAC_ERROR_HTTP_NOT_SUPPORTED);

    // Storage (-180..-219)
    ROUND_TRIP(RAC_ERROR_INSUFFICIENT_STORAGE);
    ROUND_TRIP(RAC_ERROR_STORAGE_FULL);
    ROUND_TRIP(RAC_ERROR_STORAGE_ERROR);
    ROUND_TRIP(RAC_ERROR_FILE_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_FILE_READ_FAILED);
    ROUND_TRIP(RAC_ERROR_FILE_WRITE_FAILED);
    ROUND_TRIP(RAC_ERROR_PERMISSION_DENIED);
    ROUND_TRIP(RAC_ERROR_DELETE_FAILED);
    ROUND_TRIP(RAC_ERROR_MOVE_FAILED);
    ROUND_TRIP(RAC_ERROR_DIRECTORY_CREATION_FAILED);
    ROUND_TRIP(RAC_ERROR_DIRECTORY_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_INVALID_PATH);
    ROUND_TRIP(RAC_ERROR_INVALID_FILE_NAME);
    ROUND_TRIP(RAC_ERROR_TEMP_FILE_CREATION_FAILED);

    // Hardware (-220..-229)
    ROUND_TRIP(RAC_ERROR_HARDWARE_UNSUPPORTED);
    ROUND_TRIP(RAC_ERROR_INSUFFICIENT_MEMORY);

    // Component state (-230..-249)
    ROUND_TRIP(RAC_ERROR_COMPONENT_NOT_READY);
    ROUND_TRIP(RAC_ERROR_INVALID_STATE);
    ROUND_TRIP(RAC_ERROR_SERVICE_NOT_AVAILABLE);
    ROUND_TRIP(RAC_ERROR_SERVICE_BUSY);
    ROUND_TRIP(RAC_ERROR_PROCESSING_FAILED);
    ROUND_TRIP(RAC_ERROR_START_FAILED);
    ROUND_TRIP(RAC_ERROR_NOT_SUPPORTED);

    // Validation (-250..-279)
    ROUND_TRIP(RAC_ERROR_VALIDATION_FAILED);
    ROUND_TRIP(RAC_ERROR_INVALID_INPUT);
    ROUND_TRIP(RAC_ERROR_INVALID_FORMAT);
    ROUND_TRIP(RAC_ERROR_EMPTY_INPUT);
    ROUND_TRIP(RAC_ERROR_TEXT_TOO_LONG);
    ROUND_TRIP(RAC_ERROR_INVALID_SSML);
    ROUND_TRIP(RAC_ERROR_INVALID_SPEAKING_RATE);
    ROUND_TRIP(RAC_ERROR_INVALID_PITCH);
    ROUND_TRIP(RAC_ERROR_INVALID_VOLUME);
    ROUND_TRIP(RAC_ERROR_INVALID_ARGUMENT);
    ROUND_TRIP(RAC_ERROR_NULL_POINTER);
    ROUND_TRIP(RAC_ERROR_BUFFER_TOO_SMALL);

    // Audio (-280..-299)
    ROUND_TRIP(RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED);
    ROUND_TRIP(RAC_ERROR_AUDIO_SESSION_FAILED);
    ROUND_TRIP(RAC_ERROR_MICROPHONE_PERMISSION_DENIED);
    ROUND_TRIP(RAC_ERROR_INSUFFICIENT_AUDIO_DATA);
    ROUND_TRIP(RAC_ERROR_EMPTY_AUDIO_BUFFER);
    ROUND_TRIP(RAC_ERROR_AUDIO_SESSION_ACTIVATION_FAILED);

    // Language / voice (-300..-319)
    ROUND_TRIP(RAC_ERROR_LANGUAGE_NOT_SUPPORTED);
    ROUND_TRIP(RAC_ERROR_VOICE_NOT_AVAILABLE);
    ROUND_TRIP(RAC_ERROR_STREAMING_NOT_SUPPORTED);
    ROUND_TRIP(RAC_ERROR_STREAM_CANCELLED);

    // Authentication (-320..-329)
    ROUND_TRIP(RAC_ERROR_AUTHENTICATION_FAILED);
    ROUND_TRIP(RAC_ERROR_UNAUTHORIZED);
    ROUND_TRIP(RAC_ERROR_FORBIDDEN);

    // Security (-330..-349)
    ROUND_TRIP(RAC_ERROR_KEYCHAIN_ERROR);
    ROUND_TRIP(RAC_ERROR_ENCODING_ERROR);
    ROUND_TRIP(RAC_ERROR_DECODING_ERROR);
    ROUND_TRIP(RAC_ERROR_SECURE_STORAGE_FAILED);

    // Extraction (-350..-369)
    ROUND_TRIP(RAC_ERROR_EXTRACTION_FAILED);
    ROUND_TRIP(RAC_ERROR_CHECKSUM_MISMATCH);
    ROUND_TRIP(RAC_ERROR_UNSUPPORTED_ARCHIVE);

    // Calibration (-370..-379)
    ROUND_TRIP(RAC_ERROR_CALIBRATION_FAILED);
    ROUND_TRIP(RAC_ERROR_CALIBRATION_TIMEOUT);

    // Cancellation (-380..-389)
    ROUND_TRIP(RAC_ERROR_CANCELLED);

    // Module / service (-400..-499)
    ROUND_TRIP(RAC_ERROR_MODULE_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_MODULE_ALREADY_REGISTERED);
    ROUND_TRIP(RAC_ERROR_MODULE_LOAD_FAILED);
    ROUND_TRIP(RAC_ERROR_SERVICE_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_SERVICE_ALREADY_REGISTERED);
    ROUND_TRIP(RAC_ERROR_SERVICE_CREATE_FAILED);
    ROUND_TRIP(RAC_ERROR_CAPABILITY_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_PROVIDER_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_NO_CAPABLE_PROVIDER);
    ROUND_TRIP(RAC_ERROR_NOT_FOUND);

    // Platform adapter (-500..-599)
    ROUND_TRIP(RAC_ERROR_ADAPTER_NOT_SET);

    // Backend (-600..-699)
    ROUND_TRIP(RAC_ERROR_BACKEND_NOT_FOUND);
    ROUND_TRIP(RAC_ERROR_BACKEND_NOT_READY);
    ROUND_TRIP(RAC_ERROR_BACKEND_INIT_FAILED);
    ROUND_TRIP(RAC_ERROR_BACKEND_BUSY);
    ROUND_TRIP(RAC_ERROR_BACKEND_UNAVAILABLE);
    ROUND_TRIP(RAC_ERROR_INVALID_HANDLE);

    // Event (-700..-799)
    ROUND_TRIP(RAC_ERROR_EVENT_INVALID_CATEGORY);
    ROUND_TRIP(RAC_ERROR_EVENT_SUBSCRIPTION_FAILED);
    ROUND_TRIP(RAC_ERROR_EVENT_PUBLISH_FAILED);

    // Other (-800..-899)
    ROUND_TRIP(RAC_ERROR_NOT_IMPLEMENTED);
    ROUND_TRIP(RAC_ERROR_FEATURE_NOT_AVAILABLE);
    ROUND_TRIP(RAC_ERROR_FRAMEWORK_NOT_AVAILABLE);
    ROUND_TRIP(RAC_ERROR_UNSUPPORTED_MODALITY);
    ROUND_TRIP(RAC_ERROR_UNKNOWN);
    ROUND_TRIP(RAC_ERROR_INTERNAL);

    // Plugin (-810..-829)
    ROUND_TRIP(RAC_ERROR_ABI_VERSION_MISMATCH);
    ROUND_TRIP(RAC_ERROR_CAPABILITY_UNSUPPORTED);
    ROUND_TRIP(RAC_ERROR_PLUGIN_DUPLICATE);
    ROUND_TRIP(RAC_ERROR_PLUGIN_LOAD_FAILED);
    ROUND_TRIP(RAC_ERROR_PLUGIN_BUSY);
}

void test_null_buffer_returns_invalid_argument() {
    const rac_result_t rc = rac_result_to_proto_error(RAC_ERROR_MODEL_NOT_FOUND, nullptr);
    CHECK(rc == RAC_ERROR_INVALID_ARGUMENT, "null buffer rejected");
}

void test_canonical_category_ranges() {
    struct Case {
        rac_result_t code;
        ::runanywhere::v1::ErrorCategory category;
    };
    const Case cases[] = {
        {static_cast<rac_result_t>(-100), ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION},
        {static_cast<rac_result_t>(-109), ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION},
        {static_cast<rac_result_t>(-110), ::runanywhere::v1::ERROR_CATEGORY_MODEL},
        {static_cast<rac_result_t>(-129), ::runanywhere::v1::ERROR_CATEGORY_MODEL},
        {static_cast<rac_result_t>(-130), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-149), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-150), ::runanywhere::v1::ERROR_CATEGORY_NETWORK},
        {static_cast<rac_result_t>(-179), ::runanywhere::v1::ERROR_CATEGORY_NETWORK},
        {static_cast<rac_result_t>(-180), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-219), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-220), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-229), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-230), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-249), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-250), ::runanywhere::v1::ERROR_CATEGORY_VALIDATION},
        {static_cast<rac_result_t>(-279), ::runanywhere::v1::ERROR_CATEGORY_VALIDATION},
        {static_cast<rac_result_t>(-280), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-299), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-300), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-319), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-320), ::runanywhere::v1::ERROR_CATEGORY_AUTH},
        {static_cast<rac_result_t>(-349), ::runanywhere::v1::ERROR_CATEGORY_AUTH},
        {static_cast<rac_result_t>(-350), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-369), ::runanywhere::v1::ERROR_CATEGORY_IO},
        {static_cast<rac_result_t>(-370), ::runanywhere::v1::ERROR_CATEGORY_VALIDATION},
        {static_cast<rac_result_t>(-379), ::runanywhere::v1::ERROR_CATEGORY_VALIDATION},
        {static_cast<rac_result_t>(-380), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-389), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-400), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-499), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-500), ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION},
        {static_cast<rac_result_t>(-599), ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION},
        {static_cast<rac_result_t>(-600), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-699), ::runanywhere::v1::ERROR_CATEGORY_COMPONENT},
        {static_cast<rac_result_t>(-700), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
        {static_cast<rac_result_t>(-999), ::runanywhere::v1::ERROR_CATEGORY_INTERNAL},
    };
    for (const auto& test_case : cases) {
        CHECK(rac::foundation::rac_result_to_proto_category(test_case.code) == test_case.category,
              "canonical negative range boundary");
        CHECK(rac::foundation::rac_result_to_proto_category(-test_case.code) ==
                  ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED,
              "positive result is not an error");
        rac_proto_buffer_t buffer;
        rac_proto_buffer_init(&buffer);
        CHECK(rac_result_to_proto_error(test_case.code, &buffer) == RAC_SUCCESS,
              "range boundary serializes");
        ::runanywhere::v1::SDKError parsed;
        CHECK(parsed.ParseFromArray(buffer.data, static_cast<int>(buffer.size)),
              "range boundary proto parses");
        CHECK(parsed.category() == test_case.category, "serialized category matches mapper");
        CHECK(parsed.c_abi_code() == test_case.code, "serialized ABI code preserved");
        rac_proto_buffer_free(&buffer);
    }
    for (const rac_result_t code : {0, -1, -99, -390, -399, -1000, -12345, INT32_MIN}) {
        CHECK(rac::foundation::rac_result_to_proto_category(code) ==
                  ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED,
              "unmapped and minimum integer codes remain unspecified");
    }
}

void test_success_code_writes_default_proto() {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);

    const rac_result_t rc = rac_result_to_proto_error(RAC_SUCCESS, &buffer);
    CHECK(rc == RAC_SUCCESS, "RAC_SUCCESS round-trips");
    CHECK(buffer.status == RAC_SUCCESS, "RAC_SUCCESS buffer is success");

    ::runanywhere::v1::SDKError parsed;
    const bool parsed_ok = parsed.ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    CHECK(parsed_ok, "RAC_SUCCESS parses");
    // For RAC_SUCCESS we expect ERROR_CODE_UNSPECIFIED (= 0) and an empty
    // c_abi_code (which proto3 will report as 0 / has_c_abi_code() == false).
    CHECK(parsed.code() == ::runanywhere::v1::ERROR_CODE_UNSPECIFIED,
          "RAC_SUCCESS code is unspecified");
    CHECK(!parsed.has_c_abi_code(), "RAC_SUCCESS omits c_abi_code");

    rac_proto_buffer_free(&buffer);
}

void test_unknown_negative_code_is_handled() {
    // A code outside any known range still serializes; category falls back to
    // UNSPECIFIED, which IS allowed for genuinely unknown codes (not in the
    // canonical -100..-999 ranges).
    for (const rac_result_t code : {-12345, INT32_MIN}) {
        rac_proto_buffer_t buffer;
        rac_proto_buffer_init(&buffer);
        const rac_result_t rc = rac_result_to_proto_error(code, &buffer);
        CHECK(rc == RAC_SUCCESS, "unknown code still serializes");
        ::runanywhere::v1::SDKError parsed;
        CHECK(parsed.ParseFromArray(buffer.data, static_cast<int>(buffer.size)),
              "unknown code parses");
        CHECK(parsed.c_abi_code() == code, "unknown ABI code preserved");
        CHECK(parsed.category() == ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED,
              "unknown category is unspecified");
        if (code == INT32_MIN) {
            CHECK(parsed.code() == ::runanywhere::v1::ERROR_CODE_UNKNOWN,
                  "unrepresentable magnitude maps to UNKNOWN");
        }
        CHECK(!parsed.message().empty(), "unknown code message not empty");
        rac_proto_buffer_free(&buffer);
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
#if defined(RAC_HAVE_PROTOBUF)
    std::printf("[ RUN  ] test_all_canonical_codes\n");
    test_all_canonical_codes();
    std::printf("[ RUN  ] test_canonical_category_ranges\n");
    test_canonical_category_ranges();
    std::printf("[ RUN  ] test_null_buffer_returns_invalid_argument\n");
    test_null_buffer_returns_invalid_argument();
    std::printf("[ RUN  ] test_success_code_writes_default_proto\n");
    test_success_code_writes_default_proto();
    std::printf("[ RUN  ] test_unknown_negative_code_is_handled\n");
    test_unknown_negative_code_is_handled();

    std::printf("\n%d check(s), %d failure(s)\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#else
    std::printf("[ SKIP ] RAC_HAVE_PROTOBUF undefined; nothing to verify\n");
    return 0;
#endif
}
