/**
 * HybridRunAnywhereCore.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "bridges/ExternalConfigGuard.hpp"

#include <stdexcept>
#include <utility>

// =============================================================================
// Platform HTTP transport registration
//
// On iOS, rn_register_urlsession_transport() installs a URLSession-backed
// rac_http_transport_ops vtable so subsequent rac_http_request_* calls route
// through Apple's URL loading system (system trust store, proxies, HTTP/2,
// ATS) instead of the bundled libcurl.
//
// On Android, registration happens from Kotlin
// (RNHttpTransportBridge.racHttpTransportRegisterOkHttp()) BEFORE the first
// HTTP call. C++ side is a no-op.
//
// Both registrations are idempotent.
// =============================================================================
#if defined(__APPLE__)
extern "C" void rn_register_urlsession_transport(void);
#endif

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Constructor / Destructor
// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhereCore::HybridRunAnywhereCore() : HybridObject(TAG) {
    LOGI("HybridRunAnywhereCore constructor - core module");
}

HybridRunAnywhereCore::~HybridRunAnywhereCore() {
    LOGI("HybridRunAnywhereCore destructor");

    // Nitro may create short-lived HybridObject wrappers while the SDK process
    // remains initialized. Shared bridge state is owned by initialize()/destroy(),
    // not by an individual wrapper's C++ destructor.
}

// SDK Lifecycle
// ============================================================================
// SDK Lifecycle
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initialize(
    const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Initializing Core SDK...");

        // 0. Register the platform HTTP transport (URLSession on iOS) BEFORE
        // any rac_http_request_* call fires. This makes HTTP go through the
        // system trust store / proxies / HTTP/2 instead of libcurl.
        //
        // Idempotent: subsequent calls are no-ops. Android's OkHttp transport
        // is registered separately from Kotlin's RNHttpTransportBridge.
        //
        // Note: if the bundled librac_commons is older than commons v0.2.0
        // (no rac_http_transport_register symbol), this call will fail to
        // link. A rebuild of the bundled natives is required for the
        // transport vtable to take effect.
#if defined(__APPLE__)
        rn_register_urlsession_transport();
#endif

        // Parse config
        std::string apiKey = config::trim(extractStringValue(configJson, "apiKey"));
        std::string baseURL = config::trim(extractStringValue(configJson, "baseURL", "https://api.runanywhere.ai"));
        std::string deviceId = extractStringValue(configJson, "deviceId");
        std::string envStr = extractStringValue(configJson, "environment", "production");
        std::string sdkVersionFromConfig = extractStringValue(configJson, "sdkVersion", "0.2.0");
        std::string platformFromConfig = extractStringValue(configJson, "platform", "react_native");
        std::string buildToken = extractStringValue(configJson, "buildToken", "");
        bool forceRefreshAssignments = extractBoolValue(configJson, "forceRefreshAssignments", false);
        bool flushTelemetry = extractBoolValue(configJson, "flushTelemetry", true);
        bool discoverDownloadedModels = extractBoolValue(configJson, "discoverDownloadedModels", true);
        bool rescanLocalModels = extractBoolValue(configJson, "rescanLocalModels", true);

        // Determine environment (canonical commons rac_environment_t).
        rac_environment_t env = RAC_ENV_PRODUCTION;
        if (envStr == "development") env = RAC_ENV_DEVELOPMENT;
        else if (envStr == "staging") env = RAC_ENV_STAGING;

        InitBridge::shared().setSdkVersion(sdkVersionFromConfig);

        // 1. Initialize core (platform adapter + state)
        rac_result_t result = InitBridge::shared().initialize(
            env,
            apiKey,
            baseURL,
            deviceId,
            platformFromConfig,
            sdkVersionFromConfig,
            buildToken,
            forceRefreshAssignments,
            flushTelemetry,
            discoverDownloadedModels,
            rescanLocalModels);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to initialize SDK core: " + std::to_string(result));
            return false;
        }

        // 2. Set base directory for model paths before model registry/download
        // setup. Match Swift SDK: native Documents on iOS, app filesDir on
        // Android, without relying on a JS-provided documentsPath.
        std::string modelBaseDirectory = config::trim(InitBridge::shared().getDefaultModelBaseDirectory());

        if (!modelBaseDirectory.empty()) {
            result = InitBridge::shared().setBaseDirectory(modelBaseDirectory);
            if (result != RAC_SUCCESS) {
                LOGE("Failed to set base directory: %d", result);
                // Continue - not fatal, but model paths may not work correctly
            }
        } else {
            LOGE("Unable to resolve model base directory - model paths may not work correctly!");
        }

        // 3. Initialize model registry
        result = ModelRegistryBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize model registry: %d", result);
            // Continue - not fatal
        }

        // 4. Initialize file manager bridge (POSIX-based I/O for C++ business logic)
        FileManagerBridge::shared().initialize();
        FileManagerBridge::shared().createDirectoryStructure();

        // 4b. Initialize storage analyzer with platform file callbacks.
        // Storage aggregation stays in commons; RN only supplies filesystem
        // primitives through the C++ FileManagerBridge.
        {
            StoragePlatformCallbacks storageCallbacks;
            storageCallbacks.calculateDirSize = [](const std::string& path) -> int64_t {
                return FileManagerBridge::shared().calculateDirectorySize(path);
            };
            storageCallbacks.getFileSize = [](const std::string& path) -> int64_t {
                const auto* callbacks = FileManagerBridge::shared().getCallbacks();
                if (!callbacks || !callbacks->get_file_size) return -1;
                return callbacks->get_file_size(path.c_str(), callbacks->user_data);
            };
            storageCallbacks.pathExists = [](const std::string& path) -> std::pair<bool, bool> {
                const auto* callbacks = FileManagerBridge::shared().getCallbacks();
                if (!callbacks || !callbacks->path_exists) return {false, false};
                rac_bool_t isDirectory = RAC_FALSE;
                bool exists = callbacks->path_exists(
                    path.c_str(),
                    &isDirectory,
                    callbacks->user_data) == RAC_TRUE;
                return {exists, isDirectory == RAC_TRUE};
            };
            storageCallbacks.getAvailableSpace = []() -> int64_t {
                const auto* callbacks = FileManagerBridge::shared().getCallbacks();
                if (!callbacks || !callbacks->get_available_space) return 0;
                return callbacks->get_available_space(callbacks->user_data);
            };
            storageCallbacks.getTotalSpace = []() -> int64_t {
                const auto* callbacks = FileManagerBridge::shared().getCallbacks();
                if (!callbacks || !callbacks->get_total_space) return 0;
                return callbacks->get_total_space(callbacks->user_data);
            };
            StorageBridge::shared().setPlatformCallbacks(storageCallbacks);
        }

        result = StorageBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize storage analyzer: %d", result);
            // Continue - not fatal
        }

        // 5. Configure HTTP only for deployable backend configs. Development
        // mode uses the C++ dev config directly in telemetry/device callbacks.
        if (env != RAC_ENV_DEVELOPMENT &&
            config::isUsableHttpUrl(baseURL) &&
            config::isUsableSecret(apiKey)) {
            HTTPBridge::shared().configure(baseURL, apiKey);
        } else {
            LOGI("HTTPBridge not configured: no usable external config");
        }

        // 7. Initialize telemetry (matches Swift's CppBridge.Telemetry.initialize)
        // This creates the C++ telemetry manager and registers HTTP callback
        {
            std::string persistentDeviceId = InitBridge::shared().getPersistentDeviceUUID();
            std::string deviceModel = InitBridge::shared().getDeviceModel();
            std::string osVersion = InitBridge::shared().getOSVersion();

            if (!persistentDeviceId.empty()) {
                TelemetryBridge::shared().initialize(
                    env,
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

        // 9. Register model-assignment HTTP callback. Commons Phase 2 owns
        // when assignment fetch runs; RN only supplies transport glue.
        {
            rac_assignment_callbacks_t callbacks = {};

            // HTTP GET callback — routes through the registered native HTTP transport.
            // Must be a captureless lambda so it decays to a C function pointer; URL
            // and credentials are read from HTTPBridge::shared() (configured above).
            callbacks.http_get = [](const char* endpoint, rac_bool_t requires_auth,
                                    rac_assignment_http_response_t* out_response, void* /*user_data*/) -> rac_result_t {
                if (!out_response) return RAC_ERROR_NULL_POINTER;

                try {
                    std::string endpointStr = endpoint ? endpoint : "";
                    LOGD("Model assignment HTTP GET: %s", endpointStr.c_str());

                    std::string url = endpointStr;
                    if (url.rfind("http://", 0) != 0 && url.rfind("https://", 0) != 0) {
                        if (HTTPBridge::shared().isConfigured()) {
                            url = HTTPBridge::shared().buildURL(endpointStr);
                        } else {
                            LOGE("Model assignment HTTP GET: HTTPBridge not configured");
                            out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                            out_response->error_message = strdup("HTTPBridge not configured");
                            return RAC_ERROR_HTTP_REQUEST_FAILED;
                        }
                    }

                    std::vector<std::pair<std::string, std::string>> headers;
                    if (requires_auth == RAC_TRUE) {
                        if (auto token = HTTPBridge::shared().getAuthorizationToken()) {
                            headers.emplace_back("Authorization", "Bearer " + *token);
                        }
                    }

                    const auto nativeResult = performNativeHttpRequest("GET", url, headers, "", 30000);
                    if (nativeResult.status >= 200 && nativeResult.status < 300 && !nativeResult.body.empty()) {
                        out_response->result = RAC_SUCCESS;
                        out_response->status_code = nativeResult.status;
                        out_response->response_body = strdup(nativeResult.body.c_str());
                        out_response->response_length = nativeResult.body.length();
                        return RAC_SUCCESS;
                    }

                    out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                    out_response->status_code = nativeResult.status;
                    const std::string errorMsg = nativeResult.body.empty()
                        ? "HTTP request failed"
                        : ("HTTP " + std::to_string(nativeResult.status));
                    out_response->error_message = strdup(errorMsg.c_str());
                    return RAC_ERROR_HTTP_REQUEST_FAILED;
                } catch (const std::exception& e) {
                    LOGE("Model assignment HTTP GET failed: %s", e.what());
                    out_response->result = RAC_ERROR_HTTP_REQUEST_FAILED;
                    out_response->error_message = strdup(e.what());
                    return RAC_ERROR_HTTP_REQUEST_FAILED;
                }
            };

            callbacks.user_data = nullptr;
            callbacks.auto_fetch = RAC_FALSE;

            result = rac_model_assignment_set_callbacks(&callbacks);
            if (result == RAC_SUCCESS) {
                LOGI("Model assignment callbacks registered");
            } else {
                LOGE("Failed to register model assignment callbacks: %d", result);
                // Continue - not fatal, models can be fetched later
            }
        }

        LOGI("Core SDK initialized successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::completeServicesInitialization() {
    return Promise<bool>::async([this]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Completing native services initialization...");
        bool httpConfigured = false;
        rac_result_t result = InitBridge::shared().completeServicesInitialization(httpConfigured);
        if (result != RAC_SUCCESS) {
            setLastError("Failed to complete services initialization: " + std::to_string(result));
            throw std::runtime_error("Failed to complete services initialization: " + std::to_string(result));
        }

        return httpConfigured;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::retryHTTPSetupProto() {
    return Promise<bool>::async([this]() {
        bool httpConfigured = false;
        rac_result_t result = InitBridge::shared().retryHTTPSetup(httpConfigured);
        if (result != RAC_SUCCESS) {
            setLastError("HTTP retry failed: " + std::to_string(result));
            return false;
        }
        // Resolves to has_completed_http_setup || http_configured.
        return httpConfigured;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::destroy() {
    return Promise<void>::async([this]() {
        std::lock_guard<std::mutex> lock(initMutex_);

        LOGI("Destroying Core SDK...");

        // Tear down voice/component globals + the
        // commons lifecycle registry FIRST so any in-flight component
        // callbacks/streams stop referencing soon-to-be-destroyed bridges.
        // Defined in HybridRunAnywhereCore+Voice.cpp.
        resetAllGlobalComponentHandles();

        // Cleanup bridges in reverse-init order.
        TelemetryBridge::shared().shutdown();  // Flush and destroy telemetry first
        FileManagerBridge::shared().shutdown();
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

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhereCore::setLastError(const std::string& error) {
    {
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = error;
    }
    LOGE("%s", error.c_str());
}

} // namespace margelo::nitro::runanywhere
