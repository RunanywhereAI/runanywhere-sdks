/**
 * HybridRunAnywhereQHexRT.cpp
 *
 * Nitrogen HybridObject implementation for the RunAnywhere QHexRT backend.
 *
 * QHexRT-specific provider registration + Hexagon NPU capability probe.
 *
 * NOTE: The QHexRT registration symbol lives in librac_backend_qhexrt.so and
 * the NPU probe in librac_commons.so; both are linked by the build system.
 * The probe declarations below mirror commons' rac_npu_capability.h verbatim
 * (that header is not part of the published core include bundle yet), so any
 * change to the C struct/enum there MUST be reflected here.
 */

#include "HybridRunAnywhereQHexRT.hpp"

#include "rac/core/rac_error.h"

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// ============================================================================
// QHexRT backend + NPU probe C symbols (resolved at link/runtime from the
// staged librac_backend_qhexrt.so / librac_commons.so).
// ============================================================================
extern "C" {

// engines/qhexrt/rac_backend_qhexrt_register.cpp
rac_result_t rac_backend_qhexrt_register(void);
rac_result_t rac_backend_qhexrt_unregister(void);

// rac/infrastructure/device/rac_npu_capability.h (commons). Kept in sync by hand.
typedef enum rac_hexagon_arch {
  RAC_HEXAGON_ARCH_UNKNOWN = 0,
  RAC_HEXAGON_ARCH_V68 = 68,
  RAC_HEXAGON_ARCH_V69 = 69,
  RAC_HEXAGON_ARCH_V73 = 73,
  RAC_HEXAGON_ARCH_V75 = 75,
  RAC_HEXAGON_ARCH_V79 = 79,
  RAC_HEXAGON_ARCH_V81 = 81,
} rac_hexagon_arch_t;

typedef struct rac_npu_info {
  char soc_model[64];
  int32_t soc_id;
  rac_hexagon_arch_t hexagon_arch;
  rac_bool_t qhexrt_supported;
} rac_npu_info_t;

rac_result_t rac_npu_probe(rac_npu_info_t* out);

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

// Minimal JSON string escaper for the SoC model (alphanumeric in practice).
std::string jsonEscape(const char* s) {
  std::string out;
  for (const char* p = s; *p != '\0'; ++p) {
    char c = *p;
    if (c == '"' || c == '\\') {
      out.push_back('\\');
      out.push_back(c);
    } else if (c >= 0x20) {
      out.push_back(c);
    }
  }
  return out;
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

std::shared_ptr<Promise<std::string>> HybridRunAnywhereQHexRT::probeNpu() {
  return Promise<std::string>::async([]() {
    rac_npu_info_t info;
    info.soc_model[0] = '\0';
    info.soc_id = -1;
    info.hexagon_arch = RAC_HEXAGON_ARCH_UNKNOWN;
    info.qhexrt_supported = RAC_FALSE;

    rac_result_t rc = rac_npu_probe(&info);
    if (rc != RAC_SUCCESS) {
      RAC_LOG_WARNING(LOG_CATEGORY, "rac_npu_probe failed with code: %d", rc);
      return std::string("{\"socModel\":\"\",\"socId\":-1,\"hexagonArch\":0,\"qhexrtSupported\":false}");
    }

    std::string json = "{\"socModel\":\"";
    json += jsonEscape(info.soc_model);
    json += "\",\"socId\":";
    json += std::to_string(info.soc_id);
    json += ",\"hexagonArch\":";
    json += std::to_string(static_cast<int>(info.hexagon_arch));
    json += ",\"qhexrtSupported\":";
    json += (info.qhexrt_supported != RAC_FALSE) ? "true" : "false";
    json += "}";

    RAC_LOG_INFO(LOG_CATEGORY, "NPU probe: %s", json.c_str());
    return json;
  });
}

} // namespace margelo::nitro::runanywhere::qhexrt
