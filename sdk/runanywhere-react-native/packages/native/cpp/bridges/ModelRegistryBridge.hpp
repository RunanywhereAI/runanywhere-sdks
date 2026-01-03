/**
 * @file ModelRegistryBridge.hpp
 * @brief Model registry bridge for React Native
 *
 * Matches Swift's CppBridge+ModelRegistry.swift pattern, providing:
 * - Model registration and discovery
 * - Model metadata management
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#ifdef HAS_RACOMMONS
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#else
typedef void* rac_handle_t;
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief Model metadata
 */
struct ModelInfo {
    std::string id;
    std::string name;
    std::string path;
    std::string capability; // llm, stt, tts, vad
    std::string framework;  // llamacpp, onnx
    int64_t sizeBytes = 0;
    bool isDownloaded = false;
};

/**
 * @brief Model registry bridge singleton
 *
 * Matches CppBridge+ModelRegistry.swift API.
 */
class ModelRegistryBridge {
public:
    static ModelRegistryBridge& shared();

    // Registry operations
    rac_result_t save(const ModelInfo& model);
    ModelInfo get(const std::string& modelId);
    std::vector<ModelInfo> getAll();
    rac_result_t remove(const std::string& modelId);

    // Discovery
    std::vector<ModelInfo> discoverDownloadedModels(const std::string& directory);

private:
    ModelRegistryBridge() = default;
    ~ModelRegistryBridge() = default;

    // Disable copy/move
    ModelRegistryBridge(const ModelRegistryBridge&) = delete;
    ModelRegistryBridge& operator=(const ModelRegistryBridge&) = delete;
};

} // namespace bridges
} // namespace runanywhere
