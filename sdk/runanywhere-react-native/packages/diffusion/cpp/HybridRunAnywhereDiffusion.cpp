#include "HybridRunAnywhereDiffusion.hpp"
#include "bridges/DiffusionBridge.hpp"
#include <nlohmann/json.hpp>
#include <stdexcept>

// C API headers
extern "C" {
#include "rac_diffusion_onnx.h"
#include "rac_backend_diffusion.h"
#include "rac_common.h"
}

using json = nlohmann::json;

namespace margelo::nitro::runanywhere::diffusion {

HybridRunAnywhereDiffusion::HybridRunAnywhereDiffusion()
    : HybridObject(TAG) {
}

HybridRunAnywhereDiffusion::~HybridRunAnywhereDiffusion() {
    if (handle_) {
        rac_diffusion_component_destroy(handle_);
        handle_ = nullptr;
    }
}

// MARK: - Backend Registration

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::registerBackend() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        if (isRegistered_) {
            return true;
        }

        rac_result_t result = rac_backend_diffusion_onnx_register();
        if (result == RAC_SUCCESS) {
            isRegistered_ = true;
            return true;
        }

        lastError_ = "Failed to register diffusion backend";
        throw std::runtime_error(lastError_);
    });
}

// MARK: - Configuration

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::configure(const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureRegistered();

        // Create component if not exists
        if (!handle_) {
            rac_result_t createResult = rac_diffusion_component_create(&handle_);
            if (createResult != RAC_SUCCESS || !handle_) {
                throw std::runtime_error("Failed to create diffusion component");
            }
        }

        // Parse config JSON
        json config = json::parse(configJson);

        rac_diffusion_config_t racConfig = {};
        racConfig.model_variant = config.value("model_variant", 0);
        racConfig.enable_safety_checker = config.value("enable_safety_checker", true) ? RAC_TRUE : RAC_FALSE;
        racConfig.reduce_memory = config.value("reduce_memory", false) ? RAC_TRUE : RAC_FALSE;
        racConfig.tokenizer.source = config.value("tokenizer_source", 0);
        racConfig.tokenizer.auto_download = RAC_TRUE;

        std::string customUrl;
        if (config.contains("tokenizer_custom_url")) {
            customUrl = config["tokenizer_custom_url"].get<std::string>();
            racConfig.tokenizer.custom_base_url = customUrl.c_str();
        }

        rac_result_t result = rac_diffusion_component_configure(handle_, &racConfig);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to configure diffusion component");
        }

        return true;
    });
}

// MARK: - Model Management

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::loadModel(
    const std::string& path,
    const std::string& modelId,
    const std::optional<std::string>& modelName,
    const std::optional<std::string>& configJson) {

    return Promise<bool>::async([this, path, modelId, modelName, configJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureRegistered();

        if (!handle_) {
            rac_result_t createResult = rac_diffusion_component_create(&handle_);
            if (createResult != RAC_SUCCESS) {
                throw std::runtime_error("Failed to create diffusion component");
            }
        }

        // Configure if config provided
        if (configJson.has_value()) {
            json config = json::parse(configJson.value());
            rac_diffusion_config_t racConfig = {};
            racConfig.model_variant = config.value("model_variant", 0);
            racConfig.enable_safety_checker = config.value("enable_safety_checker", true) ? RAC_TRUE : RAC_FALSE;
            racConfig.reduce_memory = config.value("reduce_memory", false) ? RAC_TRUE : RAC_FALSE;
            rac_diffusion_component_configure(handle_, &racConfig);
        }

        const char* name = modelName.has_value() ? modelName->c_str() : nullptr;

        rac_result_t result = rac_diffusion_component_load(
            handle_,
            path.c_str(),
            modelId.c_str(),
            name
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to load diffusion model");
        }

        currentModelId_ = modelId;
        return true;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereDiffusion::unloadModel() {
    return Promise<void>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        if (handle_) {
            rac_diffusion_component_unload(handle_);
            currentModelId_.clear();
        }
    });
}

bool HybridRunAnywhereDiffusion::isModelLoaded() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!handle_) return false;

    rac_bool_t loaded = RAC_FALSE;
    rac_diffusion_component_is_loaded(handle_, &loaded);
    return loaded == RAC_TRUE;
}

std::optional<std::string> HybridRunAnywhereDiffusion::currentModelId() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (currentModelId_.empty()) {
        return std::nullopt;
    }
    return currentModelId_;
}

