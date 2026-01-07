/**
 * @file LLMBridge.hpp
 * @brief LLM capability bridge for React Native
 *
 * Matches Swift's CppBridge+LLM.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Text generation (sync and streaming)
 * - Cancellation support
 *
 * Aligned with rac_llm_component.h and rac_llm_types.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>

// RACommons LLM headers - REQUIRED (flat include paths)
#include "rac_llm_component.h"
#include "rac_llm_types.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief LLM streaming callbacks
 */
struct LLMStreamCallbacks {
    std::function<bool(const std::string&)> onToken;
    std::function<void(const std::string&, int, double)> onComplete;
    std::function<void(int, const std::string&)> onError;
};

/**
 * @brief LLM generation options
 */
struct LLMOptions {
    int maxTokens = 512;
    double temperature = 0.7;
    double topP = 0.9;
    int topK = 40;
    std::string systemPrompt;
    std::string stopSequence;
};

/**
 * @brief LLM generation result
 */
struct LLMResult {
    std::string text;
    int tokenCount = 0;
    double durationMs = 0.0;
    bool cancelled = false;
};

/**
 * @brief LLM capability bridge singleton
 *
 * Matches CppBridge+LLM.swift API.
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class LLMBridge {
public:
    static LLMBridge& shared();

    // Lifecycle
    bool isLoaded() const;
    std::string currentModelId() const;
    /**
     * Load an LLM model
     * @param modelPath Path to the model file (.gguf)
     * @param modelId Model identifier for telemetry (e.g., "smollm2-360m-q8_0")
     * @param modelName Human-readable model name (e.g., "SmolLM2 360M Q8_0")
     * @return RAC_SUCCESS or error code
     */
    rac_result_t loadModel(const std::string& modelPath,
                           const std::string& modelId = "",
                           const std::string& modelName = "");
    rac_result_t unload();
    void cleanup();
    void cancel();
    void destroy();

    // Generation
    LLMResult generate(const std::string& prompt, const LLMOptions& options);
    void generateStream(const std::string& prompt, const LLMOptions& options,
                       const LLMStreamCallbacks& callbacks);

    // State
    rac_lifecycle_state_t getState() const;

private:
    LLMBridge();
    ~LLMBridge();

    // Disable copy/move
    LLMBridge(const LLMBridge&) = delete;
    LLMBridge& operator=(const LLMBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    std::string loadedModelId_;
    bool cancellationRequested_ = false;
};

} // namespace bridges
} // namespace runanywhere
