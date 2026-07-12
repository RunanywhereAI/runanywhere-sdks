/**
 * @file test_sdk_init.cpp
 * @brief Parity coverage for the canonical two-phase SDK init ABI.
 *
 * Drives rac_sdk_init_phase1_proto + rac_sdk_init_phase2_proto +
 * rac_sdk_retry_http_proto with hand-built request bytes and verifies the
 * SdkInitResult envelope. Adapter callbacks are NOT mocked here — the test
 * runs in offline mode (no platform adapter, no auth manager storage, no
 * device registration callbacks), which exercises the offline-tolerant
 * branches that match Swift's setupHTTP fallback.
 */

#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/lifecycle/rac_sdk_init.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "errors.pb.h"
#include "sdk_init.pb.h"
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

using ::runanywhere::v1::SdkInitPhase1Request;
using ::runanywhere::v1::SdkInitPhase2Request;
using ::runanywhere::v1::SdkInitResult;

bool serialize_phase1(SdkInitPhase1Request& request, std::vector<uint8_t>& out) {
    const size_t size = request.ByteSizeLong();
    out.assign(size, 0u);
    if (size == 0)
        return true;
    return request.SerializeToArray(out.data(), static_cast<int>(out.size()));
}

bool parse_result(const rac_proto_buffer_t& buffer, SdkInitResult* result) {
    if (buffer.status != RAC_SUCCESS || buffer.data == nullptr)
        return false;
    return result->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

void run_phase1_development() {
    std::fprintf(stdout, "-- phase1 development env (no api key required) --\n");
    SdkInitPhase1Request request;
    request.set_environment(::runanywhere::v1::SDK_INIT_ENVIRONMENT_DEVELOPMENT);
    request.set_device_id("dev-device-uuid");

    std::vector<uint8_t> bytes;
    CHECK(serialize_phase1(request, bytes), "phase1 dev request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_init_phase1_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS, "phase1 dev returns RAC_SUCCESS");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "phase1 dev result parses");
    CHECK(result.phase() == ::runanywhere::v1::SDK_INIT_PHASE_ONE,
          "phase1 dev result reports SDK_INIT_PHASE_ONE");
    CHECK(result.success(), "phase1 dev succeeds");
    CHECK(rac_state_is_initialized(), "rac_state_is_initialized() after phase1");
    CHECK(rac_state_get_environment() == RAC_ENV_DEVELOPMENT,
          "rac_state_get_environment() == DEVELOPMENT");

    rac_proto_buffer_free(&out);
}

void run_phase1_production_validation_failure() {
    std::fprintf(stdout, "-- phase1 production env requires api key --\n");
    rac_state_shutdown();
    rac_auth_reset();

    SdkInitPhase1Request request;
    request.set_environment(::runanywhere::v1::SDK_INIT_ENVIRONMENT_PRODUCTION);
    // Intentionally omit api_key/base_url so validation rejects the input.

    std::vector<uint8_t> bytes;
    CHECK(serialize_phase1(request, bytes), "phase1 prod-missing-key serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_init_phase1_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS, "phase1 still returns RAC_SUCCESS for typed failure");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "phase1 prod-missing-key result parses");
    CHECK(!result.success(), "phase1 prod-missing-key reports success=false");
    CHECK(result.has_error(), "phase1 prod-missing-key carries SDKError");
    CHECK(result.error().c_abi_code() == RAC_ERROR_INVALID_ARGUMENT,
          "phase1 prod-missing-key carries RAC_ERROR_INVALID_ARGUMENT");

    rac_proto_buffer_free(&out);
}

void run_phase1_production_success() {
    std::fprintf(stdout, "-- phase1 production env with valid creds --\n");
    rac_state_shutdown();
    rac_auth_reset();

    SdkInitPhase1Request request;
    request.set_environment(::runanywhere::v1::SDK_INIT_ENVIRONMENT_PRODUCTION);
    request.set_api_key("prod_api_key_xxxxxxxxxxxxxxxx");
    request.set_base_url("https://api.runanywhere.ai");
    request.set_device_id("prod-device-uuid");

    std::vector<uint8_t> bytes;
    CHECK(serialize_phase1(request, bytes), "phase1 prod-valid serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_init_phase1_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS, "phase1 prod-valid returns RAC_SUCCESS");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "phase1 prod-valid result parses");
    CHECK(result.success(), "phase1 prod-valid succeeds");
    CHECK(result.phase() == ::runanywhere::v1::SDK_INIT_PHASE_ONE, "phase tagged");
    CHECK(rac_state_get_environment() == RAC_ENV_PRODUCTION,
          "rac_state_get_environment() == PRODUCTION");

    rac_proto_buffer_free(&out);
}

void run_phase2_offline_mode() {
    std::fprintf(stdout, "-- phase2 succeeds in offline mode --\n");
    // Phase 1 must have run; assume the previous test left state initialized.
    CHECK(rac_state_is_initialized(), "phase2 prereq: state already initialized");

    SdkInitPhase2Request request;
    std::vector<uint8_t> bytes;
    bytes.assign(request.ByteSizeLong(), 0u);
    if (!bytes.empty()) {
        CHECK(request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size())),
              "phase2 request serializes");
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_init_phase2_proto(bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS, "phase2 offline returns RAC_SUCCESS");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "phase2 result parses");
    CHECK(result.phase() == ::runanywhere::v1::SDK_INIT_PHASE_TWO,
          "phase2 result reports SDK_INIT_PHASE_TWO");
    CHECK(result.success(), "phase2 offline succeeds (offline tolerance)");
    // No auth callbacks registered → http_configured=false is the expected
    // offline-mode shape.
    CHECK(!result.http_configured(), "phase2 reports http_configured=false offline");

    rac_proto_buffer_free(&out);
}

void run_phase2_without_phase1() {
    std::fprintf(stdout, "-- phase2 fails when phase1 has not run --\n");
    rac_state_shutdown();
    rac_auth_reset();
    CHECK(!rac_state_is_initialized(), "state cleared between tests");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_init_phase2_proto(nullptr, 0, &out);
    CHECK(rc == RAC_SUCCESS, "phase2 still returns RAC_SUCCESS for typed failure");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "phase2 missing-phase1 result parses");
    CHECK(!result.success(), "phase2 missing-phase1 reports success=false");
    CHECK(result.error().c_abi_code() == RAC_ERROR_NOT_INITIALIZED,
          "phase2 missing-phase1 reports RAC_ERROR_NOT_INITIALIZED");

    rac_proto_buffer_free(&out);
}

void run_retry_http_no_external_config() {
    std::fprintf(stdout, "-- retryHTTP no-op when no usable external config --\n");
    // Re-init in development env so retry is a no-op.
    SdkInitPhase1Request request;
    request.set_environment(::runanywhere::v1::SDK_INIT_ENVIRONMENT_DEVELOPMENT);
    request.set_device_id("dev-device");
    std::vector<uint8_t> phase1_bytes;
    serialize_phase1(request, phase1_bytes);

    rac_proto_buffer_t phase1_out;
    rac_proto_buffer_init(&phase1_out);
    rac_sdk_init_phase1_proto(phase1_bytes.data(), phase1_bytes.size(), &phase1_out);
    rac_proto_buffer_free(&phase1_out);

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_sdk_retry_http_proto(&out);
    CHECK(rc == RAC_SUCCESS, "retryHTTP returns RAC_SUCCESS");

    SdkInitResult result;
    CHECK(parse_result(out, &result), "retryHTTP result parses");
    CHECK(result.phase() == ::runanywhere::v1::SDK_INIT_PHASE_RETRY_HTTP,
          "retryHTTP result reports SDK_INIT_PHASE_RETRY_HTTP");
    CHECK(result.success(), "retryHTTP no-op reports success=true");
    CHECK(!result.http_configured(),
          "retryHTTP without external config reports http_configured=false");
    CHECK(!result.warning().empty(), "retryHTTP warning is set for the no-op branch");

    rac_proto_buffer_free(&out);
}

void run_invalid_arguments() {
    std::fprintf(stdout, "-- invalid argument handling --\n");
    const rac_result_t rc1 = rac_sdk_init_phase1_proto(nullptr, 0, nullptr);
    CHECK(rc1 == RAC_ERROR_INVALID_ARGUMENT, "phase1 NULL out_buffer rejected");
    const rac_result_t rc2 = rac_sdk_init_phase2_proto(nullptr, 0, nullptr);
    CHECK(rc2 == RAC_ERROR_INVALID_ARGUMENT, "phase2 NULL out_buffer rejected");
    const rac_result_t rc3 = rac_sdk_retry_http_proto(nullptr);
    CHECK(rc3 == RAC_ERROR_INVALID_ARGUMENT, "retryHTTP NULL out_buffer rejected");
}

void run_sdk_config_reset() {
    std::fprintf(stdout, "-- sdk config reset wipes copied credentials --\n");
    CHECK(rac_sdk_is_initialized(), "sdk config initialized before reset");
    CHECK(rac_sdk_get_config() != nullptr, "sdk config snapshot available before reset");

    rac_sdk_reset();

    CHECK(!rac_sdk_is_initialized(), "sdk config reports uninitialized after reset");
    CHECK(rac_sdk_get_config() == nullptr, "sdk config snapshot unavailable after reset");
    CHECK(rac_sdk_get_environment() == RAC_ENV_DEVELOPMENT,
          "sdk environment returns non-sensitive default after reset");
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

int main() {
    std::fprintf(stdout, "test_sdk_init\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: rac_sdk_init_*_proto requires protobuf runtime\n");
    return 0;
#else
    run_invalid_arguments();
    run_phase1_development();
    run_phase1_production_validation_failure();
    run_phase1_production_success();
    run_phase2_offline_mode();
    run_phase2_without_phase1();
    run_retry_http_no_external_config();
    run_sdk_config_reset();

    rac_state_shutdown();
    rac_auth_reset();

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
