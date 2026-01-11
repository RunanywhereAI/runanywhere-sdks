/**
 * @file TTSBridge.cpp
 * @brief TTS capability bridge implementation
 *
 * Aligned with rac_tts_component.h and rac_tts_types.h API.
 * RACommons and ONNX backend are REQUIRED - no stub implementations.
 */

#include "TTSBridge.hpp"
#include <stdexcept>
#include <cstring>

// RACommons logger - unified logging across platforms
#include "rac_logger.h"

// Category for TTS.ONNX logging
static const char* LOG_CATEGORY = "TTS.ONNX";

namespace runanywhere {
namespace bridges {

TTSBridge& TTSBridge::shared() {
    static TTSBridge instance;
    return instance;
}

TTSBridge::TTSBridge() = default;

TTSBridge::~TTSBridge() {
    cleanup();
    if (handle_) {
        rac_tts_component_destroy(handle_);
        handle_ = nullptr;
    }
}

bool TTSBridge::isLoaded() const {
    if (handle_) {
        return rac_tts_component_is_loaded(handle_) == RAC_TRUE;
    }
    return false;
}

std::string TTSBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t TTSBridge::loadModel(const std::string& modelId) {
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_tts_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("TTSBridge: Failed to create TTS component. Error: " + std::to_string(result));
        }
    }

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != modelId) {
        rac_tts_component_unload(handle_);
    }

    // Load new voice using rac_tts_component_load_voice(handle, voice_path, voice_id, voice_name)
    // For TTS, modelId is the voice path/id
    rac_result_t result = rac_tts_component_load_voice(
        handle_,
        modelId.c_str(),  // voice_path
        modelId.c_str(),  // voice_id
        modelId.c_str()   // voice_name
    );

    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
        RAC_LOG_INFO(LOG_CATEGORY, "TTS voice loaded: %s", modelId.c_str());
    } else {
        throw std::runtime_error("TTSBridge: Failed to load TTS voice '" + modelId + "'. Error: " + std::to_string(result));
    }
    return result;
}

rac_result_t TTSBridge::unload() {
    if (handle_) {
        rac_result_t result = rac_tts_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        } else {
            throw std::runtime_error("TTSBridge: Failed to unload TTS voice. Error: " + std::to_string(result));
        }
        return result;
    }
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void TTSBridge::cleanup() {
    if (handle_) {
        rac_tts_component_cleanup(handle_);
    }
    loadedModelId_.clear();
}

TTSResult TTSBridge::synthesize(const std::string& text, const TTSOptions& options) {
    TTSResult result;

    if (!handle_ || !isLoaded()) {
        throw std::runtime_error("TTSBridge: TTS voice not loaded. Call loadModel() first.");
    }

    rac_tts_options_t racOptions = RAC_TTS_OPTIONS_DEFAULT;
    racOptions.rate = options.speed > 0 ? options.speed : 1.0f;
    racOptions.pitch = options.pitch > 0 ? options.pitch : 1.0f;
    racOptions.sample_rate = options.sampleRate > 0 ? options.sampleRate : RAC_TTS_DEFAULT_SAMPLE_RATE;
    if (!options.voiceId.empty()) {
        racOptions.voice = options.voiceId.c_str();
    }

    rac_tts_result_t racResult = {};
    rac_result_t status = rac_tts_component_synthesize(handle_, text.c_str(),
                                                        &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        // Copy audio data
        if (racResult.audio_data && racResult.audio_size > 0) {
            size_t numSamples = racResult.audio_size / sizeof(float);
            result.audioData.resize(numSamples);
            std::memcpy(result.audioData.data(), racResult.audio_data, racResult.audio_size);
        }
        result.sampleRate = racResult.sample_rate;
        result.durationMs = static_cast<double>(racResult.duration_ms);

        // Free the C result
        rac_tts_result_free(&racResult);
    } else {
        throw std::runtime_error("TTSBridge: Speech synthesis failed with error code: " + std::to_string(status));
    }

    return result;
}

} // namespace bridges
} // namespace runanywhere
