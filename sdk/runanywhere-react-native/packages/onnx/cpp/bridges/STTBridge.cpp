/**
 * @file STTBridge.cpp
 * @brief STT capability bridge implementation
 *
 * Aligned with rac_stt_component.h and rac_stt_types.h API.
 * RACommons and ONNX backend are REQUIRED - no stub implementations.
 */

#include "STTBridge.hpp"
#include <stdexcept>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "STTBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[STTBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[STTBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[STTBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

STTBridge& STTBridge::shared() {
    static STTBridge instance;
    return instance;
}

STTBridge::STTBridge() = default;

STTBridge::~STTBridge() {
    cleanup();
    if (handle_) {
        rac_stt_component_destroy(handle_);
        handle_ = nullptr;
    }
}

bool STTBridge::isLoaded() const {
    if (handle_) {
        return rac_stt_component_is_loaded(handle_) == RAC_TRUE;
    }
    return false;
}

std::string STTBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t STTBridge::loadModel(const std::string& modelPath,
                                   const std::string& modelId,
                                   const std::string& modelName) {
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_stt_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("STTBridge: Failed to create STT component. Error: " + std::to_string(result));
        }
    }

    // Use modelPath as modelId if not provided
    std::string effectiveModelId = modelId.empty() ? modelPath : modelId;
    std::string effectiveModelName = modelName.empty() ? effectiveModelId : modelName;

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != effectiveModelId) {
        rac_stt_component_unload(handle_);
    }

    // Load new model with 4-argument signature
    rac_result_t result = rac_stt_component_load_model(
        handle_,
        modelPath.c_str(),
        effectiveModelId.c_str(),
        effectiveModelName.c_str()
    );

    if (result == RAC_SUCCESS) {
        loadedModelId_ = effectiveModelId;
        LOGI("STT model loaded: %s", effectiveModelId.c_str());
    } else {
        throw std::runtime_error("STTBridge: Failed to load STT model '" + effectiveModelId + "'. Error: " + std::to_string(result));
    }
    return result;
}

rac_result_t STTBridge::unload() {
    if (handle_) {
        rac_result_t result = rac_stt_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        } else {
            throw std::runtime_error("STTBridge: Failed to unload STT model. Error: " + std::to_string(result));
        }
        return result;
    }
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void STTBridge::cleanup() {
    if (handle_) {
        rac_stt_component_cleanup(handle_);
    }
    loadedModelId_.clear();
}

STTResult STTBridge::transcribe(const void* audioData, size_t audioSize,
                                 const STTOptions& options) {
    STTResult result;

    if (!handle_ || !isLoaded()) {
        throw std::runtime_error("STTBridge: STT model not loaded. Call loadModel() first.");
    }

    rac_stt_options_t racOptions = RAC_STT_OPTIONS_DEFAULT;
    if (!options.language.empty()) {
        racOptions.language = options.language.c_str();
    }
    racOptions.sample_rate = options.sampleRate > 0 ? options.sampleRate : RAC_STT_DEFAULT_SAMPLE_RATE;

    rac_stt_result_t racResult = {};
    rac_result_t status = rac_stt_component_transcribe(handle_, audioData, audioSize,
                                                        &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        if (racResult.text) {
            result.text = racResult.text;
        }
        result.durationMs = static_cast<double>(racResult.processing_time_ms);
        result.confidence = racResult.confidence;
        result.isFinal = true;

        // Free the C result
        rac_stt_result_free(&racResult);
    } else {
        throw std::runtime_error("STTBridge: Transcription failed with error code: " + std::to_string(status));
    }

    return result;
}

void STTBridge::transcribeStream(const void* audioData, size_t audioSize,
                                  const STTOptions& options,
                                  const STTStreamCallbacks& callbacks) {
    if (!handle_ || !isLoaded()) {
        if (callbacks.onError) {
            callbacks.onError(-4, "STT model not loaded. Call loadModel() first.");
        }
        return;
    }

    rac_stt_options_t racOptions = RAC_STT_OPTIONS_DEFAULT;
    if (!options.language.empty()) {
        racOptions.language = options.language.c_str();
    }
    racOptions.sample_rate = options.sampleRate > 0 ? options.sampleRate : RAC_STT_DEFAULT_SAMPLE_RATE;

    // Stream context for callbacks
    struct StreamContext {
        const STTStreamCallbacks* callbacks;
    };

    StreamContext ctx = { &callbacks };

    auto streamCallback = [](const char* partial_text, rac_bool_t is_final, void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (!ctx || !partial_text) return;

        STTResult sttResult;
        sttResult.text = partial_text;
        sttResult.confidence = 1.0f;
        sttResult.isFinal = is_final == RAC_TRUE;

        if (sttResult.isFinal && ctx->callbacks->onFinalResult) {
            ctx->callbacks->onFinalResult(sttResult);
        } else if (!sttResult.isFinal && ctx->callbacks->onPartialResult) {
            ctx->callbacks->onPartialResult(sttResult);
        }
    };

    rac_stt_component_transcribe_stream(handle_, audioData, audioSize,
                                         &racOptions, streamCallback, &ctx);
}

} // namespace bridges
} // namespace runanywhere
