/**
 * HybridRunAnywhereONNX.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere ONNX backend.
 *
 * Registers the generic ONNX engine and its co-distributed Sherpa speech engine.
 */

#include "HybridRunAnywhereONNX.hpp"

// Backend registration header - always available
extern "C" {
#include "rac_plugin_entry_onnx.h"
}

#include "rac/core/rac_error.h"

#if __has_include("rac/plugin/rac_plugin_entry_sherpa.h")
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#define RAC_RN_HAS_SHERPA_REGISTRATION 1
#else
#define RAC_RN_HAS_SHERPA_REGISTRATION 0
#endif

// RACommons logger - unified logging across platforms
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// Category for ONNX module logging
static const char* LOG_CATEGORY = "ONNX";

namespace margelo::nitro::runanywhere::onnx {

namespace {

bool isRegistrationSuccess(rac_result_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

std::string describeError(rac_result_t result) {
  const char* message = rac_error_message(result);
  if (message != nullptr) {
    return std::string(message) + " (" + std::to_string(result) + ")";
  }
  return std::to_string(result);
}

} // namespace

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
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX registration failed with code: %d", result);
      throw std::runtime_error("ONNX registration failed with error: " + describeError(result));
    }

    isRegistered_ = true;

#if RAC_RN_HAS_SHERPA_REGISTRATION
    // rac_backend_sherpa_register() installs BOTH the module record and the
    // unified plugin vtable in one call, so it and rac_plugin_register(entry)
    // are alternatives, not a chain. Mirror Flutter onnx_bindings.dart and
    // Swift ONNX.registerSherpaPlugin(): the wrapper symbol is exported
    // alongside this header, so call it once and stop. A failure here is a
    // genuine install failure, not something a redundant rac_plugin_register
    // could recover.
    rac_result_t sherpaResult = rac_backend_sherpa_register();
    if (isRegistrationSuccess(sherpaResult)) {
      isSherpaRegistered_ = true;
      RAC_LOG_INFO(LOG_CATEGORY, "Sherpa engine plugin registered (STT + TTS + VAD)");
    } else {
      RAC_LOG_WARNING(
        LOG_CATEGORY,
        "Sherpa backend registration failed with code: %d; Sherpa STT/TTS/VAD will not route",
        sherpaResult);
    }
#else
    RAC_LOG_WARNING(
      LOG_CATEGORY,
      "Sherpa registration header rac/plugin/rac_plugin_entry_sherpa.h is unavailable; "
      "Sherpa STT/TTS/VAD will rely on platform loader behavior");
#endif

    RAC_LOG_INFO(LOG_CATEGORY, "ONNX backend registered successfully");
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_INFO(LOG_CATEGORY, "Unregistering ONNX backend...");

#if RAC_RN_HAS_SHERPA_REGISTRATION
    if (isSherpaRegistered_) {
      rac_result_t sherpaResult = rac_backend_sherpa_unregister();
      if (sherpaResult == RAC_SUCCESS || sherpaResult == RAC_ERROR_MODULE_NOT_FOUND) {
        isSherpaRegistered_ = false;
        RAC_LOG_INFO(LOG_CATEGORY, "Sherpa backend unregistered");
      } else {
        RAC_LOG_WARNING(LOG_CATEGORY, "Sherpa unregistration failed with code: %d", sherpaResult);
      }
    }
#endif

    rac_result_t result = rac_backend_onnx_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX unregistration failed with code: %d", result);
      throw std::runtime_error("ONNX unregistration failed with error: " + describeError(result));
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
