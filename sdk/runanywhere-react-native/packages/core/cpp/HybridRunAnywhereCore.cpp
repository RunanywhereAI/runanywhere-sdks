/**
 * HybridRunAnywhereCore.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "bridges/ExternalConfigGuard.hpp"

#include <utility>

// =============================================================================
// Platform HTTP transport registration (v2 close-out Phase H6)
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

        // 5. Initialize download manager
        result = DownloadBridge::shared().initialize();
        if (result != RAC_SUCCESS) {
            LOGE("Failed to initialize download manager: %d", result);
            // Continue - not fatal
        }

        // 6. Register for events
        EventBridge::shared().registerForEvents();

        // 7. Configure HTTP only for deployable backend configs. Development
        // mode uses the C++ dev config directly in telemetry/device callbacks.
        if (env != SDKEnvironment::Development &&
            config::isUsableHttpUrl(baseURL) &&
            config::isUsableSecret(apiKey)) {
            HTTPBridge::shared().configure(baseURL, apiKey);
        } else {
            LOGI("HTTPBridge not configured: no usable external config");
        }

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

// Utility Functions
// ============================================================================
// Utility Functions
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getLastError() {
    return Promise<std::string>::async([this]() {
        std::lock_guard<std::mutex> lock(errorMutex_);
        return lastError_;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::extractArchive(
    const std::string& archivePath,
    const std::string& destPath) {
    return Promise<bool>::async([this, archivePath, destPath]() {
        LOGI("extractArchive: %s -> %s", archivePath.c_str(), destPath.c_str());

        // Use native C++ extraction (libarchive) — works on all platforms
        rac_result_t result = rac_extract_archive_native(
            archivePath.c_str(), destPath.c_str(),
            nullptr,  // default options
            nullptr,  // no progress callback
            nullptr,  // no user data
            nullptr   // no result output
        );

        if (result == RAC_SUCCESS) {
            LOGI("Native archive extraction succeeded");
            return true;
        } else {
            LOGE("Native archive extraction failed with code: %d", result);
            setLastError("Archive extraction failed");
            return false;
        }
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
    {
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = error;
    }
    LOGE("%s", error.c_str());
}

} // namespace margelo::nitro::runanywhere
