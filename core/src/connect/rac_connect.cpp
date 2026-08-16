/**
 * @file rac_connect.cpp
 * @brief Commons-owned validation and session state for LAN host/client setup.
 */

#include "rac/connect/rac_connect.h"

#include <algorithm>
#include <array>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "rac/core/rac_uuid.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "connect.pb.h"
#endif

namespace {

constexpr uint32_t kConnectProtocolVersion = 1;
constexpr size_t kMaxDisplayNameLength = 128;
constexpr size_t kMaxModelIdLength = 512;
// Soft cap for an unauthenticated LAN host. Reconnects from the same client
// instance_id still collapse to one entry; this only bounds distinct peers and
// leaked sessions that never close their transport.
constexpr size_t kMaxConnectSessions = 16;

#if defined(RAC_HAVE_PROTOBUF)

namespace v1 = ::runanywhere::v1;

struct HostRuntime {
    bool is_hosting = false;
    v1::ConnectDiscoveryMetadata metadata;
    v1::ConnectModelDescriptor model;
    // One active session per client instance. A reconnect replaces the stale
    // session from the same SDK instance instead of inflating the device count.
    std::unordered_map<std::string, std::string> session_clients;
};

struct PlatformRolePolicy {
    v1::ConnectPlatform platform;
    v1::ConnectRoleAvailability host_role;
    v1::ConnectRoleAvailability client_role;
};

// Product availability is data, not platform-specific control flow. A new
// adapter changes one table row after its transport/security requirements are
// met; the host and handshake validation paths remain unchanged.
constexpr std::array<PlatformRolePolicy, 8> kPlatformRolePolicies{{
    {v1::CONNECT_PLATFORM_MACOS, v1::CONNECT_ROLE_AVAILABILITY_ENABLED,
     v1::CONNECT_ROLE_AVAILABILITY_DISABLED},
    {v1::CONNECT_PLATFORM_IOS, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_ENABLED},
    {v1::CONNECT_PLATFORM_IPADOS, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_ENABLED},
    {v1::CONNECT_PLATFORM_ANDROID, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_ENABLED},
    // Cross-framework SDKs remain reserved on the wire but are not shipped
    // Connect clients in this release. Flip to ENABLED only after a dedicated
    // transport/discovery adapter and example validation land.
    {v1::CONNECT_PLATFORM_REACT_NATIVE, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_DISABLED},
    {v1::CONNECT_PLATFORM_FLUTTER, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_DISABLED},
    {v1::CONNECT_PLATFORM_WEB, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_PLANNED},
    {v1::CONNECT_PLATFORM_WINDOWS, v1::CONNECT_ROLE_AVAILABILITY_PLANNED,
     v1::CONNECT_ROLE_AVAILABILITY_PLANNED},
}};

std::mutex& runtime_mutex() {
    static std::mutex mutex;
    return mutex;
}

HostRuntime& runtime() {
    static HostRuntime instance;
    return instance;
}

bool has_non_whitespace(const std::string& value) {
    for (const char character : value) {
        if (character != ' ' && character != '\t' && character != '\n' && character != '\r') {
            return true;
        }
    }
    return false;
}

bool is_valid_display_name(const std::string& value) {
    return !value.empty() && value.size() <= kMaxDisplayNameLength && has_non_whitespace(value);
}

bool is_valid_model(const v1::ConnectModelDescriptor& model) {
    return !model.model_id().empty() && model.model_id().size() <= kMaxModelIdLength &&
           is_valid_display_name(model.display_name());
}

const PlatformRolePolicy* find_platform_policy(v1::ConnectPlatform platform) {
    for (const PlatformRolePolicy& policy : kPlatformRolePolicies) {
        if (policy.platform == platform) {
            return &policy;
        }
    }
    return nullptr;
}

bool is_host_role_enabled(v1::ConnectPlatform platform) {
    const PlatformRolePolicy* policy = find_platform_policy(platform);
    return policy != nullptr && policy->host_role == v1::CONNECT_ROLE_AVAILABILITY_ENABLED;
}

bool is_client_role_enabled(v1::ConnectPlatform platform) {
    const PlatformRolePolicy* policy = find_platform_policy(platform);
    return policy != nullptr && policy->client_role == v1::CONNECT_ROLE_AVAILABILITY_ENABLED;
}

v1::ConnectPlatformPolicy make_platform_policy(const PlatformRolePolicy& policy) {
    v1::ConnectPlatformPolicy response;
    response.set_platform(policy.platform);
    response.set_host_role(policy.host_role);
    response.set_client_role(policy.client_role);
    return response;
}

template <typename Message>
rac_result_t serialize_message(const Message& message, rac_proto_buffer_t* out_buffer) {
    if (out_buffer == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        rac_proto_buffer_set_error(out_buffer, RAC_ERROR_PROCESSING_FAILED,
                                   "Failed to serialize Connect protobuf response");
        return RAC_ERROR_PROCESSING_FAILED;
    }
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_buffer);
}

