/**
 * @file test_connect_proto_abi.cpp
 * @brief Contract tests for the transport-independent Connect policy and handshake.
 */

#include <cstdio>
#include <string>

#include "rac/connect/rac_connect.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "connect.pb.h"
#endif

namespace {

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

namespace v1 = runanywhere::v1;

template <typename Request, typename Response>
rac_result_t call_proto(rac_result_t (*function)(const uint8_t*, size_t, rac_proto_buffer_t*),
                        const Request& request, Response* response) {
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return RAC_ERROR_PROCESSING_FAILED;
    }

    rac_proto_buffer_t output;
    rac_proto_buffer_init(&output);
    const rac_result_t result = function(reinterpret_cast<const uint8_t*>(request_bytes.data()),
                                         request_bytes.size(), &output);
    if (result == RAC_SUCCESS && response != nullptr) {
        if (!response->ParseFromArray(output.data, static_cast<int>(output.size))) {
            rac_proto_buffer_free(&output);
            return RAC_ERROR_PROCESSING_FAILED;
        }
    }
    rac_proto_buffer_free(&output);
    return result;
}

void check_policy(v1::ConnectPlatform platform, v1::ConnectRoleAvailability expected_host,
                  v1::ConnectRoleAvailability expected_client, const char* label) {
    v1::ConnectPlatformPolicyRequest request;
    request.set_platform(platform);
    v1::ConnectPlatformPolicy policy;
    const rac_result_t result = call_proto(rac_connect_get_platform_policy_proto, request, &policy);
    CHECK(result == RAC_SUCCESS, label);
    if (result != RAC_SUCCESS) {
        return;
    }
    CHECK(policy.platform() == platform, "Connect policy preserves platform identity");
    CHECK(policy.host_role() == expected_host, "Connect policy exposes expected host role");
    CHECK(policy.client_role() == expected_client, "Connect policy exposes expected client role");
}

v1::ConnectHostStartRequest make_host_start(v1::ConnectPlatform platform) {
    v1::ConnectHostStartRequest request;
    request.set_display_name("Test Host");
    request.set_platform(platform);
    request.set_protocol_version(1);
    request.mutable_model()->set_model_id("test-model");
    request.mutable_model()->set_display_name("Test Model");
    request.mutable_model()->set_framework("Test Runtime");
    request.mutable_model()->set_context_window(4096);
    request.mutable_model()->set_supports_streaming(true);
    return request;
}

v1::ConnectClientHello make_client_hello(v1::ConnectPlatform platform,
                                         const std::string& instance_id = "client-instance") {
    v1::ConnectClientHello hello;
    hello.set_instance_id(instance_id);
    hello.set_display_name("Test Client");
    hello.set_platform(platform);
    hello.set_protocol_version(1);
    return hello;
}

void stop_host() {
    v1::ConnectHostStopRequest request;
    v1::ConnectHostState ignored;
    call_proto(rac_connect_host_stop_proto, request, &ignored);
}

void test_platform_role_policy() {
    check_policy(v1::CONNECT_PLATFORM_MACOS, v1::CONNECT_ROLE_AVAILABILITY_ENABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_DISABLED, "macOS is enabled as host only");
    check_policy(v1::CONNECT_PLATFORM_IOS, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_ENABLED, "iOS is enabled as client only");
    check_policy(v1::CONNECT_PLATFORM_IPADOS, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_ENABLED, "iPadOS is enabled as client only");
    check_policy(v1::CONNECT_PLATFORM_ANDROID, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_ENABLED, "Android is enabled as client only");
    check_policy(v1::CONNECT_PLATFORM_REACT_NATIVE, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_ENABLED, "React Native is enabled as client only");
    check_policy(v1::CONNECT_PLATFORM_FLUTTER, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_ENABLED, "Flutter is enabled as client only");
    check_policy(v1::CONNECT_PLATFORM_WEB, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_PLANNED, "Web client remains planned");
    check_policy(v1::CONNECT_PLATFORM_WINDOWS, v1::CONNECT_ROLE_AVAILABILITY_PLANNED,
                 v1::CONNECT_ROLE_AVAILABILITY_PLANNED, "Windows host and client remain planned");

    v1::ConnectPlatformPolicyRequest unspecified;
    v1::ConnectPlatformPolicy ignored;
    CHECK(call_proto(rac_connect_get_platform_policy_proto, unspecified, &ignored) ==
              RAC_ERROR_NOT_SUPPORTED,
          "Unspecified platform is rejected");
}

