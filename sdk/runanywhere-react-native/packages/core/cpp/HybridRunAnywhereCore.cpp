/**
 * HybridRunAnywhereCore.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere Core SDK.
 *
 * Core SDK implementation - includes:
 * - SDK Lifecycle, Authentication, Device Registration
 * - Model Registry, Download Service, Storage
 * - Events, HTTP Client, Utilities
 * - LLM/STT/TTS/VAD/VoiceAgent capabilities (backend-agnostic)
 *
 * The capability methods (LLM, STT, TTS, VAD, VoiceAgent) are BACKEND-AGNOSTIC.
 * They call the C++ rac_*_component_* APIs which work with any registered backend.
 * Apps must install a backend package to register the actual implementation:
 * - @runanywhere/llamacpp registers the LLM backend via rac_backend_llamacpp_register()
 * - @runanywhere/onnx registers the STT/TTS/VAD backends via rac_backend_onnx_register()
 *
 * Mirrors Swift's CppBridge architecture from:
 * sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/
 */

#include "HybridRunAnywhereCore.hpp"

// Core bridges - aligned with actual RACommons API
#include "bridges/InitBridge.hpp"
#include "bridges/DeviceBridge.hpp"
#include "bridges/AuthBridge.hpp"
#include "bridges/StorageBridge.hpp"
#include "bridges/ModelRegistryBridge.hpp"
#include "bridges/EventBridge.hpp"
#include "bridges/HTTPBridge.hpp"
#include "bridges/DownloadBridge.hpp"

// RACommons C API headers for capability methods
// These are backend-agnostic - they work with any registered backend
#include "rac_core.h"
#include "rac_llm_component.h"
#include "rac_llm_types.h"
#include "rac_stt_component.h"
#include "rac_stt_types.h"
#include "rac_tts_component.h"
#include "rac_tts_types.h"
#include "rac_vad_component.h"
#include "rac_vad_types.h"
#include "rac_types.h"

#include <sstream>
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
#define LOGI(...) printf("[HybridRunAnywhereCore] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[HybridRunAnywhereCore ERROR] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[HybridRunAnywhereCore DEBUG] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace margelo::nitro::runanywhere {

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
    // Skip if this is a string value (starts with quote)
    if (json[pos] == '"') return defaultValue;
    // Try to parse as integer, return default on failure
    try {
        return std::stoi(json.substr(pos));
    } catch (...) {
        return defaultValue;
    }
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

bool extractBoolValue(const std::string& json, const std::string& key, bool defaultValue = false) {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.size()) return defaultValue;
    if (json.substr(pos, 4) == "true") return true;
    if (json.substr(pos, 5) == "false") return false;
    return defaultValue;
}

// Convert TypeScript framework string to C++ enum
rac_inference_framework_t frameworkFromString(const std::string& framework) {
    if (framework == "LlamaCpp" || framework == "llamacpp") return RAC_FRAMEWORK_LLAMACPP;
    if (framework == "ONNX" || framework == "onnx") return RAC_FRAMEWORK_ONNX;
    if (framework == "FoundationModels") return RAC_FRAMEWORK_FOUNDATION_MODELS;
    if (framework == "SystemTTS") return RAC_FRAMEWORK_SYSTEM_TTS;
    return RAC_FRAMEWORK_UNKNOWN;
}

// Convert TypeScript category string to C++ enum
rac_model_category_t categoryFromString(const std::string& category) {
    if (category == "Language" || category == "language") return RAC_MODEL_CATEGORY_LANGUAGE;
    // Handle both hyphen and underscore variants
    if (category == "SpeechRecognition" || category == "speech-recognition" || category == "speech_recognition") return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
    if (category == "SpeechSynthesis" || category == "speech-synthesis" || category == "speech_synthesis") return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
    if (category == "VoiceActivity" || category == "voice-activity" || category == "voice_activity") return RAC_MODEL_CATEGORY_AUDIO;
    if (category == "Vision" || category == "vision") return RAC_MODEL_CATEGORY_VISION;
    if (category == "ImageGeneration" || category == "image-generation" || category == "image_generation") return RAC_MODEL_CATEGORY_IMAGE_GENERATION;
    if (category == "Multimodal" || category == "multimodal") return RAC_MODEL_CATEGORY_MULTIMODAL;
    if (category == "Audio" || category == "audio") return RAC_MODEL_CATEGORY_AUDIO;
    return RAC_MODEL_CATEGORY_UNKNOWN;
}

