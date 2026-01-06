/**
 * HybridRunAnywhereONNX.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere ONNX backend.
 *
 * ONNX-specific implementation for speech processing:
 * - STT, TTS, VAD, Voice Agent
 */

#include "HybridRunAnywhereONNX.hpp"

// ONNX bridges
#include "bridges/STTBridge.hpp"
#include "bridges/TTSBridge.hpp"
#include "bridges/VADBridge.hpp"
#include "bridges/VoiceAgentBridge.hpp"

// Backend registration header (conditionally included)
#ifdef HAS_ONNX
extern "C" {
#include "rac_vad_onnx.h"
}
#endif

#include <sstream>
#include <chrono>
#include <vector>

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HybridRunAnywhereONNX"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf(__VA_ARGS__); printf("\n")
#endif

namespace margelo::nitro::runanywhere::onnx {

using namespace ::runanywhere::bridges;

// ============================================================================
// Base64 and JSON Utilities
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

std::string extractStringValue(const std::string& json, const std::string& key, const std::string& defaultValue = "") {
  std::string searchKey = "\"" + key + "\":\"";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  size_t endPos = json.find("\"", pos);
  if (endPos == std::string::npos) return defaultValue;
  return json.substr(pos, endPos - pos);
}

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

HybridRunAnywhereONNX::HybridRunAnywhereONNX() : HybridObject(TAG) {
  LOGI("HybridRunAnywhereONNX constructor - ONNX backend module");
}

HybridRunAnywhereONNX::~HybridRunAnywhereONNX() {
  LOGI("HybridRunAnywhereONNX destructor");
  VoiceAgentBridge::shared().cleanup();
  STTBridge::shared().cleanup();
  TTSBridge::shared().cleanup();
  VADBridge::shared().cleanup();
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::registerBackend() {
  return Promise<bool>::async([this]() {
    LOGI("Registering ONNX backend with C++ registry...");
#ifdef HAS_ONNX
    rac_result_t result = rac_backend_onnx_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      LOGI("✅ ONNX backend registered successfully (STT + TTS + VAD)");
      isRegistered_ = true;
      return true;
    } else {
      LOGE("❌ ONNX registration failed with code: %d", result);
      setLastError("ONNX registration failed");
      return false;
    }
#else
    LOGE("ONNX backend not available (HAS_ONNX not defined)");
    setLastError("ONNX backend not compiled in");
    return false;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unregisterBackend() {
  return Promise<bool>::async([this]() {
    LOGI("Unregistering ONNX backend...");
#ifdef HAS_ONNX
    rac_result_t result = rac_backend_onnx_unregister();
    isRegistered_ = false;
    return result == RAC_SUCCESS;
#else
    return false;
#endif
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isRegistered_;
  });
}

// ============================================================================
// Speech-to-Text (STT)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::loadSTTModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    LOGI("Loading STT model: %s", path.c_str());
    auto result = STTBridge::shared().loadModel(path);
    if (result != 0) {
      setLastError("Failed to load STT model");
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isSTTModelLoaded() {
  return Promise<bool>::async([]() {
    return STTBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unloadSTTModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    auto result = STTBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::transcribe(
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

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
  return Promise<std::string>::async([this, filePath, language]() {
    if (!STTBridge::shared().isLoaded()) {
      return buildJsonObject({{"error", jsonString("STT model not loaded")}});
    }

    // TODO: Read audio file and transcribe
    return buildJsonObject({{"error", jsonString("transcribeFile not yet implemented with rac_* API")}});
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::supportsSTTStreaming() {
  return Promise<bool>::async([]() {
    return true;
  });
}

// ============================================================================
// Text-to-Speech (TTS)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::loadTTSModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    LOGI("Loading TTS model: %s", path.c_str());
    auto result = TTSBridge::shared().loadModel(path);
    if (result != 0) {
      setLastError("Failed to load TTS model");
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isTTSModelLoaded() {
  return Promise<bool>::async([]() {
    return TTSBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unloadTTSModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    auto result = TTSBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::synthesize(
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

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::getTTSVoices() {
  return Promise<std::string>::async([]() {
    return std::string("[{\"id\":\"default\",\"name\":\"Default Voice\",\"language\":\"en-US\"}]");
  });
}

// ============================================================================
// Voice Activity Detection (VAD)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::loadVADModel(
    const std::string& path,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    LOGI("Loading VAD model: %s", path.c_str());
    auto result = VADBridge::shared().loadModel(path);
    if (result != 0) {
      setLastError("Failed to load VAD model");
      return false;
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isVADModelLoaded() {
  return Promise<bool>::async([]() {
    return VADBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unloadVADModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    auto result = VADBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::processVAD(
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

std::shared_ptr<Promise<void>> HybridRunAnywhereONNX::resetVAD() {
  return Promise<void>::async([]() {
    VADBridge::shared().reset();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::initializeVAD(
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([]() {
    // TODO: Initialize VAD with config
    return true;
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereONNX::cleanupVAD() {
  return Promise<void>::async([]() {
    VADBridge::shared().cleanup();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::startVAD() {
  return Promise<bool>::async([]() {
    // TODO: Start VAD processing
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::stopVAD() {
  return Promise<bool>::async([]() {
    // TODO: Stop VAD processing
    return true;
  });
}

// ============================================================================
// Voice Agent
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::initializeVoiceAgent(
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

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::isVoiceAgentReady() {
  return Promise<bool>::async([]() {
    return VoiceAgentBridge::shared().isReady();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::processVoiceTurn(
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

std::shared_ptr<Promise<void>> HybridRunAnywhereONNX::cleanupVoiceAgent() {
  return Promise<void>::async([]() {
    VoiceAgentBridge::shared().cleanup();
  });
}

// ============================================================================
// Utilities
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereONNX::getLastError() {
  return Promise<std::string>::async([this]() { return lastError_; });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereONNX::getMemoryUsage() {
  return Promise<double>::async([]() {
    // TODO: Get memory usage from ONNX Runtime
    return 0.0;
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereONNX::setLastError(const std::string& error) {
  lastError_ = error;
  LOGE("Error: %s", error.c_str());
}

} // namespace margelo::nitro::runanywhere::onnx
