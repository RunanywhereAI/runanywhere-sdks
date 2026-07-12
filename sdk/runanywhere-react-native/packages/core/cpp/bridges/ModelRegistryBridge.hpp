/**
 * @file ModelRegistryBridge.hpp
 * @brief C++ bridge for model registry operations.
 *
 * Owns the global registry handle used by the proto-byte bridge domains.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

#pragma once

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

namespace runanywhere {
namespace bridges {

/**
 * ModelRegistryBridge - global registry handle owner.
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

private:
    ModelRegistryBridge() = default;
    ~ModelRegistryBridge();
    ModelRegistryBridge(const ModelRegistryBridge&) = delete;
    ModelRegistryBridge& operator=(const ModelRegistryBridge&) = delete;

    rac_model_registry_handle_t handle_ = nullptr;
};

} // namespace bridges
} // namespace runanywhere
