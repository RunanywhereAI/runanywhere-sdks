/**
 * @file VLMBridge.cpp
 * @brief VLM capability bridge implementation
 *
 * NOTE: RACommons and LlamaCPP backend are REQUIRED and always linked via the build system.
 */

#include "VLMBridge.hpp"
#include <stdexcept>
#include <cstring>

namespace runanywhere {
namespace bridges {

VLMBridge& VLMBridge::shared() {
    static VLMBridge instance;
    return instance;
}

VLMBridge::VLMBridge() = default;

VLMBridge::~VLMBridge() {
    destroy();
}

bool VLMBridge::isLoaded() const {
    if (handle_) {
        return rac_vlm_component_is_loaded(handle_) == RAC_TRUE;
    }
    return false;
}

std::string VLMBridge::currentModelId() const {
    return loadedModelId_;
}

void VLMBridge::loadModel(const std::string& modelPath,
                          const std::string& mmprojPath,
                          const std::string& modelId,
                          const std::string& modelName) {
    // Create component if needed
    if (!handle_) {
        rac_result_t result = rac_vlm_component_create(&handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("VLMBridge: Failed to create VLM component. Error: " + std::to_string(result));
        }
    }

    // Use modelPath as modelId if not provided
    std::string effectiveModelId = modelId.empty() ? modelPath : modelId;
    std::string effectiveModelName = modelName.empty() ? effectiveModelId : modelName;

    // Unload existing model if different
    if (isLoaded() && loadedModelId_ != effectiveModelId) {
        rac_vlm_component_cleanup(handle_);
    }

    // Handle mmprojPath - pass nullptr if empty string
    const char* mmprojPathPtr = mmprojPath.empty() ? nullptr : mmprojPath.c_str();

    // Load new model with correct 5-arg signature
    // rac_vlm_component_load_model(handle, model_path, mmproj_path, model_id, model_name)
    rac_result_t result = rac_vlm_component_load_model(
        handle_,
        modelPath.c_str(),
        mmprojPathPtr,
        effectiveModelId.c_str(),
        effectiveModelName.c_str()
    );
    if (result == RAC_SUCCESS) {
        loadedModelId_ = effectiveModelId;
    } else {
        throw std::runtime_error("VLMBridge: Failed to load VLM model '" + effectiveModelId + "'. Error: " + std::to_string(result));
    }
}

void VLMBridge::unload() {
    if (handle_) {
        rac_result_t result = rac_vlm_component_cleanup(handle_);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("VLMBridge: Failed to unload VLM model. Error: " + std::to_string(result));
        }
        loadedModelId_.clear();
    } else {
        loadedModelId_.clear();
    }
}

void VLMBridge::cleanup() {
    if (handle_) {
        rac_vlm_component_cleanup(handle_);
    }
    loadedModelId_.clear();
}

void VLMBridge::cancel() {
    cancellationRequested_ = true;
    if (handle_) {
        rac_vlm_component_cancel(handle_);
    }
}

void VLMBridge::destroy() {
    if (handle_) {
        rac_vlm_component_destroy(handle_);
        handle_ = nullptr;
    }
    loadedModelId_.clear();
}

VLMResult VLMBridge::process(const VLMImageInput& image, const std::string& prompt,
                             const VLMOptions& options) {
    VLMResult result;
    cancellationRequested_ = false;

    if (!handle_ || !isLoaded()) {
        throw std::runtime_error("VLMBridge: VLM model not loaded. Call loadModel() first.");
    }

    // Create rac_vlm_image_t from VLMImageInput
    rac_vlm_image_t racImage = {};
    racImage.format = image.format;

    if (image.format == RAC_VLM_IMAGE_FORMAT_FILE_PATH) {
        racImage.file_path = image.file_path.c_str();
    } else if (image.format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS) {
        racImage.pixel_data = image.pixel_data;
        racImage.width = image.width;
        racImage.height = image.height;
        racImage.data_size = image.data_size;
    } else if (image.format == RAC_VLM_IMAGE_FORMAT_BASE64) {
        racImage.base64_data = image.base64_data.c_str();
        racImage.data_size = image.base64_data.size();
    }

    // Create rac_vlm_options_t from VLMOptions
    rac_vlm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    racOptions.streaming_enabled = RAC_FALSE;

    // Call rac_vlm_component_process
    rac_vlm_result_t racResult = {};
    rac_result_t status = rac_vlm_component_process(handle_, &racImage, prompt.c_str(),
                                                      &racOptions, &racResult);

    if (status == RAC_SUCCESS) {
        if (racResult.text) {
            result.text = racResult.text;
        }
        result.promptTokens = racResult.prompt_tokens;
        result.completionTokens = racResult.completion_tokens;
        result.totalTimeMs = static_cast<double>(racResult.total_time_ms);
        result.tokensPerSecond = static_cast<double>(racResult.tokens_per_second);

        // Free the result
        rac_vlm_result_free(&racResult);
    } else {
        throw std::runtime_error("VLMBridge: Image processing failed with error code: " + std::to_string(status));
    }

    return result;
}

void VLMBridge::processStream(const VLMImageInput& image, const std::string& prompt,
                              const VLMOptions& options, const VLMStreamCallbacks& callbacks) {
    cancellationRequested_ = false;

    if (!handle_ || !isLoaded()) {
        if (callbacks.onError) {
            callbacks.onError(-4, "VLM model not loaded. Call loadModel() first.");
        }
        return;
    }

    // Create rac_vlm_image_t from VLMImageInput
    rac_vlm_image_t racImage = {};
    racImage.format = image.format;

    if (image.format == RAC_VLM_IMAGE_FORMAT_FILE_PATH) {
        racImage.file_path = image.file_path.c_str();
    } else if (image.format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS) {
        racImage.pixel_data = image.pixel_data;
        racImage.width = image.width;
        racImage.height = image.height;
        racImage.data_size = image.data_size;
    } else if (image.format == RAC_VLM_IMAGE_FORMAT_BASE64) {
        racImage.base64_data = image.base64_data.c_str();
        racImage.data_size = image.base64_data.size();
    }

    // Create rac_vlm_options_t from VLMOptions
    rac_vlm_options_t racOptions = {};
    racOptions.max_tokens = options.maxTokens;
    racOptions.temperature = static_cast<float>(options.temperature);
    racOptions.top_p = static_cast<float>(options.topP);
    racOptions.streaming_enabled = RAC_TRUE;

    // Stream context for callbacks
    struct StreamContext {
        const VLMStreamCallbacks* callbacks;
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

    auto completeCallback = [](const rac_vlm_result_t* result, void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (ctx->callbacks->onComplete) {
            ctx->callbacks->onComplete(result);
        }
    };

    auto errorCallback = [](rac_result_t error_code, const char* error_message,
                           void* user_data) {
        auto* ctx = static_cast<StreamContext*>(user_data);
        if (ctx->callbacks->onError) {
            ctx->callbacks->onError(error_code, error_message ? error_message : "Unknown error");
        }
    };

    rac_vlm_component_process_stream(handle_, &racImage, prompt.c_str(), &racOptions,
                                     tokenCallback, completeCallback, errorCallback, &ctx);
}

rac_lifecycle_state_t VLMBridge::getState() const {
    if (handle_) {
        return rac_vlm_component_get_state(handle_);
    }
    return RAC_LIFECYCLE_STATE_IDLE;
}

} // namespace bridges
} // namespace runanywhere
