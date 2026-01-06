/**
 * HybridRunAnywhere.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere SDK.
 *
 * REFACTORED: Now delegates to modular bridges that use the rac_* API
 * from runanywhere-commons, matching Swift's CppBridge pattern.
 */

#include "HybridRunAnywhere.hpp"

// Modular bridges (matching Swift CppBridge pattern)
#include "bridges/PlatformAdapterBridge.hpp"
#include "bridges/InitBridge.hpp"
#include "bridges/LLMBridge.hpp"
#include "bridges/STTBridge.hpp"
#include "bridges/TTSBridge.hpp"
#include "bridges/VADBridge.hpp"
#include "bridges/VoiceAgentBridge.hpp"
#include "bridges/StructuredOutputBridge.hpp"
#include "bridges/StorageBridge.hpp"
#include "bridges/ModelRegistryBridge.hpp"
#include "bridges/EventBridge.hpp"
#include "bridges/StateBridge.hpp"
#include "bridges/AuthBridge.hpp"
#include "bridges/HTTPBridge.hpp"
#include "bridges/DownloadBridge.hpp"
#include "bridges/DeviceBridge.hpp"

// Backend registration headers (conditionally included)
#ifdef HAS_LLAMACPP
extern "C" {
#include "rac_llm_llamacpp.h"
}
#endif

#ifdef HAS_ONNX
extern "C" {
#include "rac_vad_onnx.h"
}
#endif

#include <sstream>
#include <cstring>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <vector>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HybridRunAnywhere"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf(__VA_ARGS__); printf("\n")
#endif

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// ============================================================================
// Base64 Utilities
// ============================================================================

namespace {

static const std::string BASE64_CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(const unsigned char* data, size_t length) {
  std::string result;
  result.reserve(((length + 2) / 3) * 4);

  for (size_t i = 0; i < length; i += 3) {
    unsigned int n = static_cast<unsigned int>(data[i]) << 16;
    if (i + 1 < length) n |= static_cast<unsigned int>(data[i + 1]) << 8;
    if (i + 2 < length) n |= static_cast<unsigned int>(data[i + 2]);

    result.push_back(BASE64_CHARS[(n >> 18) & 0x3F]);
    result.push_back(BASE64_CHARS[(n >> 12) & 0x3F]);
    result.push_back((i + 1 < length) ? BASE64_CHARS[(n >> 6) & 0x3F] : '=');
    result.push_back((i + 2 < length) ? BASE64_CHARS[n & 0x3F] : '=');
  }

  return result;
}

std::vector<unsigned char> base64Decode(const std::string& encoded) {
  std::vector<unsigned char> result;
  result.reserve((encoded.size() / 4) * 3);

  std::vector<int> T(256, -1);
  for (int i = 0; i < 64; i++) {
    T[static_cast<unsigned char>(BASE64_CHARS[i])] = i;
  }

  int val = 0, valb = -8;
  for (unsigned char c : encoded) {
    if (T[c] == -1) break;
    val = (val << 6) + T[c];
    valb += 6;
    if (valb >= 0) {
      result.push_back(static_cast<unsigned char>((val >> valb) & 0xFF));
      valb -= 8;
    }
  }

  return result;
}

std::string encodeBase64Audio(const float* samples, size_t count) {
  return base64Encode(reinterpret_cast<const unsigned char*>(samples),
                      count * sizeof(float));
}

std::string encodeBase64Bytes(const uint8_t* data, size_t size) {
  return base64Encode(data, size);
}

// Simple JSON value extraction
int extractIntValue(const std::string& json, const std::string& key, int defaultValue) {
  std::string searchKey = "\"" + key + "\":";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
  if (pos >= json.size()) return defaultValue;
  return std::stoi(json.substr(pos));
}

float extractFloatValue(const std::string& json, const std::string& key, float defaultValue) {
  std::string searchKey = "\"" + key + "\":";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
  if (pos >= json.size()) return defaultValue;
  return std::stof(json.substr(pos));
}

std::string extractStringValue(const std::string& json, const std::string& key, const std::string& defaultValue = "") {
  std::string searchKey = "\"" + key + "\":\"";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  size_t endPos = json.find("\"", pos);
  if (endPos == std::string::npos) return defaultValue;
  return json.substr(pos, endPos - pos);
}

// Simple JSON builder
std::string buildJsonObject(const std::vector<std::pair<std::string, std::string>>& keyValues) {
  std::string result = "{";
  for (size_t i = 0; i < keyValues.size(); i++) {
    if (i > 0) result += ",";
    result += "\"" + keyValues[i].first + "\":" + keyValues[i].second;
  }
  result += "}";
  return result;
}

std::string jsonString(const std::string& value) {
  std::string escaped = "\"";
  for (char c : value) {
    if (c == '"') escaped += "\\\"";
    else if (c == '\\') escaped += "\\\\";
    else if (c == '\n') escaped += "\\n";
    else if (c == '\r') escaped += "\\r";
    else if (c == '\t') escaped += "\\t";
    else escaped += c;
  }
  escaped += "\"";
  return escaped;
}

} // anonymous namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhere::HybridRunAnywhere() : HybridObject(TAG) {
  LOGI("HybridRunAnywhere constructor - using modular bridges with rac_* API");
}

