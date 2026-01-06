/**
 * HybridRunAnywhereCore.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere Core SDK.
 *
 * Core-only implementation - includes only core functionality:
 * - SDK Lifecycle, Authentication, Device Registration
 * - Model Registry, Download Service, Storage
 * - Events, HTTP Client, Utilities
 *
 * NO LLM/STT/TTS/VAD/VoiceAgent methods - those are in:
 * - @runanywhere/llamacpp for text generation
 * - @runanywhere/onnx for speech processing
 */

#include "HybridRunAnywhereCore.hpp"

// Core bridges only (no LLM/STT/TTS/VAD bridges)
#include "bridges/PlatformAdapterBridge.hpp"
#include "bridges/InitBridge.hpp"
#include "bridges/StorageBridge.hpp"
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
#define LOG_TAG "HybridRunAnywhereCore"
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
// JSON Utilities
// ============================================================================

namespace {

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

HybridRunAnywhereCore::HybridRunAnywhereCore() : HybridObject(TAG) {
  LOGI("HybridRunAnywhereCore constructor - core-only module");
}

HybridRunAnywhereCore::~HybridRunAnywhereCore() {
  LOGI("HybridRunAnywhereCore destructor");

  // Cleanup core bridges only
  InitBridge::shared().shutdown();
  PlatformAdapterBridge::shared().shutdown();
}

// ============================================================================
// SDK Lifecycle - Delegates to InitBridge and PlatformAdapterBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initialize(
    const std::string& configJson) {
  return Promise<bool>::async([this, configJson]() {
    std::lock_guard<std::mutex> lock(initMutex_);

    LOGI("Initializing Core SDK with rac_* API...");

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

    LOGI("Core SDK initialized successfully");
    return true;
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::destroy() {
  return Promise<void>::async([this]() {
    std::lock_guard<std::mutex> lock(initMutex_);

    // Cleanup core bridges only
    EventBridge::shared().shutdown();
    InitBridge::shared().shutdown();
    PlatformAdapterBridge::shared().shutdown();

    StateBridge::shared().setState(SDKState::Uninitialized);

    LOGI("Core SDK destroyed");
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isInitialized() {
  return Promise<bool>::async([]() {
    return StateBridge::shared().isSDKInitialized();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getBackendInfo() {
  return Promise<std::string>::async([]() {
    return buildJsonObject({
      {"api", jsonString("rac_*")},
      {"source", jsonString("runanywhere-commons")},
      {"module", jsonString("core")}
    });
  });
}

// ============================================================================
// Authentication - Delegates to AuthBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::authenticate(
    const std::string& apiKey) {
  return Promise<bool>::async([apiKey]() {
    return AuthBridge::shared().authenticate(apiKey) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isAuthenticated() {
  return Promise<bool>::async([]() {
    return AuthBridge::shared().isAuthenticated();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getUserId() {
  return Promise<std::string>::async([]() {
    return AuthBridge::shared().getUserId();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getOrganizationId() {
  return Promise<std::string>::async([]() {
    return AuthBridge::shared().getOrganizationId();
  });
}

// ============================================================================
// Device Registration - Delegates to DeviceBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerDevice(
    const std::string& environmentJson) {
  return Promise<bool>::async([environmentJson]() {
    return DeviceBridge::shared().registerDevice(environmentJson) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isDeviceRegistered() {
  return Promise<bool>::async([]() {
    return DeviceBridge::shared().isRegistered();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDeviceId() {
  return Promise<std::string>::async([]() {
    return DeviceBridge::shared().getDeviceId();
  });
}

// ============================================================================
// Model Registry - Delegates to ModelRegistryBridge
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getAvailableModels() {
  return Promise<std::string>::async([]() {
    return ModelRegistryBridge::shared().getAvailableModelsJson();
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelInfo(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    return ModelRegistryBridge::shared().getModelInfoJson(modelId);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isModelDownloaded(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return ModelRegistryBridge::shared().isModelDownloaded(modelId);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelPath(
    const std::string& modelId) {
  return Promise<std::string>::async([modelId]() {
    return ModelRegistryBridge::shared().getModelPath(modelId);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerModel(
    const std::string& modelJson) {
  return Promise<bool>::async([modelJson]() {
    return ModelRegistryBridge::shared().registerModel(modelJson);
  });
}

// ============================================================================
// Download Service - Delegates to DownloadBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::downloadModel(
    const std::string& modelId,
    const std::string& url,
    const std::string& destPath) {
  return Promise<bool>::async([modelId, url, destPath]() {
    return DownloadBridge::shared().startDownload(modelId, url, destPath) == 0;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelDownload(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return DownloadBridge::shared().cancelDownload(modelId);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDownloadProgress(
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
// Storage - Delegates to StorageBridge
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getStorageInfo() {
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

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearCache() {
  return Promise<bool>::async([]() {
    return StorageBridge::shared().clearCache();
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::deleteModel(
    const std::string& modelId) {
  return Promise<bool>::async([modelId]() {
    return StorageBridge::shared().deleteModel(modelId);
  });
}

// ============================================================================
// Events - Delegates to EventBridge
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::emitEvent(
    const std::string& eventJson) {
  return Promise<void>::async([eventJson]() {
    EventBridge::shared().emit(eventJson);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pollEvents() {
  return Promise<std::string>::async([]() {
    return EventBridge::shared().poll();
  });
}

// ============================================================================
// HTTP Client - Delegates to HTTPBridge
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::configureHttp(
    const std::string& baseUrl,
    const std::string& apiKey) {
  return Promise<bool>::async([baseUrl, apiKey]() {
    return HTTPBridge::shared().configure(baseUrl, apiKey) == 0;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::httpPost(
    const std::string& path,
    const std::string& bodyJson) {
  return Promise<std::string>::async([path, bodyJson]() {
    return HTTPBridge::shared().post(path, bodyJson);
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::httpGet(
    const std::string& path) {
  return Promise<std::string>::async([path]() {
    return HTTPBridge::shared().get(path);
  });
}

// ============================================================================
// Utility Functions
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getLastError() {
  return Promise<std::string>::async([this]() { return lastError_; });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::extractArchive(
    const std::string& archivePath,
    const std::string& destPath) {
  return Promise<bool>::async([archivePath, destPath]() {
    // TODO: Implement via platform adapter
    LOGI("extractArchive: %s -> %s", archivePath.c_str(), destPath.c_str());
    return false;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDeviceCapabilities() {
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
        {"api", jsonString("rac_*")},
        {"module", jsonString("core")}
    });
  });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getMemoryUsage() {
  return Promise<double>::async([]() {
    // TODO: Get memory usage from commons
    return 0.0;
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereCore::setLastError(const std::string& error) {
  lastError_ = error;
  LOGE("Error: %s", error.c_str());
}

} // namespace margelo::nitro::runanywhere
