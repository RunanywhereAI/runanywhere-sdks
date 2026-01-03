/**
 * @file LLMBridge.cpp
 * @brief LLM capability bridge implementation
 */

#include "LLMBridge.hpp"

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
#ifdef HAS_RACOMMONS
    if (handle_) {
        return rac_llm_component_is_loaded(handle_) == RAC_TRUE;
    }
#endif
    return false;
}

std::string LLMBridge::currentModelId() const {
    return loadedModelId_;
}

rac_result_t LLMBridge::loadModel(const std::string& modelId) {
#ifdef HAS_RACOMMONS
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_llm_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            return result;
        }
    }

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != modelId) {
        rac_llm_component_unload(handle_);
    }

    // Load new model
    rac_result_t result = rac_llm_component_load_model(handle_, modelId.c_str());
    if (result == RAC_SUCCESS) {
        loadedModelId_ = modelId;
    }
    return result;
#else
    loadedModelId_ = modelId;
    return RAC_SUCCESS;
#endif
}

rac_result_t LLMBridge::unload() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_result_t result = rac_llm_component_unload(handle_);
        if (result == RAC_SUCCESS) {
            loadedModelId_.clear();
        }
        return result;
    }
#endif
    loadedModelId_.clear();
    return RAC_SUCCESS;
}

void LLMBridge::cleanup() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_llm_component_cleanup(handle_);
    }
#endif
    loadedModelId_.clear();
}

void LLMBridge::cancel() {
    cancellationRequested_ = true;
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_llm_component_cancel(handle_);
    }
#endif
}

void LLMBridge::destroy() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_llm_component_destroy(handle_);
        handle_ = nullptr;
    }
#endif
    loadedModelId_.clear();
}

LLMResult LLMBridge::generate(const std::string& prompt, const LLMOptions& options) {
    LLMResult result;
    cancellationRequested_ = false;

#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        return result;
    }

    rac_llm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    racOptions.top_k = options.topK;

    rac_llm_result_t racResult = {};
    rac_result_t status = rac_llm_component_generate(handle_, prompt.c_str(),
                                                      &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        if (racResult.text) {
            result.text = racResult.text;
        }
        result.tokenCount = racResult.token_count;
        result.durationMs = racResult.duration_ms;
    }
#else
    // Stub implementation when RACommons not available
    result.text = "[LLM generation not available - RACommons not linked]";
#endif

    result.cancelled = cancellationRequested_;
    return result;
}

void LLMBridge::generateStream(const std::string& prompt, const LLMOptions& options,
                               const LLMStreamCallbacks& callbacks) {
    cancellationRequested_ = false;

#ifdef HAS_RACOMMONS
    if (!handle_ || !isLoaded()) {
        if (callbacks.onError) {
            callbacks.onError(-4, "Model not loaded");
        }
        return;
    }

    rac_llm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    racOptions.top_k = options.topK;

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
                result ? result->token_count : 0,
                result ? result->duration_ms : 0.0
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
#else
    // Stub implementation
    if (callbacks.onToken) {
        callbacks.onToken("[LLM streaming not available]");
    }
    if (callbacks.onComplete) {
        callbacks.onComplete("[LLM streaming not available]", 0, 0.0);
    }
#endif
}

rac_lifecycle_state_t LLMBridge::getState() const {
#ifdef HAS_RACOMMONS
    if (handle_) {
        return rac_llm_component_get_state(handle_);
    }
#endif
    return 0;
}

} // namespace bridges
} // namespace runanywhere
