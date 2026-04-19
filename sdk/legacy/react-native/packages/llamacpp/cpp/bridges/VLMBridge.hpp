/**
 * @file VLMBridge.hpp
 * @brief VLM capability bridge for React Native
 *
 * Matches Swift's CppBridge+VLM.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Image processing (sync and streaming)
 * - Cancellation support
 *
 * Aligned with rac_vlm_component.h and rac_vlm_types.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>

// RACommons VLM headers - REQUIRED (flat include paths)
#include "rac_vlm_component.h"
#include "rac_vlm_types.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief VLM streaming callbacks
 */
struct VLMStreamCallbacks {
    std::function<bool(const std::string&)> onToken;
    std::function<void(const rac_vlm_result_t*)> onComplete;
    std::function<void(int, const std::string&)> onError;
};

/**
 * @brief VLM generation options
 */
struct VLMOptions {
    int maxTokens = 2048;
    double temperature = 0.7;
    double topP = 0.9;
};

/**
 * @brief VLM image input structure
 * Wraps rac_vlm_image_t for C++ usage
 */
struct VLMImageInput {
    rac_vlm_image_format_t format;
    std::string file_path;
    const uint8_t* pixel_data = nullptr;
    std::string base64_data;
    uint32_t width = 0;
    uint32_t height = 0;
    size_t data_size = 0;
};

/**
 * @brief VLM generation result
 */
struct VLMResult {
    std::string text;
    int promptTokens = 0;
    int completionTokens = 0;
    double totalTimeMs = 0.0;
    double tokensPerSecond = 0.0;
};

/**
 * @brief VLM capability bridge singleton
 *
 * Matches CppBridge+VLM.swift API.
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class VLMBridge {
public:
    static VLMBridge& shared();

    // Lifecycle
    bool isLoaded() const;
    std::string currentModelId() const;
    /**
     * Load a VLM model
     * @param modelPath Path to the main model file (.gguf)
     * @param mmprojPath Path to the mmproj vision projector file (empty string for nullptr)
     * @param modelId Model identifier for telemetry (e.g., "smolvlm-500m-q8_0")
     * @param modelName Human-readable model name (e.g., "SmolVLM 500M Q8_0")
     */
    void loadModel(const std::string& modelPath,
                   const std::string& mmprojPath,
                   const std::string& modelId = "",
                   const std::string& modelName = "");
    void unload();
    void cleanup();
    void cancel();
    void destroy();

    // Generation
    VLMResult process(const VLMImageInput& image, const std::string& prompt,
                     const VLMOptions& options);
    void processStream(const VLMImageInput& image, const std::string& prompt,
                      const VLMOptions& options, const VLMStreamCallbacks& callbacks);

    // State
    rac_lifecycle_state_t getState() const;

private:
    VLMBridge();
    ~VLMBridge();

    // Disable copy/move
    VLMBridge(const VLMBridge&) = delete;
    VLMBridge& operator=(const VLMBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    std::string loadedModelId_;
    bool cancellationRequested_ = false;
};

} // namespace bridges
} // namespace runanywhere
