/**
 * @file VoiceAgentBridge.cpp
 * @brief Voice Agent bridge implementation
 */

#include "VoiceAgentBridge.hpp"
#include "LLMBridge.hpp"
#include "STTBridge.hpp"
#include "TTSBridge.hpp"

#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "VoiceAgentBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

VoiceAgentBridge& VoiceAgentBridge::shared() {
    static VoiceAgentBridge instance;
    return instance;
}

VoiceAgentBridge::VoiceAgentBridge() {
    LOGI("VoiceAgentBridge created");
}

VoiceAgentBridge::~VoiceAgentBridge() {
    cleanup();
}

rac_result_t VoiceAgentBridge::initialize(const VoiceAgentConfig& config) {
    LOGI("Initializing voice agent with config");
    config_ = config;

#ifdef HAS_RACOMMONS
    // Create voice agent handle if API available
    rac_voice_agent_config_t cConfig = {};
    cConfig.vad_config.sample_rate = config.vadSampleRate;
    cConfig.vad_config.frame_length = config.vadFrameLength;
    cConfig.vad_config.energy_threshold = config.vadEnergyThreshold;

    if (!config.sttModelId.empty()) {
        cConfig.stt_config.model_id = config.sttModelId.c_str();
    }
    if (!config.llmModelId.empty()) {
        cConfig.llm_config.model_id = config.llmModelId.c_str();
    }
    if (!config.ttsVoiceId.empty()) {
        cConfig.tts_config.voice_id = config.ttsVoiceId.c_str();
    }

    rac_result_t result = rac_voice_agent_create(&handle_);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to create voice agent: %d", result);
        return result;
    }

    result = rac_voice_agent_initialize(handle_, &cConfig);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to initialize voice agent: %d", result);
        return result;
    }

    initialized_ = true;
    LOGI("Voice agent initialized successfully");
    return RAC_SUCCESS;
#else
    // Fallback: Check if individual components are loaded
    initialized_ = LLMBridge::shared().isLoaded() &&
                   STTBridge::shared().isLoaded() &&
                   TTSBridge::shared().isLoaded();
    return initialized_ ? RAC_SUCCESS : -1;
#endif
}

rac_result_t VoiceAgentBridge::initializeWithLoadedModels() {
    LOGI("Initializing voice agent with loaded models");

#ifdef HAS_RACOMMONS
    if (!handle_) {
        rac_result_t result = rac_voice_agent_create(&handle_);
        if (result != RAC_SUCCESS) {
            return result;
        }
    }

    rac_result_t result = rac_voice_agent_initialize_with_loaded_models(handle_);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to initialize with loaded models: %d", result);
        return result;
    }

    initialized_ = true;
    return RAC_SUCCESS;
#else
    // Fallback: Just check if components are loaded
    initialized_ = LLMBridge::shared().isLoaded() &&
                   STTBridge::shared().isLoaded() &&
                   TTSBridge::shared().isLoaded();
    return initialized_ ? RAC_SUCCESS : -1;
#endif
}

bool VoiceAgentBridge::isReady() const {
#ifdef HAS_RACOMMONS
    if (!handle_) return false;
    rac_bool_t ready = RAC_FALSE;
    rac_voice_agent_is_ready(handle_, &ready);
    return ready == RAC_TRUE;
#else
    return initialized_;
#endif
}

VoiceAgentComponentStates VoiceAgentBridge::getComponentStates() const {
    VoiceAgentComponentStates states;

    // Check STT
    if (STTBridge::shared().isLoaded()) {
        states.stt = ComponentState::Loaded;
        states.sttModelId = "loaded";  // TODO: Get actual model ID
    }

    // Check LLM
    if (LLMBridge::shared().isLoaded()) {
        states.llm = ComponentState::Loaded;
        states.llmModelId = LLMBridge::shared().currentModelId();
    }

    // Check TTS
    if (TTSBridge::shared().isLoaded()) {
        states.tts = ComponentState::Loaded;
        states.ttsVoiceId = "loaded";  // TODO: Get actual voice ID
    }

    return states;
}

