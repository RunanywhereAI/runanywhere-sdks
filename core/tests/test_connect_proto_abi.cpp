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
                 v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 "React Native Connect client is reserved but not shipped");
    check_policy(v1::CONNECT_PLATFORM_FLUTTER, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
                 "Flutter Connect client is reserved but not shipped");
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
         {v1::CONNECT_PLATFORM_IOS, v1::CONNECT_PLATFORM_IPADOS, v1::CONNECT_PLATFORM_ANDROID}) {
        v1::ConnectClientStartRequest request;
        request.set_display_name("Portable Client");
        request.set_platform(platform);
        request.set_protocol_version(1);
        v1::ConnectClientHello hello;
        CHECK(call_proto(rac_connect_client_create_hello_proto, request, &hello) == RAC_SUCCESS,
              "Enabled native mobile client can create a hello");
        CHECK(!hello.instance_id().empty(), "Commons assigns an ephemeral client instance id");
        CHECK(hello.platform() == platform, "Client hello preserves platform identity");
    }

    for (const v1::ConnectPlatform platform :
         {v1::CONNECT_PLATFORM_MACOS, v1::CONNECT_PLATFORM_REACT_NATIVE, v1::CONNECT_PLATFORM_FLUTTER,
          v1::CONNECT_PLATFORM_WEB, v1::CONNECT_PLATFORM_WINDOWS}) {
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

void test_session_cap_and_cancel_validation() {
    stop_host();

    v1::ConnectHostState host_state;
    const v1::ConnectHostStartRequest mac_host = make_host_start(v1::CONNECT_PLATFORM_MACOS);
    CHECK(call_proto(rac_connect_host_start_proto, mac_host, &host_state) == RAC_SUCCESS,
          "macOS host starts for session-cap tests");

    std::string last_session_id;
    for (int index = 0; index < 16; ++index) {
        const v1::ConnectClientHello hello =
            make_client_hello(v1::CONNECT_PLATFORM_ANDROID, "client-" + std::to_string(index));
        v1::ConnectHandshakeResponse response;
        CHECK(call_proto(rac_connect_host_accept_client_proto, hello, &response) == RAC_SUCCESS,
              "Distinct clients are admitted up to the session cap");
        CHECK(response.status() == v1::CONNECT_HANDSHAKE_STATUS_ACCEPTED,
              "Distinct client handshake is accepted under the cap");
        last_session_id = response.session_id();
    }

    v1::ConnectHostState capped_state;
    CHECK(call_proto(rac_connect_host_start_proto, mac_host, &capped_state) == RAC_SUCCESS,
          "Host state remains readable at the session cap");
    CHECK(capped_state.active_client_count() == 16, "Session registry reports 16 active clients");

    const v1::ConnectClientHello overflow =
        make_client_hello(v1::CONNECT_PLATFORM_ANDROID, "client-overflow");
    v1::ConnectHandshakeResponse rejected;
    CHECK(call_proto(rac_connect_host_accept_client_proto, overflow, &rejected) == RAC_SUCCESS,
          "Overflow handshake still returns a typed response");
    CHECK(rejected.status() == v1::CONNECT_HANDSHAKE_STATUS_REJECTED,
          "Overflow handshake is rejected at the session cap");

    v1::ConnectInvocationCancelRequest cancel;
    cancel.set_session_id(last_session_id);
    cancel.set_request_id("req-1");
    v1::ConnectInvocationValidation accepted;
    CHECK(call_proto(rac_connect_host_validate_cancel_proto, cancel, &accepted) == RAC_SUCCESS,
          "Cancel validation accepts an active session request");
    CHECK(accepted.accepted(), "Cancel validation marks the request accepted");

    v1::ConnectInvocationCancelRequest stale;
    stale.set_session_id("missing-session");
    stale.set_request_id("req-2");
    v1::ConnectInvocationValidation rejected_cancel;
    CHECK(call_proto(rac_connect_host_validate_cancel_proto, stale, &rejected_cancel) == RAC_SUCCESS,
          "Cancel validation returns a typed rejection for unknown sessions");
    CHECK(!rejected_cancel.accepted(), "Unknown-session cancel is rejected");

    stop_host();
}

void test_cluster_orchestration() {
    // Reset cluster runtime state to ensure clean test isolation
    {
        v1::ClusterStopRequest reset_request;
        v1::ClusterState reset_state;
        call_proto(rac_connect_cluster_stop_proto, reset_request, &reset_state);
    }

    // 1. Invalid cluster start (empty cluster id)
    v1::ClusterStartRequest invalid_request;
    v1::ClusterState invalid_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, invalid_request, &invalid_state) == RAC_ERROR_INVALID_ARGUMENT,
          "Cluster start rejects empty request");

    // 2. Invalid cluster start (duplicate instance_id)
    v1::ClusterStartRequest dup_request;
    dup_request.set_cluster_id("test-cluster-dup");
    dup_request.mutable_model()->set_model_id("llama-3-70b");
    dup_request.mutable_model()->set_display_name("Llama 3 70B");
    auto* d1 = dup_request.add_assignments();
    d1->set_instance_id("peer-1");
    d1->set_layer_start(0);
    d1->set_layer_end(16);
    auto* d2 = dup_request.add_assignments();
    d2->set_instance_id("peer-1");
    d2->set_layer_start(16);
    d2->set_layer_end(32);

    v1::ClusterState dup_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, dup_request, &dup_state) == RAC_ERROR_INVALID_ARGUMENT,
          "Cluster start rejects duplicate peer instance_id");

    // 3. Invalid cluster start (layer gap: [0, 10) and [15, 30))
    v1::ClusterStartRequest gap_request;
    gap_request.set_cluster_id("test-cluster-gap");
    gap_request.mutable_model()->set_model_id("llama-3-70b");
    gap_request.mutable_model()->set_display_name("Llama 3 70B");
    auto* a1 = gap_request.add_assignments();
    a1->set_instance_id("mac-coord");
    a1->set_layer_start(0);
    a1->set_layer_end(10);
    a1->set_is_coordinator(true);
    auto* a2 = gap_request.add_assignments();
    a2->set_instance_id("android-peer");
    a2->set_layer_start(15);
    a2->set_layer_end(30);

    v1::ClusterState gap_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, gap_request, &gap_state) == RAC_ERROR_INVALID_ARGUMENT,
          "Cluster start rejects layer assignment gap");

    // 4. Valid cluster start with unordered assignments: [16, 32) then [0, 16)
    v1::ClusterStartRequest valid_request;
    valid_request.set_cluster_id("cluster-alpha");
    valid_request.mutable_model()->set_model_id("llama-3-70b");
    valid_request.mutable_model()->set_display_name("Llama 3 70B");
    auto* v2_assign = valid_request.add_assignments();
    v2_assign->set_instance_id("android-snapdragon");
    v2_assign->set_layer_start(16);
    v2_assign->set_layer_end(32);

    auto* v1_assign = valid_request.add_assignments();
    v1_assign->set_instance_id("mac-coordinator");
    v1_assign->set_layer_start(0);
    v1_assign->set_layer_end(16);
    v1_assign->set_is_coordinator(true);

    v1::ClusterState active_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, valid_request, &active_state) == RAC_SUCCESS,
          "Cluster coordinator starts with valid layer sharding");
    CHECK(active_state.is_active(), "Cluster state is marked active");
    CHECK(active_state.peer_count() == 2, "Cluster state tracks 2 participating devices");
    CHECK(active_state.cluster_id() == "cluster-alpha", "Cluster ID matches request");

    // 5. Idempotent cluster start with same cluster_id
    v1::ClusterState idempotent_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, valid_request, &idempotent_state) == RAC_SUCCESS,
          "Repeated cluster start with same ID is idempotent");
    CHECK(idempotent_state.is_active(), "Idempotent start returns active state");

    // 6. Conflicting cluster start with different cluster_id while active is rejected
    v1::ClusterStartRequest conflict_request = valid_request;
    conflict_request.set_cluster_id("cluster-beta");
    v1::ClusterState conflict_state;
    CHECK(call_proto(rac_connect_cluster_start_proto, conflict_request, &conflict_state) == RAC_ERROR_INVALID_ARGUMENT,
          "Starting a different cluster while one is active is rejected");

    // 7. Peer joins cluster with ClusterJoinRequest
    v1::ClusterJoinRequest join_request;
    join_request.set_cluster_id("cluster-alpha");
    join_request.set_instance_id("android-snapdragon");
    join_request.mutable_peer_capability()->set_instance_id("android-snapdragon");
    join_request.mutable_peer_capability()->set_available_memory_bytes(8589934592ULL);
    join_request.mutable_peer_capability()->set_acceleration(v1::ACCELERATION_PREFERENCE_NPU);

    v1::ClusterStartResponse join_response;
    CHECK(call_proto(rac_connect_cluster_join_proto, join_request, &join_response) == RAC_SUCCESS,
          "Peer join request is validated successfully against active cluster");
    CHECK(join_response.accepted(), "Peer join response is accepted");
    CHECK(join_response.peer_capability().available_memory_bytes() == 8589934592ULL,
          "Peer capability is populated in join response");

    // 8. Peer join with unknown instance_id is rejected
    v1::ClusterJoinRequest unknown_peer_join = join_request;
    unknown_peer_join.set_instance_id("unknown-device");
    unknown_peer_join.mutable_peer_capability()->set_instance_id("unknown-device");
    v1::ClusterStartResponse unknown_peer_response;
    CHECK(call_proto(rac_connect_cluster_join_proto, unknown_peer_join, &unknown_peer_response) == RAC_SUCCESS,
          "Unknown peer join returns typed validation response");
    CHECK(!unknown_peer_response.accepted(), "Unknown peer instance_id is rejected");

    // 9. Activation validation between pipeline stages
    v1::ClusterActivation valid_activation;
    valid_activation.set_cluster_id("cluster-alpha");
    valid_activation.set_request_id("req-token-101");
    valid_activation.set_from_layer(16);
    valid_activation.set_tensor_data(std::string(4096 * 2, 'A'));
    valid_activation.set_seq_len(1);
    valid_activation.set_hidden_size(4096);

    v1::ConnectInvocationValidation activation_validation;
    CHECK(call_proto(rac_connect_cluster_validate_activation_proto, valid_activation, &activation_validation) == RAC_SUCCESS,
          "Valid intermediate activation tensor is validated");
    CHECK(activation_validation.accepted(), "Activation tensor passes validation");

    // 10. Activation validation rejection on mismatched cluster ID
    v1::ClusterActivation wrong_cluster_activation = valid_activation;
    wrong_cluster_activation.set_cluster_id("cluster-wrong");
    v1::ConnectInvocationValidation wrong_cluster_validation;
    CHECK(call_proto(rac_connect_cluster_validate_activation_proto, wrong_cluster_activation, &wrong_cluster_validation) == RAC_SUCCESS,
          "Mismatched cluster activation returns typed validation");
    CHECK(!wrong_cluster_validation.accepted(), "Mismatched cluster ID activation is rejected");

    // 11. Activation validation rejection on invalid layer boundary
    v1::ClusterActivation invalid_boundary_activation = valid_activation;
    invalid_boundary_activation.set_from_layer(7); // not a boundary in [0, 16) or [16, 32)
    v1::ConnectInvocationValidation invalid_boundary_validation;
    CHECK(call_proto(rac_connect_cluster_validate_activation_proto, invalid_boundary_activation, &invalid_boundary_validation) == RAC_SUCCESS,
          "Invalid layer boundary activation returns typed validation");
    CHECK(!invalid_boundary_validation.accepted(), "Invalid layer boundary is rejected");

    // 12. Stop cluster with mismatched cluster ID is rejected
    v1::ClusterStopRequest wrong_stop_request;
    wrong_stop_request.set_cluster_id("cluster-different");
    v1::ClusterState wrong_stop_state;
    CHECK(call_proto(rac_connect_cluster_stop_proto, wrong_stop_request, &wrong_stop_state) == RAC_ERROR_INVALID_ARGUMENT,
          "Stopping with mismatched cluster_id is rejected");

    // 13. Stop active cluster cleanly
    v1::ClusterStopRequest stop_request;
    stop_request.set_cluster_id("cluster-alpha");
    v1::ClusterState stopped_state;
    CHECK(call_proto(rac_connect_cluster_stop_proto, stop_request, &stopped_state) == RAC_SUCCESS,
          "Cluster stop terminates active cluster");
    CHECK(!stopped_state.is_active(), "Cluster state is marked inactive after stop");
    CHECK(stopped_state.cluster_id() == "cluster-alpha", "Stopped cluster ID is preserved in response");

    // 14. Activation rejected after stop
    v1::ConnectInvocationValidation stopped_activation_validation;
    CHECK(call_proto(rac_connect_cluster_validate_activation_proto, valid_activation, &stopped_activation_validation) == RAC_SUCCESS,
          "Activation check after stop returns typed validation");
    CHECK(!stopped_activation_validation.accepted(), "Activation tensor is rejected when cluster is inactive");
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
    test_session_cap_and_cancel_validation();
    test_cluster_orchestration();
    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
#endif
}
