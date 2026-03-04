/**
 * @file model_compatibility.cpp
 * @brief Implementation of model compatibility checks
 *
 * C++ implementation. The C API is declared in the header with extern "C".
 * Follows the same pattern as model_paths.cpp, model_registry.cpp, etc.
 */

#include "rac/infrastructure/model_management/rac_model_compatibility.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include <cstring>

// =============================================================================
// COMPATIBILITY CHECK IMPLEMENTATION
// =============================================================================

rac_result_t rac_model_check_compatibility(
    rac_model_registry_handle_t registry_handle,
    const char* model_id,
    int64_t available_ram,
    int64_t available_storage,
    rac_model_compatibility_result_t* out_result) {

    if (!registry_handle || !model_id || !out_result) {
        RAC_LOG_ERROR("ModelCompatibility", "Invalid arguments");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Zero-initialize the result
    std::memset(out_result, 0, sizeof(rac_model_compatibility_result_t));

    // Look up the model in the registry
    rac_model_info_t* model = nullptr;
    rac_result_t result = rac_model_registry_get(registry_handle, model_id, &model);
    
    if (result != RAC_SUCCESS) {
        RAC_LOG_WARNING("ModelCompatibility", 
                        "Failed to get model from registry: %s (error: %d)", 
                        model_id, result);
        return result;
    }
    
    if (!model) {
        RAC_LOG_WARNING("ModelCompatibility", "Model not found: %s", model_id);
        return RAC_ERROR_NOT_FOUND;
    }

    // Extract model requirements
    int64_t required_memory = model->memory_required;   // bytes
    int64_t required_storage = model->download_size;     // bytes

    RAC_LOG_DEBUG("ModelCompatibility", 
                "Model %s requirements: memory=%lld bytes, storage=%lld bytes",
                model_id,
                static_cast<long long>(required_memory),
                static_cast<long long>(required_storage));

    // Determine compatibility
    // can_run:  available RAM >= required memory (or requirement is 0/unknown)
    // can_fit:  available storage >= required storage (or requirement is 0/unknown)
    rac_bool_t can_run = (required_memory <= 0 || available_ram >= required_memory)
                             ? RAC_TRUE : RAC_FALSE;
    rac_bool_t can_fit = (required_storage <= 0 || available_storage >= required_storage)
                             ? RAC_TRUE : RAC_FALSE;

    // Populate result
    out_result->can_run = can_run;
    out_result->can_fit = can_fit;
    out_result->is_compatible = (can_run == RAC_TRUE && can_fit == RAC_TRUE)
                                    ? RAC_TRUE : RAC_FALSE;
    out_result->required_memory = required_memory;
    out_result->available_memory = available_ram;
    out_result->required_storage = required_storage;
    out_result->available_storage = available_storage;

    RAC_LOG_INFO("ModelCompatibility",
                 "Model %s: canRun=%d canFit=%d isCompatible=%d "
                 "(RAM: %lld/%lld, Storage: %lld/%lld)",
                 model_id,
                 can_run, can_fit, out_result->is_compatible,
                 static_cast<long long>(available_ram), 
                 static_cast<long long>(required_memory),
                 static_cast<long long>(available_storage), 
                 static_cast<long long>(required_storage));

    // Free the model info (allocated by rac_model_registry_get)
    rac_model_info_free(model);

    return RAC_SUCCESS;
}