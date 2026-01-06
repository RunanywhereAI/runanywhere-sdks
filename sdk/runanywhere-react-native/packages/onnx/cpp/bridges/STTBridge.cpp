/**
 * @file STTBridge.cpp
 * @brief STT capability bridge implementation
 */

#include "STTBridge.hpp"

namespace runanywhere {
namespace bridges {

STTBridge& STTBridge::shared() {
    static STTBridge instance;
    return instance;
}

STTBridge::STTBridge() = default;

STTBridge::~STTBridge() {
    cleanup();
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_stt_component_destroy(handle_);
        handle_ = nullptr;
    }
#endif
}

bool STTBridge::isLoaded() const {
#ifdef HAS_RACOMMONS
    if (handle_) {
        return rac_stt_component_is_loaded(handle_) == RAC_TRUE;
    }
#endif
    return false;
}

std::string STTBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t STTBridge::loadModel(const std::string& modelId) {
#ifdef HAS_RACOMMONS
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_stt_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            return result;
        }
    }

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != modelId) {
        rac_stt_component_unload(handle_);
    }

    // Load new model
    rac_result_t result = rac_stt_component_load_model(handle_, modelId.c_str());
    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
    }
    return result;
#else
    loadedModelId_ = modelId;
    return RAC_SUCCESS;
#endif
}

rac_result_t STTBridge::unload() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_result_t result = rac_stt_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        }
        return result;
    }
#endif
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void STTBridge::cleanup() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_stt_component_cleanup(handle_);
    }
#endif
    loadedModelId_.clear();
}

STTResult STTBridge::transcribe(const void* audioData, size_t audioSize,
                                 const STTOptions& options) {
    STTResult result;

#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        return result;
    }

    rac_stt_options_t racOptions = {};
    // TODO: Map options to racOptions

    rac_stt_result_t racResult = {};
    rac_result_t status = rac_stt_component_transcribe(handle_, audioData, audioSize,
                                                        &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        if (racResult.text) {
            result.text = racResult.text;
        }
        result.durationMs = racResult.duration_ms;
        result.confidence = racResult.confidence;
        result.isFinal = true;
    }
#else
    result.text = "[STT not available - RACommons not linked]";
#endif

    return result;
}

void STTBridge::transcribeStream(const void* audioData, size_t audioSize,
                                  const STTOptions& options,
                                  const STTStreamCallbacks& callbacks) {
#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        if (callbacks.onError) {
            callbacks.onError(-4, "Model not loaded");
        }
        return;
    }

    rac_stt_options_t racOptions = {};
    // TODO: Map options to racOptions

    // Stream context for callbacks
    struct StreamContext {
        const STTStreamCallbacks* callbacks;
    };

    StreamContext ctx = { &callbacks };

    auto streamCallback = [](const rac_stt_result_t* result, void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (!ctx || !result) return;

        STTResult sttResult;
        if (result->text) {
            sttResult.text = result->text;
        }
        sttResult.durationMs = result->duration_ms;
        sttResult.confidence = result->confidence;
        sttResult.isFinal = result->is_final == RAC_TRUE;

        if (sttResult.isFinal && ctx->callbacks->onFinalResult) {
            ctx->callbacks->onFinalResult(sttResult);
        } else if (!sttResult.isFinal && ctx->callbacks->onPartialResult) {
            ctx->callbacks->onPartialResult(sttResult);
        }
    };

    rac_stt_component_transcribe_stream(handle_, audioData, audioSize,
                                         &racOptions, streamCallback, &ctx);
#else
    if (callbacks.onFinalResult) {
        STTResult result;
        result.text = "[STT streaming not available]";
        result.isFinal = true;
        callbacks.onFinalResult(result);
    }
#endif
}

} // namespace bridges
} // namespace runanywhere
