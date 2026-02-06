#pragma once

// Include the generated spec header (created by nitrogen)
#if __has_include(<NitroModules/HybridObject.hpp>)
#include "HybridRunAnywhereDiffusionSpec.hpp"
#else
// Fallback include path during development
#include "../nitrogen/generated/shared/c++/HybridRunAnywhereDiffusionSpec.hpp"
#endif

#include <mutex>
#include <optional>
#include <string>

namespace margelo::nitro::runanywhere::diffusion {

/**
 * HybridRunAnywhereDiffusion - C++ implementation of the Diffusion HybridObject
 *
 * Implements the RunAnywhereDiffusion interface defined in RunAnywhereDiffusion.nitro.ts
 * Delegates to the runanywhere-commons C diffusion component.
 */
class HybridRunAnywhereDiffusion : public HybridRunAnywhereDiffusionSpec {
public:
    HybridRunAnywhereDiffusion();
    ~HybridRunAnywhereDiffusion();

    // ============================================================================
    // Backend Registration
    // ============================================================================
    std::shared_ptr<Promise<bool>> registerBackend() override;
    std::shared_ptr<Promise<bool>> unregisterBackend() override;
    std::shared_ptr<Promise<bool>> isBackendRegistered() override;

    // ============================================================================
    // Configuration
    // ============================================================================
    std::shared_ptr<Promise<bool>> configure(const std::string& configJson) override;

    // ============================================================================
    // Model Management
    // ============================================================================
    std::shared_ptr<Promise<bool>> loadModel(
        const std::string& path,
        const std::string& modelId,
        const std::optional<std::string>& modelName,
        const std::optional<std::string>& configJson) override;

    std::shared_ptr<Promise<bool>> isModelLoaded() override;
    std::shared_ptr<Promise<bool>> unloadModel() override;
    std::shared_ptr<Promise<std::optional<std::string>>> getLoadedModelId() override;

    // ============================================================================
    // Image Generation
    // ============================================================================
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

    // ============================================================================
    // Progress & State
    // ============================================================================
    std::shared_ptr<Promise<bool>> isGenerating() override;
    std::shared_ptr<Promise<std::string>> getProgress() override;

    // ============================================================================
    // Model Information
    // ============================================================================
    std::shared_ptr<Promise<std::string>> getSupportedSchedulers() override;
    std::shared_ptr<Promise<std::string>> getModelCapabilities() override;

    // ============================================================================
    // Utilities
    // ============================================================================
    std::shared_ptr<Promise<std::string>> getLastError() override;
    std::shared_ptr<Promise<double>> getMemoryUsage() override;

private:
    std::mutex mutex_;
    std::mutex progressMutex_;
    void* handle_ = nullptr;  // rac_handle_t
    std::string currentModelId_;
    std::string lastError_;
    bool isRegistered_ = false;
    bool isGenerating_ = false;

    double lastProgress_ = 0.0;
    int lastProgressStep_ = 0;
    int lastTotalSteps_ = 0;
    std::string lastProgressStage_ = "idle";

    // Helper methods
    void ensureRegisteredLocked();
    void ensureModelLoadedLocked();
    void setLastError(const std::string& error);
    void updateProgress(double progress, int step, int totalSteps, const std::string& stage);
};

} // namespace margelo::nitro::runanywhere::diffusion
