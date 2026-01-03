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
#include "bridges/ModelRegistryBridge.hpp"
#include "bridges/EventBridge.hpp"
#include "bridges/StateBridge.hpp"
#include "bridges/AuthBridge.hpp"
#include "bridges/HTTPBridge.hpp"
#include "bridges/DownloadBridge.hpp"
#include "bridges/DeviceBridge.hpp"

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
  return Promise<bool>::async([path]() {
    LOGI("Loading LLM model: %s", path.c_str());
    auto result = LLMBridge::shared().loadModel(path);
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

} // namespace margelo::nitro::runanywhere
