/**
 * @file ModelRegistryBridge.cpp
 * @brief Model registry bridge implementation
 */

#include "ModelRegistryBridge.hpp"

namespace runanywhere {
namespace bridges {

ModelRegistryBridge& ModelRegistryBridge::shared() {
    static ModelRegistryBridge instance;
    return instance;
}

rac_result_t ModelRegistryBridge::save(const ModelInfo& model) {
#ifdef HAS_RACOMMONS
    rac_model_registry_t* registry = rac_get_model_registry();
    if (!registry) {
        return -1;
    }

    rac_model_info_t info = {};
    info.id = model.id.c_str();
    info.name = model.name.c_str();
    info.path = model.path.c_str();
    info.capability = model.capability.c_str();
    info.framework = model.framework.c_str();
    info.size_bytes = model.sizeBytes;
    info.is_downloaded = model.isDownloaded ? RAC_TRUE : RAC_FALSE;

    return rac_model_registry_save(registry, &info);
#else
    return RAC_SUCCESS;
#endif
}

ModelInfo ModelRegistryBridge::get(const std::string& modelId) {
    ModelInfo result;
    result.id = modelId;

#ifdef HAS_RACOMMONS
    rac_model_registry_t* registry = rac_get_model_registry();
    if (!registry) {
        return result;
    }

    rac_model_info_t info = {};
    rac_result_t status = rac_model_registry_get(registry, modelId.c_str(), &info);

    if (status == RAC_SUCCESS) {
        if (info.id) result.id = info.id;
        if (info.name) result.name = info.name;
        if (info.path) result.path = info.path;
        if (info.capability) result.capability = info.capability;
        if (info.framework) result.framework = info.framework;
        result.sizeBytes = info.size_bytes;
        result.isDownloaded = info.is_downloaded == RAC_TRUE;
    }
#endif

    return result;
}

std::vector<ModelInfo> ModelRegistryBridge::getAll() {
    std::vector<ModelInfo> results;

#ifdef HAS_RACOMMONS
    rac_model_registry_t* registry = rac_get_model_registry();
    if (!registry) {
        return results;
    }

    rac_model_info_t* models = nullptr;
    int count = 0;
    rac_result_t status = rac_model_registry_get_all(registry, &models, &count);

    if (status == RAC_SUCCESS && models) {
        for (int i = 0; i < count; i++) {
            ModelInfo info;
            if (models[i].id) info.id = models[i].id;
            if (models[i].name) info.name = models[i].name;
            if (models[i].path) info.path = models[i].path;
            if (models[i].capability) info.capability = models[i].capability;
            if (models[i].framework) info.framework = models[i].framework;
            info.sizeBytes = models[i].size_bytes;
            info.isDownloaded = models[i].is_downloaded == RAC_TRUE;
            results.push_back(info);
        }
        // Free the models array
        rac_model_registry_free_models(models, count);
    }
#endif

    return results;
}

rac_result_t ModelRegistryBridge::remove(const std::string& modelId) {
#ifdef HAS_RACOMMONS
    rac_model_registry_t* registry = rac_get_model_registry();
    if (!registry) {
        return -1;
    }

    return rac_model_registry_remove(registry, modelId.c_str());
#else
    return RAC_SUCCESS;
#endif
}

std::vector<ModelInfo> ModelRegistryBridge::discoverDownloadedModels(const std::string& directory) {
    std::vector<ModelInfo> results;

#ifdef HAS_RACOMMONS
    rac_model_registry_t* registry = rac_get_model_registry();
    if (!registry) {
        return results;
    }

    rac_model_info_t* models = nullptr;
    int count = 0;
    rac_result_t status = rac_model_registry_discover_downloaded(registry, directory.c_str(),
                                                                   &models, &count);

    if (status == RAC_SUCCESS && models) {
        for (int i = 0; i < count; i++) {
            ModelInfo info;
            if (models[i].id) info.id = models[i].id;
            if (models[i].name) info.name = models[i].name;
            if (models[i].path) info.path = models[i].path;
            if (models[i].capability) info.capability = models[i].capability;
            if (models[i].framework) info.framework = models[i].framework;
            info.sizeBytes = models[i].size_bytes;
            info.isDownloaded = true;
            results.push_back(info);
        }
        rac_model_registry_free_models(models, count);
    }
#endif

    return results;
}

} // namespace bridges
} // namespace runanywhere
