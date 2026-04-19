/**
 * @file VADBridge.cpp
 * @brief VAD capability bridge implementation
 *
 * Aligned with rac_vad_component.h and rac_vad_types.h API.
 * RACommons is REQUIRED - no stub implementations.
 *
 * NOTE: VAD doesn't "load models" like LLM/STT/TTS.
 * Instead, it uses configure() + initialize() pattern.
 */

#include "VADBridge.hpp"
#include <stdexcept>

// RACommons logger - unified logging across platforms
#include "rac_logger.h"

// Category for VAD.ONNX logging
static const char* LOG_CATEGORY = "VAD.ONNX";

namespace runanywhere {
namespace bridges {

VADBridge& VADBridge::shared() {
    static VADBridge instance;
    return instance;
}

VADBridge::VADBridge() = default;

VADBridge::~VADBridge() {
    cleanup();
    if (handle_) {
        rac_vad_component_destroy(handle_);
        handle_ = nullptr;
    }
}

bool VADBridge::isLoaded() const {
    if (handle_) {
        return rac_vad_component_is_initialized(handle_) == RAC_TRUE;
    }
    return false;
}

std::string VADBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t VADBridge::loadModel(const std::string& modelId) {
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_vad_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("VADBridge: Failed to create VAD component. Error: " + std::to_string(result));
        }
    }

    // If already initialized with same modelId, return success
    if (isLoaded() && loadedModelId_ == modelId) {
        return RAC_SUCCESS;
    }

    // Stop current VAD processing if running
    if (isLoaded()) {
        rac_vad_component_stop(handle_);
    }

    // Configure VAD with the model_id (used for telemetry)
    rac_vad_config_t config = RAC_VAD_CONFIG_DEFAULT;
    config.model_id = modelId.c_str();

    rac_result_t result = rac_vad_component_configure(handle_, &config);
    if (result != RAC_SUCCESS) {
        throw std::runtime_error("VADBridge: Failed to configure VAD with model '" + modelId + "'. Error: " + std::to_string(result));
    }

    // Initialize the VAD
    result = rac_vad_component_initialize(handle_);
    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
        RAC_LOG_INFO(LOG_CATEGORY, "VAD initialized with model: %s", modelId.c_str());
    } else {
        throw std::runtime_error("VADBridge: Failed to initialize VAD. Error: " + std::to_string(result));
    }

    return result;
}

rac_result_t VADBridge::unload() {
    if (handle_) {
        // Stop VAD processing (there's no unload for VAD)
        rac_result_t result = rac_vad_component_stop(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
            RAC_LOG_INFO(LOG_CATEGORY, "VAD stopped");
        } else {
            throw std::runtime_error("VADBridge: Failed to stop VAD. Error: " + std::to_string(result));
        }
        return result;
    }
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void VADBridge::cleanup() {
    if (handle_) {
        rac_vad_component_cleanup(handle_);
    }
    loadedModelId_.clear();
}

void VADBridge::reset() {
    if (handle_) {
        rac_result_t result = rac_vad_component_reset(handle_);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CATEGORY, "Failed to reset VAD: %d", result);
        }
    }
    // Note: reset() doesn't clear the model, just resets the VAD state
}

VADResult VADBridge::process(const void* audioData, size_t audioSize, const VADOptions& options) {
    VADResult result;

    if (!handle_ || !isLoaded()) {
        throw std::runtime_error("VADBridge: VAD not initialized. Call loadModel() first.");
    }

    // Convert audio data to float samples
    // Assuming audioData is already float samples or we need to convert
    const float* samples = static_cast<const float*>(audioData);
    size_t numSamples = audioSize / sizeof(float);

    // Update energy threshold if specified
    if (options.threshold > 0) {
        rac_vad_component_set_energy_threshold(handle_, options.threshold);
    }

    // Process audio
    rac_bool_t isSpeech = RAC_FALSE;
    rac_result_t status = rac_vad_component_process(handle_, samples, numSamples, &isSpeech);

    if (status != RAC_SUCCESS) {
        throw std::runtime_error("VADBridge: VAD processing failed with error code: " + std::to_string(status));
    }

    result.isSpeech = isSpeech == RAC_TRUE;

    // Get additional info if needed
    result.probability = rac_vad_component_get_energy_threshold(handle_);
    result.speechProbability = result.probability; // Alias for API compatibility
    result.durationMs = 0; // Not directly available from simple VAD API

    return result;
}

} // namespace bridges
} // namespace runanywhere