template <typename Message>
rac_result_t parse_message(const uint8_t* bytes, size_t size, Message* out_message,
                           rac_proto_buffer_t* out_buffer, const char* error_context) {
    if (out_message == nullptr || out_buffer == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    const rac_result_t validation = rac_proto_bytes_validate(bytes, size);
    if (validation != RAC_SUCCESS) {
        rac_proto_buffer_set_error(out_buffer, validation, error_context);
        return validation;
    }
    if (!out_message->ParseFromArray(rac_proto_bytes_data_or_empty(bytes, size),
                                     static_cast<int>(size))) {
        rac_proto_buffer_set_error(out_buffer, RAC_ERROR_DECODING_ERROR, error_context);
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

rac_result_t generate_ephemeral_id(std::string* out_id, rac_proto_buffer_t* out_buffer) {
    if (out_id == nullptr || out_buffer == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    std::array<char, 37> uuid{};
    const rac_result_t result = rac_uuid_v4(uuid.data(), uuid.size());
    if (result != RAC_SUCCESS) {
        rac_proto_buffer_set_error(out_buffer, result, "Failed to generate Connect instance id");
        return result;
    }
    *out_id = uuid.data();
    return RAC_SUCCESS;
}

v1::ConnectHostState make_host_state(const HostRuntime& host) {
    v1::ConnectHostState state;
    state.set_is_hosting(host.is_hosting);
    state.set_active_client_count(static_cast<uint32_t>(host.session_clients.size()));
    if (host.is_hosting) {
        *state.mutable_discovery_metadata() = host.metadata;
        *state.mutable_model() = host.model;
    }
    return state;
}

rac_result_t reject_handshake(const HostRuntime& host, const char* reason,
                              rac_proto_buffer_t* out_response) {
    v1::ConnectHandshakeResponse response;
    response.set_status(v1::CONNECT_HANDSHAKE_STATUS_REJECTED);
    response.set_rejection_reason(reason);
    if (host.is_hosting) {
        *response.mutable_host() = host.metadata;
        *response.mutable_model() = host.model;
    }
    return serialize_message(response, out_response);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" {

rac_result_t rac_connect_get_platform_policy_proto(const uint8_t* request_bytes,
                                                   size_t request_size,
                                                   rac_proto_buffer_t* out_platform_policy) {
    if (out_platform_policy == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_platform_policy);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_platform_policy, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectPlatformPolicyRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_platform_policy,
                      "Invalid ConnectPlatformPolicyRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    const PlatformRolePolicy* policy = find_platform_policy(request.platform());
    if (policy == nullptr) {
        rac_proto_buffer_set_error(out_platform_policy, RAC_ERROR_NOT_SUPPORTED,
                                   "Connect platform is not present in the role policy");
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return serialize_message(make_platform_policy(*policy), out_platform_policy);
#endif
}

rac_result_t rac_connect_host_start_proto(const uint8_t* request_bytes, size_t request_size,
                                          rac_proto_buffer_t* out_host_state) {
    if (out_host_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_host_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_host_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectHostStartRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_host_state,
                      "Invalid ConnectHostStartRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }
    if (!is_host_role_enabled(request.platform())) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_NOT_SUPPORTED,
                                   "This platform is not enabled for Connect hosting");
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (request.protocol_version() != kConnectProtocolVersion) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_INVALID_CONFIGURATION,
                                   "Unsupported Connect protocol version");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (!is_valid_display_name(request.display_name())) {
        rac_proto_buffer_set_error(
            out_host_state, RAC_ERROR_INVALID_INPUT,
            "Connect host display name must be non-empty and at most 128 characters");
        return RAC_ERROR_INVALID_INPUT;
    }
    if (!request.has_model() || !is_valid_model(request.model())) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_INVALID_INPUT,
                                   "Connect host requires a selected loaded model");
        return RAC_ERROR_INVALID_INPUT;
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    HostRuntime& host = runtime();
    if (!host.is_hosting) {
        std::string instance_id;
        const rac_result_t id_result = generate_ephemeral_id(&instance_id, out_host_state);
        if (id_result != RAC_SUCCESS) {
            return id_result;
        }
        host.metadata.Clear();
        host.metadata.set_instance_id(std::move(instance_id));
        host.metadata.set_display_name(request.display_name());
        host.metadata.set_platform(request.platform());
        host.metadata.set_protocol_version(kConnectProtocolVersion);
        host.model = request.model();
        host.session_clients.clear();
        host.is_hosting = true;
    } else if (host.model.model_id() != request.model().model_id()) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_INVALID_CONFIGURATION,
                                   "Stop the active Connect host before changing its shared model");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    return serialize_message(make_host_state(host), out_host_state);
#endif
}

rac_result_t rac_connect_host_stop_proto(const uint8_t* request_bytes, size_t request_size,
                                         rac_proto_buffer_t* out_host_state) {
    if (out_host_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_host_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_host_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectHostStopRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_host_state,
                      "Invalid ConnectHostStopRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    HostRuntime& host = runtime();
    host.is_hosting = false;
    host.metadata.Clear();
    host.model.Clear();
    host.session_clients.clear();
    return serialize_message(make_host_state(host), out_host_state);
#endif
}

rac_result_t rac_connect_client_create_hello_proto(const uint8_t* request_bytes,
                                                   size_t request_size,
                                                   rac_proto_buffer_t* out_client_hello) {
    if (out_client_hello == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_client_hello);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_client_hello, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectClientStartRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_client_hello,
                      "Invalid ConnectClientStartRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }
    if (!is_client_role_enabled(request.platform())) {
        rac_proto_buffer_set_error(out_client_hello, RAC_ERROR_NOT_SUPPORTED,
                                   "This platform is not enabled as a Connect client");
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (request.protocol_version() != kConnectProtocolVersion) {
        rac_proto_buffer_set_error(out_client_hello, RAC_ERROR_INVALID_CONFIGURATION,
                                   "Unsupported Connect protocol version");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (!is_valid_display_name(request.display_name())) {
        rac_proto_buffer_set_error(
            out_client_hello, RAC_ERROR_INVALID_INPUT,
            "Connect client display name must be non-empty and at most 128 characters");
        return RAC_ERROR_INVALID_INPUT;
    }

    std::string instance_id;
    const rac_result_t id_result = generate_ephemeral_id(&instance_id, out_client_hello);
    if (id_result != RAC_SUCCESS) {
        return id_result;
    }

    v1::ConnectClientHello hello;
    hello.set_instance_id(std::move(instance_id));
    hello.set_display_name(request.display_name());
    hello.set_platform(request.platform());
    hello.set_protocol_version(kConnectProtocolVersion);
    return serialize_message(hello, out_client_hello);
#endif
}

rac_result_t rac_connect_host_accept_client_proto(const uint8_t* hello_bytes, size_t hello_size,
                                                  rac_proto_buffer_t* out_response) {
    if (out_response == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_response);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)hello_bytes;
    (void)hello_size;
    rac_proto_buffer_set_error(out_response, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectClientHello hello;
    const rac_result_t parse_result = parse_message(hello_bytes, hello_size, &hello, out_response,
                                                    "Invalid ConnectClientHello protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    HostRuntime& host = runtime();
    if (!host.is_hosting) {
        return reject_handshake(host, "Connect host is not active", out_response);
    }
    if (!is_client_role_enabled(hello.platform())) {
        return reject_handshake(host, "Client platform is not supported by this host",
                                out_response);
    }
    if (hello.protocol_version() != host.metadata.protocol_version()) {
        return reject_handshake(host, "Connect protocol versions are incompatible", out_response);
    }
    if (hello.instance_id().empty() || !is_valid_display_name(hello.display_name())) {
        return reject_handshake(host, "Client identity is invalid", out_response);
    }

    // Network transitions can leave the old transport connection alive long
    // enough for the same device to complete a new handshake. Invalidate that
    // device's previous session before registering the replacement.
    for (auto it = host.session_clients.begin(); it != host.session_clients.end();) {
        if (it->second == hello.instance_id()) {
            it = host.session_clients.erase(it);
        } else {
            ++it;
        }
    }
    if (host.session_clients.size() >= kMaxConnectSessions) {
        return reject_handshake(host, "Connect host has too many active sessions", out_response);
    }

    std::string session_id;
    const rac_result_t id_result = generate_ephemeral_id(&session_id, out_response);
    if (id_result != RAC_SUCCESS) {
        return id_result;
    }

    host.session_clients.emplace(session_id, hello.instance_id());

    v1::ConnectHandshakeResponse response;
    response.set_status(v1::CONNECT_HANDSHAKE_STATUS_ACCEPTED);
    response.set_session_id(std::move(session_id));
    *response.mutable_host() = host.metadata;
    *response.mutable_model() = host.model;
    return serialize_message(response, out_response);
#endif
}

rac_result_t rac_connect_client_validate_host_proto(const uint8_t* response_bytes,
                                                    size_t response_size,
                                                    rac_proto_buffer_t* out_session_state) {
    if (out_session_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_session_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)response_bytes;
    (void)response_size;
    rac_proto_buffer_set_error(out_session_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectHandshakeResponse response;
    const rac_result_t parse_result =
        parse_message(response_bytes, response_size, &response, out_session_state,
                      "Invalid ConnectHandshakeResponse protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    v1::ConnectClientSessionState state;
    if (response.status() != v1::CONNECT_HANDSHAKE_STATUS_ACCEPTED) {
        state.set_state(v1::CONNECT_SESSION_STATE_FAILED);
        state.set_error_message(response.rejection_reason());
        return serialize_message(state, out_session_state);
    }
    if (!response.has_host() || !response.has_model() ||
        !is_host_role_enabled(response.host().platform()) ||
        response.host().protocol_version() != kConnectProtocolVersion ||
        response.session_id().empty() || !is_valid_model(response.model())) {
        state.set_state(v1::CONNECT_SESSION_STATE_FAILED);
        state.set_error_message("Host handshake response is incompatible");
        return serialize_message(state, out_session_state);
    }

    state.set_state(v1::CONNECT_SESSION_STATE_CONNECTED);
    state.set_session_id(response.session_id());
    *state.mutable_host() = response.host();
    *state.mutable_model() = response.model();
    return serialize_message(state, out_session_state);
#endif
}

rac_result_t rac_connect_host_close_session_proto(const uint8_t* request_bytes, size_t request_size,
                                                  rac_proto_buffer_t* out_host_state) {
    if (out_host_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_host_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_host_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectSessionCloseRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_host_state,
                      "Invalid ConnectSessionCloseRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }
    if (request.session_id().empty()) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_INVALID_INPUT,
                                   "Connect session id is required");
        return RAC_ERROR_INVALID_INPUT;
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    HostRuntime& host = runtime();
    if (!host.is_hosting || host.session_clients.erase(request.session_id()) == 0) {
        rac_proto_buffer_set_error(out_host_state, RAC_ERROR_NOT_FOUND,
                                   "Connect session is not active");
        return RAC_ERROR_NOT_FOUND;
    }
    return serialize_message(make_host_state(host), out_host_state);
#endif
}

rac_result_t rac_connect_host_validate_invocation_proto(const uint8_t* request_bytes,
                                                        size_t request_size,
                                                        rac_proto_buffer_t* out_validation) {
    if (out_validation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_validation);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_validation, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectInvocationRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_validation,
                      "Invalid ConnectInvocationRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    v1::ConnectInvocationValidation validation;
    std::lock_guard<std::mutex> lock(runtime_mutex());
    const HostRuntime& host = runtime();
    if (!host.is_hosting) {
        validation.set_rejection_reason("Connect host is not active");
    } else if (request.session_id().empty() ||
               host.session_clients.find(request.session_id()) == host.session_clients.end()) {
        validation.set_rejection_reason("Connect session is not active");
    } else if (request.request_id().empty() || !request.has_generation() ||
               request.generation().messages_size() == 0) {
        // prompt was deleted from LLMGenerateRequest; the conversation now
        // travels as `messages` (repeated ChatMessage), never empty.
        validation.set_rejection_reason("Connect generation request is incomplete");
    } else if (request.generation().model_id() != host.model.model_id()) {
        validation.set_rejection_reason("Requested model is not shared by this host");
    } else {
        validation.set_accepted(true);
    }
    return serialize_message(validation, out_validation);
#endif
}

rac_result_t rac_connect_host_validate_cancel_proto(const uint8_t* request_bytes,
                                                    size_t request_size,
                                                    rac_proto_buffer_t* out_validation) {
    if (out_validation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_validation);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_validation, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Connect requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ConnectInvocationCancelRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_validation,
                      "Invalid ConnectInvocationCancelRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    v1::ConnectInvocationValidation validation;
    std::lock_guard<std::mutex> lock(runtime_mutex());
    const HostRuntime& host = runtime();
    if (!host.is_hosting) {
        validation.set_rejection_reason("Connect host is not active");
    } else if (request.session_id().empty() ||
               host.session_clients.find(request.session_id()) == host.session_clients.end()) {
        validation.set_rejection_reason("Connect session is not active");
    } else if (request.request_id().empty()) {
        validation.set_rejection_reason("Connect cancellation request is incomplete");
    } else {
        validation.set_accepted(true);
    }
    return serialize_message(validation, out_validation);
#endif
}

/* ===========================================================================
 * Cluster Orchestration Implementations (Issue #541)
 * =========================================================================== */

#if defined(RAC_HAVE_PROTOBUF)
struct ClusterRuntime {
    bool is_active = false;
    std::string cluster_id;
    v1::ConnectModelDescriptor model;
    std::vector<v1::ClusterLayerAssignment> assignments;
    std::unordered_map<std::string, v1::ClusterLayerAssignment> peer_assignments;
};

ClusterRuntime& cluster_runtime() {
    static ClusterRuntime instance;
    return instance;
}

bool validate_layer_assignments(const google::protobuf::RepeatedPtrField<v1::ClusterLayerAssignment>& assignments,
                                std::string* out_rejection_reason) {
    if (assignments.empty()) {
        if (out_rejection_reason != nullptr) {
            *out_rejection_reason = "Cluster must have at least one layer assignment";
        }
        return false;
    }

    std::unordered_set<std::string> seen_instance_ids;
    std::vector<v1::ClusterLayerAssignment> sorted_assignments;
    sorted_assignments.reserve(assignments.size());

    for (int i = 0; i < assignments.size(); ++i) {
        const v1::ClusterLayerAssignment& assignment = assignments[i];
        if (assignment.instance_id().empty()) {
            if (out_rejection_reason != nullptr) {
                *out_rejection_reason = "Peer assignment has empty instance_id";
            }
            return false;
        }
        if (!seen_instance_ids.insert(assignment.instance_id()).second) {
            if (out_rejection_reason != nullptr) {
                *out_rejection_reason = "Duplicate instance_id in cluster assignment";
            }
            return false;
        }
        if (assignment.layer_end() <= assignment.layer_start()) {
            if (out_rejection_reason != nullptr) {
                *out_rejection_reason = "Invalid layer range: layer_end must be greater than layer_start";
            }
            return false;
        }
        sorted_assignments.push_back(assignment);
    }

    std::sort(sorted_assignments.begin(), sorted_assignments.end(),
              [](const v1::ClusterLayerAssignment& a, const v1::ClusterLayerAssignment& b) {
                  return a.layer_start() < b.layer_start();
              });

    uint32_t expected_start = 0;
    for (const auto& assignment : sorted_assignments) {
        if (assignment.layer_start() != expected_start) {
            if (out_rejection_reason != nullptr) {
                *out_rejection_reason = "Layer range gap or mismatch in cluster assignment";
            }
            return false;
        }
        expected_start = assignment.layer_end();
    }
    return true;
}
#endif

rac_result_t rac_connect_cluster_start_proto(const uint8_t* request_bytes,
                                             size_t request_size,
                                             rac_proto_buffer_t* out_cluster_state) {
    if (out_cluster_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_cluster_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Cluster orchestration requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ClusterStartRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_cluster_state,
                      "Invalid ClusterStartRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    ClusterRuntime& cluster = cluster_runtime();

    if (request.cluster_id().empty()) {
        rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_INVALID_ARGUMENT,
                                   "ClusterStartRequest missing cluster_id");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (cluster.is_active) {
        if (cluster.cluster_id == request.cluster_id()) {
            // Idempotent start: return existing state
            v1::ClusterState state;
            state.set_is_active(true);
            state.set_cluster_id(cluster.cluster_id);
            *state.mutable_model() = cluster.model;
            for (const auto& item : cluster.assignments) {
                *state.add_assignments() = item;
            }
            state.set_peer_count(static_cast<uint32_t>(cluster.assignments.size()));
            return serialize_message(state, out_cluster_state);
        }
        rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_INVALID_ARGUMENT,
                                   "Another cluster is already active");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (!is_valid_model(request.model())) {
        rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_INVALID_ARGUMENT,
                                   "ClusterStartRequest missing or invalid model descriptor");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string rejection;
    if (!validate_layer_assignments(request.assignments(), &rejection)) {
        rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_INVALID_ARGUMENT,
                                   rejection.c_str());
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    cluster.is_active = true;
    cluster.cluster_id = request.cluster_id();
    cluster.model = request.model();
    cluster.assignments.clear();
    cluster.peer_assignments.clear();

    v1::ClusterState state;
    state.set_is_active(true);
    state.set_cluster_id(cluster.cluster_id);
    *state.mutable_model() = cluster.model;

    for (const v1::ClusterLayerAssignment& item : request.assignments()) {
        cluster.assignments.push_back(item);
        cluster.peer_assignments[item.instance_id()] = item;
        *state.add_assignments() = item;
    }
    state.set_peer_count(static_cast<uint32_t>(request.assignments_size()));

    return serialize_message(state, out_cluster_state);
#endif
}

rac_result_t rac_connect_cluster_join_proto(const uint8_t* request_bytes,
                                            size_t request_size,
                                            rac_proto_buffer_t* out_response) {
    if (out_response == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_response);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_response, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Cluster orchestration requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ClusterJoinRequest request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_response,
                      "Invalid ClusterJoinRequest protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    v1::ClusterStartResponse response;
    std::string rejection;
    if (request.cluster_id().empty()) {
        response.set_accepted(false);
        response.set_rejection_reason("Cluster ID is empty");
    } else if (request.instance_id().empty()) {
        response.set_accepted(false);
        response.set_rejection_reason("Peer instance_id is empty");
    } else if (!is_valid_model(request.cluster_start().model())) {
        response.set_accepted(false);
        response.set_rejection_reason("Invalid model descriptor in cluster start");
    } else if (!validate_layer_assignments(request.cluster_start().assignments(), &rejection)) {
        response.set_accepted(false);
        response.set_rejection_reason(rejection);
    } else {
        bool peer_found = false;
        for (const auto& a : request.cluster_start().assignments()) {
            if (a.instance_id() == request.instance_id()) {
                peer_found = true;
                break;
            }
        }
        if (!peer_found) {
            response.set_accepted(false);
            response.set_rejection_reason("Peer instance_id not found in cluster layer assignments");
        } else {
            response.set_accepted(true);
            *response.mutable_peer_capability() = request.peer_capability();
        }
    }

    return serialize_message(response, out_response);
#endif
}

rac_result_t rac_connect_cluster_stop_proto(const uint8_t* request_bytes,
                                            size_t request_size,
                                            rac_proto_buffer_t* out_cluster_state) {
    if (out_cluster_state == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_cluster_state);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Cluster orchestration requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ClusterStopRequest request;
    if (request_bytes != nullptr && request_size > 0) {
        const rac_result_t parse_result =
            parse_message(request_bytes, request_size, &request, out_cluster_state,
                          "Invalid ClusterStopRequest protobuf payload");
        if (parse_result != RAC_SUCCESS) {
            return parse_result;
        }
    }

    std::lock_guard<std::mutex> lock(runtime_mutex());
    ClusterRuntime& cluster = cluster_runtime();

    if (!request.cluster_id().empty() && cluster.is_active &&
        request.cluster_id() != cluster.cluster_id) {
        rac_proto_buffer_set_error(out_cluster_state, RAC_ERROR_INVALID_ARGUMENT,
                                   "ClusterStopRequest cluster_id does not match the active cluster");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string stopped_cluster_id = cluster.cluster_id;
    cluster.is_active = false;
    cluster.cluster_id.clear();
    cluster.model.Clear();
    cluster.assignments.clear();
    cluster.peer_assignments.clear();

    v1::ClusterState state;
    state.set_is_active(false);
    state.set_cluster_id(stopped_cluster_id);
    state.set_peer_count(0);
    return serialize_message(state, out_cluster_state);
#endif
}

rac_result_t rac_connect_cluster_validate_activation_proto(const uint8_t* request_bytes,
                                                           size_t request_size,
                                                           rac_proto_buffer_t* out_validation) {
    if (out_validation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_validation);

#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    rac_proto_buffer_set_error(out_validation, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "Cluster orchestration requires protobuf support");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    v1::ClusterActivation request;
    const rac_result_t parse_result =
        parse_message(request_bytes, request_size, &request, out_validation,
                      "Invalid ClusterActivation protobuf payload");
    if (parse_result != RAC_SUCCESS) {
        return parse_result;
    }

    v1::ConnectInvocationValidation validation;
    std::lock_guard<std::mutex> lock(runtime_mutex());
    const ClusterRuntime& cluster = cluster_runtime();

    if (!cluster.is_active) {
        validation.set_rejection_reason("Cluster is not active");
    } else if (request.cluster_id() != cluster.cluster_id) {
        validation.set_rejection_reason("Cluster ID mismatch on activation tensor");
    } else if (request.request_id().empty()) {
        validation.set_rejection_reason("Activation request_id is empty");
    } else if (request.tensor_data().empty()) {
        validation.set_rejection_reason("Activation tensor_data is empty");
    } else if (request.seq_len() == 0 || request.hidden_size() == 0) {
        validation.set_rejection_reason("Invalid activation tensor dimensions (seq_len/hidden_size zero)");
    } else {
        bool valid_boundary = (request.from_layer() == 0);
        for (const auto& a : cluster.assignments) {
            if (request.from_layer() == a.layer_start() || request.from_layer() == a.layer_end()) {
                valid_boundary = true;
                break;
            }
        }
        const uint64_t min_elements = static_cast<uint64_t>(request.seq_len()) * request.hidden_size();
        if (!valid_boundary) {
            validation.set_rejection_reason("Activation from_layer does not match any cluster layer boundary");
        } else if (request.tensor_data().size() < min_elements) {
            validation.set_rejection_reason("Activation tensor_data size is smaller than tensor dimensions");
        } else {
            validation.set_accepted(true);
        }
    }
    return serialize_message(validation, out_validation);
#endif
}

}  // extern "C"
