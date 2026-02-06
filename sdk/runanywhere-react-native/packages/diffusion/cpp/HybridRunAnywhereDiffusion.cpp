#include "HybridRunAnywhereDiffusion.hpp"
#include "bridges/DiffusionBridge.hpp"

#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <vector>

// C API headers
extern "C" {
#include "rac/backends/rac_vad_onnx.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_component.h"
}

using json = nlohmann::json;

namespace margelo::nitro::runanywhere::diffusion {

namespace {

std::string buildProgressJson(double progress, int step, int totalSteps, const std::string& stage) {
    json result;
    result["progress"] = progress;
    result["currentStep"] = step;
    result["totalSteps"] = totalSteps;
    result["stage"] = stage;
    return result.dump();
}

std::string buildSchedulerListJson() {
    json schedulers = json::array();
    schedulers.push_back("dpm++_2m_karras");
    schedulers.push_back("dpm++_2m");
    schedulers.push_back("dpm++_2m_sde");
    schedulers.push_back("ddim");
    schedulers.push_back("euler");
    schedulers.push_back("euler_a");
    schedulers.push_back("pndm");
    schedulers.push_back("lms");
    return schedulers.dump();
}

}  // namespace

HybridRunAnywhereDiffusion::HybridRunAnywhereDiffusion() : HybridObject(TAG) {}

HybridRunAnywhereDiffusion::~HybridRunAnywhereDiffusion() {
    if (handle_) {
        rac_diffusion_component_destroy(handle_);
        handle_ = nullptr;
    }
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::registerBackend() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        if (isRegistered_) {
            return true;
        }

        rac_result_t result = rac_backend_onnx_register();
        if (result == RAC_SUCCESS || result == RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            isRegistered_ = true;
            return true;
        }

        setLastError("Failed to register diffusion backend: " + std::to_string(result));
        throw std::runtime_error(lastError_);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::unregisterBackend() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        if (!isRegistered_) {
            return true;
        }

        rac_result_t result = rac_backend_onnx_unregister();
        isRegistered_ = false;
        if (handle_) {
            rac_diffusion_component_destroy(handle_);
            handle_ = nullptr;
            currentModelId_.clear();
            isGenerating_ = false;
        }
        if (result != RAC_SUCCESS) {
            setLastError("Failed to unregister diffusion backend: " + std::to_string(result));
            throw std::runtime_error(lastError_);
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::isBackendRegistered() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        return isRegistered_;
    });
}

// ============================================================================
// Configuration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::configure(const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureRegisteredLocked();

        if (!handle_) {
            rac_result_t createResult = rac_diffusion_component_create(&handle_);
            if (createResult != RAC_SUCCESS || !handle_) {
                setLastError("Failed to create diffusion component");
                throw std::runtime_error(lastError_);
            }
        }

        rac_result_t result =
            rac_diffusion_component_configure_json(handle_, configJson.c_str());
        if (result != RAC_SUCCESS) {
            setLastError("Failed to configure diffusion component: " + std::to_string(result));
            throw std::runtime_error(lastError_);
        }

        return true;
    });
}

// ============================================================================
// Model Management
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::loadModel(
    const std::string& path,
    const std::string& modelId,
    const std::optional<std::string>& modelName,
    const std::optional<std::string>& configJson) {

    return Promise<bool>::async([this, path, modelId, modelName, configJson]() {
        std::lock_guard<std::mutex> lock(mutex_);
        ensureRegisteredLocked();

        if (isGenerating_) {
            setLastError("Cannot load model while generation is in progress");
            throw std::runtime_error(lastError_);
        }

        if (!handle_) {
            rac_result_t createResult = rac_diffusion_component_create(&handle_);
            if (createResult != RAC_SUCCESS || !handle_) {
                setLastError("Failed to create diffusion component");
                throw std::runtime_error(lastError_);
            }
        }

        if (configJson.has_value()) {
            rac_result_t cfgResult =
                rac_diffusion_component_configure_json(handle_, configJson->c_str());
            if (cfgResult != RAC_SUCCESS) {
                setLastError("Failed to configure diffusion component: " +
                             std::to_string(cfgResult));
                throw std::runtime_error(lastError_);
            }
        }

        const char* name = modelName.has_value() ? modelName->c_str() : nullptr;
        rac_result_t result = rac_diffusion_component_load_model(
            handle_, path.c_str(), modelId.c_str(), name);

        if (result != RAC_SUCCESS) {
            setLastError("Failed to load diffusion model: " + std::to_string(result));
            throw std::runtime_error(lastError_);
        }

        currentModelId_ = modelId;
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::isModelLoaded() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!handle_) {
            return false;
        }
        return rac_diffusion_component_is_loaded(handle_) == RAC_TRUE;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::unloadModel() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);

        if (!handle_) {
            return true;
        }
        if (isGenerating_) {
            setLastError("Cannot unload model while generation is in progress");
            return false;
        }

        rac_result_t result = rac_diffusion_component_unload(handle_);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to unload diffusion model: " + std::to_string(result));
            return false;
        }

        currentModelId_.clear();
        return true;
    });
}

