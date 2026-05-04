/**
 * HybridRunAnywhereCore+AuthDevice.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "bridges/ExternalConfigGuard.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Authentication and Device Registration
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

namespace {

// Shared helper: POST a JSON payload to `baseURL + endpoint` using the
// libcurl-backed client and return the response body. Throws on transport or
// non-2xx failure so the surrounding Promise rejects cleanly.
std::string postJsonNative(
    const std::string& baseURL,
    const std::string& endpoint,
    const std::string& bodyJson
) {
    if (!config::isUsableHttpUrl(baseURL)) {
        throw std::runtime_error("No usable external config");
    }

    std::string url = config::appendEndpointPath(config::trim(baseURL), endpoint);

    std::vector<std::pair<std::string, std::string>> headers = {
        {"Content-Type", "application/json"},
        {"Accept", "application/json"},
    };

    NativeHttpResult resp = performNativeHttpRequest(
        "POST", url, headers, bodyJson, /*timeoutMs=*/30000);

    if (resp.status < 200 || resp.status >= 300) {
        throw std::runtime_error(
            "HTTP " + std::to_string(resp.status) + " from " + url + ": " + resp.body);
    }
    return resp.body;
}

} // anonymous namespace

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::authAuthenticate(
    const std::string& apiKey,
    const std::string& baseURL,
    const std::string& deviceId,
    const std::string& platform,
    const std::string& sdkVersion) {
    return Promise<std::string>::async([this, apiKey, baseURL, deviceId, platform, sdkVersion]() -> std::string {
        LOGI("authAuthenticate -> %s (device=%s, platform=%s)",
             baseURL.c_str(), deviceId.c_str(), platform.c_str());

        if (!config::isUsableHttpUrl(baseURL) || !config::isUsableSecret(apiKey)) {
            setLastError("authAuthenticate skipped: no usable external config");
            throw std::runtime_error("No usable external config");
        }

        std::string requestJson = AuthBridge::shared().buildAuthenticateRequestJSON(
            apiKey, deviceId, platform, sdkVersion);
        if (requestJson.empty()) {
            setLastError("Failed to build auth request");
            throw std::runtime_error("Failed to build auth request");
        }

        std::string responseBody;
        try {
            responseBody = postJsonNative(baseURL, "/api/v1/auth/sdk/authenticate", requestJson);
        } catch (const std::exception& e) {
            setLastError(std::string("authAuthenticate transport error: ") + e.what());
            throw;
        }

        AuthResponse parsed = AuthBridge::shared().handleAuthResponse(responseBody);
        if (!parsed.success) {
            std::string msg = "authAuthenticate: backend rejected auth: " + parsed.error;
            setLastError(msg);
            throw std::runtime_error(msg);
        }
        AuthBridge::shared().setAuth(parsed);
        LOGI("authAuthenticate: tokens stored (expires_in=%lld)",
             static_cast<long long>(parsed.expiresIn));
        return responseBody;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::authRefreshToken(
    const std::string& baseURL) {
    return Promise<std::string>::async([this, baseURL]() -> std::string {
        std::string refresh = AuthBridge::shared().getRefreshToken();
        if (refresh.empty()) {
            throw std::runtime_error("authRefreshToken: no refresh token stored");
        }
        if (!config::isUsableHttpUrl(baseURL) || !config::isUsableSecret(refresh)) {
            setLastError("authRefreshToken skipped: no usable external config");
            throw std::runtime_error("No usable external config");
        }

        std::string deviceId = InitBridge::shared().getPersistentDeviceUUID();
        std::string requestJson = AuthBridge::shared().buildRefreshRequestJSON(refresh, deviceId);

        std::string responseBody;
        try {
            responseBody = postJsonNative(baseURL, "/api/v1/auth/sdk/refresh", requestJson);
        } catch (const std::exception& e) {
            setLastError(std::string("authRefreshToken transport error: ") + e.what());
            throw;
        }

        AuthResponse parsed = AuthBridge::shared().handleAuthResponse(responseBody);
        if (!parsed.success) {
            std::string msg = "authRefreshToken: backend rejected refresh: " + parsed.error;
            setLastError(msg);
            throw std::runtime_error(msg);
        }
        AuthBridge::shared().setAuth(parsed);
        LOGI("authRefreshToken: refreshed tokens (expires_in=%lld)",
             static_cast<long long>(parsed.expiresIn));
        return responseBody;
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

        // For development mode, get build token from C++ dev config if not provided
        // This matches Swift's CppBridge.DevConfig.buildToken behavior
        if (buildToken.empty() && env == RAC_ENV_DEVELOPMENT) {
            const char* devBuildToken = rac_dev_config_get_build_token();
            if (devBuildToken && config::isUsableSecret(devBuildToken)) {
                buildToken = devBuildToken;
                LOGD("Using build token from dev config");
            }
        }

        if (env == RAC_ENV_DEVELOPMENT) {
            auto supabaseConfig = config::makeEndpointConfig(
                rac_dev_config_get_supabase_url() ? rac_dev_config_get_supabase_url() : "",
                rac_dev_config_get_supabase_key() ? rac_dev_config_get_supabase_key() : "");

            if (!supabaseConfig.usable || !config::isUsableSecret(buildToken)) {
                LOGI("Skipping telemetry/device registration: no usable config");
                return true;
            }
        } else {
            const std::string baseURL = InitBridge::shared().getBaseURL();
            const std::string accessToken = AuthBridge::shared().getAccessToken();
            const std::string apiKey = InitBridge::shared().getApiKey();
            const bool hasUsableAuthToken =
                config::isUsableSecret(accessToken) || config::isUsableSecret(apiKey);

            if (!config::isUsableHttpUrl(baseURL) ||
                !hasUsableAuthToken ||
                !config::isUsableSecret(buildToken)) {
                LOGI("Skipping telemetry/device registration: no usable config");
                return true;
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
        // Uses shared native C++ HTTP transport (rac_http_client_*).
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
                auto supabaseConfig = config::makeEndpointConfig(
                    rac_dev_config_get_supabase_url() ? rac_dev_config_get_supabase_url() : "",
                    rac_dev_config_get_supabase_key() ? rac_dev_config_get_supabase_key() : "");

                if (!supabaseConfig.usable) {
                    LOGI("Skipping telemetry/device registration: no usable config");
                    return {true, 204, "{}", ""};
                }

                baseURL = supabaseConfig.baseURL;
                apiKey = supabaseConfig.token;
                LOGD("Using configured development Supabase endpoint");
            } else {
                // Production/Staging: Use configured Railway URL
                // These come from SDK initialization (App.tsx -> RunAnywhere.initialize)
                baseURL = config::trim(InitBridge::shared().getBaseURL());

                // For production mode, prefer JWT access token (from authentication)
                // over raw API key. This matches Swift/Kotlin behavior.
                std::string accessToken = AuthBridge::shared().getAccessToken();
                if (config::isUsableSecret(accessToken)) {
                    apiKey = accessToken;  // Use JWT for Authorization header
                    LOGD("Using JWT access token for device registration");
                } else {
                    // Fallback to API key if not authenticated yet
                    apiKey = config::trim(InitBridge::shared().getApiKey());
                    LOGD("Using API key for device registration (not authenticated)");
                }

                if (!config::isUsableHttpUrl(baseURL) || !config::isUsableSecret(apiKey)) {
                    LOGI("Skipping telemetry/device registration: no usable config");
                    return {true, 204, "{}", ""};
                }

                LOGD("Using configured production/staging endpoint");
            }

            std::string fullURL = config::appendEndpointPath(baseURL, endpoint);
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

} // namespace margelo::nitro::runanywhere
