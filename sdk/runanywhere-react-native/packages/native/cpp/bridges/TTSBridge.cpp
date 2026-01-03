/**
 * @file TTSBridge.cpp
 * @brief TTS capability bridge implementation
 */

#include "TTSBridge.hpp"

namespace runanywhere {
namespace bridges {

TTSBridge& TTSBridge::shared() {
    static TTSBridge instance;
    return instance;
}

TTSBridge::TTSBridge() = default;

TTSBridge::~TTSBridge() {
    cleanup();
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_tts_component_destroy(handle_);
        handle_ = nullptr;
    }
#endif
}

bool TTSBridge::isLoaded() const {
#ifdef HAS_RACOMMONS
    if (handle_) {
        return rac_tts_component_is_loaded(handle_) == RAC_TRUE;
    }
#endif
    return false;
}

std::string TTSBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t TTSBridge::loadModel(const std::string& modelId) {
#ifdef HAS_RACOMMONS
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_tts_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            return result;
        }
    }

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != modelId) {
        rac_tts_component_unload(handle_);
    }

    // Load new model
    rac_result_t result = rac_tts_component_load_model(handle_, modelId.c_str());
    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
    }
    return result;
#else
    loadedModelId_ = modelId;
    return RAC_SUCCESS;
#endif
}

rac_result_t TTSBridge::unload() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_result_t result = rac_tts_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        }
        return result;
    }
#endif
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void TTSBridge::cleanup() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_tts_component_cleanup(handle_);
    }
#endif
    loadedModelId_.clear();
}

TTSResult TTSBridge::synthesize(const std::string& text, const TTSOptions& options) {
    TTSResult result;

#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        return result;
    }

    rac_tts_options_t racOptions = {};
    racOptions.speed = options.speed;
    racOptions.pitch = options.pitch;
    racOptions.sample_rate = options.sampleRate;

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
        result.durationMs = racResult.duration_ms;
    }
#endif

    return result;
}

} // namespace bridges
} // namespace runanywhere
