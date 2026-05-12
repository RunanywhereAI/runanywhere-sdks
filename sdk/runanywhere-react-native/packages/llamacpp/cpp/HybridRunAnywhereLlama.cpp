/**
 * HybridRunAnywhereLlama.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere Llama backend.
 *
 * Llama-specific provider registration for LlamaCPP.
 *
 * NOTE: LlamaCPP backend is REQUIRED and always linked via the build system.
 */

#include "HybridRunAnywhereLlama.hpp"

// Backend registration headers - always available
extern "C" {
#include "rac_llm_llamacpp.h"
#include "rac_vlm_llamacpp.h"
}

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_llamacpp.h"

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// Log category for this module
#define LOG_CATEGORY "LLM.LlamaCpp"
#define VLM_LOG_CATEGORY "VLM.LlamaCpp"

namespace margelo::nitro::runanywhere::llama {

namespace {

bool isRegistrationSuccess(rac_result_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

} // namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereLlama::HybridRunAnywhereLlama() : HybridObject(TAG) {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama constructor - Llama backend module");
}

HybridRunAnywhereLlama::~HybridRunAnywhereLlama() {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama destructor");
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::registerBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Registering LlamaCPP backend with C++ registry");

    rac_result_t result = rac_backend_llamacpp_register();
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP registration failed with error: " + std::to_string(result));
    }

    // Android loads the backend as a dynamic shared library. Unlike iOS static
    // linking, the plugin auto-registration shim intentionally does not run in
    // that mode, so the RN host must register the unified router vtable here.
    result = rac_plugin_register(rac_plugin_entry_llamacpp());
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP plugin registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP plugin registration failed with error: " + std::to_string(result));
    }

    RAC_LOG_INFO(LOG_CATEGORY, "LlamaCPP backend registered successfully");
    isRegistered_ = true;
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Unregistering LlamaCPP backend");

    rac_result_t result = rac_backend_llamacpp_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP unregistration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP unregistration failed with error: " + std::to_string(result));
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::isBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isRegistered_;
  });
}

// ============================================================================
// VLM Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::registerVLMBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(VLM_LOG_CATEGORY, "Registering LlamaCPP VLM backend with C++ registry");

    rac_result_t result = rac_backend_llamacpp_vlm_register();
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(VLM_LOG_CATEGORY, "LlamaCPP VLM registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP VLM registration failed with error: " + std::to_string(result));
    }

    result = rac_plugin_register(rac_plugin_entry_llamacpp_vlm());
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(VLM_LOG_CATEGORY, "LlamaCPP VLM plugin registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP VLM plugin registration failed with error: " + std::to_string(result));
    }

    RAC_LOG_INFO(VLM_LOG_CATEGORY, "LlamaCPP VLM backend registered successfully");
    isVLMRegistered_ = true;
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::unregisterVLMBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(VLM_LOG_CATEGORY, "Unregistering LlamaCPP VLM backend");

    rac_result_t result = rac_backend_llamacpp_vlm_unregister();
    isVLMRegistered_ = false;
    if (result == RAC_SUCCESS) {
      RAC_LOG_INFO(VLM_LOG_CATEGORY, "LlamaCPP VLM backend unregistered");
      return true;
    }

    RAC_LOG_ERROR(VLM_LOG_CATEGORY, "LlamaCPP VLM unregistration failed with code: %d", result);
    throw std::runtime_error("LlamaCPP VLM unregistration failed with error: " + std::to_string(result));
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::isVLMBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isVLMRegistered_;
  });
}

} // namespace margelo::nitro::runanywhere::llama