VoiceAgentResult VoiceAgentBridge::processVoiceTurn(const void* audioData, size_t audioSize) {
    VoiceAgentResult result;

    if (!isReady()) {
        LOGE("Voice agent not ready");
        return result;
    }

#ifdef HAS_RACOMMONS
    rac_voice_agent_result_t cResult = {};
    rac_result_t ret = rac_voice_agent_process_voice_turn(
        handle_,
        audioData,
        audioSize,
        &cResult
    );

    if (ret == RAC_SUCCESS) {
        result.speechDetected = cResult.speech_detected == RAC_TRUE;
        if (cResult.transcription) {
            result.transcription = std::string(cResult.transcription);
        }
        if (cResult.response) {
            result.response = std::string(cResult.response);
        }
        if (cResult.synthesized_audio && cResult.synthesized_audio_size > 0) {
            result.synthesizedAudio.assign(
                static_cast<const uint8_t*>(cResult.synthesized_audio),
                static_cast<const uint8_t*>(cResult.synthesized_audio) + cResult.synthesized_audio_size
            );
        }
        rac_voice_agent_result_free(&cResult);
    }
#else
    // Fallback: Process through individual components
    // 1. STT
    STTOptions sttOpts;
    sttOpts.language = "en";
    auto sttResult = STTBridge::shared().transcribe(audioData, audioSize, sttOpts);
    result.transcription = sttResult.text;
    result.speechDetected = !result.transcription.empty();

    // 2. LLM
    if (result.speechDetected) {
        LLMOptions llmOpts;
        llmOpts.maxTokens = 256;
        auto llmResult = LLMBridge::shared().generate(result.transcription, llmOpts);
        result.response = llmResult.text;

        // 3. TTS
        if (!result.response.empty()) {
            TTSOptions ttsOpts;
            auto ttsResult = TTSBridge::shared().synthesize(result.response, ttsOpts);
            // Convert float audio to bytes
            result.synthesizedAudio.resize(ttsResult.audioData.size() * sizeof(float));
            memcpy(result.synthesizedAudio.data(), ttsResult.audioData.data(),
                   result.synthesizedAudio.size());
            result.sampleRate = ttsResult.sampleRate;
        }
    }
#endif

    return result;
}

std::string VoiceAgentBridge::transcribe(const void* audioData, size_t audioSize) {
#ifdef HAS_RACOMMONS
    if (!handle_) return "";

    char* transcription = nullptr;
    rac_result_t result = rac_voice_agent_transcribe(
        handle_,
        audioData,
        audioSize,
        &transcription
    );

    if (result == RAC_SUCCESS && transcription) {
        std::string text(transcription);
        free(transcription);
        return text;
    }
    return "";
#else
    STTOptions opts;
    opts.language = "en";
    return STTBridge::shared().transcribe(audioData, audioSize, opts).text;
#endif
}

std::string VoiceAgentBridge::generateResponse(const std::string& prompt) {
#ifdef HAS_RACOMMONS
    if (!handle_) return "";

    char* response = nullptr;
    rac_result_t result = rac_voice_agent_generate_response(
        handle_,
        prompt.c_str(),
        &response
    );

    if (result == RAC_SUCCESS && response) {
        std::string text(response);
        free(response);
        return text;
    }
    return "";
#else
    LLMOptions opts;
    opts.maxTokens = 256;
    return LLMBridge::shared().generate(prompt, opts).text;
#endif
}

std::vector<uint8_t> VoiceAgentBridge::synthesizeSpeech(const std::string& text) {
#ifdef HAS_RACOMMONS
    if (!handle_) return {};

    void* audioData = nullptr;
    size_t audioSize = 0;
    rac_result_t result = rac_voice_agent_synthesize_speech(
        handle_,
        text.c_str(),
        &audioData,
        &audioSize
    );

    if (result == RAC_SUCCESS && audioData && audioSize > 0) {
        std::vector<uint8_t> audio(
            static_cast<uint8_t*>(audioData),
            static_cast<uint8_t*>(audioData) + audioSize
        );
        free(audioData);
        return audio;
    }
    return {};
#else
    TTSOptions opts;
    auto ttsResult = TTSBridge::shared().synthesize(text, opts);
    std::vector<uint8_t> audio(ttsResult.audioData.size() * sizeof(float));
    memcpy(audio.data(), ttsResult.audioData.data(), audio.size());
    return audio;
#endif
}

void VoiceAgentBridge::cleanup() {
#ifdef HAS_RACOMMONS
    if (handle_) {
        rac_voice_agent_destroy(handle_);
        handle_ = nullptr;
    }
#endif
    initialized_ = false;
    LOGI("Voice agent cleaned up");
}

} // namespace bridges
} // namespace runanywhere
