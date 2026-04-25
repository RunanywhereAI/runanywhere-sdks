/**
 * @file CompatibilityBridge.hpp
 * @brief C++ bridge for model compatibility checks.
 *
 */

#pragma once

#include <string>
#include <cstdint>

#include "rac/infrastructure/model_management/rac_model_compatibility.h"

namespace runanywhere {
namespace bridges {

/**
 * Compatibility result wrapper
 */
struct CompatibilityResult {
    bool isCompatible = true;   // Default permissive — function not yet in librac_commons
    bool canRun = true;
    bool canFit = true;
    int64_t requiredMemory = 0;
    int64_t availableMemory = 0;
    int64_t requiredStorage = 0;
    int64_t availableStorage = 0;
};

/**
 * CompatibilityBridge - Model compatibility checks
 */
class CompatibilityBridge {
public:
    static CompatibilityResult checkCompatibility(
        const std::string& modelId,
        rac_model_registry_handle_t registryHandle
    );
};

} // namespace bridges
} // namespace runanywhere
