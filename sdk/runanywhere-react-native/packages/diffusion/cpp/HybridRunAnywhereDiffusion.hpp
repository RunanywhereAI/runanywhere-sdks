#pragma once

#include "HybridRunAnywhereDiffusionSpec.hpp"
#include <mutex>
#include <string>
#include <optional>

namespace margelo::nitro::runanywhere::diffusion {

/**
 * HybridRunAnywhereDiffusion - C++ implementation of the Diffusion HybridObject
 *
 * This class implements the Nitro spec interface and bridges to the C API
 * defined in rac_diffusion_onnx.h and rac_backend_diffusion.h
 */
class HybridRunAnywhereDiffusion : public HybridRunAnywhereDiffusionSpec {
public:
    HybridRunAnywhereDiffusion();
    ~HybridRunAnywhereDiffusion();

    // Backend Registration
    std::shared_ptr<Promise<bool>> registerBackend() override;

    // Configuration
    std::shared_ptr<Promise<bool>> configure(const std::string& configJson) override;

    // Model Management
    std::shared_ptr<Promise<bool>> loadModel(
        const std::string& path,
        const std::string& modelId,
        const std::optional<std::string>& modelName,
        const std::optional<std::string>& configJson) override;

    std::shared_ptr<Promise<void>> unloadModel() override;
    bool isModelLoaded() override;
    std::optional<std::string> currentModelId() override;

    // Image Generation
    std::shared_ptr<Promise<std::string>> generateImage(
        const std::string& prompt,
        const std::string& optionsJson) override;

    std::shared_ptr<Promise<std::string>> imageToImage(
        const std::string& prompt,
        const std::string& inputImageBase64,
        const std::string& optionsJson) override;

    std::shared_ptr<Promise<std::string>> inpaint(
        const std::string& prompt,
        const std::string& inputImageBase64,
        const std::string& maskImageBase64,
        const std::string& optionsJson) override;

    std::shared_ptr<Promise<void>> cancelGeneration() override;

    // Progress (streaming callback pattern)
    std::shared_ptr<Promise<std::string>> generateWithProgress(
        const std::string& prompt,
        const std::string& optionsJson,
        const std::function<void(double progress, int step, int totalSteps)>& callback) override;

    // Model Info
    std::shared_ptr<Promise<std::string>> getModelInfo() override;

    // Utilities
    std::shared_ptr<Promise<std::string>> encodeImageToBase64(const std::string& imagePath) override;
    std::shared_ptr<Promise<bool>> saveImageToFile(
        const std::string& imageBase64,
        const std::string& outputPath) override;

private:
    std::mutex mutex_;
    void* handle_ = nullptr;  // rac_handle_t
    std::string currentModelId_;
    std::string lastError_;
    bool isRegistered_ = false;

    // Helper methods
    void ensureRegistered();
    void ensureModelLoaded();
    std::string getLastError();
};

} // namespace margelo::nitro::runanywhere::diffusion
