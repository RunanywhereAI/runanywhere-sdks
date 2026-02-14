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

// RACommons headers
#include "rac_dev_config.h"  // For rac_dev_config_get_build_token

// Core bridges - aligned with actual RACommons API
#include "bridges/InitBridge.hpp"
#include "bridges/DeviceBridge.hpp"
#include "bridges/AuthBridge.hpp"
#include "bridges/StorageBridge.hpp"
#include "bridges/ModelRegistryBridge.hpp"
#include "bridges/EventBridge.hpp"
#include "bridges/HTTPBridge.hpp"
#include "bridges/DownloadBridge.hpp"
#include "bridges/TelemetryBridge.hpp"
#include "bridges/ToolCallingBridge.hpp"

// RACommons C API headers for capability methods
// These are backend-agnostic - they work with any registered backend
#include "rac_core.h"
#include "rac_llm_component.h"
#include "rac_llm_types.h"
#include "rac_llm_structured_output.h"
#include "rac_stt_component.h"
#include "rac_stt_types.h"
#include "rac_tts_component.h"
#include "rac_tts_types.h"
#include "rac_vad_component.h"
#include "rac_vad_types.h"
#include "rac_voice_agent.h"
#include "rac_types.h"
#include "rac_model_assignment.h"

#include <sstream>
#include <chrono>
#include <vector>
#include <mutex>
#include <cstdio>
#include <cstring>

// Platform-specific headers for memory usage
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/task.h>
#endif

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HybridRunAnywhereCore"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf("[HybridRunAnywhereCore] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[HybridRunAnywhereCore WARN] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[HybridRunAnywhereCore ERROR] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[HybridRunAnywhereCore DEBUG] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// ============================================================================
// Base64 Utilities
// ============================================================================