std::shared_ptr<Promise<std::optional<std::string>>> HybridRunAnywhereDiffusion::getLoadedModelId() {
    return Promise<std::optional<std::string>>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!handle_) {
            return std::optional<std::string>();
        }
        const char* modelId = rac_diffusion_component_get_model_id(handle_);
        if (!modelId || modelId[0] == '\0') {
            return std::optional<std::string>();
        }
        return std::optional<std::string>(std::string(modelId));
    });
}

// ============================================================================
// Image Generation
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::generateImage(
    const std::string& prompt,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, optionsJson]() {
        rac_handle_t localHandle = nullptr;
        int steps = 0;

        {
            std::lock_guard<std::mutex> lock(mutex_);
            ensureModelLoadedLocked();
            if (isGenerating_) {
                setLastError("Generation already in progress");
                throw std::runtime_error(lastError_);
            }
            isGenerating_ = true;
            localHandle = handle_;
        }

        std::string mergedOptions;
        try {
            json options = json::parse(optionsJson);
            options["prompt"] = prompt;
            if (!options.contains("mode")) {
                options["mode"] = "txt2img";
            }
            steps = options.value("steps", 0);
            mergedOptions = options.dump();
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError(std::string("Invalid options JSON: ") + e.what());
            throw std::runtime_error(lastError_);
        }

        updateProgress(0.0, 0, steps, "starting");

        char* out_json = nullptr;
        rac_result_t result = rac_diffusion_component_generate_json(
            localHandle,
            mergedOptions.c_str(),
            nullptr,
            0,
            nullptr,
            0,
            &out_json);

        {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
        }

        if (result != RAC_SUCCESS || out_json == nullptr) {
            updateProgress(0.0, 0, steps, "error");
            if (out_json) {
                rac_free(out_json);
            }
            std::string errorMessage = "Image generation failed: " + std::to_string(result);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                setLastError(errorMessage);
            }
            throw std::runtime_error(errorMessage);
        }

        updateProgress(1.0, steps, steps, "complete");
        std::string resultJson(out_json);
        rac_free(out_json);
        return resultJson;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::imageToImage(
    const std::string& prompt,
    const std::string& inputImageBase64,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, inputImageBase64, optionsJson]() {
        rac_handle_t localHandle = nullptr;
        int steps = 0;

        {
            std::lock_guard<std::mutex> lock(mutex_);
            ensureModelLoadedLocked();
            if (isGenerating_) {
                setLastError("Generation already in progress");
                throw std::runtime_error(lastError_);
            }
            isGenerating_ = true;
            localHandle = handle_;
        }

        std::vector<uint8_t> inputImage = DiffusionBridge::decodeBase64(inputImageBase64);
        if (inputImage.empty()) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError("Input image is required for image-to-image generation");
            throw std::runtime_error(lastError_);
        }

        std::string mergedOptions;
        try {
            json options = json::parse(optionsJson);
            options["prompt"] = prompt;
            options["mode"] = "img2img";
            steps = options.value("steps", 0);
            mergedOptions = options.dump();
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError(std::string("Invalid options JSON: ") + e.what());
            throw std::runtime_error(lastError_);
        }

        updateProgress(0.0, 0, steps, "starting");

        char* out_json = nullptr;
        rac_result_t result = rac_diffusion_component_generate_json(
            localHandle,
            mergedOptions.c_str(),
            inputImage.empty() ? nullptr : inputImage.data(),
            inputImage.size(),
            nullptr,
            0,
            &out_json);

        {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
        }

        if (result != RAC_SUCCESS || out_json == nullptr) {
            updateProgress(0.0, 0, steps, "error");
            if (out_json) {
                rac_free(out_json);
            }
            std::string errorMessage =
                "Image-to-image generation failed: " + std::to_string(result);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                setLastError(errorMessage);
            }
            throw std::runtime_error(errorMessage);
        }

        updateProgress(1.0, steps, steps, "complete");
        std::string resultJson(out_json);
        rac_free(out_json);
        return resultJson;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::inpaint(
    const std::string& prompt,
    const std::string& inputImageBase64,
    const std::string& maskImageBase64,
    const std::string& optionsJson) {

    return Promise<std::string>::async([this, prompt, inputImageBase64, maskImageBase64, optionsJson]() {
        rac_handle_t localHandle = nullptr;
        int steps = 0;

        {
            std::lock_guard<std::mutex> lock(mutex_);
            ensureModelLoadedLocked();
            if (isGenerating_) {
                setLastError("Generation already in progress");
                throw std::runtime_error(lastError_);
            }
            isGenerating_ = true;
            localHandle = handle_;
        }

        std::vector<uint8_t> inputImage = DiffusionBridge::decodeBase64(inputImageBase64);
        std::vector<uint8_t> maskImage = DiffusionBridge::decodeBase64(maskImageBase64);
        if (inputImage.empty()) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError("Input image is required for inpainting");
            throw std::runtime_error(lastError_);
        }
        if (maskImage.empty()) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError("Mask image is required for inpainting");
            throw std::runtime_error(lastError_);
        }

        std::string mergedOptions;
        try {
            json options = json::parse(optionsJson);
            options["prompt"] = prompt;
            options["mode"] = "inpainting";
            steps = options.value("steps", 0);
            mergedOptions = options.dump();
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
            setLastError(std::string("Invalid options JSON: ") + e.what());
            throw std::runtime_error(lastError_);
        }

        updateProgress(0.0, 0, steps, "starting");

        char* out_json = nullptr;
        rac_result_t result = rac_diffusion_component_generate_json(
            localHandle,
            mergedOptions.c_str(),
            inputImage.empty() ? nullptr : inputImage.data(),
            inputImage.size(),
            maskImage.empty() ? nullptr : maskImage.data(),
            maskImage.size(),
            &out_json);

        {
            std::lock_guard<std::mutex> lock(mutex_);
            isGenerating_ = false;
        }

        if (result != RAC_SUCCESS || out_json == nullptr) {
            updateProgress(0.0, 0, steps, "error");
            if (out_json) {
                rac_free(out_json);
            }
            std::string errorMessage = "Inpainting failed: " + std::to_string(result);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                setLastError(errorMessage);
            }
            throw std::runtime_error(errorMessage);
        }

        updateProgress(1.0, steps, steps, "complete");
        std::string resultJson(out_json);
        rac_free(out_json);
        return resultJson;
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

