/**
 * HybridRunAnywhereQHexRT.cpp
 *
 * Nitrogen HybridObject implementation for the RunAnywhere QHexRT backend.
 *
 * QHexRT-specific provider registration + Hexagon NPU capability probe.
 *
 * NOTE: The QHexRT registration symbol lives in librac_backend_qhexrt.so and
 * the NPU probe in librac_commons.so; both are linked by the build system.
 * The probe returns serialized `runanywhere.v1.NpuCapability` proto bytes via
 * commons' rac_npu_probe_proto() (rac/infrastructure/device/rac_npu_capability.h,
 * part of the staged core include bundle) — no hand-mirrored struct/enum here.
 */

#include "HybridRunAnywhereQHexRT.hpp"

#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/device/rac_npu_capability.h"

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <dlfcn.h>
#include <cstdlib>
#include <stdexcept>
#include <string>

// ============================================================================
// QHexRT backend C symbols (resolved at link/runtime from the staged
// librac_backend_qhexrt.so).
// ============================================================================
extern "C" {

// engines/qhexrt/rac_backend_qhexrt_register.cpp
rac_result_t rac_backend_qhexrt_register(void);
rac_result_t rac_backend_qhexrt_unregister(void);

} // extern "C"

// Log category for this module
#define LOG_CATEGORY "NPU.QHexRT"

namespace margelo::nitro::runanywhere::qhexrt {

namespace {

bool isRegistrationSuccess(rac_result_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

// Point Hexagon fastRPC at the app's native library dir so it can dlopen the
// bundled QNN DSP skels (libQnnHtpV75Skel.so / libQnnHtpV79Skel.so /
// libQnnHtpV81Skel.so). The skels
// ship alongside librac_backend_qhexrt.so in the APK's nativeLibraryDir, which
// we resolve at runtime via dladdr on the backend's register symbol — keeping
// this SDK-owned (no Android Context / example-app glue needed). Mirrors the
// iOS/Android source-of-truth that sets ADSP_LIBRARY_PATH before QNN loads.
void configureDspLibraryPath() {
  void* sym = dlsym(RTLD_DEFAULT, "rac_backend_qhexrt_register");
  if (sym == nullptr) {
    return;
  }
  Dl_info info;
  if (dladdr(sym, &info) == 0 || info.dli_fname == nullptr) {
    return;
  }
  std::string libPath(info.dli_fname);
  auto slash = libPath.find_last_of('/');
  if (slash == std::string::npos) {
    return;
  }
  std::string dir = libPath.substr(0, slash);
  std::string path = dir;
  const char* existing = std::getenv("ADSP_LIBRARY_PATH");
  if (existing != nullptr && existing[0] != '\0') {
    path += ";";
    path += existing;
  }
  path += ";/vendor/dsp/cdsp;/vendor/lib/rfsa/adsp";
  setenv("ADSP_LIBRARY_PATH", path.c_str(), 1);
  RAC_LOG_INFO(LOG_CATEGORY, "ADSP_LIBRARY_PATH set to %s", path.c_str());
}

} // namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereQHexRT::HybridRunAnywhereQHexRT() : HybridObject(TAG) {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereQHexRT constructor - QHexRT backend module");
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

    configureDspLibraryPath();

    rac_result_t result = rac_backend_qhexrt_register();
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "QHexRT registration failed with code: %d", result);
      throw std::runtime_error("QHexRT registration failed with error: " + std::to_string(result));
    }

    RAC_LOG_INFO(LOG_CATEGORY, "QHexRT backend registered successfully (LLM, VLM, STT, TTS)");
    isRegistered_ = true;
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereQHexRT::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Unregistering QHexRT backend");

    rac_result_t result = rac_backend_qhexrt_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "QHexRT unregistration failed with code: %d", result);
      throw std::runtime_error("QHexRT unregistration failed with error: " + std::to_string(result));
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereQHexRT::isBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isRegistered_;
  });
}

// ============================================================================
// NPU Capability Probe
// ============================================================================

// Serialized `runanywhere.v1.NpuCapability` proto bytes from commons'
// rac_npu_probe_proto(). Resolved via dlsym so the hybrid keeps loading even
// against an older librac_commons.so without the symbol (empty buffer then;
// the TS layer decodes an empty buffer to the unknown/unsupported fallback).
std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>> HybridRunAnywhereQHexRT::probeNpuProto() {
  return Promise<std::shared_ptr<ArrayBuffer>>::async([]() -> std::shared_ptr<ArrayBuffer> {
    using NpuProbeProtoFn = rac_result_t (*)(rac_proto_buffer_t*);
    auto fn = reinterpret_cast<NpuProbeProtoFn>(dlsym(RTLD_DEFAULT, "rac_npu_probe_proto"));
    if (!fn) {
      RAC_LOG_WARNING(LOG_CATEGORY, "probeNpuProto: rac_npu_probe_proto unavailable");
      return ArrayBuffer::allocate(0);
    }

    rac_proto_buffer_t out{};
    rac_result_t rc = fn(&out);
    std::shared_ptr<ArrayBuffer> buffer;
    if (rc == RAC_SUCCESS && out.status == RAC_SUCCESS && out.data != nullptr && out.size > 0) {
      buffer = ArrayBuffer::copy(out.data, out.size);
      RAC_LOG_INFO(LOG_CATEGORY, "NPU probe: %zu proto bytes", out.size);
    } else {
      RAC_LOG_WARNING(LOG_CATEGORY, "rac_npu_probe_proto failed: rc=%d status=%d", rc, out.status);
      buffer = ArrayBuffer::allocate(0);
    }

    // Release the owned buffer fields. Prefer commons' canonical
    // rac_proto_buffer_free (idempotent, resets the struct); fall back to
    // freeing the malloc'd fields directly (the documented ownership
    // convention in rac_proto_buffer.h, mirrored by core's
    // resultToProtoErrorProto).
    using ProtoBufferFreeFn = void (*)(rac_proto_buffer_t*);
    auto freeFn = reinterpret_cast<ProtoBufferFreeFn>(dlsym(RTLD_DEFAULT, "rac_proto_buffer_free"));
    if (freeFn) {
      freeFn(&out);
    } else {
      std::free(out.data);
      std::free(out.error_message);
    }
    return buffer;
  });
}

} // namespace margelo::nitro::runanywhere::qhexrt
