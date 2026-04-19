/**
 * @file CompatibilityBridge.hpp
 * @brief C++ bridge for model compatibility checks.
 *
 * NOTE: Stub implementation — rac_model_check_compatibility() not yet in librac_commons.so.
 * Returns permissive result (always compatible) until the library is updated.
 */

#pragma once

#include <string>
#include <cstdint>

// rac_model_registry_handle_t is defined in rac_model_registry.h.
// In a stub context where the header may not be on the search path,
// fall back to void* — the real type is struct rac_model_registry*.
// (ModelRegistryBridge.hpp includes rac_model_registry.h first in practice.)
#ifdef RAC_MODEL_REGISTRY_H
// Already included via ModelRegistryBridge.hpp — type is already defined
#else
typedef void* rac_model_registry_handle_t;
#endif

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
 * CompatibilityBridge - Model compatibility checks (stub)
 */
class CompatibilityBridge {
public:
    static CompatibilityResult checkCompatibility(
        const std::string& /*modelId*/,
        rac_model_registry_handle_t /*registryHandle*/
    ) {
        // Stub: rac_model_check_compatibility not yet available in librac_commons.so
        return CompatibilityResult{};
    }
};

} // namespace bridges
} // namespace runanywhere