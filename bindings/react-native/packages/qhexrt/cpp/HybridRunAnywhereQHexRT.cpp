/**
 * HybridRunAnywhereQHexRT.cpp
 *
 * Nitrogen HybridObject implementation for the RunAnywhere QHexRT backend.
 *
 * QHexRT-specific provider registration, Hexagon capability, and
 * device-aware model-catalog adapter.
 *
 * NOTE: The QHexRT registration symbol lives in librac_backend_qhexrt.so and
 * all QHexRT-facing symbols live in librac_backend_qhexrt.so. The engine
 * composes backend-neutral registry/download/extraction primitives from
 * commons internally; this bridge only transports generated values/bytes.
 */

#include "HybridRunAnywhereQHexRT.hpp"

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/qhexrt/rac_qhexrt.h"

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef RAC_QHEXRT_BACKEND_AVAILABLE
#define RAC_QHEXRT_BACKEND_AVAILABLE 0
#endif

// ============================================================================
// QHexRT backend C symbols (resolved at link/runtime from the staged
// librac_backend_qhexrt.so).
// ============================================================================
#if RAC_QHEXRT_BACKEND_AVAILABLE
extern "C" {

// engines/qhexrt/rac_backend_qhexrt_register.cpp
rac_result_t rac_backend_qhexrt_register(void);
rac_result_t rac_backend_qhexrt_unregister(void);

} // extern "C"
#endif

// Log category for this module
#define LOG_CATEGORY "NPU.QHexRT"

namespace margelo::nitro::runanywhere::qhexrt {

namespace {

bool isRegistrationSuccess(rac_result_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

bool isBackendUnavailable(rac_result_t result) {
  return result == RAC_ERROR_BACKEND_UNAVAILABLE ||
         result == RAC_ERROR_CAPABILITY_UNSUPPORTED;
}

class ScopedProtoBuffer {
public:
  ScopedProtoBuffer() { rac_proto_buffer_init(&value); }
  ~ScopedProtoBuffer() { rac_proto_buffer_free(&value); }

  ScopedProtoBuffer(const ScopedProtoBuffer &) = delete;
  ScopedProtoBuffer &operator=(const ScopedProtoBuffer &) = delete;

  rac_proto_buffer_t value{};
};

rac_qhexrt_hexagon_arch_t toNativeArch(double arch) {
  if (!std::isfinite(arch) || std::trunc(arch) != arch ||
      arch < static_cast<double>(std::numeric_limits<int32_t>::min()) ||
      arch > static_cast<double>(std::numeric_limits<int32_t>::max())) {
    return RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN;
  }
  return static_cast<rac_qhexrt_hexagon_arch_t>(static_cast<int32_t>(arch));
}

std::vector<uint8_t>
copyArrayBuffer(const std::shared_ptr<ArrayBuffer> &buffer) {
  if (!buffer || buffer->size() == 0) {
    return {};
  }
  std::vector<uint8_t> bytes(buffer->size());
  std::memcpy(bytes.data(), buffer->data(), buffer->size());
  return bytes;
}

} // namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereQHexRT::HybridRunAnywhereQHexRT() : HybridObject(TAG) {
  RAC_LOG_DEBUG(LOG_CATEGORY,
                "HybridRunAnywhereQHexRT constructor - QHexRT backend module");
}

HybridRunAnywhereQHexRT::~HybridRunAnywhereQHexRT() {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereQHexRT destructor");
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereQHexRT::registerBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Registering QHexRT backend with C++ registry");

    // Android package bootstrap extracts the DSP skels from assets and passes
    // the app-private directory to the QHexRT engine before this call.

#if !RAC_QHEXRT_BACKEND_AVAILABLE
    RAC_LOG_WARNING(
        LOG_CATEGORY,
        "QHexRT private native backend is not staged; registration skipped");
    isRegistered_ = false;
    return false;
#else
    rac_result_t result = rac_backend_qhexrt_register();
    if (isBackendUnavailable(result)) {
      RAC_LOG_WARNING(LOG_CATEGORY,
                      "QHexRT backend unavailable on this device or build: %d",
                      result);
      isRegistered_ = false;
      return false;
    }
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "QHexRT registration failed with code: %d",
                    result);
      throw std::runtime_error("QHexRT registration failed with error: " +
                               std::to_string(result));
    }

    RAC_LOG_INFO(LOG_CATEGORY,
                 "QHexRT backend registered successfully (LLM, VLM, STT, TTS)");
    isRegistered_ = true;
    return true;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereQHexRT::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Unregistering QHexRT backend");

