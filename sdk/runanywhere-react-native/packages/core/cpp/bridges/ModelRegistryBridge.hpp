/**
 * @file ModelRegistryBridge.hpp
 * @brief C++ bridge for model registry operations.
 *
 * Mirrors Swift's CppBridge+ModelRegistry.swift pattern:
 * - Handle-based API via rac_model_registry_*
 * - Model management and queries
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

#pragma once

#include <string>
#include <vector>
#include <optional>
#include <cstdint>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace runanywhere {
namespace bridges {

/**
 * Model info wrapper for C++ use
 */
struct ModelInfo {
    std::string id;
    std::string name;
    std::string description;
    rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
    rac_model_format_t format = RAC_MODEL_FORMAT_UNKNOWN;
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    std::string downloadUrl;
    std::string localPath;
    int64_t downloadSize = 0;
    int64_t memoryRequired = 0;
    int32_t contextLength = 0;
    bool supportsThinking = false;
    std::vector<std::string> tags;
    rac_model_source_t source = RAC_MODEL_SOURCE_REMOTE;
    bool isDownloaded = false;
};

/**
 * Model filter criteria
 */
struct ModelFilter {
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    rac_model_format_t format = RAC_MODEL_FORMAT_UNKNOWN;
    rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
    int64_t maxSize = 0;
    std::string searchQuery;
};

/**
 * ModelRegistryBridge - Model registry via rac_model_registry_* API
 *
 * Mirrors Swift's CppBridge.ModelRegistry pattern:
 * - Handle-based API
 * - Model CRUD operations
 * - Query and filtering
 */
class ModelRegistryBridge {
public:
    /**
     * Get shared instance
     */
    static ModelRegistryBridge& shared();

    /**
     * Initialize the model registry
     */
    rac_result_t initialize();

    /**
     * Shutdown and cleanup
     */
    void shutdown();

    /**
     * Check if initialized
     */
    bool isInitialized() const { return handle_ != nullptr; }

    /**
     * Get the underlying handle (for use by other bridges)
     */
    rac_model_registry_handle_t getHandle() const { return handle_; }

    // =========================================================================
    // Model CRUD Operations
    // =========================================================================

    /**
     * Add a model to the registry
     */
    rac_result_t addModel(const ModelInfo& model);

    /**
     * Remove a model from the registry
     */
    rac_result_t removeModel(const std::string& modelId);

    /**
     * Update model local path after download
     */
    rac_result_t updateModelPath(const std::string& modelId, const std::string& localPath);

    // =========================================================================
    // Model Queries
    // =========================================================================

    /**
     * Get a model by ID
     */
    std::optional<ModelInfo> getModel(const std::string& modelId);

    /**
     * Get all models
     */
    std::vector<ModelInfo> getAllModels();

    /**
     * Get models filtered by criteria
     */
    std::vector<ModelInfo> getModels(const ModelFilter& filter);

    /**
     * Get models by framework
     */
    std::vector<ModelInfo> getModelsByFramework(rac_inference_framework_t framework);

    /**
     * Get downloaded models
     */
    std::vector<ModelInfo> getDownloadedModels();

    /**
     * Check if a model exists
     */
    bool modelExists(const std::string& modelId);

    /**
     * Check if a model is downloaded
     */
    bool isModelDownloaded(const std::string& modelId);

    /**
     * Get model path if downloaded
     */
    std::optional<std::string> getModelPath(const std::string& modelId);

    /**
     * Get model count
     */
    size_t getModelCount();

private:
    ModelRegistryBridge() = default;
    ~ModelRegistryBridge();
    ModelRegistryBridge(const ModelRegistryBridge&) = delete;
    ModelRegistryBridge& operator=(const ModelRegistryBridge&) = delete;

    // Convert C model info to C++ wrapper
    static ModelInfo fromRac(const rac_model_info_t& cModel);

    // Convert C++ wrapper to C model info
    static void toRac(const ModelInfo& model, rac_model_info_t& cModel);

    rac_model_registry_handle_t handle_ = nullptr;
};

} // namespace bridges
} // namespace runanywhere
