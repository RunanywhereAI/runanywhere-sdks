/**
 * @file CompatibilityBridge.hpp
 * @brief C++ bridge for model compatibility checks.
 *
 * Uses DeviceBridge and StorageBridge to query device capabilities,
 * then calls rac_model_check_compatibility() from runanywhere-commons.
 */

#pragma once

#include <string>
#include <cstdint>

#include "rac_types.h"
#include "rac_model_compatibility.h"
#include "rac_model_registry.h"

namespace runanywhere {
namespace bridges {

/**
 * Compatibility result wrapper
 */
struct CompatibilityResult {
    bool isCompatible = false;
    bool canRun = false;
    bool canFit = false;
    int64_t requiredMemory = 0;
    int64_t availableMemory = 0;
    int64_t requiredStorage = 0;
    int64_t availableStorage = 0;
};

/**
 * CompatibilityBridge - Model compatibility checks
 *
 * Queries device capabilities via DeviceBridge and StorageBridge,
 * then delegates to rac_model_check_compatibility() in runanywhere-commons.
 */
class CompatibilityBridge {
public:
    /**
     * Check model compatibility against current device resources
     *
     * Automatically queries available RAM and storage via existing bridges.
     *
     * @param modelId  Model identifier
     * @param registryHandle  Model registry handle
     * @return CompatibilityResult with canRun, canFit, isCompatible
     */
    static CompatibilityResult checkCompatibility(
        const std::string& modelId,
        rac_model_registry_handle_t registryHandle
    );
};

} // namespace bridges
} // namespace runanywhere