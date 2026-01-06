/**
 * @file VoiceAgentBridge.hpp
 * @brief Voice Agent bridge for React Native
 *
 * Matches Swift's CppBridge+VoiceAgent.swift pattern, providing:
 * - Full voice pipeline orchestration (STT -> LLM -> TTS)
 * - Component state management
 * - Audio processing for voice turns
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#ifdef HAS_RACOMMONS
#include "rac/features/voice_agent/rac_voice_agent.h"
#else
typedef void* rac_handle_t;
typedef int rac_result_t;
typedef int rac_bool_t;
#define RAC_SUCCESS 0
#define RAC_TRUE 1
#define RAC_FALSE 0
#endif

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

    // Voice Processing
    VoiceAgentResult processVoiceTurn(const void* audioData, size_t audioSize);
    std::string transcribe(const void* audioData, size_t audioSize);
    std::string generateResponse(const std::string& prompt);
    std::vector<uint8_t> synthesizeSpeech(const std::string& text);

private:
    VoiceAgentBridge();
    ~VoiceAgentBridge();

    // Disable copy/move
    VoiceAgentBridge(const VoiceAgentBridge&) = delete;
    VoiceAgentBridge& operator=(const VoiceAgentBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    bool initialized_ = false;
    VoiceAgentConfig config_;
};

} // namespace bridges
} // namespace runanywhere
