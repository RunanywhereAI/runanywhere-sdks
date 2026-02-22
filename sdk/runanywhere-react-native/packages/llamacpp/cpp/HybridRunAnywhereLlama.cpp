/**
 * HybridRunAnywhereLlama.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere Llama backend.
 *
 * Llama-specific implementation for text generation using LlamaCPP.
 *
 * NOTE: LlamaCPP backend is REQUIRED and always linked via the build system.
 */

#include "HybridRunAnywhereLlama.hpp"

// Llama bridges
#include "bridges/LLMBridge.hpp"
#include "bridges/StructuredOutputBridge.hpp"
#include "bridges/VLMBridge.hpp"

// Backend registration headers - always available
extern "C" {
#include "rac_llm_llamacpp.h"
#include "rac_vlm_llamacpp.h"
}

// Unified logging via rac_logger.h
#include "rac_logger.h"

#include <sstream>
#include <chrono>
#include <vector>
#include <stdexcept>

// Log category for this module
#define LOG_CATEGORY "LLM.LlamaCpp"
#define VLM_LOG_CATEGORY "VLM.LlamaCpp"

namespace margelo::nitro::runanywhere::llama {

using namespace ::runanywhere::bridges;

// ============================================================================
// JSON Utilities
// ============================================================================

namespace {

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

// Base64 decoding for rgbPixels image format
std::vector<uint8_t> base64Decode(const std::string& encoded) {
  static const std::string base64_chars =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  std::vector<uint8_t> decoded;
  std::vector<int> T(256, -1);
  for (int i = 0; i < 64; i++) T[base64_chars[i]] = i;

  int val = 0, valb = -8;
  for (unsigned char c : encoded) {
    if (T[c] == -1) break;
    val = (val << 6) + T[c];
    valb += 6;
    if (valb >= 0) {
      decoded.push_back(char((val >> valb) & 0xFF));
      valb -= 8;
    }
  }
  return decoded;
}

// Build VLMImageInput from JS bridge parameters
VLMImageInput buildVLMImageInput(int imageFormat, const std::string& imageData,
                                 int imageWidth, int imageHeight) {
  VLMImageInput input;

  if (imageFormat == 0) {
    // File path format
    input.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
    input.file_path = imageData;
  } else if (imageFormat == 1) {
    // RGB pixels format (base64-encoded from JS)
    input.format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
    // Decode base64 to raw bytes
    static std::vector<uint8_t> pixelBuffer;
    pixelBuffer = base64Decode(imageData);
    input.pixel_data = pixelBuffer.data();
    input.width = static_cast<uint32_t>(imageWidth);
    input.height = static_cast<uint32_t>(imageHeight);
    input.data_size = pixelBuffer.size();
  } else if (imageFormat == 2) {
    // Base64 format
    input.format = RAC_VLM_IMAGE_FORMAT_BASE64;
    input.base64_data = imageData;
  } else {
    throw std::runtime_error("Invalid image format: " + std::to_string(imageFormat));
  }

  return input;
}

} // anonymous namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereLlama::HybridRunAnywhereLlama() : HybridObject(TAG) {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama constructor - Llama backend module");
}

HybridRunAnywhereLlama::~HybridRunAnywhereLlama() {
  RAC_LOG_DEBUG(LOG_CATEGORY, "HybridRunAnywhereLlama destructor");
  // NOTE: Do NOT call LLMBridge::shared().destroy() or VLMBridge::shared().destroy() here.
  // The bridges are process-lifetime singletons. Destroying them from any HybridObject
  // destructor would tear down shared model state when garbage-collected temporary
  // instances are cleaned up (e.g., from isNativeLlamaModuleAvailable() checks).
  // Bridge cleanup happens naturally at process exit via their own static destructors.
}