// Convert TypeScript format string to C++ enum
rac_model_format_t formatFromString(const std::string& format) {
    if (format == "GGUF" || format == "gguf") return RAC_MODEL_FORMAT_GGUF;
    if (format == "GGML" || format == "ggml") return RAC_MODEL_FORMAT_BIN;  // GGML -> BIN as fallback
    if (format == "ONNX" || format == "onnx") return RAC_MODEL_FORMAT_ONNX;
    if (format == "ORT" || format == "ort") return RAC_MODEL_FORMAT_ORT;
    if (format == "BIN" || format == "bin") return RAC_MODEL_FORMAT_BIN;
    return RAC_MODEL_FORMAT_UNKNOWN;
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

std::string buildJsonObject(const std::vector<std::pair<std::string, std::string>>& keyValues) {
    std::string result = "{";
    for (size_t i = 0; i < keyValues.size(); i++) {
        if (i > 0) result += ",";
        result += "\"" + keyValues[i].first + "\":" + keyValues[i].second;
    }
    result += "}";
    return result;
}

} // anonymous namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereCore::HybridRunAnywhereCore() : HybridObject(TAG) {
    LOGI("HybridRunAnywhereCore constructor - core module");
}

HybridRunAnywhereCore::~HybridRunAnywhereCore() {
    LOGI("HybridRunAnywhereCore destructor");

    // Cleanup bridges
    EventBridge::shared().unregisterFromEvents();
    DownloadBridge::shared().shutdown();
    StorageBridge::shared().shutdown();
    ModelRegistryBridge::shared().shutdown();
    InitBridge::shared().shutdown();
}

