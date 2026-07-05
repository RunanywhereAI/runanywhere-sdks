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

// Backend registration headers - always available.
// Resolve the canonical commons header (RACommons xcframework / jniLibs) rather
// than a per-package fork, so the full published LlamaCPP ABI stays in sync.
extern "C" {
#include "rac/backends/rac_llm_llamacpp.h"
}

#include "rac/core/rac_error.h"

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <stdexcept>
#include <string>

// Log category for this module
#define LOG_CATEGORY "LLM.LlamaCpp"

namespace margelo::nitro::runanywhere::llama {

namespace {

bool isRegistrationSuccess(rac_result_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

} // namespace

// Constructor / Destructor

HybridRunAnywhereLlama::HybridRunAnywhereLlama() : HybridObject(TAG) {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama constructor - Llama backend module");
}

HybridRunAnywhereLlama::~HybridRunAnywhereLlama() {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama destructor");
}

// Backend Registration

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::registerBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Registering LlamaCPP backend with C++ registry");

    // rac_backend_llamacpp_register() internally registers both the module and
    // the plugin entry (rac_plugin_entry_llamacpp()) — see
    // engines/llamacpp/rac_backend_llamacpp_register.cpp:462-478, which plugs
    // the Android dynamic-loading gap where the RAC_STATIC_PLUGIN_REGISTER ctor
    // never fires (Kotlin/JNI loads librac_backend_llamacpp_jni.so directly,
    // not the carrier librunanywhere_llamacpp.so). Matches the iOS Swift
    // source-of-truth in sdk/runanywhere-swift/Sources/LlamaCPPRuntime which
    // also relies on the in-engine registration only.
    rac_result_t result = rac_backend_llamacpp_register();
    if (!isRegistrationSuccess(result)) {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP registration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP registration failed with error: " + std::to_string(result));
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

} // namespace margelo::nitro::runanywhere::llama