// ============================================================================
// Backend Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::registerBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Registering LlamaCPP backend with C++ registry");

    rac_result_t result = rac_backend_llamacpp_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(LOG_CATEGORY, "LlamaCPP backend registered successfully");
      isRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP registration failed with code: %d", result);
      setLastError("LlamaCPP registration failed with error: " + std::to_string(result));
      throw std::runtime_error("LlamaCPP registration failed with error: " + std::to_string(result));
    }
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::unregisterBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(LOG_CATEGORY, "Unregistering LlamaCPP backend");

    rac_result_t result = rac_backend_llamacpp_unregister();
    isRegistered_ = false;
    if (result != RAC_SUCCESS) {
      RAC_LOG_ERROR(LOG_CATEGORY, "LlamaCPP unregistration failed with code: %d", result);
      throw std::runtime_error("LlamaCPP unregistration failed with error: " + std::to_string(result));
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::isBackendRegistered() {
  return Promise<bool>::async([this]() {
    return isRegistered_;
  });
}

// ============================================================================
// Model Loading
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::loadModel(
    const std::string& path,
    const std::optional<std::string>& modelId,
    const std::optional<std::string>& modelName,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path, modelId, modelName, configJson]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    RAC_LOG_INFO(LOG_CATEGORY, "Loading Llama model: %s", path.c_str());

    std::string id = modelId.value_or("");
    std::string name = modelName.value_or("");

    // Call with correct 4-arg signature (path, modelId, modelName)
    // LLMBridge::loadModel will throw on error
    auto result = LLMBridge::shared().loadModel(path, id, name);
    if (result != 0) {
      std::string error = "Failed to load Llama model: " + path + " (error: " + std::to_string(result) + ")";
      setLastError(error);
      throw std::runtime_error(error);
    }
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::isModelLoaded() {
  return Promise<bool>::async([]() {
    return LLMBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::unloadModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    auto result = LLMBridge::shared().unload();
    return result == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::getModelInfo() {
  return Promise<std::string>::async([]() {
    if (!LLMBridge::shared().isLoaded()) {
      return std::string("{}");
    }
    return buildJsonObject({
      {"loaded", "true"},
      {"backend", jsonString("llamacpp")}
    });
  });
}

// ============================================================================
// Text Generation
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, prompt, optionsJson]() {
    if (!LLMBridge::shared().isLoaded()) {
      setLastError("Model not loaded");
      throw std::runtime_error("LLMBridge: Model not loaded. Call loadModel() first.");
    }

    LLMOptions options;
    if (optionsJson.has_value()) {
      options.maxTokens = extractIntValue(*optionsJson, "max_tokens", 512);
      options.temperature = extractFloatValue(*optionsJson, "temperature", 0.7f);
      options.topP = extractFloatValue(*optionsJson, "top_p", 0.9f);
      options.topK = extractIntValue(*optionsJson, "top_k", 40);
    }

    RAC_LOG_DEBUG(LOG_CATEGORY, "Generating with prompt: %.50s...", prompt.c_str());

    auto startTime = std::chrono::high_resolution_clock::now();
    // LLMBridge::generate will throw on error
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

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
  return Promise<std::string>::async([this, prompt, optionsJson, callback]() {
    if (!LLMBridge::shared().isLoaded()) {
      setLastError("Model not loaded");
      throw std::runtime_error("LLMBridge: Model not loaded. Call loadModel() first.");
    }

    LLMOptions options;
    options.maxTokens = extractIntValue(optionsJson, "max_tokens", 512);
    options.temperature = extractFloatValue(optionsJson, "temperature", 0.7f);

    std::string fullResponse;
    std::string streamError;

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
    streamCallbacks.onError = [this, &streamError](int code, const std::string& message) {
      setLastError(message);
      streamError = message;
    };

    LLMBridge::shared().generateStream(prompt, options, streamCallbacks);

    if (!streamError.empty()) {
      throw std::runtime_error("LLMBridge: Stream generation failed: " + streamError);
    }

    return fullResponse;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::cancelGeneration() {
  return Promise<bool>::async([]() {
    LLMBridge::shared().cancel();
    return true;
  });
}

// ============================================================================
// Structured Output
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::generateStructured(
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
// Utilities
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::getLastError() {
  return Promise<std::string>::async([this]() { return lastError_; });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereLlama::getMemoryUsage() {
  return Promise<double>::async([]() {
    // TODO: Get memory usage from LlamaCPP
    return 0.0;
  });
}

// ============================================================================
// VLM (Vision Language Model)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::registerVLMBackend() {
  return Promise<bool>::async([this]() {
    RAC_LOG_DEBUG(VLM_LOG_CATEGORY, "Registering LlamaCPP VLM backend with C++ registry");

    rac_result_t result = rac_backend_llamacpp_vlm_register();
    // RAC_SUCCESS (0) or RAC_ERROR_MODULE_ALREADY_REGISTERED (-4) are both OK
    if (result == RAC_SUCCESS || result == -4) {
      RAC_LOG_INFO(VLM_LOG_CATEGORY, "LlamaCPP VLM backend registered successfully");
      isVLMRegistered_ = true;
      return true;
    } else {
      RAC_LOG_ERROR(VLM_LOG_CATEGORY, "LlamaCPP VLM registration failed with code: %d", result);
      setLastError("LlamaCPP VLM registration failed with error: " + std::to_string(result));
      throw std::runtime_error("LlamaCPP VLM registration failed with error: " + std::to_string(result));
    }
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::loadVLMModel(
    const std::string& modelPath,
    const std::string& mmprojPath,
    const std::optional<std::string>& modelId,
    const std::optional<std::string>& modelName) {
  return Promise<bool>::async([this, modelPath, mmprojPath, modelId, modelName]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    RAC_LOG_INFO(VLM_LOG_CATEGORY, "Loading VLM model: %s", modelPath.c_str());

    std::string id = modelId.value_or("");
    std::string name = modelName.value_or("");

    try {
      VLMBridge::shared().loadModel(modelPath, mmprojPath, id, name);
      return true;
    } catch (const std::exception& e) {
      std::string error = "Failed to load VLM model: " + modelPath + " - " + e.what();
      setLastError(error);
      throw std::runtime_error(error);
    }
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::isVLMModelLoaded() {
  return Promise<bool>::async([]() {
    return VLMBridge::shared().isLoaded();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::unloadVLMModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    try {
      VLMBridge::shared().unload();
      return true;
    } catch (const std::exception& e) {
      setLastError(e.what());
      return false;
    }
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::processVLMImage(
    double imageFormat,
    const std::string& imageData,
    double imageWidth,
    double imageHeight,
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, imageFormat, imageData, imageWidth, imageHeight, prompt, optionsJson]() {
    if (!VLMBridge::shared().isLoaded()) {
      setLastError("VLM model not loaded");
      throw std::runtime_error("VLMBridge: VLM model not loaded. Call loadVLMModel() first.");
    }

    // Parse options
    VLMOptions options;
    if (optionsJson.has_value()) {
      options.maxTokens = extractIntValue(*optionsJson, "max_tokens", 2048);
      options.temperature = extractFloatValue(*optionsJson, "temperature", 0.7f);
      options.topP = extractFloatValue(*optionsJson, "top_p", 0.9f);
    }

    // Build image input
    VLMImageInput imageInput = buildVLMImageInput(
      static_cast<int>(imageFormat),
      imageData,
      static_cast<int>(imageWidth),
      static_cast<int>(imageHeight)
    );

    RAC_LOG_DEBUG(VLM_LOG_CATEGORY, "Processing VLM image with prompt: %.50s...", prompt.c_str());

    try {
      auto result = VLMBridge::shared().process(imageInput, prompt, options);

      return buildJsonObject({
        {"text", jsonString(result.text)},
        {"promptTokens", std::to_string(result.promptTokens)},
        {"completionTokens", std::to_string(result.completionTokens)},
        {"totalTimeMs", std::to_string(result.totalTimeMs)},
        {"tokensPerSecond", std::to_string(result.tokensPerSecond)}
      });
    } catch (const std::exception& e) {
      setLastError(e.what());
      throw;
    }
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereLlama::processVLMImageStream(
    double imageFormat,
    const std::string& imageData,
    double imageWidth,
    double imageHeight,
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
  return Promise<std::string>::async([this, imageFormat, imageData, imageWidth, imageHeight, prompt, optionsJson, callback]() {
    if (!VLMBridge::shared().isLoaded()) {
      setLastError("VLM model not loaded");
      throw std::runtime_error("VLMBridge: VLM model not loaded. Call loadVLMModel() first.");
    }

    // Parse options
    VLMOptions options;
    options.maxTokens = extractIntValue(optionsJson, "max_tokens", 2048);
    options.temperature = extractFloatValue(optionsJson, "temperature", 0.7f);
    options.topP = extractFloatValue(optionsJson, "top_p", 0.9f);

    // Build image input
    VLMImageInput imageInput = buildVLMImageInput(
      static_cast<int>(imageFormat),
      imageData,
      static_cast<int>(imageWidth),
      static_cast<int>(imageHeight)
    );

    std::string fullResponse;
    std::string streamError;

    VLMStreamCallbacks streamCallbacks;
    streamCallbacks.onToken = [&callback, &fullResponse](const std::string& token) -> bool {
      fullResponse += token;
      if (callback) {
        callback(token, false);
      }
      return true;
    };
    streamCallbacks.onComplete = [&callback](const rac_vlm_result_t*) {
      if (callback) {
        callback("", true);
      }
    };
    streamCallbacks.onError = [this, &streamError](int code, const std::string& message) {
      setLastError(message);
      streamError = message;
    };

    try {
      VLMBridge::shared().processStream(imageInput, prompt, options, streamCallbacks);
    } catch (const std::exception& e) {
      setLastError(e.what());
      throw;
    }

    if (!streamError.empty()) {
      throw std::runtime_error("VLMBridge: Stream processing failed: " + streamError);
    }

    return fullResponse;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereLlama::cancelVLMGeneration() {
  return Promise<bool>::async([]() {
    VLMBridge::shared().cancel();
    return true;
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereLlama::setLastError(const std::string& error) {
  lastError_ = error;
  RAC_LOG_ERROR(LOG_CATEGORY, "Error: %s", error.c_str());
}

} // namespace margelo::nitro::runanywhere::llama