HybridRunAnywhere::~HybridRunAnywhere() {
  LOGI("HybridRunAnywhere destructor");

  // Cleanup bridges
  VoiceAgentBridge::shared().cleanup();
  LLMBridge::shared().destroy();
  STTBridge::shared().cleanup();
  TTSBridge::shared().cleanup();
  VADBridge::shared().cleanup();
  InitBridge::shared().shutdown();
  PlatformAdapterBridge::shared().shutdown();
}

// ============================================================================
// SDK Lifecycle - Delegates to InitBridge and PlatformAdapterBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::createBackend(
    const std::string& name) {
  return Promise<bool>::async([this, name]() {
    LOGI("createBackend: %s (deprecated - use initialize)", name.c_str());
    // In the new architecture, backends are managed per-capability
    // This is kept for backwards compatibility
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::initialize(
    const std::string& configJson) {
  return Promise<bool>::async([this, configJson]() {
    std::lock_guard<std::mutex> lock(initMutex_);

    LOGI("Initializing SDK with rac_* API...");

    // 1. Setup platform adapter callbacks (MUST be first)
    PlatformCallbacks callbacks;
    callbacks.fileExists = [](const std::string& path) {
      // TODO: Implement via HybridRunAnywhereFileSystem
      return false;
    };
    callbacks.fileRead = [](const std::string& path) -> std::string {
      // TODO: Implement via HybridRunAnywhereFileSystem
      return "";
    };
    callbacks.fileWrite = [](const std::string& path, const std::string& data) {
      // TODO: Implement via HybridRunAnywhereFileSystem
      return false;
    };
    callbacks.fileDelete = [](const std::string& path) {
      // TODO: Implement via HybridRunAnywhereFileSystem
      return false;
    };
    callbacks.log = [](int level, const std::string& category, const std::string& message) {
      LOGI("[%s] %s", category.c_str(), message.c_str());
    };
    callbacks.nowMs = []() -> int64_t {
      auto now = std::chrono::system_clock::now();
      return std::chrono::duration_cast<std::chrono::milliseconds>(
          now.time_since_epoch()).count();
    };

    PlatformAdapterBridge::shared().initialize(callbacks);

    // 2. Initialize commons
    auto result = InitBridge::shared().initialize(configJson);
    if (result != 0) {
      setLastError("Failed to initialize SDK");
      return false;
    }

    // 3. Setup event bridge
    EventBridge::shared().initialize([](const std::string& eventJson) {
      // TODO: Forward to JS via Nitrogen event emitter
      LOGD("Event: %s", eventJson.c_str());
    });

    // 4. Update state
    StateBridge::shared().setState(SDKState::Initialized);

    LOGI("SDK initialized successfully");
    return true;
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhere::destroy() {
  return Promise<void>::async([this]() {
    std::lock_guard<std::mutex> lock(initMutex_);

    // Cleanup all bridges
    VoiceAgentBridge::shared().cleanup();
    LLMBridge::shared().destroy();
    STTBridge::shared().cleanup();
    TTSBridge::shared().cleanup();
    VADBridge::shared().cleanup();
    EventBridge::shared().shutdown();
    InitBridge::shared().shutdown();
    PlatformAdapterBridge::shared().shutdown();

    StateBridge::shared().setState(SDKState::Uninitialized);

    LOGI("SDK destroyed");
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isInitialized() {
  return Promise<bool>::async([]() {
    return StateBridge::shared().isSDKInitialized();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getBackendInfo() {
  return Promise<std::string>::async([]() {
    return buildJsonObject({
      {"api", jsonString("rac_*")},
      {"source", jsonString("runanywhere-commons")},
      {"llmLoaded", LLMBridge::shared().isLoaded() ? "true" : "false"},
      {"sttLoaded", STTBridge::shared().isLoaded() ? "true" : "false"},
      {"ttsLoaded", TTSBridge::shared().isLoaded() ? "true" : "false"},
      {"vadLoaded", VADBridge::shared().isLoaded() ? "true" : "false"}
    });
  });
}

// ============================================================================
// Text Generation (LLM) - Delegates to LLMBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadTextModel(
    const std::string& path,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([path, configJson]() {
    LOGI("Loading LLM model: %s", path.c_str());

    // Extract modelId and modelName from config if provided
    std::string modelId;
    std::string modelName;
    if (configJson.has_value()) {
      modelId = extractStringValue(*configJson, "model_id", "");
      modelName = extractStringValue(*configJson, "model_name", "");
    }

    // Call with correct 4-arg signature (path, modelId, modelName)
    auto result = LLMBridge::shared().loadModel(path, modelId, modelName);
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isTextModelLoaded() {
  return Promise<bool>::async([]() {
    return LLMBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadTextModel() {
  return Promise<bool>::async([]() {
    auto result = LLMBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, prompt, optionsJson]() {
    if (!LLMBridge::shared().isLoaded()) {
      setLastError("Model not loaded");
      return buildJsonObject({{"error", jsonString("Model not loaded")}});
    }

    LLMOptions options;
    if (optionsJson.has_value()) {
      options.maxTokens = extractIntValue(*optionsJson, "max_tokens", 512);
      options.temperature = extractFloatValue(*optionsJson, "temperature", 0.7f);
      options.topP = extractFloatValue(*optionsJson, "top_p", 0.9f);
      options.topK = extractIntValue(*optionsJson, "top_k", 40);
    }

    LOGI("Generating with prompt: %.50s...", prompt.c_str());

    auto startTime = std::chrono::high_resolution_clock::now();
    auto result = LLMBridge::shared().generate(prompt, options);
    auto endTime = std::chrono::high_resolution_clock::now();
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        endTime - startTime).count();

    return buildJsonObject({
      {"text", jsonString(result.text)},
      {"tokensUsed", std::to_string(result.tokenCount)},
      {"latencyMs", std::to_string(durationMs)},
      {"cancelled", result.cancelled ? "true" : "false"}
    });
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
  return Promise<std::string>::async([this, prompt, optionsJson, callback]() {
    if (!LLMBridge::shared().isLoaded()) {
      setLastError("Model not loaded");
      return std::string("");
    }

    LLMOptions options;
    options.maxTokens = extractIntValue(optionsJson, "max_tokens", 512);
    options.temperature = extractFloatValue(optionsJson, "temperature", 0.7f);

    std::string fullResponse;

    LLMStreamCallbacks streamCallbacks;
    streamCallbacks.onToken = [&callback, &fullResponse](const std::string& token) -> bool {
      fullResponse += token;
      if (callback) {
        callback(token, false);
      }
      return true;
    };
    streamCallbacks.onComplete = [&callback](const std::string&, int, double) {
      if (callback) {
        callback("", true);
      }
    };
    streamCallbacks.onError = [this](int code, const std::string& message) {
      setLastError(message);
    };

    LLMBridge::shared().generateStream(prompt, options, streamCallbacks);

    return fullResponse;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::cancelGeneration() {
  return Promise<bool>::async([]() {
    LLMBridge::shared().cancel();
    return true;
  });
}

// ============================================================================
// Structured Output - Delegates to StructuredOutputBridge
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::generateStructured(
    const std::string& prompt,
    const std::string& schema,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, prompt, schema, optionsJson]() {
    auto result = StructuredOutputBridge::shared().generate(
      prompt, schema, optionsJson.value_or("")
    );

    if (result.success) {
      return result.json;
    } else {
      setLastError(result.error);
      return buildJsonObject({{"error", jsonString(result.error)}});
    }
  });
}

// ============================================================================
// Speech-to-Text (STT) - Delegates to STTBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadSTTModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([path]() {
    LOGI("Loading STT model: %s", path.c_str());
    auto result = STTBridge::shared().loadModel(path);
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isSTTModelLoaded() {
  return Promise<bool>::async([]() {
    return STTBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadSTTModel() {
  return Promise<bool>::async([]() {
    auto result = STTBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::transcribe(
    const std::string& audioBase64,
    double sampleRate,
    const std::optional<std::string>& language) {
  return Promise<std::string>::async([this, audioBase64, sampleRate, language]() {
    if (!STTBridge::shared().isLoaded()) {
      return buildJsonObject({{"error", jsonString("STT model not loaded")}});
    }

    auto audioBytes = base64Decode(audioBase64);
    const void* samples = audioBytes.data();
    size_t audioSize = audioBytes.size();

    STTOptions options;
    options.language = language.value_or("en");

    auto result = STTBridge::shared().transcribe(samples, audioSize, options);

    return buildJsonObject({
      {"text", jsonString(result.text)},
      {"confidence", std::to_string(result.confidence)},
      {"isFinal", result.isFinal ? "true" : "false"}
    });
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
  return Promise<std::string>::async([this, filePath, language]() {
    if (!STTBridge::shared().isLoaded()) {
      return buildJsonObject({{"error", jsonString("STT model not loaded")}});
    }

    // TODO: Read audio file and transcribe
    // This requires platform-specific audio file reading
    return buildJsonObject({{"error", jsonString("transcribeFile not yet implemented with rac_* API")}});
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::supportsSTTStreaming() {
  return Promise<bool>::async([]() {
    // STT streaming support depends on the model
    return true;
  });
}

// ============================================================================
// Text-to-Speech (TTS) - Delegates to TTSBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadTTSModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([path]() {
    LOGI("Loading TTS model: %s", path.c_str());
    auto result = TTSBridge::shared().loadModel(path);
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isTTSModelLoaded() {
  return Promise<bool>::async([]() {
    return TTSBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadTTSModel() {
  return Promise<bool>::async([]() {
    auto result = TTSBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::synthesize(
    const std::string& text,
    const std::string& voiceId,
    double speedRate,
    double pitchShift) {
  return Promise<std::string>::async([this, text, voiceId, speedRate, pitchShift]() {
    if (!TTSBridge::shared().isLoaded()) {
      return buildJsonObject({{"error", jsonString("TTS model not loaded")}});
    }

    TTSOptions options;
    options.voiceId = voiceId;
    options.speed = static_cast<float>(speedRate);
    options.pitch = static_cast<float>(pitchShift);

    auto result = TTSBridge::shared().synthesize(text, options);

    std::string audioBase64 = encodeBase64Audio(result.audioData.data(), result.audioData.size());

    return buildJsonObject({
      {"audio", jsonString(audioBase64)},
      {"sampleRate", std::to_string(result.sampleRate)},
      {"numSamples", std::to_string(result.audioData.size())},
      {"duration", std::to_string(result.durationMs / 1000.0)}
    });
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getTTSVoices() {
  return Promise<std::string>::async([]() {
    return std::string("[{\"id\":\"default\",\"name\":\"Default Voice\",\"language\":\"en-US\"}]");
  });
}

// ============================================================================
// Voice Activity Detection (VAD) - Delegates to VADBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadVADModel(
    const std::string& path,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([path]() {
    LOGI("Loading VAD model: %s", path.c_str());
    auto result = VADBridge::shared().loadModel(path);
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isVADModelLoaded() {
  return Promise<bool>::async([]() {
    return VADBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadVADModel() {
  return Promise<bool>::async([]() {
    auto result = VADBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::processVAD(
    const std::string& audioBase64,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, audioBase64, optionsJson]() {
    if (!VADBridge::shared().isLoaded()) {
      return buildJsonObject({{"error", jsonString("VAD model not loaded")}});
    }

    auto audioBytes = base64Decode(audioBase64);
    VADOptions options;
    auto result = VADBridge::shared().process(audioBytes.data(), audioBytes.size(), options);

    return buildJsonObject({
      {"isSpeech", result.isSpeech ? "true" : "false"},
      {"speechProbability", std::to_string(result.speechProbability)},
      {"startTime", std::to_string(result.startTime)},
      {"endTime", std::to_string(result.endTime)}
    });
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhere::resetVAD() {
  return Promise<void>::async([]() {
    VADBridge::shared().reset();
  });
}

// ============================================================================
// Voice Agent - Delegates to VoiceAgentBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::initializeVoiceAgent(
    const std::string& configJson) {
  return Promise<bool>::async([configJson]() {
    VoiceAgentConfig config;
    config.sttModelId = extractStringValue(configJson, "sttModelId");
    config.llmModelId = extractStringValue(configJson, "llmModelId");
    config.ttsVoiceId = extractStringValue(configJson, "ttsVoiceId");

    auto result = VoiceAgentBridge::shared().initialize(config);
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::initializeVoiceAgentWithLoadedModels() {
  return Promise<bool>::async([]() {
    auto result = VoiceAgentBridge::shared().initializeWithLoadedModels();
    return result == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isVoiceAgentReady() {
  return Promise<bool>::async([]() {
    return VoiceAgentBridge::shared().isReady();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getVoiceAgentComponentStates() {
  return Promise<std::string>::async([]() {
    auto states = VoiceAgentBridge::shared().getComponentStates();

    auto stateToString = [](ComponentState state) -> std::string {
      switch (state) {
        case ComponentState::NotLoaded: return "notLoaded";
        case ComponentState::Loading: return "loading";
        case ComponentState::Loaded: return "loaded";
        case ComponentState::Failed: return "failed";
      }
      return "unknown";
    };

    return buildJsonObject({
      {"stt", buildJsonObject({
        {"state", jsonString(stateToString(states.stt))},
        {"modelId", jsonString(states.sttModelId)}
      })},
      {"llm", buildJsonObject({
        {"state", jsonString(stateToString(states.llm))},
        {"modelId", jsonString(states.llmModelId)}
      })},
      {"tts", buildJsonObject({
        {"state", jsonString(stateToString(states.tts))},
        {"voiceId", jsonString(states.ttsVoiceId)}
      })},
      {"isFullyReady", states.isFullyReady() ? "true" : "false"}
    });
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::processVoiceTurn(
    const std::string& audioBase64) {
  return Promise<std::string>::async([this, audioBase64]() {
    if (!VoiceAgentBridge::shared().isReady()) {
      return buildJsonObject({{"error", jsonString("Voice agent not ready")}});
    }

    auto audioBytes = base64Decode(audioBase64);
    auto result = VoiceAgentBridge::shared().processVoiceTurn(
      audioBytes.data(), audioBytes.size()
    );

    std::string synthesizedBase64;
    if (!result.synthesizedAudio.empty()) {
      synthesizedBase64 = encodeBase64Bytes(
        result.synthesizedAudio.data(),
        result.synthesizedAudio.size()
      );
    }

    return buildJsonObject({
      {"speechDetected", result.speechDetected ? "true" : "false"},
      {"transcription", jsonString(result.transcription)},
      {"response", jsonString(result.response)},
      {"synthesizedAudio", jsonString(synthesizedBase64)},
      {"sampleRate", std::to_string(result.sampleRate)}
    });
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::voiceAgentTranscribe(
    const std::string& audioBase64) {
  return Promise<std::string>::async([audioBase64]() {
    auto audioBytes = base64Decode(audioBase64);
    return VoiceAgentBridge::shared().transcribe(
      audioBytes.data(), audioBytes.size()
    );
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::voiceAgentGenerateResponse(
    const std::string& prompt) {
  return Promise<std::string>::async([prompt]() {
    return VoiceAgentBridge::shared().generateResponse(prompt);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::voiceAgentSynthesizeSpeech(
    const std::string& text) {
  return Promise<std::string>::async([text]() {
    auto audio = VoiceAgentBridge::shared().synthesizeSpeech(text);
    return encodeBase64Bytes(audio.data(), audio.size());
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhere::cleanupVoiceAgent() {
  return Promise<void>::async([]() {
    VoiceAgentBridge::shared().cleanup();
  });
}

// ============================================================================
// Model Assignment - Delegates to ModelRegistryBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::assignModel(
    const std::string& modelId,
    const std::string& framework) {
  return Promise<bool>::async([modelId, framework]() {
    return ModelRegistryBridge::shared().assignModel(modelId, framework);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getModelAssignment(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    return ModelRegistryBridge::shared().getModelAssignment(modelId);
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhere::clearModelAssignments() {
  return Promise<void>::async([]() {
    ModelRegistryBridge::shared().clearModelAssignments();
  });
}

// ============================================================================
// Model Registry - Delegates to ModelRegistryBridge
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getAvailableModels() {
  return Promise<std::string>::async([]() {
    return ModelRegistryBridge::shared().getAvailableModelsJson();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getModelInfo(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    return ModelRegistryBridge::shared().getModelInfoJson(modelId);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isModelDownloaded(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return ModelRegistryBridge::shared().isModelDownloaded(modelId);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getModelPath(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    return ModelRegistryBridge::shared().getModelPath(modelId);
  });
}

// ============================================================================
// Download Service - Delegates to DownloadBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::downloadModel(
    const std::string& modelId,
    const std::string& url,
    const std::string& destPath) {
  return Promise<bool>::async([modelId, url, destPath]() {
    return DownloadBridge::shared().startDownload(modelId, url, destPath) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::cancelDownload(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return DownloadBridge::shared().cancelDownload(modelId);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getDownloadProgress(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    auto progress = DownloadBridge::shared().getProgress(modelId);
    return buildJsonObject({
      {"bytesDownloaded", std::to_string(progress.bytesDownloaded)},
      {"totalBytes", std::to_string(progress.totalBytes)},
      {"percentage", std::to_string(progress.percentage)},
      {"isComplete", progress.isComplete ? "true" : "false"},
      {"error", jsonString(progress.error)}
    });
  });
}

// ============================================================================
// Authentication - Delegates to AuthBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::authenticate(
    const std::string& apiKey) {
  return Promise<bool>::async([apiKey]() {
    return AuthBridge::shared().authenticate(apiKey) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isAuthenticated() {
  return Promise<bool>::async([]() {
    return AuthBridge::shared().isAuthenticated();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getUserId() {
  return Promise<std::string>::async([]() {
    return AuthBridge::shared().getUserId();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getOrganizationId() {
  return Promise<std::string>::async([]() {
    return AuthBridge::shared().getOrganizationId();
  });
}

// ============================================================================
// Device Registration - Delegates to DeviceBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::registerDevice(
    const std::string& environmentJson) {
  return Promise<bool>::async([environmentJson]() {
    return DeviceBridge::shared().registerDevice(environmentJson) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isDeviceRegistered() {
  return Promise<bool>::async([]() {
    return DeviceBridge::shared().isRegistered();
  });
}

// ============================================================================
// HTTP Client - Delegates to HTTPBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::configureHttp(
    const std::string& baseUrl,
    const std::string& apiKey) {
  return Promise<bool>::async([baseUrl, apiKey]() {
    return HTTPBridge::shared().configure(baseUrl, apiKey) == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::httpPost(
    const std::string& path,
    const std::string& bodyJson) {
  return Promise<std::string>::async([path, bodyJson]() {
    return HTTPBridge::shared().post(path, bodyJson);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::httpGet(
    const std::string& path) {
  return Promise<std::string>::async([path]() {
    return HTTPBridge::shared().get(path);
  });
}

// ============================================================================
// Events - Delegates to EventBridge
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhere::emitEvent(
    const std::string& eventJson) {
  return Promise<void>::async([eventJson]() {
    EventBridge::shared().emit(eventJson);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::pollEvents() {
  return Promise<std::string>::async([]() {
    return EventBridge::shared().poll();
  });
}

// ============================================================================
// Storage - Delegates to StorageBridge
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getStorageInfo() {
  return Promise<std::string>::async([]() {
    auto info = StorageBridge::shared().getStorageInfo();
    return buildJsonObject({
      {"totalBytes", std::to_string(info.totalBytes)},
      {"availableBytes", std::to_string(info.availableBytes)},
      {"usedByModelsBytes", std::to_string(info.usedByModelsBytes)},
      {"usedByCacheBytes", std::to_string(info.usedByCacheBytes)}
    });
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::clearCache() {
  return Promise<bool>::async([]() {
    return StorageBridge::shared().clearCache();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::deleteModel(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return StorageBridge::shared().deleteModel(modelId);
  });
}

// ============================================================================
// Utility Functions
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getLastError() {
  return Promise<std::string>::async([this]() { return lastError_; });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::extractArchive(
    const std::string& archivePath,
    const std::string& destPath) {
  return Promise<bool>::async([archivePath, destPath]() {
    // TODO: Implement via platform adapter
    LOGI("extractArchive: %s -> %s", archivePath.c_str(), destPath.c_str());
    return false;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getDeviceCapabilities() {
  return Promise<std::string>::async([]() {
    std::string platform =
#if defined(__APPLE__)
        "ios";
#else
        "android";
#endif
    bool supportsMetal =
#if defined(__APPLE__)
        true;
#else
        false;
#endif
    bool supportsVulkan =
#if defined(__APPLE__)
        false;
#else
        true;
#endif
    return buildJsonObject({
        {"platform", jsonString(platform)},
        {"supports_metal", supportsMetal ? "true" : "false"},
        {"supports_vulkan", supportsVulkan ? "true" : "false"},
        {"api", jsonString("rac_*")}
    });
  });
}

std::shared_ptr<Promise<double>> HybridRunAnywhere::getMemoryUsage() {
  return Promise<double>::async([]() {
    // TODO: Get memory usage from commons
    return 0.0;
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhere::setLastError(const std::string& error) {
  lastError_ = error;
  LOGE("Error: %s", error.c_str());
}

// ============================================================================
// Backend Registration - Matches Swift LlamaCPP.register(), ONNX.register()
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::registerLlamaCppBackend() {
  return Promise<bool>::async([]() {
    LOGI("Registering LlamaCPP backend with C++ registry...");
#ifdef HAS_LLAMACPP
    rac_result_t result = rac_backend_llamacpp_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      LOGI("✅ LlamaCPP backend registered successfully");
      return true;
    } else {
      LOGE("❌ LlamaCPP registration failed with code: %d", result);
      return false;
    }
#else
    LOGE("LlamaCPP backend not available (HAS_LLAMACPP not defined)");
    return false;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unregisterLlamaCppBackend() {
  return Promise<bool>::async([]() {
    LOGI("Unregistering LlamaCPP backend...");
#ifdef HAS_LLAMACPP
    rac_result_t result = rac_backend_llamacpp_unregister();
    return result == RAC_SUCCESS;
#else
    return false;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::registerONNXBackend() {
  return Promise<bool>::async([]() {
    LOGI("Registering ONNX backend with C++ registry...");
#ifdef HAS_ONNX
    rac_result_t result = rac_backend_onnx_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      LOGI("✅ ONNX backend registered successfully (STT + TTS + VAD)");
      return true;
    } else {
      LOGE("❌ ONNX registration failed with code: %d", result);
      return false;
    }
#else
    LOGE("ONNX backend not available (HAS_ONNX not defined)");
    return false;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unregisterONNXBackend() {
  return Promise<bool>::async([]() {
    LOGI("Unregistering ONNX backend...");
#ifdef HAS_ONNX
    rac_result_t result = rac_backend_onnx_unregister();
    return result == RAC_SUCCESS;
#else
    return false;
#endif
  });
}

} // namespace margelo::nitro::runanywhere