void test_client_admission() {
    for (const v1::ConnectPlatform platform :
         {v1::CONNECT_PLATFORM_IOS, v1::CONNECT_PLATFORM_IPADOS, v1::CONNECT_PLATFORM_ANDROID,
          v1::CONNECT_PLATFORM_REACT_NATIVE, v1::CONNECT_PLATFORM_FLUTTER}) {
        v1::ConnectClientStartRequest request;
        request.set_display_name("Portable Client");
        request.set_platform(platform);
        request.set_protocol_version(1);
        v1::ConnectClientHello hello;
        CHECK(call_proto(rac_connect_client_create_hello_proto, request, &hello) == RAC_SUCCESS,
              "Enabled mobile client can create a hello");
        CHECK(!hello.instance_id().empty(), "Commons assigns an ephemeral client instance id");
        CHECK(hello.platform() == platform, "Client hello preserves platform identity");
    }

    for (const v1::ConnectPlatform platform :
         {v1::CONNECT_PLATFORM_MACOS, v1::CONNECT_PLATFORM_WEB, v1::CONNECT_PLATFORM_WINDOWS}) {
        v1::ConnectClientStartRequest request;
        request.set_display_name("Unsupported Client");
        request.set_platform(platform);
        request.set_protocol_version(1);
        v1::ConnectClientHello ignored;
        CHECK(call_proto(rac_connect_client_create_hello_proto, request, &ignored) ==
                  RAC_ERROR_NOT_SUPPORTED,
              "Non-enabled client role is rejected by Commons");
    }
}

void test_host_handshake_and_reconnect_deduplication() {
    stop_host();

    v1::ConnectHostState host_state;
    const v1::ConnectHostStartRequest android_host = make_host_start(v1::CONNECT_PLATFORM_ANDROID);
    CHECK(call_proto(rac_connect_host_start_proto, android_host, &host_state) ==
              RAC_ERROR_NOT_SUPPORTED,
          "Android cannot start a Connect host");

    const v1::ConnectHostStartRequest mac_host = make_host_start(v1::CONNECT_PLATFORM_MACOS);
    CHECK(call_proto(rac_connect_host_start_proto, mac_host, &host_state) == RAC_SUCCESS,
          "macOS can start a Connect host");
    CHECK(host_state.is_hosting(), "Host state becomes active");
    CHECK(host_state.active_client_count() == 0, "New host begins without clients");

    const v1::ConnectClientHello first_hello =
        make_client_hello(v1::CONNECT_PLATFORM_ANDROID, "stable-client-id");
    v1::ConnectHandshakeResponse first_response;
    CHECK(call_proto(rac_connect_host_accept_client_proto, first_hello, &first_response) ==
              RAC_SUCCESS,
          "Host processes Android client hello");
    CHECK(first_response.status() == v1::CONNECT_HANDSHAKE_STATUS_ACCEPTED,
          "Android client handshake is accepted");
    CHECK(!first_response.session_id().empty(), "Accepted handshake creates a session id");

    v1::ConnectClientSessionState client_state;
    CHECK(call_proto(rac_connect_client_validate_host_proto, first_response, &client_state) ==
              RAC_SUCCESS,
          "Client validates accepted host response");
    CHECK(client_state.state() == v1::CONNECT_SESSION_STATE_CONNECTED,
          "Validated client state is connected");
    CHECK(client_state.model().model_id() == "test-model",
          "Validated client adopts the host model");

    v1::ConnectHandshakeResponse reconnect_response;
    CHECK(call_proto(rac_connect_host_accept_client_proto, first_hello, &reconnect_response) ==
              RAC_SUCCESS,
          "Same client instance can reconnect");
    CHECK(reconnect_response.session_id() != first_response.session_id(),
          "Reconnect replaces the stale session id");

    v1::ConnectHostState refreshed_state;
    CHECK(call_proto(rac_connect_host_start_proto, mac_host, &refreshed_state) == RAC_SUCCESS,
          "Active host state can be queried idempotently");
    CHECK(refreshed_state.active_client_count() == 1,
          "Reconnect does not inflate connected-device count");

    v1::ConnectSessionCloseRequest close_request;
    close_request.set_session_id(reconnect_response.session_id());
    v1::ConnectHostState closed_state;
    CHECK(call_proto(rac_connect_host_close_session_proto, close_request, &closed_state) ==
              RAC_SUCCESS,
          "Active client session closes cleanly");
    CHECK(closed_state.active_client_count() == 0,
          "Closing the session decrements connected-device count");

    v1::ConnectClientHello incompatible =
        make_client_hello(v1::CONNECT_PLATFORM_FLUTTER, "flutter-client");
    incompatible.set_protocol_version(2);
    v1::ConnectHandshakeResponse rejected;
    CHECK(call_proto(rac_connect_host_accept_client_proto, incompatible, &rejected) == RAC_SUCCESS,
          "Incompatible handshake returns a typed response");
    CHECK(rejected.status() == v1::CONNECT_HANDSHAKE_STATUS_REJECTED,
          "Protocol mismatch is rejected");

    stop_host();
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_connect_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: Connect proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_platform_role_policy();
    test_client_admission();
    test_host_handshake_and_reconnect_deduplication();
    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
#endif
}
