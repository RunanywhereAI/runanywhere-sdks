/**
 * @file rac_connect.cpp
 * @brief Commons-owned validation and session state for LAN host/client setup.
 */

#include "rac/connect/rac_connect.h"

#include <array>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>

#include "rac/core/rac_uuid.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "connect.pb.h"
#endif

namespace {

constexpr uint32_t kConnectProtocolVersion = 1;
constexpr size_t kMaxDisplayNameLength = 128;
constexpr size_t kMaxModelIdLength = 512;

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
    {v1::CONNECT_PLATFORM_REACT_NATIVE, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_ENABLED},
    {v1::CONNECT_PLATFORM_FLUTTER, v1::CONNECT_ROLE_AVAILABILITY_DISABLED,
     v1::CONNECT_ROLE_AVAILABILITY_ENABLED},
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

    std::string session_id;
    const rac_result_t id_result = generate_ephemeral_id(&session_id, out_response);
    if (id_result != RAC_SUCCESS) {
        return id_result;
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
               request.generation().prompt().empty()) {
        validation.set_rejection_reason("Connect generation request is incomplete");
    } else if (request.generation().model_id() != host.model.model_id()) {
        validation.set_rejection_reason("Requested model is not shared by this host");
    } else {
        validation.set_accepted(true);
    }
    return serialize_message(validation, out_validation);
#endif
}

}  // extern "C"