#if !RAC_QHEXRT_BACKEND_AVAILABLE
    isRegistered_ = false;
    return true;
#else
    rac_result_t result = rac_backend_qhexrt_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "QHexRT unregistration failed with code: %d",
                    result);
      throw std::runtime_error("QHexRT unregistration failed with error: " +
                               std::to_string(result));
    }
    return true;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereQHexRT::isBackendRegistered() {
  return Promise<bool>::async([this]() { return isRegistered_; });
}

// ============================================================================
// NPU Capability Probe
// ============================================================================

// Serialized `runanywhere.v1.NpuCapability` proto bytes from QHexRT.
std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereQHexRT::probeNpuProto() {
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      []() -> std::shared_ptr<ArrayBuffer> {
#if !RAC_QHEXRT_BACKEND_AVAILABLE
        return ArrayBuffer::allocate(0);
#else
        ScopedProtoBuffer out;
        rac_result_t rc = rac_qhexrt_probe_proto(&out.value);
        std::shared_ptr<ArrayBuffer> buffer;
        if (rc == RAC_SUCCESS && out.value.status == RAC_SUCCESS &&
            out.value.data != nullptr && out.value.size > 0) {
          buffer = ArrayBuffer::copy(out.value.data, out.value.size);
          RAC_LOG_INFO(LOG_CATEGORY, "NPU probe: %zu proto bytes",
                       out.value.size);
        } else {
          RAC_LOG_WARNING(LOG_CATEGORY,
                          "rac_qhexrt_probe_proto failed: rc=%d status=%d", rc,
                          out.value.status);
          buffer = ArrayBuffer::allocate(0);
        }
        return buffer;
#endif
      });
}

bool HybridRunAnywhereQHexRT::isArchitectureSupported(double arch) {
#if !RAC_QHEXRT_BACKEND_AVAILABLE
  (void)arch;
  return false;
#else
  return rac_qhexrt_arch_is_supported(toNativeArch(arch)) == RAC_TRUE;
#endif
}

bool HybridRunAnywhereQHexRT::modelSupportsArchitecture(
    const std::string &modelId, double arch) {
#if !RAC_QHEXRT_BACKEND_AVAILABLE
  (void)modelId;
  (void)arch;
  return false;
#else
  return rac_qhexrt_catalog_model_supports_arch(modelId.c_str(),
                                                toNativeArch(arch)) == RAC_TRUE;
#endif
}

bool HybridRunAnywhereQHexRT::modelRequiresHfAuth(const std::string &modelId) {
#if !RAC_QHEXRT_BACKEND_AVAILABLE
  (void)modelId;
  return false;
#else
  return rac_qhexrt_catalog_model_requires_hf_auth(modelId.c_str()) == RAC_TRUE;
#endif
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereQHexRT::catalogRegisterModelProto(
    const std::shared_ptr<ArrayBuffer> &requestBytes) {
  auto request = copyArrayBuffer(requestBytes);
  return Promise<std::shared_ptr<ArrayBuffer>>::async(
      [request = std::move(request)]() {
#if !RAC_QHEXRT_BACKEND_AVAILABLE
        return ArrayBuffer::allocate(0);
#else
        rac_bool_t registered = RAC_FALSE;
        ScopedProtoBuffer out;
        const rac_result_t rc = rac_qhexrt_catalog_register_model_proto(
            request.data(), request.size(), &registered, &out.value);
        const rac_result_t status = rc != RAC_SUCCESS ? rc : out.value.status;
        if (status != RAC_SUCCESS) {
          const std::string detail =
              out.value.error_message != nullptr ? out.value.error_message : "";
          throw std::runtime_error(
              "QHexRT device-aware model registration failed (code=" +
              std::to_string(status) + ")" +
              (detail.empty() ? "" : ": " + detail));
        }
        if (registered != RAC_TRUE) {
          return ArrayBuffer::allocate(0);
        }
        if (out.value.data == nullptr || out.value.size == 0) {
          throw std::runtime_error(
              "QHexRT registration returned an empty ModelInfo payload");
        }
        return ArrayBuffer::copy(out.value.data, out.value.size);
#endif
      });
}

} // namespace margelo::nitro::runanywhere::qhexrt
