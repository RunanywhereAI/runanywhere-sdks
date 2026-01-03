/**
 * @file VADBridge.cpp
 * @brief VAD capability bridge implementation
 */

#include "VADBridge.hpp"

namespace runanywhere {
namespace bridges {

VADBridge& VADBridge::shared() {
    static VADBridge instance;
    return instance;
}

VADBridge::VADBridge() = default;

VADBridge::~VADBridge() {
    cleanup();
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_vad_component_destroy(handle_);
        handle_ = nullptr;
    }
#endif
}

bool VADBridge::isLoaded() const {
#ifdef HAS_RACOMMONS
    if (handle_) {
        return rac_vad_component_is_loaded(handle_) == RAC_TRUE;
    }
#endif
    return false;
}

std::string VADBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t VADBridge::loadModel(const std::string& modelId) {
#ifdef HAS_RACOMMONS
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_vad_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            return result;
        }
    }

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != modelId) {
        rac_vad_component_unload(handle_);
    }

    // Load new model
    rac_result_t result = rac_vad_component_load_model(handle_, modelId.c_str());
    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
    }
    return result;
#else
    loadedModelId_ = modelId;
    return RAC_SUCCESS;
#endif
}

rac_result_t VADBridge::unload() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_result_t result = rac_vad_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        }
        return result;
    }
#endif
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void VADBridge::cleanup() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_vad_component_cleanup(handle_);
    }
#endif
    loadedModelId_.clear();
}

VADResult VADBridge::process(const void* audioData, size_t audioSize, const VADOptions& options) {
    VADResult result;

#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        return result;
    }

    rac_vad_options_t racOptions = {};
    racOptions.threshold = options.threshold;
    racOptions.window_size_ms = options.windowSizeMs;
    racOptions.sample_rate = options.sampleRate;

    rac_vad_result_t racResult = {};
    rac_result_t status = rac_vad_component_process(handle_, audioData, audioSize,
                                                     &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        result.isSpeech = racResult.is_speech == RAC_TRUE;
        result.probability = racResult.probability;
        result.durationMs = racResult.duration_ms;
    }
#endif

    return result;
}

} // namespace bridges
} // namespace runanywhere
