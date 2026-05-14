/**
 * @file test_auth_sdk_events.cpp
 * @brief Auth manager coverage for canonical SDKEvent AuthEvent emissions.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/network/rac_auth_manager.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
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

bool poll_event(runanywhere::v1::SDKEvent* out) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_sdk_event_poll(&buffer);
    if (rc != RAC_SUCCESS) {
        return false;
    }
    const bool parsed = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return parsed;
}

constexpr const char* kAuthResponse =
    R"({"access_token":"access-1","refresh_token":"refresh-1","device_id":"device-1","user_id":"user-1","organization_id":"org-1","token_type":"bearer","expires_in":3600})";

constexpr const char* kRefreshResponse =
    R"({"access_token":"access-2","refresh_token":"refresh-2","device_id":"device-1","user_id":"user-1","organization_id":"org-1","token_type":"bearer","expires_in":7200})";

void expect_auth_envelope(const runanywhere::v1::SDKEvent& event,
                          runanywhere::v1::AuthEventKind kind, const char* operation) {
    CHECK(!event.id().empty(), "auth SDKEvent has id");
    CHECK(event.timestamp_ms() > 0, "auth SDKEvent has timestamp");
    CHECK(event.category() == runanywhere::v1::EVENT_CATEGORY_AUTH,
          "auth SDKEvent uses auth category");
    CHECK(event.source() == "cpp", "auth SDKEvent source is cpp");
    CHECK(event.operation_id() == operation, "auth SDKEvent carries operation id");
    CHECK(event.has_auth(), "auth SDKEvent uses AuthEvent payload");
    CHECK(event.auth().kind() == kind, "auth SDKEvent carries expected AuthEvent kind");
    CHECK(event.auth().provider() == "runanywhere", "auth SDKEvent carries provider");
    CHECK(event.auth().scope() == "sdk", "auth SDKEvent carries scope");
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_auth_sdk_events\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: auth SDKEvent tests (no protobuf)\n");
    return 0;
#else
    rac_auth_init(nullptr);
    rac_sdk_event_clear_queue();

    int rc = rac_auth_handle_authenticate_response(kAuthResponse);
    CHECK(rc == 0, "authenticate response is accepted");
    CHECK(rac_auth_is_authenticated(), "auth manager becomes authenticated");
    CHECK(std::strcmp(rac_auth_get_access_token(), "access-1") == 0,
          "auth manager stores access token");

    runanywhere::v1::SDKEvent auth_event;
    CHECK(poll_event(&auth_event), "authenticate response publishes SDKEvent");
    expect_auth_envelope(auth_event, runanywhere::v1::AUTH_EVENT_KIND_SUCCEEDED,
                         "auth.authenticate");
    CHECK(auth_event.severity() == runanywhere::v1::ERROR_SEVERITY_INFO,
          "authenticate success severity is info");
    CHECK(auth_event.auth().subject_id() == "user-1", "authenticate event carries subject");
    const auto device_property = auth_event.properties().find("device_id");
    CHECK(device_property != auth_event.properties().end() && device_property->second == "device-1",
          "authenticate event carries device id property");

    rac_sdk_event_clear_queue();
    rc = rac_auth_handle_refresh_response(kRefreshResponse);
    CHECK(rc == 0, "refresh response is accepted");
    CHECK(std::strcmp(rac_auth_get_access_token(), "access-2") == 0,
          "refresh updates access token");

    runanywhere::v1::SDKEvent refresh_event;
    CHECK(poll_event(&refresh_event), "refresh response publishes SDKEvent");
    expect_auth_envelope(refresh_event, runanywhere::v1::AUTH_EVENT_KIND_TOKEN_REFRESHED,
                         "auth.refresh");
    CHECK(refresh_event.severity() == runanywhere::v1::ERROR_SEVERITY_INFO,
          "refresh severity is info");

    rac_sdk_event_clear_queue();
    rc = rac_auth_handle_authenticate_response(R"({"access_token":"missing-refresh"})");
    CHECK(rc == -1, "invalid authenticate response is rejected");

    runanywhere::v1::SDKEvent failed_event;
    CHECK(poll_event(&failed_event), "invalid authenticate response publishes SDKEvent");
    expect_auth_envelope(failed_event, runanywhere::v1::AUTH_EVENT_KIND_FAILED,
                         "auth.authenticate");
    CHECK(failed_event.severity() == runanywhere::v1::ERROR_SEVERITY_ERROR,
          "auth failure severity is error");
    CHECK(failed_event.has_error(), "auth failure carries SDKError");
    CHECK(failed_event.error().c_abi_code() == RAC_ERROR_AUTHENTICATION_FAILED,
          "auth failure preserves C ABI error code");
    CHECK(failed_event.auth().error() == "Authentication response is invalid",
          "auth failure carries parse failure message");

    rac_auth_clear();
    rac_sdk_event_clear_queue();

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
