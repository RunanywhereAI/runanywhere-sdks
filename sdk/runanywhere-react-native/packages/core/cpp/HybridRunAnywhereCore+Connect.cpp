/**
 * React Native Connect bridge.
 *
 * Transport and discovery stay platform-owned, while policy and handshake
 * validation are delegated to the same C++ commons ABI used by Swift,
 * Kotlin, and Flutter.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "rac/connect/rac_connect.h"

#include <stdexcept>
#include <utility>

namespace margelo::nitro::runanywhere {

namespace {

using ConnectProtoFunction = rac_result_t (*)(const uint8_t *, size_t,
                                               rac_proto_buffer_t *);

/// RAII guard so every exit path frees the commons-owned proto buffer.
struct ProtoBufferGuard {
  rac_proto_buffer_t buffer{};

  ProtoBufferGuard() { rac_proto_buffer_init(&buffer); }

  ~ProtoBufferGuard() { rac_proto_buffer_free(&buffer); }

  ProtoBufferGuard(const ProtoBufferGuard &) = delete;
  ProtoBufferGuard &operator=(const ProtoBufferGuard &) = delete;
};

std::shared_ptr<ArrayBuffer>
callConnectProto(const std::shared_ptr<ArrayBuffer> &input,
                 ConnectProtoFunction function, const char *operation) {
  ProtoBufferGuard output;
  const auto result = function(input->data(), input->size(), &output.buffer);
  if (result != RAC_SUCCESS) {
    throw std::runtime_error(std::string(operation) + " failed: " +
                             std::to_string(result));
  }

  return output.buffer.data && output.buffer.size > 0
             ? ArrayBuffer::copy(output.buffer.data, output.buffer.size)
             : ArrayBuffer::allocate(0);
}

} // namespace

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::connectGetPlatformPolicyProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
  return Promise<std::shared_ptr<ArrayBuffer>>::async([requestBytes]() {
    return callConnectProto(requestBytes,
                            rac_connect_get_platform_policy_proto,
                            "Connect platform policy");
  });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::connectClientCreateHelloProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
  return Promise<std::shared_ptr<ArrayBuffer>>::async([requestBytes]() {
    return callConnectProto(requestBytes,
                            rac_connect_client_create_hello_proto,
                            "Connect client hello");
  });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::connectClientValidateHostProto(
    const std::shared_ptr<ArrayBuffer> &responseBytes) {
  return Promise<std::shared_ptr<ArrayBuffer>>::async([responseBytes]() {
    return callConnectProto(responseBytes,
                            rac_connect_client_validate_host_proto,
                            "Connect host validation");
  });
}

} // namespace margelo::nitro::runanywhere
