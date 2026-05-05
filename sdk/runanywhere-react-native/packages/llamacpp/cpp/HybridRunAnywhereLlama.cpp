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

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// Log category for this module
#define LOG_CATEGORY "LLM.LlamaCpp"
#define VLM_LOG_CATEGORY "VLM.LlamaCpp"

namespace margelo::nitro::runanywhere::llama {

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
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(LOG_CATEGORY, "LlamaCPP backend registered successfully");
      isRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP registration failed with error: " + std::to_string(result));
    }
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
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(VLM_LOG_CATEGORY, "LlamaCPP VLM backend registered successfully");
      isVLMRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(VLM_LOG_CATEGORY, "LlamaCPP VLM registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP VLM registration failed with error: " + std::to_string(result));
    }
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
