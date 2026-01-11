/**
 * @file VoiceAgentBridge.cpp
 * @brief Voice Agent bridge implementation
 *
 * Aligned with rac_voice_agent.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#include "VoiceAgentBridge.hpp"
#include "STTBridge.hpp"
#include "TTSBridge.hpp"
#include <stdexcept>
#include <cstring>

#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "VoiceAgentBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) printf("[VoiceAgentBridge] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[VoiceAgentBridge DEBUG] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[VoiceAgentBridge ERROR] "); printf(__VA_ARGS__); printf("\n")
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

    // Create voice agent handle using standalone API (owns its component handles)
    if (!handle_) {
        rac_result_t result = rac_voice_agent_create_standalone(&handle_);
        if (result != RAC_SUCCESS) {
            LOGE("Failed to create voice agent: %d", result);
            throw std::runtime_error("VoiceAgentBridge: Failed to create voice agent. Error: " + std::to_string(result));
        }
    }

    // Build configuration struct matching rac_voice_agent_config_t
    rac_voice_agent_config_t cConfig = RAC_VOICE_AGENT_CONFIG_DEFAULT;

    // VAD config
    cConfig.vad_config.sample_rate = config.vadSampleRate;
    cConfig.vad_config.frame_length = static_cast<float>(config.vadFrameLength) / 1000.0f; // Convert to seconds
    cConfig.vad_config.energy_threshold = config.vadEnergyThreshold;

    // STT config - model_path, model_id, model_name
    if (!config.sttModelId.empty()) {
        cConfig.stt_config.model_id = config.sttModelId.c_str();
        // model_path and model_name can be set if available
    }

    // LLM config - model_path, model_id, model_name
    if (!config.llmModelId.empty()) {
        cConfig.llm_config.model_id = config.llmModelId.c_str();
    }

    // TTS config - voice_path, voice_id, voice_name
    if (!config.ttsVoiceId.empty()) {
        cConfig.tts_config.voice_id = config.ttsVoiceId.c_str();
    }

    rac_result_t result = rac_voice_agent_initialize(handle_, &cConfig);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to initialize voice agent: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to initialize voice agent. Error: " + std::to_string(result));
    }

    initialized_ = true;
    LOGI("Voice agent initialized successfully");
    return RAC_SUCCESS;
}

rac_result_t VoiceAgentBridge::initializeWithLoadedModels() {
    LOGI("Initializing voice agent with loaded models");

    if (!handle_) {
        rac_result_t result = rac_voice_agent_create_standalone(&handle_);
        if (result != RAC_SUCCESS) {
            LOGE("Failed to create voice agent: %d", result);
            throw std::runtime_error("VoiceAgentBridge: Failed to create voice agent. Error: " + std::to_string(result));
        }
    }

    rac_result_t result = rac_voice_agent_initialize_with_loaded_models(handle_);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to initialize with loaded models: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to initialize with loaded models. Error: " + std::to_string(result));
    }

    initialized_ = true;
    return RAC_SUCCESS;
}

bool VoiceAgentBridge::isReady() const {
    if (!handle_) return false;

    rac_bool_t ready = RAC_FALSE;
    rac_result_t result = rac_voice_agent_is_ready(handle_, &ready);
    if (result != RAC_SUCCESS) {
        LOGE("Failed to check if voice agent is ready: %d", result);
        return false;
    }
    return ready == RAC_TRUE;
}

VoiceAgentComponentStates VoiceAgentBridge::getComponentStates() const {
    VoiceAgentComponentStates states;

    if (!handle_) {
        return states;
    }

    // Check STT
    rac_bool_t sttLoaded = RAC_FALSE;
    if (rac_voice_agent_is_stt_loaded(handle_, &sttLoaded) == RAC_SUCCESS && sttLoaded == RAC_TRUE) {
        states.stt = ComponentState::Loaded;
        const char* sttModelId = rac_voice_agent_get_stt_model_id(handle_);
        if (sttModelId) {
            states.sttModelId = sttModelId;
        }
    }

    // Check LLM
    rac_bool_t llmLoaded = RAC_FALSE;
    if (rac_voice_agent_is_llm_loaded(handle_, &llmLoaded) == RAC_SUCCESS && llmLoaded == RAC_TRUE) {
        states.llm = ComponentState::Loaded;
        const char* llmModelId = rac_voice_agent_get_llm_model_id(handle_);
        if (llmModelId) {
            states.llmModelId = llmModelId;
        }
    }

    // Check TTS
    rac_bool_t ttsLoaded = RAC_FALSE;
    if (rac_voice_agent_is_tts_loaded(handle_, &ttsLoaded) == RAC_SUCCESS && ttsLoaded == RAC_TRUE) {
        states.tts = ComponentState::Loaded;
        const char* ttsVoiceId = rac_voice_agent_get_tts_voice_id(handle_);
        if (ttsVoiceId) {
            states.ttsVoiceId = ttsVoiceId;
        }
    }

    return states;
}

rac_result_t VoiceAgentBridge::loadSTTModel(const std::string& modelPath,
                                            const std::string& modelId,
                                            const std::string& modelName) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    rac_result_t result = rac_voice_agent_load_stt_model(
        handle_,
        modelPath.c_str(),
        modelId.empty() ? modelPath.c_str() : modelId.c_str(),
        modelName.empty() ? modelId.c_str() : modelName.c_str()
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to load STT model: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to load STT model. Error: " + std::to_string(result));
    }

    LOGI("STT model loaded: %s", modelId.c_str());
    return result;
}

rac_result_t VoiceAgentBridge::loadLLMModel(const std::string& modelPath,
                                            const std::string& modelId,
                                            const std::string& modelName) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    rac_result_t result = rac_voice_agent_load_llm_model(
        handle_,
        modelPath.c_str(),
        modelId.empty() ? modelPath.c_str() : modelId.c_str(),
        modelName.empty() ? modelId.c_str() : modelName.c_str()
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to load LLM model: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to load LLM model. Error: " + std::to_string(result));
    }

    LOGI("LLM model loaded: %s", modelId.c_str());
    return result;
}

rac_result_t VoiceAgentBridge::loadTTSVoice(const std::string& voicePath,
                                            const std::string& voiceId,
                                            const std::string& voiceName) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    rac_result_t result = rac_voice_agent_load_tts_voice(
        handle_,
        voicePath.c_str(),
        voiceId.empty() ? voicePath.c_str() : voiceId.c_str(),
        voiceName.empty() ? voiceId.c_str() : voiceName.c_str()
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to load TTS voice: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to load TTS voice. Error: " + std::to_string(result));
    }

    LOGI("TTS voice loaded: %s", voiceId.c_str());
    return result;
}

VoiceAgentResult VoiceAgentBridge::processVoiceTurn(const void* audioData, size_t audioSize) {
    VoiceAgentResult result;

    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    if (!isReady()) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not ready. Ensure all models are loaded.");
    }

    rac_voice_agent_result_t cResult = {};
    rac_result_t ret = rac_voice_agent_process_voice_turn(
        handle_,
        audioData,
        audioSize,
        &cResult
    );

    if (ret != RAC_SUCCESS) {
        LOGE("Failed to process voice turn: %d", ret);
        throw std::runtime_error("VoiceAgentBridge: Failed to process voice turn. Error: " + std::to_string(ret));
    }

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

    // Free the C result
    rac_voice_agent_result_free(&cResult);

    return result;
}

std::string VoiceAgentBridge::transcribe(const void* audioData, size_t audioSize) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    char* transcription = nullptr;
    rac_result_t result = rac_voice_agent_transcribe(
        handle_,
        audioData,
        audioSize,
        &transcription
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to transcribe: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to transcribe audio. Error: " + std::to_string(result));
    }

    std::string text;
    if (transcription) {
        text = transcription;
        free(transcription);
    }
    return text;
}

std::string VoiceAgentBridge::generateResponse(const std::string& prompt) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    char* response = nullptr;
    rac_result_t result = rac_voice_agent_generate_response(
        handle_,
        prompt.c_str(),
        &response
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to generate response: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to generate response. Error: " + std::to_string(result));
    }

    std::string text;
    if (response) {
        text = response;
        free(response);
    }
    return text;
}

std::vector<uint8_t> VoiceAgentBridge::synthesizeSpeech(const std::string& text) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    void* audioData = nullptr;
    size_t audioSize = 0;
    rac_result_t result = rac_voice_agent_synthesize_speech(
        handle_,
        text.c_str(),
        &audioData,
        &audioSize
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to synthesize speech: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to synthesize speech. Error: " + std::to_string(result));
    }

    std::vector<uint8_t> audio;
    if (audioData && audioSize > 0) {
        audio.assign(
            static_cast<uint8_t*>(audioData),
            static_cast<uint8_t*>(audioData) + audioSize
        );
        free(audioData);
    }
    return audio;
}

bool VoiceAgentBridge::detectSpeech(const float* samples, size_t sampleCount) {
    if (!handle_) {
        throw std::runtime_error("VoiceAgentBridge: Voice agent not created. Call initialize() first.");
    }

    rac_bool_t speechDetected = RAC_FALSE;
    rac_result_t result = rac_voice_agent_detect_speech(
        handle_,
        samples,
        sampleCount,
        &speechDetected
    );

    if (result != RAC_SUCCESS) {
        LOGE("Failed to detect speech: %d", result);
        throw std::runtime_error("VoiceAgentBridge: Failed to detect speech. Error: " + std::to_string(result));
    }

    return speechDetected == RAC_TRUE;
}

void VoiceAgentBridge::cleanup() {
    if (handle_) {
        rac_result_t result = rac_voice_agent_cleanup(handle_);
        if (result != RAC_SUCCESS) {
            LOGE("Failed to cleanup voice agent: %d", result);
        }

        rac_voice_agent_destroy(handle_);
        handle_ = nullptr;
    }
    initialized_ = false;
    LOGI("Voice agent cleaned up");
}

} // namespace bridges
} // namespace runanywhere