// ============================================================================
// Progress & State
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereDiffusion::isGenerating() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        return isGenerating_;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::getProgress() {
    return Promise<std::string>::async([this]() {
        std::lock_guard<std::mutex> lock(progressMutex_);
        return buildProgressJson(lastProgress_, lastProgressStep_, lastTotalSteps_, lastProgressStage_);
    });
}

// ============================================================================
// Model Information
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::getSupportedSchedulers() {
    return Promise<std::string>::async([]() {
        return buildSchedulerListJson();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::getModelCapabilities() {
    return Promise<std::string>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        json result;

        if (!handle_) {
            result["is_ready"] = false;
            return result.dump();
        }

        rac_diffusion_info_t info = {};
        rac_result_t status = rac_diffusion_component_get_info(handle_, &info);
        if (status != RAC_SUCCESS) {
            result["is_ready"] = false;
            result["error"] = status;
            return result.dump();
        }

        result["is_ready"] = info.is_ready == RAC_TRUE;
        result["current_model"] = info.current_model ? info.current_model : "";
        result["model_variant"] = static_cast<int>(info.model_variant);
        result["supports_txt2img"] = info.supports_text_to_image == RAC_TRUE;
        result["supports_img2img"] = info.supports_image_to_image == RAC_TRUE;
        result["supports_inpainting"] = info.supports_inpainting == RAC_TRUE;
        result["safety_checker_enabled"] = info.safety_checker_enabled == RAC_TRUE;
        result["max_width"] = info.max_width;
        result["max_height"] = info.max_height;

        return result.dump();
    });
}

// ============================================================================
// Utilities
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereDiffusion::getLastError() {
    return Promise<std::string>::async([this]() {
        std::lock_guard<std::mutex> lock(mutex_);
        return lastError_;
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereDiffusion::getMemoryUsage() {
    return Promise<double>::async([]() {
        return 0.0;
    });
}

// ============================================================================
// Private Helpers
// ============================================================================

void HybridRunAnywhereDiffusion::ensureRegisteredLocked() {
    if (!isRegistered_) {
        setLastError("Diffusion backend not registered. Call registerBackend() first.");
        throw std::runtime_error(lastError_);
    }
}

void HybridRunAnywhereDiffusion::ensureModelLoadedLocked() {
    ensureRegisteredLocked();
    if (!handle_ || rac_diffusion_component_is_loaded(handle_) != RAC_TRUE) {
        setLastError("No diffusion model loaded. Call loadModel() first.");
        throw std::runtime_error(lastError_);
    }
}

void HybridRunAnywhereDiffusion::setLastError(const std::string& error) {
    lastError_ = error;
}

void HybridRunAnywhereDiffusion::updateProgress(double progress, int step, int totalSteps,
                                                const std::string& stage) {
    std::lock_guard<std::mutex> lock(progressMutex_);
    lastProgress_ = progress;
    lastProgressStep_ = step;
    lastTotalSteps_ = totalSteps;
    lastProgressStage_ = stage;
}

} // namespace margelo::nitro::runanywhere::diffusion
