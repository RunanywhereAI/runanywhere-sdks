/**
 * @file VoiceAgentBridge.hpp
 * @brief Voice Agent bridge for React Native
 *
 * Matches Swift's CppBridge+VoiceAgent.swift pattern, providing:
 * - Full voice pipeline orchestration (STT -> LLM -> TTS)
 * - Component state management
 * - Audio processing for voice turns
 *
 * Aligned with rac_voice_agent.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

// RACommons voice agent header - REQUIRED
#include "rac/features/voice_agent/rac_voice_agent.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief Voice agent result structure
 */
struct VoiceAgentResult {
    bool speechDetected = false;
    std::string transcription;
    std::string response;
    std::vector<uint8_t> synthesizedAudio;
    int sampleRate = 16000;
};

/**
 * @brief Component load state
 */
enum class ComponentState {
    NotLoaded,
    Loading,
    Loaded,
    Failed
};

/**
 * @brief Voice agent component states
 */
struct VoiceAgentComponentStates {
    ComponentState stt = ComponentState::NotLoaded;
    ComponentState llm = ComponentState::NotLoaded;
    ComponentState tts = ComponentState::NotLoaded;
    std::string sttModelId;
    std::string llmModelId;
    std::string ttsVoiceId;

    bool isFullyReady() const {
        return stt == ComponentState::Loaded &&
               llm == ComponentState::Loaded &&
               tts == ComponentState::Loaded;
    }
};

/**
 * @brief Voice agent configuration
 */
struct VoiceAgentConfig {
    std::string sttModelId;
    std::string llmModelId;
    std::string ttsVoiceId;
    int vadSampleRate = 16000;
    int vadFrameLength = 512;
    float vadEnergyThreshold = 0.1f;
};

/**
 * @brief Voice Agent bridge singleton
 *
 * Matches CppBridge+VoiceAgent.swift API.
 * Orchestrates the full voice pipeline using shared STT, LLM, and TTS components.
 *
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class VoiceAgentBridge {
public:
    static VoiceAgentBridge& shared();

    // Lifecycle
    rac_result_t initialize(const VoiceAgentConfig& config);
    rac_result_t initializeWithLoadedModels();
    bool isReady() const;
    VoiceAgentComponentStates getComponentStates() const;
    void cleanup();

    // Model Loading (for standalone voice agent)
    rac_result_t loadSTTModel(const std::string& modelPath,
                              const std::string& modelId = "",
                              const std::string& modelName = "");
    rac_result_t loadLLMModel(const std::string& modelPath,
                              const std::string& modelId = "",
                              const std::string& modelName = "");
    rac_result_t loadTTSVoice(const std::string& voicePath,
                              const std::string& voiceId = "",
                              const std::string& voiceName = "");

    // Voice Processing
    VoiceAgentResult processVoiceTurn(const void* audioData, size_t audioSize);
    std::string transcribe(const void* audioData, size_t audioSize);
    std::string generateResponse(const std::string& prompt);
    std::vector<uint8_t> synthesizeSpeech(const std::string& text);
    bool detectSpeech(const float* samples, size_t sampleCount);

private:
    VoiceAgentBridge();
    ~VoiceAgentBridge();

    // Disable copy/move
    VoiceAgentBridge(const VoiceAgentBridge&) = delete;
    VoiceAgentBridge& operator=(const VoiceAgentBridge&) = delete;

    rac_voice_agent_handle_t handle_ = nullptr;
    bool initialized_ = false;
    VoiceAgentConfig config_;
};

} // namespace bridges
} // namespace runanywhere