// MARK: - Image Generation

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::generateImage(
    const std::string& prompt,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, optionsJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureModelLoaded();

        json options = json::parse(optionsJson);

        rac_diffusion_options_t racOptions = {};
        racOptions.prompt = prompt.c_str();

        std::string negPrompt = options.value("negative_prompt", "");
        racOptions.negative_prompt = negPrompt.c_str();

        racOptions.width = options.value("width", 512);
        racOptions.height = options.value("height", 512);
        racOptions.steps = options.value("steps", 28);
        racOptions.guidance_scale = options.value("guidance_scale", 7.5f);
        racOptions.seed = options.value("seed", -1);
        racOptions.scheduler = options.value("scheduler", 0);
        racOptions.mode = 0; // Text-to-image

        rac_diffusion_result_t racResult = {};
        rac_result_t result = rac_diffusion_component_generate(
            handle_,
            &racOptions,
            nullptr, 0,  // No input image
            nullptr, 0,  // No mask
            &racResult
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Image generation failed");
        }

        // Convert result to JSON
        json resultJson;
        resultJson["width"] = racResult.width;
        resultJson["height"] = racResult.height;
        resultJson["seed_used"] = racResult.seed_used;
        resultJson["generation_time_ms"] = racResult.generation_time_ms;

        // Encode image data as base64
        if (racResult.image_data && racResult.image_data_size > 0) {
            resultJson["image_base64"] = DiffusionBridge::encodeBase64(
                racResult.image_data,
                racResult.image_data_size
            );
        }

        // Free result
        rac_diffusion_result_free(&racResult);

        return resultJson.dump();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::imageToImage(
    const std::string& prompt,
    const std::string& inputImageBase64,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, inputImageBase64, optionsJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureModelLoaded();

        json options = json::parse(optionsJson);

        // Decode input image
        std::vector<uint8_t> inputImage = DiffusionBridge::decodeBase64(inputImageBase64);

        rac_diffusion_options_t racOptions = {};
        racOptions.prompt = prompt.c_str();

        std::string negPrompt = options.value("negative_prompt", "");
        racOptions.negative_prompt = negPrompt.c_str();

        racOptions.width = options.value("width", 512);
        racOptions.height = options.value("height", 512);
        racOptions.steps = options.value("steps", 28);
        racOptions.guidance_scale = options.value("guidance_scale", 7.5f);
        racOptions.seed = options.value("seed", -1);
        racOptions.scheduler = options.value("scheduler", 0);
        racOptions.mode = 1; // Image-to-image
        racOptions.denoise_strength = options.value("denoise_strength", 0.8f);

        rac_diffusion_result_t racResult = {};
        rac_result_t result = rac_diffusion_component_generate(
            handle_,
            &racOptions,
            inputImage.data(), inputImage.size(),
            nullptr, 0,
            &racResult
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Image-to-image generation failed");
        }

        json resultJson;
        resultJson["width"] = racResult.width;
        resultJson["height"] = racResult.height;
        resultJson["seed_used"] = racResult.seed_used;
        resultJson["generation_time_ms"] = racResult.generation_time_ms;

        if (racResult.image_data && racResult.image_data_size > 0) {
            resultJson["image_base64"] = DiffusionBridge::encodeBase64(
                racResult.image_data,
                racResult.image_data_size
            );
        }

        rac_diffusion_result_free(&racResult);
        return resultJson.dump();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::inpaint(
    const std::string& prompt,
    const std::string& inputImageBase64,
    const std::string& maskImageBase64,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, inputImageBase64, maskImageBase64, optionsJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureModelLoaded();

        json options = json::parse(optionsJson);

        std::vector<uint8_t> inputImage = DiffusionBridge::decodeBase64(inputImageBase64);
        std::vector<uint8_t> maskImage = DiffusionBridge::decodeBase64(maskImageBase64);

        rac_diffusion_options_t racOptions = {};
        racOptions.prompt = prompt.c_str();

        std::string negPrompt = options.value("negative_prompt", "");
        racOptions.negative_prompt = negPrompt.c_str();

        racOptions.width = options.value("width", 512);
        racOptions.height = options.value("height", 512);
        racOptions.steps = options.value("steps", 28);
        racOptions.guidance_scale = options.value("guidance_scale", 7.5f);
        racOptions.seed = options.value("seed", -1);
        racOptions.scheduler = options.value("scheduler", 0);
        racOptions.mode = 2; // Inpainting

        rac_diffusion_result_t racResult = {};
        rac_result_t result = rac_diffusion_component_generate(
            handle_,
            &racOptions,
            inputImage.data(), inputImage.size(),
            maskImage.data(), maskImage.size(),
            &racResult
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Inpainting failed");
        }

        json resultJson;
        resultJson["width"] = racResult.width;
        resultJson["height"] = racResult.height;
        resultJson["seed_used"] = racResult.seed_used;
        resultJson["generation_time_ms"] = racResult.generation_time_ms;

        if (racResult.image_data && racResult.image_data_size > 0) {
            resultJson["image_base64"] = DiffusionBridge::encodeBase64(
                racResult.image_data,
                racResult.image_data_size
            );
        }

        rac_diffusion_result_free(&racResult);
        return resultJson.dump();
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereDiffusion::cancelGeneration() {
    return Promise<void>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (handle_) {
            rac_diffusion_component_cancel(handle_);
        }
    });
}

// MARK: - Progress Streaming

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::generateWithProgress(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(double progress, int step, int totalSteps)>& callback) {

    return Promise<std::string>::async([this, prompt, optionsJson, callback]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureModelLoaded();

        json options = json::parse(optionsJson);

        rac_diffusion_options_t racOptions = {};
        racOptions.prompt = prompt.c_str();

        std::string negPrompt = options.value("negative_prompt", "");
        racOptions.negative_prompt = negPrompt.c_str();

        racOptions.width = options.value("width", 512);
        racOptions.height = options.value("height", 512);
        racOptions.steps = options.value("steps", 28);
        racOptions.guidance_scale = options.value("guidance_scale", 7.5f);
        racOptions.seed = options.value("seed", -1);
        racOptions.scheduler = options.value("scheduler", 0);
        racOptions.mode = options.value("mode", 0);
        racOptions.report_intermediate_images = RAC_FALSE;
        racOptions.progress_stride = options.value("progress_stride", 1);

        // Set up progress callback
        struct CallbackContext {
            std::function<void(double, int, int)> callback;
            int totalSteps;
        };

        CallbackContext ctx{callback, racOptions.steps};

        rac_diffusion_progress_callback_t progressCallback = [](
            const rac_diffusion_progress_t* progress,
            void* user_data) {
            auto* ctx = static_cast<CallbackContext*>(user_data);
            if (ctx && ctx->callback) {
                ctx->callback(
                    progress->progress,
                    progress->current_step,
                    progress->total_steps
                );
            }
        };

        rac_diffusion_result_t racResult = {};
        rac_result_t result = rac_diffusion_component_generate_with_progress(
            handle_,
            &racOptions,
            nullptr, 0,
            nullptr, 0,
            progressCallback,
            &ctx,
            &racResult
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Image generation failed");
        }

        json resultJson;
        resultJson["width"] = racResult.width;
        resultJson["height"] = racResult.height;
        resultJson["seed_used"] = racResult.seed_used;
        resultJson["generation_time_ms"] = racResult.generation_time_ms;

        if (racResult.image_data && racResult.image_data_size > 0) {
            resultJson["image_base64"] = DiffusionBridge::encodeBase64(
                racResult.image_data,
                racResult.image_data_size
            );
        }

        rac_diffusion_result_free(&racResult);
        return resultJson.dump();
    });
}