namespace {

static const std::string base64_chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::vector<uint8_t> base64Decode(const std::string& encoded) {
    std::vector<uint8_t> decoded;
    if (encoded.empty()) return decoded;

    int val = 0, valb = -8;
    for (char c : encoded) {
        if (c == '=' || c == '\n' || c == '\r') continue;
        size_t pos = base64_chars.find(c);
        if (pos == std::string::npos) continue;
        val = (val << 6) + static_cast<int>(pos);
        valb += 6;
        if (valb >= 0) {
            decoded.push_back(static_cast<uint8_t>((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    return decoded;
}

std::string base64Encode(const uint8_t* data, size_t len) {
    std::string encoded;
    if (!data || len == 0) return encoded;

    int val = 0, valb = -6;
    for (size_t i = 0; i < len; i++) {
        val = (val << 8) + data[i];
        valb += 8;
        while (valb >= 0) {
            encoded.push_back(base64_chars[(val >> valb) & 0x3F]);
            valb -= 6;
        }
    }
    if (valb > -6) {
        encoded.push_back(base64_chars[((val << 8) >> (valb + 8)) & 0x3F]);
    }
    while (encoded.size() % 4) {
        encoded.push_back('=');
    }
    return encoded;
}

// ============================================================================
// JSON Utilities
// ============================================================================

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

double extractDoubleValue(const std::string& json, const std::string& key, double defaultValue) {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.size()) return defaultValue;
    // Skip if this is a string value (starts with quote)
    if (json[pos] == '"') return defaultValue;
    // Try to parse as double, return default on failure
    try {
        return std::stod(json.substr(pos));
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
#ifdef __APPLE__
    if (framework == "CoreML" || framework == "coreml") return RAC_FRAMEWORK_COREML;
#endif
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
    if (category == "Embedding" || category == "embedding") return RAC_MODEL_CATEGORY_EMBEDDING;
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

    // Cleanup bridges (note: telemetry is NOT shutdown here because it's shared
    // across instances and should persist for the SDK lifetime)
    EventBridge::shared().unregisterFromEvents();
    DownloadBridge::shared().shutdown();
    StorageBridge::shared().shutdown();
    ModelRegistryBridge::shared().shutdown();
    // Note: InitBridge and TelemetryBridge are not shutdown in destructor
    // to allow events to be tracked even after HybridObject instances are destroyed
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
        std::string sdkVersionFromConfig = extractStringValue(configJson, "sdkVersion", "0.2.0");

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

        // Set SDK version from TypeScript SDKConstants (centralized version)
        InitBridge::shared().setSdkVersion(sdkVersionFromConfig);

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

        // 8. Initialize telemetry (matches Swift's CppBridge.Telemetry.initialize)
        // This creates the C++ telemetry manager and registers HTTP callback
        {
            std::string persistentDeviceId = InitBridge::shared().getPersistentDeviceUUID();
            std::string deviceModel = InitBridge::shared().getDeviceModel();
            std::string osVersion = InitBridge::shared().getOSVersion();

            if (!persistentDeviceId.empty()) {
                TelemetryBridge::shared().initialize(
                    env == SDKEnvironment::Development ? RAC_ENV_DEVELOPMENT :
                    env == SDKEnvironment::Staging ? RAC_ENV_STAGING : RAC_ENV_PRODUCTION,
                    persistentDeviceId,
                    deviceModel,
                    osVersion,
                    sdkVersionFromConfig  // Use version from config
                );

                // Register analytics events callback to route events to telemetry
                TelemetryBridge::shared().registerEventsCallback();

                LOGI("Telemetry initialized with device: %s", persistentDeviceId.c_str());
            } else {
                LOGE("Cannot initialize telemetry: device ID unavailable");
            }
        }

        // 9. Initialize model assignments with auto-fetch
        // Set up HTTP GET callback for fetching models from backend
        {
            rac_assignment_callbacks_t callbacks = {};

            // HTTP GET callback - uses HTTPBridge for network requests
            callbacks.http_get = [](const char* endpoint, rac_bool_t requires_auth,
                                    rac_assignment_http_response_t* out_response, void* user_data) -> rac_result_t {
                if (!out_response) return RAC_ERROR_NULL_POINTER;

                try {
                    std::string endpointStr = endpoint ? endpoint : "";
                    LOGD("Model assignment HTTP GET: %s", endpointStr.c_str());

                    // Use HTTPBridge::execute which calls the registered JS executor
                    auto responseOpt = HTTPBridge::shared().execute("GET", endpointStr, "", requires_auth == RAC_TRUE);

                    if (!responseOpt.has_value()) {
                        LOGE("HTTP executor not registered");
                        out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                        out_response->error_message = strdup("HTTP executor not registered");
                        return RAC_ERROR_HTTP_REQUEST_FAILED;
                    }

                    const auto& response = responseOpt.value();
                    if (response.success && !response.body.empty()) {
                        out_response->result = RAC_SUCCESS;
                        out_response->status_code = response.statusCode;
                        out_response->response_body = strdup(response.body.c_str());
                        out_response->response_length = response.body.length();
                        return RAC_SUCCESS;
                    } else {
                        out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                        out_response->status_code = response.statusCode;
                        if (!response.error.empty()) {
                            out_response->error_message = strdup(response.error.c_str());
                        }
                        return RAC_ERROR_HTTP_REQUEST_FAILED;
                    }
                } catch (const std::exception& e) {
                    LOGE("Model assignment HTTP GET failed: %s", e.what());
                    out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                    out_response->error_message = strdup(e.what());
                    return RAC_ERROR_HTTP_REQUEST_FAILED;
                }
            };

            callbacks.user_data = nullptr;
            // Only auto-fetch in staging/production, not development
            bool shouldAutoFetch = (env != SDKEnvironment::Development);
            callbacks.auto_fetch = shouldAutoFetch ? RAC_TRUE : RAC_FALSE;

            result = rac_model_assignment_set_callbacks(&callbacks);
            if (result == RAC_SUCCESS) {
                LOGI("Model assignment callbacks registered (autoFetch: %s)", shouldAutoFetch ? "true" : "false");
            } else {
                LOGE("Failed to register model assignment callbacks: %d", result);
                // Continue - not fatal, models can be fetched later
            }
        }

        LOGI("Core SDK initialized successfully");
        return true;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::destroy() {
    return Promise<void>::async([this]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Destroying Core SDK...");

        // Cleanup in reverse order
        TelemetryBridge::shared().shutdown();  // Flush and destroy telemetry first
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
        // Check if SDK is initialized using the actual InitBridge state
        bool isInitialized = InitBridge::shared().isInitialized();

        std::string status = isInitialized ? "initialized" : "not_initialized";
        std::string name = isInitialized ? "RunAnywhere Core" : "Not initialized";

        return buildJsonObject({
            {"name", jsonString(name)},
            {"status", jsonString(status)},
            {"version", jsonString("0.2.0")},
            {"api", jsonString("rac_*")},
            {"source", jsonString("runanywhere-commons")},
            {"module", jsonString("core")},
            {"initialized", isInitialized ? "true" : "false"}
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
        // Use actual platform (ios/android) as backend only accepts these values
#if defined(__APPLE__)
        std::string platform = "ios";
#elif defined(ANDROID) || defined(__ANDROID__)
        std::string platform = "android";
#else
        std::string platform = "ios"; // Default to ios for unknown platforms
#endif
        // Use centralized SDK version from InitBridge (set from TypeScript SDKConstants)
        std::string sdkVersion = InitBridge::shared().getSdkVersion();

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

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::setAuthTokens(
    const std::string& authResponseJson) {
    return Promise<bool>::async([this, authResponseJson]() -> bool {
        LOGI("Setting auth tokens from JS authentication response...");

        // Parse the auth response
        AuthResponse response = AuthBridge::shared().handleAuthResponse(authResponseJson);

        if (response.success) {
            // IMPORTANT: Actually store the tokens in AuthBridge!
            // handleAuthResponse only parses, setAuth stores them
            AuthBridge::shared().setAuth(response);

            LOGI("Auth tokens set successfully. Token expires in %lld seconds",
                 static_cast<long long>(response.expiresIn));
            LOGD("Access token stored (length=%zu)", response.accessToken.length());
            return true;
        } else {
            LOGE("Failed to set auth tokens: %s", response.error.c_str());
            setLastError("Failed to set auth tokens: " + response.error);
            return false;
        }
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
        std::string supabaseKey = extractStringValue(environmentJson, "supabaseKey", "");

        // For development mode, get build token from C++ dev config if not provided
        // This matches Swift's CppBridge.DevConfig.buildToken behavior
        if (buildToken.empty() && env == RAC_ENV_DEVELOPMENT) {
            const char* devBuildToken = rac_dev_config_get_build_token();
            if (devBuildToken && strlen(devBuildToken) > 0) {
                buildToken = devBuildToken;
                LOGD("Using build token from dev config");
            }
        }

        // Set up platform callbacks (matches Swift's CppBridge.Device.registerCallbacks)
        DevicePlatformCallbacks callbacks;

        // Device info callback - populates all fields needed by backend
        // Matches Swift's CppBridge+Device.swift get_device_info callback
        callbacks.getDeviceInfo = []() -> DeviceInfo {
            DeviceInfo info;

            // Core identification
            info.deviceId = InitBridge::shared().getPersistentDeviceUUID();
            // Use actual platform (ios/android) as backend only accepts these values
#if defined(__APPLE__)
            info.platform = "ios";
#elif defined(ANDROID) || defined(__ANDROID__)
            info.platform = "android";
#else
            info.platform = "ios"; // Default to ios for unknown platforms
#endif
            // Use centralized SDK version from InitBridge (set from TypeScript SDKConstants)
            info.sdkVersion = InitBridge::shared().getSdkVersion();

            // Device hardware info from platform-specific code
            info.deviceModel = InitBridge::shared().getDeviceModel();
            info.deviceName = info.deviceModel; // Use model as name (React Native doesn't expose device name)
            info.osVersion = InitBridge::shared().getOSVersion();
            info.chipName = InitBridge::shared().getChipName();
            info.architecture = InitBridge::shared().getArchitecture();
            info.totalMemory = InitBridge::shared().getTotalMemory();
            info.availableMemory = InitBridge::shared().getAvailableMemory();
            info.coreCount = InitBridge::shared().getCoreCount();

            // Form factor detection (matches Swift SDK: device.userInterfaceIdiom == .pad)
            // Uses platform-specific detection via InitBridge::isTablet()
            bool isTabletDevice = InitBridge::shared().isTablet();
            info.formFactor = isTabletDevice ? "tablet" : "phone";

            // Platform-specific values
            #if defined(__APPLE__)
            info.osName = "iOS";
            info.gpuFamily = InitBridge::shared().getGPUFamily(); // "apple"
            info.hasNeuralEngine = true;
            info.neuralEngineCores = 16; // Modern iPhones have 16 ANE cores
            #elif defined(ANDROID) || defined(__ANDROID__)
            info.osName = "Android";
            info.gpuFamily = InitBridge::shared().getGPUFamily(); // "mali", "adreno", etc.
            info.hasNeuralEngine = false;
            info.neuralEngineCores = 0;
            #else
            info.osName = "Unknown";
            info.gpuFamily = "unknown";
            info.hasNeuralEngine = false;
            info.neuralEngineCores = 0;
            #endif

            // Battery info (not available in React Native easily, use defaults)
            info.batteryLevel = -1.0; // Unknown
            info.batteryState = ""; // Unknown
            info.isLowPowerMode = false;

            // Core distribution (approximate for mobile devices)
            info.performanceCores = info.coreCount > 4 ? 2 : 1;
            info.efficiencyCores = info.coreCount - info.performanceCores;

            return info;
        };

        // Device ID callback
        callbacks.getDeviceId = []() -> std::string {
            return InitBridge::shared().getPersistentDeviceUUID();
        };

        // Check registration status callback
        callbacks.isRegistered = []() -> bool {
            // Check UserDefaults/SharedPrefs for registration status
            std::string value;
            if (InitBridge::shared().secureGet("com.runanywhere.sdk.deviceRegistered", value)) {
                return value == "true";
            }
            return false;
        };

        // Set registration status callback
        callbacks.setRegistered = [](bool registered) {
            InitBridge::shared().secureSet("com.runanywhere.sdk.deviceRegistered",
                                           registered ? "true" : "false");
        };

        // HTTP POST callback - key for device registration!
        // Uses native URLSession (iOS) or HttpURLConnection (Android)
        // All credentials come from C++ dev config (matches Swift's CppBridge.DevConfig)
        callbacks.httpPost = [env](
            const std::string& endpoint,
            const std::string& jsonBody,
            bool requiresAuth
        ) -> std::tuple<bool, int, std::string, std::string> {
            // Build full URL based on environment (matches Swift HTTPService)
            std::string baseURL;
            std::string apiKey;

            if (env == RAC_ENV_DEVELOPMENT) {
                // Development: Use Supabase from C++ dev config (development_config.cpp)
                // NO FALLBACK - credentials must come from C++ config only
                const char* devUrl = rac_dev_config_get_supabase_url();
                const char* devKey = rac_dev_config_get_supabase_key();

                baseURL = devUrl ? devUrl : "";
                apiKey = devKey ? devKey : "";

                if (baseURL.empty()) {
                    LOGW("Development mode but Supabase URL not configured in C++ dev_config");
                } else {
                    LOGD("Using Supabase from dev config: %s", baseURL.c_str());
                }
            } else {
                // Production/Staging: Use configured Railway URL
                // These come from SDK initialization (App.tsx -> RunAnywhere.initialize)
                baseURL = InitBridge::shared().getBaseURL();

                // For production mode, prefer JWT access token (from authentication)
                // over raw API key. This matches Swift/Kotlin behavior.
                std::string accessToken = AuthBridge::shared().getAccessToken();
                if (!accessToken.empty()) {
                    apiKey = accessToken;  // Use JWT for Authorization header
                    LOGD("Using JWT access token for device registration");
                } else {
                    // Fallback to API key if not authenticated yet
                    apiKey = InitBridge::shared().getApiKey();
                    LOGD("Using API key for device registration (not authenticated)");
                }

                // Fallback to default if not configured
                if (baseURL.empty()) {
                    baseURL = "https://api.runanywhere.ai";
                }

                LOGD("Using production config: %s", baseURL.c_str());
            }

            std::string fullURL = baseURL + endpoint;
            LOGI("Device HTTP POST to: %s (env=%d)", fullURL.c_str(), env);

            return InitBridge::shared().httpPostSync(fullURL, jsonBody, apiKey);
        };

        // Set callbacks on DeviceBridge
        DeviceBridge::shared().setPlatformCallbacks(callbacks);

        // Register callbacks with C++
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

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearDeviceRegistration() {
    return Promise<bool>::async([]() -> bool {
        LOGI("Clearing device registration flag for testing...");
        bool success = InitBridge::shared().secureDelete("com.runanywhere.sdk.deviceRegistered");
        if (success) {
            LOGI("Device registration flag cleared successfully");
        } else {
            LOGI("Device registration flag not found (may not exist)");
        }
        return true; // Return true even if key didn't exist
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
                case RAC_MODEL_CATEGORY_IMAGE_GENERATION: categoryStr = "image-generation"; break;
                case RAC_MODEL_CATEGORY_AUDIO: categoryStr = "audio"; break;
                case RAC_MODEL_CATEGORY_MULTIMODAL: categoryStr = "multimodal"; break;
                case RAC_MODEL_CATEGORY_EMBEDDING: categoryStr = "embedding"; break;
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
#ifdef __APPLE__
                case RAC_FRAMEWORK_COREML: frameworkStr = "CoreML"; break;
#endif
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
            case RAC_MODEL_CATEGORY_EMBEDDING: categoryStr = "embedding"; break;
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
#ifdef __APPLE__
            case RAC_FRAMEWORK_COREML: frameworkStr = "CoreML"; break;
#endif
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
        LOGI("Clearing cache...");

        // Clear the model assignment cache (in-memory cache for model assignments)
        rac_model_assignment_clear_cache();

        LOGI("Cache cleared successfully");
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
        double memoryUsageMB = 0.0;

#if defined(__APPLE__)
        // iOS/macOS: Use mach_task_basic_info
        mach_task_basic_info_data_t taskInfo;
        mach_msg_type_number_t infoCount = MACH_TASK_BASIC_INFO_COUNT;

        kern_return_t result = task_info(
            mach_task_self(),
            MACH_TASK_BASIC_INFO,
            reinterpret_cast<task_info_t>(&taskInfo),
            &infoCount
        );

        if (result == KERN_SUCCESS) {
            // resident_size is in bytes, convert to MB
            memoryUsageMB = static_cast<double>(taskInfo.resident_size) / (1024.0 * 1024.0);
        }
#elif defined(__ANDROID__) || defined(ANDROID)
        // Android: Read from /proc/self/status
        FILE* file = fopen("/proc/self/status", "r");
        if (file) {
            char line[128];
            while (fgets(line, sizeof(line), file)) {
                // Look for VmRSS (Resident Set Size)
                if (strncmp(line, "VmRSS:", 6) == 0) {
                    long vmRssKB = 0;
                    sscanf(line + 6, "%ld", &vmRssKB);
                    memoryUsageMB = static_cast<double>(vmRssKB) / 1024.0;
                    break;
                }
            }
            fclose(file);
        }
#endif

        LOGI("Memory usage: %.2f MB", memoryUsageMB);
        return memoryUsageMB;
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
// Uses a global LLM component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global LLM component handle - shared across all instances
static rac_handle_t g_llm_component_handle = nullptr;
static std::mutex g_llm_mutex;

static rac_handle_t getGlobalLLMHandle() {
    std::lock_guard<std::mutex> lock(g_llm_mutex);
    if (g_llm_component_handle == nullptr) {
        rac_result_t result = rac_llm_component_create(&g_llm_component_handle);
        if (result != RAC_SUCCESS) {
            g_llm_component_handle = nullptr;
        }
    }
    return g_llm_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTextModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, configJson]() -> bool {
        LOGI("Loading text model: %s", modelPath.c_str());

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            setLastError("Failed to create LLM component. Is an LLM backend registered?");
            throw std::runtime_error("LLM backend not registered. Install @runanywhere/llamacpp.");
        }

        // Load the model
        rac_result_t result = rac_llm_component_load_model(handle, modelPath.c_str(), modelPath.c_str(), modelPath.c_str());
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
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_llm_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTextModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTextModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        rac_llm_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_llm_mutex);
            g_llm_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, prompt, optionsJson]() -> std::string {
        LOGI("Generating text...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
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
            temperature = static_cast<float>(extractDoubleValue(optionsJson.value(), "temperature", 0.7));
        }

        rac_llm_options_t options = {};
        options.max_tokens = maxTokens;
        options.temperature = temperature;
        options.top_p = 0.9f;

        rac_llm_result_t llmResult = {};
        rac_result_t result = rac_llm_component_generate(handle, prompt.c_str(), &options, &llmResult);

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

// Streaming context for LLM callbacks
struct LLMStreamContext {
    std::function<void(const std::string&, bool)> callback;
    std::string accumulatedText;
    int tokenCount = 0;
    bool hasError = false;
    std::string errorMessage;
    rac_llm_result_t finalResult = {};
};

// Token callback for streaming
static rac_bool_t llmStreamTokenCallback(const char* token, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx || !token) return RAC_FALSE;

    std::string tokenStr(token);
    ctx->accumulatedText += tokenStr;
    ctx->tokenCount++;

    // Call the JS callback with partial text (not final)
    if (ctx->callback) {
        ctx->callback(tokenStr, false);
    }

    return RAC_TRUE; // Continue streaming
}

// Complete callback for streaming
static void llmStreamCompleteCallback(const rac_llm_result_t* result, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx) return;

    if (result) {
        ctx->finalResult = *result;
    }

    // Call callback with final signal
    if (ctx->callback) {
        ctx->callback("", true);
    }
}

// Error callback for streaming
static void llmStreamErrorCallback(rac_result_t errorCode, const char* errorMessage, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx) return;

    ctx->hasError = true;
    ctx->errorMessage = errorMessage ? std::string(errorMessage) : "Unknown streaming error";
    LOGE("LLM streaming error: %d - %s", errorCode, ctx->errorMessage.c_str());
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
    return Promise<std::string>::async([this, prompt, optionsJson, callback]() -> std::string {
        LOGI("Streaming text generation...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Parse options
        rac_llm_options_t options = {};
        options.max_tokens = extractIntValue(optionsJson, "max_tokens", 256);
        options.temperature = static_cast<float>(extractDoubleValue(optionsJson, "temperature", 0.7));
        options.top_p = 0.9f;

        // Create streaming context
        LLMStreamContext ctx;
        ctx.callback = callback;

        // Use proper streaming API
        rac_result_t result = rac_llm_component_generate_stream(
            handle,
            prompt.c_str(),
            &options,
            llmStreamTokenCallback,
            llmStreamCompleteCallback,
            llmStreamErrorCallback,
            &ctx
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Streaming generation failed: " + std::to_string(result));
        }

        if (ctx.hasError) {
            throw std::runtime_error("Streaming error: " + ctx.errorMessage);
        }

        LOGI("Streaming complete: %zu chars, %d tokens", ctx.accumulatedText.size(), ctx.tokenCount);

        return buildJsonObject({
            {"text", jsonString(ctx.accumulatedText)},
            {"tokensUsed", std::to_string(ctx.tokenCount)}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelGeneration() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
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
    return Promise<std::string>::async([this, prompt, schema, optionsJson]() -> std::string {
        LOGI("Generating structured output...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Prepare the prompt with the schema embedded
        rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
        config.json_schema = schema.c_str();
        config.include_schema_in_prompt = RAC_TRUE;

        char* preparedPrompt = nullptr;
        rac_result_t prepResult = rac_structured_output_prepare_prompt(prompt.c_str(), &config, &preparedPrompt);
        if (prepResult != RAC_SUCCESS || !preparedPrompt) {
            throw std::runtime_error("Failed to prepare structured output prompt");
        }

        // Generate with the prepared prompt
        rac_llm_options_t options = {};
        if (optionsJson.has_value()) {
            options.max_tokens = extractIntValue(optionsJson.value(), "max_tokens", 512);
            options.temperature = static_cast<float>(extractDoubleValue(optionsJson.value(), "temperature", 0.7));
        } else {
            options.max_tokens = 512;
            options.temperature = 0.7f;
        }

        rac_llm_result_t llmResult = {};
        rac_result_t result = rac_llm_component_generate(handle, preparedPrompt, &options, &llmResult);

        free(preparedPrompt);

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Text generation failed: " + std::to_string(result));
        }

        std::string generatedText;
        if (llmResult.text) {
            generatedText = std::string(llmResult.text);
        }
        rac_llm_result_free(&llmResult);

        // Extract JSON from the generated text
        char* extractedJson = nullptr;
        rac_result_t extractResult = rac_structured_output_extract_json(generatedText.c_str(), &extractedJson, nullptr);

        if (extractResult == RAC_SUCCESS && extractedJson) {
            std::string jsonOutput = std::string(extractedJson);
            free(extractedJson);
            LOGI("Extracted structured JSON: %s", jsonOutput.substr(0, 100).c_str());
            return jsonOutput;
        }

        // If extraction failed, return the raw text (let the caller handle it)
        LOGI("Could not extract JSON, returning raw: %s", generatedText.substr(0, 100).c_str());
        return generatedText;
    });
}

// ============================================================================
// STT Capability (Backend-Agnostic)
// Calls rac_stt_component_* APIs - works with any registered backend
// Uses a global STT component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global STT component handle - shared across all instances
// This ensures model loading state persists even when HybridRunAnywhereCore instances are recreated
static rac_handle_t g_stt_component_handle = nullptr;
static std::mutex g_stt_mutex;

static rac_handle_t getGlobalSTTHandle() {
    std::lock_guard<std::mutex> lock(g_stt_mutex);
    if (g_stt_component_handle == nullptr) {
        rac_result_t result = rac_stt_component_create(&g_stt_component_handle);
        if (result != RAC_SUCCESS) {
            g_stt_component_handle = nullptr;
        }
    }
    return g_stt_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadSTTModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        try {
            LOGI("Loading STT model: %s", modelPath.c_str());

            if (modelPath.empty()) {
                setLastError("STT model path is empty. Download the model first.");
                return false;
            }

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                setLastError("Failed to create STT component. Is an STT backend registered?");
                return false;
            }

            rac_result_t result = rac_stt_component_load_model(
                handle, modelPath.c_str(), modelPath.c_str(), modelType.c_str());
            if (result != RAC_SUCCESS) {
                setLastError("Failed to load STT model: " + std::to_string(result));
                return false;
            }

            LOGI("STT model loaded successfully");
            return true;
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("loadSTTModel exception: %s", msg.c_str());
            setLastError(msg);
            return false;
        } catch (...) {
            setLastError("STT model load failed (unknown error)");
            return false;
        }
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isSTTModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_stt_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isSTTModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadSTTModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        rac_stt_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_stt_mutex);
            g_stt_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribe(
    const std::string& audioBase64,
    double sampleRate,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, audioBase64, sampleRate, language]() -> std::string {
        try {
            LOGI("Transcribing audio (base64)...");

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                return "{\"error\":\"STT component not available. Is an STT backend registered?\"}";
            }

            if (rac_stt_component_is_loaded(handle) != RAC_TRUE) {
                return "{\"error\":\"No STT model loaded. Call loadSTTModel first.\"}";
            }

            // Decode base64 audio data
            std::vector<uint8_t> audioData = base64Decode(audioBase64);
            if (audioData.empty()) {
                return "{\"error\":\"Failed to decode base64 audio data\"}";
            }

            // Minimum ~0.05s at 16kHz 16-bit to avoid backend crash on tiny input
            if (audioData.size() < 1600) {
                return "{\"text\":\"\",\"confidence\":0.0}";
            }

            LOGI("Decoded %zu bytes of audio data", audioData.size());

            // Set up transcription options
            rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
            options.sample_rate = static_cast<int32_t>(sampleRate > 0 ? sampleRate : 16000);
            options.audio_format = RAC_AUDIO_FORMAT_PCM;
            if (language.has_value() && !language->empty()) {
                options.language = language->c_str();
            }

            // Transcribe
            rac_stt_result_t result = {};
            rac_result_t status = rac_stt_component_transcribe(
                handle,
                audioData.data(),
                audioData.size(),
                &options,
                &result
            );

            if (status != RAC_SUCCESS) {
                rac_stt_result_free(&result);
                return "{\"error\":\"Transcription failed with error code: " + std::to_string(status) + "\"}";
            }

            std::string transcribedText;
            if (result.text) {
                transcribedText = std::string(result.text);
            }
            float confidence = result.confidence;

            rac_stt_result_free(&result);

            LOGI("Transcription result: %s", transcribedText.c_str());
            return "{\"text\":" + jsonString(transcribedText) + ",\"confidence\":" + std::to_string(confidence) + "}";
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("Transcribe exception: %s", msg.c_str());
            return "{\"error\":" + jsonString(msg) + "}";
        } catch (...) {
            return "{\"error\":\"Transcription failed (unknown error)\"}";
        }
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, filePath, language]() -> std::string {
        try {
            LOGI("Transcribing file: %s", filePath.c_str());

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                return "{\"error\":\"STT component not available. Is an STT backend registered?\"}";
            }

            if (rac_stt_component_is_loaded(handle) != RAC_TRUE) {
                return "{\"error\":\"No STT model loaded. Call loadSTTModel first.\"}";
            }

            // Open the file
            FILE* file = fopen(filePath.c_str(), "rb");
            if (!file) {
                return "{\"error\":\"Failed to open audio file. Check that the path is valid.\"}";
            }

            // Get file size
            fseek(file, 0, SEEK_END);
            long fileSize = ftell(file);
            fseek(file, 0, SEEK_SET);

            if (fileSize <= 0) {
                fclose(file);
                return "{\"error\":\"Audio file is empty\"}";
            }

            LOGI("File size: %ld bytes", fileSize);

            // Read the entire file into memory
            std::vector<uint8_t> fileData(static_cast<size_t>(fileSize));
            size_t bytesRead = fread(fileData.data(), 1, static_cast<size_t>(fileSize), file);
            fclose(file);

            if (bytesRead != static_cast<size_t>(fileSize)) {
                return "{\"error\":\"Failed to read audio file completely\"}";
            }

            // Parse WAV header to extract audio data
            const uint8_t* data = fileData.data();
            size_t dataSize = fileData.size();
            int32_t sampleRate = 16000;

            if (dataSize < 44) {
                return "{\"error\":\"File too small to be a valid WAV file\"}";
            }
            if (data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F') {
                return "{\"error\":\"Invalid WAV file: missing RIFF header\"}";
            }
            if (data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
                return "{\"error\":\"Invalid WAV file: missing WAVE format\"}";
            }

            size_t pos = 12;
            size_t audioDataOffset = 0;
            size_t audioDataSize = 0;

            while (pos + 8 < dataSize) {
                char chunkId[5] = {0};
                memcpy(chunkId, &data[pos], 4);
                uint32_t chunkSize = *reinterpret_cast<const uint32_t*>(&data[pos + 4]);

                if (strcmp(chunkId, "fmt ") == 0) {
                    if (pos + 8 + chunkSize <= dataSize && chunkSize >= 16) {
                        sampleRate = *reinterpret_cast<const int32_t*>(&data[pos + 12]);
                        if (sampleRate <= 0 || sampleRate > 48000) sampleRate = 16000;
                        LOGI("WAV sample rate: %d Hz", sampleRate);
                    }
                } else if (strcmp(chunkId, "data") == 0) {
                    audioDataOffset = pos + 8;
                    audioDataSize = chunkSize;
                    LOGI("Found audio data: offset=%zu, size=%zu", audioDataOffset, audioDataSize);
                    break;
                }

                pos += 8 + chunkSize;
                if (chunkSize % 2 != 0) pos++;
            }

            if (audioDataSize == 0 || audioDataOffset + audioDataSize > dataSize) {
                return "{\"error\":\"Could not find valid audio data in WAV file\"}";
            }

            // Minimum ~0.1s at 16kHz 16-bit; avoid empty or tiny buffers
            if (audioDataSize < 3200) {
                return "{\"error\":\"Recording too short to transcribe\"}";
            }

            rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
            options.sample_rate = sampleRate;
            options.audio_format = RAC_AUDIO_FORMAT_PCM;
            if (language.has_value() && !language->empty()) {
                options.language = language->c_str();
            }

            LOGI("Transcribing %zu bytes of audio at %d Hz", audioDataSize, sampleRate);

            rac_stt_result_t result = {};
            rac_result_t status = rac_stt_component_transcribe(
                handle,
                &data[audioDataOffset],
                audioDataSize,
                &options,
                &result
            );

            if (status != RAC_SUCCESS) {
                rac_stt_result_free(&result);
                return "{\"error\":\"Transcription failed with error code: " + std::to_string(status) + "\"}";
            }

            std::string transcribedText;
            if (result.text) {
                transcribedText = std::string(result.text);
            }

            rac_stt_result_free(&result);
            LOGI("Transcription result: %s", transcribedText.c_str());
            return transcribedText;
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("TranscribeFile exception: %s", msg.c_str());
            return "{\"error\":\"" + msg + "\"}";
        } catch (...) {
            return "{\"error\":\"Transcription failed (unknown error)\"}";
        }
    });
}

// ============================================================================
// TTS Capability (Backend-Agnostic)
// Calls rac_tts_component_* APIs - works with any registered backend
// Uses a global TTS component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global TTS component handle - shared across all instances
static rac_handle_t g_tts_component_handle = nullptr;
static std::mutex g_tts_mutex;

static rac_handle_t getGlobalTTSHandle() {
    std::lock_guard<std::mutex> lock(g_tts_mutex);
    if (g_tts_component_handle == nullptr) {
        rac_result_t result = rac_tts_component_create(&g_tts_component_handle);
        if (result != RAC_SUCCESS) {
            g_tts_component_handle = nullptr;
        }
    }
    return g_tts_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTTSModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        LOGI("Loading TTS model: %s", modelPath.c_str());

        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            setLastError("Failed to create TTS component. Is a TTS backend registered?");
            throw std::runtime_error("TTS backend not registered. Install @runanywhere/onnx.");
        }

        // Configure the TTS component first
        rac_tts_config_t config = RAC_TTS_CONFIG_DEFAULT;
        config.model_id = modelPath.c_str();
        rac_result_t result = rac_tts_component_configure(handle, &config);
        if (result != RAC_SUCCESS) {
            LOGE("TTS configure failed: %d", result);
            throw std::runtime_error("Failed to configure TTS: " + std::to_string(result));
        }

        // Extract model ID from path for telemetry
        std::string voiceId = modelPath;
        size_t lastSlash = voiceId.find_last_of('/');
        if (lastSlash != std::string::npos) {
            voiceId = voiceId.substr(lastSlash + 1);
        }

        // Load the voice - this is what actually loads the model files
        result = rac_tts_component_load_voice(handle, modelPath.c_str(), voiceId.c_str(), modelType.c_str());
        if (result != RAC_SUCCESS) {
            LOGE("TTS load_voice failed: %d", result);
            throw std::runtime_error("Failed to load TTS voice: " + std::to_string(result));
        }

        // Verify loading
        bool isLoaded = rac_tts_component_is_loaded(handle) == RAC_TRUE;
        LOGI("TTS model loaded successfully, isLoaded=%s", isLoaded ? "true" : "false");

        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTTSModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_tts_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTTSModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTTSModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        rac_tts_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_tts_mutex);
            g_tts_component_handle = nullptr;
        }
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

        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            throw std::runtime_error("TTS component not available. Is a TTS backend registered?");
        }

        if (rac_tts_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No TTS model loaded. Call loadTTSModel first.");
        }

        // Set up synthesis options
        rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
        if (!voiceId.empty()) {
            options.voice = voiceId.c_str();
        }
        options.rate = static_cast<float>(speedRate > 0 ? speedRate : 1.0);
        options.pitch = static_cast<float>(pitchShift > 0 ? pitchShift : 1.0);

        // Synthesize
        rac_tts_result_t result = {};
        rac_result_t status = rac_tts_component_synthesize(handle, text.c_str(), &options, &result);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("TTS synthesis failed with error code: " + std::to_string(status));
        }

        if (!result.audio_data || result.audio_size == 0) {
            rac_tts_result_free(&result);
            throw std::runtime_error("TTS synthesis returned no audio data");
        }

        LOGI("TTS synthesis complete: %zu bytes, %d Hz, %lld ms",
             result.audio_size, result.sample_rate, result.duration_ms);

        // Convert audio data to base64
        std::string audioBase64 = base64Encode(
            static_cast<const uint8_t*>(result.audio_data),
            result.audio_size
        );

        // Build JSON result with metadata
        std::ostringstream json;
        json << "{";
        json << "\"audioBase64\":\"" << audioBase64 << "\",";
        json << "\"sampleRate\":" << result.sample_rate << ",";
        json << "\"durationMs\":" << result.duration_ms << ",";
        json << "\"audioSize\":" << result.audio_size;
        json << "}";

        rac_tts_result_free(&result);

        return json.str();
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
// Uses a global VAD component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global VAD component handle - shared across all instances
static rac_handle_t g_vad_component_handle = nullptr;
static std::mutex g_vad_mutex;

static rac_handle_t getGlobalVADHandle() {
    std::lock_guard<std::mutex> lock(g_vad_mutex);
    if (g_vad_component_handle == nullptr) {
        rac_result_t result = rac_vad_component_create(&g_vad_component_handle);
        if (result != RAC_SUCCESS) {
            g_vad_component_handle = nullptr;
        }
    }
    return g_vad_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadVADModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath]() -> bool {
        LOGI("Loading VAD model: %s", modelPath.c_str());

        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            setLastError("Failed to create VAD component. Is a VAD backend registered?");
            throw std::runtime_error("VAD backend not registered. Install @runanywhere/onnx.");
        }

        rac_vad_config_t config = RAC_VAD_CONFIG_DEFAULT;
        config.model_id = modelPath.c_str();
        rac_result_t result = rac_vad_component_configure(handle, &config);
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
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_vad_component_is_initialized(handle) == RAC_TRUE;
        LOGD("isVADModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadVADModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        rac_vad_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_vad_mutex);
            g_vad_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVAD(
    const std::string& audioBase64,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, audioBase64, optionsJson]() -> std::string {
        LOGI("Processing VAD...");

        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            throw std::runtime_error("VAD component not available. Is a VAD backend registered?");
        }

        // Decode base64 audio data
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode base64 audio data for VAD");
        }

        // Convert byte data to float samples
        // Assuming 16-bit PCM audio: 2 bytes per sample
        size_t numSamples = audioData.size() / sizeof(int16_t);
        std::vector<float> floatSamples(numSamples);

        const int16_t* pcmData = reinterpret_cast<const int16_t*>(audioData.data());
        for (size_t i = 0; i < numSamples; i++) {
            floatSamples[i] = static_cast<float>(pcmData[i]) / 32768.0f;
        }

        LOGI("VAD processing %zu samples", numSamples);

        // Process with VAD
        rac_bool_t isSpeech = RAC_FALSE;
        rac_result_t status = rac_vad_component_process(
            handle,
            floatSamples.data(),
            numSamples,
            &isSpeech
        );

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("VAD processing failed with error code: " + std::to_string(status));
        }

        // Return JSON result
        std::ostringstream json;
        json << "{";
        json << "\"isSpeech\":" << (isSpeech == RAC_TRUE ? "true" : "false") << ",";
        json << "\"samplesProcessed\":" << numSamples;
        json << "}";

        return json.str();
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::resetVAD() {
    return Promise<void>::async([]() -> void {
        rac_handle_t handle = getGlobalVADHandle();
        if (handle) {
            rac_vad_component_reset(handle);
        }
    });
}

// ============================================================================
// Voice Agent Capability (Backend-Agnostic)
// Calls rac_voice_agent_* APIs - requires STT, LLM, TTS, and VAD backends
// Uses a global voice agent handle that composes the global component handles
// Mirrors Swift SDK's CppBridge.VoiceAgent.shared architecture
// ============================================================================

// Global Voice Agent handle - composes the global STT, LLM, TTS, VAD handles
static rac_voice_agent_handle_t g_voice_agent_handle = nullptr;
static std::mutex g_voice_agent_mutex;

static rac_voice_agent_handle_t getGlobalVoiceAgentHandle() {
    std::lock_guard<std::mutex> lock(g_voice_agent_mutex);
    if (g_voice_agent_handle == nullptr) {
        // Get component handles - required for voice agent
        rac_handle_t llmHandle = getGlobalLLMHandle();
        rac_handle_t sttHandle = getGlobalSTTHandle();
        rac_handle_t ttsHandle = getGlobalTTSHandle();
        rac_handle_t vadHandle = getGlobalVADHandle();

        if (!llmHandle || !sttHandle || !ttsHandle || !vadHandle) {
            // Cannot create voice agent without all components
            return nullptr;
        }

        rac_result_t result = rac_voice_agent_create(
            llmHandle, sttHandle, ttsHandle, vadHandle, &g_voice_agent_handle);
        if (result != RAC_SUCCESS) {
            g_voice_agent_handle = nullptr;
        }
    }
    return g_voice_agent_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgent(
    const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() -> bool {
        LOGI("Initializing voice agent...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent requires STT, LLM, TTS, and VAD backends. "
                                     "Install @runanywhere/llamacpp and @runanywhere/onnx.");
        }

        // Initialize with default config (or parse configJson if needed)
        rac_result_t result = rac_voice_agent_initialize(handle, nullptr);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to initialize voice agent: " + std::to_string(result));
        }

        LOGI("Voice agent initialized");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgentWithLoadedModels() {
    return Promise<bool>::async([this]() -> bool {
        LOGI("Initializing voice agent with loaded models...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent requires STT, LLM, TTS, and VAD backends. "
                                     "Install @runanywhere/llamacpp and @runanywhere/onnx.");
        }

        // Initialize using already-loaded models
        rac_result_t result = rac_voice_agent_initialize_with_loaded_models(handle);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Voice agent requires all models to be loaded. Error: " + std::to_string(result));
        }

        LOGI("Voice agent initialized with loaded models");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVoiceAgentReady() {
    return Promise<bool>::async([]() -> bool {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            return false;
        }

        rac_bool_t isReady = RAC_FALSE;
        rac_result_t result = rac_voice_agent_is_ready(handle, &isReady);
        if (result != RAC_SUCCESS) {
            return false;
        }

        LOGD("isVoiceAgentReady: %s", isReady == RAC_TRUE ? "true" : "false");
        return isReady == RAC_TRUE;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getVoiceAgentComponentStates() {
    return Promise<std::string>::async([]() -> std::string {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();

        // Get component loaded states
        rac_bool_t sttLoaded = RAC_FALSE;
        rac_bool_t llmLoaded = RAC_FALSE;
        rac_bool_t ttsLoaded = RAC_FALSE;

        if (handle) {
            rac_voice_agent_is_stt_loaded(handle, &sttLoaded);
            rac_voice_agent_is_llm_loaded(handle, &llmLoaded);
            rac_voice_agent_is_tts_loaded(handle, &ttsLoaded);
        }

        // Get model IDs if loaded
        const char* sttModelId = handle ? rac_voice_agent_get_stt_model_id(handle) : nullptr;
        const char* llmModelId = handle ? rac_voice_agent_get_llm_model_id(handle) : nullptr;
        const char* ttsVoiceId = handle ? rac_voice_agent_get_tts_voice_id(handle) : nullptr;

        return buildJsonObject({
            {"stt", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", sttLoaded == RAC_TRUE ? "true" : "false"},
                {"modelId", sttModelId ? jsonString(sttModelId) : "null"}
            })},
            {"llm", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", llmLoaded == RAC_TRUE ? "true" : "false"},
                {"modelId", llmModelId ? jsonString(llmModelId) : "null"}
            })},
            {"tts", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", ttsLoaded == RAC_TRUE ? "true" : "false"},
                {"voiceId", ttsVoiceId ? jsonString(ttsVoiceId) : "null"}
            })}
        });
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVoiceTurn(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        LOGI("Processing voice turn...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        // Decode base64 audio
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode audio data");
        }

        rac_voice_agent_result_t result = {};
        rac_result_t status = rac_voice_agent_process_voice_turn(
            handle, audioData.data(), audioData.size(), &result);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Voice turn processing failed: " + std::to_string(status));
        }

        // Build result JSON
        std::string responseJson = buildJsonObject({
            {"speechDetected", result.speech_detected == RAC_TRUE ? "true" : "false"},
            {"transcription", result.transcription ? jsonString(result.transcription) : "\"\""},
            {"response", result.response ? jsonString(result.response) : "\"\""},
            {"audioSize", std::to_string(result.synthesized_audio_size)}
        });

        // Free result resources
        rac_voice_agent_result_free(&result);

        LOGI("Voice turn completed");
        return responseJson;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentTranscribe(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        LOGI("Voice agent transcribing...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        // Decode base64 audio
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode audio data");
        }

        char* transcription = nullptr;
        rac_result_t status = rac_voice_agent_transcribe(
            handle, audioData.data(), audioData.size(), &transcription);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Transcription failed: " + std::to_string(status));
        }

        std::string result = transcription ? transcription : "";
        if (transcription) {
            free(transcription);
        }

        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentGenerateResponse(
    const std::string& prompt) {
    return Promise<std::string>::async([this, prompt]() -> std::string {
        LOGI("Voice agent generating response...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        char* response = nullptr;
        rac_result_t status = rac_voice_agent_generate_response(handle, prompt.c_str(), &response);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Response generation failed: " + std::to_string(status));
        }

        std::string result = response ? response : "";
        if (response) {
            free(response);
        }

        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentSynthesizeSpeech(
    const std::string& text) {
    return Promise<std::string>::async([this, text]() -> std::string {
        LOGI("Voice agent synthesizing speech...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        void* audioData = nullptr;
        size_t audioSize = 0;
        rac_result_t status = rac_voice_agent_synthesize_speech(
            handle, text.c_str(), &audioData, &audioSize);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Speech synthesis failed: " + std::to_string(status));
        }

        // Encode audio to base64
        std::string audioBase64 = base64Encode(static_cast<uint8_t*>(audioData), audioSize);

        if (audioData) {
            free(audioData);
        }

        return audioBase64;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::cleanupVoiceAgent() {
    return Promise<void>::async([]() -> void {
        LOGI("Cleaning up voice agent...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (handle) {
            rac_voice_agent_cleanup(handle);
        }

        // Note: We don't destroy the voice agent handle here - it's reusable
        // The models can be unloaded separately via unloadSTTModel, etc.
    });
}

// ============================================================================
// Secure Storage Methods
// Matches Swift: KeychainManager.swift
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageSet(
    const std::string& key,
    const std::string& value) {
    return Promise<bool>::async([key, value]() -> bool {
        LOGI("Secure storage set: key=%s", key.c_str());

        bool success = InitBridge::shared().secureSet(key, value);
        if (!success) {
            LOGE("Failed to store value for key: %s", key.c_str());
        }
        return success;
    });
}

std::shared_ptr<Promise<std::variant<nitro::NullType, std::string>>> HybridRunAnywhereCore::secureStorageGet(
    const std::string& key) {
    return Promise<std::variant<nitro::NullType, std::string>>::async([key]() -> std::variant<nitro::NullType, std::string> {
        LOGI("Secure storage get: key=%s", key.c_str());

        std::string value;
        if (InitBridge::shared().secureGet(key, value)) {
            return value;
        }
        return nitro::NullType();
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageDelete(
    const std::string& key) {
    return Promise<bool>::async([key]() -> bool {
        LOGI("Secure storage delete: key=%s", key.c_str());

        bool success = InitBridge::shared().secureDelete(key);
        if (!success) {
            LOGE("Failed to delete key: %s", key.c_str());
        }
        return success;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::secureStorageExists(
    const std::string& key) {
    return Promise<bool>::async([key]() -> bool {
        LOGD("Secure storage exists: key=%s", key.c_str());
        return InitBridge::shared().secureExists(key);
    });
}

// Semantic aliases for set/get (forward to actual implementations)
std::shared_ptr<Promise<void>> HybridRunAnywhereCore::secureStorageStore(
    const std::string& key,
    const std::string& value) {
    // Direct implementation (no double-wrapping of promises)
    return Promise<void>::async([key, value]() -> void {
        LOGI("Secure storage store: key=%s", key.c_str());
        bool success = InitBridge::shared().secureSet(key, value);
        if (!success) {
            LOGE("Failed to store value for key: %s", key.c_str());
            throw std::runtime_error("Failed to store value for key: " + key);
        }
    });
}

std::shared_ptr<Promise<std::variant<nitro::NullType, std::string>>> HybridRunAnywhereCore::secureStorageRetrieve(
    const std::string& key) {
    // Direct implementation (reuse exact same logic as secureStorageGet)
    return Promise<std::variant<nitro::NullType, std::string>>::async([key]() -> std::variant<nitro::NullType, std::string> {
        LOGI("Secure storage retrieve: key=%s", key.c_str());
        std::string value;
        if (InitBridge::shared().secureGet(key, value)) {
            return value;
        }
        return nitro::NullType();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getPersistentDeviceUUID() {
    return Promise<std::string>::async([]() -> std::string {
        LOGI("Getting persistent device UUID...");

        std::string uuid = InitBridge::shared().getPersistentDeviceUUID();

        if (uuid.empty()) {
            throw std::runtime_error("Failed to get or generate device UUID");
        }

        LOGI("Persistent device UUID: %s", uuid.c_str());
        return uuid;
    });
}

// ============================================================================
// Telemetry
// Matches Swift: CppBridge+Telemetry.swift
// C++ handles all telemetry logic - batching, JSON building, routing
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::flushTelemetry() {
    return Promise<void>::async([]() -> void {
        LOGI("Flushing telemetry events...");
        TelemetryBridge::shared().flush();
        LOGI("Telemetry flushed");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTelemetryInitialized() {
    return Promise<bool>::async([]() -> bool {
        return TelemetryBridge::shared().isInitialized();
    });
}

// ============================================================================
// Tool Calling
//
// ARCHITECTURE:
// - C++ (ToolCallingBridge): Parses <tool_call> tags from LLM output.
//   This is the SINGLE SOURCE OF TRUTH for parsing, ensuring consistency.
//
// - TypeScript (RunAnywhere+ToolCalling.ts): Handles tool registry, executor
//   storage, prompt formatting, and orchestration. Executors MUST stay in
//   TypeScript because they need JavaScript APIs (fetch, device APIs, etc.).
//
// Only parseToolCallFromOutput is implemented in C++. All other tool calling
// functionality (registration, execution, prompt formatting) is in TypeScript.
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::parseToolCallFromOutput(const std::string& llmOutput) {
    return Promise<std::string>::async([llmOutput]() -> std::string {
        LOGD("parseToolCallFromOutput: input length=%zu", llmOutput.length());

        // TODO: Re-enable when commons includes rac_tool_call_* functions
        // Use ToolCallingBridge for parsing - single source of truth
        // This ensures consistent <tool_call> tag parsing across all platforms
        // return ::runanywhere::bridges::ToolCallingBridge::shared().parseToolCall(llmOutput);
        
        // Temporary stub - return empty JSON for now
        LOGW("parseToolCallFromOutput: ToolCallingBridge disabled, returning empty JSON");
        return "{}";
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::formatToolsForPrompt(
    const std::string& toolsJson,
    const std::string& format
) {
    return Promise<std::string>::async([toolsJson, format]() -> std::string {
        LOGD("formatToolsForPrompt: tools length=%zu, format=%s", toolsJson.length(), format.c_str());

        // TODO: Re-enable when commons includes rac_tool_call_* functions
        // Use C++ single source of truth for prompt formatting
        // This eliminates duplicate TypeScript implementation
        // return ::runanywhere::bridges::ToolCallingBridge::shared().formatToolsPrompt(toolsJson, format);
        
        // Temporary stub - return empty string for now
        LOGW("formatToolsForPrompt: ToolCallingBridge disabled, returning empty string");
        return "";
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::buildInitialPrompt(
    const std::string& userPrompt,
    const std::string& toolsJson,
    const std::string& optionsJson
) {
    return Promise<std::string>::async([userPrompt, toolsJson, optionsJson]() -> std::string {
        LOGD("buildInitialPrompt: prompt length=%zu, tools length=%zu", userPrompt.length(), toolsJson.length());

        // TODO: Re-enable when commons includes rac_tool_call_* functions
        // Use C++ single source of truth for initial prompt building
        // return ::runanywhere::bridges::ToolCallingBridge::shared().buildInitialPrompt(userPrompt, toolsJson, optionsJson);
        
        // Temporary stub - return user prompt as-is
        LOGW("buildInitialPrompt: ToolCallingBridge disabled, returning user prompt");
        return userPrompt;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::buildFollowupPrompt(
    const std::string& originalPrompt,
    const std::string& toolsPrompt,
    const std::string& toolName,
    const std::string& resultJson,
    bool keepToolsAvailable
) {
    return Promise<std::string>::async([originalPrompt, toolsPrompt, toolName, resultJson, keepToolsAvailable]() -> std::string {
        LOGD("buildFollowupPrompt: tool=%s, keepTools=%d", toolName.c_str(), keepToolsAvailable);

        // TODO: Re-enable when commons includes rac_tool_call_* functions
        // Use C++ single source of truth for follow-up prompt building
        // return ::runanywhere::bridges::ToolCallingBridge::shared().buildFollowupPrompt(
        //     originalPrompt, toolsPrompt, toolName, resultJson, keepToolsAvailable);
        
        // Temporary stub - return original prompt
        LOGW("buildFollowupPrompt: ToolCallingBridge disabled, returning original prompt");
        return originalPrompt;
    });
}

} // namespace margelo::nitro::runanywhere
