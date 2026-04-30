/**
 * HybridRunAnywhereCore+Storage.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Storage
// ============================================================================
// Storage
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getStorageInfo() {
    return Promise<std::string>::async([]() {
        // Accurate device + app storage comes from FileManagerBridge (POSIX).
        // Always works once initialize() has been called.
        auto fmInfo = FileManagerBridge::shared().getStorageInfo();

        // Model count is a best-effort lookup from the registry. If the registry
        // isn't initialized yet (e.g. SDK.initialize() hasn't finished), fall
        // back to 0 rather than failing the whole call — device storage still
        // needs to render in the UI.
        size_t modelCount = 0;
        try {
            auto registryHandle = ModelRegistryBridge::shared().getHandle();
            if (registryHandle != nullptr) {
                auto storageInfo = StorageBridge::shared().analyzeStorage(registryHandle);
                modelCount = storageInfo.models.size();
            }
        } catch (...) {
            // Registry unavailable — device storage still returned below.
        }

        return buildJsonObject({
            {"totalDeviceSpace", std::to_string(fmInfo.device_total)},
            {"freeDeviceSpace", std::to_string(fmInfo.device_free)},
            {"usedDeviceSpace", std::to_string(fmInfo.device_total - fmInfo.device_free)},
            {"documentsSize", std::to_string(fmInfo.models_size)},
            {"cacheSize", std::to_string(fmInfo.cache_size)},
            {"appSupportSize", std::to_string(fmInfo.temp_size)},
            {"totalAppSize", std::to_string(fmInfo.total_app_size)},
            {"totalModelsSize", std::to_string(fmInfo.models_size)},
            {"modelCount", std::to_string(modelCount)}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::clearCache() {
    return Promise<bool>::async([]() {
        LOGI("Clearing cache...");

        // Clear the model assignment cache (in-memory cache for model assignments)
        rac_model_assignment_clear_cache();

        // Clear file cache and temp directories via C++ file manager
        FileManagerBridge::shared().clearCache();
        FileManagerBridge::shared().clearTemp();

        LOGI("Cache cleared successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::deleteModel(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() {
        LOGI("Deleting model: %s", modelId.c_str());

        // Get framework from registry before removing, so we can delete files
        auto modelInfo = ModelRegistryBridge::shared().getModel(modelId);
        int framework = modelInfo ? static_cast<int>(modelInfo->framework) : -1;

        // Remove from registry
        rac_result_t result = ModelRegistryBridge::shared().removeModel(modelId);

        // Delete files from disk
        if (framework >= 0) {
            FileManagerBridge::shared().deleteModel(modelId, framework);
        }

        return result == RAC_SUCCESS;
    });
}

} // namespace margelo::nitro::runanywhere