// MARK: - Model Info

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::getModelInfo() {
    return Promise<std::string>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        json info;
        info["is_loaded"] = isModelLoaded();
        info["model_id"] = currentModelId_;

        if (handle_) {
            rac_diffusion_model_info_t modelInfo = {};
            if (rac_diffusion_component_get_info(handle_, &modelInfo) == RAC_SUCCESS) {
                info["model_variant"] = modelInfo.model_variant;
                info["backend"] = modelInfo.backend_name ? modelInfo.backend_name : "unknown";
                info["default_width"] = modelInfo.default_width;
                info["default_height"] = modelInfo.default_height;
                info["default_steps"] = modelInfo.default_steps;
            }
        }

        return info.dump();
    });
}

// MARK: - Utilities

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::encodeImageToBase64(
    const std::string& imagePath) {

    return Promise<std::string>::async([imagePath]() {
        return DiffusionBridge::encodeFileToBase64(imagePath);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::saveImageToFile(
    const std::string& imageBase64,
    const std::string& outputPath) {

    return Promise<bool>::async([imageBase64, outputPath]() {
        return DiffusionBridge::saveBase64ToFile(imageBase64, outputPath);
    });
}

// MARK: - Private Helpers

void HybridRunAnywhereDiffusion::ensureRegistered() {
    if (!isRegistered_) {
        throw std::runtime_error("Diffusion backend not registered. Call registerBackend() first.");
    }
}

void HybridRunAnywhereDiffusion::ensureModelLoaded() {
    ensureRegistered();
    if (!handle_ || !isModelLoaded()) {
        throw std::runtime_error("No diffusion model loaded. Call loadModel() first.");
    }
}

std::string HybridRunAnywhereDiffusion::getLastError() {
    return lastError_;
}

} // namespace margelo::nitro::runanywhere::diffusion
