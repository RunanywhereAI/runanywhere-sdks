/**
 * HybridRunAnywhereONNX.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere ONNX backend.
 *
 * ONNX-specific provider registration for speech processing.
 */

#include "HybridRunAnywhereONNX.hpp"

// Backend registration header - always available
extern "C" {
#include "rac_vad_onnx.h"
}

// RACommons logger - unified logging across platforms
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// Category for ONNX module logging
static const char* LOG_CATEGORY = "ONNX";

namespace margelo::nitro::runanywhere::onnx {

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereONNX::HybridRunAnywhereONNX() : HybridObject(TAG) {
  RAC_LOG_INFO(LOG_CATEGORY, "HybridRunAnywhereONNX constructor - ONNX backend module");
}

HybridRunAnywhereONNX::~HybridRunAnywhereONNX() {
  RAC_LOG_INFO(LOG_CATEGORY, "HybridRunAnywhereONNX destructor");
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::registerBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_INFO(LOG_CATEGORY, "Registering ONNX backend with C++ registry...");

    rac_result_t result = rac_backend_onnx_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(LOG_CATEGORY, "ONNX backend registered successfully (STT + TTS + VAD)");
      isRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX registration failed with code: %d", result);
      throw std::runtime_error("ONNX registration failed with error: " + std::to_string(result));
    }
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_INFO(LOG_CATEGORY, "Unregistering ONNX backend...");

    rac_result_t result = rac_backend_onnx_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX unregistration failed with code: %d", result);
      throw std::runtime_error("ONNX unregistration failed with error: " + std::to_string(result));
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isRegistered_;
  });
}

} // namespace margelo::nitro::runanywhere::onnx
