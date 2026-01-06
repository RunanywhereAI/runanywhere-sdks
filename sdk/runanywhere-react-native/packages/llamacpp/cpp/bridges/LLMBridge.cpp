/**
 * @file LLMBridge.cpp
 * @brief LLM capability bridge implementation
 *
 * NOTE: RACommons and LlamaCPP backend are REQUIRED and always linked via the build system.
 */

#include "LLMBridge.hpp"
#include <stdexcept>

namespace runanywhere {
namespace bridges {

LLMBridge& LLMBridge::shared() {
    static LLMBridge instance;
    return instance;
}

LLMBridge::LLMBridge() = default;

LLMBridge::~LLMBridge() {
    destroy();
}

bool LLMBridge::isLoaded() const {
    if (handle_) {
        return rac_llm_component_is_loaded(handle_) == RAC_TRUE;
    }
    return false;
}

std::string LLMBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t LLMBridge::loadModel(const std::string& modelPath,
                                  const std::string& modelId,
                                  const std::string& modelName) {
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_llm_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("LLMBridge: Failed to create LLM component. Error: " + std::to_string(result));
        }
    }

    // Use modelPath as modelId if not provided
    std::string effectiveModelId = modelId.empty() ? modelPath : modelId;
    std::string effectiveModelName = modelName.empty() ? effectiveModelId : modelName;

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != effectiveModelId) {
        rac_llm_component_unload(handle_);
    }

    // Load new model with correct 4-arg signature
    // rac_llm_component_load_model(handle, model_path, model_id, model_name)
    rac_result_t result = rac_llm_component_load_model(
        handle_,
        modelPath.c_str(),
        effectiveModelId.c_str(),
        effectiveModelName.c_str()
    );
    if (result == RAC_SUCCESS) {
        loadedModelId_ = effectiveModelId;
    } else {
        throw std::runtime_error("LLMBridge: Failed to load LLM model '" + effectiveModelId + "'. Error: " + std::to_string(result));
    }
    return result;
}

rac_result_t LLMBridge::unload() {
    if (handle_) {
        rac_result_t result = rac_llm_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        } else {
            throw std::runtime_error("LLMBridge: Failed to unload LLM model. Error: " + std::to_string(result));
        }
        return result;
    }
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void LLMBridge::cleanup() {
    if (handle_) {
        rac_llm_component_cleanup(handle_);
    }
    loadedModelId_.clear();
}

void LLMBridge::cancel() {
    cancellationRequested_ = true;
    if (handle_) {
        rac_llm_component_cancel(handle_);
    }
}

void LLMBridge::destroy() {
    if (handle_) {
        rac_llm_component_destroy(handle_);
        handle_ = nullptr;
    }
    loadedModelId_.clear();
}

LLMResult LLMBridge::generate(const std::string& prompt, const LLMOptions& options) {
    LLMResult result;
    cancellationRequested_ = false;

    if (!handle_ || !isLoaded()) {
        throw std::runtime_error("LLMBridge: LLM model not loaded. Call loadModel() first.");
    }

    rac_llm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    // NOTE: top_k is not available in rac_llm_options_t, only top_p

    rac_llm_result_t racResult = {};
    rac_result_t status = rac_llm_component_generate(handle_, prompt.c_str(),
                                                      &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        if (racResult.text) {
            result.text = racResult.text;
        }
        result.tokenCount = racResult.completion_tokens;
        result.durationMs = static_cast<double>(racResult.total_time_ms);
    } else {
        throw std::runtime_error("LLMBridge: Text generation failed with error code: " + std::to_string(status));
    }

    result.cancelled = cancellationRequested_;
    return result;
}

void LLMBridge::generateStream(const std::string& prompt, const LLMOptions& options,
                               const LLMStreamCallbacks& callbacks) {
    cancellationRequested_ = false;

    if (!handle_ || !isLoaded()) {
        if (callbacks.onError) {
            callbacks.onError(-4, "LLM model not loaded. Call loadModel() first.");
        }
        return;
    }

    rac_llm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    // NOTE: top_k is not available in rac_llm_options_t, only top_p

    // Stream context for callbacks
    struct StreamContext {
        const LLMStreamCallbacks* callbacks;
        bool* cancellationRequested;
        std::string accumulatedText;
    };

    StreamContext ctx = { &callbacks, &cancellationRequested_, "" };

    auto tokenCallback = [](const char* token, void* user_data) -> rac_bool_t {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (*ctx->cancellationRequested) {
            return RAC_FALSE;
        }
        if (ctx->callbacks->onToken && token) {
            ctx->accumulatedText += token;
            return ctx->callbacks->onToken(token) ? RAC_TRUE : RAC_FALSE;
        }
        return RAC_TRUE;
    };

    auto completeCallback = [](const rac_llm_result_t* result, void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (ctx->callbacks->onComplete) {
            ctx->callbacks->onComplete(
                ctx->accumulatedText,
                result ? result->completion_tokens : 0,
                result ? static_cast<double>(result->total_time_ms) : 0.0
            );
        }
    };

    auto errorCallback = [](rac_result_t error_code, const char* error_message,
                           void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (ctx->callbacks->onError) {
            ctx->callbacks->onError(error_code, error_message ? error_message : "Unknown error");
        }
    };

    rac_llm_component_generate_stream(handle_, prompt.c_str(), &racOptions,
                                      tokenCallback, completeCallback, errorCallback, &ctx);
}

rac_lifecycle_state_t LLMBridge::getState() const {
    if (handle_) {
        return rac_llm_component_get_state(handle_);
    }
    return RAC_LIFECYCLE_STATE_IDLE;
}

} // namespace bridges
} // namespace runanywhere