// ============================================================================
// SDK Lifecycle
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initialize(
    const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Initializing Core SDK...");

        // Parse config
        std::string apiKey = extractStringValue(configJson, "apiKey");
        std::string baseURL = extractStringValue(configJson, "baseURL", "https://api.runanywhere.ai");
        std::string deviceId = extractStringValue(configJson, "deviceId");
        std::string envStr = extractStringValue(configJson, "environment", "production");

        // Determine environment
        SDKEnvironment env = SDKEnvironment::Production;
        if (envStr == "development") env = SDKEnvironment::Development;
        else if (envStr == "staging") env = SDKEnvironment::Staging;

        // 1. Initialize core (platform adapter + state)
        rac_result_t result = InitBridge::shared().initialize(env, apiKey, baseURL, deviceId);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to initialize SDK core: " + std::to_string(result));
            return false;
        }

        // 2. Set base directory for model paths (mirrors Swift's CppBridge.ModelPaths.setBaseDirectory)
        // This must be called before using model path utilities
        std::string documentsPath = extractStringValue(configJson, "documentsPath");
        if (!documentsPath.empty()) {
            result = InitBridge::shared().setBaseDirectory(documentsPath);
            if (result != RAC_SUCCESS) {
                LOGE("Failed to set base directory: %d", result);
                // Continue - not fatal, but model paths may not work correctly
            }
        } else {
            LOGE("documentsPath not provided in config - model paths may not work correctly!");
        }

        // 3. Initialize model registry
        result = ModelRegistryBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize model registry: %d", result);
            // Continue - not fatal
        }

        // 4. Initialize storage analyzer
        result = StorageBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize storage analyzer: %d", result);
            // Continue - not fatal
        }

        // 5. Initialize download manager
        result = DownloadBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize download manager: %d", result);
            // Continue - not fatal
        }

        // 6. Register for events
        EventBridge::shared().registerForEvents();

        // 7. Configure HTTP
        HTTPBridge::shared().configure(baseURL, apiKey);

        LOGI("Core SDK initialized successfully");
        return true;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::destroy() {
    return Promise<void>::async([this]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Destroying Core SDK...");

        // Cleanup in reverse order
        EventBridge::shared().unregisterFromEvents();
        DownloadBridge::shared().shutdown();
        StorageBridge::shared().shutdown();
        ModelRegistryBridge::shared().shutdown();
        InitBridge::shared().shutdown();

        LOGI("Core SDK destroyed");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isInitialized() {
    return Promise<bool>::async([]() {
        return InitBridge::shared().isInitialized();
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
// Authentication
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::authenticate(
    const std::string& apiKey) {
    return Promise<bool>::async([this, apiKey]() -> bool {
        LOGI("Authenticating...");

        // Build auth request JSON
        std::string deviceId = DeviceBridge::shared().getDeviceId();
        std::string platform = "react-native";
        std::string sdkVersion = "0.1.0"; // TODO: Get from config

        std::string requestJson = AuthBridge::shared().buildAuthenticateRequestJSON(
            apiKey, deviceId, platform, sdkVersion
        );

        if (requestJson.empty()) {
            setLastError("Failed to build auth request");
            return false;
        }

        // NOTE: HTTP request must be made by JS layer
        // This C++ method just prepares the request JSON
        // The JS layer should:
        // 1. Call this method to prepare
        // 2. Make HTTP POST to /api/v1/auth/sdk/authenticate
        // 3. Call handleAuthResponse() with the response

        // For now, we indicate that auth JSON is prepared
        LOGI("Auth request JSON prepared. HTTP must be done by JS layer.");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isAuthenticated() {
    return Promise<bool>::async([]() -> bool {
        return AuthBridge::shared().isAuthenticated();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getUserId() {
    return Promise<std::string>::async([]() -> std::string {
        return AuthBridge::shared().getUserId();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getOrganizationId() {
    return Promise<std::string>::async([]() -> std::string {
        return AuthBridge::shared().getOrganizationId();
    });
}

// ============================================================================
// Device Registration
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerDevice(
    const std::string& environmentJson) {
    return Promise<bool>::async([this, environmentJson]() -> bool {
        LOGI("Registering device...");

        // Parse environment
        std::string envStr = extractStringValue(environmentJson, "environment", "production");
        rac_environment_t env = RAC_ENV_PRODUCTION;
        if (envStr == "development") env = RAC_ENV_DEVELOPMENT;
        else if (envStr == "staging") env = RAC_ENV_STAGING;

        std::string buildToken = extractStringValue(environmentJson, "buildToken", "");

        // Register callbacks first
        rac_result_t result = DeviceBridge::shared().registerCallbacks();
        if (result != RAC_SUCCESS) {
            setLastError("Failed to register device callbacks: " + std::to_string(result));
            return false;
        }

        // Now register device
        result = DeviceBridge::shared().registerIfNeeded(env, buildToken);
        if (result != RAC_SUCCESS) {
            setLastError("Device registration failed: " + std::to_string(result));
            return false;
        }

        LOGI("Device registered successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isDeviceRegistered() {
    return Promise<bool>::async([]() -> bool {
        return DeviceBridge::shared().isRegistered();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDeviceId() {
    return Promise<std::string>::async([]() -> std::string {
        return DeviceBridge::shared().getDeviceId();
    });
}

// ============================================================================
// Model Registry
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getAvailableModels() {
    return Promise<std::string>::async([]() -> std::string {
        auto models = ModelRegistryBridge::shared().getAllModels();

        LOGI("getAvailableModels: Building JSON for %zu models", models.size());

        std::string result = "[";
        for (size_t i = 0; i < models.size(); i++) {
            if (i > 0) result += ",";
            const auto& m = models[i];
            // Convert C++ enum values to TypeScript string values for compatibility
            std::string categoryStr = "unknown";
            switch (m.category) {
                case RAC_MODEL_CATEGORY_LANGUAGE: categoryStr = "language"; break;
                case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION: categoryStr = "speech-recognition"; break;
                case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS: categoryStr = "speech-synthesis"; break;
                case RAC_MODEL_CATEGORY_VISION: categoryStr = "vision"; break;
                case RAC_MODEL_CATEGORY_AUDIO: categoryStr = "audio"; break;
                case RAC_MODEL_CATEGORY_MULTIMODAL: categoryStr = "multimodal"; break;
                default: categoryStr = "unknown"; break;
            }
            std::string formatStr = "unknown";
            switch (m.format) {
                case RAC_MODEL_FORMAT_GGUF: formatStr = "gguf"; break;
                case RAC_MODEL_FORMAT_ONNX: formatStr = "onnx"; break;
                case RAC_MODEL_FORMAT_ORT: formatStr = "ort"; break;
                case RAC_MODEL_FORMAT_BIN: formatStr = "bin"; break;
                default: formatStr = "unknown"; break;
            }
            std::string frameworkStr = "unknown";
            switch (m.framework) {
                case RAC_FRAMEWORK_LLAMACPP: frameworkStr = "LlamaCpp"; break;
                case RAC_FRAMEWORK_ONNX: frameworkStr = "ONNX"; break;
                case RAC_FRAMEWORK_FOUNDATION_MODELS: frameworkStr = "FoundationModels"; break;
                case RAC_FRAMEWORK_SYSTEM_TTS: frameworkStr = "SystemTTS"; break;
                default: frameworkStr = "unknown"; break;
            }

            result += buildJsonObject({
                {"id", jsonString(m.id)},
                {"name", jsonString(m.name)},
                {"localPath", jsonString(m.localPath)},
                {"downloadURL", jsonString(m.downloadUrl)},  // TypeScript uses capital U
                {"category", jsonString(categoryStr)},       // String for TypeScript
                {"format", jsonString(formatStr)},           // String for TypeScript
                {"preferredFramework", jsonString(frameworkStr)}, // String for TypeScript
                {"downloadSize", std::to_string(m.downloadSize)},
                {"memoryRequired", std::to_string(m.memoryRequired)},
                {"supportsThinking", m.supportsThinking ? "true" : "false"},
                {"isDownloaded", m.isDownloaded ? "true" : "false"},
                {"isAvailable", "true"}  // Models in registry are available
            });
        }
        result += "]";

        LOGD("getAvailableModels: JSON length=%zu", result.length());

        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelInfo(
    const std::string& modelId) {
    return Promise<std::string>::async([modelId]() -> std::string {
        auto model = ModelRegistryBridge::shared().getModel(modelId);
        if (!model.has_value()) {
            return "{}";
        }

        const auto& m = model.value();

        // Convert enums to strings (same as getAvailableModels)
        std::string categoryStr = "unknown";
        switch (m.category) {
            case RAC_MODEL_CATEGORY_LANGUAGE: categoryStr = "language"; break;
            case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION: categoryStr = "speech-recognition"; break;
            case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS: categoryStr = "speech-synthesis"; break;
            case RAC_MODEL_CATEGORY_AUDIO: categoryStr = "audio"; break;
            case RAC_MODEL_CATEGORY_VISION: categoryStr = "vision"; break;
            case RAC_MODEL_CATEGORY_IMAGE_GENERATION: categoryStr = "image-generation"; break;
            case RAC_MODEL_CATEGORY_MULTIMODAL: categoryStr = "multimodal"; break;
            default: categoryStr = "unknown"; break;
        }
        std::string formatStr = "unknown";
        switch (m.format) {
            case RAC_MODEL_FORMAT_GGUF: formatStr = "gguf"; break;
            case RAC_MODEL_FORMAT_ONNX: formatStr = "onnx"; break;
            case RAC_MODEL_FORMAT_ORT: formatStr = "ort"; break;
            case RAC_MODEL_FORMAT_BIN: formatStr = "bin"; break;
            default: formatStr = "unknown"; break;
        }
        std::string frameworkStr = "unknown";
        switch (m.framework) {
            case RAC_FRAMEWORK_LLAMACPP: frameworkStr = "LlamaCpp"; break;
            case RAC_FRAMEWORK_ONNX: frameworkStr = "ONNX"; break;
            case RAC_FRAMEWORK_FOUNDATION_MODELS: frameworkStr = "FoundationModels"; break;
            case RAC_FRAMEWORK_SYSTEM_TTS: frameworkStr = "SystemTTS"; break;
            default: frameworkStr = "unknown"; break;
        }

        return buildJsonObject({
            {"id", jsonString(m.id)},
            {"name", jsonString(m.name)},
            {"description", jsonString(m.description)},
            {"localPath", jsonString(m.localPath)},
            {"downloadURL", jsonString(m.downloadUrl)},  // Fixed: downloadURL (capital URL) to match TypeScript
            {"category", jsonString(categoryStr)},       // String for TypeScript
            {"format", jsonString(formatStr)},           // String for TypeScript
            {"preferredFramework", jsonString(frameworkStr)}, // String for TypeScript (preferredFramework key)
            {"downloadSize", std::to_string(m.downloadSize)},
            {"memoryRequired", std::to_string(m.memoryRequired)},
            {"contextLength", std::to_string(m.contextLength)},
            {"supportsThinking", m.supportsThinking ? "true" : "false"},
            {"isDownloaded", m.isDownloaded ? "true" : "false"},
            {"isAvailable", "true"}  // Added isAvailable field
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isModelDownloaded(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() -> bool {
        return ModelRegistryBridge::shared().isModelDownloaded(modelId);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelPath(
    const std::string& modelId) {
    return Promise<std::string>::async([modelId]() -> std::string {
        auto path = ModelRegistryBridge::shared().getModelPath(modelId);
        return path.value_or("");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerModel(
    const std::string& modelJson) {
    return Promise<bool>::async([modelJson]() -> bool {
        LOGI("Registering model from JSON: %.200s", modelJson.c_str());

        ModelInfo model;
        model.id = extractStringValue(modelJson, "id");
        model.name = extractStringValue(modelJson, "name");
        model.description = extractStringValue(modelJson, "description");
        model.localPath = extractStringValue(modelJson, "localPath");

        // Support both TypeScript naming (downloadURL) and C++ naming (downloadUrl)
        model.downloadUrl = extractStringValue(modelJson, "downloadURL");
        if (model.downloadUrl.empty()) {
            model.downloadUrl = extractStringValue(modelJson, "downloadUrl");
        }

        model.downloadSize = extractIntValue(modelJson, "downloadSize", 0);
        model.memoryRequired = extractIntValue(modelJson, "memoryRequired", 0);
        model.contextLength = extractIntValue(modelJson, "contextLength", 0);
        model.supportsThinking = extractBoolValue(modelJson, "supportsThinking", false);

        // Handle category - could be string (TypeScript) or int
        std::string categoryStr = extractStringValue(modelJson, "category");
        if (!categoryStr.empty()) {
            model.category = categoryFromString(categoryStr);
        } else {
            model.category = static_cast<rac_model_category_t>(extractIntValue(modelJson, "category", RAC_MODEL_CATEGORY_UNKNOWN));
        }

        // Handle format - could be string (TypeScript) or int
        std::string formatStr = extractStringValue(modelJson, "format");
        if (!formatStr.empty()) {
            model.format = formatFromString(formatStr);
        } else {
            model.format = static_cast<rac_model_format_t>(extractIntValue(modelJson, "format", RAC_MODEL_FORMAT_UNKNOWN));
        }

        // Handle framework - prefer string extraction for TypeScript compatibility
        std::string frameworkStr = extractStringValue(modelJson, "preferredFramework");
        if (!frameworkStr.empty()) {
            model.framework = frameworkFromString(frameworkStr);
        } else {
            frameworkStr = extractStringValue(modelJson, "framework");
            if (!frameworkStr.empty()) {
                model.framework = frameworkFromString(frameworkStr);
            } else {
                model.framework = static_cast<rac_inference_framework_t>(extractIntValue(modelJson, "preferredFramework", RAC_FRAMEWORK_UNKNOWN));
            }
        }

        LOGI("Registering model: id=%s, name=%s, framework=%d, category=%d",
             model.id.c_str(), model.name.c_str(), model.framework, model.category);

        rac_result_t result = ModelRegistryBridge::shared().addModel(model);

        if (result == RAC_SUCCESS) {
            LOGI("✅ Model registered successfully: %s", model.id.c_str());
        } else {
            LOGE("❌ Model registration failed: %s, result=%d", model.id.c_str(), result);
        }

        return result == RAC_SUCCESS;
    });
}

// ============================================================================
// Download Service
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::downloadModel(
    const std::string& modelId,
    const std::string& url,
    const std::string& destPath) {
    return Promise<bool>::async([this, modelId, url, destPath]() -> bool {
        LOGI("Starting download: %s", modelId.c_str());

        std::string taskId = DownloadBridge::shared().startDownload(
            modelId, url, destPath, false,  // requiresExtraction
            [](const DownloadProgress& progress) {
                LOGD("Download progress: %.1f%%", progress.overallProgress * 100);
            }
        );

        if (taskId.empty()) {
            setLastError("Failed to start download");
            return false;
        }

        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelDownload(
    const std::string& taskId) {
    return Promise<bool>::async([taskId]() -> bool {
        rac_result_t result = DownloadBridge::shared().cancelDownload(taskId);
        return result == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getDownloadProgress(
    const std::string& taskId) {
    return Promise<std::string>::async([taskId]() -> std::string {
        auto progress = DownloadBridge::shared().getProgress(taskId);
        if (!progress.has_value()) {
            return "{}";
        }

        const auto& p = progress.value();
        std::string stateStr;
        switch (p.state) {
            case DownloadState::Pending: stateStr = "pending"; break;
            case DownloadState::Downloading: stateStr = "downloading"; break;
            case DownloadState::Extracting: stateStr = "extracting"; break;
            case DownloadState::Retrying: stateStr = "retrying"; break;
            case DownloadState::Completed: stateStr = "completed"; break;
            case DownloadState::Failed: stateStr = "failed"; break;
            case DownloadState::Cancelled: stateStr = "cancelled"; break;
        }

        return buildJsonObject({
            {"bytesDownloaded", std::to_string(p.bytesDownloaded)},
            {"totalBytes", std::to_string(p.totalBytes)},
            {"overallProgress", std::to_string(p.overallProgress)},
            {"stageProgress", std::to_string(p.stageProgress)},
            {"state", jsonString(stateStr)},
            {"speed", std::to_string(p.speed)},
            {"estimatedTimeRemaining", std::to_string(p.estimatedTimeRemaining)},
            {"retryAttempt", std::to_string(p.retryAttempt)},
            {"errorCode", std::to_string(p.errorCode)},
            {"errorMessage", jsonString(p.errorMessage)}
        });
    });
}

// ============================================================================
// Storage
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getStorageInfo() {
    return Promise<std::string>::async([]() {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        auto info = StorageBridge::shared().analyzeStorage(registryHandle);

        return buildJsonObject({
            {"totalDeviceSpace", std::to_string(info.deviceStorage.totalSpace)},
            {"freeDeviceSpace", std::to_string(info.deviceStorage.freeSpace)},
            {"usedDeviceSpace", std::to_string(info.deviceStorage.usedSpace)},
            {"documentsSize", std::to_string(info.appStorage.documentsSize)},
            {"cacheSize", std::to_string(info.appStorage.cacheSize)},
            {"appSupportSize", std::to_string(info.appStorage.appSupportSize)},
            {"totalAppSize", std::to_string(info.appStorage.totalSize)},
            {"totalModelsSize", std::to_string(info.totalModelsSize)},
            {"modelCount", std::to_string(info.models.size())}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearCache() {
    return Promise<bool>::async([]() {
        // TODO: Implement cache clearing via storage bridge
        LOGI("Clearing cache...");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::deleteModel(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() {
        LOGI("Deleting model: %s", modelId.c_str());
        rac_result_t result = ModelRegistryBridge::shared().removeModel(modelId);
        return result == RAC_SUCCESS;
    });
}

// ============================================================================
// Events
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::emitEvent(
    const std::string& eventJson) {
    return Promise<void>::async([eventJson]() -> void {
        std::string type = extractStringValue(eventJson, "type");
        std::string categoryStr = extractStringValue(eventJson, "category", "sdk");

        EventCategory category = EventCategory::SDK;
        if (categoryStr == "model") category = EventCategory::Model;
        else if (categoryStr == "llm") category = EventCategory::LLM;
        else if (categoryStr == "stt") category = EventCategory::STT;
        else if (categoryStr == "tts") category = EventCategory::TTS;

        EventBridge::shared().trackEvent(type, category, EventDestination::All, eventJson);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pollEvents() {
    // Events are push-based via callback, not polling
    return Promise<std::string>::async([]() -> std::string {
        return "[]";
    });
}

// ============================================================================
// HTTP Client
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::configureHttp(
    const std::string& baseUrl,
    const std::string& apiKey) {
    return Promise<bool>::async([baseUrl, apiKey]() -> bool {
        HTTPBridge::shared().configure(baseUrl, apiKey);
        return HTTPBridge::shared().isConfigured();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::httpPost(
    const std::string& path,
    const std::string& bodyJson) {
    return Promise<std::string>::async([this, path, bodyJson]() -> std::string {
        // HTTP is handled by JS layer
        // This returns URL for JS to use
        std::string url = HTTPBridge::shared().buildURL(path);

        // Try to use registered executor if available
        auto response = HTTPBridge::shared().execute("POST", path, bodyJson, true);
        if (response.has_value()) {
            if (response->success) {
                return response->body;
            } else {
                throw std::runtime_error(response->error);
            }
        }

        // No executor - return error indicating HTTP must be done by JS
        throw std::runtime_error("HTTP executor not registered. Use JS layer for HTTP requests.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::httpGet(
    const std::string& path) {
    return Promise<std::string>::async([this, path]() -> std::string {
        auto response = HTTPBridge::shared().execute("GET", path, "", true);
        if (response.has_value()) {
            if (response->success) {
                return response->body;
            } else {
                throw std::runtime_error(response->error);
            }
        }

        throw std::runtime_error("HTTP executor not registered. Use JS layer for HTTP requests.");
    });
}

// ============================================================================
// Utility Functions
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getLastError() {
    return Promise<std::string>::async([this]() { return lastError_; });
}

// Forward declaration for platform-specific archive extraction
#if defined(__APPLE__)
extern "C" bool ArchiveUtility_extract(const char* archivePath, const char* destinationPath);
#elif defined(__ANDROID__)
// On Android, we'll call the Kotlin ArchiveUtility via JNI in a separate helper
extern "C" bool ArchiveUtility_extractAndroid(const char* archivePath, const char* destinationPath);
#endif

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::extractArchive(
    const std::string& archivePath,
    const std::string& destPath) {
    return Promise<bool>::async([this, archivePath, destPath]() {
        LOGI("extractArchive: %s -> %s", archivePath.c_str(), destPath.c_str());

#if defined(__APPLE__)
        // iOS: Call Swift ArchiveUtility
        bool success = ArchiveUtility_extract(archivePath.c_str(), destPath.c_str());
        if (success) {
            LOGI("iOS archive extraction succeeded");
            return true;
        } else {
            LOGE("iOS archive extraction failed");
            setLastError("Archive extraction failed");
            return false;
        }
#elif defined(__ANDROID__)
        // Android: Call Kotlin ArchiveUtility via JNI
        bool success = ArchiveUtility_extractAndroid(archivePath.c_str(), destPath.c_str());
        if (success) {
            LOGI("Android archive extraction succeeded");
            return true;
        } else {
            LOGE("Android archive extraction failed");
            setLastError("Archive extraction failed");
            return false;
        }
#else
        LOGW("Archive extraction not supported on this platform");
        setLastError("Archive extraction not supported");
        return false;
#endif
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
        // TODO: Get memory usage from platform
        return 0.0;
    });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereCore::setLastError(const std::string& error) {
    lastError_ = error;
    LOGE("%s", error.c_str());
}

// ============================================================================
// LLM Capability (Backend-Agnostic)
// Calls rac_llm_component_* APIs - works with any registered backend
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTextModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, configJson]() -> bool {
        LOGI("Loading text model: %s", modelPath.c_str());

        // Create LLM component if needed
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to create LLM component. Is an LLM backend registered?");
            throw std::runtime_error("LLM backend not registered. Install @runanywhere/llamacpp.");
        }

        // Load the model
        result = rac_llm_component_load_model(handle, modelPath.c_str(), modelPath.c_str(), modelPath.c_str());
        if (result != RAC_SUCCESS) {
            setLastError("Failed to load model: " + std::to_string(result));
            throw std::runtime_error("Failed to load text model: " + std::to_string(result));
        }

        LOGI("Text model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTextModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        return rac_llm_component_is_loaded(handle) == RAC_TRUE;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTextModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        rac_llm_component_cleanup(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, prompt, optionsJson]() -> std::string {
        LOGI("Generating text...");

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Parse options
        int maxTokens = 256;
        float temperature = 0.7f;
        if (optionsJson.has_value()) {
            maxTokens = extractIntValue(optionsJson.value(), "max_tokens", 256);
            temperature = static_cast<float>(extractIntValue(optionsJson.value(), "temperature", 7)) / 10.0f;
        }

        rac_llm_options_t options = {};
        options.max_tokens = maxTokens;
        options.temperature = temperature;
        options.top_p = 0.9f;

        rac_llm_result_t llmResult = {};
        result = rac_llm_component_generate(handle, prompt.c_str(), &options, &llmResult);

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Text generation failed: " + std::to_string(result));
        }

        std::string text = llmResult.text ? llmResult.text : "";
        int tokensUsed = llmResult.completion_tokens;

        return buildJsonObject({
            {"text", jsonString(text)},
            {"tokensUsed", std::to_string(tokensUsed)},
            {"modelUsed", jsonString("llm")},
            {"latencyMs", std::to_string(llmResult.total_time_ms)}
        });
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
    return Promise<std::string>::async([this, prompt, optionsJson, callback]() -> std::string {
        LOGI("Streaming text generation...");

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // For now, use non-streaming and call callback once
        // TODO: Implement proper streaming with rac_llm_component_generate_stream
        rac_llm_options_t options = {};
        options.max_tokens = extractIntValue(optionsJson, "max_tokens", 256);
        options.temperature = 0.7f;

        rac_llm_result_t llmResult = {};
        result = rac_llm_component_generate(handle, prompt.c_str(), &options, &llmResult);

        std::string text = llmResult.text ? llmResult.text : "";

        if (result == RAC_SUCCESS) {
            // Call callback with full text and completion flag
            if (callback) {
                callback(text, true);
            }
        }

        return buildJsonObject({
            {"text", jsonString(text)},
            {"tokensUsed", std::to_string(llmResult.completion_tokens)}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelGeneration() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_llm_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        rac_llm_component_cancel(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generateStructured(
    const std::string& prompt,
    const std::string& schema,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, prompt, schema]() -> std::string {
        LOGI("Generating structured output...");
        // TODO: Implement structured output generation
        throw std::runtime_error("Structured output not yet implemented in core. Use @runanywhere/llamacpp.");
    });
}

// ============================================================================
// STT Capability (Backend-Agnostic)
// Calls rac_stt_component_* APIs - works with any registered backend
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadSTTModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        LOGI("Loading STT model: %s", modelPath.c_str());

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_stt_component_create(&handle);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to create STT component. Is an STT backend registered?");
            throw std::runtime_error("STT backend not registered. Install @runanywhere/onnx.");
        }

        result = rac_stt_component_load_model(handle, modelPath.c_str(), modelPath.c_str(), modelType.c_str());
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to load STT model: " + std::to_string(result));
        }

        LOGI("STT model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isSTTModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_stt_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        return rac_stt_component_is_loaded(handle) == RAC_TRUE;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadSTTModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_stt_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        rac_stt_component_cleanup(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribe(
    const std::string& audioBase64,
    double sampleRate,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, audioBase64, sampleRate, language]() -> std::string {
        LOGI("Transcribing audio...");

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_stt_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            throw std::runtime_error("STT component not available. Is an STT backend registered?");
        }

        if (rac_stt_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No STT model loaded. Call loadSTTModel first.");
        }

        // TODO: Decode base64 and transcribe
        // For now, throw indicating full implementation needed
        throw std::runtime_error("STT transcription not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, filePath, language]() -> std::string {
        LOGI("Transcribing file: %s", filePath.c_str());

        // TODO: Implement file transcription
        throw std::runtime_error("STT file transcription not fully implemented in core. Use @runanywhere/onnx.");
    });
}

// ============================================================================
// TTS Capability (Backend-Agnostic)
// Calls rac_tts_component_* APIs - works with any registered backend
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTTSModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        LOGI("Loading TTS model: %s", modelPath.c_str());

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_tts_component_create(&handle);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to create TTS component. Is a TTS backend registered?");
            throw std::runtime_error("TTS backend not registered. Install @runanywhere/onnx.");
        }

        // TTS uses configure instead of load_model
        rac_tts_config_t config = RAC_TTS_CONFIG_DEFAULT;
        config.model_id = modelPath.c_str();
        result = rac_tts_component_configure(handle, &config);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to load TTS model: " + std::to_string(result));
        }

        LOGI("TTS model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTTSModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_tts_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        return rac_tts_component_is_loaded(handle) == RAC_TRUE;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTTSModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_tts_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        rac_tts_component_cleanup(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::synthesize(
    const std::string& text,
    const std::string& voiceId,
    double speedRate,
    double pitchShift) {
    return Promise<std::string>::async([this, text, voiceId, speedRate, pitchShift]() -> std::string {
        LOGI("Synthesizing speech: %s", text.substr(0, 50).c_str());

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_tts_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            throw std::runtime_error("TTS component not available. Is a TTS backend registered?");
        }

        if (rac_tts_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No TTS model loaded. Call loadTTSModel first.");
        }

        // TODO: Implement synthesis and return base64 audio
        throw std::runtime_error("TTS synthesis not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getTTSVoices() {
    return Promise<std::string>::async([]() -> std::string {
        return "[]"; // Return empty array for now
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelTTS() {
    return Promise<bool>::async([]() -> bool {
        return true;
    });
}

// ============================================================================
// VAD Capability (Backend-Agnostic)
// Calls rac_vad_component_* APIs - works with any registered backend
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadVADModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath]() -> bool {
        LOGI("Loading VAD model: %s", modelPath.c_str());

        rac_handle_t handle = nullptr;
        rac_result_t result = rac_vad_component_create(&handle);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to create VAD component. Is a VAD backend registered?");
            throw std::runtime_error("VAD backend not registered. Install @runanywhere/onnx.");
        }

        rac_vad_config_t config = RAC_VAD_CONFIG_DEFAULT;
        config.model_id = modelPath.c_str();
        result = rac_vad_component_configure(handle, &config);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to configure VAD: " + std::to_string(result));
        }

        result = rac_vad_component_initialize(handle);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to initialize VAD: " + std::to_string(result));
        }

        LOGI("VAD model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVADModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_vad_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        return rac_vad_component_is_initialized(handle) == RAC_TRUE;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadVADModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_vad_component_create(&handle);
        if (result != RAC_SUCCESS || !handle) {
            return false;
        }
        rac_vad_component_cleanup(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVAD(
    const std::string& audioBase64,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        LOGI("Processing VAD...");

        // TODO: Implement VAD processing
        throw std::runtime_error("VAD processing not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::resetVAD() {
    return Promise<void>::async([]() -> void {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_vad_component_create(&handle);
        if (result == RAC_SUCCESS && handle) {
            rac_vad_component_reset(handle);
        }
    });
}

// ============================================================================
// Voice Agent Capability (Backend-Agnostic)
// Calls rac_voice_agent_* APIs - requires STT, LLM, and TTS backends
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgent(
    const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() -> bool {
        LOGI("Initializing voice agent...");

        // TODO: Implement voice agent initialization
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgentWithLoadedModels() {
    return Promise<bool>::async([this]() -> bool {
        LOGI("Initializing voice agent with loaded models...");

        // TODO: Implement voice agent initialization
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVoiceAgentReady() {
    return Promise<bool>::async([]() -> bool {
        return false;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getVoiceAgentComponentStates() {
    return Promise<std::string>::async([]() -> std::string {
        return "{}";
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVoiceTurn(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentTranscribe(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentGenerateResponse(
    const std::string& prompt) {
    return Promise<std::string>::async([this, prompt]() -> std::string {
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentSynthesizeSpeech(
    const std::string& text) {
    return Promise<std::string>::async([this, text]() -> std::string {
        throw std::runtime_error("Voice agent not fully implemented in core. Use @runanywhere/onnx.");
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::cleanupVoiceAgent() {
    return Promise<void>::async([]() -> void {
        LOGI("Cleaning up voice agent...");
    });
}

} // namespace margelo::nitro::runanywhere
