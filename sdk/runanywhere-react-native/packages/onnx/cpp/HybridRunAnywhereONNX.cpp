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

// Backend registration header - always available
extern "C" {
#include "rac_vad_onnx.h"
}

// RACommons logger - unified logging across platforms
#include "rac_logger.h"

#include <sstream>
#include <chrono>
#include <cctype>
#include <cstring>
#include <fstream>
#include <optional>
#include <vector>
#include <stdexcept>

#if defined(__APPLE__)
#include <mach/mach.h>
#endif

// Category for ONNX module logging
static const char* LOG_CATEGORY = "ONNX";

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

std::optional<double> extractNumericValue(const std::string& json, const std::string& key) {
  std::string searchKey = "\"" + key + "\":";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return std::nullopt;

  pos += searchKey.length();
  while (pos < json.size() && std::isspace(static_cast<unsigned char>(json[pos]))) {
    ++pos;
  }

  size_t endPos = pos;
  while (endPos < json.size()) {
    char c = json[endPos];
    if ((c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+') {
      ++endPos;
      continue;
    }
    break;
  }

  if (endPos == pos) {
    return std::nullopt;
  }

  try {
    return std::stod(json.substr(pos, endPos - pos));
  } catch (...) {
    return std::nullopt;
  }
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
  RAC_LOG_INFO(LOG_CATEGORY, "HybridRunAnywhereONNX constructor - ONNX backend module");
}

HybridRunAnywhereONNX::~HybridRunAnywhereONNX() {
  RAC_LOG_INFO(LOG_CATEGORY, "HybridRunAnywhereONNX destructor");
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
    RAC_LOG_INFO(LOG_CATEGORY, "Registering ONNX backend with C++ registry...");

    rac_result_t result = rac_backend_onnx_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(LOG_CATEGORY, "ONNX backend registered successfully (STT + TTS + VAD)");
      isRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX registration failed with code: %d", result);
      setLastError("ONNX registration failed with error: " + std::to_string(result));
      throw std::runtime_error("ONNX registration failed with error: " + std::to_string(result));
    }
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_INFO(LOG_CATEGORY, "Unregistering ONNX backend...");

    rac_result_t result = rac_backend_onnx_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "ONNX unregistration failed with code: %d", result);
      throw std::runtime_error("ONNX unregistration failed with error: " + std::to_string(result));
    }
    return true;
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
    RAC_LOG_INFO("STT.ONNX", "Loading STT model: %s", path.c_str());
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

    try {
      std::ifstream file(filePath, std::ios::binary | std::ios::ate);
      if (!file.is_open()) {
        return buildJsonObject({{"error", jsonString("Failed to open audio file")}});
      }

      std::streamsize fileSize = file.tellg();
      if (fileSize <= 0) {
        return buildJsonObject({{"error", jsonString("Audio file is empty")}});
      }

      file.seekg(0, std::ios::beg);
      std::vector<uint8_t> fileData(static_cast<size_t>(fileSize));
      if (!file.read(reinterpret_cast<char*>(fileData.data()), fileSize)) {
        return buildJsonObject({{"error", jsonString("Failed to read audio file")}});
      }

      const uint8_t* data = fileData.data();
      size_t dataSize = fileData.size();
      int32_t sampleRate = 16000;

      if (dataSize < 44) {
        return buildJsonObject({{"error", jsonString("File too small to be a valid WAV file")}});
      }
      if (data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F') {
        return buildJsonObject({{"error", jsonString("Invalid WAV file: missing RIFF header")}});
      }
      if (data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
        return buildJsonObject({{"error", jsonString("Invalid WAV file: missing WAVE format")}});
      }

      size_t pos = 12;
      size_t audioDataOffset = 0;
      size_t audioDataSize = 0;

      while (pos + 8 < dataSize) {
        char chunkId[5] = {0};
        std::memcpy(chunkId, &data[pos], 4);

        uint32_t chunkSize = 0;
        std::memcpy(&chunkSize, &data[pos + 4], sizeof(chunkSize));

        if (std::strcmp(chunkId, "fmt ") == 0) {
          if (pos + 8 + chunkSize <= dataSize && chunkSize >= 16) {
            std::memcpy(&sampleRate, &data[pos + 12], sizeof(sampleRate));
            if (sampleRate <= 0 || sampleRate > 48000) {
              sampleRate = 16000;
            }
          }
        } else if (std::strcmp(chunkId, "data") == 0) {
          audioDataOffset = pos + 8;
          audioDataSize = chunkSize;
          break;
        }

        pos += 8 + chunkSize;
        if (chunkSize % 2 != 0) {
          ++pos;
        }
      }

      if (audioDataSize == 0 || audioDataOffset + audioDataSize > dataSize) {
        return buildJsonObject({{"error", jsonString("Could not find valid audio data in WAV file")}});
      }

      if (audioDataSize < 3200) {
        return buildJsonObject({{"error", jsonString("Recording too short to transcribe")}});
      }

      STTOptions options;
      options.language = language.value_or("en");
      options.sampleRate = sampleRate;

      auto result = STTBridge::shared().transcribe(&data[audioDataOffset], audioDataSize, options);

      return buildJsonObject({
        {"text", jsonString(result.text)},
        {"confidence", std::to_string(result.confidence)},
        {"isFinal", result.isFinal ? "true" : "false"}
      });
    } catch (const std::exception& e) {
      return buildJsonObject({{"error", jsonString(e.what())}});
    }
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
    RAC_LOG_INFO("TTS.ONNX", "Loading TTS model: %s", path.c_str());
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
    const std::string voiceId = TTSBridge::shared().currentModelId();
    if (voiceId.empty()) {
      return std::string("[]");
    }

    return std::string("[") + buildJsonObject({
      {"id", jsonString(voiceId)},
      {"name", jsonString(voiceId)},
      {"language", jsonString("unknown")}
    }) + "]";
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
    RAC_LOG_INFO("VAD.ONNX", "Loading VAD model: %s", path.c_str());
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
    if (!VADBridge::shared().isReady()) {
      return buildJsonObject({{"error", jsonString("VAD not initialized")}});
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
  return Promise<bool>::async([configJson]() {
    int sampleRate = 16000;
    float frameLengthSeconds = 0.1f;
    float energyThreshold = 0.005f;

    if (configJson.has_value()) {
      if (const auto parsed =
              extractNumericValue(*configJson, "sampleRate").value_or(
                  extractNumericValue(*configJson, "sample_rate").value_or(16000.0));
          parsed > 0) {
        sampleRate = static_cast<int>(parsed);
      }
      if (const auto parsed =
              extractNumericValue(*configJson, "frameLength").value_or(
                  extractNumericValue(*configJson, "frame_length").value_or(0.1));
          parsed > 0.0) {
        frameLengthSeconds = static_cast<float>(parsed);
      }
      if (const auto parsed =
              extractNumericValue(*configJson, "energyThreshold").value_or(
                  extractNumericValue(*configJson, "energy_threshold").value_or(0.005));
          parsed > 0.0) {
        energyThreshold = static_cast<float>(parsed);
      }
    }

    auto result = VADBridge::shared().initialize(sampleRate, frameLengthSeconds, energyThreshold);
    return result == RAC_SUCCESS;
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereONNX::cleanupVAD() {
  return Promise<void>::async([]() {
    VADBridge::shared().cleanup();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::startVAD() {
  return Promise<bool>::async([]() {
    auto result = VADBridge::shared().start();
    return result == RAC_SUCCESS;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereONNX::stopVAD() {
  return Promise<bool>::async([]() {
    auto result = VADBridge::shared().stop();
    return result == RAC_SUCCESS;
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
    double memoryUsageMB = 0.0;

#if defined(__APPLE__)
    mach_task_basic_info_data_t taskInfo;
    mach_msg_type_number_t infoCount = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(
        mach_task_self(),
        MACH_TASK_BASIC_INFO,
        reinterpret_cast<task_info_t>(&taskInfo),
        &infoCount
    );

    if (result == KERN_SUCCESS) {
      memoryUsageMB = static_cast<double>(taskInfo.resident_size) / (1024.0 * 1024.0);
    }
#elif defined(__ANDROID__) || defined(ANDROID)
    std::ifstream statusFile("/proc/self/status");
    std::string line;
    while (std::getline(statusFile, line)) {
      if (line.rfind("VmRSS:", 0) == 0) {
        std::istringstream iss(line.substr(6));
        long vmRssKB = 0;
        iss >> vmRssKB;
        memoryUsageMB = static_cast<double>(vmRssKB) / 1024.0;
        break;
      }
    }
#endif

    return memoryUsageMB;
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereONNX::setLastError(const std::string& error) {
  lastError_ = error;
  RAC_LOG_ERROR(LOG_CATEGORY, "Error: %s", error.c_str());
}

} // namespace margelo::nitro::runanywhere::onnx
